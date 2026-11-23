class_name MatchManager
extends Node
## Rules of a match (server-authoritative):
##   - killing an enemy gives the team GameDefines.KILL_SCORE points (+ kill / death / assist stats)
##   - a team standing alone in the zone in the middle (King of the Hill) gets 1 point every
##     GameDefines.ZONE_TICK seconds; when both teams are inside it is contested
##   - first team to GameDefines.SCORE_TO_WIN wins, otherwise the higher score when the time is up
##   - the respawn time grows with each death
##   - heroes gain XP (time, kills, assists) and level up (Player.add_xp)
##   - a rune (Haste / Power / Shield / Heal) appears at one of GameDefines.RUNE_SPOTS now and then
## The host sends scores / stats / events to every peer; MatchHUD draws them.

signal scores_changed(left: int, right: int)
signal stats_changed(stats: Dictionary)
signal zone_changed(state: int)
signal hero_killed(victim_peer: int, killer_peer: int, assist_peers: Array, respawn_time: float)
signal match_ended(winner_team: int)

enum ZoneState { NEUTRAL = -1, LEFT = 0, RIGHT = 1, CONTESTED = 2 }
enum Rune { HASTE, POWER, SHIELD, HEAL }
const RUNE_NAMES := ["Haste", "Power", "Shield", "Heal"]
const RUNE_COLORS := [Color(0.3, 0.9, 1.0), Color(1.0, 0.35, 0.2), Color(0.7, 0.6, 1.0), Color(0.3, 1.0, 0.4)]

## No orders / casts once the match is over (read by Player and SkillCaster)
static var is_over := false

## Kills and damage older than this (ms) don't count for assists
const ASSIST_WINDOW_MS := 10000

@onready var game_play: GamePlay = get_parent()
@onready var hero_spawner: HeroSpawner = $"../HeroSpawner"
@onready var game_play_network: GamePlayNetwork = $"../GamePlayNetwork"

var scores := [0, 0]
## peer_id -> {name, hero, team, kills, deaths, assists, damage}
var stats := {}
var zone_state: int = ZoneState.NEUTRAL
var winner_team := -1

var _running := false
## Every peer: the match has started (heroes spawned)
var _started := false
var _hud: MatchHUD
## Every peer: the rune on the ground (-1 = none), its kind and where it is
var rune_kind := -1
var rune_position := Vector3.ZERO
var _rune_node: Node3D
var _elapsed := 0.0  # server
var _next_rune_time := 0.0  # server
var _zone_timer := 0.0
var _zone_visual: Node3D
var _zone_material: StandardMaterial3D
var _ring_material: StandardMaterial3D


func _ready() -> void:
	is_over = false
	game_play_network.start_game.connect(_on_start_game)
	game_play_network.play_time_trigged.connect(_on_play_time)
	_build_zone_visual()
	_hud = MatchHUD.new()
	_hud.name = "MatchHUD"
	add_child(_hud)
	_hud.setup(self)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	# New match ("Play again"): someone who left the previous one would never load it
	_check_missing_players.call_deferred()


func _exit_tree() -> void:
	is_over = false


# ------------------------------------------------------------------ server

func _on_start_game() -> void:
	_started = true
	_init_stats()
	if not multiplayer.is_server(): return
	_running = true
	_elapsed = 0.0
	_next_rune_time = GameDefines.RUNE_FIRST_TIME


func _init_stats() -> void:
	stats.clear()
	for peer_id in game_play_network.hero_selection_status:
		var info: Dictionary = game_play_network.hero_selection_status[peer_id]
		stats[peer_id] = {
			"name": str(info.get(GameDefines.NAME, "P")),
			"hero": int(info.get(GameDefines.HERO_ID, 0)),
			"team": int(info.get(GameDefines.TEAM_SIDE, 0)),
			"kills": 0, "deaths": 0, "assists": 0, "damage": 0,
		}
	stats_changed.emit(stats)


