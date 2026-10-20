extends Node2D
## Светлячки и болотные огоньки (M14-C + сказочная правка 2026-10-20).
## Ночью в городе: тёплые светлячки над деревьями и лугами, холодные огоньки
## у воды. У каждого — многослойное гало и искры-блики; поверх — несколько
## настоящих PointLight2D, которые медленно кочуют между стайками и льют
## живой свет на землю. Днём всё погашено (alpha задаёт сцена через night).

const FLY_COLOR := Color(1.0, 0.88, 0.42)
const FLY_COLOR2 := Color(0.85, 1.0, 0.55)
const WISP_COLOR := Color(0.5, 0.95, 0.85)
const WISP_COLOR2 := Color(0.45, 0.7, 1.0)
const FLY_COUNT := 24
const WISP_COUNT := 14
const LIGHT_COUNT := 6

var night := 0.0
var _flies: Array = []   # {base: Vector2, phase: float, span: float}
var _wisps: Array = []
var _lights: Array = []  # PointLight2D — «живой свет» стай
var _time := 0.0
var _seed := 20261020


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
	var lowlands: Array = []
	for t: Vector2i in water:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if city_map.in_bounds(n) and int(city_map.grid[n.y][n.x]) == city_map.TILE_GRASS:
				lowlands.append(n)
	for i in FLY_COUNT:
		if trees.is_empty() and meadows.is_empty():
			break
		var src: Array = meadows if (not meadows.is_empty() and i % 4 == 0) else trees
		if src.is_empty():
			src = meadows
		var t: Vector2i = src[_warp_rand(src.size())]
		_flies.append({
			"base": city_map.tile_center_px(t) + Vector2(_warp_rand(21) - 10, _warp_rand(21) - 10),
			"phase": float(i) * 1.7, "span": 10.0 + _warp_rand(9),
		})
	for i in WISP_COUNT:
		var pool: Array = water if not water.is_empty() else lowlands
		if pool.is_empty():
			break
		var t2: Vector2i = pool[_warp_rand(pool.size())]
		_wisps.append({
			"base": city_map.tile_center_px(t2) + Vector2(_warp_rand(15) - 7, _warp_rand(15) - 7),
			"phase": float(i) * 2.3, "span": 14.0 + _warp_rand(10),
		})


func _ready() -> void:
	# «живой свет»: несколько мягких источников кочуют между стайками
	for i in LIGHT_COUNT:
		var l := PointLight2D.new()
		l.texture = _glow_texture()
		l.texture_scale = 3.2
		l.color = FLY_COLOR if i < LIGHT_COUNT / 2 else WISP_COLOR
		l.energy = 0.0
		l.enabled = false
		add_child(l)
		_lights.append(l)


func _glow_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex


func _process(delta: float) -> void:
	_time += delta
	if night <= 0.01:
		for l in _lights:
			if l.enabled:
				l.enabled = false
		return
	queue_redraw()
	# света дышат и дрейфуют вокруг своих стай
	for i in _lights.size():
		var pool: Array = _flies if i < _lights.size() / 2 else _wisps
		var l: PointLight2D = _lights[i]
		if pool.is_empty():
			l.enabled = false
			continue
		var anchor: Dictionary = pool[i % pool.size()]
		var t2 := _time * 0.13 + float(i) * 2.1
		l.enabled = true
		l.position = (anchor["base"] as Vector2) + Vector2(sin(t2) * 22.0, cos(t2 * 0.8) * 15.0)
		l.energy = night * (0.6 + 0.25 * sin(_time * 1.2 + float(i) * 1.9))


## Детерминированный «случайный» для setup (важен стабильный вид, не честность).
func _warp_rand(n: int) -> int:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return _seed % maxi(1, n)


func _draw() -> void:
	if night <= 0.01:
		return
	for i in _flies.size():
		var f: Dictionary = _flies[i]
		var pos: Vector2 = f["base"] + Vector2(
				sin(_time * 0.9 + f["phase"]) * f["span"],
				sin(_time * 1.3 + f["phase"] * 1.6) * f["span"] * 0.6)
		var blink := 0.55 + 0.45 * sin(_time * 3.0 + f["phase"] * 2.0)
		var col: Color = FLY_COLOR.lerp(FLY_COLOR2, 0.5 + 0.5 * sin(_time * 0.4 + f["phase"]))
		# трёхслойное свечение: гало → ореол → ядро
		draw_circle(pos, 7.0, Color(col.r, col.g, col.b, 0.08 * night))
		draw_circle(pos, 3.2, Color(col.r, col.g, col.b, 0.30 * night * blink))
		draw_circle(pos, 1.4, Color(1.0, 0.98, 0.85, night * blink))
		# искры-блики у каждой третьей
		if i % 3 == 0:
			var s := 3.5 * blink * night
			draw_line(pos + Vector2(-s, 0), pos + Vector2(s, 0), Color(1, 1, 0.9, 0.5 * night * blink), 0.8)
			draw_line(pos + Vector2(0, -s), pos + Vector2(0, s), Color(1, 1, 0.9, 0.5 * night * blink), 0.8)
	for j in _wisps.size():
		var w: Dictionary = _wisps[j]
		var pos2: Vector2 = w["base"] + Vector2(
				sin(_time * 0.5 + w["phase"]) * w["span"],
				cos(_time * 0.7 + w["phase"] * 1.2) * 3.0)
		var flicker := 0.5 + 0.5 * sin(_time * 1.7 + w["phase"] * 3.0)
		var col2: Color = WISP_COLOR.lerp(WISP_COLOR2, 0.5 + 0.5 * sin(_time * 0.3 + w["phase"]))
		draw_circle(pos2, 10.0, Color(col2.r, col2.g, col2.b, 0.07 * night))
		draw_circle(pos2, 5.0, Color(col2.r, col2.g, col2.b, 0.22 * night * flicker))
		draw_circle(pos2, 2.0, Color(0.92, 1.0, 0.98, night * flicker))
		# «дыхание» огонька: расходящееся кольцо
		var ripple := fmod(_time * 0.6 + w["phase"], 2.0)
		draw_arc(pos2, 6.0 + ripple * 9.0, 0.0, TAU, 24,
				Color(col2.r, col2.g, col2.b, (0.35 - ripple * 0.15) * night * flicker), 1.2)
