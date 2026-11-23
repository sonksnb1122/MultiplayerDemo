class_name BasicAttackFx
extends RefCounted
## Visual projectile for ranged basic attacks. Built from plain meshes in code (no particles,
## no lights, no custom shader): cheap to draw and nothing to compile at the first shot.
## To give another hero a projectile, add its CharacterData.id to PROJECTILES.

## id -> look of the projectile
const PROJECTILES := {
	SkillDB.MAGE: {
		"color": Color(0.45, 0.8, 1.0),   # electric blue
		"core_color": Color(0.9, 0.97, 1.0),
		"radius": 0.28,
		"speed": 35.0,                    # units per second
	},
	# Ranger: an arrow from the bow
	SkillDB.RANGER: {
		"model": SkillDB.ARROW_MODEL,
		"model_rotation": SkillDB.ARROW_ROTATION,
		"model_scale": 1.3,
		"color": Color(1.0, 0.95, 0.85),  # faint streak behind it / impact flash
		"radius": 0.08,
		"speed": 45.0,
	},
	# Rogue: a crossbow bolt
	SkillDB.ROGUE: {
		"model": SkillDB.CROSSBOW_BOLT_MODEL,
		"model_rotation": SkillDB.ARROW_ROTATION,
		"model_scale": 1.6,
		"color": Color(0.85, 1.0, 0.85),
		"radius": 0.08,
		"speed": 50.0,
	},
}
## Height the projectile flies at (chest of the heroes)
const HEIGHT := 2.2
## How far in front of the hero it starts
const FORWARD_OFFSET := 0.9

## Shared materials and meshes, created once
static var _materials: Dictionary = {}
static var _sphere: SphereMesh


static func has_projectile(character_id: int) -> bool:
	return PROJECTILES.has(character_id)


static func speed_of(character_id: int) -> float:
	return float(PROJECTILES.get(character_id, {}).get("speed", 35.0))


## Builds the projectile node for [param character_id] (flies with SkillProjectile).
static func create(character_id: int, from: Vector3, target: Node3D, travel_time: float) -> SkillProjectile:
	var look: Dictionary = PROJECTILES.get(character_id, {})
	if look.is_empty():
		return null
	var p := SkillProjectile.new()
	p.name = "BasicAttack"
	p.target = target
	p.travel_time = maxf(travel_time, 0.05)
	p.target_offset = Vector3(0, HEIGHT, 0)
	p.position = from
	var radius: float = look["radius"]
	if look.has("model"):
		var model := _model(look)
		if model != null:
			p.add_child(model)
		# Thin white streak behind the spear
		var streak := _ball(look["color"], radius, true)
		streak.scale = Vector3(radius, radius, radius * 12.0)
		streak.position = Vector3(0, 0, radius * 14.0)
		p.add_child(streak)
		return p
	# Orb: outer glow (transparent, additive) + bright core + a short tail behind it
	p.add_child(_ball(look["color"], radius * 1.8, true))
	p.add_child(_ball(look["core_color"], radius, false))
	var tail := _ball(look["color"], radius, true)
	tail.scale = Vector3(0.7, 0.7, 3.0) * radius
	tail.position = Vector3(0, 0, radius * 2.5)  # +Z is behind (the projectile flies along -Z)
	p.add_child(tail)
	return p


## A 3D model (e.g. the arrow) with every mesh painted in one color, no shadows
static func _model(look: Dictionary) -> Node3D:
	var scene := AssetPreloader.get_scene(look["model"])
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	if model == null:
		return null
	model.rotation_degrees = look.get("model_rotation", Vector3.ZERO)
	model.scale = Vector3.ONE * float(look.get("model_scale", 1.0))
	# "model_color" paints the whole model in one color; without it the model keeps its texture
	var mat: StandardMaterial3D = _solid_material(look["model_color"]) if look.has("model_color") else null
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		if mat != null:
			geo.material_override = mat
		geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model


static func _solid_material(color: Color) -> StandardMaterial3D:
	var key := "solid_%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.4
	mat.roughness = 0.35
	# A little self-light so it stays white even on the shadowed side
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	_materials[key] = mat
	return mat


## Godot compiles a material's shader the first time it is drawn, and skips the object until it
## is ready: that is why the very first projectile was invisible. Draw every projectile once,
## tiny and right in front of the camera, when the match loads. These are our own materials
## (no shared animation, no lights), so this has no side effect on the real projectiles.
static func warm_up(camera: Camera3D, seconds := 0.6) -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var holder := Node3D.new()
	holder.name = "BasicAttackWarmUp"
	camera.add_child(holder)
	holder.position = Vector3(0, 0, -2)
	holder.scale = Vector3.ONE * 0.01
	for id in PROJECTILES:
		var look: Dictionary = PROJECTILES[id]
		if look.has("model"):
			var model := _model(look)
			if model != null:
				holder.add_child(model)
		holder.add_child(_ball(look["color"], 1.0, true))
		if look.has("core_color"):
			holder.add_child(_ball(look["core_color"], 1.0, false))
	var holder_ref: WeakRef = weakref(holder)  # gone already if the scene changed: no dead capture
	camera.get_tree().create_timer(seconds).timeout.connect(func() -> void:
		var node = holder_ref.get_ref()
		if node != null:
			node.queue_free())


## Small flash where the projectile lands
static func spawn_impact(world: Node, at: Vector3, character_id: int) -> void:
	var look: Dictionary = PROJECTILES.get(character_id, {})
	if look.is_empty() or world == null or not world.is_inside_tree():
		return
	var flash := _ball(look["color"], float(look["radius"]) * 2.0, true)
	world.add_child(flash)
	flash.global_position = at
	var tween := flash.create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * 2.2, 0.18).from(Vector3.ONE * 0.4)
	tween.tween_callback(flash.queue_free)


static func _ball(color: Color, radius: float, glow: bool) -> MeshInstance3D:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 12
		_sphere.rings = 6
	var m := MeshInstance3D.new()
	m.mesh = _sphere
	m.scale = Vector3.ONE * radius
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.material_override = _material(color, glow)
	return m


static func _material(color: Color, glow: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	else:
		mat.albedo_color = color
	_materials[key] = mat
	return mat
