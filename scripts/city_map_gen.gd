# Часть: карта города — генерация: сид, природа 2.0 (леса/хребты/месторождения),
# классификация воды/суши, броды. Один класс, поведение не меняется.
extends "res://scripts/city_map_base.gd"

## в городе (ответ №117); озеро-сосед → минимум одно озеро; болото рядом →
## минимум одно болото. hydro={} — старое поведение по params (для тестов).
func generate(seed_value: int, params: Dictionary, hydro := {}) -> void:
	w = int(params["map_w"])
	h = int(params["map_h"])
	ts = int(params["tile_size"])
	# v1.43: автотесты гоняют малые карты (CI — десятки генераций)
	if OS.has_environment("PEPEL_TEST_MAPS"):
		w = mini(w, 96)
		h = mini(h, 72)
	road = {}
	wear = {}
	rock_hp = {}
	stumps = {}
	saplings = {}
	tree_size = {}
	tree_growth = {}
	logs = {}
	bridges = {}
	fords = {}
	river_origin = {}
	height = {}
	stairs = {}
	plateau_cfg = params.get("plateaus", {})
	var river_on := bool(hydro.get("river", params.get("river", true)))
	var lakes_n := int(params["lakes"])
	var swamps_n := int(params.get("swamps", 2))
	if bool(hydro.get("lake", false)):
		lakes_n = maxi(lakes_n, 1)
	if bool(hydro.get("swamp", false)):
		swamps_n = maxi(swamps_n, 1)
	for attempt in 20:
		var _t0 := Time.get_ticks_msec()
		_generate_once(seed_value + attempt * 1013, params, river_on, lakes_n, swamps_n)
		var _t1 := Time.get_ticks_msec()
		classify_water()
		var _t15 := Time.get_ticks_msec()
		mark_fords()
		var _t2 := Time.get_ticks_msec()
		if OS.get_environment("GEN_DEBUG") != "":
			var wc := 0
			for yy in h:
				for xx in w:
					if grid[yy][xx] == TILE_WATER:
						wc += 1
			print("[gen-water] water tiles=%d" % wc)
		var _ok := _connected()
		if OS.get_environment("GEN_DEBUG") != "":
			print("[gen] attempt %d: gen %d ms, classify %d ms, fords %d ms, connected=%s" % [
					attempt, _t1 - _t0, _t15 - _t1, _t2 - _t15, _ok])
		if _ok:
			break
	# v1.49 («Город живёт»): добор природы ПОСЛЕ генерации — отдельным RNG со
	# своим сидом. Ванильные параметры и последовательность бросков не тронуты
	# (детерминизм сидов и привязанные к ним тесты целы), лес/скалы/пруды
	# добираются вне ядра застройки и вдали от аномалии. ДО mark_terrain_solid —
	# новые скалы сразу сплошные для A*.
	_extra_nature_pass(seed_value, params)
	_pick_region_resource(seed_value, params)
	mark_terrain_solid()


