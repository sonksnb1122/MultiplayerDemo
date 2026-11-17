class_name StatusEffects
extends Node
## Buffs and debuffs of one hero (child of Player, named "StatusEffects" on every peer).
## The server owns all timers and numbers; whenever the visible state changes it sends a
## small dictionary to every peer, which shows the matching VFX and status text.

signal state_changed(state: Dictionary)

const SHIELD_VFX := "res://addons/emberset/effects/shield/bubble_shock.tscn"
const SLOW_VFX := "res://addons/emberset/effects/status/frozen.tscn"
const DOT_VFX := "res://addons/emberset/effects/flame/flame_hearth_medium.tscn"
const EMPOWER_VFX := "res://Asset/VFX/Skills/Leonidas/aura_red.tscn"
const CC_IMMUNE_VFX := "res://Asset/VFX/Skills/Leonidas/aura_flame.tscn"
const HASTE_VFX := "res://Asset/VFX/Skills/Leonidas/aura_blue.tscn"

## Knight buff auras are drawn 3x as big as the original effect (particles included, see SkillVfx).
const KNIGHT_AURA_SCALE := 4.5

## Floating status text: starts just above the HP bar, grows, rises and fades out.
const POPUP_START_HEIGHT := 4.9
const POPUP_RISE := 3.0
const POPUP_TIME := 1.6
## key -> [text, colour]. Order = order the popups appear in when several start at once.
const POPUPS := {
	"stun": ["STUNNED", Color(1.0, 0.85, 0.2)],
	"slow": ["SLOWED", Color(0.5, 0.8, 1.0)],
	"dot": ["POISONED", Color(0.55, 1.0, 0.4)],
	"shield": ["SHIELD", Color(0.4, 0.9, 1.0)],
	"empower": ["RAGE", Color(1.0, 0.3, 0.25)],
	"cc_immune": ["UNSTOPPABLE", Color(1.0, 0.65, 0.15)],
	"haste": ["HASTE", Color(0.35, 0.65, 1.0)],
}
## Debuffs shown next to the hero's name in the local player's HUD.
const HUD_STATUSES := ["stun", "slow", "dot"]

var player: Player

# --- Server state ---
var _stun_left := 0.0
var _slow_left := 0.0
var _slow_factor := 1.0
var _haste_left := 0.0
var _haste_factor := 1.0
var _cc_immune_left := 0.0
var _shield_amount := 0
var _shield_left := 0.0
var _empower_charges := 0
var _empower_bonus := 0
var _dots: Array = []  # of {damage, interval, tick, left}
var _dirty := false

# --- Visual state (every peer) ---
var state: Dictionary = {}
var _visuals: Dictionary = {}  # key -> Node3D


func _ready() -> void:
	player = get_parent() as Player


# ---------------------------------------------------------------- server API

func is_stunned() -> bool:
	return _stun_left > 0.0


func is_cc_immune() -> bool:
	return _cc_immune_left > 0.0


func move_speed_multiplier() -> float:
	var m := 1.0
	if _slow_left > 0.0:
		m *= _slow_factor
	if _haste_left > 0.0:
		m *= _haste_factor
	return m


func apply_stun(duration: float) -> void:
	if duration <= 0.0 or is_cc_immune():
		return
	_stun_left = maxf(_stun_left, duration)
	_dirty = true


func apply_slow(percent: float, duration: float) -> void:
	if duration <= 0.0 or percent <= 0.0 or is_cc_immune():
		return
	var factor := clampf(1.0 - percent, 0.05, 1.0)
	# Keep the strongest slow; refresh the duration.
	_slow_factor = minf(_slow_factor, factor) if _slow_left > 0.0 else factor
	_slow_left = maxf(_slow_left, duration)
	_dirty = true


func apply_dot(damage: int, interval: float, duration: float) -> void:
	if damage <= 0 or duration <= 0.0:
		return
	_dots.append({"damage": damage, "interval": maxf(interval, 0.1), "tick": 0.0, "left": duration})
	_dirty = true


