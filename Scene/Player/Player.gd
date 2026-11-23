class_name Player 

extends CharacterBody3D

# server variables
var target_position: Vector3
var target_attack = Object.new()
var attack_cooldown = 0.0

var player_state = PlayerState.IDLE
enum PlayerState{
	IDLE,
	MOVING,
	ATTACK,
	WAITING_FOR_RESPAWN,
	CASTING,
	DASHING,
}

# Skills (server)
var cast_time_left := 0.0
## Bumped when a cast is interrupted (stun, death): delayed skill effects check it and cancel
var cast_serial := 0
var state_before_cast = PlayerState.IDLE
var _stun_anim_sent := false

@onready var respawn_timer: Timer = $RespawnTimer

# general variables
var character_data: CharacterData
var current_hp: int

var team_side: GameDefines.TeamSide
var slot_index: int
var spawn_position: Vector3

var is_entered_tree = false
var current_animation: String

var camera: Node

@onready var hero_spawner = get_parent()
@onready var hp_bar = $SubViewport/hpBar
@onready var dmg_label_pos = $dmg_label_pos
var dmg_label = preload("res://Scene/Player/TakeDmgLabel.tscn")
var player_hp_bar = preload("res://Resources/GUI/PlayerHPBar.tres")
var teammate_hp_bar = preload("res://Resources/GUI/TeamMateHPBar.tres")
var enemy_hp_bar = preload("res://Resources/GUI/EnemyHPBar.tres")

var player_HUD: PlayerHUD

# Skill components, created in set_character_data() with the same name on every peer
var status: StatusEffects
var skill_caster: SkillCaster

# Variable for networking
var peer_id: int

# Network sync tuning
## Position updates per second sent by the server while a hero moves
const POSITION_SEND_RATE := 30.0
## The server re-sends position/direction this often even when nothing changed (covers lost packets)
const SYNC_HEARTBEAT := 0.5
## Client: how fast the drawn position catches up with the last received one (higher = snappier)
const CLIENT_SMOOTHING := 18.0
## Client: farther than this from the received position = teleport (spawn/respawn), snap instantly
const CLIENT_SNAP_DISTANCE := 4.0
## Server: direction changes smaller than this (degrees) are not sent
const DIRECTION_EPSILON_DEG := 2.0

# server: what was last sent, to send only changes
var _last_sent_anim := ""
var _last_sent_pos := Vector3.INF
var _last_sent_dir := Vector3.ZERO
var _pos_send_timer := 0.0
var _heartbeat_timer := 0.0
# server: path following (NavigationServer3D, baked by ArenaNavigation)
## A new path is asked for at least this often while moving (the target may move, or we got pushed)
const REPATH_INTERVAL := 0.5
## ...and at once when the goal moved more than this since the last path
const REPATH_GOAL_MOVED := 1.0
## A path corner counts as reached closer than this
const WAYPOINT_REACHED := 0.6
## Every peer: the local player's team can't see this (enemy) hero (out of vision or in a bush)
var is_hidden_locally := false
var _vision_timer := 0.0
## server: peer_id -> Time.get_ticks_msec() of the last damage from that enemy (kills / assists)
var damage_log := {}
## What a hp change was, for the floating number / hit feedback
enum DamageKind { BASIC, SKILL, DOT, HEAL }

var _flash_material: StandardMaterial3D
var _step_timer := 0.0
## Level in this match (server decides, synced to every peer by sync_level)
var level := 1
var xp := 0
## Sound of a melee basic attack landing, by hero id (ranged heroes use their shot sound)
const MELEE_ATTACK_SOUNDS := {SkillDB.KNIGHT: "sword", SkillDB.BARBARIAN: "axe"}
var _flash_tween: Tween

# server: an animation that nothing overrides for a while (e.g. the Barbarian's spin)
var _anim_lock_left := 0.0
# server: dash (SkillData.Kind.DASH)
var _dash_dir := Vector3.ZERO
var _dash_left := 0.0
var _dash_speed := 0.0
var _dash_time_left := 0.0
var _dash_on_end: Callable
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath_timer := 0.0
# client: position received from the server, drawn smoothly in _process
var _net_target_pos := Vector3.ZERO
var _has_net_target := false
# ---

func _ready() -> void:
	hp_bar.max_value = float(max_hp())
	_refresh_hp_bar()
	
	if multiplayer.is_server(): 
		target_attack = Object.new()
	
	# FIX: connect the respawn timer once here instead of on every death.
	# RespawnTimer has autostart = true in Player.tscn, so stop it now;
	# otherwise it would fire right after spawn and trigger a respawn.
	respawn_timer.stop()
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_on_timer_respawn_timeout)
	
	on_ready.rpc_id(GameDefines.HOST_ID, peer_id)

