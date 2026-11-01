extends Node2D
## ВОДА «Природы 2.0» (v1.39.0; FPS-оптимизация и органическое болото —
## v1.39.1, правки приёмки). ЖИВОЙ слой города: вода анимируется, поэтому
## не печётся в общий ландшафт, а рисуется поверх запечённой земли.
##
## АРХИТЕКТУРА ПРОИЗВОДИТЕЛЬНОСТИ (v1.39.1, фидбек «и фпс»):
##   СТАТИКА (фактура тайлов, мель, скругления, глубина, болотная тина,
##   кочки, оконца, песок бродов, тёмный ореол вокруг болот) — запекается
##   в СВОЙ SubViewport один раз на версию сетки (мост/выработка породы),
##   в кадре — один текстурированный квад;
##   ЖИВОЕ (пена, струи течения, ряби, камыши, искорки брода) — рисуется
##   поверх с КАПОМ 15 к/с (глазу хватает, нагрузка в 4 раза ниже).
##
## Язык кромок — PER-TILE, как у принятых плато v1.36 (EdgeLang): у
## берегового тайла сторона к суше получает мель-пояс, выпуклые углы
## скругляются четверть-диском (ступени тайлов не читаются). Блобы НЕ
## используются: сшивка marching-squares разваливалась на седловых
## точках меандра (урок v1.39.0).
##
## Типы воды (свой тон у трёх типов, №112):
##   озеро  — глубокая синь, мель, глубина к югу, кувшинки и ряби;
##   река   — светлее, течение (бегущие струи), мель;
##   болото — ОРГАНИЧЕСКОЕ (v1.39.1: та же кромка, что у озера, вместо
##            квадратной лужи): мутная фактура, тина, кочки, оконца,
##            камыши, тёмный ореол земли вокруг.
## Тюнинг: data/city.json → colors → "water2" (anim_fps, foam_*, reed_*).

var terrain                 # city_terrain — карта, хэш-утилиты, цвета
var map = null
var colors: Dictionary = {}
var _texs := {}             # kind -> Texture2D (полоса 3 тайлов 96x32)
var _time := 0.0
var _cache_ver := -1
var _coast: Array = []      # [{tile, sides:[Vector2i]}] — береговые тайлы
var _inner: Array = []      # открытая вода (8 соседей — вода): рябь/кувшинки
var _swamp_tiles: Array = []
var _swamp_near: Array = [] # трава вокруг болота (тёмный ореол + камыши)
var _ford_tiles: Array = []

# --- запечка статики ---
var _vp: SubViewport = null
var _sd: Node2D = null      # статичный рисовальщик в запечку
var _baked: Texture2D = null
var _bake_dirty := true
var _out: Object = null     # куда рисует хелпер: _sd (запечка) или self (живое)

# --- кап живой перерисовки (15 к/с) ---
const ANIM_FPS_CAP := 15.0
var _anim_accum := 0.0

const EdgeLangC := preload("res://scripts/edge_lang.gd")
const TS := 32


func setup(terrain_ref, cfg_colors: Dictionary) -> void:
	terrain = terrain_ref
	map = terrain_ref.map
	colors = cfg_colors
	for kind in ["lake", "river", "swamp"]:
		_texs[kind] = Assets.tex("res://assets/sprites/env/n2_water_%s.png" % kind)
	# духовка статики: размером с карту, NEAREST, UPDATE_ONCE
	_vp = SubViewport.new()
	_vp.size = Vector2i(map.w * map.ts, map.h * map.ts)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_sd = Node2D.new()
	_sd.draw.connect(_draw_static)
	_vp.add_child(_sd)
	_baked = _vp.get_texture()


func _ready() -> void:
	# первый bake — из _ready (в дереве), как у city_terrain: запекать
	# во время чужого _draw() нельзя (урок v1.39.1: сигнатура draw
	# срабатывала вне режима рисования и спамила ошибками движка)
	_do_bake()


func _process(delta: float) -> void:
	_time += delta
	# рельеф менялся (мост/выработка) — перевыпечь статику воды
	_ensure_cache()
	if _bake_dirty:
		_do_bake()
	# кап анимации: перерисовываем живой слой не чаще ANIM_FPS_CAP
	_anim_accum += delta
	if _anim_accum >= 1.0 / ANIM_FPS_CAP:
		_anim_accum = 0.0
		queue_redraw()


