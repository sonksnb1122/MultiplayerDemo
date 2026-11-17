class_name Character
extends Node3D
	
@export var animation_player: AnimationPlayer

signal finished_attack

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	play_animation("idle")
	pass # Replace with function body.

func play_animation(anim: String):	
	animation_player.play(anim)
	if anim != "attack":
		animation_player.get_animation(anim).loop = true


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "attack":
		finished_attack.emit()
		animation_player.play(anim_name)
