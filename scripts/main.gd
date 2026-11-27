extends Node2D

enum State { TITLE, PLAYING, UPGRADE_CHOICE, WAVE_CLEAR, PAUSED, GAMEOVER }

const WAVE_BREAK := 0.90
const PAD_HEIGHT := 280.0
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

var state: State = State.TITLE
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var kills: int = 0
var _vampire_counter: int = 0
var combo_timer: float = 0.0
var wave: int = 0
var arena: Rect2

var upgrades := UpgradeSystem.new()
var vfx: VfxLayer
var update_checker: UpdateChecker

var _wave_timer: float = 0.0
var _spawn_queue: Array[int] = []
var _pending_portals: Array[Dictionary] = []
var _burn_zones: Array[Dictionary] = []
var _boss_hp_map: Dictionary = {}
var _spawn_cd: float = 0.0
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _border_pulse: float = 0.0
var _hitstop_token: int = 0
var _move: Vector2 = Vector2.ZERO
var _fire: bool = false
var _special: bool = false
var _state_before_pause: State = State.PLAYING
var _current_choices: Array[Dictionary] = []
var _rerolls_left: int = 0
var _in_chain_lightning: bool = false
var _banner_tween: Tween
var _safe_top: float = 0.0
var _safe_bottom: float = 0.0

# Dynamic HUD & Overlay controls
var _hp_text: Label
var _combo_bar: ProgressBar
var _overdrive_pill: Label
var _boss_box: Panel
var _boss_bar: ProgressBar
var _boss_label: Label
var _upgrade_panel: Control
var _upgrade_heading: Label
var _upgrade_subtitle: Label
var _upgrade_cards_box: VBoxContainer
var _upgrade_reroll_btn: Button
var _upgrade_build_label: Label
var _title_toggles: Array[Button] = []
var _pause_toggles: Array[Button] = []
var _ship_buttons: Array[Button] = []
var _ship_box: HBoxContainer
var _ship_trait_label: Label
var _pause_build_label: Label
var _over_badge: Label
var _over_build_label: Label
var _over_title_btn: Button

@onready var world: Node2D = $World
@onready var camera: Camera2D = $Camera
@onready var player: Player = $World/Player
@onready var arena_poly: Polygon2D = $World/Arena
@onready var arena_border: Line2D = $World/ArenaBorder
@onready var pad: VirtualPad = $UI/VirtualPad
@onready var hud: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HUD/HpBar
@onready var hp_tag: Label = $UI/HUD/HpTag
@onready var special_bar: ProgressBar = $UI/HUD/SpecialBar
@onready var sp_tag: Label = $UI/HUD/SpTag
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
	upgrades.reset(SaveData.selected_ship)

	vfx = VfxLayer.new()
	vfx.name = "VfxLayer"
	vfx.z_index = 2
	world.add_child(vfx)
	world.move_child(vfx, arena_poly.get_index() + 2)

	_build_version_label()
	_build_hud_extras()
	_build_upgrade_overlay()
	_polish_title_and_menus()
	_layout_for_viewport()
	get_viewport().size_changed.connect(_layout_for_viewport)

	player.arena_rect = arena
	player.auto_fire_enabled = SaveData.auto_fire
	pad.set_auto_fire(SaveData.auto_fire)
	player.reset_state(arena.get_center(), upgrades)
	player.died.connect(_on_player_died)
	player.hurt.connect(_on_player_hurt)
	player.shield_blocked.connect(_on_player_shield_blocked)
	player.special_changed.connect(_on_special_changed)
	player.overdrive_changed.connect(_on_overdrive_changed)
	pad.controls_changed.connect(_on_controls)
	pad.auto_fire_toggled.connect(_on_auto_fire_toggled)

	btn_start.pressed.connect(_start_game)
	btn_retry.pressed.connect(_start_game)
	btn_pause.pressed.connect(_toggle_pause)
	btn_resume.pressed.connect(_toggle_pause)
	btn_quit.pressed.connect(_to_title)

	_bind_system_back()

	flash.modulate.a = 0.0
	banner.visible = false
	_show_title()

	if DisplayServer.get_name() != "headless":
		update_checker = UpdateChecker.new()
		update_checker.name = "UpdateChecker"
		add_child(update_checker)
		update_checker.start(title_panel)
	set_process(true)


func _compute_safe_insets(vp: Vector2) -> void:
	_safe_top = 0.0
	_safe_bottom = 0.0
	if not OS.has_feature("mobile"):
		return
	var win_sz := Vector2(DisplayServer.window_get_size())
	if win_sz.y <= 1.0:
		return
	var safe := DisplayServer.get_display_safe_area()
	var scale_y := vp.y / win_sz.y
	_safe_top = clampf(float(safe.position.y) * scale_y, 0.0, 72.0)
	var bottom_px := maxf(0.0, win_sz.y - float(safe.end.y))
	_safe_bottom = clampf(bottom_px * scale_y, 0.0, 56.0)


func _layout_for_viewport() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 100.0 or vp.y < 100.0:
		vp = Vector2(720, 1280)
	_compute_safe_insets(vp)

	# Dynamic full-screen arena filling tall 20:9 phones seamlessly!
	var arena_w := minf(vp.x - 44.0, 760.0)
	var left := (vp.x - arena_w) * 0.5
	var top := _safe_top + 114.0
	var bottom := maxf(top + 420.0, vp.y - PAD_HEIGHT - _safe_bottom - 14.0)
	arena = Rect2(left, top, arena_w, bottom - top)

	var pts := PackedVector2Array([
		arena.position,
		Vector2(arena.end.x, arena.position.y),
		arena.end,
		Vector2(arena.position.x, arena.end.y),
	])
	arena_poly.polygon = pts
	arena_poly.color = Color(0.065, 0.06, 0.115, 1.0)
	arena_border.points = PackedVector2Array(pts + PackedVector2Array([pts[0]]))
	arena_border.width = 3.5
	arena_border.default_color = Color(1.0, 0.48, 0.2, 0.85)
	_build_grid()
	camera.position = vp * 0.5

	if vfx != null:
		vfx.setup(arena)
	if player != null:
		player.arena_rect = arena
		if state == State.TITLE:
			player.global_position = arena.get_center()
		else:
			player._clamp_to_arena()
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.arena_rect = arena

	# VirtualPad sits above bottom gesture bar
	pad.offset_top = -(PAD_HEIGHT + _safe_bottom)
	pad.offset_bottom = -_safe_bottom

	# Reposition HUD across viewport width & top safe area
	var st := _safe_top
	hp_tag.position = Vector2(28, st + 6)
	hp_bar.position = Vector2(24, st + 28)
	score_label.position = Vector2(24, st + 58)
	if _hp_text != null:
		_hp_text.position = Vector2(228, st + 25)

	sp_tag.position = Vector2(vp.x - 216, st + 6)
	special_bar.position = Vector2(vp.x - 220, st + 28)
	wave_label.position = Vector2(vp.x - 240, st + 58)
	wave_label.size = Vector2(216, 32)
	btn_pause.position = Vector2(vp.x - 100, st + 94)

	combo_label.position = Vector2(vp.x * 0.5 - 120, st + 58)
	combo_label.size = Vector2(240, 32)
	if _combo_bar != null:
		_combo_bar.position = Vector2(vp.x * 0.5 - 70, st + 90)
	if _overdrive_pill != null:
		_overdrive_pill.position = Vector2(vp.x * 0.5 - 120, top + 10)
	if _boss_box != null:
		var bw := minf(480.0, vp.x - 80.0)
		_boss_box.position = Vector2((vp.x - bw) * 0.5, top + 10)
		_boss_box.size = Vector2(bw, 48)
		_boss_label.size = Vector2(bw - 24, 20)
		_boss_bar.size = Vector2(bw - 28, 14)

	# Center Title / Pause / GameOver / UpgradeOverlay cleanly on any aspect ratio
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	_layout_title(vp, cx, cy, st)
	_layout_pause(vp, cx, cy)
	_layout_gameover(vp, cx, cy)
	_layout_upgrade_overlay(vp, cx, st)


