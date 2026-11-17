class_name SkillProjectile
extends Node3D
## Visual-only projectile: homes in on a target and arrives exactly after [member travel_time].
## The server applies the hit on its own timer, so every peer sees the impact at the same moment.
## The node's -Z axis is the flight direction.

var target: Node3D
var target_offset := Vector3(0, 1.6, 0)
var travel_time := 0.5

var _elapsed := 0.0
var _aim := Vector3.ZERO


static func create(skill: SkillData, from: Vector3, target_node: Node3D, time: float) -> SkillProjectile:
	var p := SkillProjectile.new()
	p.name = "Projectile_" + skill.id
	p.target = target_node
	p.travel_time = maxf(time, 0.05)
	p.target_offset = Vector3(0, skill.projectile_height, 0)
	p.position = from

	if not skill.projectile_model.is_empty():
		var model_scene := SkillVfx.load_scene(skill.projectile_model)
		if model_scene != null:
			var model := model_scene.instantiate() as Node3D
			if model != null:
				model.name = "Model"
				model.rotation_degrees = skill.projectile_model_rotation
				model.scale = Vector3.ONE * skill.projectile_model_scale
				p.add_child(model)

	if not skill.vfx_scene.is_empty():
		var fx := SkillVfx.instantiate(skill.vfx_scene, skill.vfx_scale)
		if fx != null:
			fx.name = "Vfx"
			fx.rotation_degrees = skill.projectile_vfx_rotation
			p.add_child(fx)
	return p


func _ready() -> void:
	_aim = _target_point()
	_face(_aim)
	var fx := get_node_or_null("Vfx")
	if fx != null and fx.has_method("open"):
		fx.call("open")


func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(target):
		_aim = _target_point()
	var remaining := travel_time - _elapsed
	if remaining <= 0.0:
		global_position = _aim
		queue_free()
		return
	var to_target := _aim - global_position
	global_position += to_target * minf(delta / remaining, 1.0)
	_face(_aim)


func _target_point() -> Vector3:
	if is_instance_valid(target):
		return target.global_position + target_offset
	return _aim


func _face(point: Vector3) -> void:
	var dir := point - global_position
	if dir.length() < 0.05:
		return
	# look_at fails when the direction is parallel to the up vector.
	if absf(dir.normalized().dot(Vector3.UP)) > 0.99:
		return
	look_at(point, Vector3.UP)
