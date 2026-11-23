class_name SkillBar
extends Control
## Battle buttons of the local hero in the bottom-right corner, laid out like a mobile MOBA:
## a big basic-attack button, Q W E R on an arc around it, and a smaller Dash button on its
## lower left. Built in code.
##
## Press a skill button and drag away from it to aim (the range / area shows on the ground),
## let go to cast. A short tap aims at the closest enemy (or straight ahead). The attack button
## attacks the closest enemy (keep it held to keep picking a target). The keys still work:
## Q W E R Space aim with the mouse, A attacks.

## Size of the corner area holding the buttons
const AREA := Vector2(272, 232)
## Center of the attack button inside the area
const ATTACK_CENTER := Vector2(214, 170)
const ATTACK_SIZE := 78.0
## Per slot: [angle in degrees (0 = right, 90 = up), distance from the attack center, diameter]
const SLOT_LAYOUT := [
	[185.0, 104.0, 50.0],  # Q
	[148.0, 104.0, 50.0],  # W
	[112.0, 104.0, 50.0],  # E
	[76.0, 104.0, 50.0],   # R
	[208.0, 66.0, 38.0],   # Dash (smaller, lower left of the attack button)
]
## Dragging this far from the button aims at the full range
const AIM_DRAG_RADIUS := 70.0
const KEY_HEIGHT := 12
const ATTACK_SLOT := -1
const NO_SLOT := -2
## While the attack button is held, look for a target again this often
const ATTACK_REPEAT := 0.4
const ATTACK_ICON := "res://Asset/Art/UI/Generated/icon_swords.png"

var caster: SkillCaster
var _holders: Array[Control] = []
var _sizes: Array[Vector2] = []
var _overlays: Array[ColorRect] = []
var _timers: Array[Label] = []
var _locks: Array[Label] = []
var _attack_holder: Control
var _message: Label
var _message_tween: Tween
## Pointer id (finger / mouse) -> slot it pressed (ATTACK_SLOT for the attack button)
var _active := {}
var _attack_repeat_left := 0.0


func setup(skill_caster: SkillCaster) -> void:
	caster = skill_caster
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -AREA.x
	offset_top = -AREA.y
	offset_right = 0
	offset_bottom = 0

	_build_attack_button()
	for i in caster.skills.size():
		_build_slot(i, caster.skills[i])

	_message = Label.new()
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.position = Vector2(-60, -6)
	_message.size = Vector2(AREA.x, 28)
	_message.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	_message.add_theme_constant_override("outline_size", 6)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.modulate.a = 0.0
	add_child(_message)

	caster.cooldown_started.connect(_on_cooldown_started)
	caster.cast_failed.connect(_on_cast_failed)


# ---------------------------------------------------------------- building

func _slot_center(i: int) -> Vector2:
	var l: Array = SLOT_LAYOUT[mini(i, SLOT_LAYOUT.size() - 1)]
	var a := deg_to_rad(float(l[0]))
	return ATTACK_CENTER + Vector2(cos(a), -sin(a)) * float(l[1])


func _slot_diameter(i: int) -> float:
	return float(SLOT_LAYOUT[mini(i, SLOT_LAYOUT.size() - 1)][2])


## Box holding one round button (scaled from its center when pressed)
func _make_holder(center: Vector2, diameter: float) -> Control:
	var h := Control.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.size = Vector2(diameter, diameter)
	h.position = center - h.size / 2.0
	h.pivot_offset = h.size / 2.0
	add_child(h)
	return h


