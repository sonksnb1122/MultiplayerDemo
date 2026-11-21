class_name MainMenu
extends Control

@onready var lobby_scene = $LobbyScene
@onready var menu_hub = $MenuHub

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if NetworkManager.disconnected_reason in [GameDefines.DisconnectReason.HOST_CLOSED_ROOM, GameDefines.DisconnectReason.BACK_TO_LOBBY]:
		go_to_lobby()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_play_button_pressed() -> void:
	go_to_lobby()

func go_to_lobby():
	menu_hub.visible = false
	lobby_scene.visible = true
func _on_quit_button_pressed() -> void:
	get_tree().quit()
	pass # Replace with function body.


func _on_lobby_scene_back_to_main_menu() -> void:
	menu_hub.visible = true
	lobby_scene.visible = false
