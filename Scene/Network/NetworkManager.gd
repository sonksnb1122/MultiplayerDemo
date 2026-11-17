extends Node

# signal for updating UI
signal peer_connected(peer_id: int) 
signal peer_disconnected(peer_id: int) 
signal connected_to_server
signal connection_failed
signal server_disconnected

signal new_player_joined(peer_id: int, player_name: String)
signal player_leaved(peer_id: int)

var room_name: String = ""
var room_port: int = 0
var max_players: int = GameDefines.MAX_PLAYER

var players: = {}
var player_authority_name: String

var disconnected_reason = GameDefines.DisconnectReason.NONE

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# clients only signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# authority player info
	player_authority_name = GameDefines.PLAYER_SUFFIX_STR + str(randi() % 1000)

func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	
func quit_room():
	player_leaved.emit(multiplayer.get_unique_id())
	BroadcastManager.refresh_room_list()
	if multiplayer.is_server():
		BroadcastManager.stop_send_message()
	remove_multiplayer_peer()

func is_mine(peer_id: int) -> bool:
	return peer_id == multiplayer.get_unique_id()
	
# --- HOST SIDE ---

func create_room():
	room_name = GameDefines.ROOM_SUFFIX_STR + str(randi() % 1000)
	
	var peer := ENetMultiplayerPeer.new()
	
	var err := peer.create_server(GameDefines.GAME_PORT, GameDefines.MAX_PLAYER - 1) # -1 because we already have 1 host
	if err != OK:
		push_error("Failed to host room on port %d: %s" % [GameDefines.GAME_PORT, err])
		return false

	multiplayer.multiplayer_peer = peer

	room_port = GameDefines.GAME_PORT
	players.clear()
	players[GameDefines.HOST_ID] = {
		GameDefines.NAME: player_authority_name,
	}
	
	new_player_joined.emit(GameDefines.HOST_ID, players[GameDefines.HOST_ID][GameDefines.NAME])
	
	var is_success = BroadcastManager.start_send_message(room_name, player_authority_name)
	return is_success	

func _on_peer_connected(id: int) -> void:
	print("_on_peer_connected")
	peer_connected.emit(id)
	
func _on_peer_disconnected(id: int) -> void:
	print("_on_peer_disconnected")
	peer_disconnected.emit(id)
	if multiplayer.is_server():
		var new_players = players.duplicate()
		new_players.erase(id)
		update_players.rpc(new_players)

# --- CLIENT SIDE ---

func join_room(address: String, port: int) -> bool:
	if address.is_empty() || port <= 0: return false
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error:
		return error

	multiplayer.multiplayer_peer = peer
	disconnected_reason = GameDefines.DisconnectReason.NONE
	return true

func _on_connected_to_server() -> void:
	print("_on_connected_to_server")
	connected_to_server.emit()
	request_register_player.rpc(player_authority_name)

func _on_connection_failed() -> void:
	print("_on_connection_failed")
	connection_failed.emit()
	remove_multiplayer_peer()

func _on_server_disconnected()-> void:
	print("_on_server_disconnected")
	server_disconnected.emit()
	remove_multiplayer_peer()
	disconnected_reason = GameDefines.DisconnectReason.HOST_CLOSED_ROOM

# --- RPC ---

@rpc("any_peer", "reliable")
func request_register_player(player_name: String) -> void:
	# call from client to server
	print("request_register_player")
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var new_players = players.duplicate()
	new_players[peer_id] = {GameDefines.NAME: player_name}
	update_players.rpc(new_players)

@rpc("authority", "reliable", "call_local")
func update_players(new_state: Dictionary) -> void:
	# call at all clients and server
	print("update_players")
	
	# Check for any one leaved
	var old_peer_ids = players.keys()
	for id in old_peer_ids:
		if not new_state.has(id): player_leaved.emit(id)
		
	# Check for any new one joined
	if multiplayer.is_server():
		var new_peer_ids = new_state.keys()
		for id in new_peer_ids:
			if not players.has(id): new_player_joined.emit(id, new_state[id][GameDefines.NAME])
	
	players = new_state


	
	