func _layout_title(vp: Vector2, cx: float, cy: float, st: float) -> void:
	var t_lbl := title_panel.get_node_or_null("TitleLabel") as Control
	var sub := title_panel.get_node_or_null("Sub") as Control
	var hint := title_panel.get_node_or_null("Hint") as Control
	var ver := title_panel.get_node_or_null("VersionLabel") as Control
	var base_y := clampf(cy - 340.0, st + 115.0, 290.0)

	if ver != null:
		ver.offset_top = st + 22
		ver.offset_bottom = st + 54
	if not _title_toggles.is_empty():
		var row := _title_toggles[0].get_parent() as Control
		if row != null:
			row.position = Vector2(20, st + 20)
	if t_lbl != null:
		t_lbl.position = Vector2(cx - 300, base_y)
		t_lbl.size = Vector2(600, 96)
	if sub != null:
		sub.position = Vector2(cx - 300, base_y + 92)
		sub.size = Vector2(600, 74)
	title_best.position = Vector2(cx - 310, base_y + 178)
	title_best.size = Vector2(620, 36)

	if _ship_box != null:
		var sw := minf(648.0, vp.x - 40.0)
		_ship_box.position = Vector2(cx - sw * 0.5, base_y + 232)
		_ship_box.size = Vector2(sw, 118)
	if _ship_trait_label != null:
		_ship_trait_label.position = Vector2(cx - 300, base_y + 360)
		_ship_trait_label.size = Vector2(600, 32)

	btn_start.position = Vector2(cx - 155, base_y + 412)
	btn_start.size = Vector2(310, 82)
	if hint != null:
		hint.position = Vector2(cx - 300, vp.y - _safe_bottom - 132)
		hint.size = Vector2(600, 96)


func _layout_pause(_vp: Vector2, cx: float, cy: float) -> void:
	var t_lbl := pause_panel.get_node_or_null("TitleLabel") as Control
	if t_lbl != null:
		t_lbl.position = Vector2(cx - 280, cy - 220)
	btn_resume.position = Vector2(cx - 150, cy - 110)
	btn_quit.position = Vector2(cx - 150, cy - 16)
	if not _pause_toggles.is_empty():
		var row := _pause_toggles[0].get_parent() as Control
		if row != null:
			row.position = Vector2(cx - 224, cy + 84)
	if _pause_build_label != null:
		_pause_build_label.position = Vector2(cx - 300, cy + 148)


func _layout_gameover(_vp: Vector2, cx: float, cy: float) -> void:
	var t_lbl := over_panel.get_node_or_null("TitleLabel") as Control
	if _over_badge != null:
		_over_badge.position = Vector2(cx - 280, cy - 300)
	if t_lbl != null:
		t_lbl.position = Vector2(cx - 280, cy - 252)
	over_score.position = Vector2(cx - 300, cy - 162)
	over_score.size = Vector2(600, 148)
	btn_retry.position = Vector2(cx - 150, cy + 4)
	if _over_title_btn != null:
		_over_title_btn.position = Vector2(cx - 150, cy + 102)
	if _over_build_label != null:
		_over_build_label.position = Vector2(cx - 300, cy + 186)


func _layout_upgrade_overlay(vp: Vector2, cx: float, st: float) -> void:
	if _upgrade_panel == null:
		return
	var cw := minf(636.0, vp.x - 48.0)
	var top_y := st + 86.0
	if _upgrade_heading != null:
		_upgrade_heading.position = Vector2(cx - cw * 0.5, top_y)
		_upgrade_heading.size = Vector2(cw, 50)
	if _upgrade_subtitle != null:
		_upgrade_subtitle.position = Vector2(cx - cw * 0.5, top_y + 52)
		_upgrade_subtitle.size = Vector2(cw, 32)
	if _upgrade_cards_box != null:
		_upgrade_cards_box.position = Vector2(cx - cw * 0.5, top_y + 104)
		_upgrade_cards_box.size = Vector2(cw, 540)
	if _upgrade_reroll_btn != null:
		_upgrade_reroll_btn.position = Vector2(cx - 130, top_y + 662)
		_upgrade_reroll_btn.size = Vector2(260, 56)
	if _upgrade_build_label != null:
		_upgrade_build_label.position = Vector2(cx - cw * 0.5, top_y + 734)
		_upgrade_build_label.size = Vector2(cw, 110)


func _build_grid() -> void:
	var old := world.get_node_or_null("Grid")
	if old:
		old.queue_free()
	var grid := Node2D.new()
	grid.name = "Grid"
	world.add_child(grid)
	world.move_child(grid, arena_poly.get_index() + 1)
	var col := Color(1.0, 0.55, 0.28, 0.055)
	var step := 54.0
	var x := arena.position.x
	while x <= arena.end.x + 0.5:
		var ln := Line2D.new()
		ln.width = 1.0
		ln.default_color = col
		ln.antialiased = true
		ln.points = PackedVector2Array([Vector2(x, arena.position.y), Vector2(x, arena.end.y)])
		grid.add_child(ln)
		x += step
	var y := arena.position.y
	while y <= arena.end.y + 0.5:
		var ln2 := Line2D.new()
		ln2.width = 1.0
		ln2.default_color = col
		ln2.antialiased = true
		ln2.points = PackedVector2Array([Vector2(arena.position.x, y), Vector2(arena.end.x, y)])
		grid.add_child(ln2)
		y += step


func _build_version_label() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if version.is_empty():
		return
	var lbl := Label.new()
	lbl.name = "VersionLabel"
	lbl.text = version if version.begins_with("v") or version.begins_with("V") else "v%s" % version
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	lbl.offset_left = -160
	lbl.offset_top = 22
	lbl.offset_right = -20
	lbl.offset_bottom = 54
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.68, 0.70, 0.82, 0.88))
	title_panel.add_child(lbl)


