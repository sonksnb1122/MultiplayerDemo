class_name MatchSettings
extends RefCounted
## Match options the host picks in the room (Settings button), sent to every player in the room:
## match length, score to win, bots filling the teams and how well the bots play.
## Static: they stay the same for every match of the session ("Play again" too).

## Choices shown in the room's Settings panel
const DURATIONS := [180, 300, 480, 600]
const SCORES := [20, 40, 60]
## Bots fill each team up to this many heroes (0 = no bots)
const BOT_TEAM_SIZES := [0, 1, 2, 3]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]

static var match_duration: int = GameDefines.MATCH_DURATION
static var score_to_win: int = GameDefines.SCORE_TO_WIN
static var bot_team_size: int = 0
static var bot_difficulty: int = 1


static func to_dict() -> Dictionary:
	return {"duration": match_duration, "score": score_to_win, "bots": bot_team_size, "difficulty": bot_difficulty}


## Values from the host; anything unknown keeps the default (a client can't pick odd values)
static func apply(values: Dictionary) -> void:
	var d := int(values.get("duration", match_duration))
	match_duration = d if DURATIONS.has(d) else GameDefines.MATCH_DURATION
	var s := int(values.get("score", score_to_win))
	score_to_win = s if SCORES.has(s) else GameDefines.SCORE_TO_WIN
	var b := int(values.get("bots", bot_team_size))
	bot_team_size = b if BOT_TEAM_SIZES.has(b) else 0
	bot_difficulty = clampi(int(values.get("difficulty", bot_difficulty)), 0, DIFFICULTIES.size() - 1)


static func duration_text(seconds: int) -> String:
	return "%d min" % (seconds / 60)


static func bots_text(team_size: int) -> String:
	return "No bots" if team_size <= 0 else "Fill to %dv%d" % [team_size, team_size]


## One line for the room: "5 min  ·  40 points  ·  Bots: Fill to 2v2 (Normal)"
static func summary() -> String:
	var bots := "Bots: off" if bot_team_size <= 0 else "Bots: %s (%s)" % [bots_text(bot_team_size), DIFFICULTIES[bot_difficulty]]
	return "%s   |   %d points   |   %s" % [duration_text(match_duration), score_to_win, bots]
