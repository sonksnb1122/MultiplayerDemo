extends  Node
class_name HeroSpawner

signal all_player_spawned

var player_list = {}
var player_ready_list: Array
var player_already_spawn_hero: Array

var player_scene = preload("res://Scene/Player/Player.tscn")
@onready var game_play_network: Node = $"../GamePlayNetwork"
@onready var game_play = get_parent()

var finished_spawned_all_player = false;
## Server: bots (negative ids) were added to player_ready_list
var _bots_ready := false
## Server: players who told they have every hero in their scene (the match starts after
## all of them, or after PEER_SPAWN_TIMEOUT seconds: otherwise the host's first updates for a
## hero reach a client before that hero exists there -> "Node not found" errors)
var _peers_spawned: Array[int] = []
var _local_spawned := false
var _wait_peers_left := 0.0
const PEER_SPAWN_TIMEOUT := 5.0

## Server: positions of every hero that moved, POSITION_SEND_RATE times a second, in ONE packet
## (instead of one packet per hero); every hero is re-sent each POSITION_HEARTBEAT seconds
## in case a packet was lost.
const POSITION_SEND_RATE := 30.0
const POSITION_HEARTBEAT := 0.5
var _pos_timer := 0.0
var _pos_heartbeat := 0.0
var _last_sent_pos := {}
var timer_force_spawn: Timer

# Loading: this peer tells the host it is ready only once the match assets are loaded
var _loading := false
var _load_paths: Array = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# A player who leaves the match (Exit to Main Menu / Quit) disappears from the battlefield
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# The hero selection is given to GamePlayNetwork right after this scene is added: start next frame
	_start_loading.call_deferred()
	
	if not multiplayer.is_server(): return
	
	timer_force_spawn = Timer.new()
	timer_force_spawn.wait_time = GameDefines.TIMEOUT_FORCE_SPAWN_HERO
	timer_force_spawn.timeout.connect(_on_timer_force_spawn_time_out)
	# FIX: Timer must be in the scene tree, otherwise it never ticks
	add_child(timer_force_spawn)
	timer_force_spawn.start()

func _start_loading() -> void:
	var hero_ids: Array = []
	for peer_id in game_play_network.hero_selection_status:
		hero_ids.append(game_play_network.hero_selection_status[peer_id][GameDefines.HERO_ID])
	_load_paths = CharacterDB.paths_for_heroes(hero_ids)
	AssetPreloader.start(_load_paths)  # already started in hero select: only the rest is loaded
	_loading = true

func _update_loading() -> void:
	var screen = game_play.get_node_or_null("LoadingScreen")
	var done := true
	for path in _load_paths:
		if not AssetPreloader.is_ready(path):
			done = false
			break
	if screen != null:
		screen.set_progress(AssetPreloader.progress(_load_paths) * 0.9)
	if not done: return
	_loading = false
	for path in _load_paths:
		AssetPreloader.get_scene(path)  # take them out of the loader into the cache
	# Heroes previewed in hero select but not picked: free them
	AssetPreloader.release_except(_load_paths)
	if screen != null:
		screen.set_progress(0.95)
		screen.set_status("Waiting for other players...")
	on_ready.rpc_id(GameDefines.HOST_ID)

func _on_timer_force_spawn_time_out():
	if not multiplayer.is_server(): return
	if finished_spawned_all_player:
		# FIX: everyone already spawned normally, no need to keep the timer running
		timer_force_spawn.stop()
		return

	if not is_hero_chosed_result_setted():
		timer_force_spawn.wait_time = 1
		return

	print("Force spawn heroes after timeout")
	timer_force_spawn.stop()
	var player_infos_for_spawn: Dictionary
	for peer_id in game_play_network.hero_selection_status:
		player_infos_for_spawn[peer_id] = get_hero_config_for_spawn(peer_id)
	# FIX: send the RPC once, after the dictionary is complete (was inside the loop)
	spawn_heros_to_tree.rpc(player_infos_for_spawn)
		
func _process(delta: float) -> void:
	if _loading:
		_update_loading()
	if !finished_spawned_all_player && is_hero_chosed_result_setted():
		var number_hero_ready = 0
		for player in player_list:
			if player_list[player].is_entered_tree: number_hero_ready += 1
		if number_hero_ready == game_play_network.hero_selection_status.size():
			if not multiplayer.is_server():
				report_spawned.rpc_id(GameDefines.HOST_ID)
				all_player_spawned.emit()
				finished_spawned_all_player = true
			elif not _local_spawned:
				_local_spawned = true
				_wait_peers_left = PEER_SPAWN_TIMEOUT
	if multiplayer.is_server() and _local_spawned and not finished_spawned_all_player:
		_wait_peers_left -= delta
		if _all_peers_spawned() or _wait_peers_left <= 0.0:
			all_player_spawned.emit()
			finished_spawned_all_player = true
	
	if not multiplayer.is_server(): return	
	if not is_hero_chosed_result_setted(): return
	# Bots have no peer to load anything: spawn them with the first player who is ready
	if not _bots_ready and not player_ready_list.is_empty():
		_bots_ready = true
		for id in game_play_network.hero_selection_status:
			if int(id) < 0 and not player_ready_list.has(int(id)):
				player_ready_list.push_back(int(id))
	# spawn hero for ready players
	
	var must_spawn_hero = false;
	for ready_id in player_ready_list:
		if not player_already_spawn_hero.has(ready_id):
			must_spawn_hero = true
			break
	
	if must_spawn_hero:
		var player_infos_for_spawn: Dictionary
		for ready_id in player_ready_list:
			player_infos_for_spawn[ready_id] = get_hero_config_for_spawn(ready_id)
			
		spawn_heros_to_tree.rpc(player_infos_for_spawn)