## Запечь статику воды в SubViewport (НЕ из _draw!).
func _do_bake() -> void:
	if _vp == null or not is_inside_tree():
		return
	_bake_dirty = false
	_sd.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _fps() -> float:
	return float(colors.get("water2", {}).get("anim_fps", 5.0))


func _opt(section: String, key: String, def: float) -> float:
	return float(colors.get("water2", {}).get(section, {}).get(key, def))


## Кэш берегов и открытой воды — перестраивается при смене версии сетки.
func _ensure_cache() -> void:
	if map == null or (_cache_ver == map.grid_ver and not _coast.is_empty()):
		return
	_cache_ver = map.grid_ver
	_coast = []
	_inner = []
	_swamp_tiles = []
	_swamp_near = []
	_ford_tiles = []
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			var g: int = map.grid[y][x]
			if g == map.TILE_WATER:
				var sides: Array = []
				for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					var n: Vector2i = t + d
					if not map.in_bounds(n) or map.grid[n.y][n.x] != map.TILE_WATER:
						sides.append(d)
				if not sides.is_empty():
					_coast.append({"tile": t, "sides": sides})
				elif _water_neighbors8(t) == 8:
					_inner.append(t)
				if map.water_kind_at(t) == "swamp":
					_swamp_tiles.append(t)
				if map.fords.has(t):
					_ford_tiles.append(t)
			elif g == map.TILE_GRASS and _near_swamp(t):
				_swamp_near.append(t)
	_bake_dirty = true


func _water_neighbors8(t: Vector2i) -> int:
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var p := t + Vector2i(dx, dy)
			if map.in_bounds(p) and map.grid[p.y][p.x] == map.TILE_WATER:
				n += 1
	return n


func _kind_at(t: Vector2i) -> String:
	var k: String = map.water_kind_at(t)
	return k if k != "" else "lake"


func _draw() -> void:
	if map == null or _vp == null:
		return
	if _baked != null:
		draw_texture_rect(_baked, Rect2(Vector2.ZERO,
				Vector2(map.w * map.ts, map.h * map.ts)), false)
	# живое поверх статики: пена, течение, ряби, камыши, искорки
	_out = self
	var ts := float(map.ts)
	for c in _coast:
		var t: Vector2i = c["tile"]
		match _kind_at(t):
			"lake":
				for side: Vector2i in c["sides"]:
					_foam_side(t, side, ts, _base_color("lake"))
			"river":
				for side: Vector2i in c["sides"]:
					_foam_side(t, side, ts, _base_color("river"))
				_draw_flow(t, ts)
			"swamp":
				pass
	_draw_reeds(ts)
	_draw_ripples(ts)
	_draw_ford_sparks(ts)


## ==================== СТАТИКА (запечка) ====================

func _draw_static() -> void:
	_out = _sd
	var ts := float(map.ts)
	# тёмный ореол земли вокруг болота (грязная топь у кромки)
	for t: Vector2i in _swamp_near:
		_out.draw_rect(Rect2(Vector2(t) * ts, Vector2(ts, ts)), Color("#3f4a33", 0.55))
	# тело воды по тайлам
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] != map.TILE_WATER:
				continue
			var t := Vector2i(x, y)
			var kind := _kind_at(t)
			var rect := Rect2(Vector2(t) * ts, Vector2(ts, ts))
			var tex: Texture2D = _texs[kind]
			if tex != null:
				var variant: int = terrain._hash(x, y, 3)
				_out.draw_texture_rect_region(tex, rect, Rect2(variant * TS, 0, TS, TS))
			match kind:
				"lake":
					var deep := _deep_color("lake")
					var open := _water_neighbors8(t)
					if open >= 6:
						_out.draw_rect(rect, Color(deep, 0.10 + 0.05 * float(open - 6)))
				"swamp":
					_out.draw_rect(rect, Color(_swamp_fill(), 0.45))
	# статика берегов: мель, направленный объём, скругления, оконца
	for c in _coast:
		var t: Vector2i = c["tile"]
		var sides: Array = c["sides"]
		match _kind_at(t):
			"lake":
				_static_lake_coast(t, sides, ts)
			"river":
				_static_river_coast(t, sides, ts)
			"swamp":
				_static_swamp_coast(t, sides, ts)
	_static_swamp_details(ts)
	_static_swamp_reeds(ts)
	_static_fords(ts)
	_static_lilies(ts)


