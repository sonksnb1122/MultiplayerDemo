extends Node
## Autoload.
## - Menus (Main menu, Lobby, Room) are plain 2D screens that rarely change, so there the engine
##   only redraws when something on screen changes (low processor mode). Hero select and the
##   match (3D scenes) render normally.
## - F9 toggles "recording mode" for OBS: 30 FPS and the 3D scene drawn at a lower resolution
##   (UI stays sharp), which frees the GPU for OBS.
## - F8 toggles "low graphics" (saved): no shadows, no glow and the 3D scene drawn at 75%
##   resolution, for weak GPUs / laptops. UI stays sharp.

const RECORDING_TOGGLE_KEY := KEY_F9
const RECORDING_FPS := 30
const RECORDING_3D_SCALE := 0.7
const QUALITY_TOGGLE_KEY := KEY_F8
const LOW_3D_SCALE := 0.75
const SETTINGS_PATH := "user://graphics.cfg"

var low_quality := false

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
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		low_quality = bool(cfg.get_value("graphics", "low_quality", false))
	_apply_3d_scale()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == _last_scene:
		return
	_last_scene = scene
	OS.low_processor_usage_mode = scene != null and not (scene is Node3D)
	_apply_quality(scene)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == RECORDING_TOGGLE_KEY:
		set_recording_mode(not recording_mode)
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.physical_keycode == QUALITY_TOGGLE_KEY:
		set_low_quality(not low_quality)
		get_viewport().set_input_as_handled()


func set_recording_mode(on: bool) -> void:
	recording_mode = on
	Engine.max_fps = RECORDING_FPS if on else _normal_fps
	_apply_3d_scale()
	# Short notice only, so it doesn't end up in the recording
	_show_notice("Recording mode: ON (30 FPS, F9 to turn off)" if on else "Recording mode: OFF")


func set_low_quality(on: bool) -> void:
	low_quality = on
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "low_quality", on)
	cfg.save(SETTINGS_PATH)
	_apply_quality(get_tree().current_scene)
	_show_notice("Low graphics: ON (F8 to turn off)" if on else "Low graphics: OFF")


## 3D resolution: recording mode, else low graphics, else full
func _apply_3d_scale() -> void:
	var vp := get_tree().root
	var s := RECORDING_3D_SCALE if recording_mode else (LOW_3D_SCALE if low_quality else 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s


## Shadows of the sun light(s) and glow of the scene off in low graphics (the scene's own values
## are kept in a meta, to put back exactly when it is turned off)
func _apply_quality(scene: Node) -> void:
	_apply_3d_scale()
	if scene == null:
		return
	for node in scene.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if not light.has_meta("gs_shadow"):
			light.set_meta("gs_shadow", light.shadow_enabled)
		light.shadow_enabled = bool(light.get_meta("gs_shadow")) and not low_quality
	for node in scene.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null:
			continue
		if not env.has_meta("gs_glow"):
			env.set_meta("gs_glow", env.glow_enabled)
		env.glow_enabled = bool(env.get_meta("gs_glow")) and not low_quality


func _show_notice(text: String) -> void:
	_indicator.text = text
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