func _enter_tree() -> void:
	global_position = spawn_position
	_net_target_pos = spawn_position
	camera = get_tree().get_root().get_node("GamePlay").get_node("Camera3D")
	if NetworkManager.is_mine(peer_id):
		if camera is CameraController:
			camera.focus_to_me(global_position)		
		player_HUD = $CanvasLayer/player_details
		player_HUD.update_character_data_details(character_data)
	else:
		$CanvasLayer.queue_free()
	$character.finished_attack.connect(perform_attack)
	if get_parent() is HeroSpawner:
		print("connect all_player_spawned")
		get_parent().all_player_spawned.connect(_on_all_player_spawned)
	else:
		print("Error because parent isnt HeroSpawner")
	is_entered_tree = true
	
func _on_all_player_spawned() -> void:
	print("_on_all_player_spawned")
	set_hp_bar_texture()
	
func set_character_data(data: CharacterData) -> void:
	character_data = data
	# Already loaded in the background since the game started (AssetPreloader)
	var hero_model_scene = AssetPreloader.get_scene(character_data.character_scene)
	var hero_model = hero_model_scene.instantiate()	
	add_child(hero_model)
	hero_model.position = Vector3(0,0,0)

	# Skill system: same node names on every peer so their RPCs reach each other
	status = StatusEffects.new()
	status.name = "StatusEffects"
	add_child(status)
	skill_caster = SkillCaster.new()
	skill_caster.name = "SkillCaster"
	add_child(skill_caster)

func init(hero_team_info: Dictionary):
	spawn_position = GameDefines.LEFT_TEAM_SPAWN_POSITION
	
	team_side = hero_team_info[GameDefines.TEAM_SIDE]
	slot_index = hero_team_info[GameDefines.SLOT]
	
	if team_side == GameDefines.TeamSide.RIGHT:
		spawn_position = GameDefines.RIGHT_TEAM_SPAWN_POSITION
	
	spawn_position.z += GameDefines.DISTANCE_SPAWN_BETWEEN_PLAYERS * slot_index
	
	current_hp = max_hp()
	
func _input(event: InputEvent) -> void:
	if not NetworkManager.is_mine(peer_id): return
	if PauseMenu.is_open or MatchManager.is_over: return
	if hero_spawner.is_game_started():
		if event.is_action("Moving"):
			shoot_ray_cast()

## Raycast from the mouse cursor into the world. Returns {} or {"collider", "position", ...}.
func mouse_raycast(exclude_self := false) -> Dictionary:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_length = 1000
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * ray_length
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	# The hero's body is slim (to walk between props); clicks use the bigger ClickArea around it
	query.collide_with_areas = true
	if exclude_self:
		query.exclude = [get_rid(), $ClickArea.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] is Area3D and hit["collider"].get_parent() is Player:
		hit["collider"] = hit["collider"].get_parent()
	return hit

func shoot_ray_cast():
	#using ray cast to detect position cursor point at
	var raycast_result = mouse_raycast()
	if !raycast_result.is_empty():
		var coll = raycast_result.get("collider")
		if coll is Player:
			hero_clicked.rpc_id(GameDefines.HOST_ID, coll.peer_id)
		else:
			position_clicked.rpc_id(GameDefines.HOST_ID, raycast_result["position"])

## The hp bar is drawn in a SubViewport: render it only when it changed instead of every frame
func _refresh_hp_bar() -> void:
	var vp := hp_bar.get_parent() as SubViewport
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_hp_bar_texture() -> void:
	var player_id = multiplayer.get_unique_id()
	if peer_id == player_id: 
		hp_bar.add_theme_stylebox_override("fill", player_hp_bar)
		_refresh_hp_bar()
		return
	
	if not get_parent() is HeroSpawner: return
	var main_player = get_parent().get_player(player_id)
	if not main_player is Player: return
	
	var player_side = main_player.team_side

	if team_side != player_side:
		hp_bar.add_theme_stylebox_override("fill", enemy_hp_bar)
	else:
		hp_bar.add_theme_stylebox_override("fill", teammate_hp_bar)
	_refresh_hp_bar()

# --- SERVER FUNCTION ---

