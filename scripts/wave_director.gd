extends RefCounted
class_name WaveDirector

## Builds wave compositions with progressive enemy variety and Boss waves every 5th wave.

static func is_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % 5 == 0


static func build_queue(wave: int) -> Array[int]:
	var q: Array[int] = []
	if is_boss_wave(wave):
		q.append(Enemy.Kind.BOSS)
		var escorts := 2 + mini(wave / 5, 4)
		for i in escorts:
			q.append(Enemy.Kind.CHASER if i % 2 == 0 else Enemy.Kind.SHOOTER)
		return q

	var chasers := 3 + wave + int(wave / 3)
	var shooters := 1 + int(wave / 2)
	var dashers := 0 if wave < 2 else 1 + int((wave - 2) / 2)
	var bruisers := 0 if wave < 3 else 1 + int((wave - 3) / 3)
	var splitters := 0 if wave < 4 else 1 + int((wave - 4) / 3)

	for _i in chasers:
		q.append(Enemy.Kind.CHASER)
	for _i in shooters:
		q.append(Enemy.Kind.SHOOTER)
	for _i in dashers:
		q.append(Enemy.Kind.DASHER)
	for _i in bruisers:
		q.append(Enemy.Kind.BRUISER)
	for _i in splitters:
		q.append(Enemy.Kind.SPLITTER)
	q.shuffle()
	return q


static func spawn_interval(wave: int) -> float:
	if is_boss_wave(wave):
		return 1.35
	return maxf(0.24, 0.62 - float(wave) * 0.025)
