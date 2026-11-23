class_name SkillVfx
extends RefCounted
## Helpers to spawn and remove the skill VFX from the different packs the same way:
## - Emberset scenes (EmbersetEffect): set "size"/"hue_shift" before adding, they autoplay, stop() fades them.
## - BinbunVFX Vol2 scenes (VFXEmitterBB): open() to start, close() to fade out.
## - Anything else (tornado): scaled in and out with a tween.

static var _cache: Dictionary = {}
## Resized particle quads, shared between casts (see _scale_aligned_particles)
static var _scaled_quads: Dictionary = {}
## Dynamic lights from effects at the same time: each one costs every lit object near it
## (the Mobile renderer draws them per object). Extra effects simply come without their light.
const MAX_VFX_LIGHTS := 4


static func load_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if not _cache.has(path):
		# Usually already loaded in the background (AssetPreloader)
		var res := AssetPreloader.get_scene(path)
		if res == null:
			push_error("SkillVfx: can't load scene %s" % path)
		_cache[path] = res
	return _cache[path]


static func instantiate(path: String, scale_value: float, hue_shift := 0.0) -> Node3D:
	var packed := load_scene(path)
	if packed == null:
		return null
	var fx := packed.instantiate() as Node3D
	if fx == null:
		return null
	_disable_shadows(fx)
	for node in fx.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).bus = GraphicsSettings.SFX_BUS
	if GraphicsSettings.low_quality:
		_low_quality(fx)
	var ember := fx as EmbersetEffect
	if ember != null:
		ember.size = scale_value
		if hue_shift != 0.0:
			ember.hue_shift = hue_shift
	else:
		fx.scale = Vector3.ONE * scale_value
		_scale_aligned_particles(fx, scale_value)
	return fx


## Glowing VFX don't need to cast shadows: skipping them saves drawing every particle a second
## time into the shadow map.
static func _disable_shadows(fx: Node) -> void:
	if fx is GeometryInstance3D:
		(fx as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node in fx.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node in fx.find_children("*", "Light3D", true, false):
		(node as Light3D).shadow_enabled = false


## Low graphics (F8): no dynamic light from the effect, half the particles
static func _low_quality(fx: Node) -> void:
	for node in fx.find_children("*", "Light3D", true, false):
		(node as Light3D).visible = false
	for node in fx.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		particles.amount_ratio = 0.5
		# Simulated at 30 steps a second (drawn smoothly, interpolated)
		if particles.fixed_fps > 30:
			particles.fixed_fps = 30
			particles.interpolate = true


## At most MAX_VFX_LIGHTS effect lights at once (group "vfx_light"; freed lights leave it)
static func _limit_lights(fx: Node3D) -> void:
	var tree := fx.get_tree()
	if tree == null:
		return
	var active := tree.get_nodes_in_group("vfx_light").size()
	for node in fx.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if not light.visible:
			continue
		if active >= MAX_VFX_LIGHTS:
			light.visible = false
		else:
			light.add_to_group("vfx_light")
			active += 1


## Particles with a transform_align mode rebuild their own rotation, which drops the node scale:
## their quads keep the original size while everything else grows. Resize those quads to match.
static func _scale_aligned_particles(fx: Node, scale_value: float) -> void:
	if is_equal_approx(scale_value, 1.0):
		return
	for node in fx.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		if particles.transform_align == GPUParticles3D.TRANSFORM_ALIGN_DISABLED:
			continue
		var quad := particles.draw_pass_1 as QuadMesh
		if quad == null:
			continue
		# One resized copy per (quad, size), shared by every cast instead of a new mesh each time
		var key := "%d:%.3f" % [quad.get_instance_id(), scale_value]
		if not _scaled_quads.has(key):
			var copy := quad.duplicate() as QuadMesh
			copy.size *= scale_value
			_scaled_quads[key] = copy
		particles.draw_pass_1 = _scaled_quads[key]


## Spawns a VFX as a child of [param parent] (follows it). Looping VFX stay until [method stop_and_free].
static func spawn_attached(parent: Node3D, path: String, offset: Vector3, scale_value: float, _looping := true, hue_shift := 0.0) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var fx := instantiate(path, scale_value, hue_shift)
	if fx == null:
		return null
	parent.add_child(fx)
	fx.position = offset
	_start(fx)
	return fx


## Spawns a VFX in the world at [param world_position]. One-shot Emberset effects free themselves;
## everything else is removed after [param lifetime] seconds.
static func spawn_world(world: Node, path: String, world_position: Vector3, scale_value: float, lifetime: float, pop_in := false, facing := Vector3.ZERO) -> Node3D:
	if world == null or not world.is_inside_tree():
		return null
	var fx := instantiate(path, scale_value)
	if fx == null:
		return null
	var ember := fx as EmbersetEffect
	if ember != null:
		ember.auto_free = true
	world.add_child(fx)
	fx.global_position = world_position
	if facing.length() > 0.01:
		fx.look_at(world_position + facing, Vector3.UP)
	if pop_in:
		var full := fx.scale
		fx.scale = full * 0.05
		fx.set_meta("pop", full)
		fx.create_tween().tween_property(fx, "scale", full, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_start(fx)
	var self_freeing := ember != null and ember.one_shot
	if lifetime > 0.0 and not self_freeing:
		var fx_ref: WeakRef = weakref(fx)  # the effect may be freed first (scene change): no dead capture
		fx.get_tree().create_timer(lifetime).timeout.connect(func() -> void:
			var node = fx_ref.get_ref()
			if node != null:
				stop_and_free(node))
	return fx


static func stop_and_free(fx: Node3D) -> void:
	if not is_instance_valid(fx):
		return
	if not fx.is_inside_tree():
		fx.queue_free()
		return
	var delay := 0.0
	var ember := fx as EmbersetEffect
	if ember != null:
		ember.auto_free = true
		ember.stop()
		delay = 2.0  # safety net: stop() frees it once the effect has died out
	elif fx.has_method("close"):
		fx.call("close")
		delay = 1.2
	if fx.has_meta("pop"):
		fx.create_tween().tween_property(fx, "scale", fx.scale * 0.05, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		delay = maxf(delay, 0.3)
	if delay <= 0.0:
		fx.queue_free()
		return
	var fx_ref: WeakRef = weakref(fx)
	fx.get_tree().create_timer(delay).timeout.connect(func() -> void:
		var node = fx_ref.get_ref()
		if node != null:
			node.queue_free())


static func _start(fx: Node3D) -> void:
	_limit_lights(fx)
	# Emberset effects autoplay on enter tree; Binbun Vol2 emitters need open().
	if not (fx is EmbersetEffect) and fx.has_method("open"):
		fx.call("open")