func _physics_process(delta: float) -> void:
	# only handle physic on server
	if not multiplayer.is_server(): return
	
	if _anim_lock_left > 0.0:
		_anim_lock_left -= delta
		if _anim_lock_left <= 0.0 or is_dead():
			_anim_lock_left = 0.0
			_last_sent_anim = ""
			# Back to what the hero is doing (attacking re-sends its own animation every frame)
			if not is_dead():
				_send_animation("moving" if player_state == PlayerState.MOVING else "idle")
			# Face the way again at once (the next direction is always sent)
			_last_sent_dir = Vector3.ZERO
	# No gravity while dead: the collision shape is off, the hero would fall through the ground
	if !is_on_floor() and not is_dead():
		velocity += get_gravity()*delta
		velocity.x = move_toward(velocity.x, 0, character_data.movement_speed)
		velocity.z = move_toward(velocity.z, 0, character_data.movement_speed)
		move_and_slide()
	_sync_transform_to_clients(delta)

	# Match over: everyone stands still
	if MatchManager.is_over:
		if player_state != PlayerState.WAITING_FOR_RESPAWN:
			_send_animation("idle")
		return
		
	if player_state == PlayerState.WAITING_FOR_RESPAWN: return

	# Dashing: nothing stops it (except a wall)
	if player_state == PlayerState.DASHING:
		_process_dash(delta)
		return

	# Stunned: stand still, keep the current order for when the stun ends
	if status.is_stunned():
		if player_state == PlayerState.CASTING:
			cast_serial += 1
			_end_cast()
		if not _stun_anim_sent:
			_stun_anim_sent = true
			_send_animation("idle")
		return
	if _stun_anim_sent:
		_stun_anim_sent = false

	# Casting a skill: stand still until the cast animation is done
	if player_state == PlayerState.CASTING:
		cast_time_left -= delta
		if cast_time_left <= 0.0:
			_end_cast()
		return

	# move player to target position
	if attack_cooldown < character_data.attack_speed:
		attack_cooldown += delta
	if player_state == PlayerState.MOVING:
		move_to_target(target_position)
	elif player_state == PlayerState.ATTACK and (not is_instance_valid(target_attack) or not target_attack is Player or target_attack.is_dead() or Vision.is_hidden(target_attack, team_side, hero_spawner.player_list.values())):
		# The target died, left the game or went out of sight: stop attacking, wait for the next order
		player_state = PlayerState.IDLE
		target_attack = null
		_clear_path()
		_send_animation("idle")
	elif player_state == PlayerState.ATTACK:		
		if (target_attack.position - global_position).length() > character_data.attack_range or not has_line_of_fire(target_attack):
			_send_animation("moving")
			move_to_target(target_attack.position)
		else: 
			var lookAtVector = Vector3(target_attack.position.x, position.y, target_attack.position.z)
			_send_direction(lookAtVector)
			_send_animation("attack")
	pass

func perform_attack() -> void:
	if not multiplayer.is_server(): return
	# The "attack" animation is also used to cast skills: only a real basic attack deals damage
	if player_state != PlayerState.ATTACK or status.is_stunned(): return
	if not is_instance_valid(target_attack): return
	#if attack_cooldown >= character_data.attack_speed:
	if target_attack is Player:
		var bonus := status.consume_empowered_attack()
		var dmg := attack_damage() + bonus
		attack_cooldown = 0
		status.break_stealth()  # attacking reveals a stealthed hero
		if BasicAttackFx.has_projectile(character_data.id):
			# Ranged: show the projectile everywhere, deal the damage when it lands
			var target: Player = target_attack
			var dist := (target.global_position - global_position).length()
			# A prop in the way stops the shot there: no damage
			var block := shot_block_point(target)
			if block != Vector3.INF:
				var to_block := Vector2(block.x - global_position.x, block.z - global_position.z).length()
				var block_travel := maxf(to_block / BasicAttackFx.speed_of(character_data.id), 0.05)
				play_basic_attack_fx.rpc(target.peer_id, block_travel, true, block)
				return
			var travel := maxf(dist / BasicAttackFx.speed_of(character_data.id), 0.05)
			play_basic_attack_fx.rpc(target.peer_id, travel, false, Vector3.ZERO)
			get_tree().create_timer(travel).timeout.connect(func() -> void:
				if is_instance_valid(target) and not target.is_dead() and not is_dead():
					target.take_damage(dmg, peer_id))
		else:
			play_melee_sound.rpc()
			target_attack.take_damage(dmg, peer_id)
			# Melee heroes heal a little on every hit
			heal(maxi(int(round(dmg * GameDefines.MELEE_LIFESTEAL)), 1))

## Server: where a shot from this hero to [param target] (chest height) hits a prop, or Vector3.INF
func shot_block_point(target: Node3D, height := BasicAttackFx.HEIGHT) -> Vector3:
	var up := Vector3(0, height, 0)
	return Obstacles.first_hit(get_world_3d(), global_position + up, target.global_position + up)

## Melee heroes always may hit; ranged ones need no prop between them and the target
func has_line_of_fire(target: Node3D) -> bool:
	if not BasicAttackFx.has_projectile(character_data.id): return true
	return shot_block_point(target) == Vector3.INF

## Server: rush [param distance] along [param dir] at [param speed]; [param on_end] runs when it stops
func start_dash(dir: Vector3, distance: float, speed: float, on_end: Callable) -> void:
	if not multiplayer.is_server(): return
	_clear_path()
	_dash_dir = Vector3(dir.x, 0, dir.z).normalized()
	_dash_left = distance
	_dash_speed = maxf(speed, 1.0)
	_dash_time_left = distance / _dash_speed + 0.25  # a wall in the way ends it
	_dash_on_end = on_end
	player_state = PlayerState.DASHING
	_send_direction(global_position + _dash_dir * 5.0, true)
	_send_animation("moving")
	if distance <= 0.05:
		_end_dash()

