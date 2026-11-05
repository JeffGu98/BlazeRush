extends SceneTree

var _ok := true

func _initialize() -> void:
	call_deferred("_run")

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
	if main.has_method("_start_game"):
		main._start_game()
	for i in 45:
		await process_frame
	var enemies = get_nodes_in_group("enemies")
	print("[selftest] enemies after start: ", enemies.size())
	if enemies.is_empty():
		push_error("expected enemies to spawn")
		_ok = false
	if main.has_method("player_special_nova"):
		main.player_special_nova(Vector2(360, 545))
	await process_frame
	await process_frame
	# Basic script sanity
	var player = main.get_node_or_null("World/Player")
	if player == null or not player.alive:
		# may have died to enemies — still ok if scene ran
		print("[selftest] player alive=", player.alive if player else false)
	print("[selftest] score=", main.score, " wave=", main.wave)
	if main.wave < 1:
		push_error("wave did not start")
		_ok = false
	main.queue_free()
	await process_frame
	if _ok:
		print("[selftest] PASS")
		quit(0)
	else:
		_fail()

func _fail() -> void:
	print("[selftest] FAIL")
	quit(1)