func _build_hud_extras() -> void:
	var hud_root := $UI/HUD as Control
	_hp_text = Label.new()
	_hp_text.size = Vector2(150, 28)
	_hp_text.add_theme_font_size_override("font_size", 18)
	_hp_text.add_theme_color_override("font_color", Color(1.0, 0.88, 0.82))
	hud_root.add_child(_hp_text)

	_combo_bar = ProgressBar.new()
	_combo_bar.size = Vector2(140, 6)
	_combo_bar.max_value = 100.0
	_combo_bar.value = 0.0
	_combo_bar.show_percentage = false
	_combo_bar.visible = false
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(0.15, 0.12, 0.2, 0.8)
	cbg.set_corner_radius_all(3)
	var cfill := StyleBoxFlat.new()
	cfill.bg_color = Color(1.0, 0.8, 0.25, 0.95)
	cfill.set_corner_radius_all(3)
	_combo_bar.add_theme_stylebox_override("background", cbg)
	_combo_bar.add_theme_stylebox_override("fill", cfill)
	hud_root.add_child(_combo_bar)

	_overdrive_pill = Label.new()
	_overdrive_pill.size = Vector2(240, 30)
	_overdrive_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overdrive_pill.add_theme_font_size_override("font_size", 18)
	_overdrive_pill.add_theme_color_override("font_color", Color(1.0, 0.9, 0.32))
	_overdrive_pill.visible = false
	hud_root.add_child(_overdrive_pill)

	_boss_box = Panel.new()
	_boss_box.size = Vector2(480, 48)
	_boss_box.visible = false
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.12, 0.05, 0.09, 0.90)
	bstyle.set_corner_radius_all(10)
	bstyle.set_border_width_all(1)
	bstyle.border_color = Color(1.0, 0.35, 0.25, 0.72)
	_boss_box.add_theme_stylebox_override("panel", bstyle)
	hud_root.add_child(_boss_box)

	_boss_label = Label.new()
	_boss_label.position = Vector2(12, 3)
	_boss_label.size = Vector2(456, 20)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.add_theme_font_size_override("font_size", 15)
	_boss_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.45))
	_boss_label.text = "烈焰领主"
	_boss_box.add_child(_boss_label)

	_boss_bar = ProgressBar.new()
	_boss_bar.position = Vector2(14, 26)
	_boss_bar.size = Vector2(452, 14)
	_boss_bar.show_percentage = false
	var bb_bg := StyleBoxFlat.new()
	bb_bg.bg_color = Color(0.22, 0.08, 0.12, 0.9)
	bb_bg.set_corner_radius_all(5)
	var bb_fill := StyleBoxFlat.new()
	bb_fill.bg_color = Color(1.0, 0.34, 0.2, 1.0)
	bb_fill.set_corner_radius_all(5)
	_boss_bar.add_theme_stylebox_override("background", bb_bg)
	_boss_bar.add_theme_stylebox_override("fill", bb_fill)
	_boss_box.add_child(_boss_bar)


func _build_upgrade_overlay() -> void:
	_upgrade_panel = Control.new()
	_upgrade_panel.name = "UpgradeOverlay"
	_upgrade_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_upgrade_panel.visible = false
	_upgrade_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(_upgrade_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.025, 0.065, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_upgrade_panel.add_child(dim)

	_upgrade_heading = Label.new()
	_upgrade_heading.text = "波次净化 · 择一强化"
	_upgrade_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_heading.add_theme_font_size_override("font_size", 34)
	_upgrade_heading.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
	_upgrade_panel.add_child(_upgrade_heading)

	_upgrade_subtitle = Label.new()
	_upgrade_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_subtitle.add_theme_font_size_override("font_size", 18)
	_upgrade_subtitle.add_theme_color_override("font_color", Color(0.76, 0.80, 0.92))
	_upgrade_panel.add_child(_upgrade_subtitle)

	_upgrade_cards_box = VBoxContainer.new()
	_upgrade_cards_box.add_theme_constant_override("separation", 16)
	_upgrade_panel.add_child(_upgrade_cards_box)

	_upgrade_reroll_btn = Button.new()
	_upgrade_reroll_btn.name = "RerollBtn"
	_upgrade_reroll_btn.focus_mode = Control.FOCUS_NONE
	_upgrade_reroll_btn.add_theme_font_size_override("font_size", 20)
	_upgrade_reroll_btn.pressed.connect(_on_reroll_upgrades)
	_upgrade_panel.add_child(_upgrade_reroll_btn)

	_upgrade_build_label = Label.new()
	_upgrade_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_upgrade_build_label.add_theme_font_size_override("font_size", 16)
	_upgrade_build_label.add_theme_color_override("font_color", Color(0.74, 0.80, 0.94))
	_upgrade_panel.add_child(_upgrade_build_label)


func _polish_title_and_menus() -> void:
	var sub := title_panel.get_node_or_null("Sub") as Label
	if sub:
		sub.text = "极简三键 · 战机流派 · 领主激战\n清波叠连击，触发共鸣弹幕"

	_title_toggles = _create_setting_row(title_panel, Vector2(20, 20))
	_pause_toggles = _create_setting_row(pause_panel, Vector2(136, 740))

	# 3-ship selector cards right on the Title screen
	_ship_box = HBoxContainer.new()
	_ship_box.name = "ShipSelector"
	_ship_box.add_theme_constant_override("separation", 12)
	title_panel.add_child(_ship_box)

	_ship_buttons.clear()
	for spec in ShipCatalog.SHIPS:
		var sid := str(spec["id"])
		var b := Button.new()
		b.name = "ShipBtn_" + sid
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.text = "%s\n%s" % [str(spec["name"]), str(spec["role"])]
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_select_ship.bind(sid))
		_ship_box.add_child(b)
		_ship_buttons.append(b)

	_ship_trait_label = Label.new()
	_ship_trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ship_trait_label.add_theme_font_size_override("font_size", 17)
	_ship_trait_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	title_panel.add_child(_ship_trait_label)

	_pause_build_label = Label.new()
	_pause_build_label.size = Vector2(600, 140)
	_pause_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_build_label.add_theme_font_size_override("font_size", 18)
	_pause_build_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	pause_panel.add_child(_pause_build_label)

	_over_badge = Label.new()
	_over_badge.size = Vector2(560, 42)
	_over_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_badge.add_theme_font_size_override("font_size", 24)
	_over_badge.add_theme_color_override("font_color", Color(1.0, 0.86, 0.32))
	_over_badge.visible = false
	over_panel.add_child(_over_badge)

	_over_build_label = Label.new()
	_over_build_label.size = Vector2(600, 120)
	_over_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_build_label.add_theme_font_size_override("font_size", 17)
	_over_build_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
	over_panel.add_child(_over_build_label)

	_over_title_btn = Button.new()
	_over_title_btn.text = "回标题"
	_over_title_btn.focus_mode = Control.FOCUS_NONE
	_over_title_btn.size = Vector2(300, 64)
	_over_title_btn.add_theme_font_size_override("font_size", 24)
	_style_pill_button(_over_title_btn, Color(0.22, 0.20, 0.34, 0.95), Color(0.55, 0.58, 0.78, 0.45))
	_over_title_btn.pressed.connect(_to_title)
	over_panel.add_child(_over_title_btn)

	_refresh_ship_buttons()
	_refresh_setting_buttons()


func _select_ship(ship_id: String) -> void:
	SaveData.set_selected_ship(ship_id)
	upgrades.reset(ship_id)
	if player != null:
		player.apply_ship_visual(ship_id)
	Sfx.play("click", 1.08)
	_refresh_ship_buttons()


