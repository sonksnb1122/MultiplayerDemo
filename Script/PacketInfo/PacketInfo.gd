## BASECLASS ##

class_name PacketInfo

var stream = StreamPeerBuffer.new()

# Don't make values above 255, since we send "packet_type" as a single byte
enum PACKET_TYPE {
	BROADCAST_ROOM_INFO = 0,
}

var packet_type: PACKET_TYPE
var flag: int

# Override function in derived classes
func encode() -> PackedByteArray:
	stream.data_array = PackedByteArray()
	stream.seek(0)
	stream.put_8(packet_type)
	return stream.data_array

# Override function in derived classes
func decode(data: PackedByteArray) -> void:
	stream.data_array = data
	stream.seek(0)
	packet_type = stream.get_8()
