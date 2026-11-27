extends RefCounted
class_name UpgradeSystem

enum Rarity { COMMON, RARE, EPIC }

const CATALOG: Array[Dictionary] = [
	{
		"id": "multishot",
		"name": "扇形齐射",
		"tag": "多发",
		"desc": "每次射击额外发射 +1 发弹丸，形成扇形火力网",
		"rarity": Rarity.EPIC,
		"max_level": 2,
		"color": Color(1.0, 0.52, 0.18),
	},
	{
		"id": "fire_rate",
		"name": "炙热连发",
		"tag": "射速",
		"desc": "武器射速提升 22%，弹幕倾泻更快",
		"rarity": Rarity.COMMON,
		"max_level": 4,
		"color": Color(1.0, 0.78, 0.25),
	},
	{
		"id": "damage",
		"name": "高能弹芯",
		"tag": "火力",
		"desc": "单发子弹基础伤害 +1，快速融化重甲目标",
		"rarity": Rarity.RARE,
		"max_level": 4,
		"color": Color(1.0, 0.34, 0.32),
	},
	{
		"id": "pierce",
		"name": "贯穿射线",
		"tag": "穿透",
		"desc": "子弹可额外穿透 +1 名敌人，清理尸潮利器",
		"rarity": Rarity.RARE,
		"max_level": 3,
		"color": Color(0.28, 0.88, 1.0),
	},
	{
		"id": "ricochet",
		"name": "电弧弹射",
		"tag": "弹射",
		"desc": "命中后自动向附近目标弹射 +1 次",
		"rarity": Rarity.EPIC,
		"max_level": 2,
		"color": Color(0.55, 0.75, 1.0),
	},
	{
		"id": "crit",
		"name": "烈焰暴击",
		"tag": "暴击",
		"desc": "暴击率 +18%，暴击造成 2 倍伤害与金色爆裂",
		"rarity": Rarity.RARE,
		"max_level": 3,
		"color": Color(1.0, 0.86, 0.28),
	},
	{
		"id": "speed",
		"name": "推进增压",
		"tag": "机动",
		"desc": "移动速度 +14%，更轻松走位躲避弹幕",
		"rarity": Rarity.COMMON,
		"max_level": 3,
		"color": Color(0.35, 0.95, 0.78),
	},
	{
		"id": "charge",
		"name": "聚能核心",
		"tag": "充能",
		"desc": "必杀充能效率 +30%，掉落物磁吸范围 +35%",
		"rarity": Rarity.COMMON,
		"max_level": 3,
		"color": Color(0.45, 0.82, 1.0),
	},
	{
		"id": "nova_plus",
		"name": "超新星扩域",
		"tag": "必杀",
		"desc": "必杀冲击范围 +25%、伤害 +3，触发双环爆破",
		"rarity": Rarity.RARE,
		"max_level": 3,
		"color": Color(1.0, 0.62, 0.2),
	},
	{
		"id": "shield",
		"name": "脉冲护盾",
		"tag": "护盾",
		"desc": "每波自动充能 +1 层护盾抵挡致命伤害，并立即回 1 血",
		"rarity": Rarity.EPIC,
		"max_level": 2,
		"color": Color(0.32, 0.92, 1.0),
	},
	{
		"id": "vitality",
		"name": "熔核护甲",
		"tag": "生命",
		"desc": "最大生命上限 +1，并立即回复 2 点生命",
		"rarity": Rarity.COMMON,
		"max_level": 3,
		"color": Color(0.32, 0.95, 0.56),
	},
	{
		"id": "vampire",
		"name": "战意虹吸",
		"tag": "续航",
		"desc": "每累计击杀 15 名敌人自动回复 1 点生命",
		"rarity": Rarity.EPIC,
		"max_level": 1,
		"color": Color(0.95, 0.35, 0.65),
	},
]

var levels: Dictionary = {}
var picked_order: Array[String] = []


func reset() -> void:
	levels.clear()
	picked_order.clear()


func level_of(id: String) -> int:
	return int(levels.get(id, 0))


