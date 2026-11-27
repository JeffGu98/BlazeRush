extends Node2D
class_name Pickup

enum Kind { ENERGY, HEAL, OVERDRIVE }

signal collected(pickup: Pickup, kind: Kind)

var kind: Kind = Kind.ENERGY
var life: float = 9.0
var _age: float = 0.0
var _vel: Vector2 = Vector2.ZERO
var _collected: bool = false


func setup(p_kind: Kind, pos: Vector2) -> void:
	kind = p_kind
	global_position = pos
	life = 11.0 if kind != Kind.ENERGY else 8.5
	var ang := randf() * TAU
	_vel = Vector2(cos(ang), sin(ang)) * randf_range(50.0, 110.0)
	add_to_group("pickups")


func update_pickup(delta: float, player: Node2D, magnet_radius: float, arena: Rect2) -> void:
	if _collected:
		return
	_age += delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	global_position += _vel * delta
	_vel = _vel.move_toward(Vector2.ZERO, 240.0 * delta)
	if arena.size != Vector2.ZERO:
		global_position.x = clampf(global_position.x, arena.position.x + 18.0, arena.end.x - 18.0)
		global_position.y = clampf(global_position.y, arena.position.y + 18.0, arena.end.y - 18.0)

	if is_instance_valid(player) and player.get("alive") != false:
		var to_p: Vector2 = player.global_position - global_position
		var dist := to_p.length()
		if dist < 24.0:
			_collected = true
			collected.emit(self, kind)
			queue_free()
			return
		elif dist < magnet_radius:
			var pull := lerpf(420.0, 150.0, dist / maxf(magnet_radius, 1.0))
			global_position += to_p.normalized() * pull * delta
	queue_redraw()


func _draw() -> void:
	if life < 2.2 and int(_age * 14.0) % 2 == 0:
		return
	var bob := sin(_age * 6.0) * 2.5
	var center := Vector2(0, bob)
	var pulse := 1.0 + 0.12 * sin(_age * 8.0)
	match kind:
		Kind.ENERGY:
			var col := Color(0.35, 0.88, 1.0)
			draw_circle(center, 11.0 * pulse, Color(col.r, col.g, col.b, 0.22))
			var pts := PackedVector2Array([
				center + Vector2(0, -8) * pulse,
				center + Vector2(7, 0) * pulse,
				center + Vector2(0, 8) * pulse,
				center + Vector2(-7, 0) * pulse,
			])
			draw_colored_polygon(pts, col)
		Kind.HEAL:
			var col := Color(0.28, 0.96, 0.56)
			draw_circle(center, 14.0 * pulse, Color(col.r, col.g, col.b, 0.24))
			draw_rect(Rect2(center + Vector2(-3.0, -8.5), Vector2(6.0, 17.0)), col)
			draw_rect(Rect2(center + Vector2(-8.5, -3.0), Vector2(17.0, 6.0)), col)
		Kind.OVERDRIVE:
			var col := Color(1.0, 0.74, 0.2)
			draw_circle(center, 16.0 * pulse, Color(col.r, col.g, col.b, 0.28))
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + TAU * float(i) / 10.0 + _age * 2.0
				var r := (11.0 if i % 2 == 0 else 5.2) * pulse
				pts.append(center + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, col)
