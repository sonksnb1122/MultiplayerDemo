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

const RANGER := 1
const BARBARIAN := 2
const KNIGHT := 3
const MAGE := 4
const ROGUE := 5


static func get_skills(character_id: int) -> Array[SkillData]:
	var list: Array[SkillData] = []
	for values: Dictionary in _table().get(character_id, []):
		list.append(SkillData.make(values))
	return list


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
			_arrow({"id": "ranger_red", "display_name": "Flame Arrow", "color": Color(0.9, 0.2, 0.1),
				"description": "Mũi tên đỏ: sát thương cơ bản + 25.",
				"cooldown": 6.0, "uses_base_damage": true, "bonus_damage": 25, "vfx_scene": JAVELIN_RED}),
			_arrow({"id": "ranger_yellow", "display_name": "Thunder Arrow", "color": Color(0.95, 0.8, 0.1),
				"description": "Mũi tên vàng: sát thương cơ bản, làm choáng 1.5 giây.",
				"cooldown": 12.0, "uses_base_damage": true, "stun_duration": 1.5, "vfx_scene": JAVELIN_YELLOW}),
			_arrow({"id": "ranger_blue", "display_name": "Frost Arrow", "color": Color(0.2, 0.55, 1.0),
				"description": "Mũi tên xanh: sát thương cơ bản, làm chậm 40% trong 3 giây.",
				"cooldown": 9.0, "uses_base_damage": true, "slow_percent": 0.4, "slow_duration": 3.0,
				"vfx_scene": JAVELIN_BLUE}),
		],
		BARBARIAN: [
			{"id": "barbarian_heavy_steel", "display_name": "Heavy Steel", "color": Color(0.75, 0.75, 0.8),
				"description": "Cần kẻ địch trong 9m. Đứng tại chỗ đánh hết 1 đòn, đập xuống đất phía trước, choáng mọi kẻ địch trong bán kính 9m quanh Barbarian trong 1.5 giây.",
				"kind": SkillData.Kind.AREA_IN_FRONT, "cooldown": 10.0, "wait_for_attack_animation": true,
				"needs_target": true, "cast_range": 9.0,
				"radius": 9.0, "forward_distance": 4.0, "area_on_caster": true, "stun_duration": 1.5,
				"vfx_scene": HIT_HEAVY_STEEL, "vfx_scale": 5.25},
			{"id": "barbarian_ground_blast", "display_name": "Ground Blast", "color": Color(1.0, 0.45, 0.1),
				"description": "Cần kẻ địch trong 15m. Đánh hết 1 đòn rồi nổ lửa cách 8m về phía kẻ địch, gây 45 sát thương trong bán kính 7.5m.",
				"kind": SkillData.Kind.AREA_IN_FRONT, "cooldown": 8.0, "wait_for_attack_animation": true,
				"needs_target": true, "cast_range": 15.0,
				"radius": 7.5, "forward_distance": 8.0, "bonus_damage": 45,
				"vfx_scene": GROUND_BLAST_FIRE, "vfx_scale": 3.3},
			{"id": "barbarian_bubble_shock", "display_name": "Bubble Shock", "color": Color(0.3, 0.75, 1.0),
				"description": "Khiên phép hấp thụ 80 sát thương, vỡ khi hết lượng hấp thụ (tối đa 8 giây).",
				"kind": SkillData.Kind.SELF_BUFF, "cooldown": 15.0, "cast_time": 0.0,
				"buff": SkillData.Buff.SHIELD, "buff_value": 80.0, "buff_duration": 8.0},
		],
		MAGE: [
			_tornado({"id": "mage_red", "display_name": "Fire Tornado", "color": Color(0.95, 0.25, 0.1),
				"description": "Lốc xoáy đỏ tại vị trí kẻ địch: sát thương cơ bản + 20.",
				"cooldown": 7.0, "uses_base_damage": true, "bonus_damage": 20, "vfx_scene": TORNADO_RED}),
			_tornado({"id": "mage_blue", "display_name": "Frost Tornado", "color": Color(0.25, 0.5, 1.0),
				"description": "Lốc xoáy xanh dương: 10 sát thương, làm chậm 50% trong 2.5 giây.",
				"cooldown": 10.0, "bonus_damage": 10, "slow_percent": 0.5, "slow_duration": 2.5,
				"vfx_scene": TORNADO_BLUE}),
			_tornado({"id": "mage_green", "display_name": "Venom Tornado", "color": Color(0.3, 0.85, 0.25),
				"description": "Lốc xoáy xanh lá: mất 6 máu mỗi 0.5 giây trong 4 giây.",
				"cooldown": 12.0, "dot_damage": 6, "dot_interval": 0.5, "dot_duration": 4.0,
				"vfx_scene": TORNADO_GREEN}),
		],
		ROGUE: [
			_orb({"id": "rogue_red", "display_name": "Inferno Orb", "color": Color(1.0, 0.3, 0.1),
				"description": "Cầu đỏ: sát thương cơ bản + 25.",
				"cooldown": 6.0, "uses_base_damage": true, "bonus_damage": 25, "vfx_scene": ORB_RED}),
			_orb({"id": "rogue_purple", "display_name": "Plague Orb", "color": Color(0.65, 0.25, 1.0),
				"description": "Cầu tím: mất 5 máu mỗi 0.5 giây trong 4 giây.",
				"cooldown": 10.0, "dot_damage": 5, "dot_interval": 0.5, "dot_duration": 4.0,
				"vfx_scene": ORB_PURPLE}),
			_orb({"id": "rogue_black", "display_name": "Void Orb", "color": Color(0.2, 0.15, 0.25),
				"description": "Cầu đen: 10 sát thương, làm choáng 1.5 giây.",
				"cooldown": 12.0, "bonus_damage": 10, "stun_duration": 1.5, "vfx_scene": ORB_BLACK}),
		],
		KNIGHT: [
			{"id": "knight_rage", "display_name": "Blood Rage", "color": Color(0.9, 0.1, 0.1),
				"description": "5 đòn đánh thường tiếp theo gây thêm 15 sát thương.",
				"kind": SkillData.Kind.SELF_BUFF, "cooldown": 12.0, "cast_time": 0.0,
				"buff": SkillData.Buff.EMPOWER_ATTACKS, "buff_value": 15.0, "buff_count": 5},
			{"id": "knight_unstoppable", "display_name": "Unstoppable", "color": Color(1.0, 0.6, 0.1),
				"description": "Kháng mọi hiệu ứng khống chế (choáng, làm chậm) trong 5 giây và giải các hiệu ứng đang dính.",
				"kind": SkillData.Kind.SELF_BUFF, "cooldown": 16.0, "cast_time": 0.0,
				"buff": SkillData.Buff.CC_IMMUNE, "buff_duration": 5.0},
			{"id": "knight_sprint", "display_name": "Sprint", "color": Color(0.2, 0.55, 1.0),
				"description": "Tăng gấp đôi tốc độ di chuyển trong 3 giây.",
				"kind": SkillData.Kind.SELF_BUFF, "cooldown": 12.0, "cast_time": 0.0,
				"buff": SkillData.Buff.HASTE, "buff_value": 2.0, "buff_duration": 3.0},
		],
	}
