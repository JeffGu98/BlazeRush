extends CharacterBody2D
class_name Enemy

enum Kind { CHASER, SHOOTER, BRUISER }

signal killed(enemy: Enemy, points: int)

var kind: Kind = Kind.CHASER
var hp: int = 2
var max_hp: int = 2
var speed: float = 120.0
var points: int = 100
var alive: bool = true
var arena_rect: Rect2 = Rect2()
var _flash: float = 0.0
var _knock: Vector2 = Vector2.ZERO
var _shoot_cd: float = 1.0
var _pulse: float = 0.0
var player: Node2D

@onready var body: Polygon2D = $Body
@onready var ring: Polygon2D = $Ring

func setup(k: Kind, pos: Vector2, p: Node2D, rect: Rect2, wave: int) -> void:
	kind = k
	global_position = pos
	player = p
	arena_rect = rect
	alive = true
	_pulse = randf() * TAU
	match kind:
		Kind.CHASER:
			max_hp = 2 + int(wave / 4)
			speed = 130.0 + wave * 4.0
			points = 100
			body.color = Color(0.95, 0.25, 0.3)
			ring.color = Color(1.0, 0.4, 0.45, 0.25)
			_set_poly(12)
		Kind.SHOOTER:
			max_hp = 2 + int(wave / 5)
			speed = 95.0 + wave * 2.5
			points = 150
			body.color = Color(0.65, 0.35, 1.0)
			ring.color = Color(0.75, 0.45, 1.0, 0.25)
			_set_poly(5)
			_shoot_cd = randf_range(0.6, 1.2)
		Kind.BRUISER:
			max_hp = 5 + int(wave / 3)
			speed = 70.0 + wave * 1.5
			points = 250
			body.color = Color(1.0, 0.75, 0.2)
			ring.color = Color(1.0, 0.85, 0.3, 0.22)
			_set_poly(6, 20.0)
	hp = max_hp
	add_to_group("enemies")

func _set_poly(sides: int, radius: float = 14.0) -> void:
	var pts := PackedVector2Array()
	var rpts := PackedVector2Array()
	for i in sides:
		var a := -PI * 0.5 + TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
		rpts.append(Vector2(cos(a), sin(a)) * (radius + 6.0))
	body.polygon = pts
	ring.polygon = rpts

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_flash = maxf(0.0, _flash - delta)
	_pulse += delta * 6.0
	if _flash > 0.0:
		modulate = Color(2.0, 2.0, 2.0)
	else:
		modulate = Color.WHITE
		ring.scale = Vector2.ONE * (1.0 + 0.06 * sin(_pulse))

	if not is_instance_valid(player) or player.get("alive") == false:
		velocity = _knock
		_knock = _knock.move_toward(Vector2.ZERO, 1200.0 * delta)
		move_and_slide()
		return

	var to_p: Vector2 = player.global_position - global_position
	var dist := to_p.length()
	var dir := to_p.normalized() if dist > 1.0 else Vector2.ZERO

	match kind:
		Kind.CHASER:
			velocity = dir * speed + _knock
		Kind.SHOOTER:
			var desired := dir
			if dist < 180.0:
				desired = -dir
			elif dist > 280.0:
				desired = dir
			else:
				desired = Vector2(-dir.y, dir.x) # strafe
			velocity = desired * speed + _knock
			_shoot_cd -= delta
			if _shoot_cd <= 0.0 and dist < 420.0:
				_shoot_cd = randf_range(1.0, 1.6)
				_fire_at(dir)
		Kind.BRUISER:
			velocity = dir * speed + _knock

	_knock = _knock.move_toward(Vector2.ZERO, 1100.0 * delta)
	move_and_slide()
	_clamp()

	# contact damage
	if dist < 26.0 + (8.0 if kind == Kind.BRUISER else 0.0):
		if player.has_method("take_damage"):
			player.take_damage(1 if kind != Kind.BRUISER else 2, global_position)
			_knock = -dir * 160.0

func _clamp() -> void:
	if arena_rect.size == Vector2.ZERO:
		return
	global_position.x = clampf(global_position.x, arena_rect.position.x + 16.0, arena_rect.end.x - 16.0)
	global_position.y = clampf(global_position.y, arena_rect.position.y + 16.0, arena_rect.end.y - 16.0)

func _fire_at(dir: Vector2) -> void:
	var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
	var b = bullet_scene.instantiate()
	b.setup(global_position + dir * 18.0, dir, false, 1, 280.0)
	get_parent().add_child(b)

func take_hit(damage: int, from_pos: Vector2, knock_force: float = 220.0) -> void:
	if not alive:
		return
	hp -= damage
	_flash = 0.07
	var away := (global_position - from_pos).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	_knock = away * knock_force * (0.45 if kind == Kind.BRUISER else 1.0)
	Sfx.play("hit", randf_range(0.85, 1.15), -6.0)
	if hp <= 0:
		_die()

func _die() -> void:
	alive = false
	Sfx.play("die", randf_range(0.9, 1.2), -3.0)
	killed.emit(self, points)
	queue_free()