func _refresh_ship_buttons() -> void:
	var cur := SaveData.selected_ship
	var spec := ShipCatalog.get_ship(cur)
	if _ship_trait_label != null:
		_ship_trait_label.text = "%s：%s" % [str(spec["name"]), str(spec["trait"])]
		_ship_trait_label.add_theme_color_override("font_color", (spec["color"] as Color).lightened(0.2))
	for i in mini(_ship_buttons.size(), ShipCatalog.SHIPS.size()):
		var b: Button = _ship_buttons[i]
		var s: Dictionary = ShipCatalog.SHIPS[i]
		var selected := str(s["id"]) == cur
		var col: Color = s["color"]
		b.add_theme_color_override("font_color", col.lightened(0.25) if selected else Color(0.72, 0.74, 0.84))
		_style_pill_button(
			b,
			Color(col.r * 0.22, col.g * 0.20, col.b * 0.24, 0.94) if selected else Color(0.11, 0.10, 0.17, 0.86),
			col if selected else Color(0.38, 0.40, 0.52, 0.36)
		)


func _create_setting_row(parent: Control, pos: Vector2) -> Array[Button]:
	var row := HBoxContainer.new()
	row.position = pos
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var btns: Array[Button] = []
	var cbs := [_toggle_bgm, _toggle_sfx, _toggle_haptics, _toggle_auto_fire]
	for cb in cbs:
		var b := Button.new()
		b.custom_minimum_size = Vector2(106, 38)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(cb)
		row.add_child(b)
		btns.append(b)
	return btns


func _toggle_bgm() -> void:
	SaveData.set_bgm_muted(not SaveData.bgm_muted)
	Bgm.refresh_mute()
	Sfx.play("click")
	_refresh_setting_buttons()


func _toggle_sfx() -> void:
	SaveData.set_sfx_muted(not SaveData.sfx_muted)
	if not SaveData.sfx_muted:
		Sfx.play("click")
	_refresh_setting_buttons()


func _toggle_haptics() -> void:
	SaveData.set_haptics_enabled(not SaveData.haptics_enabled)
	Sfx.play("click")
	if SaveData.haptics_enabled:
		Haptics.pickup()
	_refresh_setting_buttons()


func _toggle_auto_fire() -> void:
	_on_auto_fire_toggled(not SaveData.auto_fire)


func _on_auto_fire_toggled(enabled: bool) -> void:
	SaveData.set_auto_fire(enabled)
	if player != null:
		player.auto_fire_enabled = enabled
	if pad != null:
		pad.set_auto_fire(enabled)
	Sfx.play("click", 1.15 if enabled else 0.92)
	_refresh_setting_buttons()


func _refresh_setting_buttons() -> void:
	var labels := [
		"音乐:关" if SaveData.bgm_muted else "音乐:开",
		"音效:关" if SaveData.sfx_muted else "音效:开",
		"震动:开" if SaveData.haptics_enabled else "震动:关",
		"自射:开" if SaveData.auto_fire else "自射:关",
	]
	var active := [not SaveData.bgm_muted, not SaveData.sfx_muted, SaveData.haptics_enabled, SaveData.auto_fire]
	for group in [_title_toggles, _pause_toggles]:
		for i in mini(group.size(), labels.size()):
			var b: Button = group[i]
			b.text = labels[i]
			var on: bool = active[i]
			b.add_theme_color_override("font_color", Color(1.0, 0.94, 0.85) if on else Color(0.55, 0.56, 0.65))
			_style_pill_button(
				b,
				Color(0.20, 0.16, 0.28, 0.92) if on else Color(0.11, 0.10, 0.16, 0.85),
				Color(1.0, 0.52, 0.22, 0.55) if on else Color(0.35, 0.35, 0.45, 0.35)
			)