## Добор природы (v1.49): деревья, скалы и малые пруды вне ядра города.
## v1.50 «Живая земля»: + ЛЕСНЫЕ МАССИВЫ (кластеры 30–120 деревьев с
## полянами) и СКАЛЬНЫЕ ХРЕБТЫ (связные гряды 20–60 тайлов с изгибами) —
## по сиду не на каждой карте (chance), заметно гуще прежнего.
## min_radius — от старта (кольцо стен, поля и застройка свободны),
## anomaly_radius — вокруг аномалии (улью и герою нужен подход).
func _extra_nature_pass(seed_value: int, params: Dictionary) -> void:
	var ncfg: Dictionary = params.get("extra_nature", {})
	if ncfg.is_empty() or ncfg.get("enabled", true) == false:
		return
	var erng := RandomNumberGenerator.new()
	erng.seed = hash("extra-nature:%d" % seed_value)
	var min_r := int(ncfg.get("min_radius", 26))
	var anom_r := int(ncfg.get("anomaly_radius", 8))
	# лесные массивы (v1.50): не на каждой карте — шанс по сиду
	var fcfg: Dictionary = ncfg.get("forests", {})
	if bool(fcfg.get("enabled", true)) and erng.randf() < float(fcfg.get("chance", 0.85)):
		for f in erng.randi_range(1, int(fcfg.get("count_max", 2))):
			_forest_cluster(erng, fcfg, min_r, anom_r)
	# скальные хребты (v1.50; v1.54-ускорение): связность проверяется ОДИН
	# раз после всех гряд (прежде — полный BFS после каждой: до 4 секунд
	# на старт). Сломали — откатываем гряды целиком, карта валидна и без них
	var rcfg: Dictionary = ncfg.get("ridges", {})
	var ridge_tiles: Array = []
	if bool(rcfg.get("enabled", true)) and erng.randf() < float(rcfg.get("chance", 0.65)):
		for g in erng.randi_range(1, int(rcfg.get("count_max", 2))):
			ridge_tiles.append_array(_rock_ridge(erng, rcfg, min_r, anom_r))
		if not ridge_tiles.is_empty() and not _connected():
			for t: Vector2i in ridge_tiles:
				grid[t.y][t.x] = TILE_GRASS
	# деревья — лес кольцом вокруг города (луг между ядром и стеной чистый);
	# v1.50: одиночки ПОКРУПНЕЕ (lone_big — свой бросок размера, вангал цел)
	var n_trees := int(ncfg.get("trees", 0))
	var lone_big := bool(ncfg.get("lone_big", true))
	var placed := 0
	var guard := 0
	while placed < n_trees and guard < n_trees * 30:
		guard += 1
		var p := Vector2i(erng.randi_range(1, w - 2), erng.randi_range(1, h - 2))
		if grid[p.y][p.x] != TILE_GRASS or not _extra_spot_ok(p, min_r, anom_r):
			continue
		grid[p.y][p.x] = TILE_TREE
		tree_size[p] = _roll_lone_tree_size(erng.randf()) if lone_big \
				else _roll_tree_size(erng.randf())
		placed += 1
	# малые пруды: вода сплошная — на карте появляются новые водоёмы
	for i in int(ncfg.get("ponds", 0)):
		var pc := Vector2i(erng.randi_range(1, w - 2), erng.randi_range(1, h - 2))
		var pr := erng.randi_range(2, 3)
		if grid[pc.y][pc.x] != TILE_GRASS or not _extra_blob_ok(pc, pr, min_r, anom_r):
			continue
		_blob(pc, pr, TILE_WATER)
	# скалы: компактные гряды с сателлитами (как ванильные, но мельче)
	var n_rocks := int(ncfg.get("rocks", 0))
	var hp := float(params.get("mountain", {}).get("hp", 80.0))
	var made := 0
	guard = 0
	while made < n_rocks and guard < n_rocks * 30:
		guard += 1
		var c := Vector2i(erng.randi_range(1, w - 2), erng.randi_range(1, h - 2))
		var cr := erng.randi_range(2, 4)
		if grid[c.y][c.x] != TILE_GRASS or not _extra_blob_ok(c, cr, min_r, anom_r):
			continue
		_blob(c, cr, TILE_ROCK)
		for s in 2:
			var c2 := c + Vector2i(erng.randi_range(-5, 5), erng.randi_range(-4, 4))
			if c2.x < 1 or c2.y < 1 or c2.x > w - 2 or c2.y > h - 2:
				continue
			var cr2 := erng.randi_range(1, 2)
			if grid[c2.y][c2.x] == TILE_GRASS and _extra_blob_ok(c2, cr2, min_r, anom_r):
				_blob(c2, cr2, TILE_ROCK)
		made += 1
	# прочность всем скалам (новым тоже): гряда добываема, руда богаче
	for y in h:
		for x in w:
			var t := Vector2i(x, y)
			if grid[y][x] == TILE_ROCK and not rock_hp.has(t):
				rock_hp[t] = hp
			elif grid[y][x] == TILE_ORE and not rock_hp.has(t):
				rock_hp[t] = hp * 1.3


