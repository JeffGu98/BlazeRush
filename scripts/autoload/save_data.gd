extends Node

const PATH := "user://blazerush_save.cfg"
var best_score: int = 0
var best_wave: int = 0

func _ready() -> void:
	load_data()

func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		best_score = int(cfg.get_value("stats", "best_score", 0))
		best_wave = int(cfg.get_value("stats", "best_wave", 0))

func save_run(score: int, wave: int) -> void:
	var changed := false
	if score > best_score:
		best_score = score
		changed = true
	if wave > best_wave:
		best_wave = wave
		changed = true
	if changed:
		var cfg := ConfigFile.new()
		cfg.set_value("stats", "best_score", best_score)
		cfg.set_value("stats", "best_wave", best_wave)
		cfg.save(PATH)
