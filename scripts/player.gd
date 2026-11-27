extends CharacterBody2D
class_name Player

signal died
signal hurt(hp_left: int, max_hp: int)
signal shield_blocked(shield_left: int)
signal special_changed(charge: float, ready: bool)
signal overdrive_changed(time_left: float)
signal fired

const MAX_HP := 5
const MOVE_SPEED := 325.0
const FIRE_COOLDOWN := 0.165
const SPECIAL_COST := 1.0
const INVULN_TIME := 0.85
const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")

var hp: int = MAX_HP
var max_hp: int = MAX_HP
var shield: int = 0
var facing: Vector2 = Vector2.UP
var move_input: Vector2 = Vector2.ZERO
var fire_held: bool = false
var special_pressed: bool = false
var special_charge: float = 0.0
var overdrive_timer: float = 0.0
var locked_target: Node2D = null
var alive: bool = true
var arena_rect: Rect2 = Rect2()
var upgrades: UpgradeSystem = null

var _fire_cd: float = 0.0
var _invuln: float = 0.0
var _flash: float = 0.0
var _knock: Vector2 = Vector2.ZERO
var _thruster_cd: float = 0.0
var _time: float = 0.0

@onready var body: Polygon2D = $Body
@onready var glow: Polygon2D = $Glow


func _ready() -> void:
	add_to_group("player")
	_build_shapes()


func _build_shapes() -> void:
	body.polygon = PackedVector2Array([
		Vector2(0, -20), Vector2(15, 14), Vector2(0, 7), Vector2(-15, 14)
	])
	body.color = Color(1.0, 0.56, 0.2)
	glow.polygon = PackedVector2Array([
		Vector2(0, -27), Vector2(22, 19), Vector2(0, 10), Vector2(-22, 19)
	])
	glow.color = Color(1.0, 0.42, 0.12, 0.30)


func reset_state(pos: Vector2, p_upgrades: UpgradeSystem = null) -> void:
	upgrades = p_upgrades
	global_position = pos
	max_hp = MAX_HP + (upgrades.max_hp_bonus() if upgrades else 0)
	hp = max_hp
	shield = upgrades.wave_shield_max() if upgrades else 0
	alive = true
	special_charge = 0.0
	overdrive_timer = 0.0
	locked_target = null
	_fire_cd = 0.0
	_invuln = 0.0
	_flash = 0.0
	_knock = Vector2.ZERO
	facing = Vector2.UP
	rotation = 0.0
	velocity = Vector2.ZERO
	modulate = Color.WHITE
	visible = true
	Sfx.reset_ready()
	special_changed.emit(special_charge, false)
	overdrive_changed.emit(0.0)
	queue_redraw()


func sync_upgrades(heal_amount: int = 0) -> void:
	var new_max := MAX_HP + (upgrades.max_hp_bonus() if upgrades else 0)
	max_hp = new_max
	if heal_amount > 0:
		hp = mini(hp + heal_amount, max_hp)
	refresh_wave_shield()


func refresh_wave_shield() -> void:
	if upgrades != null:
		shield = maxi(shield, upgrades.wave_shield_max())
		queue_redraw()


func heal(amount: int) -> bool:
	if not alive or hp >= max_hp:
		return false
	hp = mini(hp + amount, max_hp)
	hurt.emit(hp, max_hp)
	return true


func activate_overdrive(duration: float = 5.5) -> void:
	overdrive_timer = maxf(overdrive_timer, duration)
	overdrive_changed.emit(overdrive_timer)
	queue_redraw()


func set_controls(move: Vector2, fire: bool, special: bool) -> void:
	move_input = move
	fire_held = fire
	special_pressed = special


func add_charge(amount: float) -> void:
	var mult := upgrades.charge_mult() if upgrades else 1.0
	var was_ready := special_charge >= SPECIAL_COST
	special_charge = clampf(special_charge + amount * mult, 0.0, SPECIAL_COST)
	var now_ready := special_charge >= SPECIAL_COST
	if now_ready and not was_ready:
		Sfx.play_ready_once()
		Haptics.ready_special()
	special_changed.emit(special_charge, now_ready)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_time += delta
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_flash = maxf(0.0, _flash - delta)
	if overdrive_timer > 0.0:
		overdrive_timer = maxf(0.0, overdrive_timer - delta)
		overdrive_changed.emit(overdrive_timer)

	if _flash > 0.0:
		modulate = Color(1.7, 1.7, 1.7)
	elif _invuln > 0.0 and int(_invuln * 14.0) % 2 == 0:
		modulate = Color(1, 1, 1, 0.45)
	else:
		modulate = Color.WHITE

	var spd := upgrades.move_speed() if upgrades else MOVE_SPEED
	if overdrive_timer > 0.0:
		spd *= 1.12
	var wish := move_input
	if wish.length() > 1.0:
		wish = wish.normalized()
	if wish.length() > 0.12:
		facing = wish.normalized()
		rotation = facing.angle() + PI * 0.5
		_thruster_cd -= delta
		if _thruster_cd <= 0.0:
			_thruster_cd = 0.04
			var back_pos := global_position - facing * 16.0
			get_tree().call_group("game", "spawn_player_thruster", back_pos, -facing, overdrive_timer > 0.0)
	velocity = wish * spd + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 1450.0 * delta)
	move_and_slide()
	_clamp_to_arena()

	locked_target = _find_target()

	if fire_held and _fire_cd <= 0.0:
		_do_fire()
	if special_pressed and special_charge >= SPECIAL_COST:
		_do_special()
		special_pressed = false
	queue_redraw()


