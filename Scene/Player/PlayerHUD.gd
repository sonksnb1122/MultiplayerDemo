class_name PlayerHUD

extends Control

var detail_hp_bar: Node
var detail_avatar: Node
var detail_name_label: Node
var detail_damage_label: Node
var detail_speed_label: Node

func load_GUI():
	detail_hp_bar = $Control/BoxContainer/MarginContainer/Control/hp_bar
	detail_avatar = $Control/BoxContainer/avatar
	detail_name_label = $Control/BoxContainer/MarginContainer/Control/MarginContainer/name_label
	detail_damage_label = $Control/BoxContainer/MarginContainer/Control/HBoxContainer/damage_label
	detail_speed_label = $Control/BoxContainer/MarginContainer/Control/HBoxContainer/speed_label

func set_current_hp_details(value: int) -> void:
	detail_hp_bar.value = float(value)
	
func update_character_data_details(character_data: CharacterData) -> void:
	load_GUI()
	var tex = load(character_data.hero_avatar)
	detail_avatar.texture = tex
	#name
	detail_name_label.text = character_data.name
	detail_damage_label.text = "%d" % character_data.damage
	detail_speed_label.text =  "%d" % character_data.movement_speed
	#hp_bar
	detail_hp_bar.max_value = float(character_data.hp)
	detail_hp_bar.value = float(character_data.hp)
