extends Control

@onready var timer_label = $MarginContainer/Control/HBoxContainer/TimerLabel
@onready var player_avatar_list = $MarginContainer/Control/HBoxContainer/PlayerList
@onready var boss_avatar_list = $MarginContainer/Control/HBoxContainer/BossList
@onready var hero_avatar = preload("res://Scene/SelectHero/HeroAvatar.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:	
	pass

func set_heroes_status(heroes_status: Dictionary):
	for child in player_avatar_list.get_children():
		child.queue_free()
	for child in boss_avatar_list.get_children():
		child.queue_free()
			
	for key in heroes_status.keys():
		var hero_status = heroes_status[key]
		var player_hero_avatar = hero_avatar.instantiate()		
		if hero_status[GameDefines.TEAM_SIDE] == GameDefines.TeamSide.LEFT:
			player_avatar_list.add_child(player_hero_avatar)		
		else:
			boss_avatar_list.add_child(player_hero_avatar)		
		player_hero_avatar.set_hero_avatar_info(key, int(hero_status[GameDefines.HERO_ID]), hero_status[GameDefines.LOCKED])
		player_hero_avatar.update_avatar()
		
func set_timer_label(time: int) -> void:
	var minutes = (time % 3600) / 60
	var seconds = time % 60
	var time_string = "%02d:%02d" % [minutes, seconds]
	timer_label.text = time_string

	
func set_team_avatar(side: GameDefines.TeamSide, slot: int, char_data: CharacterData) -> void:
	
	pass
