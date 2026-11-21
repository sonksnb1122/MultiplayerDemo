class_name SkillCaster
extends Node
## Q / W / E skills of one hero (child of Player, named "SkillCaster" on every peer).
##
## Flow (server-authoritative, like the rest of the game):
##   owner presses a key -> request_cast.rpc_id(HOST) with the target under the mouse
##   server checks owner / alive / stun / cooldown / range -> starts the cast on the Player,
##   tells every peer to play the VFX (play_skill_fx), applies the effect on its own timer,
##   and tells the owner the cooldown (cooldown_started).

signal cooldown_started(slot: int, duration: float)
signal cast_failed(slot: int, reason: String)

const ACTIONS := [&"Skill1", &"Skill2", &"Skill3"]
const KEYS := [KEY_Q, KEY_W, KEY_E]
const KEY_LABELS := ["Q", "W", "E"]
## When the mouse is not exactly on an enemy, pick the closest enemy within this distance of the cursor.
const CURSOR_PICK_RADIUS := 4.0
const RANGE_TOLERANCE := 1.0

var player: Player
var skills: Array[SkillData] = []

var _cooldown_left: Array[float] = [0.0, 0.0, 0.0]  # server
var _local_ready_at: Array[float] = [0.0, 0.0, 0.0]  # owner, in seconds (Time.get_ticks_msec / 1000)
var _skill_bar: SkillBar


static func ensure_input_actions() -> void:
	for i in ACTIONS.size():
		if InputMap.has_action(ACTIONS[i]):
			continue
		InputMap.add_action(ACTIONS[i])
		var ev := InputEventKey.new()
		ev.physical_keycode = KEYS[i]
		InputMap.action_add_event(ACTIONS[i], ev)


func _ready() -> void:
	player = get_parent() as Player
	skills = SkillDB.get_skills(player.character_data.id)
	# Load the scenes now so the first cast doesn't hitch.
	for skill in skills:
		SkillVfx.load_scene(skill.vfx_scene)
		SkillVfx.load_scene(skill.projectile_model)
	if NetworkManager.is_mine(player.peer_id):
		ensure_input_actions()
		_create_skill_bar.call_deferred()


func _create_skill_bar() -> void:
	if player.player_HUD == null:
		return
	_skill_bar = SkillBar.new()
	var area: Control = player.player_HUD.get_skill_area()
	if area != null:
		area.add_child(_skill_bar)  # under the hp bar, inside the hero panel
	else:
		player.player_HUD.add_child(_skill_bar)
	_skill_bar.setup(self)


# ---------------------------------------------------------------- owner input

func _unhandled_input(event: InputEvent) -> void:
	if not NetworkManager.is_mine(player.peer_id):
		return
	if not player.hero_spawner.is_game_started() or PauseMenu.is_open or MatchManager.is_over:
		return
	for i in mini(ACTIONS.size(), skills.size()):
		if event.is_action_pressed(ACTIONS[i]):
			get_viewport().set_input_as_handled()
			try_cast(i)
			return


func try_cast(slot: int) -> void:
	if slot < 0 or slot >= skills.size():
		return
	if local_cooldown_left(slot) > 0.0:
		cast_failed.emit(slot, "Cooldown")
		return
	var skill := skills[slot]
	var hit := player.mouse_raycast()
	var point: Vector3 = hit.get("position", player.global_position)
	var target_peer := -1
	if skill.is_targeted():
		var target := _pick_target(hit, point, skill)
		if target == null:
			cast_failed.emit(slot, "No target")
			return
		target_peer = target.peer_id
	request_cast.rpc_id(GameDefines.HOST_ID, slot, target_peer, point)


func local_cooldown_left(slot: int) -> float:
	return maxf(_local_ready_at[slot] - Time.get_ticks_msec() / 1000.0, 0.0)


func _pick_target(hit: Dictionary, point: Vector3, skill: SkillData) -> Player:
	var collider = hit.get("collider")
	if collider is Player and player.is_enemy(collider) and not collider.is_dead():
		return collider
	# Closest enemy to the cursor, then closest enemy in range of the hero.
	var best: Player = null
	var best_dist := CURSOR_PICK_RADIUS
	for other in _enemies():
		var d := _flat_distance(other.global_position, point)
		if d <= best_dist:
			best = other
			best_dist = d
	if best != null:
		return best
	best_dist = skill.cast_range
	for other in _enemies():
		var d := _flat_distance(other.global_position, player.global_position)
		if d <= best_dist:
			best = other
			best_dist = d
	return best