func _on_play_time(time: int) -> void:
	if not multiplayer.is_server() or not _running: return
	sync_stats.rpc(stats)
	# Everyone levels up a little just by playing
	for hero in hero_spawner.player_list.values():
		if is_instance_valid(hero):
			hero.add_xp(GameDefines.XP_PER_SECOND)
	if time >= GameDefines.MATCH_DURATION:
		_end_match()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not _running: return
	_elapsed += delta
	_update_rune()
	var count := [0, 0]
	for p in hero_spawner.player_list.values():
		if not is_instance_valid(p) or not p.is_inside_tree() or p.is_dead(): continue
		var d := Vector2(p.global_position.x - GameDefines.ZONE_CENTER.x, p.global_position.z - GameDefines.ZONE_CENTER.z)
		if d.length() <= GameDefines.ZONE_RADIUS:
			count[p.team_side] += 1
	var state := ZoneState.NEUTRAL
	if count[0] > 0 and count[1] > 0: state = ZoneState.CONTESTED
	elif count[0] > 0: state = ZoneState.LEFT
	elif count[1] > 0: state = ZoneState.RIGHT
	if state != zone_state:
		_zone_timer = 0.0
		set_zone_state.rpc(state)
	if state == ZoneState.LEFT or state == ZoneState.RIGHT:
		_zone_timer += delta
		if _zone_timer >= GameDefines.ZONE_TICK:
			_zone_timer -= GameDefines.ZONE_TICK
			_add_score(state, 1)


## Server: a hero took [param amount] damage from [param attacker_peer]
func on_damage(attacker_peer: int, amount: int) -> void:
	if not _running or not stats.has(attacker_peer): return
	stats[attacker_peer]["damage"] += amount


## Server: [param victim] just died. [param attacker_peer] dealt the last hit (0 = unknown).
func on_hero_killed(victim: Player, attacker_peer: int) -> void:
	if not _running or not stats.has(victim.peer_id): return
	var now := Time.get_ticks_msec()
	var recent: Array = []
	for peer in victim.damage_log:
		if now - int(victim.damage_log[peer]) <= ASSIST_WINDOW_MS and stats.has(peer) and stats[peer]["team"] != stats[victim.peer_id]["team"]:
			recent.append(peer)
	# Killed by poison with no known source: the last enemy who hit
	if not stats.has(attacker_peer) or stats[attacker_peer]["team"] == stats[victim.peer_id]["team"]:
		attacker_peer = 0
		var best := -1
		for peer in recent:
			if int(victim.damage_log[peer]) > best:
				best = int(victim.damage_log[peer])
				attacker_peer = peer
	var assists: Array = []
	for peer in recent:
		if peer != attacker_peer:
			assists.append(peer)
			stats[peer]["assists"] += 1
	stats[victim.peer_id]["deaths"] += 1
	if attacker_peer != 0:
		stats[attacker_peer]["kills"] += 1
		_add_score(stats[attacker_peer]["team"], GameDefines.KILL_SCORE)
		_give_xp(attacker_peer, GameDefines.KILL_XP)
	for peer in assists:
		_give_xp(peer, GameDefines.ASSIST_XP)
	victim.damage_log.clear()
	var respawn := respawn_time_for(victim.peer_id)
	announce_kill.rpc(victim.peer_id, attacker_peer, assists, respawn)
	sync_stats.rpc(stats)


func _give_xp(peer_id: int, amount: int) -> void:
	var hero = hero_spawner.get_player(peer_id)
	if hero != null:
		hero.add_xp(amount)


# ------------------------------------------------------------------ runes

## Server: spawn a rune when it is time, give it to the first living hero who reaches it
func _update_rune() -> void:
	if rune_kind < 0:
		if _elapsed >= _next_rune_time:
			var spot: Vector3 = GameDefines.RUNE_SPOTS[randi() % GameDefines.RUNE_SPOTS.size()]
			spawn_rune.rpc(randi() % RUNE_NAMES.size(), spot)
		return
	for hero in hero_spawner.player_list.values():
		if not is_instance_valid(hero) or not hero.is_inside_tree() or hero.is_dead():
			continue
		var d := Vector2(hero.global_position.x - rune_position.x, hero.global_position.z - rune_position.z)
		if d.length() <= GameDefines.RUNE_PICK_RADIUS:
			_apply_rune(hero, rune_kind)
			pick_rune.rpc(hero.peer_id)
			_next_rune_time = _elapsed + GameDefines.RUNE_INTERVAL
			return


