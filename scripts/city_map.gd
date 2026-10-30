extends RefCounted
## Карта города (M2): тайлы травы/воды/скал/деревьев, аномалия-вход в данж.
## Чистая логика без сцены — тестируется headless. Пиксель-арт — этап M8.

const TILE_GRASS := 0
const TILE_WATER := 1
const TILE_ROCK := 2
const TILE_TREE := 3
const TILE_ORE := 4       # скала с железной рудой — под ней можно поставить шахту (M5+)
const TILE_DEADROCK := 5  # выработанный массив (правки v1.21): пустая порода/жилы —
                          # стоит на месте выработанной скалы, добывается шахтой

const TREE_SMALL := 1     # размеры деревьев (правки v1.21): малое/среднее/большое
const TREE_MEDIUM := 2
const TREE_LARGE := 3

var w := 0
var h := 0
var ts := 32
var grid_ver := 0             # v1.28.1: версия масок воды/скал — инкремент при выработке породы
var grid: Array = []            # grid[y][x] -> TILE_*
var road := {}                  # Vector2i -> true: дороги (M6) — ускорение и приоритет путей
var wear := {}                  # Vector2i -> float: износ троп (M6) — город сам строит дороги там, где ходят
var rock_hp := {}               # Vector2i -> float: запас скалы (M11) — добыча истощает тайл
var stumps := {}                # Vector2i -> true: пни на месте срубленных деревьев (M11)
var saplings := {}              # Vector2i -> {t: float}: посаженные деревья, растут (M11)
var tree_size := {}             # Vector2i -> int (TREE_SMALL/MEDIUM/LARGE): размер дерева (v1.21)
var tree_growth := {}           # Vector2i -> float: дни роста дерева до следующего размера (v1.21)
var logs := {}                  # Vector2i -> {size: int}: поваленные брёвна на земле (v1.21.2) —
                                # герой валит, лесопилка подбирает и пилит
var bridges := {}               # Vector2i -> true: мосты через воду (M14-I)
var fords := {}                 # Vector2i -> true: мелководье-брод (v1.31)
var river_origin := {}          # Vector2i -> true: тайлы, нарисованные РЕКОЙ (v1.31.2)
var water_kind := {}            # Vector2i -> "lake"|"river"|"swamp" — тип водоёма
                                # для отрисовки (цвет воды, песчаная кромка)
var anomaly_tile := Vector2i.ZERO   # вход в данж (у аномалии)
var spawn_tile := Vector2i.ZERO     # старт героя и жителей
var world_exit_tile := Vector2i.ZERO  # край города — выход на карту мира (M8)
var astar: AStarGrid2D = null         # пути жителей/героя: ворота всегда проходимы
var astar_raider: AStarGrid2D = null  # пути мутантов: закрытые ворота — стена (v1.26)


## Генерация по seed: детерминированная, связная (от старта достижимы все проходимые тайлы).
## v2 («Мир v2», этап 1): гидро-контекст клетки мира (world_map.city_hydro())
## решает, какие водоёмы есть в локации: река на глобальной клетке = река
## в городе (ответ №117); озеро-сосед → минимум одно озеро; болото рядом →
## минимум одно болото. hydro={} — старое поведение по params (для тестов).
func generate(seed_value: int, params: Dictionary, hydro := {}) -> void:
	w = int(params["map_w"])
	h = int(params["map_h"])
	ts = int(params["tile_size"])
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
	var river_on := bool(hydro.get("river", params.get("river", true)))
	var lakes_n := int(params["lakes"])
	var swamps_n := int(params.get("swamps", 2))
	if bool(hydro.get("lake", false)):
		lakes_n = maxi(lakes_n, 1)
	if bool(hydro.get("swamp", false)):
		swamps_n = maxi(swamps_n, 1)
	for attempt in 20:
		_generate_once(seed_value + attempt * 1013, params, river_on, lakes_n, swamps_n)
		if _connected():
			break
	classify_water()
	mark_fords()
	_setup_astar()
	mark_terrain_solid()


## Природные препятствия: ВОДА и скалы/руда/выработанная порода — сплошные
## для обеих сеток A* (v1.29.2, заказчик: «запрети всем ходить через воду,
## только через мост» — брод v1.29.1 отменён). Переправа — только мосты
## (M14-I). Деревья проходимы по дизайну — на них стоят лесорубы и герой
## при рубке.
func mark_terrain_solid() -> void:
	if astar == null:
		return
	for y in h:
		for x in w:
			var t := Vector2i(x, y)
			var solid: bool = not is_nature_walkable(t)
			astar.set_point_solid(t, solid)
			astar_raider.set_point_solid(t, solid)
	for p: Vector2i in bridges:
		_apply_tile_weight(p)
	for p: Vector2i in fords:
		astar.set_point_weight_scale(p, 1.6)
		astar_raider.set_point_weight_scale(p, 1.6)


