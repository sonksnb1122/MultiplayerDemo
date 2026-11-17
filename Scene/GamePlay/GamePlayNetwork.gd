extends Node

class_name GamePlayNetwork
signal start_game
signal play_time_trigged(time: int)
signal heroes_status_updated(heroes_status: Dictionary)
@onready var hero_spawner: HeroSpawner = $"../HeroSpawner"
@onready var game_play_timer: Timer = $PlayTimer

var hero_selection_status = {} # {1:[GameDefines.TEAM_SIDE: 0, GameDefines.HERO_ID: 0, GameDefines.SLOT : 3]}

var play_time = 0
func _ready() -> void:
	hero_spawner.all_player_spawned.connect(_all_player_spawned)
	pass
	
func set_hero_selection_status(heroes_status: Dictionary):
	hero_selection_status = heroes_status
	# setup slot info
	var number_heros_on_left = 0;
	var number_heros_on_right = 0;
	for peer_id in hero_selection_status:
		if hero_selection_status[peer_id][GameDefines.TEAM_SIDE] == GameDefines.TeamSide.LEFT:
			hero_selection_status[peer_id][GameDefines.SLOT] = number_heros_on_left
			number_heros_on_left += 1
		else:
			hero_selection_status[peer_id][GameDefines.SLOT] = number_heros_on_right
			number_heros_on_right += 1
	if not multiplayer.is_server():
		return
	update_hero_status.rpc(heroes_status)
	 
@rpc("authority", "call_local", "reliable")
func update_hero_status(heroes_status: Dictionary):
	heroes_status_updated.emit(heroes_status)
		
func _all_player_spawned():
	# TODO send timer sync for all client
	# The first time client receive signal game start, allow players to move
	if not multiplayer.is_server():
		return false
		
	#start timer
	start_the_game.rpc()
	
	show_play_time.rpc(play_time)
	game_play_timer.wait_time = 1
	game_play_timer.one_shot = false
	game_play_timer.timeout.connect(send_play_time)
	game_play_timer.start()
		
		
func send_play_time():
	play_time += 1
	show_play_time.rpc(play_time)
	
@rpc("authority", "call_local", "reliable")	
func start_the_game():
	print("game stated")
	start_game.emit()
					
@rpc("authority", "call_local", "reliable")	
func show_play_time(time: int):
	play_time_trigged.emit(time)
	
		