func apply(id: String) -> Dictionary:
	var item := find_item(id)
	if item.is_empty():
		return {}
	var cur := level_of(id)
	var max_lv := int(item["max_level"])
	if cur >= max_lv:
		return item
	levels[id] = cur + 1
	if not picked_order.has(id):
		picked_order.append(id)
	return item


func find_item(id: String) -> Dictionary:
	for item in CATALOG:
		if item["id"] == id:
			return item
	return {}


func roll_choices(count: int = 3, guarantee_epic: bool = false) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for item in CATALOG:
		if level_of(str(item["id"])) < int(item["max_level"]):
			pool.append(item)
	var chosen: Array[Dictionary] = []
	if pool.is_empty():
		# Fallback reward when every upgrade is maxed out.
		return [{
			"id": "bonus_heal",
			"name": "满载补给",
			"tag": "补给",
			"desc": "回复 2 点生命并立刻填满 50% 必杀能量",
			"rarity": Rarity.EPIC,
			"max_level": 99,
			"color": Color(0.35, 0.95, 0.6),
			"next_level": 1,
		}]
	if guarantee_epic:
		var epics: Array[Dictionary] = []
		for item in pool:
			if int(item["rarity"]) == Rarity.EPIC:
				epics.append(item)
		if not epics.is_empty():
			var pick: Dictionary = epics[randi() % epics.size()].duplicate()
			pick["next_level"] = level_of(str(pick["id"])) + 1
			chosen.append(pick)
			pool.erase(find_item(str(pick["id"])))

	while chosen.size() < count and not pool.is_empty():
		var pick := _weighted_pick(pool)
		pool.erase(pick)
		var copy := pick.duplicate()
		copy["next_level"] = level_of(str(pick["id"])) + 1
		chosen.append(copy)
	return chosen


func _weighted_pick(pool: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for item in pool:
		total += _rarity_weight(int(item["rarity"]))
	var roll := randf() * total
	var acc := 0.0
	for item in pool:
		acc += _rarity_weight(int(item["rarity"]))
		if roll <= acc:
			return item
	return pool.back()


func _rarity_weight(r: int) -> float:
	match r:
		Rarity.EPIC:
			return 0.65
		Rarity.RARE:
			return 1.15
		_:
			return 1.6


static func rarity_label(r: int) -> String:
	match r:
		Rarity.EPIC:
			return "史诗"
		Rarity.RARE:
			return "稀有"
		_:
			return "普通"


static func rarity_color(r: int) -> Color:
	match r:
		Rarity.EPIC:
			return Color(1.0, 0.72, 0.25)
		Rarity.RARE:
			return Color(0.55, 0.78, 1.0)
		_:
			return Color(0.68, 0.74, 0.84)


func projectile_count() -> int:
	return 1 + level_of("multishot")


func fire_cooldown() -> float:
	return 0.165 / pow(1.22, float(level_of("fire_rate")))


func bullet_damage() -> int:
	return 1 + level_of("damage")


func pierce_count() -> int:
	return level_of("pierce")


func ricochet_count() -> int:
	return level_of("ricochet")


func crit_chance() -> float:
	return minf(0.75, 0.05 + 0.18 * float(level_of("crit")))


func move_speed() -> float:
	return 325.0 * (1.0 + 0.14 * float(level_of("speed")))


func charge_mult() -> float:
	return 1.0 + 0.30 * float(level_of("charge"))


func pickup_radius() -> float:
	return 120.0 * (1.0 + 0.35 * float(level_of("charge")))


func nova_radius_mult() -> float:
	return 1.0 + 0.25 * float(level_of("nova_plus"))


func nova_damage_bonus() -> int:
	return 3 * level_of("nova_plus")


func max_hp_bonus() -> int:
	return level_of("vitality")


func wave_shield_max() -> int:
	return level_of("shield")


func vampire_enabled() -> bool:
	return level_of("vampire") > 0


func summary_tags() -> Array[String]:
	var out: Array[String] = []
	for id in picked_order:
		var item := find_item(id)
		if item.is_empty():
			continue
		var lv := level_of(id)
		out.append("%s×%d" % [str(item["tag"]), lv] if lv > 1 else str(item["tag"]))
	return out
