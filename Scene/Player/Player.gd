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
# client: position received from the server, drawn smoothly in _process
var _net_target_pos := Vector3.ZERO
var _has_net_target := false
# ---

func _ready() -> void:
	hp_bar.max_value = float(character_data.hp)
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
	
	current_hp = character_data.hp
	
func _input(event: InputEvent) -> void:
	if not NetworkManager.is_mine(peer_id): return
	if PauseMenu.is_open: return
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
	if exclude_self:
		query.exclude = [get_rid()]
	return space.intersect_ray(query)

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
	
	if !is_on_floor():
		velocity += get_gravity()*delta
		velocity.x = move_toward(velocity.x, 0, character_data.movement_speed)
		velocity.z = move_toward(velocity.z, 0, character_data.movement_speed)
		move_and_slide()
	_sync_transform_to_clients(delta)
		
	if player_state == PlayerState.WAITING_FOR_RESPAWN: return

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
	elif player_state == PlayerState.ATTACK and not is_instance_valid(target_attack):
		# The target left the game
		player_state = PlayerState.IDLE
		_send_animation("idle")
	elif player_state == PlayerState.ATTACK:		
		if (target_attack.position - global_position).length() > character_data.attack_range:
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
		var dmg := character_data.damage + bonus
		attack_cooldown = 0
		if BasicAttackFx.has_projectile(character_data.id):
			# Ranged: show the projectile everywhere, deal the damage when it lands
			var target: Player = target_attack
			var dist := (target.global_position - global_position).length()
			var travel := maxf(dist / BasicAttackFx.speed_of(character_data.id), 0.05)
			play_basic_attack_fx.rpc(target.peer_id, travel)
			get_tree().create_timer(travel).timeout.connect(func() -> void:
				if is_instance_valid(target) and not target.is_dead() and not is_dead():
					target.take_damage(dmg))
		else:
			target_attack.take_damage(dmg)

func get_move_speed() -> float:
	return character_data.movement_speed * status.move_speed_multiplier()

func move_to_target(target: Vector3):
	var direction = (target - global_transform.origin).normalized()
	var speed = get_move_speed()
	if (target - global_position).length() > GameDefines.STOP_DISTANCE:
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)
		if target:
			var lookAtVector = Vector3(target.x, position.y, target.z)
			_send_direction(lookAtVector)
		
		_send_animation("moving")
		move_and_slide()
	else:
		_send_animation("idle")
		player_state = PlayerState.IDLE

# --- NETWORK SYNC (server) ---
# Animation/direction are sent only when they change; position at POSITION_SEND_RATE on its own
# channel, so it never waits behind reliable packets (ENet delivers each channel in order).

func _send_animation(animation_name: String) -> void:
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
	if multiplayer.is_server() or not _has_net_target: return
	var weight := 1.0 - exp(-CLIENT_SMOOTHING * delta)
	global_position = global_position.lerp(_net_target_pos, weight)

func take_damage(dmg: int) -> void:
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
	set_current_hp.rpc(peer_id, dmg, current_hp)	
	
func handle_player_dead():
	if not multiplayer.is_server(): return
	if player_state == PlayerState.WAITING_FOR_RESPAWN: return
	
	print("handle_player_dead")
	player_state = PlayerState.WAITING_FOR_RESPAWN
	cast_time_left = 0.0
	cast_serial += 1
	status.clear_all()
	respawn_timer.wait_time = GameDefines.COOL_DOWN_FOR_RESPAWN_AFTER_DEAD
	respawn_timer.start()
	
