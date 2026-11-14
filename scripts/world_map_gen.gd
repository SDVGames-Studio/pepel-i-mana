# Часть: карта мира — генерация: сид, гидрология (море/реки/влажность),
# озёра и болота, биом-регионы. Один класс, поведение не меняется.
extends "res://scripts/world_map_base.gd"

func generate(seed_value: int, params: Dictionary) -> void:
	cfg = params
	w = int(params["map_w"])
	h = int(params["map_h"])
	# v1.43: автотесты гоняют малые карты (CI — десятки генераций)
	if OS.has_environment("PEPEL_TEST_MAPS"):
		w = mini(w, 72)
		h = mini(h, 52)
	ts = int(params["tile_size"])
	gen_seed = seed_value
	_terrain_bake = null   # карта новая — кэш рельефа устарел
	_rng.seed = seed_value
	for attempt in 20:
		var _t0 := Time.get_ticks_msec()
		_generate_once(seed_value + attempt * 977, params)
		var _t1 := Time.get_ticks_msec()
		if OS.get_environment("GEN_DEBUG") != "":
			print("[world] attempt %d: %d ms, pois_ok=%s" % [attempt, _t1 - _t0, _pois_ok()])
		if _pois_ok():
			break
	_place_epicenter()
	_setup_fog()
	astar_ready = false   # v1.68: A* лениво, первым tile_path (генерация -0.9 с)


func _generate_once(seed_value: int, params: Dictionary) -> void:
	_rng.seed = seed_value
	w = int(params["map_w"])
	h = int(params["map_h"])
	grid = []
	for y in h:
		var row := []
		row.resize(w)
		row.fill(TILE_PLAINS)
		grid.append(row)
	var hcfg: Dictionary = params.get("hydro", {})
	region = {}
	# режим моря — рандом мира (ответ №118: «океан по краю ИЛИ внутренние
	# моря — случайно»): веса в world.json → regions.sea_modes
	sea_mode = _roll_sea_mode()
	# гидрология («Мир v2»): высоты → скалы → море → реки → город →
	# влажность → озёра/болота; лес/пепел — блобами, как раньше
	_build_heights(hcfg)
	_build_hills(hcfg)
	_build_sea(hcfg)
	_build_rivers(hcfg)
	# город: от центра, приоритет — тайл с рекой («город на клетке с рекой»)
	city_tile = _pick_city_tile(hcfg)
	_clear_around_land(city_tile, 2)
	_build_moisture(hcfg)
	_build_lakes_swamps(hcfg)
	# пятна леса и пепла (не поверх воды/болот/русел)
	var blobs: Dictionary = params.get("blobs", {})
	var radii: Dictionary = params.get("blob_radius", {})
	var kinds := {"forest": TILE_FOREST, "waste": TILE_WASTE}
	for key in blobs:
		if not kinds.has(key):
			continue
		for i in int(blobs[key]):
			var r: Array = radii.get(key, [3, 5])
			_blob(_random_inner_tile(), _rng.randi_range(int(r[0]), int(r[1])), kinds[key])
	# биом-регионы («Мир v2» этап 2): снег/вулкан/пустыня/мёртвель —
	# поверх суши, после пятен (мёртвель любит пепелища)
	_build_regions(params.get("regions", {}))
	pois = []
	_poi_id = 1
	_place_pois(params)
	_draw_roads()


