class_name HpBar3D
extends Node3D
## Hp bar over a hero: two quads that always face the camera (dark background + colored fill cut
## to the hp left). Replaces the old SubViewport + ProgressBar + Sprite3D, which needed one extra
## render target (texture) per hero. Used the same way as that ProgressBar:
## max_value, value, add_theme_stylebox_override("fill", <StyleBoxTexture>).

## Size in world units (the old 400 x 60 px viewport shown at 0.01 per pixel)
const SIZE := Vector2(4.0, 0.6)
const BORDER := 0.05
const BACKGROUND := Color(0.05, 0.05, 0.05, 0.8)

var max_value := 100.0:
	set(v):
		max_value = maxf(v, 1.0)
		_update()
var value := 100.0:
	set(v):
		value = v
		_update()

var _fill_texture: Texture2D
var _bg: MeshInstance3D
var _fill: MeshInstance3D


func _ready() -> void:
	_bg = _make_quad(BACKGROUND, null, 0)
	(_bg.mesh as QuadMesh).size = SIZE + Vector2(BORDER, BORDER) * 2.0
	_fill = _make_quad(Color.WHITE, _fill_texture, 1)
	_update()


## Same call as on the ProgressBar: only the "fill" texture is used
func add_theme_stylebox_override(theme_name: StringName, stylebox: StyleBox) -> void:
	if theme_name != &"fill":
		return
	var box := stylebox as StyleBoxTexture
	_fill_texture = box.texture if box != null else null
	if _fill != null:
		(_fill.material_override as StandardMaterial3D).albedo_texture = _fill_texture


func _make_quad(color: Color, texture: Texture2D, priority: int) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_color = color
	mat.albedo_texture = texture
	# Fill drawn after the background
	mat.render_priority = priority
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	return quad


## The fill keeps its left edge and is cut on the right (texture cut, not squeezed)
func _update() -> void:
	if _fill == null:
		return
	var ratio := clampf(value / max_value, 0.0, 1.0)
	_fill.visible = ratio > 0.0
	var quad := _fill.mesh as QuadMesh
	quad.size = Vector2(maxf(SIZE.x * ratio, 0.001), SIZE.y)
	quad.center_offset = Vector3(-SIZE.x * (1.0 - ratio) * 0.5, 0.0, 0.0)
	(_fill.material_override as StandardMaterial3D).uv1_scale = Vector3(ratio, 1.0, 1.0)