func _apply_rune(hero, kind: int) -> void:
	match kind:
		Rune.HASTE:
			hero.status.apply_haste(1.5, 8.0)
		Rune.POWER:
			hero.status.add_empowered_attacks(5, 15)
		Rune.SHIELD:
			hero.status.add_shield(80, 10.0)
		Rune.HEAL:
			hero.heal(ceili(hero.max_hp() * 0.4))


@rpc("authority", "call_local", "reliable")
func spawn_rune(kind: int, position_on_ground: Vector3) -> void:
	_clear_rune_node()
	rune_kind = kind
	rune_position = position_on_ground
	_rune_node = _build_rune_node(kind)
	add_child(_rune_node)
	_rune_node.global_position = position_on_ground
	_hud.add_feed_message("A %s rune appeared!" % RUNE_NAMES[kind])
	Sfx.play_ui(get_tree(), "rune", -6.0)


@rpc("authority", "call_local", "reliable")
func pick_rune(peer_id: int) -> void:
	if rune_kind < 0:
		return
	var kind := rune_kind
	rune_kind = -1
	Sfx.play_3d(get_tree(), "rune", rune_position + Vector3(0, 1, 0))
	_clear_rune_node()
	_hud.add_feed_message("%s took the %s rune" % [_player_name(peer_id), RUNE_NAMES[kind]])


func _clear_rune_node() -> void:
	if is_instance_valid(_rune_node):
		_rune_node.queue_free()
	_rune_node = null


