extends Node

signal on_update_room_info(room_info: BroadcastRoomInfo)
signal on_refresh_room_list

@onready var broadcast_timer: Timer = $BroadcastTimer

var sender_socket: PacketPeerUDP
var receiver_socket: PacketPeerUDP

var is_sending: bool = false
var is_recieving: bool = false

var rooms: = {}
var rooms_num_tried := {} # use to close room after not found info in NUM_TRIED receiving packetss

func _ready() -> void:
	broadcast_timer.start()
	broadcast_timer.wait_time = GameDefines.BROADCAST_INTERVAL
	broadcast_timer.timeout.connect(update_broadcast)
	
func update_broadcast():
	if is_sending: broadcast_message()
	if is_recieving: check_packets()
	
func _get_lan_ip() -> String:
	for a in IP.get_local_addresses():
		if a == "127.0.0.1":
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"
	
# --- SENDER ---

func start_send_message(room_name: String, host_name: String) -> bool:
	print("Start broadcast message room info ...")
	sender_socket = PacketPeerUDP.new()
	if sender_socket.has_method("set_reuse_address_enabled"): sender_socket.set_reuse_address_enabled(true)
	if sender_socket.has_method("set_reuse_port_enabled"): sender_socket.set_reuse_port_enabled(true)
	sender_socket.set_broadcast_enabled(true)
	var err := sender_socket.set_dest_address(GameDefines.BROADCAST_ADDRESS, GameDefines.BROADCAST_PORT)
	if err != OK:
		push_error("Couldn't set broadcasting at port %d: %s" % [GameDefines.BROADCAST_PORT, err])

	self.set_meta("room_name", room_name)
	self.set_meta("host_name", host_name)
	self.set_meta("room_port", GameDefines.GAME_PORT)
	# Cache in metadata (so we don't pass around args each time)
	
	if err == OK:
		is_sending = true
	return is_sending

func broadcast_message() -> void:
	if not is_sending: return
	
	var ip := _get_lan_ip()
	var room_name: String = self.get_meta("room_name")
	var host_name: String = self.get_meta("host_name")
	var room_port: int = int(self.get_meta("room_port"))
	
	var packetInfo := BroadcastRoomInfo.create(ip, room_port, room_name, host_name, NetworkManager.players.size(), NetworkManager.max_players, 0, 1, false)
	var packet := packetInfo.encode()
	sender_socket.put_packet(packet)
	
func stop_send_message():
	print("Stop broadcast message room info ...")
	if is_sending:
		# notify close room
		print("Broadcast last message notify clients about closing room")
		var ip := _get_lan_ip()
		var room_name: String = self.get_meta("room_name")
		var host_name: String = self.get_meta("host_name")
		var room_port: int = int(self.get_meta("room_port"))
		
		var packetInfo := BroadcastRoomInfo.create(ip, room_port, room_name, host_name, NetworkManager.players.size(), NetworkManager.max_players, 0, 1, true)
		var packet := packetInfo.encode()
		if sender_socket.put_packet(packet) == OK:
			# close socket
			is_sending = false
			sender_socket.set_broadcast_enabled(false)
			sender_socket.close()

# --- RECEIVER ---

func start_receiving_messages() -> bool:
	print("Start receiving broadcast messages ...")
	receiver_socket = PacketPeerUDP.new()
	if receiver_socket.has_method("set_reuse_address_enabled"): receiver_socket.set_reuse_address_enabled(true)
	if receiver_socket.has_method("set_reuse_port_enabled"): receiver_socket.set_reuse_port_enabled(true)
	var bind_err := receiver_socket.bind(GameDefines.BROADCAST_PORT)
	
	if bind_err == OK:
		is_recieving = true;
	else:
		push_warning("Couldn't bind lan broadcast listener")
	return is_recieving

func check_packets() -> void:
	var room_ids = rooms_num_tried.keys()
	for id in room_ids:
		rooms_num_tried[id] = rooms_num_tried[id] - 1
	
	if not is_recieving: return
	while receiver_socket.get_available_packet_count() > 0:
		var server_ip := receiver_socket.get_packet_ip()
		var port := receiver_socket.get_packet_port()
		var bytes := receiver_socket.get_packet()
		var room_info := BroadcastRoomInfo.create_from_data(bytes)
		
		if server_ip != '' and port > 0:
			_handle_discovered_room(room_info)
		
	for id in room_ids:
		if rooms.has(id) && rooms_num_tried.has(id) && rooms_num_tried[id] == 0:
			print("Close room: " + id + " because not found room for " + str(GameDefines.BROADCAST_NUM_TRIED) + " tried")
			close_room(id)
			
	on_update_room_info.emit(rooms)

func _handle_discovered_room(roomInfo: BroadcastRoomInfo) -> void:
	if roomInfo == null:
		return
		
	var key := "%s:%d" % [roomInfo.ip, roomInfo.port]
	if roomInfo.closed:
		close_room(key)
	else:
		rooms[key] = roomInfo
		rooms_num_tried[key] = GameDefines.BROADCAST_NUM_TRIED

func close_room(id: String):
	rooms.erase(id)
	rooms_num_tried.erase(id)
	on_refresh_room_list.emit()

func refresh_room_list():
	rooms = {}
	rooms_num_tried = {}
	on_refresh_room_list.emit()
	
func stop_receiving_messages():
	print("Stop listening broadcast messages...")
	if is_recieving:
		is_recieving = false
		receiver_socket.close()
		rooms = {}
		rooms_num_tried = {}
		on_update_room_info.emit(rooms)
