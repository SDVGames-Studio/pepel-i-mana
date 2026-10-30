extends RefCounted
## Карта мира (M8): процедурная по сиду, биомы цветом, точки интереса (POI),
## туман войны, старые дороги. Чистая логика без сцены — тестируется headless.
## Город игрока — стартовая локация; от него герой выходит на карту и входит назад.
##
## Тайл: 0 равнина, 1 вода (непроходима), 2 лес, 3 холмы, 4 пепел, 5 старая дорога.
## POI: {id, kind, biome, faction, tile, discovered, strength, state,
##       cleared_day, used} — kind: city|dungeon|ruins|camp|settlement|
##       caravan|obelisk; biome — биом данжа из dungeon.json ("" у городской
##       аномалии, она выбирает биом как раньше); faction — traders|bandits|cult.
##
## Гидрология («Мир v2», этап 1): карта высот (наклон N→S + шум) → скалы
## на севере, океан на юге + внутренние моря, реки из скал к морю (жадный
## спуск + меандр), озёра/болота по влажности. Река — ОВЕРЛЕЙ (river):
## тайл остаётся сушей и проходим (брод), но дороже; grid-вода (море/озёра)
## непроходима, как раньше. Клетка города несёт свои водоёмы в локацию
## города — city_hydro() (река на глобале = река в городе, ответ №117).

const TILE_PLAINS := 0
const TILE_WATER := 1
const TILE_FOREST := 2
const TILE_HILL := 3
const TILE_WASTE := 4
const TILE_ROAD := 5
const TILE_SWAMP := 6   # болото (M14-I): проходимо, но дорого — замедление

var w := 0
var h := 0
var ts := 32
var cfg: Dictionary = {}
var grid: Array = []
var height: Array = []          # высоты 0..1 (гидрология) — по строкам, как grid
var river: Dictionary = {}      # Vector2i -> true: русло (оверлей, проходим)
var water_kind: Dictionary = {} # Vector2i -> "sea"|"lake": тип grid-воды
var city_tile := Vector2i.ZERO      # город игрока — стартовая локация
var pois: Array = []                # точки интереса, см. шапку
var fog: Dictionary = {}            # Vector2i -> true: исследованные тайлы
var astar: AStarGrid2D = null
var boats_enabled := false   # лодки (M14-I): вода проходима, но медленна
var _terrain_bake = null     # v1.35.1: кэш запечённого рельефа (world_view.gd)
var _rng := RandomNumberGenerator.new()
var _poi_id := 1


## Генерация по сиду: детерминированная (тот же сид — та же карта и POI).
func generate(seed_value: int, params: Dictionary) -> void:
	cfg = params
	w = int(params["map_w"])
	h = int(params["map_h"])
	ts = int(params["tile_size"])
	_terrain_bake = null   # карта новая — кэш рельефа устарел
	_rng.seed = seed_value
	for attempt in 20:
		_generate_once(seed_value + attempt * 977, params)
		if _pois_ok():
			break
	_setup_astar()
	_setup_fog()


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


