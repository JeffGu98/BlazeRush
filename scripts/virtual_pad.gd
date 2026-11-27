extends Control
class_name VirtualPad

signal controls_changed(move: Vector2, fire: bool, special: bool)
signal auto_fire_toggled(enabled: bool)

var move_vec: Vector2 = Vector2.ZERO
var fire_held: bool = false
var auto_fire_active: bool = false
var _special_queue: bool = false

var _joy_touch: int = -1
var _fire_touch: int = -1
var _special_touch: int = -1
var _joy_center: Vector2 = Vector2.ZERO
var _rest_joy_pos: Vector2 = Vector2(116, 120)
var _active_joy_pos: Vector2 = Vector2(116, 120)
var _joy_knob: Vector2 = Vector2.ZERO
var _max_radius: float = 78.0
var _kb_special_prev: bool = false
var _special_ready: bool = false
var _special_ratio: float = 0.0
var _time: float = 0.0
var _auto_btn: Button

@onready var joy_base: Control = $JoyBase
@onready var joy_knob: Control = $JoyBase/Knob
@onready var btn_fire: Control = $BtnFire
@onready var btn_special: Control = $BtnSpecial
@onready var fire_label: Label = $BtnFire/Label
@onready var special_label: Label = $BtnSpecial/Label
@onready var special_fill: ColorRect = $BtnSpecial/Fill


func _ready() -> void:
	fire_label.text = "射击"
	special_label.text = "必杀"
	_joy_center = joy_base.size * 0.5
	joy_knob.position = _joy_center - joy_knob.size * 0.5
	for c in [joy_base, joy_knob, btn_fire, btn_special, fire_label, special_label, special_fill]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_circular_styles()
	_build_auto_fire_pill()
	resized.connect(_layout_controls)
	_layout_controls()


func _apply_circular_styles() -> void:
	var empty := StyleBoxEmpty.new()
	for p in [joy_base, joy_knob, btn_fire, btn_special]:
		if p is Panel:
			(p as Panel).add_theme_stylebox_override("panel", empty)
			p.modulate = Color.WHITE
	special_fill.visible = false
	fire_label.add_theme_font_size_override("font_size", 28)
	fire_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.9, 1.0))
	special_label.add_theme_font_size_override("font_size", 24)
	special_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))


func _build_auto_fire_pill() -> void:
	_auto_btn = Button.new()
	_auto_btn.name = "AutoFireBtn"
	_auto_btn.focus_mode = Control.FOCUS_NONE
	_auto_btn.size = Vector2(92, 34)
	_auto_btn.add_theme_font_size_override("font_size", 15)
	_auto_btn.pressed.connect(func():
		set_auto_fire(not auto_fire_active)
		auto_fire_toggled.emit(auto_fire_active)
	)
	add_child(_auto_btn)
	_refresh_auto_btn()


func set_auto_fire(enabled: bool) -> void:
	auto_fire_active = enabled
	_refresh_auto_btn()
	queue_redraw()


func _refresh_auto_btn() -> void:
	if _auto_btn == null:
		return
	_auto_btn.text = "自动:开" if auto_fire_active else "自动:关"
	_auto_btn.add_theme_color_override(
		"font_color",
		Color(0.12, 0.08, 0.03) if auto_fire_active else Color(0.75, 0.78, 0.88)
	)
	var bg := Color(1.0, 0.78, 0.25, 0.92) if auto_fire_active else Color(0.14, 0.13, 0.22, 0.84)
	var border := Color(1.0, 0.90, 0.45, 0.95) if auto_fire_active else Color(0.55, 0.58, 0.72, 0.42)
	for st in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = bg.lightened(0.08) if st == "hover" else bg
		box.set_corner_radius_all(12)
		box.set_border_width_all(1)
		box.border_color = border
		_auto_btn.add_theme_stylebox_override(st, box)
	_auto_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _layout_controls() -> void:
	var w := size.x if size.x > 100.0 else 720.0
	var h := size.y if size.y > 100.0 else 280.0
	var cy := clampf(h * 0.45, 110.0, 145.0)
	joy_base.position = Vector2(36.0, cy - joy_base.size.y * 0.5)
	_rest_joy_pos = joy_base.position + _joy_center
	if _joy_touch < 0:
		_active_joy_pos = _rest_joy_pos
	btn_fire.position = Vector2(w - 200.0, cy - btn_fire.size.y * 0.5 + 10.0)
	btn_special.position = Vector2(w - 340.0, cy - btn_special.size.y * 0.5 + 30.0)
	if _auto_btn != null:
		_auto_btn.position = Vector2(btn_fire.position.x + (btn_fire.size.x - _auto_btn.size.x) * 0.5, maxf(14.0, btn_fire.position.y - 44.0))
	queue_redraw()


