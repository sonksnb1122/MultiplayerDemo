class_name SkillBar
extends Control
## Skill bar for the local hero: one slot per skill with its key, name, colour and a cooldown
## overlay. Built in code. When added to the HUD's SkillArea it fills that area (under the hp
## bar); otherwise it sits in the bottom-right corner.

const SPACING := 8
const MARGIN := 16

var SLOT_SIZE := Vector2(86, 86)

var caster: SkillCaster
var _overlays: Array[ColorRect] = []
var _timers: Array[Label] = []
var _message: Label
var _message_tween: Tween


func setup(skill_caster: SkillCaster) -> void:
	caster = skill_caster
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := caster.skills.size()
	var width: float
	var parent_area := get_parent() as Control
	var embedded := parent_area != null and parent_area.name == "SkillArea"
	if embedded:
		var area_size := parent_area.size
		if area_size.x < 1.0 or area_size.y < 1.0:
			area_size = Vector2(parent_area.offset_right - parent_area.offset_left, parent_area.offset_bottom - parent_area.offset_top)
		width = area_size.x
		SLOT_SIZE = Vector2((area_size.x - (count - 1) * SPACING) / maxf(count, 1), area_size.y)
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0
		offset_right = 0
		offset_top = 0
		offset_bottom = 0
	else:
		width = count * SLOT_SIZE.x + (count - 1) * SPACING
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = -width - MARGIN
		offset_right = -MARGIN
		offset_top = -SLOT_SIZE.y - MARGIN
		offset_bottom = -MARGIN

	for i in count:
		_build_slot(i, caster.skills[i])

	_message = Label.new()
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Above the whole hero panel when embedded, above the slots otherwise
	_message.position = Vector2(0, -34 - (parent_area.position.y if embedded else 0.0))
	_message.size = Vector2(width, 28)
	_message.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	_message.add_theme_constant_override("outline_size", 6)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.modulate.a = 0.0
	add_child(_message)

	caster.cooldown_started.connect(_on_cooldown_started)
	caster.cast_failed.connect(_on_cast_failed)


func _build_slot(i: int, skill: SkillData) -> void:
	var slot := Panel.new()
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.tooltip_text = "%s [%s]\n%s\nHồi chiêu: %ds" % [skill.display_name, SkillCaster.KEY_LABELS[i], skill.description, int(skill.cooldown)]
	slot.position = Vector2(i * (SLOT_SIZE.x + SPACING), 0)
	slot.size = SLOT_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = skill.color.darkened(0.35)
	style.border_color = skill.color.lightened(0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	slot.add_theme_stylebox_override("panel", style)
	add_child(slot)

	var name_label := Label.new()
	name_label.text = skill.display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.position = Vector2(4, 22)
	name_label.size = Vector2(SLOT_SIZE.x - 8, SLOT_SIZE.y - 26)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(name_label)

	var key_label := Label.new()
	key_label.text = SkillCaster.KEY_LABELS[i]
	key_label.position = Vector2(7, 2)
	key_label.add_theme_font_size_override("font_size", 18)
	key_label.add_theme_constant_override("outline_size", 5)
	key_label.add_theme_color_override("font_outline_color", Color.BLACK)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(key_label)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.position = Vector2.ZERO
	overlay.size = SLOT_SIZE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	slot.add_child(overlay)
	_overlays.append(overlay)

	var timer_label := Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.size = SLOT_SIZE
	timer_label.add_theme_font_size_override("font_size", 28)
	timer_label.add_theme_constant_override("outline_size", 6)
	timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.visible = false
	slot.add_child(timer_label)
	_timers.append(timer_label)


func _process(_delta: float) -> void:
	if caster == null:
		return
	for i in _overlays.size():
		var left := caster.local_cooldown_left(i)
		var cooling := left > 0.0
		_overlays[i].visible = cooling
		_timers[i].visible = cooling
		if cooling:
			var total: float = maxf(caster.skills[i].cooldown, 0.01)
			# Overlay shrinks from the top as the skill comes back.
			var ratio := clampf(left / total, 0.0, 1.0)
			_overlays[i].size = Vector2(SLOT_SIZE.x, SLOT_SIZE.y * ratio)
			_overlays[i].position = Vector2(0, SLOT_SIZE.y * (1.0 - ratio))
			_timers[i].text = ("%.1f" % left) if left < 3.0 else str(ceili(left))


func _on_cooldown_started(_slot: int, _duration: float) -> void:
	pass  # _process reads the cooldown from the caster every frame


func _on_cast_failed(_slot: int, reason: String) -> void:
	_message.text = reason
	if _message_tween:
		_message_tween.kill()
	_message.modulate.a = 1.0
	_message_tween = create_tween()
	_message_tween.tween_interval(0.8)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.4)
