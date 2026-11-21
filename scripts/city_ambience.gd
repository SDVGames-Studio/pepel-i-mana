extends Node2D
## Светлячки и болотные огоньки (M14-C + сказочная правка 2026-10-20).
## Ночью в городе: тёплые светлячки над деревьями и лугами, холодные огоньки
## у воды. У каждого — многослойное гало и искры-блики; поверх — настоящие
## PointLight2D. Днём всё погашено (alpha задаёт сцена через night).
##
## v1.79.14 (заказчик: «источники света не издают света, где светлячки и
## болотные огоньки?»): раньше 24 светлячка и 14 огоньков были рассыпаны
## по ВСЕЙ карте 384×288 — в деревне на экране их не бывало. Теперь:
## 1) стайки живут ВОКРУГ ДЕРЕВНИ (радиус VILLAGE_R тайлов от спавна);
## 2) у костра площади и у домов — уличные огни: тёплое гало + свой
##    PointLight2D (перестраиваются при постройке зданий);
## 3) плотность поднята (36/22/8+10+1 источников).

const FLY_COLOR := Color(1.0, 0.88, 0.42)
const FLY_COLOR2 := Color(0.85, 1.0, 0.55)
const WISP_COLOR := Color(0.5, 0.95, 0.85)
const WISP_COLOR2 := Color(0.45, 0.7, 1.0)
const FLY_COUNT := 36
const WISP_COUNT := 22
const LIGHT_COUNT := 5        # кочующие огни стай (v1.80.1: 8→5, FPS)
const STREET_LIGHT_MAX := 8   # фонари у домов (v1.80.1: 10→8, FPS)
const VILLAGE_R := 50         # радиус деревни (тайлы) — тут живут стайки

var night := 0.0
var map = null              # карта города (v1.29.4: центры тайлов берега для света)
var _sim = null             # v1.79.14: костёр/здания для уличных огней
var _flies: Array = []   # {base: Vector2, phase: float, span: float}
var _wisps: Array = []
var _lowlands: Array = []   # трава у воды: берег — свет, не сама вода
var _lights: Array = []  # PointLight2D — «живой свет» стай
var _street: Array = []  # v1.79.14: уличные огни {pos, fl}
var _street_lights: Array = []  # PointLight2D у домов
var _fire_light: PointLight2D = null  # PointLight2D костра
var _fire_pos := Vector2.ZERO
var _bld_seen := -1         # число зданий на последней сборке уличных огней
var _time := 0.0
var _seed := 20261020


func setup(city_map, sim = null) -> void:
	map = city_map
	_sim = sim
	_flies = []
	_wisps = []
	_lowlands = []
	_street = []
	var center: Vector2i = city_map.spawn_tile
	var trees: Array = []
	var meadows: Array = []
	var water: Array = []
	var trees_all: Array = []
	var meadows_all: Array = []
	var water_all: Array = []
	for y in city_map.h:
		for x in city_map.w:
			var t := Vector2i(x, y)
			var near: bool = Vector2(t - center).length() <= float(VILLAGE_R)
			match int(city_map.grid[y][x]):
				city_map.TILE_TREE:
					trees_all.append(t)
					if near:
						trees.append(t)
				city_map.TILE_GRASS:
					meadows_all.append(t)
					if near:
						meadows.append(t)
				city_map.TILE_WATER:
					water_all.append(t)
					if near:
						water.append(t)
	# v1.79.14: если у деревни своих деревьев/воды мало — добираем со всей
	# карты (стайки всё равно тяготеют к центру, см. смешение ниже)
	if trees.size() < 8:
		trees = trees_all
	if meadows.size() < 8:
		meadows = meadows_all
	if water.size() < 6:
		water = water_all
	for t: Vector2i in water:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if city_map.in_bounds(n) and int(city_map.grid[n.y][n.x]) == city_map.TILE_GRASS:
				_lowlands.append(n)
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
		var pool: Array = water if not water.is_empty() else _lowlands
		if pool.is_empty():
			break
		var t2: Vector2i = pool[_warp_rand(pool.size())]
		_wisps.append({
			"base": city_map.tile_center_px(t2) + Vector2(_warp_rand(15) - 7, _warp_rand(15) - 7),
			"phase": float(i) * 2.3, "span": 14.0 + _warp_rand(10),
		})
	_build_street(center)


## Уличные огни: костёр у площади + тёплые фонари у активных зданий рядом
## с центром. Вызывается из setup и из _process при изменении числа зданий.
func _build_street(center: Vector2i) -> void:
	if _sim == null or map == null:
		return
	_street = []
	var blds: Array = _sim.get("buildings") if _sim.get("buildings") != null else []
	# костёр там же, где рисует view: у колодца, иначе в центре (M12)
	var fire := center
	for b in blds:
		if _sim._active(b) and String(b["type"]) == "well":
			fire = Vector2i(b["tile"]) + Vector2i(1, 0)
			break
	_fire_pos = map.tile_center_px(fire) + Vector2(0, 4)
	var n := 0
	for b in blds:
		if n >= STREET_LIGHT_MAX:
			break
		if not _sim._active(b):
			continue
		var bt := Vector2i(b["tile"])
		if Vector2(bt - center).length() > 40.0:
			continue
		_street.append({
			"pos": map.tile_center_px(bt) + Vector2(0, -map.ts * 0.6),
			"fl": float(n) * 1.7,
		})
		n += 1
	_bld_seen = blds.size()
	_sync_street_lights()


