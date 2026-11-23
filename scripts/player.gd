extends CharacterBody2D
class_name Player

signal died
signal hurt(hp_left: int)
signal special_changed(charge: float, ready: bool)
signal fired

const MAX_HP := 5
const MOVE_SPEED := 320.0
const FIRE_COOLDOWN := 0.16
const SPECIAL_COST := 1.0
const INVULN_TIME := 0.85

var hp: int = MAX_HP
var facing: Vector2 = Vector2.UP
var move_input: Vector2 = Vector2.ZERO
var fire_held: bool = false
var special_pressed: bool = false
var special_charge: float = 0.0
var _fire_cd: float = 0.0
var _invuln: float = 0.0
var _flash: float = 0.0
var _knock: Vector2 = Vector2.ZERO
var alive: bool = true
var arena_rect: Rect2 = Rect2()

@onready var body: Polygon2D = $Body
@onready var glow: Polygon2D = $Glow

func _ready() -> void:
	add_to_group("player")
	_build_shapes()

func _build_shapes() -> void:
	body.polygon = PackedVector2Array([
		Vector2(0, -18), Vector2(14, 14), Vector2(0, 8), Vector2(-14, 14)
	])
	body.color = Color(1.0, 0.55, 0.2)
	glow.polygon = PackedVector2Array([
		Vector2(0, -24), Vector2(20, 18), Vector2(0, 10), Vector2(-20, 18)
	])
	glow.color = Color(1.0, 0.4, 0.1, 0.28)

func reset_state(pos: Vector2) -> void:
	global_position = pos
	hp = MAX_HP
	alive = true
	special_charge = 0.0
	_fire_cd = 0.0
	_invuln = 0.0
	_flash = 0.0
	_knock = Vector2.ZERO
	facing = Vector2.UP
	velocity = Vector2.ZERO
	modulate = Color.WHITE
	visible = true
	Sfx.reset_ready()
	special_changed.emit(special_charge, false)

func set_controls(move: Vector2, fire: bool, special: bool) -> void:
	move_input = move
	fire_held = fire
	special_pressed = special

func add_charge(amount: float) -> void:
	var was_ready := special_charge >= SPECIAL_COST
	special_charge = clampf(special_charge + amount, 0.0, SPECIAL_COST)
	var now_ready := special_charge >= SPECIAL_COST
	if now_ready and not was_ready:
		Sfx.play_ready_once()
		Haptics.ready_special()
	special_changed.emit(special_charge, now_ready)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_flash = maxf(0.0, _flash - delta)
	if _flash > 0.0:
		modulate = Color(1.6, 1.6, 1.6)
	elif _invuln > 0.0 and int(_invuln * 14.0) % 2 == 0:
		modulate = Color(1, 1, 1, 0.45)
	else:
		modulate = Color.WHITE

	var wish := move_input
	if wish.length() > 1.0:
		wish = wish.normalized()
	if wish.length() > 0.12:
		facing = wish.normalized()
		rotation = facing.angle() + PI * 0.5
	velocity = wish * MOVE_SPEED + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 1400.0 * delta)
	move_and_slide()
	_clamp_to_arena()

	if fire_held and _fire_cd <= 0.0:
		_do_fire()
	if special_pressed and special_charge >= SPECIAL_COST:
		_do_special()
		special_pressed = false

func _clamp_to_arena() -> void:
	if arena_rect.size == Vector2.ZERO:
		return
	global_position.x = clampf(global_position.x, arena_rect.position.x + 20.0, arena_rect.end.x - 20.0)
	global_position.y = clampf(global_position.y, arena_rect.position.y + 20.0, arena_rect.end.y - 20.0)

func _aim_dir() -> Vector2:
	var nearest: Node2D = null
	var best := 1e12
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.get("alive") == false:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < best:
			best = d
			nearest = e
	if nearest and best < 420.0 * 420.0:
		return (nearest.global_position - global_position).normalized()
	return facing

func _do_fire() -> void:
	_fire_cd = FIRE_COOLDOWN
	var dir := _aim_dir()
	facing = dir
	rotation = facing.angle() + PI * 0.5
	_knock += -dir * 28.0
	_spawn_muzzle()
	fired.emit()
	Sfx.play("shoot", randf_range(0.92, 1.08), -4.0)
	var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
	var b = bullet_scene.instantiate()
	b.setup(global_position + dir * 22.0, dir, true, 1, 560.0)
	get_parent().add_child(b)

func _spawn_muzzle() -> void:
	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([
		Vector2(-5, -18), Vector2(0, -36), Vector2(5, -18)
	])
	flash.color = Color(1.0, 0.92, 0.5, 1)
	flash.z_index = 2
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.07)
	tw.tween_callback(flash.queue_free)

func _do_special() -> void:
	special_charge = 0.0
	Sfx.reset_ready()
	special_changed.emit(0.0, false)
	Sfx.play("nova", 1.0, -1.0)
	# Nova handled by main via signal-like call group
	get_tree().call_group("game", "player_special_nova", global_position)

func take_damage(amount: int, from_pos: Vector2) -> void:
	if not alive or _invuln > 0.0:
		return
	hp -= amount
	_invuln = INVULN_TIME
	_flash = 0.08
	var away := (global_position - from_pos).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	_knock = away * 280.0
	Sfx.play("hurt", randf_range(0.9, 1.1))
	Haptics.hurt()
	hurt.emit(hp)
	if hp <= 0:
		alive = false
		visible = false
		died.emit()
