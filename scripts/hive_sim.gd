extends RefCounted
## Улей мутантов («Новый мир v2», этап 2, директива заказчика 2026-11-03):
## мутанты городской аномалии строят своё поселение — улей. Роли (по
## прототипу F:/kust/new-world-v-2): скауты ищут ресурсы и следы героя,
## добытчики носят в улей, стражи охраняют. Запас ресурсов растит уровень
## улья → шире радиусы, больше ролей, сильнее волны на город. Улей можно
## разорить — награда; через N дней аномалия отстраивает новый.
## ЧИСТАЯ логика уровней/волн — тестируется headless. Конфиг —
## balance.json → "hive".

const LEVELS := [60, 160, 320]      # запас ресурсов для уровня 2/3/4
const RADIUS_BASE := 14.0           # радиус поиска ресурсов, тайлы
const RADIUS_PER_LEVEL := 6.0
const WAVE_DAYS := 2.5              # раз в сколько дней улей шлёт волну
const WAVE_BASE := 2
const WAVE_PER_LEVEL := 1
const WAVE_STOCK_DIV := 60          # +1 мутант за каждые N запаса
const HP := 150
const RESPAWN_DAYS := 10
const START_DAY := 4
const GUARDS := 2
const GATHERERS := 3
const SCOUTS := 1
const GATHER_PER_TRIP := 3
const TRACK_LIFE := 120.0           # жизнь следа героя, сек


## Уровень улья по запасу (1..1+len).
static func level_for(stock: int) -> int:
	var level := 1
	for need in LEVELS:
		if stock >= int(need):
			level += 1
	return level


## Радиус поиска ресурсов (тайлы) на уровне.
static func radius_for(level: int) -> float:
	return RADIUS_BASE + float(level - 1) * RADIUS_PER_LEVEL


## Число ролей на уровне: [стражи, добытчики, скауты].
static func roles_for(level: int) -> Array:
	return [GUARDS + level - 1, GATHERERS + (level - 1) * 2, SCOUTS + (level - 1) / 2]


## Размер волны: база + уровень + бонус за накопленный запас (успех сбора).
static func wave_size(level: int, stock: int, waves_sent: int) -> int:
	var n := WAVE_BASE + (level - 1) * WAVE_PER_LEVEL + stock / WAVE_STOCK_DIV \
			+ waves_sent / 2
	return clampi(n, 1, 14)


## Период волн сокращается с уровнем (дни): 2.5 → 1.3.
static func wave_days(level: int) -> float:
	return maxf(1.3, WAVE_DAYS - float(level - 1) * 0.4)


## Новый след героя: возвращает обновлённый массив следов (хвост по времени).
## tracks: [{pos: Vector2, t: float}]; старые и далёкие отрезаются снаружи.
static func push_track(tracks: Array, pos: Vector2, now: float, hero_speed_px: float) -> Array:
	if tracks.is_empty():
		tracks.append({"pos": pos, "t": now})
		return tracks
	var last: Vector2 = tracks.back()["pos"]
	if last.distance_to(pos) < hero_speed_px * 0.5:
		return tracks
	tracks.append({"pos": pos, "t": now})
	while tracks.size() > 80:
		tracks.pop_front()
	return tracks


## Свежие следы в радиусе (для скаута): ближайшая точка или Vector2.INF.
static func track_near(tracks: Array, center: Vector2, radius_px: float, now: float) -> Vector2:
	var best := Vector2.INF
	var best_t := -1.0
	for tr in tracks:
		if now - float(tr["t"]) > TRACK_LIFE:
			continue
		var p: Vector2 = tr["pos"]
		if p.distance_to(center) <= radius_px and float(tr["t"]) > best_t:
			best_t = float(tr["t"])
			best = p
	return best


## Награда за разорение улья (в общий пул города).
static func loot_for(level: int) -> Dictionary:
	return {"coins": 20 + level * 10, "crystal": level * 2, "food": level * 4}
