extends Node

var _cooldown_until_ms: int = 0


func pulse(ms: int, amplitude: float = 0.5) -> void:
	if not SaveData.haptics_enabled or ms <= 0:
		return
	var now := Time.get_ticks_msec()
	if now < _cooldown_until_ms:
		return
	Input.vibrate_handheld(ms, clampf(amplitude, 0.0, 1.0))
	_cooldown_until_ms = now + maxi(ms, 28)


func hit() -> void:
	pulse(12, 0.32)


func crit() -> void:
	pulse(20, 0.55)


func kill(heavy: bool = false) -> void:
	if heavy:
		pulse(44, 0.82)
	else:
		pulse(26, 0.52)


func pickup() -> void:
	pulse(14, 0.35)


func hurt() -> void:
	pulse(55, 0.85)


func nova() -> void:
	pulse(95, 1.0)


func ready_special() -> void:
	pulse(18, 0.45)
