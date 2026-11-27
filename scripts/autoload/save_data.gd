extends Node

const PATH := "user://blazerush_save.cfg"

var best_score: int = 0
var best_wave: int = 0
var best_combo: int = 0
var total_kills: int = 0
var runs_played: int = 0

var bgm_muted: bool = false
var sfx_muted: bool = false
var haptics_enabled: bool = true
var auto_fire: bool = false
var selected_ship: String = "vanguard"


func _ready() -> void:
	load_data()


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		best_score = int(cfg.get_value("stats", "best_score", 0))
		best_wave = int(cfg.get_value("stats", "best_wave", 0))
		best_combo = int(cfg.get_value("stats", "best_combo", 0))
		total_kills = int(cfg.get_value("stats", "total_kills", 0))
		runs_played = int(cfg.get_value("stats", "runs_played", 0))
		bgm_muted = bool(cfg.get_value("settings", "bgm_muted", false))
		sfx_muted = bool(cfg.get_value("settings", "sfx_muted", false))
		haptics_enabled = bool(cfg.get_value("settings", "haptics_enabled", true))
		auto_fire = bool(cfg.get_value("settings", "auto_fire", false))
		selected_ship = str(cfg.get_value("settings", "selected_ship", "vanguard"))


func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "best_score", best_score)
	cfg.set_value("stats", "best_wave", best_wave)
	cfg.set_value("stats", "best_combo", best_combo)
	cfg.set_value("stats", "total_kills", total_kills)
	cfg.set_value("stats", "runs_played", runs_played)
	cfg.set_value("settings", "bgm_muted", bgm_muted)
	cfg.set_value("settings", "sfx_muted", sfx_muted)
	cfg.set_value("settings", "haptics_enabled", haptics_enabled)
	cfg.set_value("settings", "auto_fire", auto_fire)
	cfg.set_value("settings", "selected_ship", selected_ship)
	cfg.save(PATH)


func save_run(score: int, wave: int, max_combo: int = 0, kills: int = 0) -> Dictionary:
	var new_best_score := score > best_score
	var new_best_wave := wave > best_wave
	if new_best_score:
		best_score = score
	if new_best_wave:
		best_wave = wave
	if max_combo > best_combo:
		best_combo = max_combo
	total_kills += maxi(kills, 0)
	runs_played += 1
	save_all()
	return {
		"new_best_score": new_best_score,
		"new_best_wave": new_best_wave,
	}


func set_bgm_muted(muted: bool) -> void:
	bgm_muted = muted
	save_all()


func set_sfx_muted(muted: bool) -> void:
	sfx_muted = muted
	save_all()


func set_haptics_enabled(enabled: bool) -> void:
	haptics_enabled = enabled
	save_all()


func set_auto_fire(enabled: bool) -> void:
	auto_fire = enabled
	save_all()


func set_selected_ship(ship_id: String) -> void:
	selected_ship = ship_id
	save_all()
