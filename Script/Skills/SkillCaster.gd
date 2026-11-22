class_name SkillCaster
extends Node
## Q / W / E / R (ultimate) skills and the Dash (Space) of one hero (child of Player, named
## "SkillCaster" on every peer). Hold a key to aim (range / area shown on the ground), release to
## cast; self buffs are cast on press.
##
## Flow (server-authoritative, like the rest of the game):
##   owner presses a key -> request_cast.rpc_id(HOST) with the target under the mouse
##   server checks owner / alive / stun / cooldown / range -> starts the cast on the Player,
##   tells every peer to play the VFX (play_skill_fx), applies the effect on its own timer,
##   and tells the owner the cooldown (cooldown_started).

signal cooldown_started(slot: int, duration: float)
signal cast_failed(slot: int, reason: String)

const ACTIONS := [&"Skill1", &"Skill2", &"Skill3", &"Skill4", &"Dash"]
const KEYS := [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_SPACE]
const KEY_LABELS := ["Q", "W", "E", "R", "SPC"]
## When the mouse is not exactly on an enemy, pick the closest enemy within this distance of the cursor.
const CURSOR_PICK_RADIUS := 4.0
const RANGE_TOLERANCE := 1.0

var player: Player
var skills: Array[SkillData] = []

var _cooldown_left: Array[float] = []  # server
var _local_ready_at: Array[float] = []  # owner, in seconds (Time.get_ticks_msec / 1000)
var _skill_bar: SkillBar
## Owner: slot being aimed (key held), -1 = none
var _aiming := -1
var _indicator: SkillIndicator
## Server: skill shots in flight {pos, dir, left, hit (peer ids), skill}
var _line_shots: Array = []


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
	_cooldown_left.resize(skills.size())
	_cooldown_left.fill(0.0)
	_local_ready_at.resize(skills.size())
	_local_ready_at.fill(0.0)
	# Load the scenes now so the first cast doesn't hitch.
	for skill in skills:
		SkillVfx.load_scene(skill.vfx_scene)
		SkillVfx.load_scene(skill.projectile_model)
		SkillVfx.load_scene(skill.rain_model)
		SkillVfx.load_scene(skill.rain_vfx)
		SkillVfx.load_scene(skill.aura_vfx)
	if NetworkManager.is_mine(player.peer_id):
		ensure_input_actions()
		_create_skill_bar.call_deferred()
		_indicator = SkillIndicator.new()
		_indicator.name = "SkillIndicator"
		add_child(_indicator)


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
		_stop_aiming()
		return
	for i in mini(ACTIONS.size(), skills.size()):
		if event.is_action_pressed(ACTIONS[i], false):
			get_viewport().set_input_as_handled()
			if skills[i].kind == SkillData.Kind.SELF_BUFF:
				_stop_aiming()
				try_cast(i)  # nothing to aim
			else:
				_aiming = i
			return
		if event.is_action_released(ACTIONS[i]) and _aiming == i:
			get_viewport().set_input_as_handled()
			_stop_aiming()
			try_cast(i)
			return


func _stop_aiming() -> void:
	_aiming = -1
	if _indicator != null:
		_indicator.hide_indicator()


## Owner: draw the range / area of the skill being aimed
func _update_indicator() -> void:
	if _aiming < 0 or _indicator == null:
		return
	if player.is_dead() or PauseMenu.is_open or MatchManager.is_over:
		_stop_aiming()
		return
	var skill := skills[_aiming]
	var hero := player.global_position
	var hit := player.mouse_raycast()
	var point: Vector3 = hit.get("position", hero)
	var center := hero
	match skill.kind:
		SkillData.Kind.PROJECTILE, SkillData.Kind.AREA_AT_TARGET:
			var target := _pick_target(hit, point, skill)
			center = target.global_position if target != null else _clamp_to_range(point, skill.cast_range)
		SkillData.Kind.AREA_AT_POINT:
			center = _clamp_to_range(point, skill.cast_range)
		SkillData.Kind.AREA_IN_FRONT:
			var dir := point - hero
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.1 else player.facing_direction()
			center = hero if skill.area_on_caster else hero + dir * skill.forward_distance
		SkillData.Kind.DASH:
			if skill.needs_target:
				var target := _pick_target(hit, point, skill)
				center = target.global_position if target != null else _clamp_to_range(point, skill.cast_range)
			else:
				center = _clamp_to_range(point, skill.cast_range)
	if skill.kind == SkillData.Kind.LINE_SHOT:
		var line_dir := Vector3(point.x - hero.x, 0, point.z - hero.z)
		if line_dir.length() < 0.1:
			line_dir = player.facing_direction()
		_indicator.show_line(skill.color, hero, line_dir, skill.cast_range, skill.radius)
		return
	var area := skill.indicator_radius()
	if skill.kind == SkillData.Kind.DASH and area <= 0.0:
		area = 1.0  # where the dash ends
	var range_radius := skill.cast_range
	if skill.kind == SkillData.Kind.AREA_AROUND_CASTER or (skill.kind == SkillData.Kind.AREA_IN_FRONT and not skill.needs_target):
		range_radius = 0.0
	_indicator.show_at(skill.color, hero, range_radius, center, area)


