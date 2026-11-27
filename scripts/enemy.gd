extends CharacterBody2D
class_name Enemy

enum Kind { CHASER, SHOOTER, BRUISER, DASHER, SPLITTER, MINI, BOSS }

signal killed(enemy: Enemy, points: int)
signal boss_hp_changed(hp: int, max_hp: int)
signal split_requested(pos: Vector2, count: int)

const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")

var kind: Kind = Kind.CHASER
var hp: int = 2
var max_hp: int = 2
var speed: float = 120.0
var points: int = 100
var alive: bool = true
var arena_rect: Rect2 = Rect2()
var player: Node2D

var _flash: float = 0.0
var _knock: Vector2 = Vector2.ZERO
var _shoot_cd: float = 1.0
var _pulse: float = 0.0
var _spawn_t: float = 0.0
var _telegraph: float = 0.0
var _telegraph_dir: Vector2 = Vector2.RIGHT
var _dash_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _boss_phase_cd: float = 1.6
var _boss_pattern: int = 0
var _contact_radius: float = 26.0
var _radius: float = 14.0
var _core_col: Color = Color(0.95, 0.25, 0.3)

@onready var body: Polygon2D = $Body
@onready var ring: Polygon2D = $Ring
@onready var col_shape: CollisionShape2D = $CollisionShape2D


func setup(k: Kind, pos: Vector2, p: Node2D, rect: Rect2, wave: int) -> void:
	kind = k
	global_position = pos
	player = p
	arena_rect = rect
	alive = true
	_pulse = randf() * TAU
	_spawn_t = 0.0
	_telegraph = 0.0
	_dash_timer = 0.0
	scale = Vector2(0.2, 0.2)

	match kind:
		Kind.CHASER:
			max_hp = 2 + int(wave / 3)
			speed = 135.0 + minf(float(wave) * 5.0, 95.0)
			points = 100
			_radius = 14.0
			_contact_radius = 25.0
			_core_col = Color(1.0, 0.28, 0.32)
			body.color = _core_col
			ring.color = Color(1.0, 0.42, 0.45, 0.26)
			_set_dart_poly()
		Kind.SHOOTER:
			max_hp = 2 + int(wave / 4)
			speed = 98.0 + minf(float(wave) * 3.0, 60.0)
			points = 150
			_radius = 14.5
			_contact_radius = 25.0
			_core_col = Color(0.72, 0.36, 1.0)
			body.color = _core_col
			ring.color = Color(0.82, 0.48, 1.0, 0.26)
			_set_poly(5, _radius)
			_shoot_cd = randf_range(0.75, 1.25)
		Kind.BRUISER:
			max_hp = 6 + int(wave * 0.65)
			speed = 74.0 + minf(float(wave) * 2.0, 42.0)
			points = 260
			_radius = 21.0
			_contact_radius = 34.0
			_core_col = Color(1.0, 0.72, 0.18)
			body.color = _core_col
			ring.color = Color(1.0, 0.85, 0.32, 0.26)
			_set_poly(6, _radius)
			_set_collision_radius(21.0)
		Kind.DASHER:
			max_hp = 3 + int(wave / 4)
			speed = 118.0 + minf(float(wave) * 3.5, 65.0)
			points = 180
			_radius = 15.0
			_contact_radius = 26.0
			_core_col = Color(1.0, 0.22, 0.68)
			body.color = _core_col
			ring.color = Color(1.0, 0.38, 0.78, 0.28)
			_set_diamond_poly(_radius)
			_shoot_cd = randf_range(1.1, 1.7)
		Kind.SPLITTER:
			max_hp = 4 + int(wave / 3)
			speed = 88.0 + minf(float(wave) * 2.5, 45.0)
			points = 200
			_radius = 17.0
			_contact_radius = 28.0
			_core_col = Color(0.24, 0.88, 1.0)
			body.color = _core_col
			ring.color = Color(0.42, 0.94, 1.0, 0.26)
			_set_poly(8, _radius)
			_set_collision_radius(17.0)
		Kind.MINI:
			max_hp = 1 + int(wave / 7)
			speed = 165.0 + minf(float(wave) * 4.0, 80.0)
			points = 60
			_radius = 9.5
			_contact_radius = 20.0
			_core_col = Color(0.45, 0.95, 1.0)
			body.color = _core_col
			ring.color = Color(0.55, 0.98, 1.0, 0.28)
			_set_poly(3, _radius)
			_set_collision_radius(10.0)
		Kind.BOSS:
			var tier := maxi(1, int(wave / 5))
			max_hp = 42 + (tier - 1) * 28
			speed = 86.0 + float(tier - 1) * 8.0
			points = 1200 + (tier - 1) * 400
			_radius = 34.0
			_contact_radius = 46.0
			_core_col = Color(1.0, 0.34, 0.2)
			body.color = _core_col
			ring.color = Color(1.0, 0.76, 0.24, 0.34)
			_set_star_poly(8, 36.0, 22.0)
			_set_collision_radius(32.0)
			_boss_phase_cd = 1.4
	hp = max_hp
	add_to_group("enemies")
	if kind == Kind.BOSS:
		boss_hp_changed.emit(hp, max_hp)