func _draw() -> void:
	# Cockpit neon core
	draw_circle(Vector2(0, -3), 4.2, Color(1.0, 0.94, 0.72, 0.95))
	# Flickering engine flame
	if move_input.length() > 0.12 or overdrive_timer > 0.0:
		var flick := 14.0 + 7.0 * sin(_time * 42.0)
		var col := Color(1.0, 0.9, 0.35, 0.88) if overdrive_timer > 0.0 else Color(1.0, 0.5, 0.16, 0.8)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-6, 11), Vector2(0, 11 + flick), Vector2(6, 11)
		]), col)
	# Overdrive aura
	if overdrive_timer > 0.0:
		var r := 25.0 + 2.5 * sin(_time * 16.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(1.0, 0.82, 0.25, 0.72), 2.5, true)
	# Shield ring
	if shield > 0:
		var sr := 28.0 + 1.5 * sin(_time * 7.0)
		draw_arc(Vector2.ZERO, sr, 0.0, TAU, 32, Color(0.32, 0.92, 1.0, 0.78), 2.4, true)
		if shield >= 2:
			draw_arc(Vector2.ZERO, sr + 4.5, 0.0, TAU, 32, Color(0.55, 0.96, 1.0, 0.45), 1.6, true)


func _clamp_to_arena() -> void:
	if arena_rect.size == Vector2.ZERO:
		return
	global_position.x = clampf(global_position.x, arena_rect.position.x + 20.0, arena_rect.end.x - 20.0)
	global_position.y = clampf(global_position.y, arena_rect.position.y + 20.0, arena_rect.end.y - 20.0)


func _find_target() -> Node2D:
	var nearest: Node2D = null
	var best := 460.0 * 460.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.get("alive") == false:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < best:
			best = d
			nearest = e
	return nearest


func _aim_dir() -> Vector2:
	if is_instance_valid(locked_target) and locked_target.get("alive") != false:
		return (locked_target.global_position - global_position).normalized()
	return facing


func _do_fire() -> void:
	var cd := upgrades.fire_cooldown() if upgrades else FIRE_COOLDOWN
	if overdrive_timer > 0.0:
		cd /= 1.55
	_fire_cd = cd
	var dir := _aim_dir()
	facing = dir
	rotation = facing.angle() + PI * 0.5
	_knock += -dir * 22.0
	_spawn_muzzle()
	fired.emit()
	Sfx.play("shoot", randf_range(1.02, 1.18) if overdrive_timer > 0.0 else randf_range(0.92, 1.08), -4.5)

	var count := (upgrades.projectile_count() if upgrades else 1) + (1 if overdrive_timer > 0.0 else 0)
	var base_dmg := upgrades.bullet_damage() if upgrades else 1
	var pierce := upgrades.pierce_count() if upgrades else 0
	var ricochet := upgrades.ricochet_count() if upgrades else 0
	var crit_rate := upgrades.crit_chance() if upgrades else 0.05
	var spread_step := 0.13 if count <= 3 else 0.11

	for i in count:
		var offset_idx := float(i) - float(count - 1) * 0.5
		var shot_dir := dir.rotated(offset_idx * spread_step)
		var is_crit := randf() < crit_rate
		var dmg := base_dmg * (2 if is_crit else 1)
		var b: Bullet = BULLET_SCENE.instantiate()
		b.setup(
			global_position + shot_dir * 22.0,
			shot_dir,
			true,
			dmg,
			620.0 if overdrive_timer > 0.0 else 580.0,
			pierce,
			ricochet,
			is_crit,
			arena_rect
		)
		get_parent().add_child(b)


func _spawn_muzzle() -> void:
	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([
		Vector2(-6, -18), Vector2(0, -38), Vector2(6, -18)
	])
	flash.color = Color(1.0, 0.96, 0.55, 1)
	flash.z_index = 2
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.065)
	tw.tween_callback(flash.queue_free)


func _do_special() -> void:
	special_charge = 0.0
	Sfx.reset_ready()
	special_changed.emit(0.0, false)
	Sfx.play("nova", 1.0, -1.0)
	get_tree().call_group("game", "player_special_nova", global_position)


func take_damage(amount: int, from_pos: Vector2) -> void:
	if not alive or _invuln > 0.0:
		return
	var away := (global_position - from_pos).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	if shield > 0:
		shield -= 1
		_invuln = 0.75
		_flash = 0.09
		_knock = away * 220.0
		Sfx.play("ready", 1.25, -2.0)
		Haptics.hit()
		shield_blocked.emit(shield)
		queue_redraw()
		return

	hp -= amount
	_invuln = INVULN_TIME
	_flash = 0.09
	_knock = away * 280.0
	Sfx.play("hurt", randf_range(0.9, 1.1))
	Haptics.hurt()
	hurt.emit(hp, max_hp)
	if hp <= 0:
		alive = false
		visible = false
		died.emit()
