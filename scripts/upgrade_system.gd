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

const SYNERGIES: Array[Dictionary] = [
	{
		"id": "thunder_blaze",
		"name": "雷火风暴",
		"requires": ["multishot", "ricochet"],
		"desc": "暴击与击杀额外触发链式闪电，电击周围最多 2 名敌人",
		"color": Color(0.45, 0.85, 1.0),
	},
	{
		"id": "focus_beam",
		"name": "聚能死光",
		"requires": ["pierce", "crit"],
		"desc": "子弹每次穿透后伤害 +1 且必定触发暴击爆发",
		"color": Color(1.0, 0.88, 0.30),
	},
	{
		"id": "aftershock_nova",
		"name": "灼烧余震",
		"requires": ["nova_plus", "charge"],
		"desc": "必杀释放后在原地留下 3.5 秒烈焰领域持续灼烧敌人",
		"color": Color(1.0, 0.50, 0.18),
	},
	{
		"id": "aegis_siphon",
		"name": "圣盾回响",
		"requires": ["shield", "vampire"],
		"desc": "护盾碎裂时爆发清弹震荡波，战意虹吸降至 10 杀回血",
		"color": Color(0.38, 0.96, 0.72),
	},
]

var ship: Dictionary = ShipCatalog.SHIPS[0]
var levels: Dictionary = {}
var picked_order: Array[String] = []
var unlocked_synergies: Array[String] = []


func reset(ship_id: String = "vanguard") -> void:
	ship = ShipCatalog.get_ship(ship_id)
	levels.clear()
	picked_order.clear()
	unlocked_synergies.clear()


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
	var newly_activated: Array[Dictionary] = []
	for syn in SYNERGIES:
		var sid := str(syn["id"])
		if unlocked_synergies.has(sid):
			continue
		if _meets_synergy(syn):
			unlocked_synergies.append(sid)
			newly_activated.append(syn)
	var result := item.duplicate()
	result["new_synergies"] = newly_activated
	return result


func _meets_synergy(syn: Dictionary) -> bool:
	var reqs: Array = syn["requires"]
	for req in reqs:
		if level_of(str(req)) <= 0:
			return false
	return true


func has_synergy(syn_id: String) -> bool:
	return unlocked_synergies.has(syn_id)


func active_synergies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for syn in SYNERGIES:
		if unlocked_synergies.has(str(syn["id"])):
			out.append(syn)
	return out


func would_activate_synergies(candidate_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for syn in SYNERGIES:
		var sid := str(syn["id"])
		if unlocked_synergies.has(sid):
			continue
		var reqs: Array = syn["requires"]
		if not reqs.has(candidate_id):
			continue
		var ok := true
		for req in reqs:
			var rid := str(req)
			if rid != candidate_id and level_of(rid) <= 0:
				ok = false
				break
		if ok:
			out.append(syn)
	return out


func find_item(id: String) -> Dictionary:
	for item in CATALOG:
		if item["id"] == id:
			return item
	return {}


func roll_choices(count: int = 3, guarantee_epic: bool = false, exclude_ids: Array[String] = []) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for item in CATALOG:
		var id := str(item["id"])
		if level_of(id) < int(item["max_level"]) and not exclude_ids.has(id):
			pool.append(item)
	# If excluding previous ids leaves fewer than count, allow the full available pool.
	if pool.size() < count and not exclude_ids.is_empty():
		pool.clear()
		for item in CATALOG:
			if level_of(str(item["id"])) < int(item["max_level"]):
				pool.append(item)

	var chosen: Array[Dictionary] = []
	if pool.is_empty():
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
		var w := _rarity_weight(int(item["rarity"]))
		# Slightly favor upgrades that complete an active synergy!
		if not would_activate_synergies(str(item["id"])).is_empty():
			w *= 1.65
		total += w
	var roll := randf() * total
	var acc := 0.0
	for item in pool:
		var w := _rarity_weight(int(item["rarity"]))
		if not would_activate_synergies(str(item["id"])).is_empty():
			w *= 1.65
		acc += w
		if roll <= acc:
			return item
	return pool.back()


func _rarity_weight(r: int) -> float:
	match r:
		Rarity.EPIC:
			return 0.72
		Rarity.RARE:
			return 1.18
		_:
			return 1.55


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


func base_max_hp() -> int:
	return int(ship.get("base_hp", 5)) + level_of("vitality")


func projectile_count() -> int:
	return int(ship.get("base_projectiles", 1)) + level_of("multishot")


func fire_cooldown() -> float:
	var ship_mult := float(ship.get("fire_rate_mult", 1.0))
	return (0.165 / maxf(ship_mult, 0.5)) / pow(1.22, float(level_of("fire_rate")))


func bullet_damage() -> int:
	return 1 + level_of("damage")


func pierce_count() -> int:
	return int(ship.get("base_pierce", 0)) + level_of("pierce")


func ricochet_count() -> int:
	return level_of("ricochet")


func crit_chance() -> float:
	var base := float(ship.get("base_crit", 0.05))
	return minf(0.80, base + 0.18 * float(level_of("crit")))


func move_speed() -> float:
	var ship_mult := float(ship.get("speed_mult", 1.0))
	return 325.0 * ship_mult * (1.0 + 0.14 * float(level_of("speed")))


func charge_mult() -> float:
	var ship_mult := float(ship.get("charge_mult", 1.0))
	return ship_mult * (1.0 + 0.30 * float(level_of("charge")))


func pickup_radius() -> float:
	return 125.0 * (1.0 + 0.35 * float(level_of("charge")))


func nova_radius_mult() -> float:
	var ship_mult := float(ship.get("nova_mult", 1.0))
	return ship_mult * (1.0 + 0.25 * float(level_of("nova_plus")))


func nova_damage_bonus() -> int:
	return 3 * level_of("nova_plus")


func max_hp_bonus() -> int:
	return level_of("vitality")


func wave_shield_max() -> int:
	return level_of("shield")


func vampire_enabled() -> bool:
	return level_of("vampire") > 0


func vampire_threshold() -> int:
	return 10 if has_synergy("aegis_siphon") else 15


func summary_tags() -> Array[String]:
	var out: Array[String] = []
	for syn in active_synergies():
		out.append("⚡" + str(syn["name"]))
	for id in picked_order:
		var item := find_item(id)
		if item.is_empty():
			continue
		var lv := level_of(id)
		out.append("%s×%d" % [str(item["tag"]), lv] if lv > 1 else str(item["tag"]))
	return out
