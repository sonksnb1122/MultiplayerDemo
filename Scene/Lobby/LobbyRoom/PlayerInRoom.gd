extends Panel

@onready var avatar = $Ctn/Avatar
@onready var player_name: Label = $Ctn/Name
@onready var ready_status = $Ctn/Status/Ready
@onready var idle_status = $Ctn/Status/Idle

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_player_info(player_info: Dictionary, is_host: bool):
	var name = player_info[GameDefines.NAME]
	if is_host:
		name += " (Host)"
	player_name.text = name
	
	var is_ready = player_info[GameDefines.READY]
	ready_status.visible = is_ready
	idle_status.visible = !is_ready
	
	
	
