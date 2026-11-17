extends Node

@export var characters: Array[CharacterData] = []

func get_character(id: int) -> CharacterData:
	for c in characters:
		if c.id == id:
			return c
	return null

func get_all_character() -> Array[CharacterData]:
	return characters
	
func _ready() -> void:
	load_all_characters()
	preload_heavy_scenes()

## Starts loading the hero models and every skill VFX on background threads right at launch,
## so they are ready long before hero select / the match need them.
func preload_heavy_scenes() -> void:
	var paths: Array = []
	for c in characters:
		if c != null and not c.character_scene.is_empty():
			paths.append(c.character_scene)
	paths.append_array(AssetPreloader.scene_paths_in([SkillDB, StatusEffects]))
	AssetPreloader.start(paths)
	
func load_all_characters():
	var resources_path = "res://Resources/Character/"
	var dir := DirAccess.open(resources_path)
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			var file_name = file
			if not file.ends_with(".tres"):
				file_name = file.get_basename()

			var path = resources_path + file_name
			var data = load(path)
			CharacterDB.characters.append(data)
			file = dir.get_next()
