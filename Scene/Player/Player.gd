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
}

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

# Variable for networking
var peer_id: int
# ---

func _ready() -> void:
	hp_bar.max_value = float(character_data.hp)
	
	if multiplayer.is_server(): 
		target_attack = Object.new()
	on_ready.rpc_id(GameDefines.HOST_ID, peer_id)

func _enter_tree() -> void:
	global_position = spawn_position
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
	var hero_model_scene = load(character_data.character_scene)
	var hero_model = hero_model_scene.instantiate()	
	add_child(hero_model)
	hero_model.position = Vector3(0,0,0)

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
	if hero_spawner.is_game_started():
		if event.is_action("Moving"):
			shoot_ray_cast()

func shoot_ray_cast():
	#using ray cast to detect position cursor point at
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_length = 1000
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * ray_length
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	var raycast_result =  space.intersect_ray(query)
	if !raycast_result.is_empty():
		var coll = raycast_result.get("collider")
		if coll is Player:
			hero_clicked.rpc_id(GameDefines.HOST_ID, coll.peer_id)
		else:
			position_clicked.rpc_id(GameDefines.HOST_ID, raycast_result["position"])

func set_hp_bar_texture() -> void:
	var player_id = multiplayer.get_unique_id()
	if peer_id == player_id: 
		hp_bar.add_theme_stylebox_override("fill", player_hp_bar)
		return
	
	if not get_parent() is HeroSpawner: return
	var main_player = get_parent().get_player(player_id)
	if not main_player is Player: return
	
	var player_side = main_player.team_side

	if team_side != player_side:
		hp_bar.add_theme_stylebox_override("fill", enemy_hp_bar)
	else:
		hp_bar.add_theme_stylebox_override("fill", teammate_hp_bar)

# --- SERVER FUNCTION ---

func _physics_process(delta: float) -> void:
	# only handle physic on server
	if not multiplayer.is_server(): return
	
	if !is_on_floor():
		velocity += get_gravity()*delta
		velocity.x = move_toward(velocity.x, 0, character_data.movement_speed)
		velocity.z = move_toward(velocity.z, 0, character_data.movement_speed)
		move_and_slide()
		set_object_position.rpc(peer_id, global_position)
		
	if player_state == PlayerState.WAITING_FOR_RESPAWN: return

	# move player to target position
	if attack_cooldown < character_data.attack_speed:
		attack_cooldown += delta
	if player_state == PlayerState.MOVING:
		move_to_target(target_position)
	elif player_state == PlayerState.ATTACK:		
		if (target_attack.position - global_position).length() > character_data.attack_range:
			trigger_animation.rpc(peer_id, "moving")
			move_to_target(target_attack.position)
		else: 
			var lookAtVector = Vector3(target_attack.position.x, position.y, target_attack.position.z)
			set_object_direction.rpc(peer_id, lookAtVector)
			trigger_animation.rpc(peer_id, "attack")
	pass

func perform_attack() -> void:
	if not multiplayer.is_server(): return
	#if attack_cooldown >= character_data.attack_speed:
	if target_attack is Player: 
		target_attack.take_damage(character_data.damage)
		attack_cooldown = 0
	
func move_to_target(target: Vector3):
	var direction = (target - global_transform.origin).normalized()
	if (target - global_position).length() > GameDefines.STOP_DISTANCE:
		if direction:
			velocity.x = direction.x * character_data.movement_speed
			velocity.z = direction.z * character_data.movement_speed
		else:
			velocity.x = move_toward(velocity.x, 0, character_data.movement_speed)
			velocity.z = move_toward(velocity.z, 0, character_data.movement_speed)
		if target:
			var lookAtVector = Vector3(target.x, position.y, target.z)
			set_object_direction.rpc(peer_id, lookAtVector)
		
		trigger_animation.rpc(peer_id, "moving")
		move_and_slide()
		set_object_position.rpc(peer_id, global_position)
	else:
		trigger_animation.rpc(peer_id, "idle")
		player_state = PlayerState.IDLE

func take_damage(dmg: int) -> void:
	if not multiplayer.is_server(): return
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
	respawn_timer.wait_time = GameDefines.COOL_DOWN_FOR_RESPAWN_AFTER_DEAD
	respawn_timer.timeout.connect(_on_timer_respawn_timeout)
	respawn_timer.start()
	
func _on_timer_respawn_timeout():
	print("_on_timer_respawn_timeout")
	if not multiplayer.is_server(): return
	respawn_timer.stop()
	player_state = PlayerState.IDLE
	trigger_respawn.rpc(peer_id, spawn_position, character_data.hp)
	
# --- RPCs ----

# server call to clients and/or itself
@rpc("authority", "call_remote", "unreliable_ordered")
func set_object_position(object_target_peer_id: int, new_position: Vector3):
	if peer_id != object_target_peer_id: return
	global_position = new_position

@rpc("authority", "call_local", "unreliable_ordered")
func set_object_direction(object_target_peer_id: int, lookAtVector: Vector3):
	if peer_id != object_target_peer_id: return
	$character.look_at(lookAtVector, Vector3.UP)

@rpc("authority", "call_local", "reliable") 
func set_current_hp(object_target_peer_id: int, damage_take: int, current_hp_after_take_dmg: int):
	if peer_id != object_target_peer_id: return
	
	print("set_current_hp: " + str(current_hp_after_take_dmg))
	# TODO: trigger animation take dmg, UI for decrease HP
	if damage_take != 0:
		show_take_damage_label(damage_take)
	if player_HUD != null:
		player_HUD.set_current_hp_details(current_hp_after_take_dmg)
	current_hp = current_hp_after_take_dmg
	hp_bar.value = current_hp
	if current_hp <= 0:
		handle_player_dead()

@rpc("authority", "call_local", "reliable")
func trigger_animation(object_target_peer_id: int, animation_name: String):
	if peer_id != object_target_peer_id: return
	
	if current_animation == animation_name: return
	current_animation = animation_name
	print("trigger_animation: " + animation_name + " PEER_ID: " + str(multiplayer.get_remote_sender_id()))
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
	
	# Update position, hp for the sender
	set_object_position.rpc_id(peer_id_sender, peer_id, spawn_position)
	set_current_hp.rpc_id(peer_id_sender, peer_id, 0, character_data.hp)
	
@rpc("any_peer", "call_local", "unreliable_ordered")
func position_clicked(mouse_position: Vector3):
	if not multiplayer.is_server(): return
	if not _is_sender_owner("position_clicked"): return
	player_state = PlayerState.MOVING
	target_position = mouse_position
	
@rpc("any_peer", "call_local", "unreliable_ordered")
func hero_clicked(peer_id_object_clicked: int):
	if not multiplayer.is_server(): return
	if not _is_sender_owner("hero_clicked"): return

	var hero_is_clicked: Object = null
	if get_parent() is HeroSpawner:
		hero_is_clicked = get_parent().get_player(peer_id_object_clicked)
	else:
		print("hero_clicked: not found the hero with peer_id = " + str(peer_id_object_clicked))
		
	if hero_is_clicked == null: return
	if hero_is_clicked.team_side != team_side:
		target_attack = hero_is_clicked
		target_position = hero_is_clicked.position

		player_state = PlayerState.ATTACK
	else:
		target_position = hero_is_clicked.position
		player_state = PlayerState.MOVING

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