func _process_dash(delta: float) -> void:
	var step := minf(_dash_speed * delta, _dash_left)
	var before := global_position
	velocity = _dash_dir * (step / maxf(delta, 0.0001))
	move_and_slide()
	_dash_left -= Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_dash_time_left -= delta
	if _dash_left <= 0.05 or _dash_time_left <= 0.0:
		_end_dash()

func _end_dash() -> void:
	velocity = Vector3.ZERO
	player_state = PlayerState.IDLE
	_send_animation("idle")
	var cb := _dash_on_end
	_dash_on_end = Callable()
	if cb.is_valid():
		cb.call()

# --- LEVELS ---

func max_hp() -> int:
	return int(round(character_data.hp * (1.0 + GameDefines.HP_PER_LEVEL * (level - 1))))

func attack_damage() -> int:
	return int(round(character_data.damage * (1.0 + GameDefines.DAMAGE_PER_LEVEL * (level - 1))))

## XP needed for the next level (0 at max level) / total XP of the current level
func xp_for_next_level() -> int:
	return GameDefines.LEVEL_XP[level - 1] if level - 1 < GameDefines.LEVEL_XP.size() else 0

func xp_for_this_level() -> int:
	return GameDefines.LEVEL_XP[level - 2] if level >= 2 else 0

## Server: gain XP, level up (more max hp, healed by the difference) as many times as it reaches
func add_xp(amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0: return
	xp += amount
	var leveled := false
	while xp_for_next_level() > 0 and xp >= xp_for_next_level():
		var old_max := max_hp()
		level += 1
		leveled = true
		if not is_dead():
			current_hp = mini(current_hp + max_hp() - old_max, max_hp())
	sync_level.rpc(peer_id, level, xp)
	if leveled and not is_dead():
		set_current_hp.rpc(peer_id, 0, current_hp, DamageKind.HEAL)

@rpc("authority", "call_local", "reliable")
func sync_level(object_target_peer_id: int, new_level: int, new_xp: int) -> void:
	if peer_id != object_target_peer_id: return
	var leveled_up := new_level > level
	level = new_level
	xp = new_xp
	hp_bar.max_value = float(max_hp())
	_refresh_hp_bar()
	if player_HUD != null:
		player_HUD.set_level(self)
	if leveled_up and not is_hidden_locally:
		_level_up_feedback()

func _level_up_feedback() -> void:
	status.popup("LEVEL %d!" % level, Color(1, 0.85, 0.3))
	Sfx.play_3d(get_tree(), "level_up", global_position + Vector3(0, 1.5, 0))

## Server: play [param animation_name] on every peer and keep it for [param duration] seconds
## (moving / attacking don't replace it meanwhile)
func play_locked_animation(animation_name: String, duration: float) -> void:
	if not multiplayer.is_server(): return
	if $character is Character and not $character.animation_player.has_animation(animation_name): return
	_anim_lock_left = 0.0
	_last_sent_anim = animation_name
	trigger_animation.rpc(peer_id, animation_name)
	_anim_lock_left = duration

## Server: after a charge, keep attacking [param target]
func attack_after_dash(target: Player) -> void:
	if is_dead() or target == null or target.is_dead(): return
	target_attack = target
	target_position = target.position
	player_state = PlayerState.ATTACK

func get_move_speed() -> float:
	return character_data.movement_speed * status.move_speed_multiplier()

func move_to_target(target: Vector3):
	var speed = get_move_speed()
	var waypoint := _next_waypoint(target)
	# Stop at the goal, or at the end of the path when the goal itself can't be reached
	# (clicked inside a prop): the path then ends at the closest reachable point.
	var end_point := target if _path.is_empty() else _path[_path.size() - 1]
	if _flat_distance(end_point, global_position) > GameDefines.STOP_DISTANCE:
		var direction := waypoint - global_position
		direction.y = 0.0
		if direction.length() > 0.001:
			direction = direction.normalized()
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
			_send_direction(Vector3(waypoint.x, position.y, waypoint.z))
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)
		_send_animation("moving")
		move_and_slide()
	else:
		_clear_path()
		_send_animation("idle")
		player_state = PlayerState.IDLE

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _clear_path() -> void:
	_path = PackedVector3Array()
	_path_index = 0
	_path_goal = Vector3.INF

