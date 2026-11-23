class_name Music
extends RefCounted
## Background music of the menus (main menu, lobby, room, hero select). It lives under the tree
## root, so it keeps playing across those scene changes; the match itself has no music
## (GamePlay calls stop()) so nothing distracts from the fight.

const MENU_MUSIC := "res://Asset/Audio/Music/jrpg_battle_full.mp3"
const VOLUME_DB := -16.0
const NODE_NAME := "MenuMusic"


## Starts the menu music (does nothing if it is already playing)
static func play_menu(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	var player := tree.root.get_node_or_null(NODE_NAME) as AudioStreamPlayer
	if player != null and player.playing:
		return
	if player != null:
		player.name = NODE_NAME + "_old"
		player.queue_free()
	if not ResourceLoader.exists(MENU_MUSIC):
		return
	var stream := load(MENU_MUSIC) as AudioStream
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", true)
	player = AudioStreamPlayer.new()
	player.bus = GraphicsSettings.MUSIC_BUS
	player.name = NODE_NAME
	player.stream = stream
	player.volume_db = -40.0
	tree.root.add_child.call_deferred(player)
	player.ready.connect(func() -> void:
		player.play()
		player.create_tween().tween_property(player, "volume_db", VOLUME_DB, 1.5))


## Fades the menu music out (entering a match)
static func stop(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	var player := tree.root.get_node_or_null(NODE_NAME) as AudioStreamPlayer
	if player == null or player.has_meta("stopping"):
		return
	# Renamed: a play_menu() during the fade starts a new one instead of finding this one
	player.name = NODE_NAME + "_fading"
	player.set_meta("stopping", true)
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", -40.0, 0.8)
	tween.tween_callback(player.queue_free)