func add_shield(amount: int, duration: float) -> void:
	_shield_amount = amount
	_shield_left = duration if duration > 0.0 else INF
	_dirty = true


## Returns the damage left after the shield took its share.
func absorb_damage(damage: int) -> int:
	if _shield_amount <= 0 or _shield_left <= 0.0 or damage <= 0:
		return damage
	var absorbed := mini(damage, _shield_amount)
	_shield_amount -= absorbed
	if _shield_amount <= 0:
		_shield_left = 0.0
	_dirty = true
	_sync()  # right away, so the ripple shows on the hit that caused it
	return damage - absorbed


func add_empowered_attacks(count: int, bonus: int) -> void:
	_empower_charges = count
	_empower_bonus = bonus
	_dirty = true


## Extra damage for one basic attack (0 when not empowered).
func consume_empowered_attack() -> int:
	if _empower_charges <= 0:
		return 0
	_empower_charges -= 1
	_dirty = true
	return _empower_bonus


func grant_cc_immunity(duration: float) -> void:
	_cc_immune_left = maxf(_cc_immune_left, duration)
	# Cleanse what is already on the hero.
	_stun_left = 0.0
	_slow_left = 0.0
	_slow_factor = 1.0
	_dirty = true


func apply_haste(factor: float, duration: float) -> void:
	_haste_factor = factor
	_haste_left = maxf(_haste_left, duration)
	_dirty = true


func clear_all() -> void:
	_stun_left = 0.0
	_slow_left = 0.0
	_slow_factor = 1.0
	_haste_left = 0.0
	_haste_factor = 1.0
	_cc_immune_left = 0.0
	_shield_amount = 0
	_shield_left = 0.0
	_empower_charges = 0
	_empower_bonus = 0
	_dots.clear()
	_dirty = true
	_sync()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_stun_left = _tick(_stun_left, delta)
	_slow_left = _tick(_slow_left, delta)
	if _slow_left <= 0.0:
		_slow_factor = 1.0
	_haste_left = _tick(_haste_left, delta)
	_cc_immune_left = _tick(_cc_immune_left, delta)
	_shield_left = _tick(_shield_left, delta)
	if _shield_left <= 0.0:
		_shield_amount = 0

	# Damage over time: add everything up first, deal it once at the end
	# (taking damage can kill the hero, which clears _dots).
	var dot_total := 0
	for dot in _dots:
		dot["tick"] += delta
		dot["left"] -= delta
		while dot["tick"] >= dot["interval"]:
			dot["tick"] -= dot["interval"]
			dot_total += int(dot["damage"])
	var before := _dots.size()
	_dots = _dots.filter(func(d: Dictionary) -> bool: return d["left"] > 0.0)
	if _dots.size() != before:
		_dirty = true

	_sync()
	if dot_total > 0 and player != null:
		player.take_damage(dot_total)


func _tick(value: float, delta: float) -> float:
	if value <= 0.0:
		return 0.0
	value -= delta
	if value <= 0.0:
		_dirty = true
		return 0.0
	return value


func _build_state() -> Dictionary:
	return {
		"stun": _stun_left > 0.0,
		"slow": _slow_left > 0.0,
		"dot": not _dots.is_empty(),
		"shield": _shield_amount if _shield_left > 0.0 else 0,
		"empower": _empower_charges,
		"cc_immune": _cc_immune_left > 0.0,
		"haste": _haste_left > 0.0,
	}


func _sync() -> void:
	if not _dirty:
		return
	_dirty = false
	var new_state := _build_state()
	if new_state != state:
		sync_state.rpc(new_state)


# ---------------------------------------------------------------- every peer