## Next corner of the path around the props toward [param goal]. Straight line when there is
## no navigation mesh yet (still baking) or no path was found.
func _next_waypoint(goal: Vector3) -> Vector3:
	_repath_timer -= get_physics_process_delta_time()
	if _path.is_empty() or _repath_timer <= 0.0 or _flat_distance(_path_goal, goal) > REPATH_GOAL_MOVED:
		_repath_timer = REPATH_INTERVAL
		_path_goal = goal
		_path_index = 0
		_path = PackedVector3Array()
		var nav_map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			_path = NavigationServer3D.map_get_path(nav_map, global_position, goal, true)
			# The first point is where we stand: skip it
			if _path.size() > 1:
				_path_index = 1
	if _path.is_empty():
		return goal
	while _path_index < _path.size() - 1 and _flat_distance(_path[_path_index], global_position) < WAYPOINT_REACHED:
		_path_index += 1
	return _path[_path_index]

# --- NETWORK SYNC (server) ---
# Animation/direction are sent only when they change; position at POSITION_SEND_RATE on its own
# channel, so it never waits behind reliable packets (ENet delivers each channel in order).

func _send_animation(animation_name: String) -> void:
	if _anim_lock_left > 0.0: return
	if _last_sent_anim == animation_name: return
	_last_sent_anim = animation_name
	trigger_animation.rpc(peer_id, animation_name)

func _send_direction(look_point: Vector3, force := false) -> void:
	var dir := look_point - global_position
	dir.y = 0.0
	if dir.length() < 0.01: return
	dir = dir.normalized()
	if not force and _last_sent_dir != Vector3.ZERO and _last_sent_dir.angle_to(dir) < deg_to_rad(DIRECTION_EPSILON_DEG):
		return
	_last_sent_dir = dir
	set_object_direction.rpc(peer_id, look_point)

func _sync_transform_to_clients(delta: float) -> void:
	# Before the match starts the clients may not have spawned this hero yet: position travels on
	# channel 1, so it could arrive before spawn_heros_to_tree (channel 0) -> "Node not found".
	if not hero_spawner.is_game_started(): return
	_pos_send_timer += delta
	_heartbeat_timer += delta
	var heartbeat := _heartbeat_timer >= SYNC_HEARTBEAT
	var moved := global_position.distance_squared_to(_last_sent_pos) > 0.0001
	if heartbeat or (moved and _pos_send_timer >= 1.0 / POSITION_SEND_RATE):
		_pos_send_timer = 0.0
		_heartbeat_timer = 0.0
		_last_sent_pos = global_position
		set_object_position.rpc(peer_id, global_position)
		if heartbeat and _last_sent_dir != Vector3.ZERO:
			set_object_direction.rpc(peer_id, global_position + _last_sent_dir)

# --- CLIENT SMOOTHING ---

func _process(delta: float) -> void:
	_play_footsteps(delta)
	_vision_timer -= delta
	if _vision_timer <= 0.0:
		_vision_timer = 0.1
		_update_vision()
	if multiplayer.is_server() or not _has_net_target: return
	var weight := 1.0 - exp(-CLIENT_SMOOTHING * delta)
	global_position = global_position.lerp(_net_target_pos, weight)

## Server. [param attacker_peer]: hero who dealt it (0 = unknown), for kills / assists / stats
func take_damage(dmg: int, attacker_peer := 0, kind := DamageKind.BASIC) -> void:
	if not multiplayer.is_server(): return
	if is_dead(): return
	# Shield (Bubble Shock) absorbs first
	dmg = status.absorb_damage(dmg)
	if dmg <= 0: return
	current_hp -= dmg
	if current_hp <= 0:
		# recaculate extractly dame taken
		dmg = dmg + current_hp
		current_hp = 0
	var match_manager := _match_manager()
	if attacker_peer != 0 and attacker_peer != peer_id:
		damage_log[attacker_peer] = Time.get_ticks_msec()
		if match_manager != null:
			match_manager.on_damage(attacker_peer, dmg)
	# Before set_current_hp: it starts the respawn timer, whose length depends on the deaths count
	if current_hp <= 0 and match_manager != null:
		match_manager.on_hero_killed(self, attacker_peer)
	set_current_hp.rpc(peer_id, dmg, current_hp, kind)	

func _match_manager() -> MatchManager:
	var scene := get_tree().current_scene
	if scene == null: return null
	return scene.get_node_or_null("MatchManager") as MatchManager
	
func handle_player_dead():
	if not multiplayer.is_server(): return
	if player_state == PlayerState.WAITING_FOR_RESPAWN: return
	
	print("handle_player_dead")
	player_state = PlayerState.WAITING_FOR_RESPAWN
	cast_time_left = 0.0
	cast_serial += 1
	status.clear_all()
	var match_manager := _match_manager()
	respawn_timer.wait_time = match_manager.respawn_time_for(peer_id) if match_manager != null else GameDefines.COOL_DOWN_FOR_RESPAWN_AFTER_DEAD
	respawn_timer.start()
	
