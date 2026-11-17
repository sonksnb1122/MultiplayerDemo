extends Control

signal return_to_lobby

@onready var player_list = $RoomHub/Panel/LobbyAndRoom/RoomList/Players/PlayerHub/PlayersCtn
@onready var boss_list = $RoomHub/Panel/LobbyAndRoom/RoomList/Players/BossHub/BossCtn
@onready var start_btn: Button = $RoomHub/Panel/LobbyAndRoom/RoomList/StartBtn
@onready var starting_label: Label = $StartingLabel

var player_info_scene = preload("res://Scene/Lobby/LobbyRoom/PlayerInRoom.tscn")

var select_hero_scene = preload("res://Scene/SelectHero/SelectHero.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	LobbyNetworkManager.players_updated.connect(_on_players_updated)
	LobbyNetworkManager.cool_down_trigged.connect(_on_pending_time_to_start)
	LobbyNetworkManager.game_started.connect(_on_start_game)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func setup_scene():
	starting_label.visible = false
	if not multiplayer.is_server():
		start_btn.text = GameDefines.READY

func _on_players_updated(players: Dictionary) -> void:
	refresh_players_in_room(players)

	
func refresh_players_in_room(players: Dictionary):
	for player in player_list.get_children():
		player.queue_free()
	for player in boss_list.get_children():
		player.queue_free()
		
	var is_player = true
	for key in players.keys():	
		var player_info = players[key]
		var player_obj = player_info_scene.instantiate()
		if is_player:
			player_list.add_child(player_obj)
			is_player = false
		else:
			boss_list.add_child(player_obj)		
			is_player = true
		var is_host = false
		if key == GameDefines.HOST_ID:
			is_host = true
		player_obj.set_player_info(player_info, is_host)

func _on_start_or_ready_btn_pressed() -> void:
	if multiplayer.is_server():
		LobbyNetworkManager.try_start_game()
	else:
		var is_ready =!LobbyNetworkManager.player_status[multiplayer.get_unique_id()][GameDefines.READY]
		LobbyNetworkManager.set_ready_status.rpc_id(GameDefines.HOST_ID, is_ready)
		if is_ready:
			start_btn.text = GameDefines.UNREADY
		else:
			start_btn.text = GameDefines.READY

func _on_pending_time_to_start(time: int):
	starting_label.visible = true
	starting_label.text = GameDefines.STARTING_IN_STR + str(time)

func _on_start_game():
	var scene = select_hero_scene.instantiate()
	get_tree().current_scene.queue_free()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	
func _on_invite_btn_pressed() -> void:
	pass

func _on_copy_btn_pressed() -> void:
	pass
	
func _on_back_btn_pressed() -> void:
	NetworkManager.quit_room()
	return_to_lobby.emit()
	
func _on_server_disconnected() -> void:
	BroadcastManager.refresh_room_list()
	return_to_lobby.emit()
	
func _on_connection_failed() -> void:
	return_to_lobby.emit()