func _sync_street_lights() -> void:
	while _street_lights.size() < _street.size() + 1:
		var l := PointLight2D.new()
		l.texture = _glow_texture()
		l.color = Color(1.0, 0.72, 0.38)
		l.enabled = false
		add_child(l)
		_street_lights.append(l)
	# [0] — костёр, остальные — дома
	for i in _street_lights.size():
		var l2: PointLight2D = _street_lights[i]
		if i == 0:
			l2.position = _fire_pos
			l2.color = Color(1.0, 0.58, 0.26)
			l2.texture_scale = 2.6
		elif i - 1 < _street.size():
			l2.position = _street[i - 1]["pos"]
			l2.color = Color(1.0, 0.72, 0.38)
			l2.texture_scale = 1.6
		else:
			l2.enabled = false
			l2.position = Vector2(-99999, -99999)


func _ready() -> void:
	# «живой свет»: несколько мягких источников кочуют между стайками.
	# v1.29.4: источник ВДВОЕ меньше и втрое слабее; свет огоньков у воды
	# кочует по БЕРЕГУ, а не по воде — раньше большие гало PointLight2D
	# заливали реку/озеро светом, и вода ночью «белела» (замечание заказчика)
	for i in LIGHT_COUNT:
		var l := PointLight2D.new()
		l.texture = _glow_texture()
		l.texture_scale = 1.5
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
	# дома перестраиваются — уличные огни следят за списком зданий
	if _sim != null and (_sim.get("buildings") as Array).size() != _bld_seen:
		_build_street(_sim.map.spawn_tile)
	if night <= 0.01:
		for l in _lights:
			if l.enabled:
				l.enabled = false
		for l2 in _street_lights:
			if l2.enabled:
				l2.enabled = false
		return
	queue_redraw()
	# света дышат и дрейфуют вокруг своих стай; свет «у воды» — по берегу
	for i in _lights.size():
		var l: PointLight2D = _lights[i]
		var base := Vector2.ZERO
		if i < _lights.size() / 2:
			if _flies.is_empty():
				l.enabled = false
				continue
			base = _flies[i % _flies.size()]["base"]
		else:
			if _lowlands.is_empty() or map == null:
				l.enabled = false
				continue
			base = map.tile_center_px(_lowlands[i % _lowlands.size()])
		var t2 := _time * 0.13 + float(i) * 2.1
		l.enabled = true
		l.position = base + Vector2(sin(t2) * 22.0, cos(t2 * 0.8) * 15.0)
		l.energy = night * (0.35 + 0.15 * sin(_time * 1.2 + float(i) * 1.9))
	# v1.79.14: уличные огни — костёр и фонари домов
	for i in _street_lights.size():
		var l3: PointLight2D = _street_lights[i]
		if i == 0:
			l3.enabled = true
			l3.energy = night * (0.85 + 0.15 * sin(_time * 7.0))   # пламя живое
		elif i - 1 < _street.size():
			l3.enabled = true
			l3.energy = night * (0.42 + 0.06 * sin(_time * 2.3 + _street[i - 1]["fl"]))
		# выключенные (лишние) уже спрятаны в _sync_street_lights


## Детерминированный «случайный» для setup (важен стабильный вид, не честность).
func _warp_rand(n: int) -> int:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return _seed % maxi(1, n)


func _draw() -> void:
	if night <= 0.01:
		return
	# v1.79.14: гало уличных огней (костёр — крупный, живой; дома — тёплый)
	var glow := 0.22 + 0.06 * sin(_time * 7.0)
	draw_circle(_fire_pos, map.ts * 2.4, Color(1.0, 0.62, 0.28, glow * night))
	draw_circle(_fire_pos, map.ts * 1.2, Color(1.0, 0.7, 0.32, 0.4 * night))
	for s in _street:
		var p: Vector2 = s["pos"]
		var fl: float = 0.13 + 0.03 * sin(_time * 2.3 + s["fl"])
		draw_circle(p, map.ts * 1.3, Color(1.0, 0.72, 0.38, fl * night))
		draw_circle(p, map.ts * 0.22, Color(1.0, 0.85, 0.55, 0.55 * night))
	for i in _flies.size():
		var f: Dictionary = _flies[i]
		var pos: Vector2 = f["base"] + Vector2(
				sin(_time * 0.9 + f["phase"]) * f["span"],
				sin(_time * 1.3 + f["phase"] * 1.6) * f["span"] * 0.6)
		var blink := 0.55 + 0.45 * sin(_time * 3.0 + f["phase"] * 2.0)
		var col: Color = FLY_COLOR.lerp(FLY_COLOR2, 0.5 + 0.5 * sin(_time * 0.4 + f["phase"]))
		# трёхслойное свечение: гало → ореол → ядро
		draw_circle(pos, 7.0, Color(col.r, col.g, col.b, 0.10 * night))
		draw_circle(pos, 3.2, Color(col.r, col.g, col.b, 0.34 * night * blink))
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
		draw_circle(pos2, 10.0, Color(col2.r, col2.g, col2.b, 0.09 * night))
		draw_circle(pos2, 5.0, Color(col2.r, col2.g, col2.b, 0.26 * night * flicker))
		draw_circle(pos2, 2.0, Color(0.92, 1.0, 0.98, night * flicker))
		# «дыхание» огонька: расходящееся кольцо
		var ripple := fmod(_time * 0.6 + w["phase"], 2.0)
		draw_arc(pos2, 6.0 + ripple * 9.0, 0.0, TAU, 24,
				Color(col2.r, col2.g, col2.b, (0.35 - ripple * 0.15) * night * flicker), 1.2)
