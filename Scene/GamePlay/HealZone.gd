class_name HealZone
extends Node3D
## Healing circle at a team's spawn: heroes of [member team] standing in it get back
## HEAL_PERCENT of their max hp every TICK seconds (host only). Drawn green for your own team,
## red for the enemy's.

@export var team := 0
@export var radius := 7.0

const HEAL_PERCENT := 0.06
const TICK := 0.5

var _timer := 0.0
var _ring_material: StandardMaterial3D
var _disc_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("heal_zone")
	_build()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or MatchManager.is_over: return
	_timer += delta
	if _timer < TICK: return
	_timer -= TICK
	var spawner := get_tree().current_scene.get_node_or_null("HeroSpawner") as HeroSpawner
	if spawner == null: return
	for hero in spawner.player_list.values():
		if not is_instance_valid(hero) or not hero.is_inside_tree() or hero.team_side != team or hero.is_dead():
			continue
		var d := Vector2(hero.global_position.x - global_position.x, hero.global_position.z - global_position.z)
		if d.length() <= radius:
			hero.heal(ceili(hero.max_hp() * HEAL_PERCENT))


func _process(_delta: float) -> void:
	# The local team is only known once the heroes exist: keep the color right
	var c := _color()
	if _ring_material.albedo_color != c:
		_ring_material.albedo_color = c
		_disc_material.albedo_color = Color(c.r, c.g, c.b, 0.12)


func _color() -> Color:
	var spawner := get_tree().current_scene.get_node_or_null("HeroSpawner") as HeroSpawner
	if spawner != null:
		var me = spawner.get_player(multiplayer.get_unique_id())
		if me != null and me.team_side != team:
			return Color(0.95, 0.3, 0.25)
	return Color(0.3, 0.9, 0.4)


func _build() -> void:
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 40
	disc.mesh = disc_mesh
	_disc_material = StandardMaterial3D.new()
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = _disc_material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.1
	add_child(disc)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius - 0.2
	ring_mesh.outer_radius = radius
	ring_mesh.rings = 40
	ring_mesh.ring_segments = 6
	ring.mesh = ring_mesh
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.1
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = _ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_ring_material.albedo_color = Color.BLACK  # forces the first _process update
