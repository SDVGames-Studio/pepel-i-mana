extends RefCounted
## Следы на карте города (v2.2 «Следы, алтарь благодати, тайные лагеря»).
## Все ходячие (жители, звери, мутанты, ищейки, путники) оставляют следы:
## {pos: Vector2, t: float, who: String, dir: Vector2}. Следы тают со
## временем (дождь ускоряет — life умножается на RAIN_MULT). Читают:
## ищейки мутантов (цепочка ведёт к городу), охотники города (ведут к
## логову/лагерю), герой («идти по следу»). Следы героя живут отдельно
## (sim.hero_tracks — скауты улья читают их как раньше).
## ЧИСТАЯ логика — тестируется headless. По образцу HiveSim.

const RAIN_MULT := 0.55          # во сколько раз короче жизнь следа под дождём
const MIN_STEP := 24.0           # минимальный шаг между следами, px (FPS/память)
const CAP := 1200                # общий потолок следов (~пара дней активного города)


## Новый след: отступ от прошлого (чтобы цепочка не слиплась) + потолок.
## dir — нормализованное направление движения (куда смотрит сапог).
static func push(tracks: Array, pos: Vector2, now: float, who: String,
		dir: Vector2, min_step := MIN_STEP, cap := CAP) -> Array:
	if not tracks.is_empty():
		var last: Dictionary = tracks.back()
		if (last["pos"] as Vector2).distance_to(pos) < min_step \
				and String(last["who"]) == who:
			return tracks
	tracks.append({"pos": pos, "t": now, "who": who,
			"dir": dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT})
	while tracks.size() > cap:
		tracks.pop_front()
	return tracks


## Свежий след ближайший к точке (опционально только от who: "").
## Возвращает {} или сам след (словарь по ссылке).
static func near(tracks: Array, center: Vector2, radius_px: float, now: float,
		life: float, who := "") -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for tr in tracks:
		if now - float(tr["t"]) > life:
			continue
		if who != "" and String(tr["who"]) != who:
			continue
		var d: float = (tr["pos"] as Vector2).distance_to(center)
		if d <= radius_px and d < best_d:
			best_d = d
			best = tr
	return best


## Цепочка следов от точки: ближайший свежий, затем каждый следующий в
## радиусе шага дальше по времени (для «идти по следу» — куда ведёт).
## Возвращает массив следов от старого к новому (порядок ходьбы).
static func chain(tracks: Array, from: Vector2, radius_px: float, now: float,
		life: float, who := "", max_len := 12) -> Array:
	var pool: Array = []
	for tr in tracks:
		if now - float(tr["t"]) > life:
			continue
		if who != "" and String(tr["who"]) != who:
			continue
		if (tr["pos"] as Vector2).distance_to(from) <= radius_px * 2.5:
			pool.append(tr)
	pool.sort_custom(func(a, b) -> bool: return float(a["t"]) < float(b["t"]))
	# идём по цепочке: следующий след — не дальше шага от предыдущего
	var out: Array = []
	var cur := from
	for tr in pool:
		if out.size() >= max_len:
			break
		# первый след — старт цепочки (уже в радиусе поиска), дальше — шагами
		if out.is_empty() or (tr["pos"] as Vector2).distance_to(cur) <= radius_px * 2.0:
			out.append(tr)
			cur = tr["pos"]
	return out


## Стереть протухшие следы; возвращает сколько стёрто (для летописи/теста).
static func prune(tracks: Array, now: float, life: float) -> int:
	var gone := 0
	var i := 0
	while i < tracks.size():
		if now - float(tracks[i]["t"]) > life:
			tracks.remove_at(i)
			gone += 1
			continue
		i += 1
	return gone
