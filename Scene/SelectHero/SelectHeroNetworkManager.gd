extends Node

signal hero_all_selection_updated(hero_all_selection: Dictionary)
signal hero_selection_updated(peer_id: int, hero_selection: Dictionary)
signal count_down_trigged(time: int)
signal game_started
signal start_game_pending

@onready var select_timer: Timer = $SelectTimer
@onready var start_game_timer: Timer = $StartTimer

var hero_selection_status := {} # {1:[GameDefines.NAME: "P#x", GameDefines.TEAM_SIDE: 0, GameDefines.HERO_ID: 0, GameDefines.LOCKED: false]}

var remaining_time_to_start := GameDefines.COOL_DOWN_START_GAME
func _ready() -> void:
	NetworkManager.player_leaved.connect(_on_player_leave)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func init_hero_select():
	on_start_selecting.rpc_id(GameDefines.HOST_ID, multiplayer.get_unique_id())
	
func _on_player_leave(peer_id: int):
	hero_selection_status.erase(peer_id)
	#players_updated.emit(player_status)

func _on_server_disconnected():
	hero_selection_status = {}
	hero_all_selection_updated.emit(hero_selection_status)
	
# --- PLAYER ACTION IN ROOM ---
@rpc("any_peer", "call_local", "reliable")
func on_start_selecting(peer_id: int) -> void:
	# Only handle new player in server side
	if not multiplayer.is_server(): return
	
	# Send exist players in room to new client
	add_exist_selections.rpc_id(peer_id, hero_selection_status)
	
	# Handle new player status
	# Send it to all clients
	var player_info = LobbyNetworkManager.player_status[peer_id]
	add_new_selection.rpc(peer_id, {GameDefines.NAME: player_info[GameDefines.NAME], GameDefines.TEAM_SIDE: player_info[GameDefines.TEAM_SIDE], GameDefines.HERO_ID: 0, GameDefines.LOCKED: false})

		
@rpc("authority", "call_local", "reliable")
func add_exist_selections(exist_selections: Dictionary):
	print("add_exist_selections: " + str(exist_selections))
	for peer_id in exist_selections:
		hero_selection_status[peer_id] = exist_selections[peer_id]
	hero_all_selection_updated.emit(hero_selection_status)
	
@rpc("authority", "call_local", "reliable")
func add_new_selection(peer_id: int, new_selection_info: Dictionary):
	print("add_new_selection: " + str(new_selection_info))
	hero_selection_status[peer_id] = new_selection_info
	hero_all_selection_updated.emit(hero_selection_status)
	
@rpc("any_peer", "call_local", "reliable")
func set_selection_status(hero_id: int, locked: bool) -> void:
	print("Choosing hero " + str(hero_id) + ", is locked: " + str(locked))
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if hero_selection_status[peer_id][GameDefines.HERO_ID] != hero_id or hero_selection_status[peer_id][GameDefines.LOCKED] != locked:
		hero_selection_status[peer_id][GameDefines.HERO_ID] = hero_id
		hero_selection_status[peer_id][GameDefines.LOCKED] = locked
		update_selection_status.rpc(peer_id, hero_selection_status[peer_id])
	
@rpc("authority", "call_local", "reliable")
func update_selection_status(peer_id: int, hero_selection: Dictionary):
	hero_selection_status[peer_id] = hero_selection
	hero_selection_updated.emit(peer_id, hero_selection)

@rpc("authority", "call_local", "reliable")
func update_all_selection_status(all_selection_status: Dictionary):
	print("update_all_selection_status: " + str(all_selection_status))
	hero_selection_status = all_selection_status
	hero_all_selection_updated.emit(hero_selection_status)
	
# --- START GAME ---
func try_start_game() -> bool:
	if not multiplayer.is_server():
		return false	
	
	remaining_time_to_start = GameDefines.STARTING_TIME
	show_count_down.rpc(remaining_time_to_start)
	start_game_timer.wait_time = 1
	start_game_timer.one_shot = false
	start_game_timer.timeout.connect(send_start_remaining_time)
	start_game_timer.start()
	
	return true
	
func send_start_remaining_time():
	remaining_time_to_start -= 1

	if remaining_time_to_start <= 0:
		start_game.rpc()
		start_game_timer.stop()
	else:
		show_count_down.rpc(remaining_time_to_start)
			
func try_start_select() -> bool:
	if not multiplayer.is_server():
		return false	
		
	remaining_time_to_start = GameDefines.LOBBY_TIME
	show_count_down.rpc(remaining_time_to_start)
	select_timer.wait_time = 1
	select_timer.one_shot = false
	select_timer.timeout.connect(send_select_remaining_time)
	select_timer.start()
	
	return true
	
func send_select_remaining_time():
	remaining_time_to_start -= 1

	if remaining_time_to_start <= 0:
		pending_start_game.rpc()
		select_timer.stop()
	else:
		show_count_down.rpc(remaining_time_to_start)
	
@rpc("authority", "call_local", "reliable")
func show_count_down(time: int):
	print("show_count_down: " + str(time))
	count_down_trigged.emit(time)
@rpc("authority", "call_local", "reliable")
func pending_start_game():
	print("pending_start_game")
	start_game_pending.emit()
@rpc("authority", "call_local", "reliable")
func start_game():
	print("start_game")
	game_started.emit()
