extends Node2D
class_name VfxLayer

## Pure _draw()-based neon VFX engine: embers, sparks, shockwaves, scorch decals,
## burn zones, low-HP heartbeat vignette, spawn portals, target reticle, and combat text.

var arena: Rect2 = Rect2(32, 118, 656, 868)
var lock_target: Node2D = null
var lock_color: Color = Color(1.0, 0.72, 0.28, 0.88)
var low_hp_danger: float = 0.0

var _embers: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _portals: Array[Dictionary] = []
var _scorches: Array[Dictionary] = []
var _burn_zones: Array[Dictionary] = []
var _arcs: Array[Dictionary] = []
var _texts: Array[Dictionary] = []
var _time: float = 0.0


func setup(rect: Rect2) -> void:
	arena = rect
	if _embers.is_empty():
		for i in 28:
			_embers.append({
				"pos": Vector2(
					randf_range(arena.position.x + 8.0, arena.end.x - 8.0),
					randf_range(arena.position.y + 8.0, arena.end.y - 8.0)
				),
				"vy": randf_range(-28.0, -10.0),
				"vx": randf_range(-8.0, 8.0),
				"r": randf_range(1.4, 3.4),
				"phase": randf() * TAU,
				"warm": randf(),
			})
	else:
		for e in _embers:
			e["pos"].x = clampf(e["pos"].x, arena.position.x + 8.0, arena.end.x - 8.0)
			e["pos"].y = clampf(e["pos"].y, arena.position.y + 8.0, arena.end.y - 8.0)


func clear_combat() -> void:
	_sparks.clear()
	_rings.clear()
	_portals.clear()
	_scorches.clear()
	_burn_zones.clear()
	_arcs.clear()
	_texts.clear()
	lock_target = null
	low_hp_danger = 0.0
	queue_redraw()


func spawn_portal(pos: Vector2, col: Color, duration: float = 0.5, radius: float = 24.0) -> void:
	_portals.append({
		"pos": pos,
		"col": col,
		"t": 0.0,
		"dur": duration,
		"radius": radius,
	})


func spawn_burn_zone(pos: Vector2, radius: float, duration: float = 3.5) -> void:
	_burn_zones.append({
		"pos": pos,
		"r": radius,
		"t": 0.0,
		"dur": duration,
	})


func spawn_ring(pos: Vector2, col: Color, start_r: float, end_r: float, dur: float = 0.26, width: float = 3.5) -> void:
	_rings.append({
		"pos": pos,
		"col": col,
		"start_r": start_r,
		"end_r": end_r,
		"t": 0.0,
		"dur": dur,
		"width": width,
	})


func spawn_sparks(pos: Vector2, col: Color, dir: Vector2 = Vector2.ZERO, count: int = 8, speed_min: float = 90.0, speed_max: float = 240.0) -> void:
	var has_dir := dir.length_squared() > 0.01
	var base := dir.normalized() if has_dir else Vector2.RIGHT
	for i in count:
		var ang := base.angle() + randf_range(-0.75, 0.75) if has_dir else (TAU * float(i) / float(maxi(count, 1)) + randf_range(-0.25, 0.25))
		var spd := randf_range(speed_min, speed_max)
		_sparks.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"col": col.lightened(randf_range(0.0, 0.22)),
			"t": 0.0,
			"dur": randf_range(0.18, 0.34),
			"len": randf_range(5.0, 12.0),
			"width": randf_range(2.0, 3.6),
		})


func spawn_death_burst(pos: Vector2, col: Color, heavy: bool = false) -> void:
	spawn_ring(pos, col, 14.0, 74.0 if heavy else 50.0, 0.28 if heavy else 0.22, 4.5 if heavy else 3.2)
	spawn_sparks(pos, col, Vector2.ZERO, 18 if heavy else 11, 110.0, 310.0 if heavy else 220.0)
	_scorches.append({
		"pos": pos,
		"r": 32.0 if heavy else 20.0,
		"col": col,
		"t": 0.0,
		"dur": 2.4,
	})
	if _scorches.size() > 24:
		_scorches.pop_front()


func spawn_nova(pos: Vector2, radius: float, double_ring: bool = false) -> void:
	spawn_ring(pos, Color(1.0, 0.85, 0.4), 24.0, radius, 0.36, 6.5)
	spawn_ring(pos, Color(1.0, 0.48, 0.16), 16.0, radius * 0.72, 0.30, 4.0)
	if double_ring:
		spawn_ring(pos, Color(0.55, 0.88, 1.0), 32.0, radius * 1.12, 0.44, 3.5)
	spawn_sparks(pos, Color(1.0, 0.78, 0.3), Vector2.ZERO, 26, 160.0, 420.0)
	_scorches.append({
		"pos": pos,
		"r": radius * 0.36,
		"col": Color(1.0, 0.5, 0.15),
		"t": 0.0,
		"dur": 3.0,
	})


