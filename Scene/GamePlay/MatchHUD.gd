class_name MatchHUD
extends CanvasLayer
## Match UI, built in code: score under the timer, zone status, kill feed, respawn countdown,
## scoreboard (hold TAB) and the end-of-match screen. Reads everything from MatchManager.

const FONT := preload("res://Asset/Art/UI/Fonts/RussoOne_Original.ttf")
const PANEL_TEX := preload("res://Asset/Art/UI/Generated/panel_dark.png")
const COLOR_ALLY := Color(0.3, 0.9, 0.35)
const COLOR_ENEMY := Color(0.95, 0.3, 0.25)
const KILL_FEED_MAX := 5
const KILL_FEED_TIME := 6.0

var match_manager: MatchManager

var _score_label: RichTextLabel
var _zone_label: Label
var _kill_feed: VBoxContainer
var _respawn_label: Label
var _respawn_left := 0.0
var _board: PanelContainer
var _board_grid: GridContainer
var _end_screen: Control
var _end_title: Label
var _end_grid: GridContainer
var _restart_button: Button
var _waiting_label: Label


func setup(manager: MatchManager) -> void:
	match_manager = manager
	layer = 5
	_build()
	manager.scores_changed.connect(_on_scores_changed)
	manager.zone_changed.connect(func(_s: int) -> void: _update_zone_label())
	manager.hero_killed.connect(_on_hero_killed)
	manager.stats_changed.connect(func(_s: Dictionary) -> void:
		_refresh_board(_board_grid)
		if _end_screen.visible:
			_refresh_board(_end_grid))
	manager.match_ended.connect(_on_match_ended)
	_on_scores_changed(0, 0)
	_update_zone_label()


# ------------------------------------------------------------------ build

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style() -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = PANEL_TEX
	s.set_texture_margin_all(16)
	s.set_content_margin_all(18)
	return s


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Score: under the timer (top center)
	_score_label = RichTextLabel.new()
	_score_label.bbcode_enabled = true
	_score_label.fit_content = true
	_score_label.scroll_active = false
	_score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score_label.add_theme_font_override("normal_font", FONT)
	_score_label.add_theme_font_size_override("normal_font_size", 26)
	_score_label.add_theme_constant_override("outline_size", 6)
	_score_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_label.offset_left = -150
	_score_label.offset_right = 150
	_score_label.offset_top = 52
	_score_label.offset_bottom = 88
	root.add_child(_score_label)

	_zone_label = _label("", 14)
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_zone_label.offset_left = -150
	_zone_label.offset_right = 150
	_zone_label.offset_top = 88
	_zone_label.offset_bottom = 108
	root.add_child(_zone_label)

	# Kill feed: top right, under the minimap
	_kill_feed = VBoxContainer.new()
	_kill_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_kill_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_kill_feed.offset_left = -360
	_kill_feed.offset_right = -16
	_kill_feed.offset_top = 116
	_kill_feed.offset_bottom = 260
	root.add_child(_kill_feed)

	# Respawn countdown: middle of the screen
	_respawn_label = _label("", 34)
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_label.offset_left = -300
	_respawn_label.offset_right = 300
	_respawn_label.offset_top = -120
	_respawn_label.offset_bottom = -70
	_respawn_label.visible = false
	root.add_child(_respawn_label)

	# Scoreboard (hold TAB)
	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", _panel_style())
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_board.grow_vertical = Control.GROW_DIRECTION_BOTH
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.visible = false
	_board_grid = _new_grid()
	_board.add_child(_board_grid)
	root.add_child(_board)

	# End screen
	_end_screen = Control.new()
	_end_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.visible = false
	root.add_child(_end_screen)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_end_title = _label("VICTORY", 56)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_grid = _new_grid()
	box.add_child(_end_grid)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	_restart_button = _button("Play again", "res://Resources/GUI/BlueButtonNormal.tres", "res://Resources/GUI/BlueButtonPressed.tres")
	_restart_button.pressed.connect(func() -> void:
		_restart_button.disabled = true
		match_manager.request_restart())
	buttons.add_child(_restart_button)
	var menu_button := _button("Main menu", "res://Resources/GUI/RedButtonNormal.tres", "res://Resources/GUI/RedButtonPressed.tres")
	menu_button.pressed.connect(_on_main_menu)
	buttons.add_child(menu_button)
	_waiting_label = _label("Waiting for the host to start a new match...", 14, Color(0.85, 0.85, 0.85))
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_waiting_label)


