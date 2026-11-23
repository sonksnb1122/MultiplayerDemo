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
	# Below the info panel, right of the pause button (which sits under the avatar)
	detail_status_label.position = Vector2(-8, 62)
	detail_status_label.text = bbcode
	detail_status_label.visible = not bbcode.is_empty()
