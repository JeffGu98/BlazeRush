extends Node2D

enum State { TITLE, PLAYING, WAVE_CLEAR, PAUSED, GAMEOVER }

const WAVE_BREAK := 1.35

var state: State = State.TITLE
var score: int = 0
var combo: int = 0
var combo_timer: float = 0.0
var wave: int = 0
var _wave_timer: float = 0.0
var _spawn_queue: Array = []
var _spawn_cd: float = 0.0
var _shake: float = 0.0
var _shake_pos: Vector2 = Vector2.ZERO
var _hitstop: float = 0.0
var _nova_fx: float = 0.0
var _nova_center: Vector2 = Vector2.ZERO
var arena: Rect2
var _move: Vector2 = Vector2.ZERO
var _fire: bool = false
var _special: bool = false
var _state_before_pause: State = State.PLAYING

@onready var world: Node2D = $World
@onready var camera: Camera2D = $Camera
@onready var player: Player = $World/Player
@onready var arena_poly: Polygon2D = $World/Arena
@onready var arena_border: Line2D = $World/ArenaBorder
@onready var pad: VirtualPad = $UI/VirtualPad
@onready var hud: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HUD/HpBar
@onready var special_bar: ProgressBar = $UI/HUD/SpecialBar
@onready var score_label: Label = $UI/HUD/ScoreLabel
@onready var wave_label: Label = $UI/HUD/WaveLabel
@onready var combo_label: Label = $UI/HUD/ComboLabel
@onready var title_panel: Control = $UI/Title
@onready var over_panel: Control = $UI/GameOver
@onready var pause_panel: Control = $UI/Pause
@onready var banner: Label = $UI/Banner
@onready var flash: ColorRect = $UI/Flash
@onready var over_score: Label = $UI/GameOver/ScoreText
@onready var title_best: Label = $UI/Title/BestLabel
@onready var btn_start: Button = $UI/Title/StartBtn
@onready var btn_retry: Button = $UI/GameOver/RetryBtn
@onready var btn_pause: Button = $UI/HUD/PauseBtn
@onready var btn_resume: Button = $UI/Pause/ResumeBtn
@onready var btn_quit: Button = $UI/Pause/QuitBtn
@onready var particles: Node2D = $World/Particles

func _ready() -> void:
	add_to_group("game")
	_layout_arena()
	player.arena_rect = arena
	player.reset_state(arena.get_center())
	player.died.connect(_on_player_died)
	player.hurt.connect(_on_player_hurt)
	player.special_changed.connect(_on_special_changed)
	pad.controls_changed.connect(_on_controls)
	btn_start.pressed.connect(_start_game)
	btn_retry.pressed.connect(_start_game)
	btn_pause.pressed.connect(_toggle_pause)
	btn_resume.pressed.connect(_toggle_pause)
	btn_quit.pressed.connect(_to_title)
	flash.modulate.a = 0.0
	banner.visible = false
	_show_title()
	# Import note: ensure process
	set_process(true)

func _layout_arena() -> void:
	# Playfield above controls
	var top := 110.0
	var bottom := 980.0
	var left := 36.0
	var right := 684.0
	arena = Rect2(left, top, right - left, bottom - top)
	var pts := PackedVector2Array([
		arena.position,
		Vector2(arena.end.x, arena.position.y),
		arena.end,
		Vector2(arena.position.x, arena.end.y),
	])
	arena_poly.polygon = pts
	arena_poly.color = Color(0.09, 0.08, 0.14, 1)
	arena_border.points = PackedVector2Array(pts + PackedVector2Array([pts[0]]))
	arena_border.width = 4.0
	arena_border.default_color = Color(0.95, 0.45, 0.2, 0.85)
	# grid dots via draw? skip — add subtle inner
	camera.position = Vector2(360, 640)

func _show_title() -> void:
	state = State.TITLE
	get_tree().paused = false
	title_panel.visible = true
	over_panel.visible = false
	pause_panel.visible = false
	btn_pause.visible = false
	pad.visible = false
	$UI/HUD.visible = false
	title_best.text = "最高分 %d · 最高波次 %d" % [SaveData.best_score, SaveData.best_wave]
	_clear_enemies_and_bullets()
	player.reset_state(arena.get_center())
	player.visible = true

