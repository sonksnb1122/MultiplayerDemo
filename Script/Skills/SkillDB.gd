class_name SkillDB
extends RefCounted
## The 3 skills (Q, W, E) of every hero, keyed by CharacterData.id.
## Change numbers here to rebalance; nothing else needs to change.

# --- VFX paths ---
const ARROW_MODEL := "res://Asset/Heroes/KayKit/Items/arrow_bow.gltf"
const CROSSBOW_BOLT_MODEL := "res://Asset/Heroes/KayKit/Items/arrow_crossbow.gltf"
const JAVELIN_RED := "res://Asset/VFX/BinbunVFX/magic_projectiles/effects/mprojectile_javelin/mprojectile_javelin_vfx_04.tscn"
const JAVELIN_YELLOW := "res://Asset/VFX/BinbunVFX/magic_projectiles/effects/mprojectile_javelin/mprojectile_javelin_vfx_01.tscn"
const JAVELIN_BLUE := "res://Asset/VFX/BinbunVFX/magic_projectiles/effects/mprojectile_javelin/mprojectile_javelin_vfx_02.tscn"
const HIT_HEAVY_STEEL := "res://addons/emberset/effects/hit/hit_heavy_steel.tscn"
const GROUND_BLAST_FIRE := "res://addons/emberset/effects/explosion/ground_blast_fire.tscn"
const TORNADO_RED := "res://Asset/VFX/Skills/Valkyrie/tornado_red.tscn"
const TORNADO_BLUE := "res://Asset/VFX/Skills/Valkyrie/tornado_blue.tscn"
const TORNADO_GREEN := "res://Asset/VFX/Skills/Valkyrie/tornado_green.tscn"
const ORB_RED := "res://Asset/VFX/BinbunVFX_Vol2/DarkMagicFX/effects/ball/vfx_ball_evil_01.tscn"
const ORB_PURPLE := "res://Asset/VFX/Skills/Tesla/orb_purple.tscn"
const ORB_BLACK := "res://Asset/VFX/Skills/Tesla/orb_black.tscn"

## The arrow model's tip points along +Z, the javelin VFX along +X; these turn both to -Z.
## If an arrow flies backwards or sideways in game, adjust these two values.
const ARROW_ROTATION := Vector3(0, 180, 0)
const JAVELIN_ROTATION := Vector3(0, 90, 0)

## Skill bar icons ("RPG skill icons" by v-ktor, CC0)
const ICONS := "res://Asset/Art/UI/SkillIcons/"

const RANGER := 1
const BARBARIAN := 2
const KNIGHT := 3
const MAGE := 4
const ROGUE := 5


## Q, W, E, R (ultimate) of the hero, then the Dash every hero has (Space)
static func get_skills(character_id: int) -> Array[SkillData]:
	var list: Array[SkillData] = []
	for values: Dictionary in _table().get(character_id, []):
		list.append(SkillData.make(values))
	list.append(SkillData.make(DASH))
	return list


const DASH := {
	"id": "dash", "icon": ICONS + "lightning_dash_purple.png", "display_name": "Dash", "color": Color(0.75, 0.78, 0.85),
	"description": "Lướt nhanh tới 9m về phía con trỏ.",
	"kind": SkillData.Kind.DASH, "cooldown": 8.0, "cast_range": 9.0, "dash_speed": 42.0,
	"cast_time": 0.0, "impact_delay": 0.0,
}


static func _arrow(values: Dictionary) -> Dictionary:
	var base := {
		"kind": SkillData.Kind.PROJECTILE, "cast_range": 14.0, "cast_time": 0.35, "impact_delay": 0.2,
		"projectile_model": ARROW_MODEL, "projectile_model_rotation": ARROW_ROTATION,
		"projectile_vfx_rotation": JAVELIN_ROTATION, "vfx_scale": 0.7, "projectile_speed": 35.0,
	}
	base.merge(values, true)
	return base


static func _orb(values: Dictionary) -> Dictionary:
	var base := {
		"kind": SkillData.Kind.PROJECTILE, "cast_range": 12.0, "cast_time": 0.4, "impact_delay": 0.25,
		"vfx_scale": 0.5, "projectile_speed": 18.0, "projectile_height": 1.8,
	}
	base.merge(values, true)
	return base


