extends Control

signal back_to_main_menu
@onready var back_btn = $BackBtn
@onready var lobby_hub = $LobbyHub
@onready var room_scene = $RoomScene

@onready var rooms_list = $LobbyHub/Panel/LobbyAndRoom/RoomListTab/RoomList/List
@onready var room_manager = $RoomScene

var room_info_scene = preload("res://Scene/Lobby/RoomBtn.tscn")

var current_rooms: Dictionary = {}

func _ready() -> void:
	BroadcastManager.start_receiving_messages()
	BroadcastManager.on_update_room_info.connect(_on_rooms_updated)
	BroadcastManager.on_refresh_room_list.connect(_clear_room_list)
	
	# TODO: BroadcastManager.on_update_room_info.disconnect(_on_rooms_updated)
	
func _on_rooms_updated(rooms: Dictionary) -> void:
	refresh_list(rooms)

func _clear_room_list():
	for room in rooms_list.get_children():
		room.queue_free()
		
func refresh_list(rooms: Dictionary) -> void:
	current_rooms = rooms		
	for key in rooms.keys():	
		var room_info = rooms[key]
		var found_room = false
		for room_obj in rooms_list.get_children():
			if str(key) == room_obj.get_room_id():
				room_obj.set_room_info(room_info)
				found_room = true
				break
		if not found_room:
			var room_obj = room_info_scene.instantiate()
			rooms_list.add_child(room_obj)
			room_obj.set_room_info(room_info)
			room_obj.sig_join_room.connect(_on_join_room)

func _on_host_btn_pressed() -> void:
	if NetworkManager.create_room():
		print("Create room success")
		go_to_room_scene()	
	else:
		print("Create room fail")
		# TODO: show popup to notify the error

func _on_join_game_btn_pressed()-> void:
	for key in current_rooms.keys():
		var room_info = current_rooms[key]		
		NetworkManager.join_room(room_info.ip, room_info.port)
		go_to_room_scene()	
		break

func _on_join_room(address: String, port: int):
	if NetworkManager.join_room(address, port):
		go_to_room_scene()	
	else:
		print("Cannot join room!!!")

func go_to_room_scene():
	back_btn.visible = false
	lobby_hub.visible = false
	room_scene.visible = true
	room_scene.setup_scene()
	_clear_room_list()
	
func _on_room_scene_return_to_lobby() -> void:
	back_btn.visible = true
	lobby_hub.visible = true
	room_scene.visible = false
	BroadcastManager.start_receiving_messages()


func _on_quick_match_btn_pressed() -> void:
	pass

func _on_setting_btn_pressed() -> void:
	pass
	
func _on_back_btn_pressed() -> void:
	back_to_main_menu.emit()
