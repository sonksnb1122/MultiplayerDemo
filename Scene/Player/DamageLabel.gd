extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_dmg(dmg: int) -> void:
	$Label3D.text = "-%d"%dmg

func _on_timer_timeout() -> void:
	queue_free()
	pass # Replace with function body.