# ---------------------------------------------------------------- server

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for i in _cooldown_left.size():
		if _cooldown_left[i] > 0.0:
			_cooldown_left[i] = maxf(_cooldown_left[i] - delta, 0.0)


@rpc("any_peer", "call_local", "reliable")
func request_cast(slot: int, target_peer: int, aim_point: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != player.peer_id:
		push_warning("request_cast rejected: peer %d tried to cast for peer %d" % [sender, player.peer_id])
		return
	if slot < 0 or slot >= skills.size() or MatchManager.is_over:
		return
	var skill := skills[slot]
	if _cooldown_left[slot] > 0.0:
		_fail(slot, "Cooldown")
		return
	if not player.can_cast():
		_fail(slot, "Can't cast now")
		return

	var target: Player = null
	if skill.is_targeted():
		target = player.hero_spawner.get_player(target_peer) as Player
		if target == null or not player.is_enemy(target) or target.is_dead():
			_fail(slot, "No target")
			return
		if _flat_distance(target.global_position, player.global_position) > skill.cast_range + RANGE_TOLERANCE:
			_fail(slot, "Out of range")
			return

	match skill.kind:
		SkillData.Kind.PROJECTILE:
			_cast_projectile(slot, skill, target)
		SkillData.Kind.AREA_AT_TARGET:
			_cast_area_at_target(slot, skill, target)
		SkillData.Kind.AREA_IN_FRONT:
			if target != null:
				aim_point = target.global_position  # aim at the required target
			_cast_area_in_front(slot, skill, aim_point)
		SkillData.Kind.SELF_BUFF:
			_cast_self_buff(skill)

	_cooldown_left[slot] = skill.cooldown
	cooldown_started_rpc.rpc_id(player.peer_id, slot, skill.cooldown)


func _cast_projectile(slot: int, skill: SkillData, target: Player) -> void:
	player.begin_cast(skill.cast_time, target.global_position)
	var height := Vector3(0, skill.projectile_height, 0)
	var dist := (target.global_position - player.global_position).length()
	# A prop in the way stops the projectile there: the skill is spent, nothing is hit
	var block := player.shot_block_point(target, skill.projectile_height)
	if block != Vector3.INF:
		var to_block := _flat_distance(block, player.global_position)
		var block_travel := maxf(to_block / maxf(skill.projectile_speed, 0.1), 0.05)
		play_skill_fx.rpc(slot, target.peer_id, block, Vector3.ZERO, block_travel, true)
		return
	var travel := maxf(dist / maxf(skill.projectile_speed, 0.1), 0.05)
	play_skill_fx.rpc(slot, target.peer_id, player.global_position + height, Vector3.ZERO, travel, false)
	_after(skill.impact_delay + travel, func() -> void:
		if is_instance_valid(target) and not target.is_dead():
			_apply_to(target, skill))


func _cast_area_at_target(slot: int, skill: SkillData, target: Player) -> void:
	var center := target.global_position
	player.begin_cast(skill.cast_time, center)
	play_skill_fx.rpc(slot, target.peer_id, center, Vector3.ZERO, 0.0, false)
	_after(skill.impact_delay, func() -> void:
		# The tornado sticks to where the target stood when it was cast.
		for enemy in _enemies_in_radius(center, skill.radius):
			_apply_to(enemy, skill))


func _cast_area_in_front(slot: int, skill: SkillData, aim_point: Vector3) -> void:
	var origin := player.global_position
	var dir := aim_point - origin
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = player.facing_direction()
	dir = dir.normalized()
	var fx_point := origin + dir * skill.forward_distance
	var hit_center := origin if skill.area_on_caster else fx_point
	var cast_time := skill.cast_time
	var impact_delay := skill.impact_delay
	if skill.wait_for_attack_animation:
		# Land the effect only after one full "attack" animation has played.
		cast_time = player.get_attack_animation_length()
		impact_delay = cast_time
	player.begin_cast(cast_time, origin + dir * 5.0)
	var serial := player.cast_serial
	_after(impact_delay, func() -> void:
		# Stunned or killed while winding up: the skill is cancelled, no VFX, no effect.
		if player.is_dead() or player.cast_serial != serial:
			return
		play_skill_fx.rpc(slot, -1, fx_point, dir, 0.0, false)
		for enemy in _enemies_in_radius(hit_center, skill.radius):
			_apply_to(enemy, skill))


func _cast_self_buff(skill: SkillData) -> void:
	var status := player.status
	match skill.buff:
		SkillData.Buff.SHIELD:
			status.add_shield(int(skill.buff_value), skill.buff_duration)
		SkillData.Buff.EMPOWER_ATTACKS:
			status.add_empowered_attacks(skill.buff_count, int(skill.buff_value))
		SkillData.Buff.CC_IMMUNE:
			status.grant_cc_immunity(skill.buff_duration)
		SkillData.Buff.HASTE:
			status.apply_haste(skill.buff_value, skill.buff_duration)


func _apply_to(target: Player, skill: SkillData) -> void:
	# Status first: if the damage kills the target, its statuses are cleared anyway.
	if skill.stun_duration > 0.0:
		target.status.apply_stun(skill.stun_duration)
	if skill.slow_duration > 0.0:
		target.status.apply_slow(skill.slow_percent, skill.slow_duration)
	if skill.dot_duration > 0.0:
		target.status.apply_dot(skill.dot_damage, skill.dot_interval, skill.dot_duration, player.peer_id)
	var damage := skill.total_damage(player.character_data.damage)
	if damage > 0:
		target.take_damage(damage, player.peer_id)


func _fail(slot: int, reason: String) -> void:
	cast_failed_rpc.rpc_id(player.peer_id, slot, reason)


func _after(seconds: float, callback: Callable) -> void:
	if seconds <= 0.0:
		callback.call()
		return
	get_tree().create_timer(seconds).timeout.connect(callback)


func _enemies() -> Array[Player]:
	var list: Array[Player] = []
	for other in player.hero_spawner.player_list.values():
		if other is Player and is_instance_valid(other) and player.is_enemy(other) and not other.is_dead():
			list.append(other)
	return list


func _enemies_in_radius(center: Vector3, radius: float) -> Array[Player]:
	var list: Array[Player] = []
	for other in _enemies():
		if _flat_distance(other.global_position, center) <= radius:
			list.append(other)
	return list


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- RPCs to clients

@rpc("authority", "call_local", "reliable")
func cooldown_started_rpc(slot: int, duration: float) -> void:
	_local_ready_at[slot] = Time.get_ticks_msec() / 1000.0 + duration
	cooldown_started.emit(slot, duration)


@rpc("authority", "call_local", "reliable")
func cast_failed_rpc(slot: int, reason: String) -> void:
	cast_failed.emit(slot, reason)


## Visual part of a cast, played on every peer.
@rpc("authority", "call_local", "reliable")
## [param blocked] (projectiles): the shot stops on a prop at [param point]
func play_skill_fx(slot: int, target_peer: int, point: Vector3, dir: Vector3, travel_time: float, blocked: bool) -> void:
	if slot < 0 or slot >= skills.size():
		return
	var skill := skills[slot]
	var world := _world()
	if world == null:
		return
	match skill.kind:
		SkillData.Kind.PROJECTILE:
			var target := player.hero_spawner.get_player(target_peer) as Node3D
			if target == null:
				return
			_after_visual(skill.impact_delay, func() -> void:
				if not is_instance_valid(target) or not is_instance_valid(player):
					return
				var start := player.projectile_origin(skill.projectile_height)
				var projectile := SkillProjectile.create(skill, start, target, travel_time)
				if blocked:
					projectile.set_end_point(point)
				world.add_child(projectile)
				projectile.global_position = start)
		SkillData.Kind.AREA_AT_TARGET:
			_after_visual(skill.impact_delay, func() -> void:
				SkillVfx.spawn_world(world, skill.vfx_scene, point, skill.vfx_scale, skill.vfx_lifetime, true))
		SkillData.Kind.AREA_IN_FRONT:
			# The server sends this at the moment of impact, so play it right away.
			SkillVfx.spawn_world(world, skill.vfx_scene, point + Vector3(0, 0.05, 0), skill.vfx_scale, 0.0, false, dir)
		SkillData.Kind.SELF_BUFF:
			pass  # buff visuals come from StatusEffects.sync_state


func _after_visual(seconds: float, callback: Callable) -> void:
	if seconds <= 0.0:
		callback.call()
		return
	get_tree().create_timer(seconds).timeout.connect(callback)


func _world() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		return scene
	return player.get_parent()