func _clamp_to_range(point: Vector3, max_range: float) -> Vector3:
	var hero := player.global_position
	var d := Vector3(point.x - hero.x, 0, point.z - hero.z)
	if d.length() > max_range:
		d = d.normalized() * max_range
	return hero + d


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
	if collider is Player and player.is_enemy(collider) and not collider.is_dead() and not collider.is_hidden_locally:
		return collider
	# Closest enemy to the cursor, then closest enemy in range of the hero.
	var best: Player = null
	var best_dist := CURSOR_PICK_RADIUS
	for other in _enemies():
		if other.is_hidden_locally: continue
		var d := _flat_distance(other.global_position, point)
		if d <= best_dist:
			best = other
			best_dist = d
	if best != null:
		return best
	best_dist = skill.cast_range
	for other in _enemies():
		if other.is_hidden_locally: continue
		var d := _flat_distance(other.global_position, player.global_position)
		if d <= best_dist:
			best = other
			best_dist = d
	return best


# ---------------------------------------------------------------- server

func _process(delta: float) -> void:
	_update_indicator()
	if not multiplayer.is_server():
		return
	_update_line_shots(delta)
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
		if target == null or not player.is_enemy(target) or target.is_dead() \
				or Vision.is_hidden(target, player.team_side, player.hero_spawner.player_list.values()):
			_fail(slot, "No target")
			return
		if _flat_distance(target.global_position, player.global_position) > skill.cast_range + RANGE_TOLERANCE:
			_fail(slot, "Out of range")
			return

	# Attacking / casting reveals a stealthed hero (except casting the stealth itself)
	if skill.buff != SkillData.Buff.STEALTH:
		player.status.break_stealth()

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
		SkillData.Kind.AREA_AT_POINT:
			_cast_area_at_point(slot, skill, aim_point)
		SkillData.Kind.AREA_AROUND_CASTER:
			_cast_area_around_caster(slot, skill)
		SkillData.Kind.DASH:
			_cast_dash(slot, skill, target, aim_point)
		SkillData.Kind.LINE_SHOT:
			_cast_line_shot(slot, skill, aim_point)

	_cooldown_left[slot] = skill.cooldown
	cooldown_started_rpc.rpc_id(player.peer_id, slot, skill.cooldown)
	play_cast_sound.rpc(slot)


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


## Ground area under the mouse (clamped to the range), hitting [member SkillData.hits] times
func _cast_area_at_point(slot: int, skill: SkillData, aim_point: Vector3) -> void:
	var origin := player.global_position
	var d := Vector3(aim_point.x - origin.x, 0, aim_point.z - origin.z)
	if d.length() > skill.cast_range:
		d = d.normalized() * skill.cast_range
	var center := origin + d
	center.y = 0.0
	player.begin_cast(skill.cast_time, center)
	play_skill_fx.rpc(slot, -1, center, Vector3.ZERO, 0.0, false)
	for i in maxi(skill.hits, 1):
		_after(skill.impact_delay + i * skill.hit_interval, func() -> void:
			if MatchManager.is_over or not is_instance_valid(player):
				return
			for enemy in _enemies_in_radius(center, skill.radius):
				_apply_to(enemy, skill))


