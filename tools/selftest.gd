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
	_test_ships_and_synergies()
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

	# Test ship selection & auto-fire sync
	var save_data := root.get_node_or_null("SaveData")
	main._select_ship("storm")
	main._on_auto_fire_toggled(true)
	if save_data == null or save_data.selected_ship != "storm" or not main.player.auto_fire_enabled or not main.pad.auto_fire_active:
		_fail_msg("ship select or auto_fire toggle failed to sync")
	print("[selftest] ship & auto-fire sync ok")

	# Test 20:9 tall phone expand layout
	main.get_window().size = Vector2i(720, 1600)
	await process_frame
	main._layout_for_viewport()
	if main.arena.size.y < 1050.0:
		_fail_msg("expand layout did not grow arena height on 20:9 screen: %s" % str(main.arena))
	print("[selftest] 20:9 expand layout ok: arena=%s" % str(main.arena))

	if main.has_method("_start_game"):
		main._start_game()
	if main.player.max_hp != 4 or main.upgrades.projectile_count() != 2:
		_fail_msg("storm ship starting stats mismatch hp=%d proj=%d" % [main.player.max_hp, main.upgrades.projectile_count()])

	await create_timer(0.75).timeout
	await process_frame
	var enemies = get_nodes_in_group("enemies")
	print("[selftest] enemies after start: ", enemies.size())
	if enemies.is_empty():
		_fail_msg("expected enemies to spawn after portal warning")

	# Test low-HP danger glow
	main.player.hp = 1
	await process_frame
	if main.vfx.low_hp_danger < 0.9:
		_fail_msg("low_hp_danger did not activate at 1 HP")
	main.player.hp = main.player.max_hp
	print("[selftest] low-HP danger glow ok")

	# Test shield + Aegis Siphon synergy
	main.upgrades.apply("shield")
	main.upgrades.apply("vampire")
	main.player.sync_upgrades(0)
	if not main.upgrades.has_synergy("aegis_siphon") or main.upgrades.vampire_threshold() != 10:
		_fail_msg("aegis_siphon synergy did not activate")
	var hp_before: int = main.player.hp
	var shield_before: int = main.player.shield
	main.player.take_damage(1, Vector2.ZERO)
	if main.player.hp != hp_before or main.player.shield != shield_before - 1:
		_fail_msg("shield did not absorb damage")
	print("[selftest] shield + aegis_siphon ok")

	# Test Aftershock Nova synergy creates burn zone
	main.upgrades.apply("nova_plus")
	main.upgrades.apply("charge")
	if not main.upgrades.has_synergy("aftershock_nova"):
		_fail_msg("aftershock_nova synergy did not activate")
	main.player_special_nova(Vector2(360, 545))
	if main._burn_zones.is_empty():
		_fail_msg("aftershock_nova did not spawn burn zone")
	var waited := 0
	while Engine.time_scale < 0.99 and waited < 90:
		await process_frame
		waited += 1
	if Engine.time_scale < 0.99:
		_fail_msg("time_scale not restored after nova hitstop, scale=%s" % Engine.time_scale)
	print("[selftest] aftershock_nova & hitstop ok (%d frames)" % waited)

	# Test Rift Twins combined Boss HP bar & enrage mechanic
	main.wave = 10
	var twin_a: Enemy = main._materialize_enemy(Enemy.Kind.BOSS_TWIN, Vector2(220, 260))
	var twin_b: Enemy = main._materialize_enemy(Enemy.Kind.BOSS_TWIN, Vector2(500, 260))
	if not main._boss_box.visible or int(main._boss_bar.max_value) != twin_a.max_hp + twin_b.max_hp:
		_fail_msg("rift twins combined boss bar mismatch")
	twin_a.take_hit(999, Vector2(220, 320))
	await process_frame
	if not twin_b.enraged:
		_fail_msg("surviving rift twin did not enrage after sibling died")
	twin_b.take_hit(999, Vector2(500, 320))
	await process_frame
	if main._boss_box.visible:
		_fail_msg("boss bar stayed visible after both twins died")
	print("[selftest] rift twins enrage & boss bar ok")

	# Test Star Arbiter boss spawn & kill
	main.wave = 15
	var arbiter: Enemy = main._materialize_enemy(Enemy.Kind.BOSS_ARBITER, Vector2(360, 260))
	if not main._boss_box.visible:
		_fail_msg("arbiter boss bar not visible")
	arbiter.take_hit(999, Vector2(360, 320))
	await process_frame
	print("[selftest] star arbiter ok")

	# Test pickup overdrive
	main._spawn_pickup(Pickup.Kind.OVERDRIVE, main.player.global_position)
	await process_frame
	await process_frame
	if main.player.overdrive_timer <= 0.0:
		_fail_msg("overdrive pickup did not activate")
	print("[selftest] pickup overdrive ok")

	# Test upgrade draft + free reroll
	main._open_upgrade_choice()
	if main.state != main.State.UPGRADE_CHOICE or not main._upgrade_panel.visible or main._rerolls_left != 1:
		_fail_msg("upgrade overlay or reroll state invalid")
	main._on_reroll_upgrades()
	if main._rerolls_left != 0 or main._upgrade_cards_box.get_child_count() < 1:
		_fail_msg("reroll failed")
	var first_id := str(main._current_choices[0]["id"])
	var wave_before: int = main.wave
	main._select_upgrade(first_id)
	if main.state != main.State.PLAYING or main._upgrade_panel.visible or main.wave != wave_before + 1:
		_fail_msg("selecting upgrade did not resume into next wave")
	print("[selftest] upgrade draft + reroll ok: picked=%s wave=%d" % [first_id, main.wave])

	# Reset settings cleanly
	if save_data != null:
		save_data.set_selected_ship("vanguard")
		save_data.set_auto_fire(false)

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


