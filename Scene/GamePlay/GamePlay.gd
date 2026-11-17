extends Node3D
class_name GamePlay

@onready var game_play_network: GamePlayNetwork = $GamePlayNetwork
@onready var player_hud = $CanvasLayer/PlayerHud

var game_started = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	game_play_network.start_game.connect(_on_game_started)
	game_play_network.play_time_trigged.connect(_on_play_time_trigged)
	game_play_network.heroes_status_updated.connect(_on_heroes_status_updated)
	# Compile the basic-attack projectile shaders now, so the first shot is visible
	BasicAttackFx.warm_up(_get_camera())

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _get_camera() -> Camera3D:
	return $Camera3D
	
func _on_game_started():
	game_started = true
	var loading_screen = get_node_or_null("LoadingScreen")
	if loading_screen != null:
		loading_screen.finish()
		
func _on_heroes_status_updated(heroes_status: Dictionary):
	player_hud.set_heroes_status(heroes_status)
	
func _on_play_time_trigged(time: int):
	player_hud.set_timer_label(time)

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://Scene/MainMenu/MainMenu.tscn")
