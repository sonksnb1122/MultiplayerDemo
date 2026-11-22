class_name SkillIndicator
extends Node3D
## Local-only aiming helper, shown while a skill key is held (the skill is cast on release):
##   - a ring on the ground at the skill's range around the hero
##   - the area that will be hit (circle) at the aim point / on the target / around the hero
## Lives in the world (top level) so it doesn't turn with the hero.

var _range_ring: MeshInstance3D
var _area_disc: MeshInstance3D
var _area_ring: MeshInstance3D
var _line: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D

const HEIGHT := 0.15


func _init() -> void:
	top_level = true
	_ring_mat = _material(Color.WHITE, false)
	_disc_mat = _material(Color(1, 1, 1, 0.2), true)
	_range_ring = _ring()
	_area_ring = _ring()
	_area_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	_area_disc.mesh = disc
	_area_disc.material_override = _disc_mat
	_area_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_area_disc)
	_line = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 0.02, 1)
	_line.mesh = box
	_line.material_override = _disc_mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	visible = false


func _ring() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	m.mesh = torus
	m.material_override = _ring_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _material(color: Color, transparent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true  # stay visible over the ground tiles and props
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## [param hero_pos]: caster, [param range_radius]: 0 = no range ring,
## [param area_center] / [param area_radius]: the area to hit (radius 0 = none)
func show_at(color: Color, hero_pos: Vector3, range_radius: float, area_center: Vector3, area_radius: float) -> void:
	visible = true
	_line.visible = false
	_ring_mat.albedo_color = color
	_disc_mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	_range_ring.visible = range_radius > 0.0
	if range_radius > 0.0:
		_range_ring.global_position = Vector3(hero_pos.x, HEIGHT, hero_pos.z)
		# Flat ring: thin in y
		_range_ring.scale = Vector3(range_radius, 0.05, range_radius)
	var show_area := area_radius > 0.0
	_area_disc.visible = show_area
	_area_ring.visible = show_area
	if show_area:
		var c := Vector3(area_center.x, HEIGHT, area_center.z)
		_area_disc.global_position = c
		_area_disc.scale = Vector3(area_radius, 1, area_radius)
		_area_ring.global_position = c
		_area_ring.scale = Vector3(area_radius, 0.05, area_radius)


## Straight path from [param from] along [param dir] (skill shots)
func show_line(color: Color, from: Vector3, dir: Vector3, length: float, width: float) -> void:
	show_at(color, from, 0.0, from, 0.0)
	_line.visible = true
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	if flat.length() < 0.5:
		flat = Vector3.FORWARD
	var mid := Vector3(from.x, HEIGHT, from.z) + flat * length * 0.5
	_line.global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), mid)
	_line.scale = Vector3(width * 2.0, 1, length)


func hide_indicator() -> void:
	visible = false