func spawn_arc(from_pos: Vector2, to_pos: Vector2, col: Color = Color(0.55, 0.82, 1.0)) -> void:
	_arcs.append({
		"a": from_pos,
		"b": to_pos,
		"col": col,
		"t": 0.0,
		"dur": 0.17,
	})


func spawn_thruster(pos: Vector2, dir: Vector2, overdrive: bool = false, tint: Color = Color(1.0, 0.52, 0.18)) -> void:
	if _sparks.size() > 140:
		return
	var col := Color(1.0, 0.90, 0.32) if overdrive else tint
	var spread := dir.rotated(randf_range(-0.35, 0.35))
	_sparks.append({
		"pos": pos,
		"vel": spread * randf_range(55.0, 110.0),
		"col": col,
		"t": 0.0,
		"dur": randf_range(0.12, 0.2),
		"len": randf_range(4.0, 7.5),
		"width": 2.4,
	})


func spawn_text(pos: Vector2, text: String, col: Color = Color(1, 0.95, 0.75), font_size: int = 20) -> void:
	if _texts.size() > 28:
		_texts.pop_front()
	_texts.append({
		"pos": pos + Vector2(randf_range(-12.0, 12.0), -10.0),
		"text": text,
		"col": col,
		"size": font_size,
		"t": 0.0,
		"dur": 0.68,
	})


func _process(delta: float) -> void:
	_time += delta
	for e in _embers:
		e["pos"] += Vector2(float(e["vx"]) + sin(_time * 1.3 + float(e["phase"])) * 7.0, float(e["vy"])) * delta
		if e["pos"].y < arena.position.y + 4.0:
			e["pos"].y = arena.end.y - 4.0
			e["pos"].x = randf_range(arena.position.x + 8.0, arena.end.x - 8.0)
		elif e["pos"].x < arena.position.x + 4.0:
			e["pos"].x = arena.end.x - 4.0
		elif e["pos"].x > arena.end.x - 4.0:
			e["pos"].x = arena.position.x + 4.0

	_advance_list(_sparks, delta, true)
	_advance_list(_rings, delta, false)
	_advance_list(_portals, delta, false)
	_advance_list(_scorches, delta, false)
	_advance_list(_burn_zones, delta, false)
	_advance_list(_arcs, delta, false)
	for i in range(_texts.size() - 1, -1, -1):
		var item := _texts[i]
		item["t"] = float(item["t"]) + delta
		item["pos"] = item["pos"] + Vector2(0, -46.0 * delta)
		if float(item["t"]) >= float(item["dur"]):
			_texts.remove_at(i)
	queue_redraw()


func _advance_list(list: Array[Dictionary], delta: float, move: bool) -> void:
	for i in range(list.size() - 1, -1, -1):
		var item := list[i]
		item["t"] = float(item["t"]) + delta
		if move:
			item["pos"] = item["pos"] + item["vel"] * delta
			item["vel"] = item["vel"] * (1.0 - minf(1.0, delta * 5.2))
		if float(item["t"]) >= float(item["dur"]):
			list.remove_at(i)


