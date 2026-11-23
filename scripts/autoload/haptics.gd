extends Node

var _cooldown_until_ms: int = 0

func pulse(ms: int, amplitude: float = 0.5) -> void:
	if ms <= 0:
		return
	var now := Time.get_ticks_msec()
	if now < _cooldown_until_ms:
		return
	Input.vibrate_handheld(ms, clampf(amplitude, 0.0, 1.0))
	_cooldown_until_ms = now + maxi(ms, 30)

func hit() -> void:
	pulse(14, 0.35)

func kill(heavy: bool = false) -> void:
	if heavy:
		pulse(42, 0.8)
	else:
		pulse(28, 0.55)

func hurt() -> void:
	pulse(55, 0.8)

func nova() -> void:
	pulse(95, 1.0)

func ready_special() -> void:
	pulse(18, 0.45)
