extends Node

signal players_updated(players: Dictionary)
signal cool_down_trigged(cool_down: int)
signal game_started

@onready var timer: Timer = $Timer

var player_status := {} # {1:[GameDefines.NAME: "Player123", GameDefines.READY: true, GameDefines.TeamSide.LEFT]}

var remaining_time_to_start := GameDefines.COOL_DOWN_START_GAME
var is_waiting_to_start = false

func _ready() -> void:
	# Signal for server
	NetworkManager.new_player_joined.connect(_on_new_player_joined)
	
	# Signal for boths
	NetworkManager.player_leaved.connect(_on_player_leaved)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func _on_new_player_joined(peer_id: int, player_name: String):
	# Only handle new player in server side
	if not multiplayer.is_server(): return
	
	# Send exist players in room to new client
	add_exist_players.rpc_id(peer_id, player_status)
	
	# Handle new player status
	var is_ready = peer_id == GameDefines.HOST_ID
	
	# Decide which team side to take
	var number_player_left_side = 0
	var number_player_right_side = 0
	for id in player_status:
		if player_status[id].has(GameDefines.TEAM_SIDE) &&  player_status[id][GameDefines.TEAM_SIDE] == GameDefines.TeamSide.RIGHT: 
			number_player_right_side += 1
		else:
			number_player_left_side += 1

	var side = GameDefines.TeamSide.LEFT
	if number_player_right_side < number_player_left_side:
		side = GameDefines.TeamSide.RIGHT
	
	# Send it to all clients
	add_new_player.rpc(peer_id, {GameDefines.NAME: player_name, GameDefines.READY: is_ready, GameDefines.TEAM_SIDE: side})

func _on_player_leaved(peer_id: int):
	if NetworkManager.is_mine(peer_id):
		player_status = {}
	else:
		player_status.erase(peer_id)
	players_updated.emit(player_status)
	
func _on_server_disconnected():
	player_status = {}
	players_updated.emit(player_status)
	
# --- PLAYER ACTION IN ROOM ---

@rpc("any_peer", "call_local", "reliable")
func set_ready_status(is_ready: bool) -> void:
	print("set_ready_status: " + str(is_ready))
	if not multiplayer.is_server() || is_waiting_to_start:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if player_status[peer_id][GameDefines.READY] != is_ready:
		update_lobby_status.rpc(peer_id, is_ready)
	
@rpc("authority", "call_local", "reliable")
func update_lobby_status(peer_id: int, is_ready: bool):
	print("update_lobby_status: " + str(is_ready))
	player_status[peer_id][GameDefines.READY] = is_ready
	players_updated.emit(player_status)

@rpc("authority", "call_local", "reliable")
func add_exist_players(exist_player_status: Dictionary):
	print("add_exist_players: " + str(exist_player_status))
	for peer_id in exist_player_status:
		player_status[peer_id] = exist_player_status[peer_id]
	players_updated.emit(player_status)
	
@rpc("authority", "call_local", "reliable")
func add_new_player(peer_id: int, new_player_info: Dictionary):
	print("add_new_player: " + str(new_player_info))
	player_status[peer_id] = new_player_info
	players_updated.emit(player_status)
	
# --- START GAME ---

func can_start_game() -> bool:
	if player_status.is_empty():
		return false
	for p in player_status.values():
		if not p[GameDefines.READY]:
			return false
	return true

func try_start_game() -> bool:
	if not multiplayer.is_server() || not can_start_game() || is_waiting_to_start: return false
	BroadcastManager.stop_send_message()
	
	is_waiting_to_start = true
	remaining_time_to_start = GameDefines.COOL_DOWN_START_GAME
	show_cool_down.rpc(remaining_time_to_start)
	timer.wait_time = 1
	timer.one_shot = false
	timer.timeout.connect(send_remaining_time)
	timer.start()

	return true

func send_remaining_time():
	remaining_time_to_start -= 1

	if remaining_time_to_start <= 0:
		start_game.rpc()
		timer.stop()
		is_waiting_to_start = false
	else:
		show_cool_down.rpc(remaining_time_to_start)
	
@rpc("authority", "call_local", "reliable")
func show_cool_down(cool_down: int):
	print("show_cool_down: " + str(cool_down))
	cool_down_trigged.emit(cool_down)

@rpc("authority", "call_local", "reliable")
func start_game():
	print("start_game")
	game_started.emit()
