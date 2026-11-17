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
	
## Every heavy scene a match with these heroes needs: their models, the VFX/models of their
## skills and basic-attack projectile, and the status VFX (stun, slow, shield, auras...).
func paths_for_heroes(hero_ids: Array) -> Array:
	var paths: Array = []
	for id in hero_ids:
		var c := get_character(int(id))
		if c == null:
			continue
		_add_path(paths, c.character_scene)
		for skill in SkillDB.get_skills(c.id):
			_add_path(paths, skill.vfx_scene)
			_add_path(paths, skill.projectile_model)
		var basic: Dictionary = BasicAttackFx.PROJECTILES.get(c.id, {})
		_add_path(paths, str(basic.get("model", "")))
	for p in AssetPreloader.scene_paths_in([StatusEffects]):
		_add_path(paths, p)
	for p in HeroModel.animation_paths():  # shared KayKit animations
		_add_path(paths, p)
	return paths

func _add_path(paths: Array, path: String) -> void:
	if not path.is_empty() and not paths.has(path):
		paths.append(path)
	
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
