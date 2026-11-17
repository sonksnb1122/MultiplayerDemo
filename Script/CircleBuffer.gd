extends RefCounted
class_name CircleBuffer

const CAPACITY = GameDefines.CIRCLE_BUFFER_SIZE 

var buffer: Array = []
var write_index: int = 0

func _init():
	buffer.resize(CAPACITY)
	for i in range(CAPACITY):
		buffer[i] = 0 

func push(new_value: int) -> void:
	buffer[write_index] = new_value
	write_index = (write_index + 1) % CAPACITY

func get_oldest(index: int) -> int:
	if index < 0 or index >= CAPACITY:
		return 0
		
	var actual_index = (write_index + index) % CAPACITY
	return buffer[actual_index]

func get_newest() -> int:
	var newest_index = (write_index - 1 + CAPACITY) % CAPACITY
	return buffer[newest_index]
	
	
