extends Control

@onready var timer_label = $MarginContainer/Control/HBoxContainer/TimerLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:	
	pass

## The top bar no longer shows team names / hero avatars (removed), only the timer
func set_heroes_status(_heroes_status: Dictionary):
	pass
		
func set_timer_label(time: int) -> void:
	var minutes = (time % 3600) / 60
	var seconds = time % 60
	var time_string = "%02d:%02d" % [minutes, seconds]
	timer_label.text = time_string

	
func set_team_avatar(side: GameDefines.TeamSide, slot: int, char_data: CharacterData) -> void:
	
	pass
