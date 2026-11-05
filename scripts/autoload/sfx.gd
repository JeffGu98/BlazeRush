extends Node

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _ready_played := false

func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_load("shoot", "res://assets/sfx/shoot.wav")
	_load("hit", "res://assets/sfx/hit.wav")
	_load("die", "res://assets/sfx/die.wav")
	_load("hurt", "res://assets/sfx/hurt.wav")
	_load("ready", "res://assets/sfx/ready.wav")
	_load("nova", "res://assets/sfx/nova.wav")
	_load("click", "res://assets/sfx/click.wav")
	_load("wave", "res://assets/sfx/wave.wav")
	_load("over", "res://assets/sfx/over.wav")
	_load("combo", "res://assets/sfx/combo.wav")

func _load(key: String, path: String) -> void:
	var s := load(path)
	if s:
		_streams[key] = s

func play(key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _streams.has(key):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[key]
			p.pitch_scale = clampf(pitch, 0.5, 2.0)
			p.volume_db = volume_db
			p.play()
			return
	# steal first
	var p2: AudioStreamPlayer = _players[0]
	p2.stream = _streams[key]
	p2.pitch_scale = clampf(pitch, 0.5, 2.0)
	p2.volume_db = volume_db
	p2.play()

func play_ready_once() -> void:
	if _ready_played:
		return
	_ready_played = true
	play("ready", 1.0, -2.0)

func reset_ready() -> void:
	_ready_played = false