## A glowing gem that floats and spins, with a ring on the ground
func _build_rune_node(kind: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Rune"
	var color: Color = RUNE_COLORS[kind]
	var gem := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.4
	mesh.radial_segments = 6
	mesh.rings = 2
	gem.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	gem.material_override = mat
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gem.position.y = 1.4
	root.add_child(gem)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.4
	torus.outer_radius = 1.6
	torus.rings = 32
	torus.ring_segments = 4
	ring.mesh = torus
	ring.scale = Vector3(1, 0.1, 1)
	ring.position.y = 0.1
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = color
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var spin := gem.create_tween().set_loops()
	spin.tween_property(gem, "rotation:y", TAU, 2.0).from(0.0)
	var bob := gem.create_tween().set_loops()
	bob.tween_property(gem, "position:y", 1.8, 0.8).set_trans(Tween.TRANS_SINE)
	bob.tween_property(gem, "position:y", 1.4, 0.8).set_trans(Tween.TRANS_SINE)
	return root


## Seconds before [param peer_id] respawns (grows with its deaths)
func respawn_time_for(peer_id: int) -> float:
	var deaths := 1
	if stats.has(peer_id):
		deaths = maxi(int(stats[peer_id]["deaths"]), 1)
	return minf(GameDefines.RESPAWN_BASE + GameDefines.RESPAWN_PER_DEATH * (deaths - 1), GameDefines.RESPAWN_MAX)


func _add_score(team: int, points: int) -> void:
	if team < 0 or team > 1 or not _running: return
	scores[team] += points
	sync_scores.rpc(scores[0], scores[1])
	if scores[team] >= GameDefines.SCORE_TO_WIN:
		_end_match()


func _end_match() -> void:
	if not _running: return
	_running = false
	game_play_network.game_play_timer.stop()
	var winner := -1
	if scores[0] > scores[1]: winner = 0
	elif scores[1] > scores[0]: winner = 1
	sync_stats.rpc(stats)
	finish_match.rpc(winner)


## Host: same heroes, same teams, new match
func request_restart() -> void:
	if not multiplayer.is_server(): return
	restart_match.rpc(game_play_network.hero_selection_status)


# ------------------------------------------------------------------ RPCs (every peer)

@rpc("authority", "call_local", "reliable")
func sync_scores(left: int, right: int) -> void:
	scores = [left, right]
	scores_changed.emit(left, right)


@rpc("authority", "call_local", "reliable")
func sync_stats(new_stats: Dictionary) -> void:
	stats = new_stats
	stats_changed.emit(stats)


@rpc("authority", "call_local", "reliable")
func set_zone_state(state: int) -> void:
	zone_state = state
	_update_zone_visual()
	zone_changed.emit(state)


@rpc("authority", "call_local", "reliable")
func announce_kill(victim_peer: int, killer_peer: int, assist_peers: Array, respawn_time: float) -> void:
	hero_killed.emit(victim_peer, killer_peer, assist_peers, respawn_time)


@rpc("authority", "call_local", "reliable")
func finish_match(winner: int) -> void:
	is_over = true
	winner_team = winner
	match_ended.emit(winner)


@rpc("authority", "call_local", "reliable")
func restart_match(selection: Dictionary) -> void:
	# Swap the scene after this RPC returns: the old GamePlay must leave the tree first so the new
	# one gets the same name / node paths (RPCs and Player look for "GamePlay").
	_swap_scene.call_deferred(selection)


func _swap_scene(selection: Dictionary) -> void:
	var tree := get_tree()
	var old := tree.current_scene
	tree.root.remove_child(old)
	old.queue_free()
	var scene: Node = load("res://Scene/GamePlay/GamePlay.tscn").instantiate()
	tree.root.add_child(scene)
	tree.current_scene = scene
	if scene is GamePlay:
		scene.game_play_network.set_hero_selection_status(selection)


# ------------------------------------------------------------------ players leaving

func _player_name(peer_id: int) -> String:
	if stats.has(peer_id):
		return str(stats[peer_id]["name"])
	var info: Dictionary = game_play_network.hero_selection_status.get(peer_id, {})
	return str(info.get(GameDefines.NAME, "A player"))


func _on_peer_left(peer_id: int) -> void:
	if not game_play_network.hero_selection_status.has(peer_id): return
	var who := _player_name(peer_id)
	if _started and not is_over:
		# Mid-match: the others keep playing
		_hud.add_feed_message("%s left the match" % who)
		return
	# Loading or after the end: this match can't go on (nobody would load / restart it)
	_hud.show_player_left(who)


func _check_missing_players() -> void:
	if not multiplayer.is_server(): return
	var connected := multiplayer.get_peers()
	for peer_id in game_play_network.hero_selection_status:
		if peer_id != multiplayer.get_unique_id() and not connected.has(peer_id):
			_hud.show_player_left(_player_name(peer_id))
			return


# ------------------------------------------------------------------ helpers for the HUD

func my_team() -> int:
	var me := multiplayer.get_unique_id()
	if stats.has(me):
		return int(stats[me]["team"])
	if game_play_network.hero_selection_status.has(me):
		return int(game_play_network.hero_selection_status[me][GameDefines.TEAM_SIDE])
	return 0


# ------------------------------------------------------------------ zone visual (every peer)

func _build_zone_visual() -> void:
	_zone_visual = Node3D.new()
	_zone_visual.name = "ZoneVisual"
	add_child(_zone_visual)
	_zone_visual.position = GameDefines.ZONE_CENTER + Vector3(0, 0.12, 0)

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = GameDefines.ZONE_RADIUS
	disc_mesh.bottom_radius = GameDefines.ZONE_RADIUS
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 48
	disc.mesh = disc_mesh
	_zone_material = StandardMaterial3D.new()
	_zone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = _zone_material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone_visual.add_child(disc)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = GameDefines.ZONE_RADIUS - 0.25
	ring_mesh.outer_radius = GameDefines.ZONE_RADIUS
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	ring.mesh = ring_mesh
	ring.scale = Vector3(1, 0.15, 1)
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = _ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone_visual.add_child(ring)
	_update_zone_visual()


## Color of the zone for the local player: green = my team holds it, red = enemies, yellow = contested
func zone_color() -> Color:
	match zone_state:
		ZoneState.CONTESTED:
			return Color(1.0, 0.85, 0.2)
		ZoneState.LEFT, ZoneState.RIGHT:
			return Color(0.25, 0.9, 0.3) if zone_state == my_team() else Color(0.95, 0.25, 0.2)
	return Color(0.9, 0.9, 0.9)


func _update_zone_visual() -> void:
	if _zone_material == null: return
	var c := zone_color()
	_zone_material.albedo_color = Color(c.r, c.g, c.b, 0.18)
	_ring_material.albedo_color = c