func _on_peer_disconnected(peer_id: int) -> void:
	var player = player_list.get(peer_id)
	player_list.erase(peer_id)
	if is_instance_valid(player):
		player.queue_free()

func is_game_started() -> bool:
	return game_play.game_started
	
func is_hero_chosed_result_setted() -> bool:
	if not game_play_network is GamePlayNetwork: 
		print("Please attach GamePlayNetwork to this node")
		return false
	
	var hero_status = game_play_network.hero_selection_status
	return not hero_status.is_empty()

func get_player(peer_id: int) -> Object:
	if player_list.has(peer_id): return player_list[peer_id]
	return null

func get_hero_config_for_spawn(peer_id: int) -> Dictionary:
	if not multiplayer.is_server(): return {}
	var hero_status = game_play_network.hero_selection_status
	if hero_status.has(peer_id): return hero_status[peer_id]
	
	print("Not found peer_id: %d in list hero_status_result send from chosen hero", peer_id)
	return {}
	
# --- RPCs ---

@rpc("authority", "call_local", "reliable")
# heros_for_spawn = {peer_id1: hero_id, peer_id2: hero_id,}
func spawn_heros_to_tree(heros_for_spawn: Dictionary): 
	print("spawn_heros_to_tree")
	for peer_id in heros_for_spawn: 
		if player_already_spawn_hero.has(peer_id): continue
		
		var chosen_hero_for_spawn = heros_for_spawn[peer_id]
		var hero_id = chosen_hero_for_spawn[GameDefines.HERO_ID]
		var selected_char = CharacterDB.get_character(hero_id)
		if selected_char == null: 
			print("spawn_hero fail because not found hero_id: %d in CharacterDB", hero_id)
	
		var player = player_scene.instantiate()
		player.name = chosen_hero_for_spawn[GameDefines.NAME]
		player.set_character_data(selected_char)
		player.init(chosen_hero_for_spawn)
		player.peer_id = peer_id
		player_list[peer_id] = player
		player_already_spawn_hero.push_back(peer_id)
		call_deferred("add_child", player)
		
		

@rpc("any_peer", "call_local", "reliable")
func on_ready():
	print("HeroSpawner on_ready")
	if not multiplayer.is_server(): return
	
	var peer_id_sender = multiplayer.get_remote_sender_id()
	player_ready_list.push_back(peer_id_sender)


## Server: every connected player in this match reported its heroes spawned
func _all_peers_spawned() -> bool:
	var connected := multiplayer.get_peers()
	for id in game_play_network.hero_selection_status:
		var pid := int(id)
		if pid <= 0 or pid == multiplayer.get_unique_id() or not connected.has(pid):
			continue
		if not _peers_spawned.has(pid):
			return false
	return true


@rpc("any_peer", "call_remote", "reliable")
func report_spawned() -> void:
	if not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if not _peers_spawned.has(sender):
		_peers_spawned.append(sender)


# --- POSITION SYNC ---

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_game_started():
		return
	_pos_timer += delta
	_pos_heartbeat += delta
	if _pos_timer < 1.0 / POSITION_SEND_RATE:
		return
	_pos_timer = 0.0
	var heartbeat := _pos_heartbeat >= POSITION_HEARTBEAT
	if heartbeat:
		_pos_heartbeat = 0.0
	var ids := PackedInt32Array()
	var positions := PackedVector3Array()
	for id in player_list:
		var hero = player_list[id]
		if not is_instance_valid(hero) or not hero.is_inside_tree():
			continue
		var pos: Vector3 = hero.global_position
		var last: Vector3 = _last_sent_pos.get(id, Vector3.INF)
		if heartbeat or last == Vector3.INF or pos.distance_squared_to(last) > 0.0001:
			ids.append(int(id))
			positions.append(pos)
			_last_sent_pos[id] = pos
	if not ids.is_empty():
		sync_positions.rpc(ids, positions)


## Channel 1, unreliable: a late packet is simply replaced by the next one, it never blocks the
## reliable game events on channel 0. Heroes not spawned here yet are skipped (no error).
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func sync_positions(ids: PackedInt32Array, positions: PackedVector3Array) -> void:
	for i in mini(ids.size(), positions.size()):
		var hero = player_list.get(ids[i])
		if is_instance_valid(hero):
			hero.apply_net_position(positions[i])
