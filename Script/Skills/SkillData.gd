class_name SkillData
extends RefCounted
## Describes one hero skill. All gameplay numbers live here so balancing never touches the logic.
## Instances are built by SkillDB.

enum Kind {
	PROJECTILE,      ## Flies from the hero to an enemy, effect applies on arrival.
	AREA_AT_TARGET,  ## Appears on an enemy in range, hits every enemy within [member radius].
	AREA_IN_FRONT,   ## Lands on the ground in front of the hero (towards the mouse).
	SELF_BUFF,       ## Buffs the caster.
	AREA_AT_POINT,   ## Lands on the ground under the mouse (within cast_range), hits every enemy in radius.
	AREA_AROUND_CASTER, ## Hits every enemy within radius around the caster (follows them while it lasts).
	DASH,            ## The caster rushes up to cast_range toward the mouse (or the target if needs_target);
	                 ## with a radius > 0 it hits every enemy around the end point.
	LINE_SHOT,       ## A shot flying straight toward the mouse for cast_range, through everything
	                 ## (props, heroes): hits every enemy within radius of its path, once.
}

enum Buff {
	NONE,
	SHIELD,           ## Absorbs [member buff_value] damage.
	EMPOWER_ATTACKS,  ## Next [member buff_count] basic attacks deal +[member buff_value] damage.
	CC_IMMUNE,        ## Immune to stun and slow.
	HASTE,            ## Movement speed x[member buff_value].
	STEALTH,          ## Invisible to enemies for buff_duration (unless very close); next basic attack +buff_value.
}

var id: String = ""
var display_name: String = ""
var description: String = ""
var color: Color = Color.WHITE
var kind: Kind = Kind.PROJECTILE

var cooldown: float = 5.0
## Max distance between caster and target (PROJECTILE, AREA_AT_TARGET).
var cast_range: float = 10.0
## Seconds the hero stands still playing "attack". 0 = instant, no animation.
var cast_time: float = 0.3
## Seconds after the cast starts before the projectile leaves / the area lands.
var impact_delay: float = 0.15
## Use the length of the hero's "attack" animation as cast_time and impact_delay:
## the effect lands once the whole attack animation has played.
var wait_for_attack_animation: bool = false
## AREA_IN_FRONT: can only be cast when an enemy is within [member cast_range]; the hero aims at it.
var needs_target: bool = false

# --- Damage ---
## Add the hero's basic attack damage to the skill damage.
var uses_base_damage: bool = false
## Extra damage on top (or the whole damage when uses_base_damage is false).
var bonus_damage: int = 0

# --- Area ---
var radius: float = 0.0
## AREA_IN_FRONT: distance of the effect centre in front of the hero.
var forward_distance: float = 0.0
## AREA_IN_FRONT: true = the hit area is centred on the hero, the VFX still lands in front.
var area_on_caster: bool = false

## Area kinds: how many times the area hits, and the seconds between two hits
var hits: int = 1
var hit_interval: float = 0.5

# --- Dash ---
## Units per second while dashing
var dash_speed: float = 40.0

# --- Crowd control / damage over time ---
var stun_duration: float = 0.0
## 0.4 = 40 % slower.
var slow_percent: float = 0.0
var slow_duration: float = 0.0
var dot_damage: int = 0
var dot_interval: float = 0.5
var dot_duration: float = 0.0

# --- Buffs (SELF_BUFF) ---
var buff: Buff = Buff.NONE
var buff_value: float = 0.0
var buff_count: int = 0
## 0 = no time limit.
var buff_duration: float = 0.0

# --- Visuals ---
var vfx_scene: String = ""
## Emberset effects: their own "size" property. Other scenes: node scale.
var vfx_scale: float = 1.0
## How long area VFX stay before they are removed (tornado).
var vfx_lifetime: float = 2.0
var projectile_model: String = ""
## Rotation (degrees) applied so the model's tip points along -Z (the flight direction).
var projectile_model_rotation: Vector3 = Vector3.ZERO
var projectile_model_scale: float = 1.0
## Rotation (degrees) applied so the VFX points along -Z.
var projectile_vfx_rotation: Vector3 = Vector3.ZERO
var projectile_speed: float = 25.0
## Height above the ground the projectile flies at.
var projectile_height: float = 1.6
## AREA_AT_POINT: models falling from the sky on the area (e.g. arrows), instead of / with vfx_scene
var rain_model: String = ""
var rain_count: int = 12
## VFX attached to every falling model (e.g. lightning on the arrows), and its size
var rain_vfx: String = ""
var rain_vfx_scale: float = 0.5
## Animation the caster plays (and keeps) while the skill lasts, e.g. "ultimate" (HeroModel)
var caster_animation: String = ""
## AREA_AROUND_CASTER: VFX stuck to the caster while the skill lasts (shows the area),
## scaled [member aura_scale_xz] wide and [member aura_scale_y] high
var aura_vfx: String = ""
var aura_scale_xz: float = 1.0
var aura_scale_y: float = 1.0


func total_damage(base_damage: int) -> int:
	return (base_damage if uses_base_damage else 0) + bonus_damage


func is_targeted() -> bool:
	return kind == Kind.PROJECTILE or kind == Kind.AREA_AT_TARGET or needs_target


## Area of effect to draw for the aiming indicator (0 = none)
func indicator_radius() -> float:
	if kind == Kind.PROJECTILE:
		return 1.2
	if kind == Kind.LINE_SHOT:
		return 0.0
	return radius


static func make(values: Dictionary) -> SkillData:
	var s := SkillData.new()
	for key in values:
		if not (key in s):
			push_error("SkillData: unknown field '%s'" % key)
			continue
		s.set(key, values[key])
	return s