static func _tornado(values: Dictionary) -> Dictionary:
	var base := {
		"kind": SkillData.Kind.AREA_AT_TARGET, "cast_range": 12.0, "cast_time": 0.4, "impact_delay": 0.25,
		"radius": 2.5, "vfx_lifetime": 2.0,
	}
	base.merge(values, true)
	return base


static func _table() -> Dictionary:
	return {
		RANGER: [
			_arrow({"id": "ranger_red", "icon": ICONS + "knife_red.png", "display_name": "Flame Arrow", "color": Color(0.9, 0.2, 0.1),
				"description": "Mũi tên đỏ: sát thương cơ bản + 25.",
				"cooldown": 6.0, "uses_base_damage": true, "bonus_damage": 25, "vfx_scene": JAVELIN_RED}),
			_arrow({"id": "ranger_yellow", "icon": ICONS + "lightning_orange.png", "display_name": "Thunder Arrow", "color": Color(0.95, 0.8, 0.1),
				"description": "Mũi tên vàng: sát thương cơ bản, làm choáng 1.5 giây.",
				"cooldown": 12.0, "uses_base_damage": true, "stun_duration": 1.5, "vfx_scene": JAVELIN_YELLOW}),
			_arrow({"id": "ranger_blue", "icon": ICONS + "knife_white.png", "display_name": "Frost Arrow", "color": Color(0.2, 0.55, 1.0),
				"description": "Mũi tên xanh: sát thương cơ bản, làm chậm 40% trong 3 giây.",
				"cooldown": 9.0, "uses_base_damage": true, "slow_percent": 0.4, "slow_duration": 3.0,
				"vfx_scene": JAVELIN_BLUE}),
			{"id": "ranger_arrow_rain", "icon": ICONS + "knife_impact_orange.png", "sound": "shoot", "hit_sound": "arrow_wave", "display_name": "Arrow Rain", "color": Color(1.0, 0.85, 0.4),
				"description": "CHIÊU CUỐI. Mưa tên xuống vùng bán kính 5m dưới con trỏ: 4 đợt, mỗi đợt 12 sát thương và làm chậm 40%.",
				"kind": SkillData.Kind.AREA_AT_POINT, "cooldown": 40.0, "cast_range": 14.0, "cast_time": 0.4,
				"impact_delay": 0.45, "radius": 5.0, "hits": 4, "hit_interval": 0.5, "bonus_damage": 12,
				"slow_percent": 0.4, "slow_duration": 1.0, "rain_model": ARROW_MODEL, "rain_count": 16,
				"rain_vfx": JAVELIN_YELLOW, "rain_vfx_scale": 0.45},
		],
		BARBARIAN: [
			{"id": "barbarian_heavy_steel", "icon": ICONS + "sword_bash_orange.png", "sound": "swipe", "hit_sound": "axe_heavy", "display_name": "Heavy Steel", "color": Color(0.75, 0.75, 0.8),
				"description": "Cần kẻ địch trong 9m. Đứng tại chỗ đánh hết 1 đòn, đập xuống đất phía trước, choáng mọi kẻ địch trong bán kính 9m quanh Barbarian trong 1.5 giây.",
				"kind": SkillData.Kind.AREA_IN_FRONT, "cooldown": 10.0, "wait_for_attack_animation": true,
				"needs_target": true, "cast_range": 9.0,
				"radius": 9.0, "forward_distance": 4.0, "area_on_caster": true, "stun_duration": 1.5,
				"vfx_scene": HIT_HEAVY_STEEL, "vfx_scale": 5.25},
			{"id": "barbarian_ground_blast", "icon": ICONS + "rock_blade_brown.png", "sound": "swipe", "hit_sound": "blast", "display_name": "Ground Blast", "color": Color(1.0, 0.45, 0.1),
				"description": "Cần kẻ địch trong 15m. Đánh hết 1 đòn rồi nổ lửa cách 8m về phía kẻ địch, gây 45 sát thương trong bán kính 7.5m.",
				"kind": SkillData.Kind.AREA_IN_FRONT, "cooldown": 8.0, "wait_for_attack_animation": true,
				"needs_target": true, "cast_range": 15.0,
				"radius": 7.5, "forward_distance": 8.0, "bonus_damage": 45,
				"vfx_scene": GROUND_BLAST_FIRE, "vfx_scale": 3.3},
			{"id": "barbarian_bubble_shock", "icon": ICONS + "ice_shield_white.png", "sound": "shield_up", "hit_sound": "", "display_name": "Bubble Shock", "color": Color(0.3, 0.75, 1.0),
				"description": "Khiên phép hấp thụ 80 sát thương, vỡ khi hết lượng hấp thụ (tối đa 8 giây).",
				"kind": SkillData.Kind.SELF_BUFF, "cooldown": 15.0, "cast_time": 0.0,
				"buff": SkillData.Buff.SHIELD, "buff_value": 80.0, "buff_duration": 8.0},
			{"id": "barbarian_whirlwind", "icon": ICONS + "whirlwind_red.png", "sound": "fire", "hit_sound": "swipe", "display_name": "Whirlwind", "color": Color(1.0, 0.3, 0.15),
				"description": "CHIÊU CUỐI. Xoay rìu 6 lần trong 2.4 giây quanh mình (bán kính 7.5m), mỗi lần 14 sát thương. Vẫn di chuyển được.",
				"kind": SkillData.Kind.AREA_AROUND_CASTER, "cooldown": 45.0, "cast_time": 0.0, "impact_delay": 0.0,
				"radius": 7.5, "hits": 6, "hit_interval": 0.4, "bonus_damage": 14,
				"caster_animation": "ultimate", "aura_vfx": TORNADO_RED, "aura_scale_xz": 1.6, "aura_scale_y": 0.35},
		],
		MAGE: [
			_tornado({"id": "mage_red", "icon": ICONS + "fire_ball_red.png", "display_name": "Fire Tornado", "color": Color(0.95, 0.25, 0.1),
				"description": "Lốc xoáy đỏ tại vị trí kẻ địch: sát thương cơ bản + 20.",
				"cooldown": 7.0, "uses_base_damage": true, "bonus_damage": 20, "vfx_scene": TORNADO_RED}),
			_tornado({"id": "mage_blue", "icon": ICONS + "ice_strike_white.png", "display_name": "Frost Tornado", "color": Color(0.25, 0.5, 1.0),
				"description": "Lốc xoáy xanh dương: 10 sát thương, làm chậm 50% trong 2.5 giây.",
				"cooldown": 10.0, "bonus_damage": 10, "slow_percent": 0.5, "slow_duration": 2.5,
				"vfx_scene": TORNADO_BLUE}),
			_tornado({"id": "mage_green", "icon": ICONS + "wind_slicer_green.png", "display_name": "Venom Tornado", "color": Color(0.3, 0.85, 0.25),
				"description": "Lốc xoáy xanh lá: mất 6 máu mỗi 0.5 giây trong 4 giây.",
				"cooldown": 12.0, "dot_damage": 6, "dot_interval": 0.5, "dot_duration": 4.0,
				"vfx_scene": TORNADO_GREEN}),
			{"id": "mage_maelstrom", "icon": ICONS + "lightning_cyan.png", "sound": "wind", "hit_sound": "", "display_name": "Maelstrom", "color": Color(0.35, 0.6, 1.0),
				"description": "CHIÊU CUỐI. Cơn lốc lớn dưới con trỏ (bán kính 6m): 4 đợt, mỗi đợt 10 sát thương và choáng 0.6 giây.",
				"kind": SkillData.Kind.AREA_AT_POINT, "cooldown": 45.0, "cast_range": 13.0, "cast_time": 0.5,
				"impact_delay": 0.35, "radius": 6.0, "hits": 4, "hit_interval": 0.5, "bonus_damage": 10,
				"stun_duration": 0.6, "vfx_scene": TORNADO_BLUE, "vfx_scale": 2.2, "vfx_lifetime": 2.2},
		],
		ROGUE: [
			_orb({"id": "rogue_red", "icon": ICONS + "grenade_red.png", "display_name": "Inferno Orb", "color": Color(1.0, 0.3, 0.1),
				"description": "Cầu đỏ: sát thương cơ bản + 25.",
				"cooldown": 6.0, "uses_base_damage": true, "bonus_damage": 25, "vfx_scene": ORB_RED}),
			_orb({"id": "rogue_purple", "icon": ICONS + "arcane_purple.png", "display_name": "Plague Orb", "color": Color(0.65, 0.25, 1.0),
				"description": "Cầu tím: mất 5 máu mỗi 0.5 giây trong 4 giây.",
				"cooldown": 10.0, "dot_damage": 5, "dot_interval": 0.5, "dot_duration": 4.0,
				"vfx_scene": ORB_PURPLE}),
			_orb({"id": "rogue_black", "icon": ICONS + "spell_break_black.png", "display_name": "Void Orb", "color": Color(0.2, 0.15, 0.25),
				"description": "Cầu đen: 10 sát thương, làm choáng 1.5 giây.",
				"cooldown": 12.0, "bonus_damage": 10, "stun_duration": 1.5, "vfx_scene": ORB_BLACK}),
			{"id": "rogue_crimson_bolt", "icon": ICONS + "beam_pink.png", "sound": "bolt", "hit_sound": "", "display_name": "Crimson Bolt", "color": Color(1.0, 0.2, 0.15),
				"description": "CHIÊU CUỐI. Bắn một mũi tên lớn bọc sấm sét đỏ bay thẳng 26m về phía con trỏ, xuyên qua mọi vật cản: 55 sát thương mọi kẻ địch trên đường bay.",
				"kind": SkillData.Kind.LINE_SHOT, "cooldown": 40.0, "cast_range": 26.0, "cast_time": 0.35,
				"impact_delay": 0.25, "radius": 2.2, "bonus_damage": 55, "projectile_speed": 38.0,
				"projectile_height": 2.0, "projectile_model": CROSSBOW_BOLT_MODEL,
				"projectile_model_rotation": ARROW_ROTATION, "projectile_model_scale": 6.4,
				"vfx_scene": JAVELIN_RED, "vfx_scale": 3.4, "projectile_vfx_rotation": JAVELIN_ROTATION},
		],
		KNIGHT: [
			{"id": "knight_rage", "icon": ICONS + "enhanced_sword_red.png", "sound": "charge_rage", "hit_sound": "", "display_name": "Blood Rage", "color": Color(0.9, 0.1, 0.1),
				"description": "5 đòn đánh thường tiếp theo gây thêm 15 sát thương.",
				"kind": SkillData.Kind.SELF_BUFF, "cooldown": 12.0, "cast_time": 0.0,
				"buff": SkillData.Buff.EMPOWER_ATTACKS, "buff_value": 15.0, "buff_count": 5},
			{"id": "knight_unstoppable", "icon": ICONS + "augmentation_orange.png", "sound": "charge_guard", "hit_sound": "", "display_name": "Unstoppable", "color": Color(1.0, 0.6, 0.1),
				"description": "Kháng mọi hiệu ứng khống chế (choáng, làm chậm) trong 5 giây và giải các hiệu ứng đang dính.",
				"kind": SkillData.Kind.SELF_BUFF, "cooldown": 16.0, "cast_time": 0.0,
				"buff": SkillData.Buff.CC_IMMUNE, "buff_duration": 5.0},
			{"id": "knight_sprint", "icon": ICONS + "lightning_dash_cyan.png", "sound": "charge_speed", "hit_sound": "", "display_name": "Sprint", "color": Color(0.2, 0.55, 1.0),
				"description": "Tăng gấp đôi tốc độ di chuyển trong 3 giây.",
				"kind": SkillData.Kind.SELF_BUFF, "cooldown": 12.0, "cast_time": 0.0,
				"buff": SkillData.Buff.HASTE, "buff_value": 2.0, "buff_duration": 3.0},
			{"id": "knight_shield_charge", "icon": ICONS + "shield_colored.png", "sound": "dash", "hit_sound": "metal_clang", "display_name": "Shield Charge", "color": Color(1.0, 0.8, 0.25),
				"description": "CHIÊU CUỐI. Lao tới kẻ địch trong 14m, đập khiên: 30 sát thương và choáng 1.25 giây mọi kẻ địch trong 4.5m, rồi đánh tiếp mục tiêu.",
				"kind": SkillData.Kind.DASH, "needs_target": true, "cooldown": 40.0, "cast_range": 14.0,
				"cast_time": 0.0, "impact_delay": 0.0, "dash_speed": 45.0, "radius": 4.5, "bonus_damage": 30,
				"stun_duration": 1.25, "vfx_scene": HIT_HEAVY_STEEL, "vfx_scale": 3.0},
		],
	}