func _base_color(kind: String) -> Color:
	match kind:
		"river":
			return colors.get("water_river", Color("#57b2d4"))
	return colors.get("water_lake", Color("#3f87b5"))


func _deep_color(kind: String) -> Color:
	return colors.get("water_deep", _base_color(kind).darkened(0.28))


func _swamp_fill() -> Color:
	return Color(String(colors.get("water_tune", {}).get("swamp", {})
			.get("color", "#46523a")))


## Мель-пояс у стороны к суше.
func _shallow_strip(canvas: Object, t: Vector2i, side: Vector2i, ts: float,
		col: Color) -> void:
	var w := ts * 0.34
	var p := Vector2(t) * ts
	if side == Vector2i(0, -1):
		canvas.draw_rect(Rect2(p, Vector2(ts, w)), col)
	elif side == Vector2i(0, 1):
		canvas.draw_rect(Rect2(p + Vector2(0, ts - w), Vector2(ts, w)), col)
	elif side == Vector2i(-1, 0):
		canvas.draw_rect(Rect2(p, Vector2(w, ts)), col)
	else:
		canvas.draw_rect(Rect2(p + Vector2(ts - w, 0), Vector2(w, ts)), col)


## Скругление выпуклого угла воды: четверть-диск суши строго внутри
## водного тайла (только если диагональ — трава/лес).
func _round_corner(canvas: Object, t: Vector2i, s1: Vector2i, s2: Vector2i,
		ts: float, grass: Color) -> void:
	var corner := s1 + s2
	if absi(corner.x) != 1 or absi(corner.y) != 1:
		return
	var diag: Vector2i = t + corner
	if not map.in_bounds(diag):
		return
	var g: int = map.grid[diag.y][diag.x]
	if g != map.TILE_GRASS and g != map.TILE_TREE:
		return
	var p := Vector2(t) * ts
	var c := p + Vector2(ts * 0.5, ts * 0.5) + Vector2(corner) * (ts * 0.5)
	var shade := 0.04 * float(terrain._hash(t.x + corner.x, t.y + corner.y, 3) - 1)
	var bis := atan2(float(-corner.y), float(-corner.x))
	var pts := PackedVector2Array([c])
	var r := ts * 0.34
	for i in 9:
		var a := bis + deg_to_rad(-45.0 + 90.0 * float(i) / 8.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	canvas.draw_colored_polygon(pts, grass.lightened(shade))


func _static_lake_coast(t: Vector2i, sides: Array, ts: float) -> void:
	var base := _base_color("lake")
	var grass: Color = colors.get("grass", Color("#5ca046"))
	var shallow := Color(base.lightened(_opt("lake", "shallow_light", 0.20)), 0.72)
	for side: Vector2i in sides:
		_shallow_strip(_sd, t, side, ts, shallow)
		if side == Vector2i(0, 1):
			var deep := _deep_color("lake")
			_out.draw_rect(Rect2(Vector2(t) * ts + Vector2(0, ts * 0.62),
					Vector2(ts, ts * 0.30)),
					Color(deep, _opt("lake", "side_deep_alpha", 0.30)))
		elif side == Vector2i(0, -1):
			var glint := Color(base.lightened(_opt("lake", "shallow_light", 0.20) + 0.08),
					_opt("lake", "side_glint_alpha", 0.30))
			_out.draw_rect(Rect2(Vector2(t) * ts + Vector2(0, ts * 0.08),
					Vector2(ts, ts * 0.22)), glint)
	for i in sides.size():
		for j in range(i + 1, sides.size()):
			_round_corner(_sd, t, sides[i], sides[j], ts, grass)


func _static_river_coast(t: Vector2i, sides: Array, ts: float) -> void:
	var base := _base_color("river")
	var grass: Color = colors.get("grass", Color("#5ca046"))
	var shallow := Color(base.lightened(_opt("river", "shallow_light", 0.20)), 0.72)
	for side: Vector2i in sides:
		_shallow_strip(_sd, t, side, ts, shallow)
	for i in sides.size():
		for j in range(i + 1, sides.size()):
			_round_corner(_sd, t, sides[i], sides[j], ts, grass)


## Болото — ОРГАНИЧЕСКОЕ: та же кромка, что у озера, но мутная:
## светлый оттенок тины у берега + тёмная кромка воды (грязный край).
func _static_swamp_coast(t: Vector2i, sides: Array, ts: float) -> void:
	var grass: Color = colors.get("grass", Color("#5ca046"))
	var fill := _swamp_fill()
	var shallow := Color(fill.lightened(0.16), 0.7)
	var edge := Color(fill.darkened(0.32), 0.55)
	for side: Vector2i in sides:
		_shallow_strip(_sd, t, side, ts, shallow)
		# тонкая тёмная линия по самому краю — грязная кромка топи
		var p := Vector2(t) * ts
		if side == Vector2i(0, -1):
			_sd.draw_rect(Rect2(p, Vector2(ts, 2.0)), edge)
		elif side == Vector2i(0, 1):
			_sd.draw_rect(Rect2(p + Vector2(0, ts - 2.0), Vector2(ts, 2.0)), edge)
		elif side == Vector2i(-1, 0):
			_sd.draw_rect(Rect2(p, Vector2(2.0, ts)), edge)
		else:
			_sd.draw_rect(Rect2(p + Vector2(ts - 2.0, 0), Vector2(2.0, ts)), edge)
	for i in sides.size():
		for j in range(i + 1, sides.size()):
			_round_corner(_sd, t, sides[i], sides[j], ts, grass)


## Кочки и оконца болота — на тайлах топи (детерминировано).
func _static_swamp_details(ts: float) -> void:
	var puddle_c := Color(String(colors.get("water_tune", {}).get("swamp", {})
			.get("puddle", "#28322a")))
	var tussock_c := Color(String(colors.get("water_tune", {}).get("swamp", {})
			.get("tussock", "#6a7548")))
	for tk: Vector2i in _swamp_tiles:
		var rect := Rect2(Vector2(tk) * ts, Vector2(ts, ts))
		var hx: int = terrain._hash(tk.x * 3, tk.y * 7, 100)
		if hx % 3 == 0:
			var pc := rect.position + Vector2(6.0 + float(hx % int(ts - 14.0)),
					6.0 + float((hx / 5) % int(ts - 14.0)))
			_out.draw_circle(pc, ts * 0.16, puddle_c)
			_out.draw_circle(pc + Vector2(-1.0, -1.0), ts * 0.07, puddle_c.lightened(0.35))
		for i in 1 + hx % 2:
			var h2: int = terrain._hash(tk.x * 7 + i, tk.y * 13 + i, 100)
			var c := rect.position + Vector2(6.0 + float(h2 % int(ts - 12.0)),
					6.0 + float((h2 / 5) % int(ts - 12.0)))
			_out.draw_circle(c, 2.6 + float(h2 % 2), tussock_c)
			_out.draw_circle(c + Vector2(-0.8, -0.8), 1.2, tussock_c.lightened(0.15))


## Камыши (статичное положение; лёгкое качание — в живом слое поверх).
func _static_swamp_reeds(ts: float) -> void:
	var fill := _swamp_fill()
	for tk: Vector2i in _swamp_tiles:
		if terrain._hash(tk.x, tk.y * 3, 4) == 0:
			_draw_reed_patch(Vector2(tk) * ts, ts, tk.x, tk.y, fill.lightened(0.1), Color(0, 0, 0, 0))
	for t: Vector2i in _swamp_near:
		if terrain._hash(t.x * 3, t.y * 5, 23) % 3 < 2:
			_draw_reed_patch(Vector2(t) * ts, ts, t.x, t.y, Color("#4e6b34"), Color(0, 0, 0, 0))
	# камыши в воде у берегов озера/реки (пучок растёт из тёмного плёса)
	var chance := maxi(2, int(_opt("reed", "water_chance", 12.0)))
	for c in _coast:
		var t2: Vector2i = c["tile"]
		var kind := _kind_at(t2)
		if kind == "swamp":
			continue
		if terrain._hash(t2.x * 7, t2.y * 3, 100) % chance != 0:
			continue
		var origin := Vector2(t2) * ts
		_out.draw_circle(origin + Vector2(ts * 0.5, ts * 0.72), ts * 0.20,
				Color("#2c3f33", 0.55))
		_draw_reed_patch(origin + Vector2(0, ts * 0.18), ts * 1.05, t2.x, t2.y,
				Color("#3f5a2e"), _base_color(kind))


## Брод: светлая вода, песчаное дно (искорки — живой слой).
func _static_fords(ts: float) -> void:
	var base: Color = colors.get("water_river", Color("#57b2d4"))
	for tk: Vector2i in _ford_tiles:
		var rect := Rect2(Vector2(tk) * ts, Vector2(ts, ts))
		_out.draw_rect(rect, Color(base, 0.55))
		for i in 3:
			var h2: int = terrain._hash(tk.x * 11 + i, tk.y * 7 + i, 100)
			var c := rect.position + Vector2(4.0 + float(h2 % int(ts - 8.0)),
					4.0 + float((h2 / 7) % int(ts - 8.0)))
			_out.draw_circle(c, 2.0 + float(h2 % 2), Color("#c8b183", 0.65))


## Кувшинки: пара листьев с выемкой (тихая вода озера).
func _static_lilies(ts: float) -> void:
	var drawn := 0
	for t: Vector2i in _inner:
		if _kind_at(t) != "lake" or drawn >= 3:
			continue
		if terrain._hash(t.x * 5, t.y * 9, 200) != 0:
			continue
		drawn += 1
		var base := _base_color("lake")
		var c := Vector2(t) * ts + Vector2(6.0 + float(terrain._hash(t.x, t.y, 13) % 14),
				6.0 + float(terrain._hash(t.y, t.x, 13) % 14))
		var r := 3.0 + float(terrain._hash(t.x, t.y, 3))
		var col := Color("#4e7c3a").lightened(0.05 * float(r))
		_out.draw_circle(c, r, col)
		_out.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, col.lightened(0.25))
		_out.draw_line(c, c + Vector2(r + 0.6, 0.6), Color(base, 0.5), 1.2)


