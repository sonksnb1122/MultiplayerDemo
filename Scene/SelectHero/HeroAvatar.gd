extends Control

@onready var avatar = $Control/Avatar
var peer_id: int = 0
var hero_id: int = 0
var is_lock = false

func set_hero_avatar_info(p_id: int, h_id: int, h_is_lock):
	peer_id = p_id
	hero_id = h_id
	is_lock = h_is_lock
func update_avatar():
	var char = CharacterDB.get_character(hero_id)
	var tex = load(char.hero_avatar)
	avatar.texture = tex
	if is_lock:
		avatar.modulate = Color.WHITE
	else:
		avatar.modulate = Color.WEB_GRAY
