class_name OptionsMenu
extends CanvasLayer
## Options window (graphics and sound), built in code. Opened from the main menu and the pause
## menu with OptionsMenu.open(get_tree()). Every change applies at once and is saved
## (GraphicsSettings). Esc / "Done" closes it.

const FONT := preload("res://Asset/Art/UI/Fonts/RussoOne_Original.ttf")
const NODE_NAME := "OptionsMenu"

## Labels of GraphicsSettings.FPS_CHOICES
const FPS_LABELS := ["30 FPS", "60 FPS", "Unlimited"]

var _res_value: Label
var _sfx_value: Label
var _music_value: Label


## Opens the window (only one at a time)
static func open(tree: SceneTree) -> void:
	if tree == null or tree.root.get_node_or_null(NODE_NAME) != null:
		return
	var menu := OptionsMenu.new()
	menu.name = NODE_NAME
	tree.root.add_child(menu)


static func is_open(tree: SceneTree) -> bool:
	return tree != null and tree.root.get_node_or_null(NODE_NAME) != null


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _input(event: InputEvent) -> void:
	# Esc closes this window only (not the pause menu under it)
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	queue_free()


# ------------------------------------------------------------------ building

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)  # also blocks clicks to what is behind

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.97)
	style.border_color = Color(0.85, 0.7, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := _label("Options", 24, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	_section(grid, "Graphics")
	# Quality
	var quality := _option(["High", "Low"], 1 if GraphicsSettings.low_quality else 0)
	quality.tooltip_text = "Low: no shadows, no glow, lighter skill effects (F8)"
	quality.item_selected.connect(func(i: int) -> void: GraphicsSettings.set_low_quality(i == 1))
	_row(grid, "Quality", quality, null)
	# 3D resolution
	_res_value = _label("", 15, Color(1, 0.85, 0.4))
	var res := _slider(GraphicsSettings.MIN_RENDER_SCALE * 100.0, 100.0, 5.0, GraphicsSettings.render_scale * 100.0)
	res.tooltip_text = "Lower = less GPU work (the 3D scene is a bit softer, the UI stays sharp)"
	res.value_changed.connect(func(v: float) -> void:
		GraphicsSettings.set_render_scale(v / 100.0)
		_res_value.text = "%d%%" % int(v))
	_res_value.text = "%d%%" % int(res.value)
	_row(grid, "3D resolution", res, _res_value)
	# FPS limit
	var fps := _option(FPS_LABELS, maxi(GraphicsSettings.FPS_CHOICES.find(GraphicsSettings.max_fps), 0))
	fps.tooltip_text = "30 FPS saves the most GPU / battery"
	fps.item_selected.connect(func(i: int) -> void: GraphicsSettings.set_max_fps(GraphicsSettings.FPS_CHOICES[i]))
	_row(grid, "Max FPS", fps, null)

	_section(grid, "Sound")
	_sfx_value = _label("", 15, Color(1, 0.85, 0.4))
	var sfx := _slider(0.0, 100.0, 5.0, GraphicsSettings.sfx_volume * 100.0)
	sfx.value_changed.connect(func(v: float) -> void:
		GraphicsSettings.set_sfx_volume(v / 100.0)
		_sfx_value.text = "%d%%" % int(v))
	# A short sound when the slider is let go, to hear the new volume
	sfx.drag_ended.connect(func(_changed: bool) -> void: Sfx.play_ui(get_tree(), "click"))
	_sfx_value.text = "%d%%" % int(sfx.value)
	_row(grid, "Sound effects", sfx, _sfx_value)
	_music_value = _label("", 15, Color(1, 0.85, 0.4))
	var music := _slider(0.0, 100.0, 5.0, GraphicsSettings.music_volume * 100.0)
	music.value_changed.connect(func(v: float) -> void:
		GraphicsSettings.set_music_volume(v / 100.0)
		_music_value.text = "%d%%" % int(v))
	_music_value.text = "%d%%" % int(music.value)
	_row(grid, "Music", music, _music_value)

	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(160, 44)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.add_theme_font_override("font", FONT)
	done.add_theme_font_size_override("font_size", 18)
	done.pressed.connect(close)
	box.add_child(done)
	var hint := _label("ESC - Close", 12, Color(0.7, 0.7, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _section(grid: GridContainer, text: String) -> void:
	grid.add_child(_label(text, 18, Color(1, 0.85, 0.4)))
	grid.add_child(Control.new())
	grid.add_child(Control.new())


func _row(grid: GridContainer, title: String, control: Control, value_label: Label) -> void:
	grid.add_child(_label(title, 15, Color.WHITE))
	grid.add_child(control)
	grid.add_child(value_label if value_label != null else Control.new())


func _option(labels: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(220, 34)
	o.add_theme_font_override("font", FONT)
	o.add_theme_font_size_override("font_size", 15)
	for i in labels.size():
		o.add_item(str(labels[i]), i)
	o.select(selected)
	return o


func _slider(min_value: float, max_value: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.custom_minimum_size = Vector2(220, 30)
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s