## ==================== ЖИВОЕ (15 к/с) ====================

## Пена у берега: бегущие штрихи вдоль стороны к суше (две волны).
func _foam_side(t: Vector2i, side: Vector2i, ts: float, base: Color) -> void:
	var p := Vector2(t) * ts
	var along := Vector2(1, 0) if side.y != 0 else Vector2(0, 1)
	var c := p + Vector2(ts, ts) * 0.5 + Vector2(side) * (ts * 0.30)
	for k in 2:
		var seed_h: int = terrain._hash(t.x * 3 + k, t.y * 5 + k, 9)
		var ph := fposmod(_time * _opt("foam", "speed", 0.35)
				+ float(seed_h) / 9.0 + 0.5 * float(k), 1.0)
		if ph > 0.6:
			continue
		var col := Color(base.lightened(0.75), 0.6 * (1.0 - ph * 1.6))
		var m := ts * (0.12 + 0.30 * ph)
		var off := (float(seed_h % 5) / 5.0 - 0.5) * ts * 0.5
		draw_line(c + along * (off - m), c + along * (off + m), col, 2.4)


## Течение реки: струи бегут вниз по руслу.
func _draw_flow(t: Vector2i, ts: float) -> void:
	if terrain._hash(t.x, t.y, 41) % int(_opt("river", "flow_chance", 2)) != 0:
		return
	var base := _base_color("river")
	var frame := float(int(_time * _fps()) % 6)
	var h: int = terrain._hash(t.x * 5, t.y * 11, 100)
	var px := float(t.x) * ts + 5.0 + float(h % int(ts - 14.0))
	var py0 := float(t.y) * ts + fposmod(float(h) * 0.13 + frame * ts / 6.0, ts)
	var ln := ts * (0.28 + 0.05 * float(h % 3))
	var col := base.lightened(0.45)
	col.a = 0.45
	draw_line(Vector2(px, py0), Vector2(px, minf(py0 + ln, float(t.y + 1) * ts)), col, 1.3)


