extends Node3D

@export var list_heroes: Array[CharacterData]

@onready var timer_label = $CanvasLayer/Control/MarginContainer/Control/BoxContainer/TimerLabel
@onready var heroes_container = $CanvasLayer/Control/MarginContainer2/MarginContainer/Control/MarginContainer/HeroesContainer
@onready var hero_select_button = preload("res://Scene/SelectHero/HeroSelectButton.tscn")
@onready var heroes_model_container = $HeroModelContainer

@onready var player_avatar_list = $CanvasLayer/Control/MarginContainer/Control/BoxContainer/PlayerList
@onready var boss_avatar_list = $CanvasLayer/Control/MarginContainer/Control/BoxContainer/BossList
@onready var hero_avatar = preload("res://Scene/SelectHero/HeroAvatar.tscn")

@onready var lock_btn: Button =  $CanvasLayer/Control/Control/LockBtn
@onready var rand_btn: Button =  $CanvasLayer/Control/Control/RandomBtn

@onready var select_hero_network_manager = $NetworkManager
var game_play_scene = preload("res://Scene/GamePlay/GamePlay.tscn")

var selected_hero_btn: Node
## Hero model waiting for its background load before it is shown
var _preview_path := ""

func _ready() -> void:
	lock_btn.visible = false
	list_heroes = CharacterDB.get_all_character()
	add_heroes_button()
	#add heroes select button
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	select_hero_network_manager.hero_selection_updated.connect(_on_hero_selection_updated)
	select_hero_network_manager.hero_all_selection_updated.connect(_on_hero_all_selection_updated)
	select_hero_network_manager.count_down_trigged.connect(_on_count_down_trigged)
	select_hero_network_manager.game_started.connect(_on_start_game)
	select_hero_network_manager.start_game_pending.connect(_on_start_game_pending)
	select_hero_network_manager.init_hero_select()

	if multiplayer.is_server():
		select_hero_network_manager.try_start_select()
	
func _on_hero_all_selection_updated(hero_all_selection: Dictionary):
	for child in player_avatar_list.get_children():
		child.queue_free()
	for child in boss_avatar_list.get_children():
		child.queue_free()
			
	for key in hero_all_selection.keys():
		var selection = hero_all_selection[key]
		var player_hero_avatar = hero_avatar.instantiate()		
		if selection[GameDefines.TEAM_SIDE] == GameDefines.TeamSide.LEFT:
			player_avatar_list.add_child(player_hero_avatar)		
		else:
			boss_avatar_list.add_child(player_hero_avatar)		
		player_hero_avatar.set_hero_avatar_info(key, int(selection[GameDefines.HERO_ID]), selection[GameDefines.LOCKED])
	
func _on_hero_selection_updated(peer_id: int, hero_selection: Dictionary):
	update_hero_selection(peer_id, hero_selection)
	
func update_hero_selection(peer_id: int, hero_selection: Dictionary):
	var foundSelection = false
	if hero_selection[GameDefines.TEAM_SIDE] == GameDefines.TeamSide.LEFT:
		for child in player_avatar_list.get_children():
			if child.peer_id == peer_id:
				child.set_hero_avatar_info(peer_id, hero_selection[GameDefines.HERO_ID], hero_selection[GameDefines.LOCKED])			
				child.update_avatar()
				foundSelection = true	
	else:
		for child in boss_avatar_list.get_children():
			if child.peer_id == peer_id:
				child.set_hero_avatar_info(peer_id, hero_selection[GameDefines.HERO_ID], hero_selection[GameDefines.LOCKED])				
				child.update_avatar()
				foundSelection = true
				
	if not foundSelection:		
		var player_hero_avatar = hero_avatar.instantiate()		
		if hero_selection[GameDefines.TEAM_SIDE] == GameDefines.TeamSide.LEFT:
			player_avatar_list.add_child(player_hero_avatar)		
		else:
			boss_avatar_list.add_child(player_hero_avatar)		
		player_hero_avatar.set_hero_avatar_info(peer_id, int(hero_selection[GameDefines.HERO_ID]))		
		
	if NetworkManager.is_mine(peer_id):
		var locked = hero_selection[GameDefines.LOCKED]
		if locked:
			lock_btn.text = GameDefines.UNLOCK
		else:
			lock_btn.text = GameDefines.LOCKED
		if 	selected_hero_btn:
			selected_hero_btn.update_selection(locked)	
	
