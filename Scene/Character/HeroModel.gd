class_name HeroModel
extends Character
## A hero built from a KayKit character (CC0, Kay Lousberg - www.kaylousberg.com).
##
## The character .glb has no animations: they come from the shared KayKit "Rig_Medium" animation
## files (every KayKit character uses the same skeleton). At _ready this script:
##   - creates an AnimationPlayer with exactly the 3 animations the game uses: idle, moving, attack
##   - attaches the weapons to the hands (handslot.r / handslot.l bones)
##
## Attack animations: the free Adventurers pack only has General + MovementBasic animations.
## Put the free "KayKit Character Animations" files (Rig_Medium_CombatMelee.glb,
## Rig_Medium_CombatRanged.glb) in Asset/Heroes/KayKit/Animations/ and the first name of
## [member attack_animations] that exists is used automatically; until then the fallback
## at the end of the list (e.g. "Throw") is used.

const ANIMATION_DIR := "res://Asset/Heroes/KayKit/Animations/"
const ANIMATION_FILES := [
	"Rig_Medium_General.glb",
	"Rig_Medium_MovementBasic.glb",
	# From the free KayKit Character Animations pack (CC0):
	"Rig_Medium_CombatMelee.glb",
	"Rig_Medium_CombatRanged.glb",
	"Rig_Medium_MovementAdvanced.glb",
]

@export var idle_animation := "Idle_A"
@export var move_animation := "Running_A"
## Tried in order, the first one found is used. "A+B" matches any animation whose name contains
## both A and B (case-insensitive). "A>B" plays A then B as one animation (e.g. draw then release
## a bow), so the attack lands when the whole sequence ends. "A~0.6" keeps only the first 0.6 s
## of A (e.g. the release of the bow without the slow lowering after it).
@export var attack_animations: PackedStringArray = ["Throw"]
## Optional separate animation for skills (Q/W/E casts); empty = skills use the attack animation
@export var cast_animations: PackedStringArray = []
## Optional looping animation for an ultimate that lasts (SkillData.caster_animation = "ultimate")
@export var ultimate_animations: PackedStringArray = []
@export var right_hand_item: PackedScene
@export var left_hand_item: PackedScene
## Extra rotation (degrees) of the item in each hand, if a model comes out facing the wrong way
@export var right_hand_item_rotation := Vector3.ZERO
@export var left_hand_item_rotation := Vector3.ZERO
## Seconds to blend between animations
@export var blend_time := 0.12
## Where ranged attacks / skill projectiles leave from: the item in this hand ("right" / "left";
## empty = the right-hand item, else the left one) ...
@export var muzzle_hand := ""
## ... at this point in the item's own space (e.g. the tip of a staff, the front of a crossbow)
@export var muzzle_offset := Vector3.ZERO

## "right" / "left" -> the weapon node attached to that hand
var _items := {}
var _skeleton: Skeleton3D

## name -> Animation, from every animation file found
static var _source: Dictionary = {}
static var _source_loaded := false
## "name|skeleton path|loop" -> retargeted Animation (shared by all heroes)
static var _retargeted: Dictionary = {}


## Animation files that exist in the project (CharacterDB preloads them with the heroes)
static func animation_paths() -> Array:
	var list: Array = []
	for f in ANIMATION_FILES:
		var p: String = ANIMATION_DIR + f
		if ResourceLoader.exists(p):
			list.append(p)
	return list


func _ready() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		push_error("HeroModel: missing 'Model' child")
		return
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("HeroModel: no Skeleton3D in %s" % model.name)
		return
	var skeleton := skeletons[0] as Skeleton3D
	_skeleton = skeleton
	_items["right"] = _attach(skeleton, "handslot.r", right_hand_item, right_hand_item_rotation)
	_items["left"] = _attach(skeleton, "handslot.l", left_hand_item, left_hand_item_rotation)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.playback_default_blend_time = blend_time
	model.add_child(player)  # root_node ".." = Model, so track paths are relative to Model
	var lib := AnimationLibrary.new()
	var skeleton_path := String(model.get_path_to(skeleton))
	_add_animation(lib, "idle", [idle_animation, "Idle_A"], skeleton_path, Animation.LOOP_LINEAR)
	_add_animation(lib, "moving", [move_animation, "Running_A"], skeleton_path, Animation.LOOP_LINEAR)
	_add_animation(lib, "attack", attack_animations, skeleton_path, Animation.LOOP_NONE)
	if not cast_animations.is_empty():
		_add_animation(lib, "cast", cast_animations, skeleton_path, Animation.LOOP_NONE)
	if not ultimate_animations.is_empty():
		_add_animation(lib, "ultimate", ultimate_animations, skeleton_path, Animation.LOOP_LINEAR)
	player.add_animation_library("", lib)
	player.animation_finished.connect(_on_animation_player_animation_finished)
	animation_player = player
	super._ready()


