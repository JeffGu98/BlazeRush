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
	_test_upgrade_system()
	_test_wave_director()
	_test_update_semver()

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
	_test_version_label(main)

	if main.has_method("_start_game"):
		main._start_game()
	await create_timer(0.75).timeout
	await process_frame
	var enemies = get_nodes_in_group("enemies")
	print("[selftest] enemies after start: ", enemies.size())
	if enemies.is_empty():
		_fail_msg("expected enemies to spawn after portal warning")

	# Test shield absorption
	main.upgrades.apply("shield")
	main.player.sync_upgrades(0)
	var hp_before: int = main.player.hp
	var shield_before: int = main.player.shield
	if shield_before < 1:
		_fail_msg("shield upgrade did not grant shield")
	main.player.take_damage(1, Vector2.ZERO)
	if main.player.hp != hp_before or main.player.shield != shield_before - 1:
		_fail_msg("shield did not absorb damage hp=%d/%d shield=%d" % [main.player.hp, hp_before, main.player.shield])
	print("[selftest] shield absorb ok")

	# Test splitter spawns mini enemies
	var splitter: Enemy = main._materialize_enemy(Enemy.Kind.SPLITTER, Vector2(360, 420))
	var count_before_split := get_nodes_in_group("enemies").size()
	splitter.take_hit(99, Vector2(360, 400))
	await process_frame
	var minis := 0
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.kind == Enemy.Kind.MINI:
			minis += 1
	if minis < 2:
		_fail_msg("splitter did not spawn 2 mini enemies, got %d (before=%d)" % [minis, count_before_split])
	print("[selftest] splitter ok")

	# Test boss HP bar & kill
	var boss: Enemy = main._materialize_enemy(Enemy.Kind.BOSS, Vector2(360, 260))
	if not main._boss_box.visible:
		_fail_msg("boss HP bar not visible after boss spawn")
	boss.take_hit(10, Vector2(360, 320), 100.0, true)
	if int(main._boss_bar.value) != boss.hp:
		_fail_msg("boss HP bar did not sync")
	boss.take_hit(999, Vector2(360, 320))
	await process_frame
	if main._boss_box.visible:
		_fail_msg("boss HP bar stayed visible after boss death")
	print("[selftest] boss lifecycle ok")

	# Test pickup overdrive & energy
	main._spawn_pickup(Pickup.Kind.OVERDRIVE, main.player.global_position)
	await process_frame
	await process_frame
	if main.player.overdrive_timer <= 0.0:
		_fail_msg("overdrive pickup did not activate overdrive")
	print("[selftest] pickup overdrive ok")

	# Test nova & hitstop restore
	if main.has_method("player_special_nova"):
		main.player_special_nova(Vector2(360, 545))
	var waited := 0
	while Engine.time_scale < 0.99 and waited < 90:
		await process_frame
		waited += 1
	if Engine.time_scale < 0.99:
		_fail_msg("time_scale not restored after nova hitstop, scale=%s" % Engine.time_scale)
	else:
		print("[selftest] time_scale restored after %d frames" % waited)

	# Test roguelite upgrade choice flow
	main._open_upgrade_choice()
	if main.state != main.State.UPGRADE_CHOICE or not main._upgrade_panel.visible:
		_fail_msg("upgrade overlay did not open")
	if main._upgrade_cards_box.get_child_count() < 1:
		_fail_msg("upgrade overlay rendered no cards")
	var first_id := str(main._current_choices[0]["id"])
	var wave_before: int = main.wave
	main._select_upgrade(first_id)
	if main.state != main.State.PLAYING or main._upgrade_panel.visible or main.wave != wave_before + 1:
		_fail_msg("selecting upgrade did not resume into next wave")
	print("[selftest] upgrade draft ok: picked=%s wave=%d" % [first_id, main.wave])

	if main.has_method("_clear_hitstop"):
		main._clear_hitstop()
	if main.has_method("_clear_world_entities"):
		main._clear_world_entities()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	main.queue_free()
	var bgm := root.get_node_or_null("Bgm")
	if bgm and bgm.has_method("stop"):
		bgm.stop()
	await process_frame
	await process_frame
	if _ok:
		print("[selftest] PASS")
		quit(0)
	else:
		_fail()


