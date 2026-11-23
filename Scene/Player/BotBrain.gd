class_name BotBrain
extends Node
## AI of a bot hero (a Player with a negative peer id). Lives only on the server, as a child of
## the Player, and gives it the same orders a human would (Player.order_move / order_attack,
## SkillCaster.server_cast), so everything else (sync, damage, cooldowns...) works the same.
##
## A few times per second it decides:
##   low on hp      -> walk back to its spawn until it has healed a bit (Normal / Hard)
##   enemy in sight -> use a skill that fits now, then keep basic-attacking it
##   nobody around  -> pick up the rune if one is close, else stand in the King of the Hill zone

## Per difficulty (MatchSettings.bot_difficulty): Easy, Normal, Hard
const DIFFICULTY := [
	{"think": 0.6, "skill_chance": 0.3, "aggro": 14.0, "retreat_hp": 0.0, "dash": false},
	{"think": 0.35, "skill_chance": 0.65, "aggro": 20.0, "retreat_hp": 0.25, "dash": false},
	{"think": 0.2, "skill_chance": 0.95, "aggro": 22.0, "retreat_hp": 0.35, "dash": true},
]
## Back in the fight once hp is above this share
const RETREAT_UNTIL := 0.7
## Seconds before picking another spot in the zone
const ZONE_REPICK := 4.0
const ULTIMATE_SLOT := 3
const DASH_SLOT := 4

var player: Player
var _cfg: Dictionary
var _think_left := 0.0
var _retreating := false
var _target: Player = null
var _zone_spot := Vector3.INF
var _zone_spot_left := 0.0


func _ready() -> void:
	player = get_parent() as Player
	_cfg = DIFFICULTY[clampi(MatchSettings.bot_difficulty, 0, DIFFICULTY.size() - 1)]
	# Bots don't all think on the same frame
	_think_left = randf() * float(_cfg["think"])


func _physics_process(delta: float) -> void:
	if player == null or not multiplayer.is_server():
		return
	_zone_spot_left -= delta
	_think_left -= delta
	if _think_left > 0.0:
		return
	_think_left = float(_cfg["think"])
	_think()


func _think() -> void:
	if not player.hero_spawner.is_game_started() or MatchManager.is_over or player.is_dead():
		_target = null
		_retreating = false
		return
	var hp_ratio := float(player.current_hp) / maxf(float(player.max_hp()), 1.0)
	var retreat_hp: float = _cfg["retreat_hp"]
	if retreat_hp > 0.0 and hp_ratio < retreat_hp:
		_retreating = true
	elif hp_ratio >= RETREAT_UNTIL:
		_retreating = false

	if _retreating:
		_target = null
		var chaser := _find_target(8.0)
		if chaser != null and _cfg["dash"]:
			_try_dash_toward(player.spawn_position)
		_go_to(player.spawn_position)
		return

	var target := _find_target(float(_cfg["aggro"]))
	if target != null:
		_fight(target)
		return
	_target = null
	_wander()


# ------------------------------------------------------------------ fighting

## Closest living enemy this bot's team can see, within [param radius]. Keeps the current
## target while it stays a little farther than that (no flipping between two enemies).
func _find_target(radius: float) -> Player:
	var heroes: Array = player.hero_spawner.player_list.values()
	if _is_valid_target(_target, heroes) and _dist(_target.global_position) <= radius * 1.2:
		return _target
	var best: Player = null
	var best_dist := radius
	for other in heroes:
		if not _is_valid_target(other, heroes):
			continue
		var d := _dist(other.global_position)
		if d <= best_dist:
			best = other
			best_dist = d
	return best


func _is_valid_target(other, heroes: Array) -> bool:
	return other != null and is_instance_valid(other) and other is Player and player.is_enemy(other) \
			and not other.is_dead() and not Vision.is_hidden(other, player.team_side, heroes)


func _fight(target: Player) -> void:
	_target = target
	var dist := _dist(target.global_position)
	if randf() < float(_cfg["skill_chance"]):
		_try_skill(target, dist)
	# Far away and Hard: dash closer
	if _cfg["dash"] and dist > player.character_data.attack_range + 6.0:
		_try_dash_toward(target.global_position)
	var busy: bool = player.player_state == Player.PlayerState.CASTING or player.player_state == Player.PlayerState.DASHING
	if player.target_attack != target or (player.player_state != Player.PlayerState.ATTACK and not busy):
		player.order_attack(target)