func _on_timer_respawn_timeout():
	print("_on_timer_respawn_timeout")
	if not multiplayer.is_server(): return
	# FIX: only respawn a hero that is actually waiting for respawn
	if player_state != PlayerState.WAITING_FOR_RESPAWN: return
	respawn_timer.stop()
	player_state = PlayerState.IDLE
	_last_sent_anim = "idle"  # trigger_respawn plays "idle" on every peer
	trigger_respawn.rpc(peer_id, spawn_position, max_hp())
	
# --- RPCs ----

# server call to clients and/or itself
# Channel 1: position/direction never wait behind the reliable RPCs on channel 0
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func set_object_position(object_target_peer_id: int, new_position: Vector3):
	if peer_id != object_target_peer_id: return
	if multiplayer.is_server():
		global_position = new_position
		return
	# Client: _process glides toward it; big jumps (spawn, respawn) snap at once
	_net_target_pos = new_position
	if not _has_net_target or global_position.distance_to(new_position) > CLIENT_SNAP_DISTANCE:
		global_position = new_position
	_has_net_target = true

@rpc("authority", "call_local", "unreliable_ordered", 1)
func set_object_direction(object_target_peer_id: int, lookAtVector: Vector3):
	if peer_id != object_target_peer_id: return
	$character.look_at(lookAtVector, Vector3.UP)

@rpc("authority", "call_local", "reliable") 
func set_current_hp(object_target_peer_id: int, damage_take: int, current_hp_after_take_dmg: int, kind: int = DamageKind.BASIC):
	if peer_id != object_target_peer_id: return
	
	if damage_take != 0 and not is_hidden_locally:
		show_take_damage_label(damage_take, kind)
		if kind != DamageKind.HEAL:
			_hit_feedback(damage_take, kind)
	if player_HUD != null:
		player_HUD.set_current_hp_details(current_hp_after_take_dmg)
	current_hp = current_hp_after_take_dmg
	hp_bar.value = current_hp
	_refresh_hp_bar()
	# Dead: hidden and not solid until the respawn (trigger_respawn sets the hp back > 0)
	_set_alive_visual(current_hp > 0)
	if current_hp <= 0:
		handle_player_dead()

## Every peer: turn the body's collision on / off with life, then refresh what is shown
func _set_alive_visual(alive: bool) -> void:
	$CollisionShape3D.set_deferred("disabled", not alive)
	_apply_visibility()

## Shown (model, hp bar, effects) and clickable only when alive and not hidden in a bush
func _apply_visibility() -> void:
	var shown := current_hp > 0 and not is_hidden_locally
	# Every 3D child (model, hp bar, status effects); not the CanvasLayer with the local HUD
	for child in get_children():
		if child is Node3D and child.name != "ClickArea":
			child.visible = shown
	$ClickArea/CollisionShape3D.set_deferred("disabled", not shown)

## Every peer: is this hero out of sight of the local player's team? (Vision)
func _update_vision() -> void:
	var hidden := false
	if not NetworkManager.is_mine(peer_id) and hero_spawner is HeroSpawner:
		var me = hero_spawner.get_player(multiplayer.get_unique_id())
		if me != null:
			hidden = Vision.is_hidden(self, me.team_side, hero_spawner.player_list.values())
	if hidden != is_hidden_locally or hidden:
		# (re-applied while hidden: status effects attached meanwhile must stay hidden too)
		is_hidden_locally = hidden
		_apply_visibility()

## Server: heal [param amount] hp (healing zone)
func heal(amount: int) -> void:
	if not multiplayer.is_server() or is_dead() or current_hp >= max_hp(): return
	var before := current_hp
	current_hp = mini(current_hp + amount, max_hp())
	set_current_hp.rpc(peer_id, current_hp - before, current_hp, DamageKind.HEAL)

@rpc("authority", "call_local", "reliable")
func trigger_animation(object_target_peer_id: int, animation_name: String):
	if peer_id != object_target_peer_id: return
	
	if current_animation == animation_name: return
	current_animation = animation_name
	if $character is Character:
		$character.play_animation(animation_name)	
	
@rpc("authority", "call_local", "reliable") 
func trigger_respawn(object_target_peer_id: int, respawn_location: Vector3, hp_to_set: int):
	if peer_id != object_target_peer_id: return
	
	print("trigger_respawn")
	# call local, dont need to rpc here
	set_current_hp(object_target_peer_id, 0, hp_to_set)
	set_object_position(object_target_peer_id, respawn_location)
	if NetworkManager.is_mine(peer_id):
		camera.focus_to_me(respawn_location)
	trigger_animation(object_target_peer_id, "idle")
	
# client call to the host

