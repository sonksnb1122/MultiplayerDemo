class_name Bush
extends Node3D
## Tall grass. A hero standing in it is hidden from the enemy team (model, hp bar, minimap, can't
## be clicked or targeted) unless an enemy is in the same bush or comes closer than REVEAL_DISTANCE.
## The rule itself (with the vision radius) is in Vision.is_hidden.

## Size on the ground (x, z), centered on the node
@export var size := Vector2(8, 5)

## Enemies closer than this always see you, bush or not
const REVEAL_DISTANCE := 4.0
const LEAF_COLORS := [Color(0.22, 0.45, 0.16), Color(0.27, 0.52, 0.18), Color(0.18, 0.38, 0.14)]

static var _leaf_mesh: SphereMesh
static var _leaf_materials: Array = []


func _ready() -> void:
	add_to_group("bush")
	_build()


func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.y * 0.5


static func bush_at(tree: SceneTree, point: Vector3) -> Bush:
	for node in tree.get_nodes_in_group("bush"):
		var bush := node as Bush
		if bush != null and bush.contains(point):
			return bush
	return null


# ------------------------------------------------------------------ look: a cluster of low-poly leaf balls

func _build() -> void:
	if _leaf_mesh == null:
		_leaf_mesh = SphereMesh.new()
		_leaf_mesh.radius = 1.0
		_leaf_mesh.height = 1.6
		_leaf_mesh.radial_segments = 8
		_leaf_mesh.rings = 4
		for c in LEAF_COLORS:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 1.0
			_leaf_materials.append(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) ^ int(global_position.x * 13.0) ^ int(global_position.z * 7.0)
	var step := 1.6
	var x := -size.x * 0.5 + step * 0.5
	while x < size.x * 0.5:
		var z := -size.y * 0.5 + step * 0.5
		while z < size.y * 0.5:
			var leaf := MeshInstance3D.new()
			leaf.mesh = _leaf_mesh
			leaf.material_override = _leaf_materials[rng.randi() % _leaf_materials.size()]
			leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var r := rng.randf_range(0.9, 1.3)
			leaf.scale = Vector3(r, rng.randf_range(0.9, 1.4), r)
			leaf.position = Vector3(x + rng.randf_range(-0.4, 0.4), 0.6, z + rng.randf_range(-0.4, 0.4))
			add_child(leaf)
			z += step
		x += step
