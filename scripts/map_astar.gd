extends RefCounted
## A*-сетка карты города с УРОВНЯМИ ВЫСОТЫ (этап «Многоуровневый рельеф»,
## ответы №113–115). У AStarGrid2D нет цены РЕБРА, а правило этапа —
## «на плато подняться можно только через проход-лестницу», то есть запрет
## именно перехода тайл→тайл, а не тайла целиком.
##
## Поэтому сетка — C++ AStar2D с ЯВНЫМИ рёбрами: соседи соединяются только
## при равных уровнях или если на одном из концов лестница (map.stairs).
## Отвес плато непроходим для жителей, героя и мутантов (№113). Скорость —
## как у прежней AStarGrid2D (GDScript-реализация A* не влезала в бюджет
## тика осады 25 мс). Интерфейс повторяет используемую часть AStarGrid2D:
##   set_point_solid / is_point_solid / set_point_weight_scale / get_id_path.
## Чистая логика, тестируется headless (как city_map).


var w := 0
var h := 0
var astar: AStar2D = null
var height: Dictionary = {}      # Vector2i -> int (0 — равнина)
var stairs: Dictionary = {}      # Vector2i -> true (проход между уровнями)
var solid: Dictionary = {}       # Vector2i -> true (вода/скалы/здания/ворота)

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


func setup(map_w: int, map_h: int, ts: float, map_height: Dictionary,
		map_stairs: Dictionary) -> void:
	w = map_w
	h = map_h
	height = map_height
	stairs = map_stairs
	solid = {}
	astar = AStar2D.new()
	for y in h:
		for x in w:
			astar.add_point(y * w + x, Vector2(x, y))
	for y in h:
		for x in w:
			_reconnect(Vector2i(x, y))


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


func _id(p: Vector2i) -> int:
	return p.y * w + p.x


## Ребро соседей разрешено: уровень тот же ИЛИ один из концов — лестница.
func edge_ok(a: Vector2i, b: Vector2i) -> bool:
	if stairs.has(a) or stairs.has(b):
		return true
	return level_at(a) == level_at(b)


## Уровень тайла (0 — равнина; вне карты — 0).
func level_at(p: Vector2i) -> int:
	return int(height.get(p, 0))


## Соединить тайл с соседями по правилу уровней (сплошные не соединяются).
func _reconnect(p: Vector2i) -> void:
	if solid.has(p):
		return
	for d in DIRS:
		var n: Vector2i = p + d
		if in_bounds(n) and not solid.has(n) and edge_ok(p, n):
			astar.connect_points(_id(p), _id(n))


func set_point_solid(p: Vector2i, is_solid: bool) -> void:
	if not in_bounds(p):
		return
	if is_solid:
		solid[p] = true
		for d in DIRS:
			var n: Vector2i = p + d
			if in_bounds(n):
				astar.disconnect_points(_id(p), _id(n))
	else:
		solid.erase(p)
		_reconnect(p)


func is_point_solid(p: Vector2i) -> bool:
	return solid.has(p)


func set_point_weight_scale(p: Vector2i, wscale: float) -> void:
	if in_bounds(p):
		astar.set_point_weight_scale(_id(p), wscale)


## Путь A*: массив Vector2i от начала до цели; пустой — пути нет.
func get_id_path(from_id: Vector2i, to_id: Vector2i) -> Array:
	if not in_bounds(from_id) or not in_bounds(to_id) \
			or solid.has(from_id) or solid.has(to_id):
		return []
	var ids: PackedInt64Array = astar.get_id_path(_id(from_id), _id(to_id))
	var out: Array = []
	for id: int in ids:
		out.append(Vector2i(id % w, id / w))
	return out
