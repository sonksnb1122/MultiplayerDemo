extends Node3D

@export var list_heroes: Array[CharacterData]

@onready var timer_label = $CanvasLayer/Control/MarginContainer/Control/BoxContainer/TimerLabel
@onready var heroes_container = $CanvasLayer/Control/MarginContainer2/MarginContainer/Control/MarginContainer/Row/HeroesContainer
## Skills of the hero last clicked, beside the hero column
@onready var skill_list: VBoxContainer = $CanvasLayer/Control/MarginContainer2/MarginContainer/Control/MarginContainer/Row/SkillInfo/SkillList
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
	_show_hero_info(null)
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
		if selection.get("Bot", false):
			player_hero_avatar.update_avatar()  # bots have their hero locked in from the start
	
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

## Where the hero model stands: on the ground (y = 0), centered on screen in the empty space
## between the hero panel's right edge and the right edge of the screen
func _preview_position() -> Vector3:
	var cam := get_node_or_null("Camera3D") as Camera3D
	var panel := get_node_or_null("CanvasLayer/Control/MarginContainer2/MarginContainer") as Control
	if cam == null or panel == null:
		return Vector3.ZERO
	var screen_w := get_viewport().get_visible_rect().size.x
	var target_x := (panel.get_global_rect().end.x + screen_w) / 2.0
	# Same height on screen and same depth as the platform center, moved sideways
	var depth := -(cam.global_transform.affine_inverse() * Vector3.ZERO).z
	var origin_on_screen := cam.unproject_position(Vector3.ZERO)
	var p := cam.project_position(Vector2(target_x, origin_on_screen.y), depth)
	return Vector3(p.x, 0.0, p.z)


func _process(_delta: float) -> void:
	if _preview_path.is_empty() or not AssetPreloader.is_ready(_preview_path): return
	for anim_path in HeroModel.animation_paths():
		if not AssetPreloader.is_ready(anim_path): return
	var hero_model_scene := AssetPreloader.get_scene(_preview_path)
	_preview_path = ""
	if hero_model_scene == null: return
	for child in heroes_model_container.get_children():
		child.queue_free()
	var hero_model = hero_model_scene.instantiate()	
	heroes_model_container.add_child(hero_model)
	hero_model.position = _preview_position()

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
	_show_hero_info(hero_btn)
	var is_lock = select_hero_network_manager.hero_selection_status[multiplayer.get_unique_id()][GameDefines.LOCKED]
	if not is_lock:
		for child in heroes_model_container.get_children():
			child.queue_free()
		selected_hero_btn = hero_btn			
		# Only this hero's model is loaded, on a background thread: _process shows it when ready
		_preview_path = selected_hero_btn.character_data.character_scene
		AssetPreloader.start([_preview_path] + HeroModel.animation_paths())
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


# --- Skill info beside the hero column ---

const INFO_FONT := preload("res://Asset/Art/UI/Fonts/RussoOne_Original.ttf")


## Name, stats and the Q W E R + Dash of the hero of [param hero_btn] (null: a hint).
## The clicked hero is highlighted, the others are dimmed.
func _show_hero_info(hero_btn: Node) -> void:
	for btn in heroes_container.get_children():
		btn.modulate = Color.WHITE if hero_btn == null or btn == hero_btn else Color(0.6, 0.6, 0.6)
	for child in skill_list.get_children():
		child.queue_free()
	if hero_btn == null:
		skill_list.add_child(_info_label("Pick a hero to see its skills", 15, Color(0.85, 0.85, 0.85), INFO_FONT))
		return
	var data: CharacterData = hero_btn.character_data
	skill_list.add_child(_info_label(data.name, 20, Color(1, 0.85, 0.35), INFO_FONT))
	skill_list.add_child(_info_label("HP %d   Damage %d   Range %d" % [data.hp, data.damage, data.attack_range], 12, Color(0.8, 0.8, 0.8)))
	var skills := SkillDB.get_skills(data.id)
	for i in skills.size():
		skill_list.add_child(_skill_row(skills[i], SkillCaster.KEY_LABELS[i] if i < SkillCaster.KEY_LABELS.size() else ""))


func _skill_row(skill: SkillData, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Round icon in the skill's color
	var icon_box := Panel.new()
	icon_box.custom_minimum_size = Vector2(36, 36)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon_box.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var style := StyleBoxFlat.new()
	style.bg_color = skill.color.darkened(0.35)
	style.set_corner_radius_all(19)
	style.anti_aliasing = true
	icon_box.add_theme_stylebox_override("panel", style)
	if not skill.icon.is_empty() and ResourceLoader.exists(skill.icon):
		var icon := TextureRect.new()
		icon.texture = load(skill.icon)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_box.add_child(icon)
	row.add_child(icon_box)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(_info_label("[%s] %s  -  %ds" % [key, skill.display_name, int(skill.cooldown)], 13, skill.color.lightened(0.35), INFO_FONT))
	text.add_child(_info_label(skill.description, 12, Color(0.9, 0.9, 0.9)))
	row.add_child(text)
	return row


func _info_label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	if font != null:
		l.add_theme_font_override("font", font)
	return l
