class_name MatchChat
extends CanvasLayer
## In-match chat, quick chat and map pings. Built in code, child of MatchManager on every peer.
##
##   Enter: chat with the team, Shift+Enter: chat with everyone (Tab switches while typing,
##          Enter sends, Esc closes). The "Chat" button under the pause button does the same.
##   1..6 / the "!" button: quick-chat phrases (team; "Good game!" goes to everyone).
##   Click on the minimap, or Alt + click on the ground: ping that spot for the team
##   (a ring on the ground and on the minimap for a few seconds).
##
## Everything goes through the server, which checks who sent it, trims the text, limits how
## often each player can send, and forwards it only to the right players.

## True while the chat line has the keyboard: Player / SkillCaster ignore their keys
static var is_typing := false

const FONT := preload("res://Asset/Art/UI/Fonts/RussoOne_Original.ttf")
const QUICK_CHAT := ["Attack!", "Retreat!", "Help me!", "Go to the zone!", "Enemy missing!", "Good game!"]
## Quick-chat lines that go to everyone (the others go to the team only)
const QUICK_CHAT_TO_ALL := [5]
const MAX_LENGTH := 120
const LOG_MAX := 7
const LOG_TIME := 10.0
## Server: shortest time between two messages / two pings of one player
const CHAT_GAP := 0.35
const PING_GAP := 0.6
const PING_TIME := 3.0
const PING_COLOR := Color(1.0, 0.85, 0.2)
const COLOR_ALLY := Color(0.3, 0.9, 0.35)
const COLOR_ENEMY := Color(0.95, 0.3, 0.25)
## Arena half size (ground 120 x 120): pings are kept inside it
const WORLD_HALF := 60.0

var match_manager: MatchManager
## Pings shown on the minimap (read by Minimap): [{"pos": Vector3, "left": float}]
var pings: Array = []

var _log: VBoxContainer
var _input_row: HBoxContainer
var _input: LineEdit
var _mode_button: Button
var _quick_panel: VBoxContainer
var _team_only := true
var _local_ping_ready := 0.0
## Server: peer id -> {"chat": time, "ping": time} of the last accepted one
var _last_sent := {}


func setup(manager: MatchManager) -> void:
	match_manager = manager
	layer = 6
	is_typing = false
	_build()


func _exit_tree() -> void:
	is_typing = false


# ------------------------------------------------------------------ build

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Two small round buttons under the pause button (top-left): chat and quick chat
	var chat_button := _round_button("Chat", 9, Vector2(12, 106))
	chat_button.tooltip_text = "Chat with your team (Enter)\nShift+Enter: everyone"
	chat_button.pressed.connect(func() -> void: _open_input(true))
	root.add_child(chat_button)
	var quick_button := _round_button("!", 18, Vector2(12, 146))
	quick_button.tooltip_text = "Quick chat (keys 1-6)"
	quick_button.pressed.connect(func() -> void: _quick_panel.visible = not _quick_panel.visible)
	root.add_child(quick_button)

	_quick_panel = VBoxContainer.new()
	_quick_panel.position = Vector2(54, 146)
	_quick_panel.add_theme_constant_override("separation", 3)
	_quick_panel.visible = false
	root.add_child(_quick_panel)
	for i in QUICK_CHAT.size():
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, QUICK_CHAT[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 24)
		b.add_theme_font_override("font", FONT)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_stylebox_override("normal", _flat(Color(0.05, 0.08, 0.1, 0.85), 6))
		b.add_theme_stylebox_override("hover", _flat(Color(0.15, 0.25, 0.3, 0.9), 6))
		b.add_theme_stylebox_override("pressed", _flat(Color(0.25, 0.4, 0.45, 0.95), 6))
		b.pressed.connect(func() -> void: send_quick_chat(i))
		_quick_panel.add_child(b)

	# Chat log: newest at the bottom, lines fade out after a while
	_log = VBoxContainer.new()
	_log.position = Vector2(54, 190)
	_log.size = Vector2(360, 160)
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 1)
	root.add_child(_log)

	# Typing line (hidden until Enter / the Chat button)
	_input_row = HBoxContainer.new()
	_input_row.position = Vector2(54, 352)
	_input_row.size = Vector2(380, 26)
	_input_row.add_theme_constant_override("separation", 4)
	_input_row.visible = false
	root.add_child(_input_row)
	_mode_button = Button.new()
	_mode_button.focus_mode = Control.FOCUS_NONE
	_mode_button.custom_minimum_size = Vector2(52, 26)
	_mode_button.add_theme_font_override("font", FONT)
	_mode_button.add_theme_font_size_override("font_size", 11)
	_mode_button.add_theme_stylebox_override("normal", _flat(Color(0.05, 0.08, 0.1, 0.85), 6))
	_mode_button.add_theme_stylebox_override("hover", _flat(Color(0.15, 0.25, 0.3, 0.9), 6))
	_mode_button.add_theme_stylebox_override("pressed", _flat(Color(0.25, 0.4, 0.45, 0.95), 6))
	_mode_button.tooltip_text = "Team / everyone (Tab)"
	_mode_button.pressed.connect(func() -> void:
		_set_mode(not _team_only)
		_input.grab_focus())
	_input_row.add_child(_mode_button)
	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.max_length = MAX_LENGTH
	_input.placeholder_text = "Message...  (Enter: send, Esc: close)"
	_input.add_theme_font_size_override("font_size", 12)
	_input.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0.7), 6))
	_input.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0.8), 6))
	_input.text_submitted.connect(_on_text_submitted)
	_input.focus_exited.connect(_close_input)
	_input.gui_input.connect(_on_input_gui_input)
	_input_row.add_child(_input)
	_set_mode(true)