## Around the caster, wherever they are at each hit (they can keep moving)
func _cast_area_around_caster(slot: int, skill: SkillData) -> void:
	if skill.cast_time > 0.0:
		player.begin_cast(skill.cast_time, player.global_position + player.facing_direction())
	var duration := skill.impact_delay + maxi(skill.hits, 1) * skill.hit_interval
	if not skill.caster_animation.is_empty():
		# e.g. Barbarian spinning with the axe while the whirlwind lasts
		player.play_locked_animation(skill.caster_animation, duration)
	if not skill.aura_vfx.is_empty():
		play_skill_aura.rpc(slot, duration)
	for i in maxi(skill.hits, 1):
		_after(skill.impact_delay + i * skill.hit_interval, func() -> void:
			if MatchManager.is_over or not is_instance_valid(player) or player.is_dead() or player.status.is_stunned():
				return
			var center := player.global_position
			play_skill_fx.rpc(slot, -1, center, player.facing_direction(), 0.0, false)
			for enemy in _enemies_in_radius(center, skill.radius):
				_apply_to(enemy, skill))


## Rush toward the mouse (or the target); with a radius, hit everything around the end point
func _cast_dash(slot: int, skill: SkillData, target: Player, aim_point: Vector3) -> void:
	var origin := player.global_position
	var goal := target.global_position if target != null else aim_point
	var d := Vector3(goal.x - origin.x, 0, goal.z - origin.z)
	var distance := d.length()
	if target != null:
		distance = maxf(distance - 1.5, 0.0)  # stop in front of the target, not inside it
	distance = minf(distance, skill.cast_range)
	var dir := d.normalized() if d.length() > 0.1 else player.facing_direction()
	player.start_dash(dir, distance, skill.dash_speed, func() -> void:
		if skill.radius <= 0.0 or not is_instance_valid(player) or player.is_dead():
			return
		var center := player.global_position
		play_skill_fx.rpc(slot, -1, center, dir, 0.0, false)
		for enemy in _enemies_in_radius(center, skill.radius):
			_apply_to(enemy, skill)
		# Knight's charge: keep hitting the target
		if target != null and is_instance_valid(target) and not target.is_dead():
			player.attack_after_dash(target))


## Skill shot: flies straight for cast_range through props and heroes, hitting each enemy once
func _cast_line_shot(slot: int, skill: SkillData, aim_point: Vector3) -> void:
	var origin := player.global_position
	var dir := Vector3(aim_point.x - origin.x, 0, aim_point.z - origin.z)
	dir = dir.normalized() if dir.length() > 0.1 else player.facing_direction()
	player.begin_cast(skill.cast_time, origin + dir * 5.0)
	var travel := skill.cast_range / maxf(skill.projectile_speed, 0.1)
	play_skill_fx.rpc(slot, -1, origin, dir, travel, false)
	var serial := player.cast_serial
	_after(skill.impact_delay, func() -> void:
		if not is_instance_valid(player) or player.is_dead() or player.cast_serial != serial:
			return
		_line_shots.append({"pos": player.global_position, "dir": dir, "left": skill.cast_range, "hit": [], "skill": skill}))


func _update_line_shots(delta: float) -> void:
	if _line_shots.is_empty():
		return
	for shot in _line_shots:
		var skill: SkillData = shot["skill"]
		var step := minf(skill.projectile_speed * delta, shot["left"])
		var from: Vector3 = shot["pos"]
		var to: Vector3 = from + shot["dir"] * step
		for enemy in _enemies():
			if shot["hit"].has(enemy.peer_id):
				continue
			var p := Geometry3D.get_closest_point_to_segment(Vector3(enemy.global_position.x, 0, enemy.global_position.z), Vector3(from.x, 0, from.z), Vector3(to.x, 0, to.z))
			if _flat_distance(p, enemy.global_position) <= skill.radius + 0.8:
				shot["hit"].append(enemy.peer_id)
				_apply_to(enemy, skill)
		shot["pos"] = to
		shot["left"] -= step
	_line_shots = _line_shots.filter(func(s: Dictionary) -> bool: return s["left"] > 0.01)


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
		SkillData.Buff.STEALTH:
			status.apply_stealth(skill.buff_duration)
			status.add_empowered_attacks(1, int(skill.buff_value))


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
		target.take_damage(damage, player.peer_id, Player.DamageKind.SKILL)


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
func play_cast_sound(slot: int) -> void:
	if slot < 0 or slot >= skills.size() or player.is_hidden_locally:
		return
	var skill := skills[slot]
	var sound := skill.sound
	if sound.is_empty():
		sound = "dash" if skill.kind == SkillData.Kind.DASH else "cast"
	Sfx.play_3d(get_tree(), sound, player.global_position + Vector3(0, 1.5, 0), -2.0)


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
			_play_hit_sound(skill, point)
		SkillData.Kind.SELF_BUFF:
			pass  # buff visuals come from StatusEffects.sync_state
		SkillData.Kind.AREA_AT_POINT:
			_after_visual(skill.impact_delay, func() -> void:
				if not skill.vfx_scene.is_empty():
					SkillVfx.spawn_world(world, skill.vfx_scene, point, skill.vfx_scale, skill.vfx_lifetime, true)
				if not skill.rain_model.is_empty():
					_spawn_rain(world, skill, point))
			# One sound per wave
			if not skill.hit_sound.is_empty():
				for i in maxi(skill.hits, 1):
					_after_visual(skill.impact_delay + i * skill.hit_interval, func() -> void:
						_play_hit_sound(skill, point))
		SkillData.Kind.LINE_SHOT:
			_after_visual(skill.impact_delay, func() -> void:
				if not is_instance_valid(player):
					return
				var start := player.projectile_origin(skill.projectile_height)
				var end := start + Vector3(dir.x, 0, dir.z).normalized() * skill.cast_range
				var shot := SkillProjectile.create(skill, start, null, travel_time)
				shot.set_end_point(end)
				world.add_child(shot)
				shot.global_position = start)
		SkillData.Kind.AREA_AROUND_CASTER, SkillData.Kind.DASH:
			# Sent by the server at the moment of each hit
			if not skill.vfx_scene.is_empty():
				SkillVfx.spawn_world(world, skill.vfx_scene, point + Vector3(0, 0.05, 0), skill.vfx_scale, 0.0, false, dir)
			_play_hit_sound(skill, point)