## Рябь на тихой воде: двойные кольца, дышат радиусом (референс a602a024).
func _draw_ripples(ts: float) -> void:
	for t: Vector2i in _inner:
		if terrain._hash(t.x * 11, t.y * 7, 100) != 0:
			continue
		var base := _base_color(_kind_at(t))
		var c := Vector2(t) * ts + Vector2(ts * 0.5, ts * 0.5)
		var ph := fposmod(_time * 0.5 + float(terrain._hash(t.x, t.y, 9)) / 9.0, 1.0)
		var r1 := ts * (0.16 + 0.20 * ph)
		var col := Color(base.lightened(0.30), 0.30 * (1.0 - ph))
		draw_arc(c, r1, 0.0, TAU, 14, col, 1.1)
		draw_arc(c, r1 * 1.5, 0.0, TAU, 16, Color(col.r, col.g, col.b, col.a * 0.6), 1.0)


## Искорки на бродах: блики переливаются по фазе.
func _draw_ford_sparks(ts: float) -> void:
	var frame := float(int(_time * _fps()) % 6)
	for tk: Vector2i in _ford_tiles:
		var h1: int = terrain._hash(tk.x, tk.y, 77)
		var sp := fposmod(float(h1) * 0.17 + frame / 6.0, 1.0)
		if sp >= 0.4:
			continue
		var rect := Rect2(Vector2(tk) * ts, Vector2(ts, ts))
		draw_circle(rect.position + Vector2(ts * (0.3 + 0.4 * sp), ts * 0.55),
				1.5, Color(1.0, 1.0, 0.9, 0.5 * (1.0 - sp * 2.0)))


