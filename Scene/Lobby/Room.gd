extends Button

signal sig_join_room(address: String, port: int)

@onready var room_name_text: Label = $RoomInfo/RoomNameLb
@onready var host_name_text: Label = $RoomInfo/HostLb
@onready var players_text: Label = $RoomInfo/PlayersLb
@onready var ping_text: Label = $RoomInfo/PingLb
@onready var status_text: Label = $RoomInfo/StatusLb
@onready var locked_text: Label = $RoomInfo/LockLb

var ip = "localhost"
var port = GameDefines.GAME_PORT

func _on_pressed() -> void:
	sig_join_room.emit(ip, port)

func get_room_id()-> String:
	return "%s:%s" % [ip, port]
	
func set_room_info(room_info: BroadcastRoomInfo):
	ip = room_info.ip
	port = room_info.port
	room_name_text.text = room_info.room_name
	host_name_text.text = room_info.host_name
	players_text.text = "%s/%s" % [room_info.players, room_info.max_players]
	ping_text.text = str(room_info.ping)
	status_text.text = str(room_info.status)
