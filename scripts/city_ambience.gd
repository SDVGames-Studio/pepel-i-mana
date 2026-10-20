extends Node2D
## Светлячки и болотные огоньки (M14-C, issue #3 T21/T23). Один узел, одна
## перерисовка в кадр: светлячки (тёплые) дремлют на деревьях и лугах,
## огоньки (холодные) горят у воды — влажные низины, до болот из M14-I.
## Видны только ночью: alpha задаёт сцена через night (0 — день, 1 — ночь).

const FLY_COLOR := Color(1.0, 0.9, 0.45)
const WISP_COLOR := Color(0.5, 0.95, 0.85)
const FLY_COUNT := 18
const WISP_COUNT := 12

var night := 0.0
var _flies: Array = []   # {base: Vector2, phase: float, span: float}
var _wisps: Array = []
var _time := 0.0


func setup(city_map) -> void:
	_flies = []
	_wisps = []
	var trees: Array = []
	var meadows: Array = []
	var water: Array = []
	for y in city_map.h:
		for x in city_map.w:
			var t := Vector2i(x, y)
			match int(city_map.grid[y][x]):
				city_map.TILE_TREE:
					trees.append(t)
				city_map.TILE_GRASS:
					meadows.append(t)
				city_map.TILE_WATER:
					water.append(t)
	# низины: трава рядом с водой — там тоже мерцают огоньки
	var lowlands: Array = []
	for t: Vector2i in water:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if city_map.in_bounds(n) and int(city_map.grid[n.y][n.x]) == city_map.TILE_GRASS:
				lowlands.append(n)
	for i in FLY_COUNT:
		var pool: Array = trees if not trees.is_empty() else meadows
		if pool.is_empty():
			break
		# светлячки: чаще у деревьев, каждая четвёртая — на лугу
		var src: Array = meadows if (not meadows.is_empty() and i % 4 == 0) else pool
		var t: Vector2i = src[_warp_rand(src.size())]
		_flies.append({
			"base": city_map.tile_center_px(t) + Vector2(_warp_rand(21) - 10, _warp_rand(21) - 10),
			"phase": float(i) * 1.7, "span": 10.0 + _warp_rand(8),
		})
	for i in WISP_COUNT:
		var pool2: Array = water if not water.is_empty() else lowlands
		if pool2.is_empty():
			break
		var t2: Vector2i = pool2[_warp_rand(pool2.size())]
		_wisps.append({
			"base": city_map.tile_center_px(t2) + Vector2(_warp_rand(15) - 7, _warp_rand(15) - 7),
			"phase": float(i) * 2.3, "span": 14.0 + _warp_rand(10),
		})


## Детерминированный «случайный» без RandomNumberGenerator: setup зовётся
## один раз, стабильный вид важнее честной случайности.
func _warp_rand(n: int) -> int:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return _seed % maxi(1, n)

var _seed := 20261020


func _process(delta: float) -> void:
	_time += delta
	if night > 0.01:
		queue_redraw()


func _draw() -> void:
	if night <= 0.01:
		return
	for f in _flies:
		var pos: Vector2 = f["base"] + Vector2(
				sin(_time * 0.9 + f["phase"]) * f["span"],
				sin(_time * 1.3 + f["phase"] * 1.6) * f["span"] * 0.6)
		var blink := 0.55 + 0.45 * sin(_time * 3.0 + f["phase"] * 2.0)
		draw_circle(pos, 3.5, Color(FLY_COLOR.r, FLY_COLOR.g, FLY_COLOR.b, 0.16 * night * blink))
		draw_circle(pos, 1.4, Color(FLY_COLOR.r, FLY_COLOR.g, FLY_COLOR.b, night * blink))
	for w in _wisps:
		var pos2: Vector2 = w["base"] + Vector2(
				sin(_time * 0.5 + w["phase"]) * w["span"],
				cos(_time * 0.7 + w["phase"] * 1.2) * 3.0)
		var flicker := 0.5 + 0.5 * sin(_time * 1.7 + w["phase"] * 3.0)
		draw_circle(pos2, 5.0, Color(WISP_COLOR.r, WISP_COLOR.g, WISP_COLOR.b, 0.13 * night * flicker))
		draw_circle(pos2, 1.8, Color(WISP_COLOR.r, WISP_COLOR.g, WISP_COLOR.b, night * flicker))