## Камыши: качание по фазе — только поворот «шишки», основание статично
## (в запечке уже нарисованы стебли; здесь лёгкий живой штрих на конце).
func _draw_reeds(ts: float) -> void:
	var chance := maxi(2, int(_opt("reed", "water_chance", 12.0)))
	for c in _coast:
		var t: Vector2i = c["tile"]
		var kind := _kind_at(t)
		if kind == "swamp":
			continue
		if terrain._hash(t.x * 7, t.y * 3, 100) % chance != 0:
			continue
		var origin := Vector2(t) * ts
		var sway := 1.2 * sin(_time * 2.0 + float(terrain._hash(t.x, t.y, 9)))
		var top := origin + Vector2(ts * 0.5 + sway, ts * 0.28)
		_out.draw_line(origin + Vector2(ts * 0.5, ts * 0.62), top,
				Color("#4e6b34", 0.85), 1.2)
		_out.draw_line(top, top + Vector2(sway * 0.4, -4.0), Color("#7a5230"), 2.2)


func _near_swamp(t: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = t + d
		if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER \
				and map.water_kind_at(n) == "swamp":
			return true
	return false


## Камыши-пучок (статичный, для запечки): 2–4 стебля с шишкой.
func _draw_reed_patch(origin: Vector2, ts: float, x: int, y: int,
		stem: Color, water: Color) -> void:
	var head := Color("#7a5230")
	var n: int = 2 + terrain._hash(x, y, 5) % 3
	for i in n:
		var h: int = terrain._hash(x * 7 + i, y * 11 + i, 100)
		var base := origin + Vector2(5.0 + float(h % int(ts - 10.0)), ts * 0.85)
		var lean := 1.6 + float(h % 3) * 0.8
		var top := base + Vector2(lean, -ts * (0.5 + 0.14 * float(h % 3)))
		_out.draw_line(base, top, stem, 1.4)
		_out.draw_line(top, top + Vector2(lean * 0.5, -3.0), stem, 1.1)
		_out.draw_line(top + Vector2(lean * 0.5, -3.0), top + Vector2(lean * 0.6, -7.0), head, 2.4)
		_out.draw_circle(top + Vector2(lean * 0.6, -7.0), 1.2, head.darkened(0.2))
	if water.a > 0.0:
		var ph := fposmod(_time * 0.4 + float(terrain._hash(x, y, 9)) / 9.0, 1.0)
		_out.draw_arc(origin + Vector2(ts * 0.5, ts * 0.62), ts * (0.3 + 0.25 * ph),
				0.0, TAU, 12, Color(water.lightened(0.3), 0.28 * (1.0 - ph)), 1.1)