@rpc("any_peer", "call_local", "reliable")
func on_ready(object_peer_id: int):
	if not multiplayer.is_server(): return
	
	var peer_id_sender = multiplayer.get_remote_sender_id()
	print("hero ready on peer: " + str(peer_id_sender))
	if peer_id != object_peer_id: return
	
	# The host's own copy: already at the right position (and set_object_position is call_remote,
	# so sending it to ourselves is an error), it only needs its hp bar filled
	if peer_id_sender == multiplayer.get_unique_id():
		set_current_hp(peer_id, 0, current_hp)
		return
	
	# Send the current position, hp, direction and animation to the sender
	set_object_position.rpc_id(peer_id_sender, peer_id, global_position)
	set_current_hp.rpc_id(peer_id_sender, peer_id, 0, current_hp, DamageKind.BASIC)
	sync_level.rpc_id(peer_id_sender, peer_id, level, xp)
	if _last_sent_dir != Vector3.ZERO:
		set_object_direction.rpc_id(peer_id_sender, peer_id, global_position + _last_sent_dir)
	if _last_sent_anim != "":
		trigger_animation.rpc_id(peer_id_sender, peer_id, _last_sent_anim)
	
@rpc("any_peer", "call_local", "unreliable_ordered")
func position_clicked(mouse_position: Vector3):
	if not multiplayer.is_server(): return
	if not _is_sender_owner("position_clicked"): return
	if is_dead(): return
	# On the ground: a click on top of a prop must not aim at its roof
	target_position = Vector3(mouse_position.x, 0.0, mouse_position.z)
	_clear_path()
	# A new order always turns the hero, even if it looks like the last direction sent
	_last_sent_dir = Vector3.ZERO
	_set_order(PlayerState.MOVING)
	
@rpc("any_peer", "call_local", "unreliable_ordered")
func hero_clicked(peer_id_object_clicked: int):
	if not multiplayer.is_server(): return
	if not _is_sender_owner("hero_clicked"): return
	if is_dead(): return

	var hero_is_clicked: Object = null
	if get_parent() is HeroSpawner:
		hero_is_clicked = get_parent().get_player(peer_id_object_clicked)
	else:
		print("hero_clicked: not found the hero with peer_id = " + str(peer_id_object_clicked))
		
	if hero_is_clicked == null or hero_is_clicked.is_dead(): return
	if Vision.is_hidden(hero_is_clicked, team_side, get_parent().player_list.values()): return
	if hero_is_clicked.team_side != team_side:
		target_attack = hero_is_clicked
		target_position = hero_is_clicked.position

		_set_order(PlayerState.ATTACK)
	else:
		target_position = hero_is_clicked.position
		_set_order(PlayerState.MOVING)

# A new move/attack order given while a skill is being cast runs once the cast ends
func _set_order(new_state) -> void:
	if player_state == PlayerState.DASHING:
		return  # a dash is short: orders given during it are ignored
	if player_state == PlayerState.CASTING:
		state_before_cast = new_state
	else:
		player_state = new_state

# --- SKILL HELPERS ---

func is_dead() -> bool:
	return player_state == PlayerState.WAITING_FOR_RESPAWN or current_hp <= 0

func is_enemy(other) -> bool:
	return other is Player and other != self and other.team_side != team_side

func can_cast() -> bool:
	return not is_dead() and player_state != PlayerState.CASTING and player_state != PlayerState.DASHING and not status.is_stunned()

## Direction the hero model faces (the model looks along -Z after look_at)
func facing_direction() -> Vector3:
	var forward: Vector3 = -$character.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return Vector3.FORWARD
	return forward.normalized()

## Name of the animation played when casting a skill: "cast" if the hero has one, else "attack"
func cast_animation_name() -> String:
	var ch = $character
	if ch is Character and ch.animation_player != null and ch.animation_player.has_animation("cast"):
		return "cast"
	return "attack"

## Length in seconds of this hero's skill-cast animation (its "attack" one if it has no "cast")
func get_attack_animation_length() -> float:
	var ch = $character
	var anim_name := cast_animation_name()
	if ch is Character and ch.animation_player != null and ch.animation_player.has_animation(anim_name):
		var ap: AnimationPlayer = ch.animation_player
		var speed: float = absf(ap.speed_scale) * maxf(ch.attack_speed_scale, 0.01)
		return ap.get_animation(anim_name).length / maxf(speed, 0.01)
	return 1.0

## Server: stop, face [param face_point] and play the cast animation for [param duration] seconds
func begin_cast(duration: float, face_point: Vector3) -> void:
	if not multiplayer.is_server(): return
	var look := Vector3(face_point.x, position.y, face_point.z)
	if (look - position).length() > 0.1:
		_send_direction(look, true)
	if duration <= 0.0: return
	if player_state != PlayerState.CASTING:
		state_before_cast = player_state
	player_state = PlayerState.CASTING
	cast_time_left = duration
	velocity.x = 0
	velocity.z = 0
	# trigger_cast_animation plays the cast animation on every peer; remember it so the next
	# order ("attack", "moving"...) is sent again and restarts the right animation
	_last_sent_anim = "cast"
	trigger_cast_animation.rpc(peer_id)

