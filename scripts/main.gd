extends Node2D

enum State { TITLE, PLAYING, WAVE_CLEAR, PAUSED, GAMEOVER }

const WAVE_BREAK := 1.35
const RELEASES_API := "https://api.github.com/repos/JeffGu98/BlazeRush/releases/latest"
const RELEASES_PAGE := "https://github.com/JeffGu98/BlazeRush/releases/latest"
const SEEN_PATH := "user://update_seen.cfg"

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
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _hitstop_token: int = 0
var _nova_fx: float = 0.0
var _nova_center: Vector2 = Vector2.ZERO
var arena: Rect2
var _move: Vector2 = Vector2.ZERO
var _fire: bool = false
var _special: bool = false
var _state_before_pause: State = State.PLAYING
var _release_url := RELEASES_PAGE
var _update_bar: Control
var _hint_base_top := 0.0
var _hint_base_bottom := 0.0

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
	_check_for_update()
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
	_build_grid()
	camera.position = Vector2(360, 640)

func _build_grid() -> void:
	var old := world.get_node_or_null("Grid")
	if old:
		old.queue_free()
	var grid := Node2D.new()
	grid.name = "Grid"
	world.add_child(grid)
	world.move_child(grid, arena_poly.get_index() + 1)
	var col := Color(1.0, 0.55, 0.25, 0.06)
	var step := 54.0
	var x := arena.position.x
	while x <= arena.end.x + 0.5:
		var ln := Line2D.new()
		ln.width = 1.0
		ln.default_color = col
		ln.antialiased = true
		ln.points = PackedVector2Array([
			Vector2(x, arena.position.y), Vector2(x, arena.end.y)
		])
		grid.add_child(ln)
		x += step
	var y := arena.position.y
	while y <= arena.end.y + 0.5:
		var ln2 := Line2D.new()
		ln2.width = 1.0
		ln2.default_color = col
		ln2.antialiased = true
		ln2.points = PackedVector2Array([
			Vector2(arena.position.x, y), Vector2(arena.end.x, y)
		])
		grid.add_child(ln2)
		y += step

func _show_title() -> void:
	state = State.TITLE
	_clear_hitstop()
	_trauma = 0.0
	camera.offset = Vector2.ZERO
	get_tree().paused = false
	Bgm.to_title()
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
	_trauma = 0.0
	_clear_hitstop()
	_clear_enemies_and_bullets()
	player.reset_state(arena.get_center())
	_update_hud()
	state = State.PLAYING
	Bgm.to_play()
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

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func request_hitstop(real_sec: float) -> void:
	if real_sec <= 0.0:
		return
	if state == State.PAUSED or state == State.TITLE or state == State.GAMEOVER:
		return
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = 0.1
	await get_tree().create_timer(real_sec, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0

func _clear_hitstop() -> void:
	_hitstop_token += 1
	Engine.time_scale = 1.0

func _process(delta: float) -> void:
	if state == State.PAUSED or state == State.TITLE:
		return
	var real_delta := delta
	if Engine.time_scale > 0.0001:
		real_delta = delta / Engine.time_scale
	_shake_time += real_delta * 42.0
	# Keep legacy _shake additions in sync with trauma, then decay.
	if _shake > _trauma:
		_trauma = clampf(_shake, 0.0, 1.0)
	_shake = maxf(0.0, _shake - real_delta * 2.2)
	_trauma = maxf(0.0, _trauma - real_delta * 1.9)
	if _trauma > 0.01:
		var mag := _trauma * _trauma * 14.0
		camera.offset = Vector2(sin(_shake_time * 1.7), cos(_shake_time * 1.93)) * mag
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
	var heavy := enemy.kind == Enemy.Kind.BRUISER
	add_trauma(0.42 if heavy else 0.32)
	_shake = minf(1.4, _shake + (0.5 if heavy else 0.35))
	request_hitstop(0.06 if heavy or combo >= 5 else 0.045)
	Haptics.kill(heavy)
	Sfx.play("combo", 1.0 + mini(combo, 10) * 0.03, -8.0)
	combo_label.visible = combo >= 2
	combo_label.text = "连击 x%d" % combo
	_update_hud()

func _spawn_pop(pos: Vector2, col: Color) -> void:
	_spawn_ring(pos, col, 16.0, 52.0, 0.22)
	for i in 12:
		var p := Polygon2D.new()
		var a := TAU * i / 12.0 + randf() * 0.25
		var r := randf_range(2.5, 6.5)
		p.polygon = PackedVector2Array([
			Vector2(-r, -r * 0.4), Vector2(r, -r * 0.4), Vector2(r, r * 0.4), Vector2(-r, r * 0.4)
		])
		p.rotation = a
		p.color = col.lightened(0.15)
		p.global_position = pos
		particles.add_child(p)
		var tw := create_tween()
		var dest := pos + Vector2(cos(a), sin(a)) * randf_range(30, 64)
		tw.tween_property(p, "global_position", dest, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.3)
		tw.tween_callback(p.queue_free)

func _spawn_sparks(pos: Vector2, col: Color, dir: Vector2, count: int = 6) -> void:
	var base := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	for i in count:
		var p := Polygon2D.new()
		var spread := base.rotated(randf_range(-0.7, 0.7))
		var r := randf_range(2.0, 4.5)
		p.polygon = PackedVector2Array([
			Vector2(-r, -1.2), Vector2(r, -1.2), Vector2(r, 1.2), Vector2(-r, 1.2)
		])
		p.rotation = spread.angle()
		p.color = col
		p.global_position = pos
		particles.add_child(p)
		var tw := create_tween()
		var dest := pos + spread * randf_range(18, 40)
		tw.tween_property(p, "global_position", dest, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.18)
		tw.tween_callback(p.queue_free)

func _spawn_ring(pos: Vector2, col: Color, start_r: float, end_r: float, dur: float) -> void:
	var ring := Line2D.new()
	ring.width = 3.5
	ring.default_color = Color(col.r, col.g, col.b, 0.85)
	ring.antialiased = true
	ring.closed = true
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(pos + Vector2(cos(a), sin(a)) * start_r)
	ring.points = pts
	particles.add_child(ring)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void: _scale_ring(ring, pos, start_r, end_r, t), 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, dur)
	tw.tween_callback(ring.queue_free)