func _on_timer_respawn_timeout():
	print("_on_timer_respawn_timeout")
	if not multiplayer.is_server(): return
	# FIX: only respawn a hero that is actually waiting for respawn
	if player_state != PlayerState.WAITING_FOR_RESPAWN: return
	respawn_timer.stop()
	player_state = PlayerState.IDLE
	_last_sent_anim = "idle"  # trigger_respawn plays "idle" on every peer
	trigger_respawn.rpc(peer_id, spawn_position, character_data.hp)
	
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
func set_current_hp(object_target_peer_id: int, damage_take: int, current_hp_after_take_dmg: int):
	if peer_id != object_target_peer_id: return
	
	# TODO: trigger animation take dmg, UI for decrease HP
	if damage_take != 0:
		show_take_damage_label(damage_take)
	if player_HUD != null:
		player_HUD.set_current_hp_details(current_hp_after_take_dmg)
	current_hp = current_hp_after_take_dmg
	hp_bar.value = current_hp
	_refresh_hp_bar()
	if current_hp <= 0:
		handle_player_dead()

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
	set_current_hp.rpc_id(peer_id_sender, peer_id, 0, current_hp)
	if _last_sent_dir != Vector3.ZERO:
		set_object_direction.rpc_id(peer_id_sender, peer_id, global_position + _last_sent_dir)
	if _last_sent_anim != "":
		trigger_animation.rpc_id(peer_id_sender, peer_id, _last_sent_anim)
	
@rpc("any_peer", "call_local", "unreliable_ordered")
func position_clicked(mouse_position: Vector3):
	if not multiplayer.is_server(): return
	if not _is_sender_owner("position_clicked"): return
	if is_dead(): return
	target_position = mouse_position
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
		
	if hero_is_clicked == null: return
	if hero_is_clicked.team_side != team_side:
		target_attack = hero_is_clicked
		target_position = hero_is_clicked.position

		_set_order(PlayerState.ATTACK)
	else:
		target_position = hero_is_clicked.position
		_set_order(PlayerState.MOVING)

# A new move/attack order given while a skill is being cast runs once the cast ends
func _set_order(new_state) -> void:
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
	return not is_dead() and player_state != PlayerState.CASTING and not status.is_stunned()

## Direction the hero model faces (the model looks along -Z after look_at)
func facing_direction() -> Vector3:
	var forward: Vector3 = -$character.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return Vector3.FORWARD
	return forward.normalized()

## Length in seconds of this hero's "attack" animation
func get_attack_animation_length() -> float:
	var ch = $character
	if ch is Character and ch.animation_player != null and ch.animation_player.has_animation("attack"):
		var ap: AnimationPlayer = ch.animation_player
		var speed: float = absf(ap.speed_scale) * maxf(ch.attack_speed_scale, 0.01)
		return ap.get_animation("attack").length / maxf(speed, 0.01)
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
	_last_sent_anim = "attack"  # trigger_cast_animation plays "attack" on every peer
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

## Visual only: the basic-attack projectile of a ranged hero (damage is applied by the server)
@rpc("authority", "call_local", "reliable")
func play_basic_attack_fx(target_peer: int, travel_time: float) -> void:
	if not (hero_spawner is HeroSpawner): return
	var target := hero_spawner.get_player(target_peer) as Node3D
	var world := get_tree().current_scene
	if target == null or world == null: return
	var start := global_position + facing_direction() * BasicAttackFx.FORWARD_OFFSET + Vector3(0, BasicAttackFx.HEIGHT, 0)
	var projectile := BasicAttackFx.create(character_data.id, start, target, travel_time)
	if projectile == null: return
	world.add_child(projectile)
	projectile.global_position = start
	var hero_id := character_data.id
	get_tree().create_timer(travel_time).timeout.connect(func() -> void:
		if is_instance_valid(target) and is_instance_valid(world):
			BasicAttackFx.spawn_impact(world, target.global_position + Vector3(0, BasicAttackFx.HEIGHT, 0), hero_id))

@rpc("authority", "call_local", "reliable")
func trigger_cast_animation(object_target_peer_id: int):
	if peer_id != object_target_peer_id: return
	current_animation = "attack"
	if $character is Character:
		$character.play_animation_from_start("attack")

func _is_sender_owner(rpc_name: String) -> bool:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		push_warning("%s rejected: peer %d tried to control hero of peer %d" % [rpc_name, sender_id, peer_id])
		return false
	return true

func show_take_damage_label(dmg: int):
	var label = dmg_label.instantiate()
	label.set_dmg(dmg)
	add_child(label)
	label.position = dmg_label_pos.position
	pass