func _to_title() -> void:
	Sfx.play("click")
	get_tree().paused = false
	_show_title()

func _start_game() -> void:
	Sfx.play("click")
	get_tree().paused = false
	title_panel.visible = false
	over_panel.visible = false
	pause_panel.visible = false
	btn_pause.visible = true
	pad.visible = true
	$UI/HUD.visible = true
	score = 0
	combo = 0
	combo_timer = 0.0
	wave = 0
	_shake = 0.0
	_hitstop = 0.0
	_clear_enemies_and_bullets()
	player.reset_state(arena.get_center())
	_update_hud()
	state = State.PLAYING
	_begin_wave()

func _clear_enemies_and_bullets() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	for c in world.get_children():
		if c is Bullet:
			c.queue_free()
	_spawn_queue.clear()

func _begin_wave() -> void:
	wave += 1
	_show_banner("第 %d 波" % wave)
	Sfx.play("wave", 1.0, -4.0)
	_spawn_queue = _build_wave(wave)
	_spawn_cd = 0.35
	state = State.PLAYING
	wave_label.text = "波次 %d" % wave

func _build_wave(w: int) -> Array:
	var q: Array = []
	var chasers := 3 + w
	var shooters := 1 + int((w - 1) / 2)
	var bruisers := 0 if w < 3 else 1 + int((w - 3) / 3)
	for i in chasers:
		q.append(Enemy.Kind.CHASER)
	for i in shooters:
		q.append(Enemy.Kind.SHOOTER)
	for i in bruisers:
		q.append(Enemy.Kind.BRUISER)
	q.shuffle()
	return q

func _process(delta: float) -> void:
	if state == State.PAUSED or state == State.TITLE:
		return
	if _hitstop > 0.0:
		_hitstop -= delta
		return
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.2)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 10.0
	else:
		camera.offset = Vector2.ZERO

	if _nova_fx > 0.0:
		_nova_fx = maxf(0.0, _nova_fx - delta)
		queue_redraw()

	flash.modulate.a = maxf(0.0, flash.modulate.a - delta * 3.5)

	if state == State.GAMEOVER:
		return

	combo_timer = maxf(0.0, combo_timer - delta)
	if combo_timer <= 0.0:
		combo = 0
		combo_label.visible = false

	if state == State.WAVE_CLEAR:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_begin_wave()
		return

	if state != State.PLAYING:
		return

	player.set_controls(_move, _fire, _special)
	_special = false

	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and not _spawn_queue.is_empty():
		_spawn_one(_spawn_queue.pop_front())
		_spawn_cd = maxf(0.22, 0.55 - wave * 0.02)

	if _spawn_queue.is_empty() and get_tree().get_nodes_in_group("enemies").is_empty():
		state = State.WAVE_CLEAR
		_wave_timer = WAVE_BREAK
		_show_banner("清场！")
		player.add_charge(0.15)

func _spawn_one(kind: int) -> void:
	var scene: PackedScene = preload("res://scenes/enemy.tscn")
	var e: Enemy = scene.instantiate()
	var edge := randi() % 4
	var pos := Vector2.ZERO
	match edge:
		0: pos = Vector2(randf_range(arena.position.x + 30, arena.end.x - 30), arena.position.y + 24)
		1: pos = Vector2(randf_range(arena.position.x + 30, arena.end.x - 30), arena.end.y - 24)
		2: pos = Vector2(arena.position.x + 24, randf_range(arena.position.y + 30, arena.end.y - 30))
		_: pos = Vector2(arena.end.x - 24, randf_range(arena.position.y + 30, arena.end.y - 30))
	world.add_child(e)
	e.setup(kind as Enemy.Kind, pos, player, arena, wave)
	e.killed.connect(_on_enemy_killed)

func _on_controls(move: Vector2, fire: bool, special: bool) -> void:
	_move = move
	_fire = fire
	if special:
		_special = true