func _draw() -> void:
	# 1. Ambient drifting embers
	for e in _embers:
		var pulse := 0.55 + 0.45 * sin(_time * 2.4 + float(e["phase"]))
		var c := Color(1.0, lerpf(0.35, 0.72, float(e["warm"])), 0.2, 0.22 * pulse)
		draw_circle(e["pos"], float(e["r"]), c)

	# 2. Scorch fade decals
	for sc in _scorches:
		var u := clampf(float(sc["t"]) / float(sc["dur"]), 0.0, 1.0)
		var c: Color = sc["col"]
		draw_circle(sc["pos"], float(sc["r"]), Color(c.r, c.g, c.b, (1.0 - u) * 0.14))

	# 2.5 Aftershock Nova burn zones
	for bz in _burn_zones:
		var u := clampf(float(bz["t"]) / float(bz["dur"]), 0.0, 1.0)
		var fade := 1.0 if u < 0.75 else (1.0 - (u - 0.75) / 0.25)
		var r := float(bz["r"]) * (0.96 + 0.04 * sin(_time * 12.0))
		var p: Vector2 = bz["pos"]
		draw_circle(p, r, Color(1.0, 0.36, 0.10, 0.16 * fade))
		draw_arc(p, r, 0.0, TAU, 44, Color(1.0, 0.62, 0.20, 0.72 * fade), 3.0, true)
		var spin := _time * 3.0
		for k in 3:
			var a := spin + k * TAU / 3.0
			draw_arc(p, r * 0.65, a, a + 0.9, 12, Color(1.0, 0.85, 0.35, 0.52 * fade), 2.2, true)

	# 3. Spawn warning portals
	for p in _portals:
		var u := clampf(float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		var c: Color = p["col"]
		var r := lerpf(float(p["radius"]) * 1.45, float(p["radius"]) * 0.45, u)
		var alpha := 0.25 + 0.65 * sin(u * PI)
		draw_circle(p["pos"], r * 0.65, Color(c.r, c.g, c.b, alpha * 0.22))
		draw_arc(p["pos"], r, 0.0, TAU, 28, Color(c.r, c.g, c.b, alpha), 2.5, true)
		var cross := r * 0.45
		draw_line(p["pos"] - Vector2(cross, 0), p["pos"] + Vector2(cross, 0), Color(c.r, c.g, c.b, alpha * 0.8), 1.8)
		draw_line(p["pos"] - Vector2(0, cross), p["pos"] + Vector2(0, cross), Color(c.r, c.g, c.b, alpha * 0.8), 1.8)

	# 4. Target lock reticle
	if lock_target != null and not is_instance_valid(lock_target):
		lock_target = null
	if lock_target != null and is_instance_valid(lock_target) and lock_target.get("alive") != false:
		var lp: Vector2 = lock_target.global_position
		var r := 24.0 + 2.5 * sin(_time * 10.0)
		var lk = lock_target.get("kind")
		if lk != null and Enemy.is_boss_kind(int(lk)):
			r = 44.0 + 3.0 * sin(_time * 10.0)
		var rot := _time * 2.2
		for k in 4:
			var a := rot + k * PI * 0.5
			draw_arc(lp, r, a - 0.34, a + 0.34, 8, lock_color, 2.4, true)

	# 5. Electric ricochet / chain-lightning arcs
	for a in _arcs:
		var u := clampf(float(a["t"]) / float(a["dur"]), 0.0, 1.0)
		var c: Color = a["col"]
		var p1: Vector2 = a["a"]
		var p2: Vector2 = a["b"]
		var mid := (p1 + p2) * 0.5 + Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
		var col := Color(c.r, c.g, c.b, 1.0 - u)
		draw_line(p1, mid, col, 3.0, true)
		draw_line(mid, p2, col, 3.0, true)

	# 6. Expanding shockwaves
	for r in _rings:
		var u := clampf(float(r["t"]) / float(r["dur"]), 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - u, 2.0)
		var rad := lerpf(float(r["start_r"]), float(r["end_r"]), eased)
		var c: Color = r["col"]
		var alpha := (1.0 - u) * 0.9
		draw_arc(r["pos"], rad, 0.0, TAU, 44, Color(c.r, c.g, c.b, alpha), float(r["width"]) * (1.0 - u * 0.45), true)

	# 7. Velocity sparks
	for s in _sparks:
		var u := clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
		var c: Color = s["col"]
		var v: Vector2 = s["vel"]
		var dir := v.normalized() if v.length_squared() > 0.01 else Vector2.RIGHT
		var tail: Vector2 = s["pos"] - dir * float(s["len"]) * (1.0 - u * 0.5)
		draw_line(tail, s["pos"], Color(c.r, c.g, c.b, 1.0 - u), float(s["width"]), true)

	# 8. Low-HP heartbeat danger edge glow
	if low_hp_danger > 0.01:
		var beat := 0.45 + 0.55 * pow(maxf(0.0, sin(_time * 5.2)), 2.0)
		var alpha := low_hp_danger * beat * 0.38
		var edge_w := 14.0
		var col := Color(1.0, 0.14, 0.22, alpha)
		draw_rect(Rect2(arena.position, Vector2(arena.size.x, edge_w)), col)
		draw_rect(Rect2(Vector2(arena.position.x, arena.end.y - edge_w), Vector2(arena.size.x, edge_w)), col)
		draw_rect(Rect2(arena.position, Vector2(edge_w, arena.size.y)), col)
		draw_rect(Rect2(Vector2(arena.end.x - edge_w, arena.position.y), Vector2(edge_w, arena.size.y)), col)

	# 9. Floating combat text
	var font := ThemeDB.fallback_font
	if font != null:
		for t in _texts:
			var u := clampf(float(t["t"]) / float(t["dur"]), 0.0, 1.0)
			var alpha := 1.0 if u < 0.55 else (1.0 - (u - 0.55) / 0.45)
			var c: Color = t["col"]
			var sz := int(t["size"])
			var text_str := str(t["text"])
			var pos: Vector2 = t["pos"]
			var width := font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			var draw_pos := Vector2(pos.x - width * 0.5, pos.y)
			draw_string(font, draw_pos + Vector2(1.5, 1.5), text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, alpha * 0.7))
			draw_string(font, draw_pos, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(c.r, c.g, c.b, alpha))
