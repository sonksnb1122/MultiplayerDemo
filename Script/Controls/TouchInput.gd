class_name TouchInput
extends RefCounted
## Turns a finger (ScreenTouch / ScreenDrag, one id per finger) or the mouse (left button, id
## MOUSE_ID) into one kind of pointer event, so the on-screen controls work with both and with
## several fingers at once. Mouse events Godot makes up from a touch are skipped (the touch
## itself is used).

const MOUSE_ID := -100
## No pointer
const NONE := -1000

const PRESS := 0
const RELEASE := 1
const MOVE := 2


## {} when the event is not a pointer event, otherwise {"id", "pos", "type"} (PRESS / RELEASE / MOVE)
static func parse(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		return {"id": event.index, "pos": event.position, "type": PRESS if event.pressed else RELEASE}
	if event is InputEventScreenDrag:
		return {"id": event.index, "pos": event.position, "type": MOVE}
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return {}
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return {"id": MOUSE_ID, "pos": event.position, "type": PRESS if event.pressed else RELEASE}
	if event is InputEventMouseMotion:
		return {"id": MOUSE_ID, "pos": event.position, "type": MOVE}
	return {}
