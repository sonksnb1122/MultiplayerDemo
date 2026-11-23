class_name Sfx
extends RefCounted
## Sound effects ("400 Sounds Pack" by Chequered Ink, see Asset/Audio/Effects/LICENSE.txt).
## play_3d: positional, heard from the camera; play_ui: flat (kill / end jingles, buttons).

const SOUNDS := {
	"hit": preload("res://Asset/Audio/Effects/punch_2.wav"),
	"impact": preload("res://Asset/Audio/Effects/harsh_thud.wav"),
	"shoot": preload("res://Asset/Audio/Effects/elastic_twang.wav"),       # bow / crossbow
	"shoot_magic": preload("res://Asset/Audio/Effects/whoosh_1.wav"),      # Mage orb
	"cast": preload("res://Asset/Audio/Effects/whoosh_2.wav"),
	"dash": preload("res://Asset/Audio/Effects/air_burst.wav"),
	"kill": preload("res://Asset/Audio/Effects/brass_chime_positive.wav"),
	"death": preload("res://Asset/Audio/Effects/brass_negative_quick.wav"),
	"click": preload("res://Asset/Audio/Effects/select_1.wav"),
	"victory": preload("res://Asset/Audio/Effects/brass_level_complete.wav"),
	"defeat": preload("res://Asset/Audio/Effects/brass_defeated.wav"),
	# Melee basic attacks (several files = one picked at random)
	"sword": [preload("res://Asset/Audio/Effects/sword_light.wav"), preload("res://Asset/Audio/Effects/sword_slice.wav")],
	"axe": preload("res://Asset/Audio/Effects/crunch_quick.wav"),
	# Skills
	"axe_heavy": preload("res://Asset/Audio/Effects/crunch.wav"),
	# Knight's buffs: charging up
	"charge_rage": preload("res://Asset/Audio/Effects/power_up.wav"),
	"charge_guard": preload("res://Asset/Audio/Effects/power_up_2.wav"),
	"charge_speed": preload("res://Asset/Audio/Effects/grow_big.wav"),
	# Levels / runes
	"level_up": preload("res://Asset/Audio/Effects/brass_chime_positive.wav"),
	"rune": preload("res://Asset/Audio/Effects/power_up_2.wav"),
	"shield_up": preload("res://Asset/Audio/Effects/weapon_equip.wav"),
	"swipe": preload("res://Asset/Audio/Effects/swipe.wav"),
	"blast": preload("res://Asset/Audio/Effects/explosion_small.wav"),
	# Ultimates
	"metal_clang": preload("res://Asset/Audio/Effects/metal_clang.wav"),
	"fire": preload("res://Asset/Audio/Effects/fire_lighting.wav"),
	"arrow_wave": preload("res://Asset/Audio/Effects/shot_muffled.wav"),
	"wind": preload("res://Asset/Audio/Effects/ambient_wind_short.wav"),
	"bolt": preload("res://Asset/Audio/Effects/explosion_quick.wav"),
}
const STEPS := [
	preload("res://Asset/Audio/Effects/digital_footstep_grass_1.wav"),
	preload("res://Asset/Audio/Effects/digital_footstep_grass_2.wav"),
	preload("res://Asset/Audio/Effects/digital_footstep_grass_3.wav"),
	preload("res://Asset/Audio/Effects/digital_footstep_grass_4.wav"),
]


## Sound at [param world_position] (the listener is the camera, ~30 units above the ground)
static func play_3d(tree: SceneTree, sound: String, world_position: Vector3, volume_db := 0.0, pitch_random := 0.08) -> void:
	if not SOUNDS.has(sound):
		return
	_play_stream_3d(tree, _pick(SOUNDS[sound]), world_position, volume_db, pitch_random)


static func _pick(entry) -> AudioStream:
	if entry is Array:
		return entry[randi() % entry.size()]
	return entry


## One footstep (random of 4) at [param world_position]
static func play_step(tree: SceneTree, world_position: Vector3, volume_db := -14.0) -> void:
	_play_stream_3d(tree, STEPS[randi() % STEPS.size()], world_position, volume_db, 0.12)


static func play_ui(tree: SceneTree, sound: String, volume_db := 0.0) -> void:
	if tree == null or tree.root == null or not SOUNDS.has(sound):
		return
	var p := AudioStreamPlayer.new()
	p.bus = GraphicsSettings.SFX_BUS
	p.stream = _pick(SOUNDS[sound])
	p.volume_db = volume_db
	tree.root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## 3D players are reused (a pool in the current scene) instead of one new node per sound:
## footsteps and hits play many sounds a second. When all are busy the oldest one is cut.
const POOL_3D_MAX := 24
static var _pool_3d: Array = []


static func _play_stream_3d(tree: SceneTree, stream: AudioStream, world_position: Vector3, volume_db: float, pitch_random: float) -> void:
	if tree == null or tree.current_scene == null:
		return
	var p := _free_player_3d(tree.current_scene)
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_random, pitch_random)
	p.global_position = world_position
	p.play()


static func _free_player_3d(scene: Node) -> AudioStreamPlayer3D:
	for i in range(_pool_3d.size() - 1, -1, -1):
		var player = _pool_3d[i]
		# Players of a previous scene were freed with it
		if not is_instance_valid(player) or player.get_parent() != scene:
			_pool_3d.remove_at(i)
			continue
		if not player.playing:
			return player
	if _pool_3d.size() < POOL_3D_MAX:
		var p := AudioStreamPlayer3D.new()
		p.bus = GraphicsSettings.SFX_BUS
		p.unit_size = 30.0
		p.max_distance = 90.0
		scene.add_child(p)
		_pool_3d.append(p)
		return p
	var oldest: AudioStreamPlayer3D = _pool_3d.pop_front()
	_pool_3d.append(oldest)
	oldest.stop()
	return oldest