## Пятно круглой формы (как в city_map.gd). v2: вода/болото/русло не затираем —
## гидрология важнее декоративного пятна леса/пепла.
func _blob(center: Vector2i, radius: int, kind: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var t := Vector2i(x, y)
			if Vector2(x, y).distance_to(Vector2(center)) <= radius:
				if grid[y][x] == TILE_WATER or grid[y][x] == TILE_SWAMP or river.has(t):
					continue
				grid[y][x] = kind


## Очистка вокруг города (v2): лес/скалы/пепел → равнина, ГИДРОЛОГИЮ (воду,
## болота, русло) сохраняем — окрестности города на глобале показывают свои
## водоёмы, и клетка несёт их в локацию города.
func _clear_around_land(center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var t: int = grid[y][x]
			if t == TILE_WATER or t == TILE_SWAMP:
				continue
			grid[y][x] = TILE_PLAINS


func _random_inner_tile() -> Vector2i:
	return Vector2i(_rng.randi_range(4, w - 5), _rng.randi_range(4, h - 5))


# --- гидрология («Мир v2», этап 1) ------------------------------------------
# Высоты: value-noise крупными ячейками + общий наклон N→S (север высок,
# юг низ — реки потекут к морю на юге). Ответ №117: «по рельефу
# (общий наклон N→S + меандры)».

func _build_heights(hcfg: Dictionary) -> void:
	var cell := int(hcfg.get("noise_cell", 9))
	var gw := int(ceil(w / float(cell))) + 2
	var gh := int(ceil(h / float(cell))) + 2
	var gvals: Array = []
	for j in gh:
		var row := []
		for i in gw:
			row.append(_rng.randf())
		gvals.append(row)
	height = []
	var slope_top := float(hcfg.get("slope_top", 0.72))
	var slope_bot := float(hcfg.get("slope_bot", 0.18))
	for y in h:
		var fy := float(y) / cell
		var j0 := int(fy)
		var ty := _smooth_step(fy - j0)
		var row := []
		row.resize(w)
		for x in w:
			var fx := float(x) / cell
			var i0 := int(fx)
			var tx := _smooth_step(fx - i0)
			var a: float = gvals[j0][i0]
			var b: float = gvals[j0][i0 + 1]
			var c: float = gvals[j0 + 1][i0]
			var d: float = gvals[j0 + 1][i0 + 1]
			var noise := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
			var base := lerpf(slope_top, slope_bot, float(y) / float(maxi(1, h - 1)))
			row[x] = clampf(base * 0.72 + noise * 0.28, 0.0, 1.0)
		height.append(row)



func height_at(p: Vector2i) -> float:
	if not in_bounds(p):
		return 0.0
	return float(height[p.y][p.x])


## Скалы/холмы — по высоте: северная гряда + пятна на возвышенностях.
## На юге (ниже порога) — редкие останцы-островки, чтобы рельеф юга не был
## плоской скатертью.
func _build_hills(hcfg: Dictionary) -> void:
	var threshold := float(hcfg.get("hill_threshold", 0.62))
	for y in h:
		for x in w:
			if float(height[y][x]) > threshold:
				grid[y][x] = TILE_HILL
	var outliers := _rng.randi_range(0, 2)
	for i in outliers:
		var c := Vector2i(_rng.randi_range(4, w - 5), _rng.randi_range(int(h * 0.55), h - 6))
		var r := _rng.randi_range(1, 2)
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				if Vector2(x, y).distance_to(Vector2(c)) <= r:
					grid[y][x] = TILE_HILL


## Режим моря этого мира: взвешенный бросок по regions.sea_modes.
func _roll_sea_mode() -> String:
	var weights: Dictionary = cfg.get("regions", {}).get("sea_modes",
			{"ocean": 1, "inner": 1, "both": 2})
	var total := 0
	for k in weights:
		total += maxi(0, int(weights[k]))
	var roll := _rng.randi_range(0, maxi(1, total) - 1)
	for k: String in weights:
		roll -= maxi(0, int(weights[k]))
		if roll < 0:
			return k
	return "both"


## Море (ответ №118: «океан по краю ИЛИ внутренние моря — рандом мира»,
## режим выбран в _roll_sea_mode): океан — волнистая полоса на юге;
## внутренние моря — большие пятна воды на низинах; both — и то и другое.
func _build_sea(hcfg: Dictionary) -> void:
	water_kind = {}
	if sea_mode != "inner":
		var range: Array = hcfg.get("sea_width", [2, 4])
		var widths: Array = []
		for x in w:
			widths.append(float(_rng.randi_range(int(range[0]), int(range[1]))))
		# сгладить кромку скользящим средним — берег волнистый, без «пилы»
		for x in w:
			var s := 0.0
			var n := 0
			for dx in range(-2, 3):
				var nx := clampi(x + dx, 0, w - 1)
				s += float(widths[nx])
				n += 1
			widths[x] = s / float(n)
		for x in w:
			var wd := int(round(widths[x]))
			for y in range(h - wd, h):
				grid[y][x] = TILE_WATER
				water_kind[Vector2i(x, y)] = "sea"
	# внутренние моря на низинах; мир «inner» гарантирует хотя бы одно
	var lo := int(hcfg.get("inner_seas_min", 0))
	var hi := int(hcfg.get("inner_seas_max", 2))
	if sea_mode == "inner":
		lo = maxi(1, lo)
		hi = maxi(lo, hi + 1)
	var seas := _rng.randi_range(lo, hi)
	for i in seas:
		var cands: Array = []
		for y in range(int(h * 0.3), h - 5):
			for x in range(3, w - 4):
				if float(height[y][x]) < float(hcfg.get("sea_level", 0.30)) and grid[y][x] == TILE_PLAINS:
					cands.append(Vector2i(x, y))
		if cands.is_empty():
			continue
		var center: Vector2i = cands[_rng.randi_range(0, cands.size() - 1)]
		var rad: Array = hcfg.get("sea_radius", [3, 5])
		_water_blob(center, _rng.randi_range(int(rad[0]), int(rad[1])), "sea")


## Пятно воды (море/озеро): grid-вода + тип; через болото не льём.
func _water_blob(center: Vector2i, radius: int, kind: String) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if Vector2(x, y).distance_to(Vector2(center)) <= radius:
				grid[y][x] = TILE_WATER
				water_kind[Vector2i(x, y)] = kind


## Реки: 1..3 русла из северных скал к морю — жадный спуск по высотам
## со случайным меандром (ответ №117). Главная река стартует ближе всех
## к центру и меандрирует слабее — город часто стоит на ней. Русло —
## оверлей: тайл проходим (брод на глобали), но дороже; grid не меняется.
func _build_rivers(hcfg: Dictionary) -> void:
	river = {}
	var count := _rng.randi_range(int(hcfg.get("rivers_min", 1)), int(hcfg.get("rivers_max", 3)))
	for i in count:
		var main := i == 0
		var start := _river_start(main, hcfg)
		_flow_river(start, float(hcfg.get("meander", 0.35)) * (0.7 if main else 1.0))


## Старт русла: скальный тайл в верхней половине; главная река — самый
## близкий к центральной оси из горстки кандидатов. Фолбэки: любой холм →
## самое высокое место верхней трети.
func _river_start(main: bool, hcfg: Dictionary) -> Vector2i:
	var band := int(hcfg.get("main_band", 9))
	var cands: Array = []
	var any_hill: Array = []
	for y in range(2, int(h * 0.45)):
		for x in w:
			if grid[y][x] != TILE_HILL:
				continue
			any_hill.append(Vector2i(x, y))
			if not main or absi(x - w / 2) <= band:
				cands.append(Vector2i(x, y))
	if cands.is_empty():
		cands = any_hill
	if not cands.is_empty():
		if not main:
			return cands[_rng.randi_range(0, cands.size() - 1)]
		# главная: кандидаты по близости к центру, берём из пятёрки лучших
		cands.sort_custom(func(a, b) -> bool:
			return absi(int(a.x) - w / 2) < absi(int(b.x) - w / 2))
		var top := mini(5, cands.size())
		return cands[_rng.randi_range(0, top - 1)]
	# скал нет — самое высокое место верхней трети
	var best := Vector2i(w / 2, 2)
	var best_h := -1.0
	for y in range(2, int(h * 0.33)):
		for x in w:
			if float(height[y][x]) > best_h:
				best_h = float(height[y][x])
				best = Vector2i(x, y)
	return best


## Течёт, пока не дойдёт до воды (устье), другого русла (приток) или края.
## Самопересечения штрафуются (меандр может завивать русло петлёй), обрыв —
## только если русло окружило само себя целиком.
func _flow_river(start: Vector2i, meander: float) -> void:
	var max_len := int(h * 2.2)
	var pos := start
	var last := Vector2i(0, 1)
	var steps := 0
	var own := {}   # тайлы ЭТОГО русла
	var dirs := [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1),
			Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(0, -1)]
	while steps < max_len and in_bounds(pos):
		if grid[pos.y][pos.x] == TILE_WATER:
			break   # устье: море или озеро
		if river.has(pos) and steps > 0:
			break   # приток в другую реку
		river[pos] = true
		own[pos] = true
		steps += 1
		var best := Vector2i.ZERO
		var best_score := 9.0
		var boxed := true
		for d: Vector2i in dirs:
			var n := pos + d
			if not in_bounds(n):
				continue
			var score := float(height[n.y][n.x]) + _rng.randf() * meander
			if d.y < 0:
				score += 0.22   # река стремится на юг, к морю
			if d == -last:
				score += 0.45   # не разворачиваться на 180°
			if own.has(n):
				score += 0.60   # не завиваться в себя петлёй
				if river.has(n):
					score += 10.0   # свой пройденный тайл — почти стена
			else:
				boxed = false
			if score < best_score:
				best_score = score
				best = d
		if best == Vector2i.ZERO or boxed:
			break
		last = best
		pos += best


## Влажность: юг влажнее + рядом с водой (море/озеро/русло) — по ней
## распределяются озёра и болота («озёра/болота по влажности», директива).
func _build_moisture(hcfg: Dictionary) -> void:
	var cell := int(hcfg.get("noise_cell", 9))
	var gw := int(ceil(w / float(cell))) + 2
	var gh := int(ceil(h / float(cell))) + 2
	var gvals: Array = []
	for j in gh:
		var row := []
		for i in gw:
			row.append(_rng.randf())
		gvals.append(row)
	_moist = []
	for y in h:
		var fy := float(y) / cell
		var j0 := int(fy)
		var ty := _smooth_step(fy - j0)
		var row := []
		row.resize(w)
		for x in w:
			var fx := float(x) / cell
			var i0 := int(fx)
			var tx := _smooth_step(fx - i0)
			var a: float = gvals[j0][i0]
			var b: float = gvals[j0][i0 + 1]
			var c: float = gvals[j0 + 1][i0]
			var d: float = gvals[j0 + 1][i0 + 1]
			var noise := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
			var base := lerpf(0.30, 0.62, float(y) / float(maxi(1, h - 1)))
			row[x] = base * 0.7 + noise * 0.3
		_moist.append(row)
	# близость к воде поднимает влажность (радиус 2)
	for y in h:
		for x in w:
			var t := Vector2i(x, y)
			if grid[y][x] != TILE_WATER and not river.has(t):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var n := t + Vector2i(dx, dy)
					if in_bounds(n):
						_moist[n.y][n.x] += 0.09 * float(3 - maxi(absi(dx), absi(dy)))




## Озёра — низины с высокой влажностью; болота — влажные низины рядом
## с водой/русами. Оба не ближе 2 тайлов к городу (город не в воде),
## но могут оказаться в 2–3 — тогда клетка города унаследует их.
func _build_lakes_swamps(hcfg: Dictionary) -> void:
	var lake_n := _rng.randi_range(int(hcfg.get("lakes_min", 0)), int(hcfg.get("lakes_max", 3)))
	var swamp_n := _rng.randi_range(int(hcfg.get("swamps_min", 2)), int(hcfg.get("swamps_max", 5)))
	var lake_cands: Array = []
	var swamp_cands: Array = []
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var t := Vector2i(x, y)
			if grid[y][x] != TILE_PLAINS or river.has(t):
				continue
			if Vector2(t).distance_to(Vector2(city_tile)) < 2.0:
				continue
			var ht := float(height[y][x])
			var mo := float(_moist[y][x])
			if ht > 0.22 and ht < 0.55 and mo > float(hcfg.get("lake_moist", 0.60)):
				lake_cands.append(t)
			if ht < float(hcfg.get("swamp_height", 0.50)) and mo > float(hcfg.get("swamp_moist", 0.58)):
				swamp_cands.append(t)
	for i in lake_n:
		if lake_cands.is_empty():
			break
		var c: Vector2i = lake_cands[_rng.randi_range(0, lake_cands.size() - 1)]
		var rad: Array = hcfg.get("lake_radius", [2, 4])
		_water_blob(c, _rng.randi_range(int(rad[0]), int(rad[1])), "lake")
	for i in swamp_n:
		if swamp_cands.is_empty():
			break
		var c: Vector2i = swamp_cands[_rng.randi_range(0, swamp_cands.size() - 1)]
		var rad: Array = hcfg.get("swamp_radius", [2, 3])
		_swamp_blob(c, _rng.randi_range(int(rad[0]), int(rad[1])))


## Болото — пятна проходимой топи (не поверх воды).
func _swamp_blob(center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if Vector2(x, y).distance_to(Vector2(center)) <= radius and grid[y][x] != TILE_WATER:
				grid[y][x] = TILE_SWAMP


## Город: спираль от центра, приоритет — тайл с рекой (город на реке —
## река повторится в локации, ответ №117). Не вода и не болото.
func _pick_city_tile(hcfg: Dictionary) -> Vector2i:
	var center := Vector2i(w / 2, h / 2)
	var radius := int(hcfg.get("city_pick_radius", 7))
	var fallback := center
	for r in range(radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t := center + Vector2i(dx, dy)
				if not in_bounds(t) or grid[t.y][t.x] == TILE_WATER or grid[t.y][t.x] == TILE_SWAMP:
					continue
				if river.has(t):
					return t
				if t == center or fallback == center:
					fallback = t
	return fallback


## Гидро-контекст клетки города для генерации локации города:
## река на самом тайле; озеро в соседней клетке (город на берегу);
## болото в радиусе 3. Локация повторяет эти водоёмы (директива «Мир v2»).
func city_hydro() -> Dictionary:
	return tile_hydro(city_tile)


## Гидро-контекст произвольной клетки мира (v1.41, «Мир v2» этап 3):
## поселения НПС несут свои водоёмы в локацию по тем же правилам, что
## город игрока (река на клетке = река в поселении).
func tile_hydro(tile: Vector2i) -> Dictionary:
	var out := {"river": river.has(tile), "lake": false, "swamp": false}
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n := tile + d
		if in_bounds(n) and grid[n.y][n.x] == TILE_WATER \
				and String(water_kind.get(n, "lake")) == "lake":
			out["lake"] = true
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var n := tile + Vector2i(dx, dy)
			if in_bounds(n) and grid[n.y][n.x] == TILE_SWAMP:
				out["swamp"] = true
	return out


# --- биом-регионы («Мир v2», этап 2, v1.40) ---------------------------------

## Снег на севере, вулкан у скал, пустыня на сухих низинах, мёртвель —
## у пепелищ и в глуши. Регионы красят сушу (view) и дорожают путь;
## вода/болото не перекрашиваются.
func _build_regions(rcfg: Dictionary) -> void:
	var list: Array = rcfg.get("list", [])
	for entry: Dictionary in list:
		var id := String(entry.get("id", ""))
		var count := _rng.randi_range(int(entry.get("count_min", 1)), int(entry.get("count_max", 1)))
		for i in count:
			var c := _region_center(id, entry)
			if c == Vector2i(-1, -1):
				continue
			var rad: Array = entry.get("radius", [3, 5])
			_region_blob(c, _rng.randi_range(int(rad[0]), int(rad[1])), id)


## Центр региона по его «месту обитания»:
##   snow — север (верхняя половина, желательно высоко);
##   volcanic — высокие земли (у скального порога);
##   desert — сухие низины (влажность ниже порога), юг/центр;
##   dead — глушь с низкой влажностью или рядом с пеплом.
func _region_center(id: String, entry: Dictionary) -> Vector2i:
	var moist_thr := float(entry.get("moist_max", 0.5))
	for attempt in 200:
		var p := _random_inner_tile()
		if not is_walkable(p) or grid[p.y][p.x] == TILE_SWAMP:
			continue
		var ht := float(height[p.y][p.x])
		var mo := float(_moist[p.y][p.x])
		match id:
			"snow":
				if p.y > int(h * 0.45) and ht < 0.55:
					continue
			"volcanic":
				if ht < float(cfg.get("hydro", {}).get("hill_threshold", 0.62)) - 0.08:
					continue
			"desert":
				if mo > moist_thr or p.y < int(h * 0.2):
					continue
			"dead":
				if mo > moist_thr and not _near_tile(p, TILE_WASTE, 3):
					continue
			_:
				pass
		if _poi_near(p, 3) != null:
			continue
		return p
	return Vector2i(-1, -1)


## Есть ли тайл kind в радиусе r (по клеткам).
func _near_tile(p: Vector2i, kind: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := p + Vector2i(dx, dy)
			if in_bounds(n) and grid[n.y][n.x] == kind:
				return true
	return false


## Залить регион: суша (не вода/болото) в радиусе; кромка с мягкой
## гармонической рябью (как у водоёмов) — не «вырезанные круги».
func _region_blob(center: Vector2i, radius: int, id: String) -> void:
	var ph1 := _rng.randf() * TAU
	var ph2 := _rng.randf() * TAU
	var a1 := _rng.randf_range(0.10, 0.20)
	var a2 := _rng.randf_range(0.06, 0.12)
	for y in range(center.y - radius * 2, center.y + radius * 2 + 1):
		for x in range(center.x - radius * 2, center.x + radius * 2 + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var dx := float(x - center.x) / float(radius)
			var dy := float(y - center.y) / float(radius)
			if dx * dx + dy * dy > 4.0:
				continue
			var ang := atan2(float(y - center.y), float(x - center.x))
			var k := 1.0 + a1 * sin(2.0 * ang + ph1) + a2 * sin(3.0 * ang + ph2)
			if dx * dx + dy * dy > k * k:
				continue
			var t := Vector2i(x, y)
			if grid[y][x] == TILE_WATER or grid[y][x] == TILE_SWAMP:
				continue
			region[t] = id


func region_at(p: Vector2i) -> String:
	return String(region.get(p, ""))


## Определение региона (цвета/множитель цены) из world.json.
func region_def(id: String) -> Dictionary:
	for entry: Dictionary in cfg.get("regions", {}).get("list", []):
		if String(entry.get("id", "")) == id:
			return entry
	return {}


## Случайный проходимый тайл (страховка генерации POI); не русло реки.
func _walkable_random() -> Vector2i:
	for attempt in 300:
		var p := _random_inner_tile()
		if is_walkable(p) and not river.has(p):
			return p
	return city_tile


