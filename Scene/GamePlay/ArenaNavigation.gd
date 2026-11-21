class_name ArenaNavigation
extends NavigationRegion3D
## Navigation mesh of the arena: the walkable ground minus the props (KayKit Dungeon).
## Baked at runtime from the collision shapes of every node in the "navigation_geometry" group
## (the ground "Area" and the "Props" node), so moving / adding props needs no manual re-bake.
## Only the host moves heroes, so only the host bakes it.

signal navigation_ready

var is_baked := false


func _ready() -> void:
	if not multiplayer.is_server():
		return
	bake_finished.connect(_on_bake_finished)
	# Deferred: the ground (a sibling in GamePlay) must be in the tree before it is parsed
	bake_navigation_mesh.call_deferred(true)


func _on_bake_finished() -> void:
	is_baked = true
	print("Arena navigation mesh baked: %d polygons" % navigation_mesh.get_polygon_count())
	navigation_ready.emit()
