class_name CameraController
extends Camera3D

@onready var game_play = get_parent()

var drag_active = false

func _input(event: InputEvent) -> void:
	if PauseMenu.is_open:
		drag_active = false
		return
	if game_play.game_started:
		#process camera zoom in, zoom out
		if event.is_action("CameraZoomIn"):
			if fov < GameDefines.ZOOM_MAX :
				fov += GameDefines.ZOOM_STEP
		if event.is_action("CameraZoomOut"):
			if fov > GameDefines.ZOOM_MIN :
				fov -= GameDefines.ZOOM_STEP
		#process move camera by mouse
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT || event.button_index == MOUSE_BUTTON_MIDDLE:
				drag_active = event.pressed
		elif event is InputEventMouseMotion and drag_active:
			global_position.x += -event.relative.x * GameDefines.CAMERA_SPEED
			global_position.z += -event.relative.y * GameDefines.CAMERA_SPEED
func focus_to_me(pos: Vector3):
	var offset = 20.0
	global_position.x = pos.x
	#global_position.y = pos.y
	global_position.z = pos.z + offset
