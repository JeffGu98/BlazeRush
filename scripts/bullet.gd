extends Area2D
class_name Bullet

var dir: Vector2 = Vector2.UP
var speed: float = 500.0
var damage: int = 1
var from_player: bool = true
var life: float = 1.4
var _spent: bool = false

@onready var poly: Polygon2D = $Poly

func setup(pos: Vector2, d: Vector2, player_shot: bool, dmg: int, spd: float) -> void:
	global_position = pos
	dir = d.normalized()
	from_player = player_shot
	damage = dmg
	speed = spd
	rotation = dir.angle()
	if from_player:
		collision_layer = 8  # player_bullet
		collision_mask = 4   # enemy
		poly.color = Color(1.0, 0.85, 0.35)
	else:
		collision_layer = 16 # enemy_bullet
		collision_mask = 2   # player
		poly.color = Color(1.0, 0.35, 0.75)
		scale = Vector2(1.15, 1.15)

func _ready() -> void:
	poly.polygon = PackedVector2Array([
		Vector2(10, 0), Vector2(-6, 5), Vector2(-4, 0), Vector2(-6, -5)
	])
	body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
	if _spent:
		return
	global_position += dir * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_body(body: Node) -> void:
	if _spent:
		return
	if from_player and body.is_in_group("enemies"):
		_spent = true
		if body.has_method("take_hit"):
			body.take_hit(damage, global_position)
		queue_free()
	elif not from_player and body.is_in_group("player"):
		_spent = true
		if body.has_method("take_damage"):
			body.take_damage(damage, global_position)
		queue_free()