func add_heroes_button()-> void:
	for hero in list_heroes:
		var button = hero_select_button.instantiate()
		button.hero_change.connect(_on_hero_change)
		button.set_character_data(hero)
		heroes_container.add_child(button)
		pass
	pass

func _process(_delta: float) -> void:
	if _preview_path.is_empty() or not AssetPreloader.is_ready(_preview_path): return
	var hero_model_scene := AssetPreloader.get_scene(_preview_path)
	_preview_path = ""
	if hero_model_scene == null: return
	for child in heroes_model_container.get_children():
		child.queue_free()
	var hero_model = hero_model_scene.instantiate()	
	heroes_model_container.add_child(hero_model)
	hero_model.position = Vector3(0,0,0)

## Everyone has locked in: start loading the match's heroes and skills now, during the countdown
func _preload_match_assets() -> void:
	var hero_ids: Array = []
	for peer_id in select_hero_network_manager.hero_selection_status:
		hero_ids.append(select_hero_network_manager.hero_selection_status[peer_id][GameDefines.HERO_ID])
	if selected_hero_btn:
		hero_ids.append(selected_hero_btn.character_data.id)  # ours, even if the server hasn't echoed it yet
	AssetPreloader.start(CharacterDB.paths_for_heroes(hero_ids))

func _on_count_down_trigged(time: int) -> void:
	timer_label.text = number_to_time_string(time)
	
func _on_start_game():
	var scene = game_play_scene.instantiate()
	get_tree().current_scene.queue_free()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	if scene is GamePlay: scene.game_play_network.set_hero_selection_status(select_hero_network_manager.hero_selection_status)

	
func _on_start_game_pending():
	if not selected_hero_btn:
		roll_a_random_hero()	
	lock_in_hero(true)	
	if multiplayer.is_server():
		select_hero_network_manager.try_start_game()	
	lock_btn.visible = false
	rand_btn.visible = false
	_preload_match_assets.call_deferred()
	timer_label.add_theme_color_override("font_color", Color(1, 0, 0))
	
func number_to_time_string(num: int) -> String:
	var minutes = (num % 3600) / 60
	var seconds = num % 60
	var time_string = "%02d:%02d" % [minutes, seconds]
	return time_string

func _on_hero_change(hero_btn: Node) -> void:
	var is_lock = select_hero_network_manager.hero_selection_status[multiplayer.get_unique_id()][GameDefines.LOCKED]
	if not is_lock:
		for child in heroes_model_container.get_children():
			child.queue_free()
		selected_hero_btn = hero_btn			
		# Only this hero's model is loaded, on a background thread: _process shows it when ready
		_preview_path = selected_hero_btn.character_data.character_scene
		AssetPreloader.start([_preview_path])
		lock_btn.visible = true
		
		select_hero_network_manager.set_selection_status.rpc_id(GameDefines.HOST_ID, selected_hero_btn.character_data.id, false)
		

func _on_lock_btn_pressed() -> void:
	var is_lock = select_hero_network_manager.hero_selection_status[multiplayer.get_unique_id()][GameDefines.LOCKED]
	lock_in_hero(!is_lock)

func lock_in_hero(lock_status: bool):
	if selected_hero_btn:	
		select_hero_network_manager.set_selection_status.rpc_id(GameDefines.HOST_ID, selected_hero_btn.character_data.id, lock_status)
func _on_random_btn_pressed() -> void:
	roll_a_random_hero()
	
func roll_a_random_hero():
	while true:
		var random_hero = heroes_container.get_child(randi() % heroes_container.get_child_count())
		if selected_hero_btn != random_hero:
			_on_hero_change(random_hero)
			break
				
func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://Scene/MainMenu/MainMenu.tscn")