func _set_collision_radius(r: float) -> void:
	if col_shape != null and col_shape.shape is CircleShape2D:
		var dup := (col_shape.shape as CircleShape2D).duplicate() as CircleShape2D
		dup.radius = r
		col_shape.shape = dup


func _set_poly(sides: int, radius: float = 14.0) -> void:
	var pts := PackedVector2Array()
	var rpts := PackedVector2Array()
	for i in sides:
		var a := -PI * 0.5 + TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
		rpts.append(Vector2(cos(a), sin(a)) * (radius + 6.5))
	body.polygon = pts
	ring.polygon = rpts


func _set_dart_poly() -> void:
	body.polygon = PackedVector2Array([
		Vector2(16, 0), Vector2(-11, 11), Vector2(-6, 0), Vector2(-11, -11)
	])
	ring.polygon = PackedVector2Array([
		Vector2(21, 0), Vector2(-15, 15), Vector2(-8, 0), Vector2(-15, -15)
	])


func _set_diamond_poly(r: float) -> void:
	body.polygon = PackedVector2Array([
		Vector2(r * 1.25, 0), Vector2(0, r * 0.85), Vector2(-r * 1.15, 0), Vector2(0, -r * 0.85)
	])
	var rr := r + 5.5
	ring.polygon = PackedVector2Array([
		Vector2(rr * 1.25, 0), Vector2(0, rr * 0.85), Vector2(-rr * 1.15, 0), Vector2(0, -rr * 0.85)
	])