## ---------- богатства региона (v1.56) --------------------------------------
## У КАЖДОЙ локации гарантирован (100%) свой ресурс: медь, серебро, золото,
## янтарь — на суше; жемчуг, рыбное изобилие — на воде. Месторождения
## добываются шахтой (жилы), водные — пристанью (рыбак).



## Выбрать богатство локации и разложить месторождения (детерминированно
## по сиду — NPC-карты перегенерируются и ресурс совпадает).
func _pick_region_resource(seed_value: int, params: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("region:%d" % seed_value)
	var has_water := false
	for y in h:
		for x in w:
			if grid[y][x] == TILE_WATER:
				has_water = true
				break
		if has_water:
			break
	var land_pool := ["copper", "silver", "gold", "amber"]
	var water_pool := ["pearls", "fish_abound"]
	var pool := land_pool + (water_pool if has_water else [])
	region_resource = pool[rng.randi_range(0, pool.size() - 1)]
	deposit_tiles = {}
	if region_resource in ["pearls", "fish_abound"]:
		_place_water_beds(rng)
	else:
		_place_rock_deposits(rng)


## Ячейки месторождения на скалах (металлы/янтарь): 2 гнезда по 3–5 клеток.
func _place_rock_deposits(rng: RandomNumberGenerator) -> void:
	var rocks: Array = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if grid[y][x] == TILE_ROCK:
				rocks.append(Vector2i(x, y))
	if rocks.is_empty():
		return
	for nest in 2:
		var c: Vector2i = rocks[rng.randi_range(0, rocks.size() - 1)]
		for i in rng.randi_range(3, 5):
			var t := c + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			if in_bounds(t) and grid[t.y][t.x] == TILE_ROCK:
				deposit_tiles[t] = true


## Жемчужные/рыбные банки: 2–4 водных клетки у берега.
func _place_water_beds(rng: RandomNumberGenerator) -> void:
	var waters: Array = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if grid[y][x] == TILE_WATER:
				var shore := false
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := Vector2i(x, y) + d
					if in_bounds(n) and grid[n.y][n.x] != TILE_WATER:
						shore = true
						break
				if shore:
					waters.append(Vector2i(x, y))
	if waters.is_empty():
		return
	for i in rng.randi_range(2, 4):
		var t: Vector2i = waters[rng.randi_range(0, waters.size() - 1)]
		deposit_tiles[t] = true


## Детерминированный шум 0..1 по координатам и соли (для лесов/полян —
## одинаковый при перегенерации с тем же сидом).
static func _vnoise(x: int, y: int, salt: int) -> float:
	var v := int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791))
	return float(absi(v) % 1000) / 1000.0