func _style_pill_button(btn: Button, bg: Color, border: Color) -> void:
	for st in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = bg.lightened(0.08) if st == "hover" else (bg.darkened(0.12) if st == "pressed" else bg)
		box.set_corner_radius_all(12)
		box.set_border_width_all(1)
		box.border_color = border
		btn.add_theme_stylebox_override(st, box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


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
	_upgrade_panel.visible = false
	_boss_box.visible = false
	_overdrive_pill.visible = false
	btn_pause.visible = false
	pad.visible = false
	$UI/HUD.visible = false
	title_best.text = "最高分 %d  ·  最高波次 %d  ·  最高连击 x%d" % [SaveData.best_score, SaveData.best_wave, SaveData.best_combo]
	_clear_world_entities()
	upgrades.reset(SaveData.selected_ship)
	player.reset_state(arena.get_center(), upgrades)
	player.visible = true
	_refresh_ship_buttons()
	_refresh_setting_buttons()


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
	_upgrade_panel.visible = false
	_boss_box.visible = false
	_overdrive_pill.visible = false
	btn_pause.visible = true
	pad.visible = true
	$UI/HUD.visible = true

	upgrades.reset(SaveData.selected_ship)
	score = 0
	combo = 0
	max_combo = 0
	kills = 0
	_vampire_counter = 0
	combo_timer = 0.0
	wave = 0
	_trauma = 0.0
	_border_pulse = 0.0
	_clear_hitstop()
	_clear_world_entities()
	player.auto_fire_enabled = SaveData.auto_fire
	pad.set_auto_fire(SaveData.auto_fire)
	player.reset_state(arena.get_center(), upgrades)
	_update_hud()
	state = State.PLAYING
	Bgm.to_play()
	_begin_wave()


func _clear_world_entities() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	for p in get_tree().get_nodes_in_group("pickups"):
		p.queue_free()
	for c in world.get_children():
		if c is Bullet:
			c.queue_free()
	_spawn_queue.clear()
	_pending_portals.clear()
	_burn_zones.clear()
	_boss_hp_map.clear()
	if vfx != null:
		vfx.clear_combat()


func _begin_wave() -> void:
	wave += 1
	player.refresh_wave_shield()
	var is_boss := WaveDirector.is_boss_wave(wave)
	_show_banner(WaveDirector.boss_title(wave) if is_boss else "第 %d 波" % wave)
	Sfx.play("wave", 0.85 if is_boss else 1.0, -2.5 if is_boss else -4.0)
	if is_boss:
		Bgm.to_boss()
		add_trauma(0.45)
	else:
		Bgm.to_play()
	_spawn_queue = WaveDirector.build_queue(wave)
	_spawn_cd = 0.15
	_boss_hp_map.clear()
	_boss_box.visible = false
	state = State.PLAYING
	_update_hud()


func _open_upgrade_choice() -> void:
	state = State.UPGRADE_CHOICE
	_clear_hitstop()
	get_tree().paused = true
	_rerolls_left = 1
	var boss_cleared := WaveDirector.is_boss_wave(wave)
	_upgrade_subtitle.text = "领主击败奖励 · 保底史诗强化！" if boss_cleared else "已完成第 %d 波 · 为下一波武装火力" % wave
	_populate_upgrade_cards(upgrades.roll_choices(3, boss_cleared))
	_upgrade_panel.visible = true
	Sfx.play("ready", 1.05, -3.0)


func _populate_upgrade_cards(choices: Array[Dictionary]) -> void:
	_current_choices = choices
	for child in _upgrade_cards_box.get_children():
		child.queue_free()
	for item in _current_choices:
		_upgrade_cards_box.add_child(_make_upgrade_card(item))
	_refresh_reroll_and_build()


func _on_reroll_upgrades() -> void:
	if state != State.UPGRADE_CHOICE or _rerolls_left <= 0:
		return
	_rerolls_left -= 1
	Sfx.play("click", 1.2)
	Haptics.pickup()
	var prev_ids: Array[String] = []
	for item in _current_choices:
		prev_ids.append(str(item["id"]))
	var boss_cleared := WaveDirector.is_boss_wave(wave)
	_populate_upgrade_cards(upgrades.roll_choices(3, boss_cleared, prev_ids))


func _refresh_reroll_and_build() -> void:
	if _upgrade_reroll_btn != null:
		_upgrade_reroll_btn.disabled = _rerolls_left <= 0
		_upgrade_reroll_btn.text = "刷新强化 (%d/1)" % _rerolls_left
		_upgrade_reroll_btn.add_theme_color_override(
			"font_color",
			Color(1.0, 0.90, 0.55) if _rerolls_left > 0 else Color(0.5, 0.52, 0.60)
		)
		_style_pill_button(
			_upgrade_reroll_btn,
			Color(0.20, 0.16, 0.30, 0.94) if _rerolls_left > 0 else Color(0.10, 0.10, 0.15, 0.7),
			Color(1.0, 0.74, 0.28, 0.65) if _rerolls_left > 0 else Color(0.3, 0.32, 0.4, 0.3)
		)
	if _upgrade_build_label != null:
		var tags := upgrades.summary_tags()
		var ship_name := str(upgrades.ship.get("name", "烈焰先锋"))
		_upgrade_build_label.text = ("战机：%s  |  已选：%s" % [ship_name, " · ".join(tags)]) if not tags.is_empty() else ("战机：%s  |  尚无强化" % ship_name)


func _make_upgrade_card(item: Dictionary) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id := str(item["id"])
	var syns := upgrades.would_activate_synergies(id)
	btn.custom_minimum_size = Vector2(0, 166 if not syns.is_empty() else 148)
	var accent: Color = item["color"]
	var rarity := int(item["rarity"])
	var r_col := Color(1.0, 0.85, 0.28) if not syns.is_empty() else UpgradeSystem.rarity_color(rarity)

	for st in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		var base_bg := Color(0.14, 0.11, 0.20, 0.97) if not syns.is_empty() else Color(0.11, 0.095, 0.18, 0.96)
		box.bg_color = base_bg.lightened(0.08) if st == "hover" else (base_bg.darkened(0.08) if st == "pressed" else base_bg)
		box.set_corner_radius_all(18)
		box.set_border_width_all(2)
		box.border_color = r_col if st != "hover" else r_col.lightened(0.2)
		btn.add_theme_stylebox_override(st, box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var pad_box := MarginContainer.new()
	pad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad_box.add_theme_constant_override("margin_left", 22)
	pad_box.add_theme_constant_override("margin_right", 22)
	pad_box.add_theme_constant_override("margin_top", 16)
	pad_box.add_theme_constant_override("margin_bottom", 16)
	btn.add_child(pad_box)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	pad_box.add_child(col)

	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 10)
	col.add_child(top_row)

	var rarity_lbl := Label.new()
	rarity_lbl.text = "[%s]" % UpgradeSystem.rarity_label(rarity)
	rarity_lbl.add_theme_font_size_override("font_size", 18)
	rarity_lbl.add_theme_color_override("font_color", UpgradeSystem.rarity_color(rarity))
	rarity_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(rarity_lbl)

	var title_lbl := Label.new()
	title_lbl.text = str(item["name"])
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 25)
	title_lbl.add_theme_color_override("font_color", accent.lightened(0.15))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(title_lbl)

	var next_lv := int(item.get("next_level", 1))
	var max_lv := int(item.get("max_level", 1))
	var lv_lbl := Label.new()
	lv_lbl.text = "Lv.%d/%d" % [next_lv, max_lv] if max_lv < 50 else "补给"
	lv_lbl.add_theme_font_size_override("font_size", 17)
	lv_lbl.add_theme_color_override("font_color", Color(0.76, 0.80, 0.90))
	lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(lv_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(item["desc"])
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 18)
	desc_lbl.add_theme_color_override("font_color", Color(0.90, 0.92, 0.98))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_lbl)

	if not syns.is_empty():
		var syn_names: Array[String] = []
		for s in syns:
			syn_names.append("%s（%s）" % [str(s["name"]), str(s["desc"])])
		var syn_lbl := Label.new()
		syn_lbl.text = "⚡ 可激活共鸣：" + " / ".join(syn_names)
		syn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		syn_lbl.add_theme_font_size_override("font_size", 15)
		syn_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
		syn_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(syn_lbl)

	btn.pressed.connect(_select_upgrade.bind(id))
	return btn