func _on_enemy_killed(enemy: Enemy, points: int) -> void:
	combo += 1
	combo_timer = 2.2
	var mult := 1 + mini(combo / 5, 4)
	var gained := points * mult
	score += gained
	player.add_charge(0.12 + (0.04 if enemy.kind == Enemy.Kind.BRUISER else 0.0))
	_spawn_pop(enemy.global_position, enemy.body.color)
	_shake = minf(1.4, _shake + 0.35)
	_hitstop = 0.03
	Sfx.play("combo", 1.0 + mini(combo, 10) * 0.03, -8.0)
	combo_label.visible = combo >= 2
	combo_label.text = "连击 x%d" % combo
	_update_hud()

func _spawn_pop(pos: Vector2, col: Color) -> void:
	for i in 8:
		var p := Polygon2D.new()
		var a := TAU * i / 8.0 + randf() * 0.3
		var r := randf_range(3.0, 6.0)
		p.polygon = PackedVector2Array([
			Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)
		])
		p.color = col
		p.global_position = pos
		particles.add_child(p)
		var tw := create_tween()
		var dest := pos + Vector2(cos(a), sin(a)) * randf_range(28, 55)
		tw.tween_property(p, "global_position", dest, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.28)
		tw.tween_callback(p.queue_free)

func player_special_nova(center: Vector2) -> void:
	_nova_center = center
	_nova_fx = 0.45
	flash.color = Color(1.0, 0.7, 0.25, 1)
	flash.modulate.a = 0.55
	_shake = 1.6
	_hitstop = 0.07
	queue_redraw()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d: float = center.distance_to(e.global_position)
		if d < 210.0:
			e.take_hit(4, center, 360.0)
		elif d < 320.0:
			e.take_hit(2, center, 240.0)
	# clear enemy bullets
	for c in world.get_children():
		if c is Bullet and not c.from_player:
			c.queue_free()

func _draw() -> void:
	if _nova_fx > 0.0:
		var t := 1.0 - (_nova_fx / 0.45)
		var radius := lerpf(40.0, 340.0, t)
		var alpha := (1.0 - t) * 0.55
		draw_circle(_nova_center, radius, Color(1.0, 0.55, 0.15, alpha * 0.35))
		draw_arc(_nova_center, radius, 0, TAU, 64, Color(1.0, 0.85, 0.4, alpha), 6.0, true)

func _on_player_hurt(hp_left: int) -> void:
	_shake = 1.2
	flash.color = Color(1.0, 0.15, 0.2, 1)
	flash.modulate.a = 0.4
	combo = 0
	combo_label.visible = false
	hp_bar.value = hp_left
	_update_hud()

func _on_player_died() -> void:
	state = State.GAMEOVER
	Sfx.play("over")
	SaveData.save_run(score, wave)
	pad.visible = false
	btn_pause.visible = false
	over_panel.visible = true
	over_score.text = "得分 %d\n波次 %d\n最高分 %d" % [score, wave, SaveData.best_score]
	_shake = 1.5

func _on_special_changed(charge: float, ready: bool) -> void:
	special_bar.value = charge * 100.0
	pad.set_special_charge(charge, ready)
	if ready:
		special_bar.modulate = Color(1.3, 1.1, 0.6)
	else:
		special_bar.modulate = Color(1, 1, 1)

func _update_hud() -> void:
	score_label.text = "分数 %d" % score
	wave_label.text = "波次 %d" % wave
	hp_bar.max_value = Player.MAX_HP
	hp_bar.value = player.hp
	special_bar.max_value = 100
	special_bar.value = player.special_charge * 100.0

func _show_banner(text: String) -> void:
	banner.text = text
	banner.visible = true
	banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(banner, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): banner.visible = false)

func _toggle_pause() -> void:
	if state == State.PLAYING or state == State.WAVE_CLEAR:
		_state_before_pause = state
		state = State.PAUSED
		pause_panel.visible = true
		get_tree().paused = true
		Sfx.play("click")
	elif state == State.PAUSED:
		pause_panel.visible = false
		get_tree().paused = false
		state = _state_before_pause
		Sfx.play("click")