## Лесной массив (v1.50): органический блоб (овал с гармоникой кромки),
## деревья по полю плотности, поляны — прогалы второго шума. За раз —
## от size_min до size_max деревьев; не влез целиком — остаётся рощицей.
func _forest_cluster(erng: RandomNumberGenerator, fcfg: Dictionary,
		min_r: int, anom_r: int) -> void:
	var size_min := int(fcfg.get("size_min", 30))
	var size_max := int(fcfg.get("size_max", 120))
	var density := clampf(float(fcfg.get("density", 0.8)), 0.3, 0.95)
	var clearing := clampf(float(fcfg.get("clearing", 0.16)), 0.0, 0.5)
	var r_min := int(fcfg.get("radius_min", 4))
	var r_max := int(fcfg.get("radius_max", 8))
	for attempt in 12:
		var c := Vector2i(erng.randi_range(8, w - 9), erng.randi_range(8, h - 9))
		var r := erng.randi_range(r_min, r_max)
		if not _extra_blob_ok(c, r, min_r, anom_r):
			continue
		var ph := erng.randf() * TAU
		var salt := int(erng.randi_range(1, 1 << 28))
		var placed := 0
		for y in range(maxi(1, c.y - r - 1), mini(h - 1, c.y + r + 2)):
			for x in range(maxi(1, c.x - r - 1), mini(w - 1, c.x + r + 2)):
				if placed >= size_max:
					break
				var t := Vector2i(x, y)
				var dx := float(x - c.x) / float(r)
				var dy := float(y - c.y) / float(r)
				var ang := atan2(float(y - c.y), float(x - c.x))
				var k := 1.0 + 0.14 * sin(2.0 * ang + ph)
				if dx * dx + dy * dy > k * k:
					continue
				if grid[y][x] != TILE_GRASS or not _extra_spot_ok(t, min_r, anom_r):
					continue
				if _vnoise(x, y, salt + 77) < clearing:
					continue   # поляна среди леса
				if _vnoise(x, y, salt) >= density:
					continue   # прогал по плотности
				grid[y][x] = TILE_TREE
				tree_size[t] = _roll_tree_size(erng.randf())
				placed += 1
		if placed >= size_min:
			return


## Скальный хребет (v1.50): связная гряда — шаг по направлению с изгибом,
## тайл скалы + с шансом сосед «толщины» (width 1.0..2.0). Хребет сплошной
## для A*: после укладки проверяется связность карты — сломавшая гряда
## откатывается (герой не должен оказаться отрезан от аномалии/выхода).
func _rock_ridge(erng: RandomNumberGenerator, rcfg: Dictionary,
		min_r: int, anom_r: int) -> Array:
	var len_min := int(rcfg.get("len_min", 20))
	var len_max := int(rcfg.get("len_max", 60))
	var width := clampf(float(rcfg.get("width", 1.6)), 1.0, 2.0)
	var placed: Array = []   # тайлы гряды (живёт и после цикла попыток)
	for attempt in 12:
		var c := Vector2i(erng.randi_range(8, w - 9), erng.randi_range(8, h - 9))
		if grid[c.y][c.x] != TILE_GRASS or not _extra_spot_ok(c, min_r, anom_r):
			continue
		var ang := erng.randf() * TAU
		var pos := Vector2(c)
		var target := erng.randi_range(len_min, len_max)
		var misses := 0
		while placed.size() < target and misses < 16:
			ang += erng.randf_range(-0.5, 0.5)   # изгиб гряды
			var step := Vector2(cos(ang), sin(ang))
			var nxt := Vector2i((pos + step).round())
			if nxt.x < 2 or nxt.y < 2 or nxt.x > w - 3 or nxt.y > h - 3 \
					or grid[nxt.y][nxt.x] != TILE_GRASS \
					or not _extra_spot_ok(nxt, min_r, anom_r):
				misses += 1
				ang += (0.4 if erng.randf() < 0.5 else -0.4)   # обогнуть помеху
				continue
			pos = Vector2(nxt)
			grid[nxt.y][nxt.x] = TILE_ROCK
			placed.append(nxt)
			# «толщина» хребта: сосед сбоку от направления гряды
			var side := nxt + Vector2i(roundi(-step.y), roundi(step.x))
			if side.x > 1 and side.y > 1 and side.x < w - 2 and side.y < h - 2 \
					and grid[side.y][side.x] == TILE_GRASS \
					and _extra_spot_ok(side, min_r, anom_r) \
					and erng.randf() < width - 1.0:
				grid[side.y][side.x] = TILE_ROCK
				placed.append(side)
		break   # placed готов (или короткая гряда — откат ниже)
	# связность карты проверяет вызывающий (один раз на все гряды)
	if placed.size() >= len_min:
		return placed
	for t: Vector2i in placed:
		grid[t.y][t.x] = TILE_GRASS   # короткая гряда — откат
	return []