## Вес тайла для A*: земля 1.0, дорога 0.4 (set_road), мост — 0.7
## (по мосту охотнее, чем в обход).
const BRIDGE_WEIGHT := 0.7


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
			seen[start] = true
			var comp: Array = []
			var mn: Vector2i = start
			var mx: Vector2i = start
			while not queue.is_empty():
				var t: Vector2i = queue.pop_back()
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
	var g := astar_raider if for_raider else astar
	return g.is_point_solid(p)


## Пересчитать сплошность одной клетки после изменения рельефа
## (мост построен, скала выработана, вскрыта руда).
func refresh_tile_solid(p: Vector2i) -> void:
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
	for i in swamps_n:
		_swamp_blob(_random_clear_tile(rng, 6), rng)
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
	# старт в центре, аномалия — у правого края, выход на карту мира — у левого;
	# вокруг них чистая трава
	spawn_tile = Vector2i(w / 2, h / 2)
	anomaly_tile = Vector2i(w - 3, h / 2)
	world_exit_tile = Vector2i(1, h / 2)
	_clear_around(spawn_tile, 3)
	_clear_around(anomaly_tile, 2)
	_clear_around(world_exit_tile, 2)


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
			seen[start] = true
			var qi := 0
			while qi < comp.size():
				var t: Vector2i = comp[qi]
				qi += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = t + d
					if in_bounds(n) and grid[n.y][n.x] == TILE_WATER 							and not seen.has(n) and String(water_kind.get(n, "")) == "river":
						seen[n] = true
						comp.append(n)
			comp.sort_custom(func(a, b) -> bool:
				return a.y < b.y or (a.y == b.y and a.x < b.x))
			var want := maxi(1, int(comp.size() / 10))
			for i in want:
				var idx := clampi(int(float(i) * float(comp.size()) / float(want)), 0, comp.size() - 1)
				fords[comp[idx]] = true


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


## Центр для озера/болота (v1.31.2): трава И никакой воды в радиусе rad —
## типы водоёмов не прилегают и не сливаются. Фолбэк ослабляет радиус.
func _random_clear_tile(rng: RandomNumberGenerator, rad: int) -> Vector2i:
	for r in [rad, maxi(3, rad - 2), 2]:
		for i in 16:
			var p := _random_grass_tile(rng)
			var clear := true
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var n := p + Vector2i(dx, dy)
					if in_bounds(n) and grid[n.y][n.x] == TILE_WATER:
						clear = false
						break
				if not clear:
					break
			if clear:
				return p
	return _random_grass_tile(rng)


func _random_inner_tile(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))


## Озеро (v1.29.4): почти круглый овал — вертикальный радиус выводится из
## горизонтального (отношение ≤ 1.4), случайный поворот осей.
func _lake_blob(center: Vector2i, rng: RandomNumberGenerator) -> void:
	var rx := rng.randf_range(3.4, 4.6)
	_smooth_water_blob(center, rng, rx, rx / rng.randf_range(1.15, 1.4))


## Болото (v1.29.4): малый гладкий овал (до ~11 тайлов) + лужа-сателлит
## внахлёст — суммарно ≤ 16 тайлов, чтобы остаться болотцем для
## classify_water(); форма озера, уменьшенная в два раза.
func _swamp_blob(center: Vector2i, rng: RandomNumberGenerator) -> void:
	var rx := rng.randf_range(1.8, 2.1)
	_smooth_water_blob(center, rng, rx, rx / 1.25)
	_blob(center + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1)),
			1, TILE_WATER)


## Гладкий водоём (v1.29.3): клетка заливается, если её центр внутри контура
## «овал × k(θ)», где k — две мягкие гармоники по углу. v1.29.4: рябь слабая
## (амплитуда ≤ 0.1), оси СТРОГО по сетке — повёрнутый овал при квантовании
## в тайлы превращался в «глаз-линзу» с заострёнными концами.
func _smooth_water_blob(center: Vector2i, rng: RandomNumberGenerator,
		rx: float, ry: float) -> void:
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var a1 := rng.randf_range(0.03, 0.07)
	var a2 := rng.randf_range(0.02, 0.04)
	var rad := int(ceil(maxf(rx, ry) * (1.0 + a1 + a2))) + 1
	for y in range(maxi(1, center.y - rad), mini(h - 1, center.y + rad + 1)):
		for x in range(maxi(1, center.x - rad), mini(w - 1, center.x + rad + 1)):
			var dx := float(x - center.x) / rx
			var dy := float(y - center.y) / ry
			var ang := atan2(float(y - center.y), float(x - center.x))
			var k := 1.0 + a1 * sin(2.0 * ang + ph1) + a2 * sin(3.0 * ang + ph2)
			if dx * dx + dy * dy <= k * k:
				grid[y][x] = TILE_WATER


