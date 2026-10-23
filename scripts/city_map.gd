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
var grid: Array = []            # grid[y][x] -> TILE_*
var road := {}                  # Vector2i -> true: дороги (M6) — ускорение и приоритет путей
var wear := {}                  # Vector2i -> float: износ троп (M6) — город сам строит дороги там, где ходят
var rock_hp := {}               # Vector2i -> float: запас скалы (M11) — добыча истощает тайл
var stumps := {}                # Vector2i -> true: пни на месте срубленных деревьев (M11)
var saplings := {}              # Vector2i -> {t: float}: посаженные деревья, растут (M11)
var tree_size := {}             # Vector2i -> int (TREE_SMALL/MEDIUM/LARGE): размер дерева (v1.21)
var tree_growth := {}           # Vector2i -> float: дни роста дерева до следующего размера (v1.21)
var bridges := {}               # Vector2i -> true: мосты через воду (M14-I)
var anomaly_tile := Vector2i.ZERO   # вход в данж (у аномалии)
var spawn_tile := Vector2i.ZERO     # старт героя и жителей
var world_exit_tile := Vector2i.ZERO  # край города — выход на карту мира (M8)
var astar: AStarGrid2D = null


## Генерация по seed: детерминированная, связная (от старта достижимы все проходимые тайлы).
func generate(seed_value: int, params: Dictionary) -> void:
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
	bridges = {}
	for attempt in 20:
		_generate_once(seed_value + attempt * 1013, params)
		if _connected():
			break
	_setup_astar()
	mark_terrain_solid()


## Природные препятствия (вода, скалы, руда) — сплошные для A* (этап 2:
## мутанты и жители больше не срезают через озёра и скалы). Мосты открывают
## воду (is_nature_walkable учитывает их), деревья проходимы по дизайну —
## на них стоят лесорубы и герой при рубке.
func mark_terrain_solid() -> void:
	if astar == null:
		return
	for y in h:
		for x in w:
			astar.set_point_solid(Vector2i(x, y), not is_nature_walkable(Vector2i(x, y)))


## Пересчитать сплошность одной клетки после изменения рельефа
## (мост построен, скала выработана, вскрыта руда).
func refresh_tile_solid(p: Vector2i) -> void:
	if astar != null and in_bounds(p):
		astar.set_point_solid(p, not is_nature_walkable(p))


func _generate_once(seed_value: int, params: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	grid = []
	for y in h:
		var row := []
		row.resize(w)
		row.fill(TILE_GRASS)
		grid.append(row)
	# озёра — круглые пятна, не у краёв
	for i in int(params["lakes"]):
		_blob(_random_inner_tile(rng), rng.randi_range(2, 4), TILE_WATER)
	# скальные ГРЯДЫ (M11): не россыпь одиночных камней, а единые массивы —
	# большое пятно плюс сателлиты внахлёст; в них живёт руда и их добывают
	for i in int(params.get("rocks", 2)):
		var center := _random_inner_tile(rng)
		_blob(center, rng.randi_range(4, 6), TILE_ROCK)
		for s in 2:
			var off := Vector2i(rng.randi_range(-6, 6), rng.randi_range(-5, 5))
			_blob(center + off, rng.randi_range(2, 3), TILE_ROCK)
	# рудные жилы: железо в скалах и на голой земле — места под шахту (M5+)
	for i in int(params.get("ore_spots", 0)):
		_ore_blob(_random_inner_tile(rng), rng.randi_range(1, 2))
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


func _random_inner_tile(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))


## Пятно круглой формы из тайлов kind (не поверх друг друга — вода поверх скалы допустима).
func _blob(center: Vector2i, radius: int, kind: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if Vector2(x, y).distance_to(Vector2(center)) <= radius:
				grid[y][x] = kind


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
	if in_bounds(p) and bridges.has(p):
		return true
	if not in_bounds(p):
		return false
	var t: int = grid[p.y][p.x]
	return t != TILE_WATER and t != TILE_ROCK and t != TILE_ORE and t != TILE_DEADROCK


func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(ts, ts)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()


## Полная проходимость: ландшафт + построенные здания-преграды (частокол).
func is_walkable(p: Vector2i) -> bool:
	return is_nature_walkable(p) and not (astar != null and astar.is_point_solid(p))


## Пометить тайл непроходимым (поставлен частокол) — для путей жителей.
func set_solid(p: Vector2i, solid: bool) -> void:
	astar.set_point_solid(p, solid)


## Проложить дорогу (M6): тайл в слое дорог и «дешевле» для поиска пути.
func set_road(p: Vector2i, weight := 0.4) -> void:
	road[p] = true
	if astar != null:
		astar.set_point_weight_scale(p, weight)


## Убрать дорогу (под зданием) — вес тайла возвращается к обычному.
func remove_road(p: Vector2i) -> void:
	road.erase(p)
	if astar != null:
		astar.set_point_weight_scale(p, 1.0)


func has_road(p: Vector2i) -> bool:
	return road.has(p)


## Износ тропы (M6): жители протаптывают тайлы, где ходят.
func add_wear(p: Vector2i, amount: float) -> void:
	wear[p] = float(wear.get(p, 0.0)) + amount


## Путь между тайлами в пиксельных центрах; пустой, если цели нет.
func path_px(from_px: Vector2, to_tile: Vector2i) -> PackedVector2Array:
	var from_tile := Vector2i(from_px / ts)
	if not in_bounds(from_tile) or not in_bounds(to_tile) or not is_walkable(to_tile):
		return PackedVector2Array()
	var ids := astar.get_id_path(from_tile, to_tile)
	var points := PackedVector2Array()
	for id: Vector2i in ids:
		points.append(Vector2(id.x * ts + ts / 2.0, id.y * ts + ts / 2.0))
	return points


func tile_center_px(p: Vector2i) -> Vector2:
	return Vector2(p.x * ts + ts / 2.0, p.y * ts + ts / 2.0)


func tile_of_px(px: Vector2) -> Vector2i:
	return Vector2i(px / ts)
