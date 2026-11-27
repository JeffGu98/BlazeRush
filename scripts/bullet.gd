extends Area2D
class_name Bullet

var dir: Vector2 = Vector2.UP
var speed: float = 540.0
var damage: int = 1
var from_player: bool = true
var life: float = 1.5
var pierce_left: int = 0
var ricochet_left: int = 0
var is_crit: bool = false
var arena_rect: Rect2 = Rect2()

var _spent: bool = false
var _hit_ids: Dictionary = {}
var _core_color: Color = Color(1.0, 0.88, 0.42)
var _glow_color: Color = Color(1.0, 0.55, 0.18, 0.45)

@onready var poly: Polygon2D = $Poly


func setup(
	pos: Vector2,
	d: Vector2,
	player_shot: bool,
	dmg: int,
	spd: float,
	pierce: int = 0,
	ricochet: int = 0,
	crit: bool = false,
	rect: Rect2 = Rect2()
) -> void:
	global_position = pos
	dir = d.normalized() if d.length_squared() > 0.0001 else Vector2.UP
	from_player = player_shot
	damage = dmg
	speed = spd
	pierce_left = pierce
	ricochet_left = ricochet
	is_crit = crit
	arena_rect = rect
	rotation = dir.angle()
	if from_player:
		collision_layer = 8
		collision_mask = 4
		if is_crit:
			_core_color = Color(1.0, 0.96, 0.55)
			_glow_color = Color(1.0, 0.72, 0.12, 0.65)
			scale = Vector2(1.28, 1.28)
		elif pierce_left > 0:
			_core_color = Color(0.55, 0.96, 1.0)
			_glow_color = Color(0.22, 0.78, 1.0, 0.52)
		elif ricochet_left > 0:
			_core_color = Color(0.75, 0.88, 1.0)
			_glow_color = Color(0.45, 0.68, 1.0, 0.52)
		else:
			_core_color = Color(1.0, 0.88, 0.42)
			_glow_color = Color(1.0, 0.52, 0.16, 0.48)
	else:
		collision_layer = 16
		collision_mask = 2
		_core_color = Color(1.0, 0.42, 0.78)
		_glow_color = Color(1.0, 0.18, 0.55, 0.5)
		scale = Vector2(1.12, 1.12)
	if poly != null:
		poly.visible = false
	queue_redraw()


func _ready() -> void:
	if poly != null:
		poly.visible = false
	body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	global_position += dir * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if arena_rect.size != Vector2.ZERO and not arena_rect.grow(14.0).has_point(global_position):
		queue_free()


func _draw() -> void:
	if from_player:
		var tail_len := 22.0 if is_crit else 16.0
		draw_line(Vector2(-tail_len, 0), Vector2(6, 0), _glow_color, 7.5 if is_crit else 5.5, true)
		draw_line(Vector2(-tail_len * 0.65, 0), Vector2(9, 0), _core_color, 3.2 if is_crit else 2.6, true)
		draw_circle(Vector2(7, 0), 3.4 if is_crit else 2.6, Color(1, 1, 1, 0.92))
	else:
		draw_circle(Vector2.ZERO, 8.5, _glow_color)
		draw_circle(Vector2.ZERO, 4.8, _core_color)
		draw_circle(Vector2.ZERO, 2.2, Color(1, 0.92, 0.96, 0.95))


func _on_body(body: Node) -> void:
	if _spent:
		return
	if from_player and body.is_in_group("enemies"):
		var bid := body.get_instance_id()
		if _hit_ids.has(bid):
			return
		_hit_ids[bid] = true
		if body.has_method("take_hit"):
			body.take_hit(damage, global_position, 260.0 if is_crit else 210.0, is_crit)
		if pierce_left > 0:
			pierce_left -= 1
			return
		if ricochet_left > 0:
			var next_target := _find_ricochet_target(body)
			if next_target != null:
				ricochet_left -= 1
				var new_dir := (next_target.global_position - global_position).normalized()
				if new_dir.length_squared() > 0.01:
					get_tree().call_group("game", "spawn_ricochet_arc", global_position, next_target.global_position)
					dir = new_dir
					rotation = dir.angle()
					life = maxf(life, 0.75)
					return
		_spent = true
		queue_free()
	elif not from_player and body.is_in_group("player"):
		_spent = true
		if body.has_method("take_damage"):
			body.take_damage(damage, global_position)
		queue_free()


func _find_ricochet_target(exclude: Node) -> Node2D:
	var best: Node2D = null
	var best_d2 := 290.0 * 290.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == exclude or not is_instance_valid(e) or e.get("alive") == false:
			continue
		if _hit_ids.has(e.get_instance_id()):
			continue
		var d2: float = global_position.distance_squared_to(e.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = e
	return best
