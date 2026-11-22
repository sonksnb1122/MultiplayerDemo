class_name GameDefines

# Broadcast
const BROADCAST_ADDRESS := "255.255.255.255"
const BROADCAST_PORT = 7777
const BROADCAST_INTERVAL = 0.1
const BROADCAST_NUM_TRIED := 5 # close room after 5 tried get broadcast packet not found

const GAME_PORT = 44321
const MAX_PLAYER = 4
const HOST_ID = 1
const COOL_DOWN_START_GAME = 3
## Seconds the host waits for slow peers (still loading) before spawning every hero anyway
const TIMEOUT_FORCE_SPAWN_HERO = 20
const COOL_DOWN_FOR_RESPAWN_AFTER_DEAD = 0.5

# --- Match rules (MatchManager) ---
## Length of a match in seconds
const MATCH_DURATION = 300
## First team to reach this score wins
const SCORE_TO_WIN = 40
## Points for the team of the killer
const KILL_SCORE = 2
## King of the Hill zone in the middle of the arena: 1 point every ZONE_TICK seconds
const ZONE_CENTER = Vector3(0, 0, 2.5)
const ZONE_RADIUS = 8.0
const ZONE_TICK = 4.0
## Respawn time: RESPAWN_BASE for the first death, + RESPAWN_PER_DEATH for each next one
const RESPAWN_BASE = 3.0
const RESPAWN_PER_DEATH = 1.0
const RESPAWN_MAX = 10.0

## Melee heroes (no projectile) heal this share of their basic attack damage
const MELEE_LIFESTEAL = 0.15

const ROOM_SUFFIX_STR = "Room#"
const PLAYER_SUFFIX_STR = "P#"

const NAME = "Name"
const READY = "Ready"
const TEAM_SIDE = "Side"
const UNREADY = "Unready"
const SLOT = "Slot"
const STARTING_IN_STR = "Starting in "
const LOBBY_TIME = 30
const STARTING_TIME = 5
const STOP_DISTANCE = 0.5

const HERO_ID = "Hero"
const LOCKED = "Lock"
const UNLOCK = "Unlock"

const ZOOM_MAX = 60.0
const ZOOM_MIN = 30.0
const ZOOM_STEP = 1.0
const CAMERA_SPEED = 0.1

enum TeamSide {
	LEFT = 0,
	RIGHT,
}

const CIRCLE_BUFFER_SIZE = 400
const LEFT_TEAM_SPAWN_POSITION = Vector3(-40, 0, 0)
const RIGHT_TEAM_SPAWN_POSITION = Vector3(40, 0, 0)
const DISTANCE_SPAWN_BETWEEN_PLAYERS = 5

const MAIN_MENU_SCENE = "res://Scene/MainMenu/MainMenu.tscn"

enum DisconnectReason {
	NONE = 0,
	HOST_CLOSED_ROOM,
	NETWORK_ISSUE,
	## Left a finished / broken match: open the room list again
	BACK_TO_LOBBY,
}
