extends Node
## Autoload.
## - Menus (Main menu, Lobby, Room) are plain 2D screens that rarely change, so there the engine
##   only redraws when something on screen changes (low processor mode). Hero select and the
##   match (3D scenes) render normally.
## - F9 toggles "recording mode" for OBS: 30 FPS and the 3D scene drawn at a lower resolution
##   (UI stays sharp), which frees the GPU for OBS.

const RECORDING_TOGGLE_KEY := KEY_F9
const RECORDING_FPS := 30
const RECORDING_3D_SCALE := 0.7

var recording_mode := false

var _normal_fps := 0
var _last_scene: Node = null
var _layer: CanvasLayer
var _indicator: Label
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_normal_fps = Engine.max_fps
	_build_indicator()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == _last_scene:
		return
	_last_scene = scene
	OS.low_processor_usage_mode = scene != null and not (scene is Node3D)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == RECORDING_TOGGLE_KEY:
		set_recording_mode(not recording_mode)
		get_viewport().set_input_as_handled()


func set_recording_mode(on: bool) -> void:
	recording_mode = on
	var vp := get_tree().root
	if on:
		Engine.max_fps = RECORDING_FPS
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = RECORDING_3D_SCALE
	else:
		Engine.max_fps = _normal_fps
		vp.scaling_3d_scale = 1.0
	# Short notice only, so it doesn't end up in the recording
	_indicator.text = "Recording mode: ON (30 FPS, F9 to turn off)" if on else "Recording mode: OFF"
	_indicator.visible = true
	_indicator.modulate.a = 1.0
	if _tween != null:
		_tween.kill()
	_tween = _indicator.create_tween()
	_tween.tween_interval(1.5)
	_tween.tween_property(_indicator, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(func() -> void: _indicator.visible = false)


func _build_indicator() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_indicator = Label.new()
	_indicator.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_indicator.add_theme_color_override("font_outline_color", Color.BLACK)
	_indicator.add_theme_constant_override("outline_size", 4)
	_indicator.add_theme_font_size_override("font_size", 14)
	_indicator.position = Vector2(8, 6)
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator.visible = false
	_layer.add_child(_indicator)
