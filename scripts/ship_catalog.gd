extends RefCounted
class_name ShipCatalog

const SHIPS: Array[Dictionary] = [
	{
		"id": "vanguard",
		"name": "烈焰先锋",
		"role": "均衡突击",
		"trait": "5 血 · 标准射速 · 稳健容错",
		"color": Color(1.0, 0.56, 0.20),
		"glow": Color(1.0, 0.42, 0.12, 0.32),
		"base_hp": 5,
		"speed_mult": 1.0,
		"fire_rate_mult": 1.0,
		"base_projectiles": 1,
		"base_pierce": 0,
		"base_crit": 0.05,
		"charge_mult": 1.0,
		"nova_mult": 1.0,
	},
	{
		"id": "storm",
		"name": "雷霆散射",
		"role": "双发爆发",
		"trait": "天生双发 · +14% 移速 · 4 血",
		"color": Color(0.26, 0.88, 1.0),
		"glow": Color(0.18, 0.72, 1.0, 0.34),
		"base_hp": 4,
		"speed_mult": 1.14,
		"fire_rate_mult": 0.94,
		"base_projectiles": 2,
		"base_pierce": 0,
		"base_crit": 0.08,
		"charge_mult": 1.05,
		"nova_mult": 1.0,
	},
	{
		"id": "starcore",
		"name": "星核重炮",
		"role": "贯穿暴击",
		"trait": "天生穿透 · 18% 暴击 · 充能 +20%",
		"color": Color(1.0, 0.82, 0.28),
		"glow": Color(0.95, 0.55, 0.18, 0.34),
		"base_hp": 5,
		"speed_mult": 0.94,
		"fire_rate_mult": 0.88,
		"base_projectiles": 1,
		"base_pierce": 1,
		"base_crit": 0.18,
		"charge_mult": 1.20,
		"nova_mult": 1.15,
	},
]


static func get_ship(id: String) -> Dictionary:
	for s in SHIPS:
		if str(s["id"]) == id:
			return s
	return SHIPS[0]


static func index_of(id: String) -> int:
	for i in SHIPS.size():
		if str(SHIPS[i]["id"]) == id:
			return i
	return 0
