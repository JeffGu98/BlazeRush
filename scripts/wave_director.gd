extends RefCounted
class_name WaveDirector

## Builds wave compositions with progressive enemy variety and 3 rotating Boss archetypes every 5th wave.

static func is_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % 5 == 0


static func boss_archetype(wave: int) -> int:
	# Wave 5 -> Blaze Lord, Wave 10 -> Rift Twins, Wave 15 -> Astral Arbiter, cycling cleanly.
	var idx := (maxi(1, int(wave / 5)) - 1) % 3
	match idx:
		0:
			return Enemy.Kind.BOSS
		1:
			return Enemy.Kind.BOSS_TWIN
		_:
			return Enemy.Kind.BOSS_ARBITER


static func boss_title(wave: int) -> String:
	var tier := maxi(1, int(wave / 5))
	match boss_archetype(wave):
		Enemy.Kind.BOSS_TWIN:
			return "裂空双子 · Lv.%d" % tier
		Enemy.Kind.BOSS_ARBITER:
			return "星穹裁决者 · Lv.%d" % tier
		_:
			return "烈焰领主 · Lv.%d" % tier


static func build_queue(wave: int) -> Array[int]:
	var q: Array[int] = []
	if is_boss_wave(wave):
		var bkind := boss_archetype(wave)
		if bkind == Enemy.Kind.BOSS_TWIN:
			q.append(Enemy.Kind.BOSS_TWIN)
			q.append(Enemy.Kind.BOSS_TWIN)
		else:
			q.append(bkind)
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
		return 1.25
	return maxf(0.24, 0.60 - float(wave) * 0.024)
