class_name PauseMenu
extends CanvasLayer
## In-game menu opened with ESC. The game keeps running underneath (nothing is paused):
## it only hides the battle controls of the local player while it is open.

## True while the menu is open: Player, SkillCaster and the camera ignore the player's input.
static var is_open := false

@onready var root: Control = $Root
@onready var exit_button: Button = $Root/Center/Panel/Margin/VBox/ExitButton
@onready var quit_button: Button = $Root/Center/Panel/Margin/VBox/QuitButton
## Always-visible button in the bottom-left corner: pause icon opens the menu, play icon closes it.
@onready var pause_button: TextureButton = $PauseButton

const PAUSE_ICON := preload("res://Asset/Art/Branding/btn_pause.png")
const PLAY_ICON := preload("res://Asset/Art/Branding/btn_play.png")


func _ready() -> void:
	root.visible = false
	is_open = false
	exit_button.pressed.connect(_on_exit_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	pause_button.pressed.connect(toggle)
	# Small "press" feedback on the corner button
	pause_button.button_down.connect(func() -> void: pause_button.scale = Vector2.ONE * 0.9)
	pause_button.button_up.connect(func() -> void: pause_button.scale = Vector2.ONE)
	_update_pause_button()


func _exit_tree() -> void:
	is_open = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		toggle()


func toggle() -> void:
	set_open(not root.visible)


func set_open(value: bool) -> void:
	root.visible = value
	is_open = value
	_update_pause_button()
	if value:
		exit_button.grab_focus()


func _update_pause_button() -> void:
	pause_button.texture_normal = PLAY_ICON if root.visible else PAUSE_ICON
	pause_button.tooltip_text = "Resume (ESC)" if root.visible else "Menu (ESC)"


func _on_exit_button_pressed() -> void:
	set_open(false)
	# Leave the match: a host closes the room (clients go back to the lobby on their own),
	# a client just disconnects (its hero is removed on the other peers).
	NetworkManager.quit_room()
	NetworkManager.disconnected_reason = GameDefines.DisconnectReason.NONE
	get_tree().change_scene_to_file(GameDefines.MAIN_MENU_SCENE)


func _on_quit_button_pressed() -> void:
	NetworkManager.quit_room()
	get_tree().quit()