func _scale_ring(ring: Line2D, pos: Vector2, start_r: float, end_r: float, t: float) -> void:
	if not is_instance_valid(ring):
		return
	var radius := lerpf(start_r, end_r, t)
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(pos + Vector2(cos(a), sin(a)) * radius)
	ring.points = pts

func enemy_impact(pos: Vector2, dir: Vector2, died: bool, _heavy: bool) -> void:
	if died:
		return
	add_trauma(0.14)
	_spawn_sparks(pos, Color(1.0, 0.82, 0.35), dir, 5)
	Haptics.hit()

func player_special_nova(center: Vector2) -> void:
	_nova_center = center
	_nova_fx = 0.45
	flash.color = Color(1.0, 0.7, 0.25, 1)
	flash.modulate.a = 0.55
	add_trauma(0.85)
	_shake = 1.6
	request_hitstop(0.085)
	Haptics.nova()
	_spawn_ring(center, Color(1.0, 0.7, 0.25), 24.0, 210.0, 0.28)
	_spawn_sparks(center, Color(1.0, 0.7, 0.3), Vector2.UP, 10)
	_spawn_sparks(center, Color(1.0, 0.55, 0.15), Vector2.RIGHT, 8)
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
		draw_circle(_nova_center, radius * 0.45, Color(1.0, 0.85, 0.45, alpha * 0.2))
		draw_arc(_nova_center, radius, 0, TAU, 64, Color(1.0, 0.85, 0.4, alpha), 6.0, true)
		draw_arc(_nova_center, radius * 0.62, 0, TAU, 48, Color(1.0, 0.65, 0.2, alpha * 0.7), 3.0, true)

func _on_player_hurt(hp_left: int) -> void:
	_shake = 1.2
	add_trauma(0.55)
	flash.color = Color(1.0, 0.15, 0.2, 1)
	flash.modulate.a = 0.4
	combo = 0
	combo_label.visible = false
	hp_bar.value = hp_left
	_update_hud()

func _on_player_died() -> void:
	state = State.GAMEOVER
	_clear_hitstop()
	Sfx.play("over")
	Bgm.to_gameover()
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
		_clear_hitstop()
		pause_panel.visible = true
		get_tree().paused = true
		Sfx.play("click")
	elif state == State.PAUSED:
		pause_panel.visible = false
		get_tree().paused = false
		state = _state_before_pause
		Sfx.play("click")

