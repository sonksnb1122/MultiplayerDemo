class_name AssetPreloader
extends RefCounted
## Loads the heavy scenes (hero models, skill VFX) on background threads so the game never
## freezes on a load() in the middle of hero select or a match.
##
## CharacterDB calls start() once when the game launches. Later, get_scene() returns the
## already loaded scene; if it is still loading it waits only for that one file.
## Godot 4.4+ also compiles the GPU pipelines of meshes/materials as they load, which removes
## most of the "first time this VFX appears" hitch.
## Note: don't "warm up" VFX by spawning hidden copies: the Binbun VFX animate shared materials
## (alpha) and carry OmniLights, so a copy freed mid-animation makes later ones invisible.

## path -> PackedScene. Strong references keep the scenes in memory for the whole session.
static var _cache: Dictionary = {}
## paths requested with load_threaded_request and not collected yet
static var _pending: Dictionary = {}


## Starts loading every path in the background (paths already loaded or pending are skipped).
static func start(paths: Array) -> void:
	for path in paths:
		var p := str(path)
		if p.is_empty() or _cache.has(p) or _pending.has(p):
			continue
		if not ResourceLoader.exists(p):
			push_warning("AssetPreloader: missing resource %s" % p)
			continue
		var err := ResourceLoader.load_threaded_request(p, "", true)
		if err == OK:
			_pending[p] = true
		else:
			push_warning("AssetPreloader: can't start loading %s (error %d)" % [p, err])


## Returns the scene at [param path], loading it now only if the background load never started.
static func get_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	var res: Resource = null
	if _pending.has(path):
		_pending.erase(path)
		# Returns at once when done, otherwise waits for this file only
		res = ResourceLoader.load_threaded_get(path)
	if res == null:
		res = load(path)
	var scene := res as PackedScene
	if scene == null:
		push_error("AssetPreloader: %s is not a scene" % path)
	_cache[path] = scene
	return scene


## True when every background load has finished (for a loading bar, if one is ever wanted).
static func is_done() -> bool:
	for p in _pending.keys():
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
	return true


## Every "res://….tscn/.fbx" path declared as a constant in the given scripts.
static func scene_paths_in(scripts: Array) -> Array:
	var paths: Array = []
	for script in scripts:
		if script == null:
			continue
		for value in (script as Script).get_script_constant_map().values():
			if value is String and value.begins_with("res://"):
				var ext: String = value.get_extension().to_lower()
				if ext in ["tscn", "scn", "fbx", "glb", "gltf"]:
					paths.append(value)
	return paths