func set_special_charge(ratio: float, ready: bool) -> void:
	_special_ratio = clampf(ratio, 0.0, 1.0)
	special_fill.anchor_top = 1.0 - _special_ratio
	_special_ready = ready
	_refresh_special_visual()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _joy_touch < 0:
		_active_joy_pos = _active_joy_pos.lerp(_rest_joy_pos, minf(1.0, delta * 14.0))
	var k := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if k.length() > 0.01 and _joy_touch < 0:
		move_vec = k.limit_length(1.0)
		_set_knob(move_vec * _max_radius)
	elif _joy_touch < 0 and move_vec.length() > 0.0:
		move_vec = Vector2.ZERO
		_set_knob(Vector2.ZERO)

	var fire := fire_held or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_J)
	var special_key := Input.is_key_pressed(KEY_K) or Input.is_key_pressed(KEY_SHIFT)
	var special := _special_queue
	if special_key and not _kb_special_prev:
		special = true
	_kb_special_prev = special_key
	_special_queue = false
	_refresh_fire_visual()
	_refresh_special_visual()
	controls_changed.emit(move_vec, fire, special)
	queue_redraw()


func _draw() -> void:
	draw_line(Vector2(24, 6), Vector2(size.x - 24, 6), Color(1.0, 0.5, 0.22, 0.22), 1.5)

	# 1. Floating circular joystick base & knob
	var jc := _active_joy_pos
	var jr := minf(joy_base.size.x, joy_base.size.y) * 0.5
	var joy_active := _joy_touch >= 0 or move_vec.length() > 0.05
	draw_circle(jc, jr, Color(0.11, 0.10, 0.17, 0.74 if joy_active else 0.56))
	draw_arc(jc, jr, 0.0, TAU, 48, Color(1.0, 0.58, 0.25, 0.72 if joy_active else 0.32), 2.5, true)
	draw_arc(jc, jr * 0.45, 0.0, TAU, 28, Color(1.0, 0.58, 0.25, 0.16), 1.2, true)
	var kc := jc + _joy_knob
	draw_circle(kc, 33.0, Color(1.0, 0.52, 0.18, 0.30 if joy_active else 0.14))
	draw_circle(kc, 26.0, Color(1.0, 0.62, 0.25, 0.94 if joy_active else 0.70))
	draw_circle(kc, 10.0, Color(1.0, 0.94, 0.75, 0.85))

	# 2. Circular Fire button
	var fc := btn_fire.position + btn_fire.size * 0.5
	var fr := minf(btn_fire.size.x, btn_fire.size.y) * 0.5 * (1.06 if fire_held else 1.0)
	var fire_glow_a := 0.28 if fire_held else (0.18 if auto_fire_active else 0.10)
	draw_circle(fc, fr + 6.0, Color(1.0, 0.36, 0.16, fire_glow_a))
	draw_circle(fc, fr, Color(0.95, 0.36, 0.18, 0.88 if fire_held else (0.68 if auto_fire_active else 0.54)))
	draw_arc(fc, fr, 0.0, TAU, 48, Color(1.0, 0.82, 0.36, 0.95) if (fire_held or auto_fire_active) else Color(1.0, 0.72, 0.42, 0.66), 3.0, true)

	# 3. Circular Special button with radial charge ring
	var sc := btn_special.position + btn_special.size * 0.5
	var sr := minf(btn_special.size.x, btn_special.size.y) * 0.5
	var pulse := 1.0 + (0.055 * sin(_time * 9.0) if _special_ready else 0.0)
	var eff_r := sr * pulse
	if _special_ready:
		draw_circle(sc, eff_r + 10.0, Color(1.0, 0.78, 0.22, 0.24 + 0.10 * sin(_time * 9.0)))
	draw_circle(sc, eff_r, Color(0.95, 0.66, 0.16, 0.82) if _special_ready else Color(0.16, 0.14, 0.22, 0.78))
	draw_arc(sc, eff_r, 0.0, TAU, 44, Color(1.0, 0.78, 0.28, 0.28), 3.0, true)
	if _special_ratio > 0.005:
		var start_a := -PI * 0.5
		var end_a := start_a + TAU * _special_ratio
		draw_arc(sc, eff_r, start_a, end_a, 44, Color(1.0, 0.88, 0.35, 1.0), 5.0 if _special_ready else 4.0, true)


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var local := _to_local(st.position)
		if st.pressed and _auto_btn != null and Rect2(_auto_btn.position, _auto_btn.size).grow(8.0).has_point(local):
			# Let the AutoFireBtn handle its own press cleanly.
			return
		var used := false
		if st.pressed:
			used = _on_touch_pressed(st.index, local)
		else:
			used = _on_touch_released(st.index)
		if used:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joy_touch:
			_update_joy(_to_local(sd.position))
			get_viewport().set_input_as_handled()