func _check_for_update() -> void:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	http.use_threads = true
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	http.request_completed.connect(_on_update_response.bind(http))
	var headers := PackedStringArray([
		"User-Agent: BlazeRush",
		"Accept: application/vnd.github+json",
	])
	var err := http.request(RELEASES_API, headers)
	if err != OK:
		http.queue_free()


func _on_update_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	var tag := str(data.get("tag_name", "")).strip_edges()
	if tag.is_empty() or not _is_newer(tag, str(ProjectSettings.get_setting("application/config/version", "0"))):
		return
	if _was_dismissed(tag):
		return
	var url := str(data.get("html_url", "")).strip_edges()
	if not url.is_empty():
		_release_url = url
	_show_update_banner(tag)


func _is_newer(remote: String, local: String) -> bool:
	var a := _semver(remote)
	var b := _semver(local)
	for i in range(3):
		if a[i] > b[i]:
			return true
		if a[i] < b[i]:
			return false
	return false


func _semver(raw: String) -> PackedInt32Array:
	var text := raw.strip_edges()
	if text.begins_with("v") or text.begins_with("V"):
		text = text.substr(1)
	var parts := text.split(".")
	var out := PackedInt32Array()
	for i in range(3):
		out.append(parts[i].to_int() if i < parts.size() else 0)
	return out


func _was_dismissed(tag: String) -> bool:
	var config := ConfigFile.new()
	if config.load(SEEN_PATH) != OK:
		return false
	return str(config.get_value("update", "dismissed", "")) == tag


func _dismiss_update(tag: String) -> void:
	var config := ConfigFile.new()
	config.set_value("update", "dismissed", tag)
	config.save(SEEN_PATH)


func _show_update_banner(tag: String) -> void:
	if _update_bar != null and is_instance_valid(_update_bar):
		_update_bar.queue_free()
	var hint := title_panel.get_node_or_null("Hint") as Control
	if hint != null:
		if is_zero_approx(_hint_base_bottom) and is_zero_approx(_hint_base_top):
			_hint_base_top = hint.offset_top
			_hint_base_bottom = hint.offset_bottom
		hint.offset_top = _hint_base_top - 80.0
		hint.offset_bottom = _hint_base_bottom - 80.0

	var bar := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.07, 0.08, 0.96)
	style.set_corner_radius_all(12)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 0.45, 0.18, 0.55)
	bar.add_theme_stylebox_override("panel", style)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 28
	bar.offset_right = -28
	bar.offset_top = -84
	bar.offset_bottom = -20
	title_panel.add_child(bar)
	_update_bar = bar

	var open_btn := Button.new()
	open_btn.text = "有新版本 %s　·　点此查看" % tag
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_btn.offset_right = -56
	open_btn.add_theme_font_size_override("font_size", 18)
	open_btn.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35, 1))
	open_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_update_button(open_btn, Color(0.14, 0.07, 0.08, 0.0))
	open_btn.pressed.connect(_open_release)
	bar.add_child(open_btn)

	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	close.offset_left = -52
	close.offset_right = -8
	close.offset_top = -22
	close.offset_bottom = 22
	close.add_theme_font_size_override("font_size", 22)
	close.add_theme_color_override("font_color", Color(0.72, 0.62, 0.58, 1))
	_style_update_button(close, Color(0.14, 0.07, 0.08, 0.0))
	close.pressed.connect(_hide_update_banner.bind(bar, tag))
	bar.add_child(close)


func _hide_update_banner(bar: Control, tag: String) -> void:
	_dismiss_update(tag)
	if bar != null and is_instance_valid(bar):
		bar.queue_free()
	if _update_bar == bar:
		_update_bar = null
	var hint := title_panel.get_node_or_null("Hint") as Control
	if hint != null and not is_zero_approx(_hint_base_bottom):
		hint.offset_top = _hint_base_top
		hint.offset_bottom = _hint_base_bottom


func _open_release() -> void:
	OS.shell_open(_release_url)


func _style_update_button(btn: Button, bg: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(12)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.45, 0.18, 0.16)
	hover.set_corner_radius_all(12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1.0, 0.45, 0.18, 0.28)
	pressed.set_corner_radius_all(12)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