## Размер одиночного дерева добора (v1.50, lone_big): 15% малое, 45%
## среднее, 40% БОЛЬШОЕ — одиночки на лугу заметнее прежнего.
static func _roll_lone_tree_size(roll: float) -> int:
	if roll < 0.15:
		return TREE_SMALL
	if roll < 0.60:
		return TREE_MEDIUM
	return TREE_LARGE


## Годен ли тайл под добор природы: вне ядра застройки, не у аномалии/выхода,
## и НЕ на плато (площадки и лестницы остаются чистыми, №113–115).
func _extra_spot_ok(t: Vector2i, min_radius: int, anomaly_radius: int) -> bool:
	return t.distance_to(spawn_tile) >= min_radius \
			and t.distance_to(anomaly_tile) >= anomaly_radius \
			and t.distance_to(world_exit_tile) >= 6 \
			and int(height.get(t, 0)) == 0


## Годен ли ЦЕЛИКОМ блоб радиуса r с центром c (кромка не должна налезать
## на плато/ядро — иначе плато «на скале» и недостижимые лестницы).
func _extra_blob_ok(c: Vector2i, r: int, min_radius: int, anomaly_radius: int) -> bool:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 1 or y < 1 or x > w - 2 or y > h - 2:
				continue
			var t := Vector2i(x, y)
			if Vector2(t).distance_to(Vector2(c)) > float(r):
				continue
			if grid[y][x] != TILE_GRASS or not _extra_spot_ok(t, min_radius, anomaly_radius):
				return false
	return true


## Природные препятствия: ВОДА и скалы/руда/выработанная порода — сплошные
## для обеих сеток A* (v1.29.2, заказчик: «запрети всем ходить через воду,
## только через мост» — брод v1.29.1 отменён). Переправа — только мосты
## (M14-I). Деревья проходимы по дизайну — на них стоят лесорубы и герой
## при рубке.


func mark_terrain_solid() -> void:
	# v1.43: сплошные собираются словарём и отдаются в rebuild — точки и
	# рёбра строятся одним проходом (вместо ~1 млн вызовов set/disconnect)
	if astar != null and astar_ready:
		return
	_setup_astar()
	var solids := {}
	for y in h:
		for x in w:
			var t := Vector2i(x, y)
			if not is_nature_walkable(t):
				solids[t] = true
	astar.rebuild(solids)
	astar_raider.rebuild(solids)
	astar_ready = true
	for p: Vector2i in bridges:
		_apply_tile_weight(p)
	for p: Vector2i in fords:
		astar.set_point_weight_scale(p, 1.6)
		astar_raider.set_point_weight_scale(p, 1.6)


## Вес тайла для A*: земля 1.0, дорога 0.4 (set_road), мост — 0.7
## (по мосту охотнее, чем в обход).


func _apply_tile_weight(p: Vector2i) -> void:
	var w := BRIDGE_WEIGHT if bridges.has(p) else 1.0
	astar.set_point_weight_scale(p, w)
	astar_raider.set_point_weight_scale(p, w)


## Классификация водоёмов (v1.29.1): вытянутая лента — река, малое
## компактное пятно — болотце, остальное — озеро. Источник правды для
## отрисовки (city_terrain берёт отсюда: цвета воды, песчаная кромка).
## Публичная: save_game перезапускает её ПОСЛЕ восстановления сетки из сейва
## (каркас генерируется с сидом 0 и перекрывается сохранёнными тайлами —
## без переклассификации типы воды не совпадали с реальной картой).
func classify_water() -> void:
	water_kind = {}
	var seen := {}
	for y in h:
		for x in w:
			var start := Vector2i(x, y)
			if grid[y][x] != TILE_WATER or seen.has(start):
				continue
			var queue: Array = [start]
			var qi := 0
			seen[start] = true
			var comp: Array = []
			var mn: Vector2i = start
			var mx: Vector2i = start
			while qi < queue.size():
				var t: Vector2i = queue[qi]
				qi += 1
				comp.append(t)
				mn = Vector2i(mini(mn.x, t.x), mini(mn.y, t.y))
				mx = Vector2i(maxi(mx.x, t.x), maxi(mx.y, t.y))
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = t + d
					if in_bounds(n) and grid[n.y][n.x] == TILE_WATER and not seen.has(n):
						seen[n] = true
						queue.append(n)
			var size := Vector2(mx - mn + Vector2i(1, 1))
			var kind := "lake"
			var has_river := false
			for ct: Vector2i in comp:
				if river_origin.has(ct):
					has_river = true
					break
			if has_river:
				kind = "river"   # v1.31.2: компонент с руслом — река (меандр шире высоты ошибочно звался озером)
			elif comp.size() <= 16:
				kind = "swamp"
			elif river_origin.is_empty() and maxf(size.x, size.y) / maxf(1.0, minf(size.x, size.y)) >= 2.8:
				# эвристика вытянутости — ТОЛЬКО для старых сейвов без меток русла
				kind = "river"
			for t: Vector2i in comp:
				water_kind[t] = kind