func _select_upgrade(id: String) -> void:
	if state != State.UPGRADE_CHOICE:
		return
	Sfx.play("click", 1.12)
	Haptics.pickup()
	var new_syns: Array = []
	if id == "bonus_heal":
		player.heal(2)
		player.add_charge(0.5)
	else:
		var applied := upgrades.apply(id)
		new_syns = applied.get("new_synergies", [])
		var heal_now := 0
		if id == "vitality":
			heal_now = 2
		elif id == "shield":
			heal_now = 1
		player.sync_upgrades(heal_now)
	_upgrade_panel.visible = false
	get_tree().paused = false
	_update_hud()
	_begin_wave()
	if not new_syns.is_empty():
		var s: Dictionary = new_syns[0]
		_show_banner("⚡ 共鸣激活 · %s！" % str(s["name"]))
		Sfx.play("ready", 1.25, -1.0)
		if vfx != null:
			vfx.spawn_ring(player.global_position, s["color"], 18.0, 120.0, 0.45, 5.0)
			vfx.spawn_text(player.global_position, "⚡ " + str(s["name"]), s["color"], 24)


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func request_hitstop(real_sec: float) -> void:
	if real_sec <= 0.0:
		return
	if state != State.PLAYING and state != State.WAVE_CLEAR:
		return
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = 0.12
	await get_tree().create_timer(real_sec, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0


func _clear_hitstop() -> void:
	_hitstop_token += 1
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	if state == State.PAUSED or state == State.TITLE or state == State.UPGRADE_CHOICE:
		return
	var real_delta := delta
	if Engine.time_scale > 0.0001:
		real_delta = delta / Engine.time_scale
	_shake_time += real_delta * 44.0
	_trauma = maxf(0.0, _trauma - real_delta * 2.0)
	if _trauma > 0.01:
		var mag := _trauma * _trauma * 15.0
		camera.offset = Vector2(sin(_shake_time * 1.7), cos(_shake_time * 1.93)) * mag
	else:
		camera.offset = Vector2.ZERO

	_border_pulse = maxf(0.0, _border_pulse - delta * 2.6)
	var border_col := Color(1.0, 0.48, 0.2, 0.85)
	if player.overdrive_timer > 0.0:
		border_col = Color(1.0, 0.82, 0.25, 0.95)
	elif _boss_box.visible:
		border_col = Color(1.0, 0.28, 0.24, 0.92)
	arena_border.default_color = border_col.lightened(_border_pulse * 0.35)

	flash.modulate.a = maxf(0.0, flash.modulate.a - delta * 3.5)

	if vfx != null:
		vfx.lock_target = player.locked_target if (state == State.PLAYING and is_instance_valid(player.locked_target)) else null
		vfx.lock_color = Color(1.0, 0.9, 0.32, 0.95) if player.overdrive_timer > 0.0 else Color(1.0, 0.68, 0.25, 0.88)
		if state == State.PLAYING and player.alive and player.hp <= 2:
			vfx.low_hp_danger = 1.0 if player.hp == 1 else 0.52
		else:
			vfx.low_hp_danger = 0.0

	var mag_r := upgrades.pickup_radius()
	for p in get_tree().get_nodes_in_group("pickups"):
		if is_instance_valid(p):
			p.update_pickup(delta, player, mag_r, arena)

	_update_burn_zones(delta)

	if state == State.GAMEOVER:
		return

	if combo_timer > 0.0:
		combo_timer = maxf(0.0, combo_timer - delta)
		_combo_bar.value = (combo_timer / 2.6) * 100.0
		if combo_timer <= 0.0:
			combo = 0
			combo_label.visible = false
			_combo_bar.visible = false

	if state == State.WAVE_CLEAR:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_open_upgrade_choice()
		return

	if state != State.PLAYING:
		return

	player.set_controls(_move, _fire, _special)
	_special = false

	for i in range(_pending_portals.size() - 1, -1, -1):
		var entry := _pending_portals[i]
		entry["t"] = float(entry["t"]) - delta
		if float(entry["t"]) <= 0.0:
			_pending_portals.remove_at(i)
			_materialize_enemy(int(entry["kind"]), entry["pos"])

	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and not _spawn_queue.is_empty():
		var next_kind: int = _spawn_queue.pop_front()
		_queue_portal_spawn(next_kind)
		_spawn_cd = WaveDirector.spawn_interval(wave)

	if _spawn_queue.is_empty() and _pending_portals.is_empty() and get_tree().get_nodes_in_group("enemies").is_empty():
		state = State.WAVE_CLEAR
		_wave_timer = WAVE_BREAK
		_boss_box.visible = false
		_boss_hp_map.clear()
		_show_banner("领主击败！" if WaveDirector.is_boss_wave(wave) else "清场！")
		player.add_charge(0.18)
		_border_pulse = 1.0


func _update_burn_zones(delta: float) -> void:
	for i in range(_burn_zones.size() - 1, -1, -1):
		var bz := _burn_zones[i]
		bz["life"] = float(bz["life"]) - delta
		bz["tick"] = float(bz["tick"]) - delta
		if float(bz["tick"]) <= 0.0:
			bz["tick"] = 0.45
			var pos: Vector2 = bz["pos"]
			var rad := float(bz["r"])
			for e in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(e) and e.get("alive") != false:
					if pos.distance_to(e.global_position) <= rad:
						e.take_hit(2, pos, 60.0, false)
		if float(bz["life"]) <= 0.0:
			_burn_zones.remove_at(i)


func _queue_portal_spawn(kind: int) -> void:
	var pos := _pick_spawn_pos(kind)
	var col := Color(1.0, 0.32, 0.3)
	var rad := 24.0
	var dur := 0.42
	match kind:
		Enemy.Kind.SHOOTER:
			col = Color(0.75, 0.4, 1.0)
		Enemy.Kind.BRUISER:
			col = Color(1.0, 0.78, 0.22)
			rad = 30.0
		Enemy.Kind.DASHER:
			col = Color(1.0, 0.25, 0.7)
		Enemy.Kind.SPLITTER:
			col = Color(0.28, 0.9, 1.0)
		Enemy.Kind.BOSS, Enemy.Kind.BOSS_TWIN, Enemy.Kind.BOSS_ARBITER:
			col = Color(0.75, 0.35, 1.0) if kind == Enemy.Kind.BOSS_ARBITER else (Color(0.28, 0.88, 1.0) if kind == Enemy.Kind.BOSS_TWIN else Color(1.0, 0.35, 0.18))
			rad = 44.0
			dur = 0.75
	if vfx != null:
		vfx.spawn_portal(pos, col, dur, rad)
	_pending_portals.append({"kind": kind, "pos": pos, "t": dur})


func _pick_spawn_pos(kind: int) -> Vector2:
	if kind == Enemy.Kind.BOSS_TWIN:
		var side := -1.0 if (_spawn_queue.has(Enemy.Kind.BOSS_TWIN)) else 1.0
		return Vector2(arena.get_center().x + side * minf(160.0, arena.size.x * 0.26), arena.position.y + 115.0)
	if Enemy.is_boss_kind(kind):
		return Vector2(arena.get_center().x, arena.position.y + 110.0)
	for _attempt in 6:
		var edge := randi() % 4
		var pos := Vector2.ZERO
		match edge:
			0: pos = Vector2(randf_range(arena.position.x + 36, arena.end.x - 36), arena.position.y + 28)
			1: pos = Vector2(randf_range(arena.position.x + 36, arena.end.x - 36), arena.end.y - 28)
			2: pos = Vector2(arena.position.x + 28, randf_range(arena.position.y + 36, arena.end.y - 36))
			_: pos = Vector2(arena.end.x - 28, randf_range(arena.position.y + 36, arena.end.y - 36))
		if pos.distance_to(player.global_position) > 150.0:
			return pos
	return Vector2(arena.position.x + 36, arena.position.y + 36)


func _materialize_enemy(kind: int, pos: Vector2) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	world.add_child(e)
	e.setup(kind as Enemy.Kind, pos, player, arena, wave)
	e.killed.connect(_on_enemy_killed)
	e.split_requested.connect(_on_enemy_split)
	if Enemy.is_boss_kind(kind):
		e.boss_hp_changed.connect(_on_boss_hp_changed)
		_boss_hp_map[e.get_instance_id()] = {"hp": e.hp, "max": e.max_hp}
		_refresh_boss_bar()
	_update_hud()
	return e


func _on_enemy_split(pos: Vector2, count: int) -> void:
	for i in count:
		var offset := Vector2(cos(TAU * float(i) / float(count)), sin(TAU * float(i) / float(count))) * 18.0
		_materialize_enemy(Enemy.Kind.MINI, pos + offset)


func _on_boss_hp_changed(enemy: Enemy, cur: int, total: int) -> void:
	var eid := enemy.get_instance_id()
	if cur <= 0:
		_boss_hp_map.erase(eid)
	else:
		_boss_hp_map[eid] = {"hp": cur, "max": total}
	_refresh_boss_bar()


func _refresh_boss_bar() -> void:
	var sum_hp := 0
	var sum_max := 0
	for k in _boss_hp_map.keys():
		var entry: Dictionary = _boss_hp_map[k]
		sum_hp += int(entry["hp"])
		sum_max += int(entry["max"])
	if sum_hp <= 0 or sum_max <= 0:
		_boss_box.visible = false
		return
	_boss_box.visible = true
	_boss_bar.max_value = sum_max
	_boss_bar.value = sum_hp
	_boss_label.text = WaveDirector.boss_title(wave)


func _on_controls(move: Vector2, fire: bool, special: bool) -> void:
	_move = move
	_fire = fire
	if special:
		_special = true


func _on_enemy_killed(enemy: Enemy, points: int) -> void:
	kills += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_timer = 2.6
	var mult := 1 + mini(combo / 5, 4)
	var gained := points * mult
	score += gained

	var is_boss := Enemy.is_boss_kind(enemy.kind)
	if is_boss:
		_boss_hp_map.erase(enemy.get_instance_id())
		_refresh_boss_bar()
		# If one Rift Twin dies, enrage the surviving twin!
		if enemy.kind == Enemy.Kind.BOSS_TWIN:
			for other in get_tree().get_nodes_in_group("enemies"):
				if other != enemy and is_instance_valid(other) and other.get("alive") != false and other.get("kind") == Enemy.Kind.BOSS_TWIN:
					other.enrage()
					_show_banner("裂空双子 · 狂暴！")
					if vfx != null:
						vfx.spawn_ring(other.global_position, Color(1.0, 0.25, 0.42), 20.0, 110.0, 0.4, 5.0)
						vfx.spawn_text(other.global_position, "狂暴！", Color(1.0, 0.32, 0.45), 24)

	var heavy := enemy.kind == Enemy.Kind.BRUISER or is_boss
	var charge_gain := 0.28 if is_boss else (0.15 if heavy else 0.10)
	player.add_charge(charge_gain)

	if upgrades.vampire_enabled():
		_vampire_counter += 1
		if _vampire_counter >= upgrades.vampire_threshold():
			_vampire_counter = 0
			if player.heal(1) and vfx:
				vfx.spawn_text(player.global_position, "+1 虹吸", Color(0.95, 0.42, 0.72), 20)

	# Synergy: Thunder Blaze triggers chain lightning on kill!
	if upgrades.has_synergy("thunder_blaze"):
		_trigger_chain_lightning(enemy.global_position, enemy)

	if vfx != null:
		vfx.spawn_death_burst(enemy.global_position, enemy.body.color, heavy)
		vfx.spawn_text(
			enemy.global_position,
			"+%d" % gained,
			Color(1.0, 0.88, 0.35) if mult >= 3 else Color(1.0, 0.96, 0.88),
			24 if heavy else 18
		)

	_maybe_spawn_pickup(enemy)

	add_trauma(0.65 if is_boss else (0.40 if heavy else 0.26))
	request_hitstop(0.08 if is_boss else (0.055 if heavy or combo >= 8 else 0.035))
	Haptics.kill(heavy)
	Sfx.play("combo", 1.0 + mini(combo, 12) * 0.03, -8.0)

	combo_label.visible = combo >= 2
	_combo_bar.visible = combo >= 2
	combo_label.text = "连击 x%d (×%d)" % [combo, mult] if mult > 1 else "连击 x%d" % combo
	_update_hud()


func _trigger_chain_lightning(origin: Vector2, exclude: Node = null) -> void:
	if _in_chain_lightning:
		return
	_in_chain_lightning = true
	var hits := 0
	var dmg := maxi(1, upgrades.bullet_damage())
	for e in get_tree().get_nodes_in_group("enemies"):
		if hits >= 2:
			break
		if e == exclude or not is_instance_valid(e) or e.get("alive") == false:
			continue
		if origin.distance_to(e.global_position) <= 225.0:
			if vfx != null:
				vfx.spawn_arc(origin, e.global_position, Color(0.45, 0.88, 1.0))
			e.take_hit(dmg, origin, 140.0, false)
			hits += 1
	_in_chain_lightning = false


func _maybe_spawn_pickup(enemy: Enemy) -> void:
	if Enemy.is_boss_kind(enemy.kind):
		_spawn_pickup(Pickup.Kind.HEAL, enemy.global_position + Vector2(-24, 0))
		_spawn_pickup(Pickup.Kind.OVERDRIVE, enemy.global_position + Vector2(24, 0))
		for _i in 3:
			_spawn_pickup(Pickup.Kind.ENERGY, enemy.global_position)
		return
	var roll := randf()
	var low_hp := player.hp <= maxi(2, player.max_hp / 2)
	if enemy.kind == Enemy.Kind.BRUISER:
		if roll < (0.42 if low_hp else 0.24):
			_spawn_pickup(Pickup.Kind.HEAL, enemy.global_position)
		elif roll < 0.65:
			_spawn_pickup(Pickup.Kind.OVERDRIVE, enemy.global_position)
		else:
			_spawn_pickup(Pickup.Kind.ENERGY, enemy.global_position)
	elif roll < (0.10 if low_hp else 0.04):
		_spawn_pickup(Pickup.Kind.HEAL, enemy.global_position)
	elif roll < 0.14:
		_spawn_pickup(Pickup.Kind.OVERDRIVE, enemy.global_position)
	elif roll < 0.42:
		_spawn_pickup(Pickup.Kind.ENERGY, enemy.global_position)


func _spawn_pickup(kind: Pickup.Kind, pos: Vector2) -> void:
	var p := Pickup.new()
	world.add_child(p)
	p.setup(kind, pos)
	p.collected.connect(_on_pickup_collected)


func _on_pickup_collected(pickup: Pickup, kind: Pickup.Kind) -> void:
	Haptics.pickup()
	match kind:
		Pickup.Kind.ENERGY:
			player.add_charge(0.14)
			score += 25
			Sfx.play("click", 1.35, -7.0)
			if vfx:
				vfx.spawn_text(pickup.global_position, "+能量", Color(0.4, 0.9, 1.0), 17)
		Pickup.Kind.HEAL:
			Sfx.play("ready", 1.15, -4.0)
			if player.heal(1):
				if vfx:
					vfx.spawn_text(pickup.global_position, "+1 生命", Color(0.32, 0.96, 0.56), 20)
					vfx.spawn_ring(player.global_position, Color(0.32, 0.96, 0.56), 14.0, 52.0, 0.28, 3.0)
			else:
				score += 150
				if vfx:
					vfx.spawn_text(pickup.global_position, "满血 +150", Color(0.32, 0.96, 0.56), 18)
		Pickup.Kind.OVERDRIVE:
			player.activate_overdrive(5.5)
			Sfx.play("wave", 1.25, -3.0)
			add_trauma(0.25)
			if vfx:
				vfx.spawn_text(pickup.global_position, "烈焰过载！", Color(1.0, 0.85, 0.25), 22)
				vfx.spawn_ring(player.global_position, Color(1.0, 0.82, 0.25), 16.0, 74.0, 0.32, 4.0)
	_update_hud()


func enemy_impact(pos: Vector2, dir: Vector2, died: bool, _heavy: bool, dmg: int = 1, is_crit: bool = false) -> void:
	if died:
		return
	add_trauma(0.20 if is_crit else 0.11)
	if is_crit and upgrades.has_synergy("thunder_blaze"):
		_trigger_chain_lightning(pos)
	if vfx != null:
		vfx.spawn_sparks(
			pos,
			Color(1.0, 0.92, 0.35) if is_crit else Color(1.0, 0.72, 0.32),
			dir,
			10 if is_crit else 5,
			120.0,
			260.0 if is_crit else 180.0
		)
		if is_crit:
			vfx.spawn_text(pos, "暴击 %d!" % dmg, Color(1.0, 0.92, 0.32), 20)
	if is_crit:
		Haptics.crit()
	else:
		Haptics.hit()


func spawn_ricochet_arc(a: Vector2, b: Vector2) -> void:
	if vfx != null:
		vfx.spawn_arc(a, b, Color(0.58, 0.84, 1.0))


func spawn_player_thruster(pos: Vector2, dir: Vector2, overdrive: bool, tint: Color = Color(1.0, 0.52, 0.18)) -> void:
	if vfx != null:
		vfx.spawn_thruster(pos, dir, overdrive, tint)


func player_special_nova(center: Vector2) -> void:
	var r_mult := upgrades.nova_radius_mult()
	var dmg_bonus := upgrades.nova_damage_bonus()
	var inner_r := 225.0 * r_mult
	var outer_r := 340.0 * r_mult
	var has_double := upgrades.level_of("nova_plus") > 0

	flash.color = Color(1.0, 0.72, 0.25, 1.0)
	flash.modulate.a = 0.52
	add_trauma(0.85)
	_border_pulse = 1.0
	request_hitstop(0.085)
	Haptics.nova()
	if vfx != null:
		vfx.spawn_nova(center, outer_r, has_double)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d: float = center.distance_to(e.global_position)
		if d < inner_r:
			e.take_hit(5 + dmg_bonus, center, 380.0, true)
		elif d < outer_r:
			e.take_hit(3 + dmg_bonus / 2, center, 250.0, false)
	for c in world.get_children():
		if c is Bullet and not c.from_player:
			c.queue_free()

	# Synergy: Aftershock Nova leaves a 3.5s molten burn field!
	if upgrades.has_synergy("aftershock_nova"):
		var burn_r := 155.0 * r_mult
		_burn_zones.append({"pos": center, "r": burn_r, "life": 3.5, "tick": 0.25})
		if vfx != null:
			vfx.spawn_burn_zone(center, burn_r, 3.5)
			vfx.spawn_text(center + Vector2(0, -28), "灼烧余震！", Color(1.0, 0.62, 0.22), 20)


func _on_player_shield_blocked(_shield_left: int, pos: Vector2) -> void:
	add_trauma(0.35)
	flash.color = Color(0.3, 0.88, 1.0, 1.0)
	flash.modulate.a = 0.28
	var has_echo := upgrades.has_synergy("aegis_siphon")
	if vfx != null:
		vfx.spawn_ring(pos, Color(0.32, 0.92, 1.0), 18.0, 190.0 if has_echo else 82.0, 0.34, 5.0 if has_echo else 4.0)
		vfx.spawn_text(pos, "圣盾回响!" if has_echo else "护盾抵挡!", Color(0.45, 0.95, 1.0), 22)
	if has_echo:
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and pos.distance_to(e.global_position) <= 195.0:
				e.take_hit(3, pos, 340.0, false)
		for c in world.get_children():
			if c is Bullet and not c.from_player and pos.distance_to(c.global_position) <= 240.0:
				c.queue_free()
	_update_hud()


func _on_player_hurt(hp_left: int, _max_hp: int) -> void:
	add_trauma(0.55)
	flash.color = Color(1.0, 0.15, 0.2, 1.0)
	flash.modulate.a = 0.42
	combo = 0
	combo_timer = 0.0
	combo_label.visible = false
	_combo_bar.visible = false
	hp_bar.value = hp_left
	_update_hud()


func _on_player_died() -> void:
	state = State.GAMEOVER
	_clear_hitstop()
	Sfx.play("over")
	Bgm.to_gameover()
	var rec := SaveData.save_run(score, wave, max_combo, kills)
	pad.visible = false
	btn_pause.visible = false
	_boss_box.visible = false
	_overdrive_pill.visible = false
	over_panel.visible = true

	var new_rec := bool(rec["new_best_score"]) or bool(rec["new_best_wave"])
	_over_badge.visible = new_rec
	_over_badge.text = "★ 刷新个人纪录 ★" if new_rec else ""
	var ship_name := str(upgrades.ship.get("name", "烈焰先锋"))
	over_score.text = "战机 %s   ·   本局得分 %d（最高 %d）\n到达波次 %d   ·   击杀 %d   ·   最高连击 x%d" % [
		ship_name, score, SaveData.best_score, wave, kills, max_combo
	]
	var tags := upgrades.summary_tags()
	_over_build_label.text = ("本局流派：" + "  ·  ".join(tags)) if not tags.is_empty() else "本局流派：初始火力"
	add_trauma(0.75)


func _on_special_changed(charge: float, ready: bool) -> void:
	special_bar.value = charge * 100.0
	pad.set_special_charge(charge, ready)
	if ready:
		special_bar.modulate = Color(1.35, 1.12, 0.58)
	else:
		special_bar.modulate = Color(1, 1, 1)


func _on_overdrive_changed(time_left: float) -> void:
	if time_left > 0.05:
		_overdrive_pill.visible = true
		_overdrive_pill.text = "⚡ 烈焰过载  %.1fs" % time_left
	else:
		_overdrive_pill.visible = false


func _update_hud() -> void:
	score_label.text = "分数 %d" % score
	var remain := _spawn_queue.size() + _pending_portals.size() + get_tree().get_nodes_in_group("enemies").size()
	wave_label.text = "第 %d 波 · 剩 %d" % [wave, remain] if remain > 0 else "第 %d 波" % wave
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.hp
	if _hp_text != null:
		var sh := (" +%d盾" % player.shield) if player.shield > 0 else ""
		_hp_text.text = "%d/%d%s" % [player.hp, player.max_hp, sh]
	special_bar.max_value = 100
	special_bar.value = player.special_charge * 100.0


func _show_banner(text: String) -> void:
	banner.text = text
	banner.visible = true
	banner.modulate.a = 1.0
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(0.75)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.35)
	_banner_tween.tween_callback(func(): banner.visible = false)