func _circle_style(fill: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


func _ring(parent: Control, size_px: Vector2, color: Color, width: int) -> void:
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = size_px
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = color
	style.set_border_width_all(width)
	style.set_corner_radius_all(int(size_px.x / 2.0) + 1)
	style.anti_aliasing = true
	ring.add_theme_stylebox_override("panel", style)
	parent.add_child(ring)


func _key_label(parent: Control, text: String, size_px: Vector2) -> void:
	var key_label := Label.new()
	key_label.text = text
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.position = Vector2(-8, size_px.y - 3)
	key_label.size = Vector2(size_px.x + 16, KEY_HEIGHT)
	key_label.add_theme_font_size_override("font_size", 9)
	key_label.add_theme_constant_override("outline_size", 3)
	key_label.add_theme_color_override("font_outline_color", Color.BLACK)
	key_label.modulate.a = 0.8
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(key_label)


func _build_attack_button() -> void:
	var d := ATTACK_SIZE
	var size_px := Vector2(d, d)
	_attack_holder = _make_holder(ATTACK_CENTER, d)
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_PASS
	bg.tooltip_text = "Attack [A]\nAttacks the closest enemy"
	bg.size = size_px
	bg.add_theme_stylebox_override("panel", _circle_style(Color(0.07, 0.11, 0.14, 0.82), int(d / 2.0) + 1))
	_attack_holder.add_child(bg)
	# Faint inner ring, then the sword
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.position = size_px * 0.14
	_attack_holder.add_child(inner)
	_ring(inner, size_px * 0.72, Color(0.45, 0.9, 0.95, 0.35), 2)
	if ResourceLoader.exists(ATTACK_ICON):
		var icon := TextureRect.new()
		icon.texture = load(ATTACK_ICON)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = size_px * 0.24
		icon.size = size_px * 0.52
		icon.modulate = Color(0.7, 0.95, 1.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_attack_holder.add_child(icon)
	_ring(_attack_holder, size_px, Color(0.95, 0.8, 0.4), 3)
	_key_label(_attack_holder, "A", size_px)


func _build_slot(i: int, skill: SkillData) -> void:
	var d := _slot_diameter(i)
	var size_px := Vector2(d, d)
	var holder := _make_holder(_slot_center(i), d)
	_holders.append(holder)
	_sizes.append(size_px)

	# Round slot: the background circle clips everything inside it (icon, cooldown shade)
	var slot := Panel.new()
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.tooltip_text = "%s [%s]\n%s\nCooldown: %ds" % [skill.display_name, SkillCaster.KEY_LABELS[i], skill.description, int(skill.cooldown)]
	slot.size = size_px
	slot.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	slot.add_theme_stylebox_override("panel", _circle_style(skill.color.darkened(0.35), int(d / 2.0) + 1))
	holder.add_child(slot)

	var icon_tex: Texture2D = load(skill.icon) if not skill.icon.is_empty() and ResourceLoader.exists(skill.icon) else null
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.size = size_px
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
	else:
		# No icon: the first letter of the skill
		var letter := Label.new()
		letter.text = skill.display_name.left(1)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.size = size_px
		letter.add_theme_font_size_override("font_size", 16)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(letter)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.size = size_px
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	slot.add_child(overlay)
	_overlays.append(overlay)

	var timer_label := Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.size = size_px
	timer_label.add_theme_font_size_override("font_size", 14)
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
	lock.size = size_px
	lock.add_theme_font_size_override("font_size", 12)
	lock.add_theme_constant_override("outline_size", 3)
	lock.add_theme_color_override("font_outline_color", Color.BLACK)
	lock.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.visible = false
	slot.add_child(lock)
	_locks.append(lock)

	# Ring in the skill's color, drawn over the icon (outside the clipping slot)
	_ring(holder, size_px, skill.color.lightened(0.3), 2)
	_key_label(holder, SkillCaster.KEY_LABELS[i], size_px)


# ---------------------------------------------------------------- input

func _holder_of(slot: int) -> Control:
	return _attack_holder if slot == ATTACK_SLOT else _holders[slot]


func _center_of(slot: int) -> Vector2:
	return _holder_of(slot).get_global_rect().get_center()


## Button under [param pos] (screen), NO_SLOT if none
func _slot_at(pos: Vector2) -> int:
	var best := NO_SLOT
	var best_dist := INF
	var candidates: Array[int] = [ATTACK_SLOT]
	for i in _holders.size():
		candidates.append(i)
	for slot in candidates:
		var holder := _holder_of(slot)
		var d := pos.distance_to(_center_of(slot))
		if d <= holder.size.x / 2.0 + 4.0 and d < best_dist:
			best = slot
			best_dist = d
	return best


func _input(event: InputEvent) -> void:
	if caster == null or not is_visible_in_tree():
		return
	var p := TouchInput.parse(event)
	if p.is_empty():
		return
	var id: int = p["id"]
	var pos: Vector2 = p["pos"]
	var type: int = p["type"]
	if type == TouchInput.PRESS:
		if _active.has(id):
			return
		var slot := _slot_at(pos)
		if slot == NO_SLOT:
			return
		get_viewport().set_input_as_handled()
		if not caster.can_take_input():
			return
		_active[id] = slot
		_set_pressed(slot, true)
		if slot == ATTACK_SLOT:
			_attack_repeat_left = ATTACK_REPEAT
			caster.player.attack_nearest()
		else:
			caster.touch_press(slot)
	elif _active.has(id):
		get_viewport().set_input_as_handled()
		var slot: int = _active[id]
		if type == TouchInput.MOVE:
			if slot >= 0:
				caster.touch_drag(slot, (pos - _center_of(slot)) / AIM_DRAG_RADIUS)
		else:
			_active.erase(id)
			_set_pressed(slot, false)
			if slot >= 0:
				caster.touch_release(slot)


func _set_pressed(slot: int, pressed: bool) -> void:
	var holder := _holder_of(slot)
	holder.scale = Vector2.ONE * (0.9 if pressed else 1.0)
	holder.modulate = Color(1.25, 1.25, 1.25) if pressed else Color.WHITE


## Let go of every button without casting (menu opened, hero died, match over...)
func _release_all() -> void:
	for id in _active.keys():
		_set_pressed(_active[id], false)
	_active.clear()
	caster.cancel_aim()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and caster != null and not _active.is_empty():
		_release_all()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if caster == null:
		return
	if not _active.is_empty():
		if not caster.can_take_input():
			_release_all()
		elif ATTACK_SLOT in _active.values():
			_attack_repeat_left -= delta
			if _attack_repeat_left <= 0.0:
				_attack_repeat_left = ATTACK_REPEAT
				caster.player.attack_nearest(false)
	for i in _overlays.size():
		var size_px := _sizes[i]
		if not caster.is_unlocked(i):
			_overlays[i].visible = true
			_overlays[i].size = size_px
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
			# Shade shrinks from the top as the skill comes back
			var ratio := clampf(left / total, 0.0, 1.0)
			_overlays[i].size = Vector2(size_px.x, size_px.y * ratio)
			_overlays[i].position = Vector2(0, size_px.y * (1.0 - ratio))
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
