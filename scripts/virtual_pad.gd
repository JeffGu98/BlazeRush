extends Control
class_name VirtualPad

signal controls_changed(move: Vector2, fire: bool, special: bool)

var move_vec: Vector2 = Vector2.ZERO
var fire_held: bool = false
var _special_queue: bool = false

var _joy_touch: int = -1
var _fire_touch: int = -1
var _joy_center: Vector2 = Vector2.ZERO
var _joy_knob: Vector2 = Vector2.ZERO
var _max_radius: float = 78.0
var _kb_special_prev: bool = false

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

func set_special_charge(ratio: float, ready: bool) -> void:
	special_fill.anchor_top = 1.0 - clampf(ratio, 0.0, 1.0)
	btn_special.modulate = Color(1.3, 1.05, 0.5) if ready else Color(1, 1, 1)

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
	controls_changed.emit(move_vec, fire, special)

func _gui_input(event: InputEvent) -> void:
	_handle(event)

func _set_knob(rel: Vector2) -> void:
	_joy_knob = rel.limit_length(_max_radius)
	joy_knob.position = _joy_center + _joy_knob - joy_knob.size * 0.5

func _handle(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var local := st.position - global_position
		if st.pressed:
			if _in_joy(local) and _joy_touch < 0:
				_joy_touch = st.index
				_update_joy(local)
				accept_event()
			elif _in_control(btn_fire, local):
				_fire_touch = st.index
				fire_held = true
				accept_event()
			elif _in_control(btn_special, local):
				_special_queue = true
				accept_event()
		else:
			if st.index == _joy_touch:
				_joy_touch = -1
				move_vec = Vector2.ZERO
				_set_knob(Vector2.ZERO)
			if st.index == _fire_touch:
				_fire_touch = -1
				fire_held = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joy_touch:
			_update_joy(sd.position - global_position)
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var local3 := get_local_mouse_position()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _in_joy(local3):
					_joy_touch = 1000
					_update_joy(local3)
				elif _in_control(btn_fire, local3):
					_fire_touch = 1000
					fire_held = true
				elif _in_control(btn_special, local3):
					_special_queue = true
			else:
				if _joy_touch == 1000:
					_joy_touch = -1
					move_vec = Vector2.ZERO
					_set_knob(Vector2.ZERO)
				if _fire_touch == 1000:
					_fire_touch = -1
					fire_held = false
	elif event is InputEventMouseMotion:
		if _joy_touch == 1000 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update_joy(get_local_mouse_position())

func _in_joy(local: Vector2) -> bool:
	var c := joy_base.position + joy_base.size * 0.5
	return local.distance_to(c) <= _max_radius + 40.0

func _in_control(c: Control, local: Vector2) -> bool:
	return Rect2(c.position, c.size).grow(10.0).has_point(local)

func _update_joy(local: Vector2) -> void:
	var c := joy_base.position + _joy_center
	var rel := local - c
	_set_knob(rel)
	move_vec = (_joy_knob / _max_radius).limit_length(1.0)
