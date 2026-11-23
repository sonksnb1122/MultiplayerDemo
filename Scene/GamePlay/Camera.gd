class_name CameraController
extends Camera3D

## Camera looks down at 45 degrees, about 21.2 units from the ground point it aims at
## (the y in GamePlay.tscn is the height: 21.2 * sin 45 = 15). It is locked on the local
## player's hero; FOCUS_DISTANCE is how far behind the hero it stands
## (15 would put the hero exactly in the middle, less keeps it a bit below the middle).
const HEIGHT := 15.0
const FOCUS_DISTANCE := 10.0

## Press on an empty part of the screen and drag to look around (the map follows the finger);
## let go and the camera glides back to the hero.
const DRAG_SPEED := 0.07
const MAX_PEEK := 30.0
const RETURN_SPEED := 7.0

@onready var game_play = get_parent()

## The local player's hero the camera follows (set by Player.gd through follow())
var _target: Node3D = null
## Look-around offset from the hero while dragging
var _peek := Vector3.ZERO
var _drag_pointer := TouchInput.NONE

# Shake (h/v offsets, so it doesn't fight with the camera position)
var _shake_strength := 0.0
var _shake_time := 0.0
var _shake_left := 0.0


## Lock the camera on [param hero] (the local player's hero)
func follow(hero: Node3D) -> void:
	_target = hero
	focus_to_me(hero.global_position)


## [param strength] in world units, fades out over [param duration] seconds
func shake(strength: float, duration: float) -> void:
	if _shake_left > 0.0 and _shake_strength * (_shake_left / maxf(_shake_time, 0.001)) > strength:
		return  # a stronger shake is already running
	_shake_strength = strength
	_shake_time = duration
	_shake_left = duration


## Only presses that no button / joystick / skill button took get here
func _unhandled_input(event: InputEvent) -> void:
	if PauseMenu.is_open or not game_play.game_started:
		_drag_pointer = TouchInput.NONE
		return
	var p := TouchInput.parse(event)
	if p.is_empty():
		return
	var id: int = p["id"]
	var type: int = p["type"]
	if type == TouchInput.PRESS:
		if _drag_pointer == TouchInput.NONE:
			_drag_pointer = id
	elif id == _drag_pointer:
		if type == TouchInput.RELEASE:
			_drag_pointer = TouchInput.NONE
		else:
			var rel: Vector2 = event.relative
			_peek.x -= rel.x * DRAG_SPEED
			_peek.z -= rel.y * DRAG_SPEED * 1.41  # the ground is seen at 45 degrees
			_peek = _peek.limit_length(MAX_PEEK)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_drag_pointer = TouchInput.NONE


func _process(delta: float) -> void:
	if _drag_pointer == TouchInput.NONE and _peek != Vector3.ZERO:
		_peek = _peek.lerp(Vector3.ZERO, 1.0 - exp(-RETURN_SPEED * delta))
		if _peek.length() < 0.02:
			_peek = Vector3.ZERO
	if is_instance_valid(_target):
		focus_to_me(_target.global_position)
	_update_shake(delta)


func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left -= delta
	if _shake_left <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		return
	var k := _shake_strength * (_shake_left / _shake_time)
	h_offset = randf_range(-k, k)
	v_offset = randf_range(-k, k)


func focus_to_me(pos: Vector3):
	global_position.x = pos.x + _peek.x
	global_position.y = HEIGHT
	global_position.z = pos.z + FOCUS_DISTANCE + _peek.z