func _toggle_pause() -> void:
	if state == State.PLAYING or state == State.WAVE_CLEAR:
		_state_before_pause = state
		state = State.PAUSED
		_clear_hitstop()
		var tags := upgrades.summary_tags()
		var ship_name := str(upgrades.ship.get("name", "烈焰先锋"))
		_pause_build_label.text = ("战机：%s\n当前强化：%s" % [ship_name, " · ".join(tags)]) if not tags.is_empty() else ("战机：%s\n当前强化：尚未选择强化" % ship_name)
		_refresh_setting_buttons()
		pause_panel.visible = true
		get_tree().paused = true
		Sfx.play("click")
	elif state == State.PAUSED:
		pause_panel.visible = false
		get_tree().paused = false
		state = _state_before_pause
		Sfx.play("click")


func _bind_system_back() -> void:
	var win := get_window()
	if win != null and not win.go_back_requested.is_connected(_on_system_back):
		win.go_back_requested.connect(_on_system_back)
	if not tree_exiting.is_connected(_unbind_system_back):
		tree_exiting.connect(_unbind_system_back)


func _unbind_system_back() -> void:
	var win := get_window()
	if win != null and win.go_back_requested.is_connected(_on_system_back):
		win.go_back_requested.disconnect(_on_system_back)


func _on_system_back() -> void:
	if state == State.PLAYING or state == State.WAVE_CLEAR or state == State.PAUSED:
		_toggle_pause()
	elif state == State.GAMEOVER:
		_to_title()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_on_system_back()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _banner_tween != null:
		_banner_tween.kill()
		_banner_tween = null
	_clear_hitstop()
	get_tree().paused = false