func _test_ships_and_synergies() -> void:
	if ShipCatalog.SHIPS.size() != 3:
		_fail_msg("expected 3 ships")
	var u := UpgradeSystem.new()
	u.reset("starcore")
	if u.pierce_count() != 1 or u.crit_chance() < 0.17:
		_fail_msg("starcore base stats mismatch")
	u.apply("multishot")
	var preview := u.would_activate_synergies("ricochet")
	if preview.is_empty() or str(preview[0]["id"]) != "thunder_blaze":
		_fail_msg("would_activate_synergies missed thunder_blaze")
	var applied := u.apply("ricochet")
	if not u.has_synergy("thunder_blaze") or applied.get("new_synergies", []).is_empty():
		_fail_msg("thunder_blaze failed to activate")
	u.apply("pierce")
	u.apply("crit")
	if not u.has_synergy("focus_beam"):
		_fail_msg("focus_beam failed to activate")
	print("[selftest] ships & synergies ok")


func _test_wave_director() -> void:
	if WaveDirector.boss_archetype(5) != Enemy.Kind.BOSS:
		_fail_msg("wave 5 archetype mismatch")
	if WaveDirector.boss_archetype(10) != Enemy.Kind.BOSS_TWIN:
		_fail_msg("wave 10 archetype mismatch")
	if WaveDirector.boss_archetype(15) != Enemy.Kind.BOSS_ARBITER:
		_fail_msg("wave 15 archetype mismatch")
	var w10 := WaveDirector.build_queue(10)
	if w10.count(Enemy.Kind.BOSS_TWIN) != 2:
		_fail_msg("wave 10 should spawn 2 BOSS_TWIN")
	print("[selftest] wave director ok")


func _test_update_semver() -> void:
	if not UpdateChecker.is_newer("v2.1.1", "2.1.0"):
		_fail_msg("semver failed 2.1.1 > 2.1.0")
	if UpdateChecker.is_newer("v2.1.0", "2.1.0") or UpdateChecker.is_newer("v2.0.9", "2.1.0"):
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
	var fire_pos: Vector2 = pad.btn_fire.position + pad.btn_fire.size * 0.5
	var special_pos: Vector2 = pad.btn_special.position + pad.btn_special.size * 0.5
	var miss_pos := Vector2(float(pad.size.x) - 10.0, 10.0)

	pad.debug_apply_touch(0, true, joy_pos)
	if pad.move_vec.length() < 0.01:
		pad.debug_apply_drag(0, Vector2(160, 80))
	if pad.move_vec.length() < 0.2:
		_fail_msg("floating joystick touch+drag did not produce move_vec, got %s" % pad.move_vec)
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
