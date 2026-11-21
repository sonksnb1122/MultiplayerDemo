class_name Vision
extends RefCounted
## Fog of war for heroes only (props and the map are always visible):
## an enemy is seen when it is within RADIUS of a living hero of your team (team vision), and,
## if it stands in a bush, when one of you is in the same bush or closer than Bush.REVEAL_DISTANCE.
## Every peer uses it to hide enemies; the host uses it to drop attack orders / skill targets.

## How far a hero sees (world units). Attack and skill ranges are all shorter than this.
const RADIUS := 20.0


## True when [param hero] can't be seen by the team [param viewer_team].
## [param heroes]: every hero of the match (HeroSpawner.player_list.values()).
static func is_hidden(hero, viewer_team: int, heroes: Array) -> bool:
	if hero == null or not is_instance_valid(hero) or not hero.is_inside_tree() or hero.team_side == viewer_team:
		return false
	var bush := Bush.bush_at(hero.get_tree(), hero.global_position)
	for other in heroes:
		if not is_instance_valid(other) or other.team_side != viewer_team or other.is_dead():
			continue
		var d := Vector2(other.global_position.x - hero.global_position.x, other.global_position.z - hero.global_position.z).length()
		if d > RADIUS:
			continue
		if bush == null or bush.contains(other.global_position) or d <= Bush.REVEAL_DISTANCE:
			return false
	return true