func _button(text: String, normal: String, pressed: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 56)
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_stylebox_override("normal", load(normal))
	b.add_theme_stylebox_override("hover", load(normal))
	b.add_theme_stylebox_override("pressed", load(pressed))
	b.add_theme_stylebox_override("disabled", load(pressed))
	b.pressed.connect(func() -> void: Sfx.play_ui(get_tree(), "click"))
	return b


func _new_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 6)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


# ------------------------------------------------------------------ updates

func _process(delta: float) -> void:
	if match_manager == null: return
	# Scoreboard while TAB is held (not over the end screen)
	var show_board := Input.is_key_pressed(KEY_TAB) and not _end_screen.visible
	if show_board != _board.visible:
		_board.visible = show_board
		if show_board:
			_refresh_board(_board_grid)
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0 or MatchManager.is_over:
			_respawn_label.visible = false
		else:
			_respawn_label.text = "Respawn in %d" % ceili(_respawn_left)


func _on_scores_changed(left: int, right: int) -> void:
	var mine := match_manager.my_team()
	var ally := left if mine == 0 else right
	var enemy := right if mine == 0 else left
	_score_label.text = "[center][color=#%s]%d[/color]  :  [color=#%s]%d[/color]   [font_size=14][color=#bbbbbb]/ %d[/color][/font_size][/center]" % [
		COLOR_ALLY.to_html(false), ally, COLOR_ENEMY.to_html(false), enemy, GameDefines.SCORE_TO_WIN]


func _update_zone_label() -> void:
	var text := "Zone: neutral"
	match match_manager.zone_state:
		MatchManager.ZoneState.CONTESTED:
			text = "Zone: contested!"
		MatchManager.ZoneState.LEFT, MatchManager.ZoneState.RIGHT:
			text = "Zone: your team scores" if match_manager.zone_state == match_manager.my_team() else "Zone: enemies score"
	_zone_label.text = text
	_zone_label.add_theme_color_override("font_color", match_manager.zone_color())


func _name_of(peer: int) -> String:
	var s: Dictionary = match_manager.stats.get(peer, {})
	if s.is_empty(): return "?"
	var data := CharacterDB.get_character(int(s["hero"]))
	var hero_name: String = data.name if data != null else "?"
	return "%s (%s)" % [s["name"], hero_name]


func _team_color(peer: int) -> Color:
	var s: Dictionary = match_manager.stats.get(peer, {})
	if s.is_empty(): return Color.WHITE
	return COLOR_ALLY if int(s["team"]) == match_manager.my_team() else COLOR_ENEMY


func _on_hero_killed(victim_peer: int, killer_peer: int, _assists: Array, respawn_time: float) -> void:
	# Kill feed line
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if killer_peer != 0:
		row.add_child(_label(_name_of(killer_peer), 14, _team_color(killer_peer)))
		row.add_child(_label("  killed  ", 14, Color(0.85, 0.85, 0.85)))
	else:
		row.add_child(_label("died: ", 14, Color(0.85, 0.85, 0.85)))
	row.add_child(_label(_name_of(victim_peer), 14, _team_color(victim_peer)))
	_kill_feed.add_child(row)
	while _kill_feed.get_child_count() > KILL_FEED_MAX:
		var old := _kill_feed.get_child(0)
		_kill_feed.remove_child(old)
		old.queue_free()
	var tween := row.create_tween()
	tween.tween_interval(KILL_FEED_TIME)
	tween.tween_property(row, "modulate:a", 0.0, 0.6)
	tween.tween_callback(row.queue_free)

	var me := multiplayer.get_unique_id()
	if killer_peer == me:
		Sfx.play_ui(get_tree(), "kill")
		_hit_stop()
		_shake(0.5, 0.3)
	elif victim_peer == me:
		Sfx.play_ui(get_tree(), "death")
		_shake(0.8, 0.4)

	# My hero died: respawn countdown
	if victim_peer == multiplayer.get_unique_id():
		_respawn_left = respawn_time
		_respawn_label.visible = true
		_respawn_label.text = "Respawn in %d" % ceili(respawn_time)


