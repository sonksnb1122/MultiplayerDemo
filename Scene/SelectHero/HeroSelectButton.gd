extends Control

signal hero_change(hero_btn: Node)

@onready var avatar = $Control/Avatar
@onready var locked_label = $Control/LockedLabel

var character_data: CharacterData

func set_character_data(char: CharacterData) -> void:
	character_data = char
	var tex = load(char.hero_avatar)
	$Control/Avatar.texture = tex

func update_selection(is_lock: bool):
	locked_label.visible = is_lock
	avatar.modulate = Color.GRAY
	

func _on_button_pressed() -> void:
	hero_change.emit(self)
	pass # Replace with function body.
