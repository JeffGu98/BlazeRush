extends Control
class_name VirtualPad

signal controls_changed(move: Vector2, fire: bool, special: bool)

var move_vec: Vector2 = Vector2.ZERO
var fire_held: bool = false
var _special_queue: bool = false

var _joy_touch: int = -1
var _fire_touch: int = -1
var _special_touch: int = -1
var _joy_center: Vector2 = Vector2.ZERO
var _joy_knob: Vector2 = Vector2.ZERO
var _max_radius: float = 78.0
var _kb_special_prev: bool = false
var _special_ready: bool = false
var _fire_base_mod: Color = Color(1, 0.4, 0.25, 0.75)
var _special_base_mod: Color = Color(1, 0.75, 0.25, 0.7)

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
	# Input is read in _input() so every finger arrives, not just the GUI mouse pointer.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_special_charge(ratio: float, ready: bool) -> void:
	special_fill.anchor_top = 1.0 - clampf(ratio, 0.0, 1.0)
	_special_ready = ready
	_refresh_special_visual()

func _process(_delta: float) -> void:
	var k := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if k.length() > 0.01 and _joy_touch < 0:
		move_vec = k.limit_length(1.0)
		_set_knob(move_vec * _max_radius)
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

func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	# Mouse is converted to ScreenTouch when emulate_touch_from_mouse is on (project setting).
	# Handling only touch/drag avoids the first finger being tracked twice (mouse + touch).
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var local := _to_local(st.position)
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
	# Face buttons win over the wider move zone.
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

## Test helper: apply a touch already expressed in VirtualPad local pixels.
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
	if fire_held:
		btn_fire.modulate = Color(1.35, 0.6, 0.28, 0.95)
		btn_fire.scale = Vector2(1.06, 1.06)
		btn_fire.pivot_offset = btn_fire.size * 0.5
	else:
		btn_fire.modulate = _fire_base_mod
		btn_fire.scale = Vector2.ONE
		btn_fire.pivot_offset = btn_fire.size * 0.5

func _refresh_special_visual() -> void:
	if not is_node_ready():
		return
	if _special_ready:
		var pulse := 0.08 * sin(Time.get_ticks_msec() * 0.01)
		btn_special.modulate = Color(1.35 + pulse, 1.08, 0.45, 0.9)
	elif _special_touch >= 0:
		btn_special.modulate = Color(1.15, 0.9, 0.4, 0.9)
	else:
		btn_special.modulate = _special_base_mod

func _set_knob(rel: Vector2) -> void:
	_joy_knob = rel.limit_length(_max_radius)
	joy_knob.position = _joy_center + _joy_knob - joy_knob.size * 0.5

func _in_joy(local: Vector2) -> bool:
	var c := joy_base.position + joy_base.size * 0.5
	return local.distance_to(c) <= _max_radius + 40.0

func _in_move_zone(local: Vector2) -> bool:
	if _in_joy(local):
		return true
	var r := Rect2(Vector2.ZERO, size)
	if not r.has_point(local):
		return false
	# Left half of the pad is a generous move zone for thumbs that miss the stick.
	return local.x < size.x * 0.48

func _in_control(c: Control, local: Vector2) -> bool:
	return Rect2(c.position, c.size).grow(22.0).has_point(local)

func _update_joy(local: Vector2) -> void:
	var c := joy_base.position + _joy_center
	var rel := local - c
	_set_knob(rel)
	move_vec = (_joy_knob / _max_radius).limit_length(1.0)
