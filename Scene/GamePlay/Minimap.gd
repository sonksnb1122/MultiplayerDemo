class_name Minimap
extends Control
## Small map in the corner of the HUD.
## White dot = me, green dots = teammates, red dots = enemies.
## Positions are read from the heroes already synced on this peer, so it works on host and clients.

## Half of the arena size in world units (ground is 200 x 200, centered at 0)
@export var world_half_size := 100.0
@export var dot_radius := 2.5
@export var self_dot_radius := 3.5
@export var redraw_rate := 15.0

const COLOR_BG := Color(0.05, 0.06, 0.08, 0.75)
const COLOR_BORDER := Color(0.85, 0.7, 0.3, 0.9)
const COLOR_SELF := Color(1, 1, 1)
const COLOR_TEAMMATE := Color(0.25, 0.9, 0.3)
const COLOR_ENEMY := Color(0.95, 0.2, 0.2)
const COLOR_OUTLINE := Color(0, 0, 0, 0.8)

var _hero_spawner: Node
var _redraw_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_redraw_timer -= delta
	if _redraw_timer > 0.0: return
	_redraw_timer = 1.0 / redraw_rate
	queue_redraw()


func _get_spawner() -> Node:
	if not is_instance_valid(_hero_spawner):
		var scene := get_tree().current_scene
		if scene != null:
			_hero_spawner = scene.get_node_or_null("HeroSpawner")
	return _hero_spawner


func _world_to_map(pos: Vector3) -> Vector2:
	# Camera looks toward -Z: world X goes right, world Z goes down on the map
	var u := clampf((pos.x + world_half_size) / (world_half_size * 2.0), 0.0, 1.0)
	var v := clampf((pos.z + world_half_size) / (world_half_size * 2.0), 0.0, 1.0)
	return Vector2(u * size.x, v * size.y)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, COLOR_BG)
	# Middle line between the two team sides
	draw_line(Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, size.y), Color(1, 1, 1, 0.15), 1.0)
	draw_rect(rect, COLOR_BORDER, false, 2.0)

	var spawner := _get_spawner()
	if spawner == null: return
	var my_id := multiplayer.get_unique_id()
	var me = spawner.player_list.get(my_id)
	var my_side = me.team_side if is_instance_valid(me) else -1

	for peer_id in spawner.player_list:
		if peer_id == my_id: continue
		var hero = spawner.player_list[peer_id]
		if not is_instance_valid(hero) or not hero.is_inside_tree(): continue
		if hero.is_dead(): continue
		var color := COLOR_TEAMMATE if hero.team_side == my_side else COLOR_ENEMY
		_draw_dot(_world_to_map(hero.global_position), dot_radius, color)

	# Me last, so I am always on top
	if is_instance_valid(me) and me.is_inside_tree():
		var c := COLOR_SELF if not me.is_dead() else Color(1, 1, 1, 0.35)
		_draw_dot(_world_to_map(me.global_position), self_dot_radius, c)


func _draw_dot(p: Vector2, r: float, color: Color) -> void:
	draw_circle(p, r + 1.0, COLOR_OUTLINE)
	draw_circle(p, r, color)