func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(4)
	s.anti_aliasing = true
	return s


func _round_button(text: String, font_size: int, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.position = pos
	b.size = Vector2(34, 34)
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", font_size)
	var normal := _flat(Color(0.06, 0.1, 0.13, 0.8), 17)
	normal.border_color = Color(0.85, 0.7, 0.3, 0.9)
	normal.set_border_width_all(2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.3, 0.35, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	return b


# ------------------------------------------------------------------ local input

func _unhandled_input(event: InputEvent) -> void:
	if is_typing or PauseMenu.is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key == KEY_ENTER or key == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_open_input(not event.shift_pressed)
		elif key >= KEY_1 and key < KEY_1 + QUICK_CHAT.size():
			get_viewport().set_input_as_handled()
			send_quick_chat(key - KEY_1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.alt_pressed:
		var ground = _ground_under(event.position)
		if ground != null:
			get_viewport().set_input_as_handled()
			request_ping(ground)


## The point on the ground (y = 0) under [param screen_pos], null if the camera can't see it
func _ground_under(screen_pos: Vector2):
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if dir.y > -0.01:
		return null
	return from + dir * (-from.y / dir.y)


func _set_mode(team_only: bool) -> void:
	_team_only = team_only
	_mode_button.text = "Team" if team_only else "All"
	_mode_button.add_theme_color_override("font_color", COLOR_ALLY if team_only else Color(1, 0.85, 0.35))


func _open_input(team_only: bool) -> void:
	_quick_panel.visible = false
	_set_mode(team_only)
	_input.text = ""
	_input_row.visible = true
	is_typing = true
	_input.grab_focus.call_deferred()


func _close_input() -> void:
	if not _input_row.visible:
		return
	_input_row.visible = false
	is_typing = false
	if _input.has_focus():
		_input.release_focus()


func _on_input_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.is_action_pressed("ui_cancel"):
		_input.accept_event()  # Esc closes the chat, not the pause menu
		_close_input()
	elif event.physical_keycode == KEY_TAB:
		_input.accept_event()
		_set_mode(not _team_only)


func _on_text_submitted(text: String) -> void:
	var clean := _clean(text)
	if not clean.is_empty():
		send_chat.rpc_id(GameDefines.HOST_ID, clean, _team_only)
	_close_input()


func send_quick_chat(index: int) -> void:
	_quick_panel.visible = false
	if index < 0 or index >= QUICK_CHAT.size():
		return
	send_chat.rpc_id(GameDefines.HOST_ID, QUICK_CHAT[index], not QUICK_CHAT_TO_ALL.has(index))


## Ping [param world_pos] for the team (minimap click / Alt + click)
func request_ping(world_pos: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _local_ping_ready:
		return
	_local_ping_ready = now + PING_GAP
	send_ping.rpc_id(GameDefines.HOST_ID, world_pos)


static func _clean(text: String) -> String:
	return text.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(MAX_LENGTH)


# ------------------------------------------------------------------ server

func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()


## Server: false when [param peer] sent a [param kind] less than [param gap] seconds ago
func _allow(peer: int, kind: String, gap: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var last: Dictionary = _last_sent.get(peer, {})
	if now - float(last.get(kind, -100.0)) < gap:
		return false
	last[kind] = now
	_last_sent[peer] = last
	return true


## Server: connected players who get a message of [param sender] (its team, or everyone)
func _recipients(sender: int, team_only: bool) -> Array[int]:
	var ids: Array[int] = []
	var status: Dictionary = match_manager.game_play_network.hero_selection_status
	if not status.has(sender):
		return ids
	var team := int(status[sender][GameDefines.TEAM_SIDE])
	var connected := multiplayer.get_peers()
	connected.append(multiplayer.get_unique_id())
	for peer in status:
		var pid := int(peer)
		if not connected.has(pid):
			continue
		if team_only and int(status[peer][GameDefines.TEAM_SIDE]) != team:
			continue
		ids.append(pid)
	return ids


@rpc("any_peer", "call_local", "reliable")
func send_chat(text: String, team_only: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := _sender()
	text = _clean(text)
	if text.is_empty() or not _allow(sender, "chat", CHAT_GAP):
		return
	for pid in _recipients(sender, team_only):
		if pid == multiplayer.get_unique_id():
			receive_chat(sender, text, team_only)
		else:
			receive_chat.rpc_id(pid, sender, text, team_only)


@rpc("any_peer", "call_local", "reliable")
func send_ping(world_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := _sender()
	if not _allow(sender, "ping", PING_GAP):
		return
	var pos := Vector3(clampf(world_pos.x, -WORLD_HALF, WORLD_HALF), 0.0, clampf(world_pos.z, -WORLD_HALF, WORLD_HALF))
	for pid in _recipients(sender, true):
		if pid == multiplayer.get_unique_id():
			receive_ping(sender, pos)
		else:
			receive_ping.rpc_id(pid, sender, pos)


# ------------------------------------------------------------------ every peer

@rpc("authority", "call_remote", "reliable")
func receive_chat(sender: int, text: String, team_only: bool) -> void:
	var channel := "[color=#9aa4a8][Team][/color] " if team_only else "[color=#ffd75a][All][/color] "
	_add_line("%s[color=#%s]%s[/color]: %s" % [channel, _color_of(sender).to_html(false), _escape(_name_of(sender)), _escape(text)])
	Sfx.play_ui(get_tree(), "click", -10.0)


@rpc("authority", "call_remote", "reliable")
func receive_ping(sender: int, pos: Vector3) -> void:
	pings.append({"pos": pos, "left": PING_TIME})
	_spawn_ping_marker(pos)
	_add_line("[color=#%s]%s[/color] [color=#ffd75a]pinged the map[/color]" % [_color_of(sender).to_html(false), _escape(_name_of(sender))])
	Sfx.play_ui(get_tree(), "click", -4.0)


func _process(delta: float) -> void:
	for i in range(pings.size() - 1, -1, -1):
		pings[i]["left"] = float(pings[i]["left"]) - delta
		if pings[i]["left"] <= 0.0:
			pings.remove_at(i)


func _name_of(peer: int) -> String:
	var s: Dictionary = match_manager.stats.get(peer, {})
	if s.is_empty():
		var info: Dictionary = match_manager.game_play_network.hero_selection_status.get(peer, {})
		return str(info.get(GameDefines.NAME, "?"))
	var data := CharacterDB.get_character(int(s["hero"]))
	return "%s (%s)" % [s["name"], data.name if data != null else "?"]


func _color_of(peer: int) -> Color:
	if peer == multiplayer.get_unique_id():
		return Color.WHITE
	var status: Dictionary = match_manager.game_play_network.hero_selection_status
	if not status.has(peer):
		return Color.WHITE
	return COLOR_ALLY if int(status[peer][GameDefines.TEAM_SIDE]) == match_manager.my_team() else COLOR_ENEMY


## Players' text can't add BBCode tags
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _add_line(bbcode: String) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(360, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_override("normal_font", FONT)
	line.add_theme_font_size_override("normal_font_size", 12)
	line.add_theme_constant_override("outline_size", 4)
	line.add_theme_color_override("font_outline_color", Color.BLACK)
	line.text = bbcode
	_log.add_child(line)
	while _log.get_child_count() > LOG_MAX:
		var old := _log.get_child(0)
		_log.remove_child(old)
		old.queue_free()
	var tween := line.create_tween()
	tween.tween_interval(LOG_TIME)
	tween.tween_property(line, "modulate:a", 0.0, 0.8)
	tween.tween_callback(line.queue_free)


## Yellow ring pulsing on the ground (seen through props) for PING_TIME seconds
func _spawn_ping_marker(pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = PING_COLOR
	var torus := TorusMesh.new()
	torus.inner_radius = 1.1
	torus.outer_radius = 1.45
	torus.material = mat
	var marker := MeshInstance3D.new()
	marker.mesh = torus
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(marker)
	marker.global_position = Vector3(pos.x, 0.15, pos.z)
	var tween := marker.create_tween()
	var pulses := 3
	for i in pulses:
		tween.tween_property(marker, "scale", Vector3.ONE * 1.8, (PING_TIME - 0.4) / pulses).from(Vector3.ONE * 0.4)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.tween_callback(marker.queue_free)
