class_name SkillBar
extends Control
## Skill bar for the local hero: one slot per skill with its key, name, colour and a cooldown
## overlay. Built in code. When added to the HUD's SkillArea it fills that area (under the hp
## bar); otherwise it sits in the bottom-right corner.

const SPACING := 8
const MARGIN := 16
## Room under each round slot for its key (Q, W, E, R, SPC)
const KEY_HEIGHT := 14

## Round slots, a third of the old 86 px squares
var SLOT_SIZE := Vector2(29, 29)

var caster: SkillCaster
var _overlays: Array[ColorRect] = []
var _timers: Array[Label] = []
var _locks: Array[Label] = []
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
		offset_top = -SLOT_SIZE.y - KEY_HEIGHT - MARGIN
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
	var radius := int(SLOT_SIZE.x / 2.0) + 1
	# Round slot: the background circle clips everything inside it (icon, cooldown shade)
	var slot := Panel.new()
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.tooltip_text = "%s [%s]\n%s\nHồi chiêu: %ds" % [skill.display_name, SkillCaster.KEY_LABELS[i], skill.description, int(skill.cooldown)]
	slot.position = Vector2(i * (SLOT_SIZE.x + SPACING), 0)
	slot.size = SLOT_SIZE
	slot.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var style := StyleBoxFlat.new()
	style.bg_color = skill.color.darkened(0.35)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	slot.add_theme_stylebox_override("panel", style)
	add_child(slot)

	var icon_tex: Texture2D = load(skill.icon) if not skill.icon.is_empty() and ResourceLoader.exists(skill.icon) else null
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.position = Vector2.ZERO
		icon.size = SLOT_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
	else:
		# No icon: the first letter of the skill
		var letter := Label.new()
		letter.text = skill.display_name.left(1)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.size = SLOT_SIZE
		letter.add_theme_font_size_override("font_size", 14)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(letter)

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
	timer_label.add_theme_font_size_override("font_size", 12)
	timer_label.add_theme_constant_override("outline_size", 4)
	timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.visible = false
	slot.add_child(timer_label)
	_timers.append(timer_label)

	# Locked ultimate: dark with the level it needs
	var lock := Label.new()
	lock.text = "Lv%d" % GameDefines.ULTIMATE_LEVEL
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock.size = SLOT_SIZE
	lock.add_theme_font_size_override("font_size", 10)
	lock.add_theme_constant_override("outline_size", 3)
	lock.add_theme_color_override("font_outline_color", Color.BLACK)
	lock.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.visible = false
	slot.add_child(lock)
	_locks.append(lock)

	# Ring in the skill's color, drawn over the icon (outside the clipping slot)
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = slot.position
	ring.size = SLOT_SIZE
	var ring_style := StyleBoxFlat.new()
	ring_style.draw_center = false
	ring_style.border_color = skill.color.lightened(0.3)
	ring_style.set_border_width_all(2)
	ring_style.set_corner_radius_all(radius)
	ring_style.anti_aliasing = true
	ring.add_theme_stylebox_override("panel", ring_style)
	add_child(ring)

	# Key under the circle
	var key_label := Label.new()
	key_label.text = SkillCaster.KEY_LABELS[i]
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.position = Vector2(slot.position.x - 6, SLOT_SIZE.y)
	key_label.size = Vector2(SLOT_SIZE.x + 12, KEY_HEIGHT)
	key_label.add_theme_font_size_override("font_size", 10)
	key_label.add_theme_constant_override("outline_size", 3)
	key_label.add_theme_color_override("font_outline_color", Color.BLACK)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(key_label)


func _process(_delta: float) -> void:
	if caster == null:
		return
	for i in _overlays.size():
		if not caster.is_unlocked(i):
			_overlays[i].visible = true
			_overlays[i].size = SLOT_SIZE
			_overlays[i].position = Vector2.ZERO
			_timers[i].visible = false
			_locks[i].visible = true
			continue
		_locks[i].visible = false
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
			_timers[i].text = ("%.1f" % left) if left < 1.0 else str(ceili(left))


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