## Случайный внутренний тайл с травой (сухой центр болота) — до 20 попыток,
## фолбэк — обычный внутренний тайл.
func _random_grass_tile(rng: RandomNumberGenerator) -> Vector2i:
	for i in 20:
		var p := _random_inner_tile(rng)
		if grid[p.y][p.x] == TILE_GRASS:
			return p
	return _random_inner_tile(rng)


## Центр болота (v1.30.1): трава И никакой воды в радиусе 6 — два болотца
## или болото+озеро, слившись, превышали порог 16 тайлов и классифицировались
## ОЗЕРОМ (синий блоб с песком — «болото и озеро одно и то же», заказчик).
func _random_swamp_tile(rng: RandomNumberGenerator) -> Vector2i:
	for i in 12:
		var p := _random_grass_tile(rng)
		var clear := true
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				var n := p + Vector2i(dx, dy)
				if in_bounds(n) and grid[n.y][n.x] == TILE_WATER:
					clear = false
					break
			if not clear:
				break
		if clear:
			return p
	return _random_grass_tile(rng)


## Пятно круглой формы из тайлов kind (не поверх друг друга — вода поверх скалы допустима).
func _blob(center: Vector2i, radius: int, kind: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if Vector2(x, y).distance_to(Vector2(center)) <= radius:
				grid[y][x] = kind


## Река (v1.29.3): вертикальный меандр с севера на юг — синусоида с
## ограниченным наклоном. Русло рисуется РАССТОЯНИЕМ до кривой (клетка
## заливается, если её центр ближе 1.0 к оси): берега ступают по диагонали
## плавно, без «пилы» целых столбцов; ширина стабильно 2 тайла — мост
## перекрывает. Городское ядро без реки: старт/аномалия/выход + стены.
func _generate_river(rng: RandomNumberGenerator) -> void:
	# v1.31.2: коридор русла с запасом от края (раньше амплитуда заводила
	# реку за карту — на части сидов она вырождалась и исчезала)
	var base_x := float(rng.randi_range(int(w * 0.32), int(w * 0.68)))
	var amp := float(rng.randi_range(int(w * 0.06), int(w * 0.10)))
	var period := float(rng.randi_range(int(h * 0.9), int(h * 1.3)))
	var phase := rng.randf() * TAU
	var core := 9   # кольцо стен (6) + подходы снаружи; старт всегда в центре
	var sx := w / 2
	var sy := h / 2
	var last_cx := -99.0
	for y in h:
		var cx := base_x + sin(float(y) / period * TAU + phase) * amp
		# наклон русла ограничен — река течёт плавно, без ступенек
		cx = clampf(cx, last_cx - 0.6, last_cx + 0.6) if last_cx > -90.0 else cx
		last_cx = cx
		for x in range(maxi(1, int(cx) - 2), mini(w - 1, int(cx) + 3)):
			# городское ядро без реки: старт/аномалия/выход + кольцо стен
			if absi(x - sx) <= core and absi(y - sy) <= core:
				continue
			if absi(x - (w - 3)) <= 2 and absi(y - sy) <= 3:
				continue
			if x <= 3 and absi(y - sy) <= 3:
				continue
			if absf(float(x) + 0.5 - cx) <= 1.0:
				grid[y][x] = TILE_WATER
				river_origin[Vector2i(x, y)] = true


## Рудная жила: железо поверх скал и травы, но не поверх воды.
func _ore_blob(center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if Vector2(x, y).distance_to(Vector2(center)) <= radius \
					and (grid[y][x] == TILE_GRASS or grid[y][x] == TILE_ROCK):
				grid[y][x] = TILE_ORE


func _clear_around(center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x >= 0 and y >= 0 and x < w and y < h:
				grid[y][x] = TILE_GRASS


## Связность: от старта BFS-ом достижимы аномалия, выход на карту мира
## и заметная доля суши (иначе герой не дойдёт до края — карта перегенерируется).
func _connected() -> bool:
	var reachable := _reachable_from(spawn_tile)
	return reachable.has(anomaly_tile) and reachable.has(world_exit_tile) \
			and reachable.size() >= w * h / 2


func _reachable_from(from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if in_bounds(n) and not seen.has(n) and is_nature_walkable(n):
				seen[n] = true
				queue.append(n)
	return seen


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


## Направление наружу, если тайл на краю карты (рамка в 1 тайл — зона
## перехода на карту мира, M8). Угол даёт диагональ. центр — Vector2i.ZERO.
func border_dir(p: Vector2i) -> Vector2i:
	if not in_bounds(p):
		return Vector2i.ZERO
	var dir := Vector2i.ZERO
	if p.x == 0:
		dir.x = -1
	elif p.x == w - 1:
		dir.x = 1
	if p.y == 0:
		dir.y = -1
	elif p.y == h - 1:
		dir.y = 1
	return dir


## Ближайший проходимый тайл (спираль до радиуса 4); фолбэк — старт.
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
	return spawn_tile


## Размер дерева по броску 0..1: 30% малое, 45% среднее, 25% большое (v1.21).
static func _roll_tree_size(roll: float) -> int:
	if roll < 0.30:
		return TREE_SMALL
	if roll < 0.75:
		return TREE_MEDIUM
	return TREE_LARGE


## Размер дерева на тайле (без дерева — малое, фолбэк для старых сейвов).
func tree_kind(tile: Vector2i) -> int:
	return int(tree_size.get(tile, TREE_SMALL))


## Проходимость ландшафта (без учёта зданий). Руда и выработанный массив —
## как скала: непроходимы. Мост (M14-I) делает водный тайл проходимым.
func is_nature_walkable(p: Vector2i) -> bool:
	if in_bounds(p) and (bridges.has(p) or fords.has(p)):
		return true
	if not in_bounds(p):
		return false
	var t: int = grid[p.y][p.x]
	return t != TILE_WATER and t != TILE_ROCK and t != TILE_ORE and t != TILE_DEADROCK


func _setup_astar() -> void:
	astar = _new_astar()
	astar_raider = _new_astar()


## Свежая сетка A* с общими настройками карты (v1.26: сеток две — своя и мутантов).
func _new_astar() -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, w, h)
	g.cell_size = Vector2(ts, ts)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	g.update()
	return g


## Полная проходимость: ландшафт + построенные здания-преграды (частокол).
## Ворота сознательно НЕ сплошные: для своих это дверь (v1.26, заказчик —
## закрытые ворота не должны запирать жителей и героя).
func is_walkable(p: Vector2i) -> bool:
	return is_nature_walkable(p) and not (astar != null and astar.is_point_solid(p))


## Проходимость для мутантов: как is_walkable, но закрытые ворота — стена.
func is_raider_walkable(p: Vector2i) -> bool:
	if not is_nature_walkable(p):
		return false
	return not (astar_raider != null and astar_raider.is_point_solid(p))


## Пометить тайл непроходимым (поставлен частокол) — в обеих сетках.
func set_solid(p: Vector2i, solid: bool) -> void:
	if astar != null:
		astar.set_point_solid(p, solid)
	if astar_raider != null:
		astar_raider.set_point_solid(p, solid)


## Ворота для мутантов: closed=true — заперты (стена), false — открыты.
## Сетка своих ворот не видит вовсе (см. is_walkable).
func set_gate_solid(p: Vector2i, solid: bool) -> void:
	if astar_raider != null and in_bounds(p):
		astar_raider.set_point_solid(p, solid)


## Проложить дорогу (M6): тайл в слое дорог и «дешевле» для поиска пути.
func set_road(p: Vector2i, weight := 0.4) -> void:
	road[p] = true
	if astar != null:
		astar.set_point_weight_scale(p, weight)
	if astar_raider != null:
		astar_raider.set_point_weight_scale(p, weight)


## Убрать дорогу (под зданием) — вес тайла возвращается к обычному.
func remove_road(p: Vector2i) -> void:
	road.erase(p)
	if astar != null:
		astar.set_point_weight_scale(p, 1.0)
	if astar_raider != null:
		astar_raider.set_point_weight_scale(p, 1.0)


func has_road(p: Vector2i) -> bool:
	return road.has(p)


## Износ тропы (M6): жители протаптывают тайлы, где ходят.
func add_wear(p: Vector2i, amount: float) -> void:
	wear[p] = float(wear.get(p, 0.0)) + amount


## Путь между тайлами в пиксельных центрах; пустой, если цели нет.
## for_raider — путь мутанта: закрытые ворота для него сплошные (v1.26).
func path_px(from_px: Vector2, to_tile: Vector2i, for_raider := false) -> PackedVector2Array:
	var from_tile := Vector2i(from_px / ts)
	if not in_bounds(from_tile) or not in_bounds(to_tile) or not is_walkable(to_tile):
		return PackedVector2Array()
	var grid := astar_raider if for_raider else astar
	var ids := grid.get_id_path(from_tile, to_tile)
	var points := PackedVector2Array()
	for id: Vector2i in ids:
		points.append(Vector2(id.x * ts + ts / 2.0, id.y * ts + ts / 2.0))
	return points


func tile_center_px(p: Vector2i) -> Vector2:
	return Vector2(p.x * ts + ts / 2.0, p.y * ts + ts / 2.0)


func tile_of_px(px: Vector2) -> Vector2i:
	return Vector2i(px / ts)