func _to_local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos


func _on_touch_pressed(index: int, local: Vector2) -> bool:
	if index == _joy_touch or index == _fire_touch or index == _special_touch:
		return true
	if _in_control(btn_fire, local) and _fire_touch < 0:
		_fire_touch = index
		fire_held = true
		_refresh_fire_visual()
		return true
	if _in_control(btn_special, local) and _special_touch < 0:
		_special_touch = index
		_special_queue = true
		return true
	if _in_move_zone(local) and _joy_touch < 0:
		_joy_touch = index
		# Floating joystick: center snaps right where the left thumb lands (clamped inside left zone).
		var max_x := maxf(180.0, size.x * 0.42)
		var max_y := maxf(140.0, size.y - 64.0)
		_active_joy_pos = Vector2(
			clampf(local.x, 76.0, max_x),
			clampf(local.y, 76.0, max_y)
		)
		_update_joy(local)
		return true
	return false


func _on_touch_released(index: int) -> bool:
	var used := false
	if index == _joy_touch:
		_joy_touch = -1
		move_vec = Vector2.ZERO
		_set_knob(Vector2.ZERO)
		used = true
	if index == _fire_touch:
		_fire_touch = -1
		fire_held = false
		_refresh_fire_visual()
		used = true
	if index == _special_touch:
		_special_touch = -1
		used = true
	return used


func debug_apply_touch(index: int, pressed: bool, local: Vector2) -> void:
	if pressed:
		_on_touch_pressed(index, local)
	else:
		_on_touch_released(index)


func debug_apply_drag(index: int, local: Vector2) -> void:
	if index == _joy_touch:
		_update_joy(local)


func _refresh_fire_visual() -> void:
	if not is_node_ready():
		return
	fire_label.scale = Vector2(1.06, 1.06) if fire_held else Vector2.ONE
	fire_label.pivot_offset = fire_label.size * 0.5


func _refresh_special_visual() -> void:
	if not is_node_ready():
		return
	if _special_ready:
		special_label.text = "释放!"
		special_label.add_theme_color_override("font_color", Color(0.12, 0.06, 0.02, 1.0))
	else:
		special_label.text = "必杀"
		special_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.78, 0.88))


func _set_knob(rel: Vector2) -> void:
	_joy_knob = rel.limit_length(_max_radius)
	joy_knob.position = _joy_center + _joy_knob - joy_knob.size * 0.5


func _in_joy(local: Vector2) -> bool:
	return local.distance_to(_rest_joy_pos) <= _max_radius + 42.0


func _in_move_zone(local: Vector2) -> bool:
	if _in_joy(local):
		return true
	var r := Rect2(Vector2.ZERO, size)
	if not r.has_point(local):
		return false
	return local.x < size.x * 0.48


func _in_control(c: Control, local: Vector2) -> bool:
	return Rect2(c.position, c.size).grow(22.0).has_point(local)


func _update_joy(local: Vector2) -> void:
	var rel := local - _active_joy_pos
	_set_knob(rel)
	move_vec = (_joy_knob / _max_radius).limit_length(1.0)