## Same as Character.play_animation, without touching the (shared) animation's loop setting
func play_animation(anim: String):
	if animation_player != null and animation_player.has_animation(anim):
		# The spin rotates bones (root / hips) that the other clips don't key: put the skeleton
		# back to its rest pose, otherwise the hero keeps looking the wrong way after it
		# No blend out of it either: blending would turn the body back over 180 degrees
		if animation_player.current_animation == "ultimate" and anim != "ultimate":
			if _skeleton != null:
				_skeleton.reset_bone_poses()
			animation_player.play(anim, 0.0, _speed_for(anim))
			return
		animation_player.play(anim, -1, _speed_for(anim))


## Attack speed also applies to the skill cast animation
func _speed_for(anim: String) -> float:
	return attack_speed_scale if anim == "attack" or anim == "cast" else 1.0


## World position where a projectile of this hero starts: the weapon, as it is posed right now
## (the attack animation plays on every peer, so it is the raised weapon at the moment of the shot).
## Vector3.INF when the hero holds no weapon.
func muzzle_point() -> Vector3:
	var hand := muzzle_hand
	if hand.is_empty():
		hand = "right" if _items.get("right") != null else "left"
	var item := _items.get(hand) as Node3D
	if item == null or not item.is_inside_tree():
		return Vector3.INF
	return item.to_global(muzzle_offset)


func _attach(skeleton: Skeleton3D, bone: String, item_scene: PackedScene, rotation_deg := Vector3.ZERO) -> Node3D:
	if item_scene == null or skeleton.find_bone(bone) < 0:
		return null
	var slot := BoneAttachment3D.new()
	slot.name = bone.replace(".", "_")
	slot.bone_name = bone
	skeleton.add_child(slot)
	var item := item_scene.instantiate()
	slot.add_child(item)
	if item is Node3D:
		(item as Node3D).rotation_degrees = rotation_deg
		return item
	return null


func _add_animation(lib: AnimationLibrary, as_name: String, candidates: Array, skeleton_path: String, loop: int) -> void:
	_load_sources()
	var source_name := _find(candidates)
	if source_name.is_empty():
		push_warning("HeroModel %s: none of %s found for '%s'" % [name, str(candidates), as_name])
		return
	var key := "%s|%s|%d" % [source_name, skeleton_path, loop]
	if not _retargeted.has(key):
		_retargeted[key] = _retarget(_source[source_name], skeleton_path, loop)
	lib.add_animation(as_name, _retargeted[key])


static func _find(candidates: Array) -> String:
	for c in candidates:
		var wanted := str(c)
		if wanted.is_empty():
			continue
		if ">" in wanted:
			if _build_sequence(wanted):
				return wanted
		elif "+" in wanted:
			var parts := wanted.to_lower().split("+")
			for n: String in _source:
				var lower := n.to_lower()
				var ok := true
				for p in parts:
					if not lower.contains(p):
						ok = false
						break
				if ok:
					return n
		elif _source.has(wanted):
			return wanted
	return ""


## "A>B>C": the clips one after the other in a single Animation, stored in _source under that name
static func _build_sequence(key: String) -> bool:
	if _source.has(key):
		return true
	var parts := key.split(">")
	for part in parts:
		if not _source.has(part.get_slice("~", 0)):
			return false
	var seq := Animation.new()
	var offset := 0.0
	for part in parts:
		var src: Animation = _source[part.get_slice("~", 0)]
		# "Name~0.6": only the first 0.6 s of the clip
		var length := src.length
		if "~" in part:
			length = minf(part.get_slice("~", 1).to_float(), src.length)
		for t in src.get_track_count():
			var path := src.track_get_path(t)
			var type := src.track_get_type(t)
			var dst := seq.find_track(path, type)
			if dst < 0:
				dst = seq.add_track(type)
				seq.track_set_path(dst, path)
				seq.track_set_interpolation_type(dst, src.track_get_interpolation_type(t))
			for k in src.track_get_key_count(t):
				var key_time := src.track_get_key_time(t, k)
				if key_time > length + 0.001:
					break
				seq.track_insert_key(dst, offset + key_time, src.track_get_key_value(t, k))
		offset += length
	seq.length = offset
	_source[key] = seq
	return true


## Bone tracks point at the skeleton of the animation file: point them at ours instead
static func _retarget(src: Animation, skeleton_path: String, loop: int) -> Animation:
	var anim := src.duplicate(true) as Animation
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(i)
		if path.get_subname_count() == 0:
			anim.remove_track(i)  # not a bone track (nothing else is used)
			continue
		anim.track_set_path(i, NodePath(skeleton_path + ":" + path.get_concatenated_subnames()))
	anim.loop_mode = loop
	return anim


static func _load_sources() -> void:
	if _source_loaded:
		return
	_source_loaded = true
	for path in animation_paths():
		var scene := AssetPreloader.get_scene(path)
		if scene == null:
			continue
		var root := scene.instantiate()
		for p in root.find_children("*", "AnimationPlayer", true, false):
			var ap := p as AnimationPlayer
			for lib_name in ap.get_animation_library_list():
				var lib := ap.get_animation_library(lib_name)
				for anim_name in lib.get_animation_list():
					if not _source.has(String(anim_name)):
						_source[String(anim_name)] = lib.get_animation(anim_name)
		root.free()
