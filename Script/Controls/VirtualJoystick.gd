class_name VirtualJoystick
extends Control
## On-screen joystick in the bottom-left corner. Touch / click inside it and drag:
## [member direction] is the way to walk (screen right = +x, screen up = -y), length 0..1.
## The hero walks at full speed in that direction (Player reads it every frame).

const RADIUS := 58.0
const KNOB_RADIUS := 24.0
## A press this far from the center still grabs the stick (a bit bigger than the circle)
const GRAB_RADIUS := 92.0
const DEAD_ZONE := 0.18
const MARGIN := 26.0
const ACCENT := Color(0.35, 0.95, 0.95, 0.95)

var direction := Vector2.ZERO

var _pointer := TouchInput.NONE
## Knob offset from the center, in pixels
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := RADIUS * 2.0 + 16.0
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = MARGIN
	offset_right = MARGIN + side
	offset_top = -MARGIN - side
	offset_bottom = -MARGIN


func _center_global() -> Vector2:
	return get_global_rect().get_center()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if PauseMenu.is_open or MatchManager.is_over:
		if _pointer != TouchInput.NONE:
			_release()
		return
	var p := TouchInput.parse(event)
	if p.is_empty():
		return
	var id: int = p["id"]
	var pos: Vector2 = p["pos"]
	var type: int = p["type"]
	if type == TouchInput.PRESS:
		if _pointer == TouchInput.NONE and pos.distance_to(_center_global()) <= GRAB_RADIUS:
			_pointer = id
			_move_knob(pos)
			get_viewport().set_input_as_handled()
	elif id == _pointer:
		get_viewport().set_input_as_handled()
		if type == TouchInput.MOVE:
			_move_knob(pos)
		else:
			_release()


func _move_knob(pos: Vector2) -> void:
	_knob = (pos - _center_global()).limit_length(RADIUS)
	var n := _knob / RADIUS
	direction = n if n.length() > DEAD_ZONE else Vector2.ZERO
	queue_redraw()


func _release() -> void:
	_pointer = TouchInput.NONE
	_knob = Vector2.ZERO
	direction = Vector2.ZERO
	queue_redraw()


func _notification(what: int) -> void:
	# Window lost focus: let go of the stick (its release would never come)
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _pointer != TouchInput.NONE:
		_release()


func _draw() -> void:
	var c := size / 2.0
	var active := _pointer != TouchInput.NONE
	# Base: dark see-through disc with a light rim and a faint inner ring
	draw_circle(c, RADIUS, Color(0.04, 0.09, 0.1, 0.38))
	draw_arc(c, RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.4), 2.0, true)
	draw_arc(c, RADIUS * 0.6, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 1.5, true)
	# Glowing arc on the rim toward where the hero walks
	if direction != Vector2.ZERO:
		var a := direction.angle()
		draw_arc(c, RADIUS + 3.0, a - 0.6, a + 0.6, 24, ACCENT, 4.0, true)
	# Knob
	var k := c + _knob
	draw_circle(k, KNOB_RADIUS, Color(1, 1, 1, 0.42 if active else 0.26))
	draw_arc(k, KNOB_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.7 if active else 0.45), 2.0, true)
