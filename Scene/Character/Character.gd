class_name Character
extends Node3D
	
@export var animation_player: AnimationPlayer
## Playback speed of the "attack" animation (2 = twice as fast). Basic attacks land when it ends,
## so this also makes basic attacks faster.
@export var attack_speed_scale: float = 1.0

signal finished_attack

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
func _process(delta: float) -> void:
	pass


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "attack":
		finished_attack.emit()
		animation_player.play(anim_name, -1, _speed_for(anim_name))

func _speed_for(anim: String) -> float:
	return attack_speed_scale if anim == "attack" else 1.0