func _set_star_poly(points_count: int, outer_r: float, inner_r: float) -> void:
	var pts := PackedVector2Array()
	var rpts := PackedVector2Array()
	var total := points_count * 2
	for i in total:
		var a := -PI * 0.5 + TAU * float(i) / float(total)
		var r := outer_r if i % 2 == 0 else inner_r
		pts.append(Vector2(cos(a), sin(a)) * r)
		rpts.append(Vector2(cos(a), sin(a)) * (r + 9.0))
	body.polygon = pts
	ring.polygon = rpts


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _spawn_t < 0.18:
		_spawn_t = minf(0.18, _spawn_t + delta)
		var s := lerpf(0.2, 1.0, _spawn_t / 0.18)
		scale = Vector2(s, s)
	_flash = maxf(0.0, _flash - delta)
	_pulse += delta * 6.5
	if _flash > 0.0:
		modulate = Color(3.0, 2.3, 1.6)
	else:
		modulate = Color.WHITE
		ring.scale = Vector2.ONE * (1.0 + 0.08 * sin(_pulse))

	if not is_instance_valid(player) or player.get("alive") == false:
		velocity = _knock
		_knock = _knock.move_toward(Vector2.ZERO, 1200.0 * delta)
		move_and_slide()
		queue_redraw()
		return

	var to_p: Vector2 = player.global_position - global_position
	var dist := to_p.length()
	var dir := to_p.normalized() if dist > 1.0 else Vector2.RIGHT

	match kind:
		Kind.CHASER, Kind.MINI:
			body.rotation = dir.angle()
			ring.rotation = dir.angle()
			velocity = dir * speed + _knock
		Kind.SHOOTER:
			ring.rotation += delta * 1.4
			if _telegraph > 0.0:
				_telegraph -= delta
				velocity = _knock * 0.4
				if _telegraph <= 0.0:
					_fire_at(_telegraph_dir, 290.0)
			else:
				var desired := dir
				if dist < 175.0:
					desired = -dir
				elif dist > 285.0:
					desired = dir
				else:
					desired = Vector2(-dir.y, dir.x)
				velocity = desired * speed + _knock
				_shoot_cd -= delta
				if _shoot_cd <= 0.0 and dist < 440.0:
					_shoot_cd = randf_range(1.25, 1.8)
					_telegraph = 0.42
					_telegraph_dir = dir
		Kind.BRUISER:
			body.rotation += delta * 0.65
			ring.rotation -= delta * 0.9
			velocity = dir * speed + _knock
		Kind.SPLITTER:
			body.rotation -= delta * 1.5
			ring.rotation += delta * 2.1
			velocity = dir * speed + _knock
		Kind.DASHER:
			if _dash_timer > 0.0:
				_dash_timer -= delta
				velocity = _dash_dir * 490.0 + _knock * 0.2
			elif _telegraph > 0.0:
				_telegraph -= delta
				body.rotation = _telegraph_dir.angle()
				ring.rotation = _telegraph_dir.angle()
				velocity = _knock * 0.25
				if _telegraph <= 0.0:
					_dash_dir = _telegraph_dir
					_dash_timer = 0.38
			else:
				body.rotation = dir.angle()
				ring.rotation = dir.angle()
				velocity = dir * speed + _knock
				_shoot_cd -= delta
				if _shoot_cd <= 0.0 and dist < 340.0 and dist > 80.0:
					_shoot_cd = randf_range(2.0, 2.6)
					_telegraph = 0.52
					_telegraph_dir = dir
		Kind.BOSS:
			_process_boss(delta, dir, dist)

	_knock = _knock.move_toward(Vector2.ZERO, 1100.0 * delta)
	move_and_slide()
	_clamp()

	if dist < _contact_radius:
		if player.has_method("take_damage"):
			var dmg := 2 if (kind == Kind.BRUISER or kind == Kind.BOSS) else 1
			player.take_damage(dmg, global_position)
			_knock = -dir * (80.0 if kind == Kind.BOSS else 170.0)
	queue_redraw()


func _process_boss(delta: float, dir: Vector2, dist: float) -> void:
	body.rotation += delta * 0.9
	ring.rotation -= delta * 1.4
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _dash_dir * 440.0
		return
	if _telegraph > 0.0:
		_telegraph -= delta
		velocity = Vector2.ZERO
		if _telegraph <= 0.0:
			match _boss_pattern:
				0:
					# Aimed 3-way volley
					for off in [-0.24, 0.0, 0.24]:
						_fire_at(_telegraph_dir.rotated(off), 300.0)
				1:
					# 10-way radial fire ring
					var base := _pulse
					for i in 10:
						var a := base + TAU * float(i) / 10.0
						_fire_at(Vector2(cos(a), sin(a)), 245.0)
				_:
					# Arena charge
					_dash_dir = _telegraph_dir
					_dash_timer = 0.45
			_boss_pattern = (_boss_pattern + 1) % 3
			_boss_phase_cd = 1.65
		return

	# Approach then strafe
	var desired := dir if dist > 220.0 else Vector2(-dir.y, dir.x) * 0.75 + dir * 0.25
	velocity = desired.normalized() * speed + _knock * 0.25
	_boss_phase_cd -= delta
	if _boss_phase_cd <= 0.0:
		_telegraph_dir = dir
		_telegraph = 0.62 if _boss_pattern == 2 else 0.48