static func _smooth_step(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


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


## Море (ответ №118: «и океан по краю, и внутренние моря — случайно»):
## океан — волнистая полоса на юге (реки текут к нему с севера); внутренние
## моря — 0..2 больших пятна воды на низинах.
func _build_sea(hcfg: Dictionary) -> void:
	water_kind = {}
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
	# внутренние моря на низинах (случайно при создании мира)
	var seas := _rng.randi_range(int(hcfg.get("inner_seas_min", 0)), int(hcfg.get("inner_seas_max", 2)))
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


var _moist: Array = []   # влажность 0..1+, по строкам


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
	var out := {"river": river.has(city_tile), "lake": false, "swamp": false}
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n := city_tile + d
		if in_bounds(n) and grid[n.y][n.x] == TILE_WATER \
				and String(water_kind.get(n, "lake")) == "lake":
			out["lake"] = true
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var n := city_tile + Vector2i(dx, dy)
			if in_bounds(n) and grid[n.y][n.x] == TILE_SWAMP:
				out["swamp"] = true
	return out


## Случайный проходимый тайл (страховка генерации POI); не русло реки.
func _walkable_random() -> Vector2i:
	for attempt in 300:
		var p := _random_inner_tile()
		if is_walkable(p) and not river.has(p):
			return p
	return city_tile


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


func is_walkable(p: Vector2i) -> bool:
	if boats_enabled and in_bounds(p) and grid[p.y][p.x] == TILE_WATER:
		return true   # лодка (M14-I): вода — медленный, но проходимый путь
	return in_bounds(p) and grid[p.y][p.x] != TILE_WATER


## Ближайший проходимый тайл (спираль до радиуса 4); фолбэк — город.
func nearest_walkable(tile: Vector2i) -> Vector2i:
	if is_walkable(tile):
		return tile
	for radius in range(1, 5):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := tile + Vector2i(dx, dy)
				if is_walkable(t):
					return t
	return city_tile


## Цена тайла для времени пути (биом; дорога быстрее равнины). Русло —
## брод: дороже равнины, но проходим (река на глобали не режет пути).
func tile_cost(p: Vector2i) -> float:
	if not is_walkable(p):
		return 0.0
	if river.has(p):
		return float(cfg.get("biomes", {}).get("river", {}).get("cost", 1.4))
	var biomes: Dictionary = cfg["biomes"]
	match grid[p.y][p.x]:
		TILE_PLAINS: return float(biomes["plains"]["cost"])
		TILE_FOREST: return float(biomes["forest"]["cost"])
		TILE_HILL: return float(biomes["hills"]["cost"])
		TILE_WASTE: return float(biomes["waste"]["cost"])
		TILE_ROAD: return float(biomes["road"]["cost"])
		TILE_SWAMP: return float(biomes.get("swamp", {}).get("cost", 2.5))
	return 1.0


# --- точки интереса -------------------------------------------------------

func _place_pois(params: Dictionary) -> void:
	var pconf: Dictionary = params.get("pois", {})
	var dist_cfg: Dictionary = params.get("distances", {})
	# город — всегда
	_add_poi("city", "", "", city_tile)
	# городская аномалия — ближайший данж (старый вход сохранён, пункт плана M8)
	var d: Array = dist_cfg.get("city_dungeon", [3, 5])
	_place_kind("dungeon", "", int(d[0]), int(d[1]), 1)
	# аномалии-данжи: по одной на каждый биом данжей (M7)
	var biome_list: Array = pconf.get("dungeon_biomes", [])
	d = dist_cfg.get("dungeon", [12, 30])
	for biome_id: String in biome_list:
		var poi := _place_kind("dungeon", biome_id, int(d[0]), int(d[1]), 1)
		if poi.is_empty():
			_add_poi("dungeon", biome_id, "", _walkable_random())
	# поселения фракций (M8: торговцы, культ; бандиты живут в лагерях)
	d = dist_cfg.get("settlement", [10, 20])
	for faction: String in pconf.get("settlements", []):
		var poi2 := _place_kind("settlement", "", int(d[0]), int(d[1]), 1, faction)
		if poi2.is_empty():
			_add_poi("settlement", "", faction, _walkable_random())
	# караван/лагерь торговцев
	d = dist_cfg.get("caravan", [8, 18])
	_place_kind("caravan", "", int(d[0]), int(d[1]), int(pconf.get("caravans", 1)), "traders")
	# лагерь торговцев «гуляй-город» (M10): телеги по кругу, торговля на месте
	d = dist_cfg.get("trade_camp", [6, 14])
	_place_kind("trade_camp", "", int(d[0]), int(d[1]), int(pconf.get("trade_camps", 1)), "traders")
	# руины, лагеря бандитов, обелиски
	d = dist_cfg.get("ruins", [8, 26])
	_place_kind("ruins", "", int(d[0]), int(d[1]), int(pconf.get("ruins", 3)))
	d = dist_cfg.get("camp", [8, 24])
	_place_kind("camp", "", int(d[0]), int(d[1]), int(pconf.get("camps", 4)), "bandits")
	d = dist_cfg.get("obelisk", [18, 34])
	_place_kind("obelisk", "", int(d[0]), int(d[1]), int(pconf.get("obelisks", 2)))
	# замок дракона (вишлист M13): один дальний, логово-биом и сокровищница
	d = dist_cfg.get("dragon_castle", [20, 36])
	_place_kind("dragon_castle", "dragon_lair", int(d[0]), int(d[1]), int(pconf.get("dragon_castles", 0)))
	# замок вампира и башня лича (M14-D): уникальные тёмные POI
	d = dist_cfg.get("vampire_keep", [20, 34])
	_place_kind("vampire_keep", "vampire_keep", int(d[0]), int(d[1]), int(pconf.get("vampire_keeps", 1)))
	d = dist_cfg.get("lich_tower", [16, 30])
	_place_kind("lich_tower", "lich_tower", int(d[0]), int(d[1]), int(pconf.get("lich_towers", 1)))
	# стартовые силы из конфига
	var strengths: Dictionary = params.get("sim", {}).get("start_strength", {})
	for poi in pois:
		match String(poi["kind"]):
			"camp", "settlement":
				poi["strength"] = float(strengths.get("camp" if String(poi["kind"]) == "camp" else "settlement", 6.0))
			"dragon_castle":
				poi["strength"] = float(strengths.get("dragon_castle", 12.0))
			"vampire_keep", "lich_tower":
				poi["strength"] = float(strengths.get(String(poi["kind"]), 13.0))
			"dungeon", "ruins":
				poi["strength"] = float(strengths.get("dungeon" if String(poi["kind"]) == "dungeon" else "ruins", 5.0))


## Добавить POI на точный тайл (город, страховки генерации).
func _add_poi(kind: String, biome: String, faction: String, tile: Vector2i) -> Dictionary:
	var poi := {
		"id": _poi_id, "kind": kind, "biome": biome, "faction": faction,
		"tile": tile, "discovered": kind == "city",
		"strength": 0.0, "state": "ok", "cleared_day": -1, "used": false,
	}
	_poi_id += 1
	pois.append(poi)
	return poi


## Разместить count POI на подходящих тайлах; возвращает последний или {}.
func _place_kind(kind: String, biome: String, dmin: int, dmax: int, count: int, faction := "") -> Dictionary:
	var last: Dictionary = {}
	for i in count:
		var tile := _find_spot(dmin, dmax)
		if tile == Vector2i(-1, -1):
			return last
		last = _add_poi(kind, biome, faction, tile)
	return last


## Свободный проходимый тайл в кольце расстояний от города, подальше от прочих POI.
## v2: не на русло реки (POI на берегу, не посреди брода).
func _find_spot(dmin: int, dmax: int) -> Vector2i:
	for attempt in 300:
		var p := _random_inner_tile()
		var dist := int(Vector2(p).distance_to(Vector2(city_tile)))
		if dist < dmin or dist > dmax or not is_walkable(p) or river.has(p):
			continue
		if _poi_near(p, 4) != null:
			continue
		return p
	# страховка: ослабляем требование разрежения
	for attempt in 300:
		var p := _random_inner_tile()
		if Vector2(p).distance_to(Vector2(city_tile)) >= float(dmin) and is_walkable(p) \
				and not river.has(p) and _poi_near(p, 2) == null:
			return p
	return Vector2i(-1, -1)


func _poi_near(tile: Vector2i, radius: float):
	for poi in pois:
		if Vector2(poi["tile"]).distance_to(Vector2(tile)) <= radius:
			return poi
	return null


## Все POI на суше и не слиплись (связность проверяется тестами по путям).
func _pois_ok() -> bool:
	if pois.is_empty():
		return false
	for poi in pois:
		if not is_walkable(poi["tile"]):
			return false
	# город+аномалия+данжи биомов+3 поселения+караван+гуляй-город+3 руины
	# +4 лагеря+2 обелиска+замок дракона+замок вампира+башня лича
	var expected := 1 + 1 + int(cfg.get("pois", {}).get("dungeon_biomes", []).size()) + 3 + 1 + 1 \
			+ 3 + 4 + 2 + int(cfg.get("pois", {}).get("dragon_castles", 0)) \
			+ int(cfg.get("pois", {}).get("vampire_keeps", 1)) + int(cfg.get("pois", {}).get("lich_towers", 1))
	return pois.size() >= expected


func poi_at(tile: Vector2i) -> Dictionary:
	for poi in pois:
		if poi["tile"] == tile:
			return poi
	return {}


func poi_by_id(poi_id: int) -> Dictionary:
	for poi in pois:
		if int(poi["id"]) == poi_id:
			return poi
	return {}


# --- туман войны ----------------------------------------------------------

func _setup_fog() -> void:
	fog = {}
	reveal_around(city_tile, int(cfg.get("city_reveal_radius", 9)))


## Открыть круг тайлов; попавшие в круг POI становятся найденными.
func reveal_around(center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and Vector2(p).distance_to(Vector2(center)) <= float(radius):
				fog[p] = true
	for poi in pois:
		if not bool(poi["discovered"]) \
				and Vector2(poi["tile"]).distance_to(Vector2(center)) <= float(radius) + 1.0:
			poi["discovered"] = true


func is_explored(p: Vector2i) -> bool:
	return fog.has(p)


## Найденные карты и обелиски (ответ №24): открыть count далёких мест.
## Возвращает открытые POI.
func reveal_far(count: int) -> Array:
	var hidden: Array = []
	for poi in pois:
		if not bool(poi["discovered"]):
			hidden.append(poi)
	hidden.shuffle()
	var opened: Array = []
	for poi: Dictionary in hidden:
		if opened.size() >= count:
			break
		poi["discovered"] = true
		reveal_around(poi["tile"], 4)
		opened.append(poi)
	return opened


# --- пути и время пути (дни) ----------------------------------------------

func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(ts, ts)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if not is_walkable(p):
				astar.set_point_solid(p, true)
				continue
			astar.set_point_weight_scale(p, tile_cost(p))


## Лодки (M14-I): вода становится проходимой (медленной) — пересборка путей.
func set_boats(on: bool) -> void:
	if boats_enabled == on:
		return
	boats_enabled = on
	_setup_astar()


## Тайлы пути от тайла к тайлу (по воде не пройти). Пустой — пути нет.
func tile_path(from: Vector2i, to: Vector2i) -> Array:
	if not in_bounds(from) or not in_bounds(to) or not is_walkable(to):
		return []
	return astar.get_id_path(from, to)


## Время пути в днях: сумма цен тайлов маршрута / тайлов за день, минимум 1.
## Расстояние и биом влияют на дни, старые дороги ускоряют (пункт плана M8).
func travel_days(from: Vector2i, to: Vector2i) -> int:
	var path := tile_path(from, to)
	if path.is_empty():
		return 0
	var cost := 0.0
	for i in range(1, path.size()):
		cost += tile_cost(path[i])
	var per_day: float = float(cfg.get("tiles_per_day", 22.0))
	return maxi(1, int(ceilf(cost / maxf(1.0, per_day))))


func tile_center_px(p: Vector2i) -> Vector2:
	return Vector2(p.x * ts + ts / 2.0, p.y * ts + ts / 2.0)


func tile_of_px(px: Vector2) -> Vector2i:
	return Vector2i(px / ts)


# --- старые дороги ---------------------------------------------------------

## Дороги от города к поселениям (L-образные старые тракты; вода прерывает).
func _draw_roads() -> void:
	for poi in pois:
		if String(poi["kind"]) != "settlement":
			continue
		_road_l(city_tile, poi["tile"])


func _road_l(from: Vector2i, to: Vector2i) -> void:
	var p := from
	while p.x != to.x:
		p.x += 1 if to.x > p.x else -1
		_set_road(p)
	while p.y != to.y:
		p.y += 1 if to.y > p.y else -1
		_set_road(p)


func _set_road(p: Vector2i) -> void:
	# v2: через реку дорога не кладётся (переправа — не тракт)
	if in_bounds(p) and is_walkable(p) and p != city_tile and not river.has(p):
		grid[p.y][p.x] = TILE_ROAD
