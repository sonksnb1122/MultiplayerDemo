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

func set_current_hp_details(value: int) -> void:
	detail_hp_bar.value = float(value)
	
func update_character_data_details(character_data: CharacterData) -> void:
	load_GUI()
	var tex = load(character_data.hero_avatar)
	detail_avatar.texture = tex
	#name
	detail_name_label.text = character_data.name
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
	# Just below the info panel (top-left corner), so it does not cover the hp bar / stats
	detail_status_label.position = Vector2(-50, 54)
	detail_status_label.text = bbcode
	detail_status_label.visible = not bbcode.is_empty()
