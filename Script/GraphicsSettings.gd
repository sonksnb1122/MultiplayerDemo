extends Node
## Autoload. Menus (Main menu, Lobby, Room) are plain 2D screens that rarely change, so there the
## engine only redraws when something on screen changes (low processor mode) instead of 60 times
## a second. Hero select and the match (3D scenes) render normally.

var _last_scene: Node = null


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == _last_scene:
		return
	_last_scene = scene
	OS.low_processor_usage_mode = scene != null and not (scene is Node3D)
