class_name Obstacles
extends RefCounted
## Props of the arena (walls, barrels...) are on their own physics layer so shots can test
## against them only: a projectile stops at the first prop between the shooter and the target.

## Physics layer 3 (bit value 4). Props use layers 1 + 3: heroes still bump into them (layer 1).
const LAYER := 4


## Point where the line [param from] -> [param to] first hits a prop, or Vector3.INF if clear.
static func first_hit(world: World3D, from: Vector3, to: Vector3) -> Vector3:
	if world == null:
		return Vector3.INF
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"]


static func is_blocked(world: World3D, from: Vector3, to: Vector3) -> bool:
	return first_hit(world, from, to) != Vector3.INF