func _end_cast() -> void:
	cast_time_left = 0.0
	var next = state_before_cast
	state_before_cast = PlayerState.IDLE
	if next == PlayerState.ATTACK and not (is_instance_valid(target_attack) and target_attack is Player and not target_attack.is_dead()):
		next = PlayerState.IDLE
	if next != PlayerState.MOVING and next != PlayerState.ATTACK:
		next = PlayerState.IDLE
	player_state = next
	if next == PlayerState.IDLE:
		_send_animation("idle")

## Where this hero's projectiles appear: the raised weapon (HeroModel.muzzle_point), or in front of
## the chest at [param height] if the model has no weapon point
func projectile_origin(height: float) -> Vector3:
	var model = get_node_or_null("character")
	if model != null and model.has_method("muzzle_point"):
		var p: Vector3 = model.muzzle_point()
		if p != Vector3.INF:
			return p
	return global_position + facing_direction() * BasicAttackFx.FORWARD_OFFSET + Vector3(0, height, 0)

## Visual only: the basic-attack projectile of a ranged hero (damage is applied by the server)
@rpc("authority", "call_local", "reliable")
## [param blocked]: the shot hits a prop at [param block_point] instead of the target
func play_basic_attack_fx(target_peer: int, travel_time: float, blocked: bool, block_point: Vector3) -> void:
	if not (hero_spawner is HeroSpawner): return
	var target := hero_spawner.get_player(target_peer) as Node3D
	var world := get_tree().current_scene
	if target == null or world == null: return
	var start := projectile_origin(BasicAttackFx.HEIGHT)
	var projectile := BasicAttackFx.create(character_data.id, start, target, travel_time)
	if projectile == null: return
	if blocked:
		projectile.set_end_point(block_point)
	world.add_child(projectile)
	projectile.global_position = start
	var hero_id := character_data.id
	if not is_hidden_locally:
		Sfx.play_3d(get_tree(), "shoot_magic" if hero_id == SkillDB.MAGE else "shoot", start, -3.0)
	get_tree().create_timer(travel_time).timeout.connect(func() -> void:
		if not is_instance_valid(world): return
		if blocked:
			BasicAttackFx.spawn_impact(world, block_point, hero_id)
			Sfx.play_3d(get_tree(), "impact", block_point, -4.0)
		elif is_instance_valid(target):
			BasicAttackFx.spawn_impact(world, target.global_position + Vector3(0, BasicAttackFx.HEIGHT, 0), hero_id))

@rpc("authority", "call_local", "reliable")
func trigger_cast_animation(object_target_peer_id: int):
	if peer_id != object_target_peer_id: return
	current_animation = "cast"
	if $character is Character:
		$character.play_animation_from_start(cast_animation_name())

func _is_sender_owner(rpc_name: String) -> bool:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		push_warning("%s rejected: peer %d tried to control hero of peer %d" % [rpc_name, sender_id, peer_id])
		return false
	return true

func show_take_damage_label(dmg: int, kind := DamageKind.BASIC):
	var label = dmg_label.instantiate()
	add_child(label)
	label.position = dmg_label_pos.position
	label.set_dmg(dmg, kind)

@rpc("authority", "call_local", "reliable")
func play_melee_sound() -> void:
	if is_hidden_locally: return
	Sfx.play_3d(get_tree(), MELEE_ATTACK_SOUNDS.get(character_data.id, "hit"), global_position + facing_direction() * 1.5 + Vector3(0, 1.5, 0))

## Every peer: footsteps while the run animation plays (faster heroes step faster)
func _play_footsteps(delta: float) -> void:
	if current_animation != "moving" or current_hp <= 0 or is_hidden_locally or not visible:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0: return
	_step_timer = clampf(3.2 / maxf(float(character_data.movement_speed), 1.0), 0.2, 0.45)
	Sfx.play_step(get_tree(), global_position)

## Every peer: white flash on the model, hit sound, and a camera shake if it is my hero
func _hit_feedback(dmg: int, kind: int) -> void:
	_flash_white()
	Sfx.play_3d(get_tree(), "hit" if kind != DamageKind.DOT else "impact", global_position + Vector3(0, 1.5, 0), -6.0 if kind == DamageKind.DOT else -3.0)
	if NetworkManager.is_mine(peer_id):
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.has_method("shake"):
			cam.call("shake", clampf(0.15 + float(dmg) / max_hp() * 2.0, 0.15, 0.9), 0.25)

func _flash_white() -> void:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var meshes := $character.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		(m as MeshInstance3D).material_overlay = _flash_material
	_flash_material.albedo_color = Color(1, 1, 1, 0.75)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "albedo_color:a", 0.0, 0.15)
	_flash_tween.tween_callback(func() -> void:
		for m in meshes:
			if is_instance_valid(m):
				(m as MeshInstance3D).material_overlay = null)
