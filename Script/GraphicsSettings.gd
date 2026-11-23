extends Node
## Autoload: the player's settings (graphics + sound), saved in user://graphics.cfg and changed
## in the Options menu (main menu / pause menu).
## - Menus (Main menu, Lobby, Room) are plain 2D screens that rarely change, so there the engine
##   only redraws when something on screen changes (low processor mode). Hero select and the
##   match (3D scenes) render normally.
## - Quality "Low" (also F8): no shadows, no glow, effects without lights and with half the
##   particles, 3D drawn at 75% at most.
## - 3D resolution: the 3D scene drawn smaller and stretched (UI stays sharp): less GPU work.
## - F9 toggles "recording mode" for OBS: 30 FPS and the 3D scene drawn at 70%.
## - Sound: own buses "SFX" (Sfx, skill effects) and "Music" (menu music) under Master.

const RECORDING_TOGGLE_KEY := KEY_F9
const RECORDING_FPS := 30
const RECORDING_3D_SCALE := 0.7
const QUALITY_TOGGLE_KEY := KEY_F8
const LOW_3D_SCALE := 0.75
const SETTINGS_PATH := "user://graphics.cfg"
const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
## Choices of the Options menu
const FPS_CHOICES := [30, 60, 0]  # 0 = no limit
const MIN_RENDER_SCALE := 0.5

var low_quality := false
## 3D resolution, 0.5..1.0
var render_scale := 1.0
var max_fps := 60
## 0..1
var sfx_volume := 1.0
var music_volume := 1.0

var recording_mode := false

var _last_scene: Node = null
var _layer: CanvasLayer
var _indicator: Label
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_indicator()
	_make_bus(SFX_BUS)
	_make_bus(MUSIC_BUS)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		low_quality = bool(cfg.get_value("graphics", "low_quality", false))
		render_scale = clampf(float(cfg.get_value("graphics", "render_scale", 1.0)), MIN_RENDER_SCALE, 1.0)
		var fps := int(cfg.get_value("graphics", "max_fps", 60))
		max_fps = fps if FPS_CHOICES.has(fps) else 60
		sfx_volume = clampf(float(cfg.get_value("sound", "sfx_volume", 1.0)), 0.0, 1.0)
		music_volume = clampf(float(cfg.get_value("sound", "music_volume", 1.0)), 0.0, 1.0)
	_apply_fps()
	_apply_3d_scale()
	_apply_volumes()


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
		_show_notice("Low graphics: ON (F8 to turn off)" if low_quality else "Low graphics: OFF")
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ setters (Options menu)

func set_recording_mode(on: bool) -> void:
	recording_mode = on
	_apply_fps()
	_apply_3d_scale()
	# Short notice only, so it doesn't end up in the recording
	_show_notice("Recording mode: ON (30 FPS, F9 to turn off)" if on else "Recording mode: OFF")


func set_low_quality(on: bool) -> void:
	low_quality = on
	_save()
	_apply_quality(get_tree().current_scene)


func set_render_scale(value: float) -> void:
	render_scale = clampf(value, MIN_RENDER_SCALE, 1.0)
	_save()
	_apply_3d_scale()


func set_max_fps(value: int) -> void:
	max_fps = value if FPS_CHOICES.has(value) else 60
	_save()
	_apply_fps()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_save()
	_apply_volumes()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_save()
	_apply_volumes()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "low_quality", low_quality)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "max_fps", max_fps)
	cfg.set_value("sound", "sfx_volume", sfx_volume)
	cfg.set_value("sound", "music_volume", music_volume)
	cfg.save(SETTINGS_PATH)


# ------------------------------------------------------------------ applying

func _apply_fps() -> void:
	Engine.max_fps = RECORDING_FPS if recording_mode else max_fps


## 3D resolution: recording mode, else the chosen one (at most 75% in low graphics)
func _apply_3d_scale() -> void:
	var vp := get_tree().root
	var s := render_scale
	if low_quality:
		s = minf(s, LOW_3D_SCALE)
	if recording_mode:
		s = RECORDING_3D_SCALE
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


func _make_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")


func _apply_volumes() -> void:
	for pair in [[SFX_BUS, sfx_volume], [MUSIC_BUS, music_volume]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index < 0:
			continue
		var v: float = pair[1]
		AudioServer.set_bus_mute(index, v <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.001)))


# ------------------------------------------------------------------ notice

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