## Тип воды в тайле ("" — не вода).
func water_kind_at(p: Vector2i) -> String:
	return String(water_kind.get(p, ""))


## Сплошной ли тайл для A* (вода сплошная наравне со скалами, v1.29.2).
## Страховки «замурован под стеной» должны смотреть сюда, а не в is_walkable,
## — иначе они телепортировали бы всех, кто стоит в воде.
func is_solid(p: Vector2i, for_raider := false) -> bool:
	if astar == null or not in_bounds(p):
		return false
	var g = astar_raider if for_raider else astar
	return g.is_point_solid(p)


## Пересчитать сплошность одной клетки после изменения рельефа
## (мост построен, скала выработана, вскрыта руда).
func refresh_tile_solid(p: Vector2i) -> void:
	ensure_astar()
	if astar != null and in_bounds(p):
		var solid: bool = not is_nature_walkable(p)
		astar.set_point_solid(p, solid)
		astar_raider.set_point_solid(p, solid)


func _generate_once(seed_value: int, params: Dictionary,
		river_on := true, lakes_n := -1, swamps_n := -1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if lakes_n < 0:
		lakes_n = int(params["lakes"])
	if swamps_n < 0:
		swamps_n = int(params.get("swamps", 2))
	grid = []
	# рельеф пересоздаётся на КАЖДОЙ попытке генерации (generate() крутит
	# _generate_once до связной карты — иначе высоты прошлой попытки
	# «протекают» на новую сетку)
	height = {}
	stairs = {}
	for y in h:
		var row := []
		row.resize(w)
		row.fill(TILE_GRASS)
		grid.append(row)
	# река ПЕРВОЙ (v1.31.2): чистый плавный меандр — никакие обходы не
	# искажают русло (обход v1.31 делал диагональные засечки-«непонятные
	# водоёмы», заказчик); озёра и болота ложатся ПОЗАДИ неё с зазором.
	# v2: река появляется только если она есть на клетке мира (hydro)
	if river_on:
		_generate_river(rng)
		_trim_river_stubs({})
	# озёра (v1.29.4): почти круглый овал с мягкой рябью контура — ровные
	# красивые берега у КАЖДОГО озера (оси по сетке). v1.31.2: центр не ближе
	# 8 тайлов до любой воды — озёра никогда не сливаются ни с рекой, ни
	# друг с другом (каждое — отдельный ровный овал с песчаным берегом)
	for i in lakes_n:
		_lake_blob(_random_clear_tile(rng, 8), rng)
	# болота (v1.29.3): свой малый гладкий овал — центр в 6 тайлах от воды
	var swamp_centers: Array = []
	for i in swamps_n:
		var sc := _random_clear_tile(rng, 6)
		swamp_centers.append(sc)
		_swamp_blob(sc, rng)
		# скальные ГРЯДЫ (M11): не россыпь одиночных камней, а единые массивы —
	# большое пятно плюс сателлиты внахлёст; в них живёт руда и их добывают.
	# v1.29.4: сателлита ДВА со случайными смещениями — силуэт органичнее;
	# радиусы прежние (шире залезали на кольцо стен и лес у старта)
	for i in int(params.get("rocks", 2)):
		var center := _random_inner_tile(rng)
		_blob(center, rng.randi_range(4, 6), TILE_ROCK)
		for s in 2:
			var off := Vector2i(rng.randi_range(-6, 6), rng.randi_range(-5, 5))
			_blob(center + off, rng.randi_range(2, 3), TILE_ROCK)
	# рудные жилы: железо в скалах и на голой земле — места под шахту (M5+)
	for i in int(params.get("ore_spots", 0)):
		_ore_blob(_random_inner_tile(rng), rng.randi_range(1, 2))
	# чистое ядро города (v1.29.4): та же зона радиуса 9, что у реки —
	# вода/скалы/руда в неё не попадают. Кольцо стен, лесопилка и дома
	# должны строиться гарантированно: раньше озеро, болото или руда могли
	# лечь в кольцо и ломали и стройку, и тесты (кольцо 29 вместо 40)
	var sx := w / 2
	var sy := h / 2
	for y in range(maxi(0, sy - 9), mini(h, sy + 10)):
		for x in range(maxi(0, sx - 9), mini(w, sx + 10)):
			var t: int = grid[y][x]
			if t == TILE_WATER or t == TILE_ROCK or t == TILE_ORE:
				grid[y][x] = TILE_GRASS
	# запас прочности скалы (M11): тайлы гряды добываемы; руда богаче
	var hp := float(params.get("mountain", {}).get("hp", 80.0))
	for y in h:
		for x in w:
			if grid[y][x] == TILE_ROCK:
				rock_hp[Vector2i(x, y)] = hp
			elif grid[y][x] == TILE_ORE:
				rock_hp[Vector2i(x, y)] = hp * 1.3
	# деревья поодиночке на траве — лес гуще (M5+); размер — детерминированный
	# бросок (v1.21): лес в основном средний, реже малый и большой
	var placed := 0
	var guard := 0
	while placed < int(params["trees"]) and guard < int(params["trees"]) * 20:
		guard += 1
		var p := Vector2i(rng.randi_range(1, w - 2), rng.randi_range(1, h - 2))
		if grid[p.y][p.x] == TILE_GRASS:
			grid[p.y][p.x] = TILE_TREE
			tree_size[p] = _roll_tree_size(rng.randf())
			placed += 1
	# тёмный лес вокруг болот (v1.39.2, заказчик): деревья растут кольцом
	# в 1-2 тайлах от воды болота — рендерятся тёмными (city_view)
	_plant_swamp_trees(swamp_centers, rng)
	# старт в центре, аномалия — у правого края, выход на карту мира — у левого;
	# вокруг них чистая трава
	spawn_tile = Vector2i(w / 2, h / 2)
	anomaly_tile = Vector2i(w - 3, h / 2)
	world_exit_tile = Vector2i(1, h / 2)
	_clear_around(spawn_tile, 3)
	_clear_around(anomaly_tile, 2)
	_clear_around(world_exit_tile, 2)
	# ПЛАТО (этап «Многоуровневый рельеф», №113–115): поднимаем травяные
	# массивы на уровень 1 (иногда с террасой уровня 2) и прорубаем
	# лестницы-проходы. Сетка grid не меняется — плато остаётся травой
	# (деревья/стройка на нём разрешены), высота живёт в height.
	_generate_plateaus(rng, params)
	# v1.48 («Новый мир v2» этап 6): РУИНЫ для исследования — кучи древних
	# камней (TILE_RUIN, сплошные, добываются), рядом лут-тайл (E: кристаллы/руна)
	var rcfg: Dictionary = params.get("city_ruins", {})
	if bool(rcfg.get("enabled", true)):
		for i in rng.randi_range(int(rcfg.get("min", 3)), int(rcfg.get("max", 5))):
			var rt := _random_inner_tile(rng)
			if grid[rt.y][rt.x] != TILE_GRASS:
				continue
			_blob(rt, rng.randi_range(1, 2), TILE_RUIN)
			for t2 in [rt + Vector2i(1, 0), rt + Vector2i(-1, 0), rt + Vector2i(0, 1),
					rt + Vector2i(0, -1), rt]:
				if grid[t2.y][t2.x] == TILE_GRASS 						and rng.randf() < float(rcfg.get("loot_chance", 0.35)):
					ruin_loot[t2] = true
					break


## Обрывки реки (v1.29.4): ядро города и край карты режут меандр на куски —
## осколки выглядели «глазами-линзами» с песчаной кромкой. Компонент воды, в
## котором НЕТ ни одного тайла озёр/болот (они перечислены до реки) и меньше
## 20 тайлов, — речной обрывок: возвращаем траву.
## Мелководье-броды (v1.31, заказчик): «на 10 клеток реки один проход,
## минимум один на реку» — по броду герой и жители переходят реку пешком.
## Детерминировано по компоненте (порядок тайлов по y,x) — одинаково
## после загрузки сейва. Публичная: save_game зовёт для старых сейвов.
func mark_fords() -> void:
	fords = {}
	var seen := {}
	for y in h:
		for x in w:
			var start := Vector2i(x, y)
			if grid[y][x] != TILE_WATER or String(water_kind.get(start, "")) != "river" or seen.has(start):
				continue
			var comp: Array = [start]
			var comp_set := {start: true}
			seen[start] = true
			var qi := 0
			while qi < comp.size():
				var t: Vector2i = comp[qi]
				qi += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = t + d
					if in_bounds(n) and not comp_set.has(n) 							and grid[n.y][n.x] == TILE_WATER 							and String(water_kind.get(n, "")) == "river":
						comp_set[n] = true
						seen[n] = true   # v1.43-фикс: без этого каждый тайл реки
						                 # перезапускал полный обход компоненты
						comp.append(n)
			var want := maxi(1, int(comp.size() / 10))
			for i in want:
				var idx := clampi(int(float(i) * float(comp.size()) / float(want)), 0, comp.size() - 1)
				# v1.43: брод — ПЯТНО через всю реку (радиус 5 от семени), а не
				# один тайл: в реку шириной 4-5 тайлов иначе не войти с берега
				var seed_tile: Vector2i = comp[idx]
				var blob: Array = [seed_tile]
				var blob_set := {seed_tile: true}
				var qi2 := 0
				while qi2 < blob.size():
					var t2: Vector2i = blob[qi2]
					qi2 += 1
					for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var n2: Vector2i = t2 + d2
						if in_bounds(n2) and not blob_set.has(n2) 								and comp_set.has(n2) 								and Vector2(n2).distance_to(Vector2(seed_tile)) <= 5.5:
							blob_set[n2] = true
							blob.append(n2)
				for t3: Vector2i in blob:
					fords[t3] = true


func _trim_river_stubs(keep: Dictionary) -> void:
	var seen := {}
	for y in h:
		for x in w:
			var start := Vector2i(x, y)
			if grid[y][x] != TILE_WATER or seen.has(start):
				continue
			var comp: Array = [start]
			seen[start] = true
			var has_keep := keep.has(start)
			var qi := 0
			while qi < comp.size():
				var t: Vector2i = comp[qi]
				qi += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = t + d
					if in_bounds(n) and grid[n.y][n.x] == TILE_WATER and not seen.has(n):
						seen[n] = true
						has_keep = has_keep or keep.has(n)
						comp.append(n)
			if not has_keep and comp.size() < 20:
				for t2: Vector2i in comp:
					grid[t2.y][t2.x] = TILE_GRASS


## ---------- многоуровневый рельеф (этап №2 «Рельеф, вода, данжи») ----------

## Уровень тайла: 0 равнина, 1 плато, 2 терраса (нет в словаре — равнина).
