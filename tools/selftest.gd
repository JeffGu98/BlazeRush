extends SceneTree

var _ok := true

func _initialize() -> void:
	call_deferred("_run")

func _fail_msg(msg: String) -> void:
	push_error(msg)
	print("[selftest] ERROR: ", msg)
	_ok = false

func _run() -> void:
	print("[selftest] start")
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		push_error("main.tscn failed to load")
		_fail()
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_test_bgm()
	_test_haptics()
	_test_multitouch(main)

	if main.has_method("_start_game"):
		main._start_game()
	for i in 45:
		await process_frame
	var enemies = get_nodes_in_group("enemies")
	print("[selftest] enemies after start: ", enemies.size())
	if enemies.is_empty():
		_fail_msg("expected enemies to spawn")
	if main.has_method("player_special_nova"):
		main.player_special_nova(Vector2(360, 545))
	# Hit-stop uses unscaled time (~0.085s). Wait enough frames for restore.
	var waited := 0
	while Engine.time_scale < 0.99 and waited < 90:
		await process_frame
		waited += 1
	if Engine.time_scale < 0.99:
		_fail_msg("time_scale not restored after nova hitstop, scale=%s" % Engine.time_scale)
	else:
		print("[selftest] time_scale restored after %d frames" % waited)
	await process_frame
	await process_frame
	var player = main.get_node_or_null("World/Player")
	if player == null or not player.alive:
		print("[selftest] player alive=", player.alive if player else false)
	print("[selftest] score=", main.score, " wave=", main.wave)
	if main.wave < 1:
		_fail_msg("wave did not start")
	# Leave the tree in a clean timescale.
	if main.has_method("_clear_hitstop"):
		main._clear_hitstop()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	main.queue_free()
	var bgm := root.get_node_or_null("Bgm")
	if bgm and bgm.has_method("stop"):
		bgm.stop()
	await process_frame
	if _ok:
		print("[selftest] PASS")
		quit(0)
	else:
		_fail()

func _test_bgm() -> void:
	var bgm := root.get_node_or_null("Bgm")
	if bgm == null:
		_fail_msg("Bgm autoload missing")
		return
	var stream: Resource = load("res://assets/music/blaze_theme.ogg")
	if stream == null:
		_fail_msg("blaze_theme.ogg failed to load")
		return
	print("[selftest] bgm stream ok")

func _test_haptics() -> void:
	var h := root.get_node_or_null("Haptics")
	if h == null:
		_fail_msg("Haptics autoload missing")
		return
	h.pulse(1, 0.1)
	h.hit()
	h.kill(false)
	h.hurt()
	h.nova()
	print("[selftest] haptics calls ok")

func _test_multitouch(main: Node) -> void:
	var pad = main.get_node_or_null("UI/VirtualPad")
	if pad == null:
		_fail_msg("VirtualPad missing")
		return
	# Local coordinates inside the pad (720 x 280).
	var joy_pos := Vector2(116, 120)
	var fire_pos := Vector2(590, 130)
	var special_pos := Vector2(440, 150)
	var miss_pos := Vector2(700, 10)

	pad.debug_apply_touch(0, true, joy_pos)
	if pad.move_vec.length() < 0.01:
		# Center of the stick is a dead/zero region — nudge outward.
		pad.debug_apply_drag(0, Vector2(160, 80))
	if pad.move_vec.length() < 0.2:
		_fail_msg("joystick touch did not produce move_vec, got %s" % pad.move_vec)
	pad.debug_apply_touch(1, true, fire_pos)
	if not pad.fire_held:
		_fail_msg("fire button was not held while joystick is active")
	# Releasing the move finger must not cancel fire.
	pad.debug_apply_touch(0, false, joy_pos)
	if not pad.fire_held:
		_fail_msg("releasing move finger cancelled fire")
	if pad.move_vec.length() > 0.01:
		_fail_msg("move_vec not cleared after joystick release")
	# Third finger queues special without dropping fire.
	var special_before: bool = pad._special_queue
	pad.debug_apply_touch(2, true, special_pos)
	if not pad._special_queue:
		_fail_msg("special button did not queue while fire is held")
	if not pad.fire_held:
		_fail_msg("special press cancelled fire")
	pad.debug_apply_touch(2, false, special_pos)
	pad.debug_apply_touch(1, false, fire_pos)
	if pad.fire_held:
		_fail_msg("fire_held stuck after release")
	# A miss should not steal a later fire press.
	pad.debug_apply_touch(3, true, miss_pos)
	pad.debug_apply_touch(3, false, miss_pos)
	pad.debug_apply_touch(4, true, fire_pos)
	if not pad.fire_held:
		_fail_msg("fire press after a missed touch failed")
	pad.debug_apply_touch(4, false, fire_pos)
	# Coordinate helper must apply the canvas transform, not raw subtraction.
	var xf: Transform2D = pad.get_global_transform_with_canvas()
	var world_pt := xf * fire_pos
	var back: Vector2 = pad._to_local(world_pt)
	if back.distance_to(fire_pos) > 0.75:
		_fail_msg("pad _to_local mismatch: %s vs %s" % [back, fire_pos])
	print("[selftest] multitouch pad ok")

func _fail() -> void:
	print("[selftest] FAIL")
	Engine.time_scale = 1.0
	quit(1)
