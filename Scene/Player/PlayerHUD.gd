class_name PlayerHUD

extends Control

var detail_hp_bar: Node
var detail_avatar: Node
var detail_name_label: Node
var detail_damage_label: Node
var detail_speed_label: Node

func load_GUI():
	detail_hp_bar = $Panel/hp_bar
	detail_avatar = $Panel/avatar
	detail_name_label = $Panel/name_label
	detail_damage_label = $Panel/Stats/damage_label
	detail_speed_label = $Panel/Stats/speed_label

## Where the skill bar (Q W E) is placed. null = its own spot in the bottom-right corner
func get_skill_area() -> Control:
	return get_node_or_null("Panel/SkillArea")

var _xp_bar: ProgressBar
var _hero_name := ""

## Level in the name, stats and max hp of the current level, XP bar (thin, under the hp bar)
func set_level(player) -> void:
	if detail_name_label == null:
		return
	if _hero_name.is_empty():
		_hero_name = detail_name_label.text
	detail_name_label.text = "%s  Lv.%d" % [_hero_name, player.level]
	detail_damage_label.text = "%d" % player.attack_damage()
	detail_hp_bar.max_value = float(player.max_hp())
	if _xp_bar == null:
		_xp_bar = ProgressBar.new()
		_xp_bar.show_percentage = false
		_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_xp_bar.position = Vector2(50, 30)
		_xp_bar.size = Vector2(100, 3)
		_xp_bar.custom_minimum_size = Vector2(0, 3)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.6)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(1, 0.8, 0.25)
		_xp_bar.add_theme_stylebox_override("background", bg)
		_xp_bar.add_theme_stylebox_override("fill", fill)
		$Panel.add_child(_xp_bar)
	var next: int = player.xp_for_next_level()
	if next <= 0:
		_xp_bar.value = 100.0  # max level
	else:
		var base: int = player.xp_for_this_level()
		_xp_bar.value = 100.0 * float(player.xp - base) / float(maxi(next - base, 1))

func set_current_hp_details(value: int) -> void:
	detail_hp_bar.value = float(value)
	
func update_character_data_details(character_data: CharacterData) -> void:
	load_GUI()
	var tex = load(character_data.hero_avatar)
	detail_avatar.texture = tex
	#name
	detail_name_label.text = character_data.name
	_hero_name = character_data.name
	detail_damage_label.text = "%d" % character_data.damage
	detail_speed_label.text =  "%d" % character_data.movement_speed
	#hp_bar
	detail_hp_bar.max_value = float(character_data.hp)
	detail_hp_bar.value = float(character_data.hp)

# --- Status (stun / slow / poison) next to the hero name ---

var detail_status_label: RichTextLabel

## [param bbcode]: coloured status words, "" to clear
func set_status(bbcode: String) -> void:
	if detail_name_label == null:
		return
	if detail_status_label == null:
		detail_status_label = RichTextLabel.new()
		detail_status_label.bbcode_enabled = true
		detail_status_label.fit_content = true
		detail_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		detail_status_label.scroll_active = false
		detail_status_label.clip_contents = false
		detail_status_label.custom_minimum_size = Vector2(320, 0)
		detail_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var font = detail_name_label.get_theme_font("font")
		if font != null:
			detail_status_label.add_theme_font_override("normal_font", font)
		detail_status_label.add_theme_font_size_override("normal_font_size", 14)
		detail_status_label.add_theme_constant_override("outline_size", 5)
		detail_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
		detail_name_label.add_child(detail_status_label)
	# Below the info panel, right of the pause and Auto buttons (under the avatar)
	detail_status_label.position = Vector2(32, 62)
	detail_status_label.text = bbcode
	detail_status_label.visible = not bbcode.is_empty()


# --- AUTO PLAY BUTTON ---

const AUTO_FONT := preload("res://Asset/Art/UI/Fonts/RussoOne_Original.ttf")
var _auto_button: Button
var _auto_player


## Round "Auto" button right of the pause button: the hero plays by itself (bot AI);
## moving with the joystick / arrow keys takes the control back
func add_auto_button(player) -> void:
	_auto_player = player
	_auto_button = Button.new()
	_auto_button.text = "Auto"
	_auto_button.focus_mode = Control.FOCUS_NONE
	_auto_button.position = Vector2(52, 66)
	_auto_button.size = Vector2(34, 34)
	_auto_button.tooltip_text = "Auto play: your hero fights by itself\nMove to take the control back"
	_auto_button.add_theme_font_override("font", AUTO_FONT)
	_auto_button.add_theme_font_size_override("font_size", 9)
	add_child(_auto_button)
	_auto_button.pressed.connect(func() -> void:
		if not PauseMenu.is_open and not MatchManager.is_over:
			_auto_player.request_auto.rpc_id(GameDefines.HOST_ID, not _auto_player.auto_enabled))
	player.auto_changed.connect(_on_auto_changed)
	_on_auto_changed(false)


func _on_auto_changed(on: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.45, 0.2, 0.9) if on else Color(0.06, 0.1, 0.13, 0.8)
	normal.border_color = Color(0.5, 1.0, 0.55) if on else Color(0.85, 0.7, 0.3, 0.9)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(17)
	normal.anti_aliasing = true
	_auto_button.add_theme_stylebox_override("normal", normal)
	_auto_button.add_theme_stylebox_override("hover", normal)
	_auto_button.add_theme_stylebox_override("pressed", normal)
	_auto_button.add_theme_color_override("font_color", Color(0.75, 1, 0.75) if on else Color.WHITE)