func _draw() -> void:
	# Telegraph sightlines
	if _telegraph > 0.0:
		var warn_col := Color(1.0, 0.26, 0.45, 0.85) if (kind == Kind.DASHER or (kind == Kind.BOSS and _boss_pattern == 2)) else Color(0.95, 0.45, 1.0, 0.75)
		if kind == Kind.BOSS and _boss_pattern == 1:
			draw_arc(Vector2.ZERO, _radius + 14.0 + sin(_pulse * 4.0) * 4.0, 0.0, TAU, 36, Color(1.0, 0.78, 0.25, 0.9), 3.0, true)
		else:
			var beam_len := 240.0 if kind == Kind.SHOOTER else 320.0
			draw_line(Vector2.ZERO, _telegraph_dir * beam_len, warn_col, 2.4, true)
			draw_circle(Vector2.ZERO, _radius + 6.0, Color(warn_col.r, warn_col.g, warn_col.b, 0.2))

	# Inner bright core for depth
	if kind == Kind.BOSS:
		draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.9, 0.55, 0.92))
	elif kind == Kind.BRUISER or kind == Kind.SPLITTER:
		draw_circle(Vector2.ZERO, _radius * 0.35, Color(1, 1, 1, 0.45))

	# Mini HP bar on damaged non-boss tanky enemies
	if kind != Kind.BOSS and hp < max_hp and max_hp >= 3:
		var bw := maxf(_radius * 2.0, 28.0)
		var bh := 4.5
		var top_y := -_radius - 13.0
		var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		draw_rect(Rect2(-bw * 0.5, top_y, bw, bh), Color(0.08, 0.06, 0.12, 0.85))
		draw_rect(Rect2(-bw * 0.5, top_y, bw * ratio, bh), _core_col.lightened(0.15))


func _clamp() -> void:
	if arena_rect.size == Vector2.ZERO:
		return
	var pad := _radius + 4.0
	global_position.x = clampf(global_position.x, arena_rect.position.x + pad, arena_rect.end.x - pad)
	global_position.y = clampf(global_position.y, arena_rect.position.y + pad, arena_rect.end.y - pad)


func _fire_at(dir: Vector2, spd: float = 285.0) -> void:
	var b: Bullet = BULLET_SCENE.instantiate()
	b.setup(global_position + dir * (_radius + 6.0), dir, false, 1, spd, 0, 0, false, arena_rect)
	get_parent().add_child(b)


func take_hit(damage: int, from_pos: Vector2, knock_force: float = 220.0, is_crit: bool = false) -> void:
	if not alive:
		return
	hp -= damage
	_flash = 0.10
	var away := (global_position - from_pos).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var resist := 0.12 if kind == Kind.BOSS else (0.42 if kind == Kind.BRUISER else 1.0)
	_knock = away * knock_force * resist
	_play_sfx("hit", randf_range(1.08, 1.25) if is_crit else randf_range(0.85, 1.12), -3.5 if is_crit else -5.5)
	if kind == Kind.BOSS:
		boss_hp_changed.emit(maxi(hp, 0), max_hp)
	var died := hp <= 0
	get_tree().call_group("game", "enemy_impact", global_position, away, died, kind == Kind.BRUISER or kind == Kind.BOSS, damage, is_crit)
	if died:
		_die()


func _die() -> void:
	alive = false
	_play_sfx("die", 0.72 if kind == Kind.BOSS else randf_range(0.9, 1.18), -1.0 if kind == Kind.BOSS else -3.0)
	if kind == Kind.SPLITTER:
		split_requested.emit(global_position, 2)
	killed.emit(self, points)
	queue_free()


func _play_sfx(key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play(key, pitch, volume_db)
