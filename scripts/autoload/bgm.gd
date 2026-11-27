extends Node

const TITLE_DB := -13.0
const PLAY_DB := -8.5
const BOSS_DB := -6.5
const OVER_DB := -16.0
const MUTED_DB := -80.0

var _player: AudioStreamPlayer
var _tween: Tween
var _target_db: float = TITLE_DB


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.volume_db = MUTED_DB if SaveData.bgm_muted else TITLE_DB
	add_child(_player)
	var stream: Resource = load("res://assets/music/blaze_theme.ogg")
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_player.stream = stream
	if not SaveData.bgm_muted:
		_player.play()


func to_title() -> void:
	_target_db = TITLE_DB
	_apply_volume(0.45)


func to_play() -> void:
	_target_db = PLAY_DB
	_apply_volume(0.45)


func to_boss() -> void:
	_target_db = BOSS_DB
	_apply_volume(0.35)


func to_gameover() -> void:
	_target_db = OVER_DB
	_apply_volume(0.5)


func refresh_mute() -> void:
	_apply_volume(0.18)


func _apply_volume(dur: float) -> void:
	if _player == null:
		return
	if _tween:
		_tween.kill()
		_tween = null
	if SaveData.bgm_muted:
		_player.volume_db = MUTED_DB
		if _player.playing:
			_player.stop()
		return
	if not _player.playing and _player.stream != null:
		_player.volume_db = MUTED_DB
		_player.play()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", _target_db, dur)


func stop() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	if _player:
		_player.stop()
		_player.stream = null


func _exit_tree() -> void:
	stop()
