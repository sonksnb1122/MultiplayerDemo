extends Node3D
## Floating number over a hero: pops in, rises and fades.
## Color by kind (Player.DamageKind): basic attack red, skill orange, damage over time green-yellow,
## heal green with a "+".

const COLORS := [Color(1, 0.25, 0.32), Color(1, 0.6, 0.15), Color(0.75, 0.9, 0.2), Color(0.3, 1, 0.45)]
const RISE := 1.6
## Overall size of the numbers (1 = the old size)
const SIZE_SCALE := 0.75

## Kept by the hero and shown again for the next hit (hidden instead of freed)
var pooled := false
var _tween: Tween


func set_dmg(dmg: int, kind := 0, base_position := Vector3.INF) -> void:
	if _tween != null:
		_tween.kill()
	if base_position != Vector3.INF:
		position = base_position
	visible = true
	$Timer.start()
	var label: Label3D = $Label3D
	label.text = ("+%d" if kind == 3 else "-%d") % dmg
	label.modulate = COLORS[clampi(kind, 0, COLORS.size() - 1)]
	# Bigger hits get bigger numbers
	var size := clampf(0.8 + dmg / 40.0, 0.8, 1.6)
	if kind == 2:
		size = 0.7
	size *= SIZE_SCALE
	scale = Vector3.ONE * size * 0.4
	position.x += randf_range(-0.4, 0.4)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector3.ONE * size, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:y", position.y + RISE, 0.7).set_ease(Tween.EASE_OUT)
	_tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.4)


func _on_timer_timeout() -> void:
	if pooled:
		visible = false
	else:
		queue_free()
