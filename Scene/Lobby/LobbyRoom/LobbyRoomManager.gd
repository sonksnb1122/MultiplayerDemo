extends Control

signal return_to_lobby

@onready var player_list = $RoomHub/Panel/LobbyAndRoom/RoomList/Players/PlayerHub/PlayersCtn
@onready var boss_list = $RoomHub/Panel/LobbyAndRoom/RoomList/Players/BossHub/BossCtn
@onready var start_btn: Button = $RoomHub/Panel/LobbyAndRoom/RoomList/StartBtn
@onready var starting_label: Label = $StartingLabel
@onready var settings_btn: Button = $RoomHub/Panel/LobbyAndRoom/Lobby/SettingBtn

const FONT := preload("res://Asset/Art/UI/Fonts/RussoOne_Original.ttf")
## Match options of the room (everyone sees them, only the host can change them)
var _settings_label: Label
var _settings_panel: Control
var _option_buttons := {}

var player_info_scene = preload("res://Scene/Lobby/LobbyRoom/PlayerInRoom.tscn")

var select_hero_scene = preload("res://Scene/SelectHero/SelectHero.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	LobbyNetworkManager.players_updated.connect(_on_players_updated)
	LobbyNetworkManager.cool_down_trigged.connect(_on_pending_time_to_start)
	LobbyNetworkManager.game_started.connect(_on_start_game)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	LobbyNetworkManager.settings_updated.connect(_refresh_settings)
	settings_btn.pressed.connect(_on_settings_btn_pressed)
	_build_settings_ui()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func setup_scene():
	starting_label.visible = false
	if not multiplayer.is_server():
		start_btn.text = GameDefines.READY
	# Only the host changes the match options; the others just read them
	settings_btn.text = "Match Settings" if multiplayer.is_server() else "Settings"
	settings_btn.disabled = not multiplayer.is_server()
	_settings_panel.visible = false
	_refresh_settings()

func _on_players_updated(players: Dictionary) -> void:
	refresh_players_in_room(players)

	
func refresh_players_in_room(players: Dictionary):
	for player in player_list.get_children():
		player.queue_free()
	for player in boss_list.get_children():
		player.queue_free()
		
	var is_player = true
	for key in players.keys():	
		var player_info = players[key]
		var player_obj = player_info_scene.instantiate()
		if is_player:
			player_list.add_child(player_obj)
			is_player = false
		else:
			boss_list.add_child(player_obj)		
			is_player = true
		var is_host = false
		if key == GameDefines.HOST_ID:
			is_host = true
		player_obj.set_player_info(player_info, is_host)

func _on_start_or_ready_btn_pressed() -> void:
	if multiplayer.is_server():
		LobbyNetworkManager.try_start_game()
	else:
		var is_ready =!LobbyNetworkManager.player_status[multiplayer.get_unique_id()][GameDefines.READY]
		LobbyNetworkManager.set_ready_status.rpc_id(GameDefines.HOST_ID, is_ready)
		if is_ready:
			start_btn.text = GameDefines.UNREADY
		else:
			start_btn.text = GameDefines.READY

func _on_pending_time_to_start(time: int):
	starting_label.visible = true
	starting_label.text = GameDefines.STARTING_IN_STR + str(time)

func _on_start_game():
	var scene = select_hero_scene.instantiate()
	get_tree().current_scene.queue_free()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	
func _on_invite_btn_pressed() -> void:
	pass

func _on_copy_btn_pressed() -> void:
	pass
	
func _on_back_btn_pressed() -> void:
	NetworkManager.quit_room()
	return_to_lobby.emit()
	
func _on_server_disconnected() -> void:
	BroadcastManager.refresh_room_list()
	return_to_lobby.emit()
	
func _on_connection_failed() -> void:
	return_to_lobby.emit()


# --- MATCH OPTIONS (host) ---

func _build_settings_ui() -> void:
	# One line above the Start button: "5 min | 40 points | Bots: ..."
	_settings_label = Label.new()
	_settings_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_label.add_theme_font_override("font", FONT)
	_settings_label.add_theme_font_size_override("font_size", 14)
	_settings_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	var room_list := start_btn.get_parent()
	room_list.add_child(_settings_label)
	room_list.move_child(_settings_label, start_btn.get_index())

	# Panel with one choice per option (opened with the Settings button)
	_settings_panel = CenterContainer.new()
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	add_child(_settings_panel)
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.96)
	style.border_color = Color(0.85, 0.7, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	box.add_theme_stylebox_override("panel", style)
	_settings_panel.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	box.add_child(vbox)
	var title := _text("Match Settings", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(grid)

	var durations: Array = []
	for d in MatchSettings.DURATIONS:
		durations.append(MatchSettings.duration_text(d))
	var scores: Array = []
	for sc in MatchSettings.SCORES:
		scores.append("%d points" % sc)
	var bots: Array = []
	for b in MatchSettings.BOT_TEAM_SIZES:
		bots.append(MatchSettings.bots_text(b))
	_add_option(grid, "duration", "Match length", durations, MatchSettings.DURATIONS)
	_add_option(grid, "score", "Score to win", scores, MatchSettings.SCORES)
	_add_option(grid, "bots", "Bots", bots, MatchSettings.BOT_TEAM_SIZES)
	_add_option(grid, "difficulty", "Bot difficulty", MatchSettings.DIFFICULTIES, [0, 1, 2])

	var close := Button.new()
	close.text = "Done"
	close.custom_minimum_size = Vector2(140, 40)
	close.add_theme_font_override("font", FONT)
	close.add_theme_font_size_override("font_size", 18)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: _settings_panel.visible = false)
	vbox.add_child(close)


func _text(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	return l


## A label and a drop-down; [param values] are what MatchSettings stores for each choice
func _add_option(grid: GridContainer, key: String, title: String, labels: Array, values: Array) -> void:
	grid.add_child(_text(title, 16))
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(180, 34)
	option.add_theme_font_override("font", FONT)
	option.add_theme_font_size_override("font_size", 15)
	for i in labels.size():
		option.add_item(str(labels[i]), i)
	option.item_selected.connect(func(index: int) -> void:
		LobbyNetworkManager.change_settings({key: values[index]}))
	grid.add_child(option)
	_option_buttons[key] = [option, values]


func _on_settings_btn_pressed() -> void:
	if not multiplayer.is_server():
		return
	_refresh_settings()
	_settings_panel.visible = not _settings_panel.visible


## Show the current options (label for everyone, drop-downs for the host)
func _refresh_settings() -> void:
	if _settings_label == null:
		return
	_settings_label.text = MatchSettings.summary()
	var current := MatchSettings.to_dict()
	for key in _option_buttons:
		var option: OptionButton = _option_buttons[key][0]
		var values: Array = _option_buttons[key][1]
		var index := values.find(current[key])
		if index >= 0 and option.selected != index:
			option.select(index)
