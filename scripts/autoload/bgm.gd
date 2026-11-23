extends Node

const TITLE_DB := -13.0
const PLAY_DB := -8.5
const OVER_DB := -16.0

var _player: AudioStreamPlayer
var _tween: Tween

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = TITLE_DB
	add_child(_player)
	var stream: Resource = load("res://assets/music/blaze_theme.ogg")
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_player.stream = stream
	_player.play()

func to_title() -> void:
	_fade_to(TITLE_DB)

func to_play() -> void:
	_fade_to(PLAY_DB)
	if _player and not _player.playing and _player.stream:
		_player.play()

func to_gameover() -> void:
	_fade_to(OVER_DB)

func _fade_to(db: float) -> void:
	if _player == null:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", db, 0.45)

func stop() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	if _player:
		_player.stop()
		_player.stream = null

func _exit_tree() -> void:
	stop()