@rpc("authority", "call_local", "reliable")
func sync_state(new_state: Dictionary) -> void:
	var old_state := state
	var old_shield: int = state.get("shield", 0)
	state = new_state
	_update_visual("shield", new_state.get("shield", 0) > 0, SHIELD_VFX, 1.4, Vector3(0, 1.6, 0))
	_update_visual("slow", new_state.get("slow", false), SLOW_VFX, 1.0, Vector3.ZERO)
	_update_visual("dot", new_state.get("dot", false), DOT_VFX, 0.7, Vector3(0, 0.2, 0), 0.27)
	_update_visual("empower", new_state.get("empower", 0) > 0, EMPOWER_VFX, KNIGHT_AURA_SCALE, Vector3(0, 2.0, 0))
	_update_visual("cc_immune", new_state.get("cc_immune", false), CC_IMMUNE_VFX, KNIGHT_AURA_SCALE, Vector3(0, 2.0, 0))
	_update_visual("haste", new_state.get("haste", false), HASTE_VFX, KNIGHT_AURA_SCALE, Vector3(0, 2.0, 0))

	var shield: int = new_state.get("shield", 0)
	if shield > 0 and shield < old_shield:
		var fx = _visuals.get("shield")
		if is_instance_valid(fx) and fx.has_method("hit"):
			var side := Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 0.6), randf_range(-1.0, 1.0)).normalized()
			fx.hit(fx.global_position + side * 1.6)

	# One floating text per status that just started
	var delay := 0.0
	for key in POPUPS:
		if _is_on(new_state, key) and not _is_on(old_state, key):
			_popup(POPUPS[key][0], POPUPS[key][1], delay)
			delay += 0.2

	# Debuffs next to the name in the owner's HUD
	if NetworkManager.is_mine(player.peer_id) and player.player_HUD != null:
		player.player_HUD.set_status(_hud_bbcode(new_state))

	state_changed.emit(new_state)


static func _is_on(s: Dictionary, key: String) -> bool:
	var v = s.get(key, false)
	if v is bool:
		return v
	return v > 0


func _hud_bbcode(s: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in HUD_STATUSES:
		if _is_on(s, key):
			parts.append("[color=#%s]%s[/color]" % [POPUPS[key][1].to_html(false), POPUPS[key][0]])
	return "  ".join(parts)


func _popup(text: String, color: Color, delay: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.font_size = 160
	label.outline_size = 36
	label.modulate = Color(color, 0.0)
	label.outline_modulate = Color(0, 0, 0, 0.0)
	label.position = Vector3(0, POPUP_START_HEIGHT, 0)
	label.scale = Vector3.ONE * 0.2
	player.add_child(label)

	var t := label.create_tween()
	t.tween_interval(delay)
	# Grow from small to full size while fading in...
	t.chain().tween_property(label, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(label, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(label, "outline_modulate:a", 0.9, 0.15)
	# ...rise into the air...
	t.parallel().tween_property(label, "position:y", POPUP_START_HEIGHT + POPUP_RISE, POPUP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# ...and fade out at the end.
	t.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(POPUP_TIME - 0.5)
	t.parallel().tween_property(label, "outline_modulate:a", 0.0, 0.5).set_delay(POPUP_TIME - 0.5)
	t.chain().tween_callback(label.queue_free)


func _update_visual(key: String, active: bool, scene_path: String, scale_value: float, offset: Vector3, hue_shift := 0.0) -> void:
	var fx = _visuals.get(key)
	if active and not is_instance_valid(fx):
		fx = SkillVfx.spawn_attached(player, scene_path, offset, scale_value, true, hue_shift)
		if fx != null:
			_visuals[key] = fx
			# Emberset status effects (frozen) also coat the hero's meshes with their overlay.
			var coat := fx as EmbersetStatus
			var model := player.get_node_or_null("character")
			if coat != null and model != null:
				for mesh in model.find_children("*", "MeshInstance3D", true, false):
					coat.attach(mesh)
	elif not active and is_instance_valid(fx):
		_visuals.erase(key)
		SkillVfx.stop_and_free(fx)


func _exit_tree() -> void:
	for fx in _visuals.values():
		if is_instance_valid(fx):
			fx.queue_free()
	_visuals.clear()