func _try_skill(target: Player, dist: float) -> void:
	var caster := player.skill_caster
	if caster == null:
		return
	# Ultimate first when it is ready, then the others in a random order
	var slots: Array[int] = [0, 1, 2]
	slots.shuffle()
	slots.push_front(ULTIMATE_SLOT)
	for slot in slots:
		if slot >= caster.skills.size() or not caster.is_unlocked(slot) or caster.server_cooldown_left(slot) > 0.0:
			continue
		var skill: SkillData = caster.skills[slot]
		if not _skill_fits(skill, target, dist):
			continue
		if caster.server_cast(slot, target.peer_id, target.global_position):
			return


## Whether using [param skill] on [param target] (at [param dist]) makes sense right now
func _skill_fits(skill: SkillData, target: Player, dist: float) -> bool:
	if skill.is_targeted():
		return dist <= skill.cast_range
	match skill.kind:
		SkillData.Kind.SELF_BUFF:
			var hp_ratio := float(player.current_hp) / maxf(float(player.max_hp()), 1.0)
			match skill.buff:
				SkillData.Buff.SHIELD:
					return hp_ratio < 0.85 and dist <= 10.0
				SkillData.Buff.HASTE:
					return dist > player.character_data.attack_range + 3.0
				SkillData.Buff.CC_IMMUNE:
					return target.status != null and dist <= 10.0
				_:
					return dist <= player.character_data.attack_range + 4.0
		SkillData.Kind.AREA_AT_POINT:
			return dist <= skill.cast_range + skill.radius * 0.5
		SkillData.Kind.LINE_SHOT:
			return dist <= skill.cast_range * 0.9
		SkillData.Kind.AREA_AROUND_CASTER:
			return dist <= skill.radius * 0.8
		SkillData.Kind.AREA_IN_FRONT:
			return dist <= skill.forward_distance + skill.radius * 0.7
		SkillData.Kind.DASH:
			return false  # the Dash is used on its own (chasing / running away)
	return false


func _try_dash_toward(point: Vector3) -> void:
	var caster := player.skill_caster
	if caster == null or DASH_SLOT >= caster.skills.size() or caster.server_cooldown_left(DASH_SLOT) > 0.0:
		return
	var skill: SkillData = caster.skills[DASH_SLOT]
	if skill.kind != SkillData.Kind.DASH or skill.needs_target:
		return
	var dir := Vector3(point.x - player.global_position.x, 0.0, point.z - player.global_position.z)
	if dir.length() < 3.0:
		return
	caster.server_cast(DASH_SLOT, -1, player.global_position + dir.normalized() * skill.cast_range)


# ------------------------------------------------------------------ moving around

func _wander() -> void:
	# A rune close by: grab it
	var mm := player.get_tree().current_scene.get_node_or_null("MatchManager") as MatchManager
	if mm != null and mm.rune_kind >= 0 and _dist(mm.rune_position) < 30.0:
		_go_to(mm.rune_position)
		return
	# Else stand somewhere in the King of the Hill zone
	if _zone_spot == Vector3.INF or _zone_spot_left <= 0.0:
		_zone_spot_left = ZONE_REPICK + randf() * 2.0
		var a := randf() * TAU
		var r := sqrt(randf()) * GameDefines.ZONE_RADIUS * 0.7
		_zone_spot = GameDefines.ZONE_CENTER + Vector3(cos(a) * r, 0.0, sin(a) * r)
	_go_to(_zone_spot)


## Walk to [param point] (along the navigation path), without re-sending the same order
func _go_to(point: Vector3) -> void:
	if _dist(point) < 1.5:
		return
	if player.player_state == Player.PlayerState.MOVING and Vector2(player.target_position.x - point.x, player.target_position.z - point.z).length() < 1.5:
		return
	player.order_move(point)


func _dist(point: Vector3) -> float:
	return Vector2(point.x - player.global_position.x, point.z - player.global_position.z).length()