func _play_hit_sound(skill: SkillData, point: Vector3) -> void:
	if skill.hit_sound.is_empty() or player.is_hidden_locally:
		return
	Sfx.play_3d(get_tree(), skill.hit_sound, point + Vector3(0, 1.0, 0), -2.0)


## VFX stuck to the hero while an AREA_AROUND_CASTER skill lasts (Barbarian's fire whirlwind):
## low and wide so it shows the area that is hit
@rpc("authority", "call_local", "reliable")
func play_skill_aura(slot: int, duration: float) -> void:
	if slot < 0 or slot >= skills.size():
		return
	var skill := skills[slot]
	# (scaled by the width first: particles that align themselves resize their quads with it)
	var fx := SkillVfx.instantiate(skill.aura_vfx, skill.aura_scale_xz)
	if fx == null:
		return
	player.add_child(fx)
	fx.position = Vector3(0, 0.05, 0)
	var size := Vector3(skill.aura_scale_xz, skill.aura_scale_y, skill.aura_scale_xz)
	fx.scale = size * 0.3
	for g in fx.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fx.has_method("open"):
		fx.call("open")
	var tween := fx.create_tween()
	tween.tween_property(fx, "scale", size, 0.2)
	tween.tween_interval(maxf(duration - 0.4, 0.0))
	tween.tween_property(fx, "scale", size * 0.2, 0.2)
	tween.tween_callback(fx.queue_free)


## Models (arrows) falling on the area, spread over all its hits
func _spawn_rain(world: Node, skill: SkillData, center: Vector3) -> void:
	var scene := SkillVfx.load_scene(skill.rain_model)
	if scene == null:
		return
	var total_time := maxf((skill.hits - 1) * skill.hit_interval, 0.1)
	for i in skill.rain_count:
		var delay := randf() * total_time
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(world):
				return
			var arrow := scene.instantiate() as Node3D
			if arrow == null:
				return
			world.add_child(arrow)
			var angle := randf() * TAU
			var r := sqrt(randf()) * skill.radius
			var ground := center + Vector3(cos(angle) * r, 0.3, sin(angle) * r)
			arrow.global_position = ground + Vector3(0, 12, 0)
			arrow.rotation_degrees = Vector3(90, randf() * 360.0, 0)  # tip (+Z) pointing down
			arrow.scale = Vector3.ONE * 1.6
			for g in arrow.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Lightning around the arrow (the javelin VFX points along +X: turn it along the tip, +Z)
			if not skill.rain_vfx.is_empty():
				var fx := SkillVfx.instantiate(skill.rain_vfx, skill.rain_vfx_scale)
				if fx != null:
					fx.rotation_degrees = Vector3(0, -90, 0)
					arrow.add_child(fx)
					if fx.has_method("open"):
						fx.call("open")
			var tween := arrow.create_tween()
			tween.tween_property(arrow, "global_position", ground, 0.3)
			tween.tween_interval(0.35)
			tween.tween_callback(arrow.queue_free))


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