func _refresh_board(grid: GridContainer) -> void:
	if grid == null or (grid == _board_grid and not _board.visible): return
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for header in ["Player", "Hero", "K / D / A", "Damage", ""]:
		grid.add_child(_label(header, 15, Color(0.75, 0.75, 0.75)))
	var mine := match_manager.my_team()
	# My team first
	for team in [mine, 1 - mine]:
		for peer in match_manager.stats:
			var s: Dictionary = match_manager.stats[peer]
			if int(s["team"]) != team: continue
			var color := COLOR_ALLY if team == mine else COLOR_ENEMY
			var data := CharacterDB.get_character(int(s["hero"]))
			grid.add_child(_label(str(s["name"]) + (" (you)" if peer == multiplayer.get_unique_id() else ""), 18, color))
			grid.add_child(_label(data.name if data != null else "?", 18))
			grid.add_child(_label("%d / %d / %d" % [s["kills"], s["deaths"], s["assists"]], 18))
			grid.add_child(_label(str(s["damage"]), 18))
			grid.add_child(_label("", 18))


## Freeze the game for a split second on my kills (felt more than seen)
func _hit_stop() -> void:
	Engine.time_scale = 0.1
	get_tree().create_timer(0.07, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _shake(strength: float, duration: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.has_method("shake"):
		cam.call("shake", strength, duration)


func _on_match_ended(winner: int) -> void:
	_respawn_label.visible = false
	_board.visible = false
	if winner < 0:
		_end_title.text = "DRAW"
		_end_title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	elif winner == match_manager.my_team():
		_end_title.text = "VICTORY"
		_end_title.add_theme_color_override("font_color", COLOR_ALLY)
	else:
		_end_title.text = "DEFEAT"
		_end_title.add_theme_color_override("font_color", COLOR_ENEMY)
	_refresh_board(_end_grid)
	Sfx.play_ui(get_tree(), "defeat" if winner >= 0 and winner != match_manager.my_team() else "victory")
	var is_host := multiplayer.is_server()
	_restart_button.visible = is_host
	_waiting_label.visible = not is_host
	_end_screen.visible = true


## A line in the kill feed (e.g. "X left the match")
func add_feed_message(text: String) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label(text, 14, Color(1, 0.85, 0.3)))
	_kill_feed.add_child(row)
	var tween := row.create_tween()
	tween.tween_interval(KILL_FEED_TIME)
	tween.tween_property(row, "modulate:a", 0.0, 0.6)
	tween.tween_callback(row.queue_free)


var _left_notice: CanvasLayer

## Blocking message: a player left, this match can't continue -> back to the room list
func show_player_left(player_name: String) -> void:
	if _restart_button != null:
		_restart_button.visible = false
	if _waiting_label != null:
		_waiting_label.visible = false
	if _left_notice != null:
		return
	# Own layer above everything (also above the loading screen)
	_left_notice = CanvasLayer.new()
	_left_notice.layer = 100
	add_child(_left_notice)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_left_notice.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_left_notice.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var title := _label("A player left", 36, Color(1, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var text := _label("%s has left the match.\nThis match can't continue." % player_name, 18)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	var button := _button("Back to lobby", "res://Resources/GUI/BlueButtonNormal.tres", "res://Resources/GUI/BlueButtonPressed.tres")
	button.custom_minimum_size = Vector2(240, 56)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_on_back_to_lobby)
	box.add_child(button)


func _on_back_to_lobby() -> void:
	NetworkManager.quit_room()
	NetworkManager.disconnected_reason = GameDefines.DisconnectReason.BACK_TO_LOBBY
	get_tree().change_scene_to_file(GameDefines.MAIN_MENU_SCENE)


func _on_main_menu() -> void:
	NetworkManager.quit_room()
	NetworkManager.disconnected_reason = GameDefines.DisconnectReason.NONE
	get_tree().change_scene_to_file(GameDefines.MAIN_MENU_SCENE)
