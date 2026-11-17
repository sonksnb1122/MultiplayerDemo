class_name BroadcastRoomInfo extends PacketInfo

var ip: String = "localhost"
var port: int = GameDefines.GAME_PORT

var room_name: String = "Unnamed"
var host_name: String= "Rad"
var players: int = 1
var max_players: int = 4
var ping: int = 0
var status: int = 1
var closed: bool = false

static func create(ip: String, port: int, room_name: String, host_name: String, players: int, max_players: int, ping: int, status: int, closed: bool) -> BroadcastRoomInfo:
	var info: BroadcastRoomInfo = BroadcastRoomInfo.new()
	info.ip = ip
	info.port = port
	info.room_name = room_name
	info.host_name = host_name
	info.players = players
	info.max_players = max_players
	info.ping = ping
	info.status = status
	info.closed = closed
	info.flag = ENetPacketPeer.FLAG_RELIABLE
	return info

static func create_from_data(data: PackedByteArray) -> BroadcastRoomInfo:
	var info: BroadcastRoomInfo = BroadcastRoomInfo.new()
	info.decode(data)
	return info

func encode() -> PackedByteArray:
	super.encode()
	stream.put_string(ip)
	stream.put_string(str(port))
	stream.put_string(room_name)
	stream.put_string(host_name)
	stream.put_8(players)
	stream.put_8(max_players)
	stream.put_8(ping)
	stream.put_8(status)
	stream.put_8(closed)
	return stream.data_array

func decode(data: PackedByteArray) -> void:
	super.decode(data)
	ip = stream.get_string()
	port = int(stream.get_string())
	room_name = stream.get_string()
	host_name = stream.get_string()
	players = stream.get_8()
	max_players = stream.get_8()
	ping = stream.get_8()
	status = stream.get_8()
	closed = stream.get_8()
