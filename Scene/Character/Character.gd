class_name Character
extends Node3D
	
@export var animation_player: AnimationPlayer
## Playback speed of the "attack" animation (2 = twice as fast). Basic attacks land when it ends,
## so this also makes basic attacks faster.
@export var attack_speed_scale: float = 1.0

## Moment (seconds into the "attack" animation, at normal speed) when the basic attack lands /
## the projectile leaves (e.g. the bow string is released). Below 0 = when the animation ends.
@export var attack_hit_time: float = -1.0

## Emitted when a basic attack should land (attack_hit_time, or the end of the animation)
signal finished_attack

var _hit_sent := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	play_animation("idle")
	pass # Replace with function body.

## Restart an animation from its first frame (used when casting a skill)
func play_animation_from_start(anim: String) -> void:
	if not animation_player.has_animation(anim): return
	animation_player.stop()
	animation_player.play(anim, -1, _speed_for(anim))

func play_animation(anim: String):
	animation_player.play(anim, -1, _speed_for(anim))
	if anim != "attack":
		animation_player.get_animation(anim).loop = true


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if animation_player == null or not _uses_hit_time(): return
	if animation_player.current_animation != "attack":
		_hit_sent = false
		return
	var pos := animation_player.current_animation_position
	if pos < attack_hit_time:
		_hit_sent = false  # a new swing started
	elif not _hit_sent:
		_hit_sent = true
		finished_attack.emit()


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "attack":
		if not _uses_hit_time():
			finished_attack.emit()
		_hit_sent = false
		animation_player.play(anim_name, -1, _speed_for(anim_name))

## attack_hit_time is set and inside the attack animation (a fallback clip may be shorter)
func _uses_hit_time() -> bool:
	if attack_hit_time < 0.0 or animation_player == null or not animation_player.has_animation("attack"):
		return false
	return attack_hit_time < animation_player.get_animation("attack").length

func _speed_for(anim: String) -> float:
	return attack_speed_scale if anim == "attack" else 1.0