func _test_upgrade_system() -> void:
	var u := UpgradeSystem.new()
	var picks := u.roll_choices(3, true)
	if picks.size() != 3:
		_fail_msg("roll_choices expected 3, got %d" % picks.size())
	var has_epic := false
	var seen := {}
	for p in picks:
		var id := str(p["id"])
		if seen.has(id):
			_fail_msg("duplicate choice in roll_choices: %s" % id)
		seen[id] = true
		if int(p["rarity"]) == UpgradeSystem.Rarity.EPIC:
			has_epic = true
	if not has_epic:
		_fail_msg("guarantee_epic did not include an EPIC upgrade")
	u.apply("multishot")
	u.apply("pierce")
	u.apply("ricochet")
	if u.projectile_count() != 2 or u.pierce_count() != 1 or u.ricochet_count() != 1:
		_fail_msg("upgrade stats mismatch")
	print("[selftest] upgrade system ok")


func _test_wave_director() -> void:
	if not WaveDirector.is_boss_wave(5) or WaveDirector.is_boss_wave(4):
		_fail_msg("is_boss_wave logic error")
	var w5 := WaveDirector.build_queue(5)
	if not w5.has(Enemy.Kind.BOSS):
		_fail_msg("wave 5 missing BOSS")
	var w4 := WaveDirector.build_queue(4)
	if not w4.has(Enemy.Kind.SPLITTER) or not w4.has(Enemy.Kind.DASHER):
		_fail_msg("wave 4 missing advanced enemies")
	print("[selftest] wave director ok")


func _test_update_semver() -> void:
	if not UpdateChecker.is_newer("v2.0.1", "2.0.0"):
		_fail_msg("semver failed 2.0.1 > 2.0.0")
	if UpdateChecker.is_newer("v2.0.0", "2.0.0") or UpdateChecker.is_newer("v1.9.9", "2.0.0"):
		_fail_msg("semver false positive")
	print("[selftest] update semver ok")


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
	h.crit()
	h.kill(false)
	h.pickup()
	h.hurt()
	h.nova()
	print("[selftest] haptics calls ok")


func _test_multitouch(main: Node) -> void:
	var pad = main.get_node_or_null("UI/VirtualPad")
	if pad == null:
		_fail_msg("VirtualPad missing")
		return
	var joy_pos := Vector2(116, 120)
	var fire_pos := Vector2(590, 130)
	var special_pos := Vector2(440, 150)
	var miss_pos := Vector2(700, 10)

	pad.debug_apply_touch(0, true, joy_pos)
	if pad.move_vec.length() < 0.01:
		pad.debug_apply_drag(0, Vector2(160, 80))
	if pad.move_vec.length() < 0.2:
		_fail_msg("joystick touch did not produce move_vec, got %s" % pad.move_vec)
	pad.debug_apply_touch(1, true, fire_pos)
	if not pad.fire_held:
		_fail_msg("fire button was not held while joystick is active")
	pad.debug_apply_touch(0, false, joy_pos)
	if not pad.fire_held:
		_fail_msg("releasing move finger cancelled fire")
	if pad.move_vec.length() > 0.01:
		_fail_msg("move_vec not cleared after joystick release")
	pad.debug_apply_touch(2, true, special_pos)
	if not pad._special_queue:
		_fail_msg("special button did not queue while fire is held")
	if not pad.fire_held:
		_fail_msg("special press cancelled fire")
	pad.debug_apply_touch(2, false, special_pos)
	pad.debug_apply_touch(1, false, fire_pos)
	if pad.fire_held:
		_fail_msg("fire_held stuck after release")
	pad.debug_apply_touch(3, true, miss_pos)
	pad.debug_apply_touch(3, false, miss_pos)
	pad.debug_apply_touch(4, true, fire_pos)
	if not pad.fire_held:
		_fail_msg("fire press after a missed touch failed")
	pad.debug_apply_touch(4, false, fire_pos)
	var xf: Transform2D = pad.get_global_transform_with_canvas()
	var world_pt := xf * fire_pos
	var back: Vector2 = pad._to_local(world_pt)
	if back.distance_to(fire_pos) > 0.75:
		_fail_msg("pad _to_local mismatch: %s vs %s" % [back, fire_pos])
	print("[selftest] multitouch pad ok")


func _test_version_label(main: Node) -> void:
	var lbl := main.get_node_or_null("UI/Title/VersionLabel") as Label
	var expected := "v%s" % str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if lbl == null or lbl.text != expected:
		_fail_msg("VersionLabel mismatch: got=%s want=%s" % [lbl.text if lbl else "<missing>", expected])
		return
	print("[selftest] version label ok: ", lbl.text)


func _fail() -> void:
	print("[selftest] FAIL")
	Engine.time_scale = 1.0
	quit(1)
