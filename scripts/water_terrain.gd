extends Node2D
## ВОДА «Природы 2.0» (v1.39.0) — ЖИВОЙ слой города: вода анимируется
## каждый кадр, поэтому не печётся в ландшафт (city_terrain.gd), а рисуется
## поверх запечённой земли отдельным узлом (водных тайлов в городе сотни —
## дёшево). Ассеты — ForgottenMemories (русские папки заказчика, директива
## 2026-10-30): бесшовная фактура 32px, перемапленная на гамму мастера
## (tools/make_nature2.py). Референсы «для Z.ai/вода»: кромка в 2–3 тона,
## пена только у берега, круги ряби (a602a024), камыши маскируют границу
## (ymPrI2).
##
## Язык кромок — PER-TILE, как у принятых плато v1.36 (единая система
## высот, EdgeLang): у каждого берегового тайла сторона к суше получает
## светлый мель-пояс, пена-штрихи (анимированы), у озера — тёмная глубина
## у южного берега и блик у северного (свет с СЗ). Блобы НЕ используются:
## сшивка marching-squares разваливалась на седловых точках меандра
## (урок v1.39.0), а per-tile кромки не ломаются никогда.
##
## Типы воды (решение заказчика «свой тон у трёх типов»):
##   озеро  — глубокая синь, мель, глубина к югу, кувшинки и ряби;
##   река   — светлее, течение (бегущие струи вниз по руслу), мель;
##   болото — мутная топь честными тайлами: кочки, оконца, тина, камыши;
##   брод   — светлая вода, песчаное дно, искорки (игровой ориентир).
##
## Тюнинг: data/city.json → colors → "water2" (anim_fps, foam_*, reed_*).

var terrain                 # city_terrain — карта, хэш-утилиты, цвета
var map = null
var colors: Dictionary = {}
var _texs := {}             # kind -> Texture2D (полоса 3 тайлов 96x32)
var _time := 0.0
var _cache_ver := -1
var _coast: Array = []      # [{tile, sides:[Vector2i], corner:bool}] — береговые
var _inner: Array = []      # открытая вода (8 соседей — вода): рябь/кувшинки
var _swamp_tiles: Array = []
var _ford_tiles: Array = []

const EdgeLangC := preload("res://scripts/edge_lang.gd")
const TS := 32


func setup(terrain_ref, cfg_colors: Dictionary) -> void:
	terrain = terrain_ref
	map = terrain_ref.map
	colors = cfg_colors
	for kind in ["lake", "river", "swamp"]:
		_texs[kind] = Assets.tex("res://assets/sprites/env/n2_water_%s.png" % kind)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _fps() -> float:
	return float(colors.get("water2", {}).get("anim_fps", 5.0))


func _opt(section: String, key: String, def: float) -> float:
	return float(colors.get("water2", {}).get(section, {}).get(key, def))


## Кэш берегов и открытой воды — перестраивается при смене версии сетки
## (мост, выработка породы). Чистая математика по карте, без контуров.
func _ensure_cache() -> void:
	if map == null or (_cache_ver == map.grid_ver and not _coast.is_empty()):
		return
	_cache_ver = map.grid_ver
	_coast = []
	_inner = []
	_swamp_tiles = []
	_ford_tiles = []
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if map.grid[y][x] != map.TILE_WATER:
				continue
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
	if map == null:
		return
	_ensure_cache()
	var ts := float(map.ts)
	# 1) тело: фактура по тайлам + дыхание света
	_draw_bodies(ts)
	# 2) кромки и детали по типам
	for c in _coast:
		var t: Vector2i = c["tile"]
		match _kind_at(t):
			"lake":
				_draw_lake_coast(t, c["sides"], ts)
			"river":
				_draw_river_coast(t, c["sides"], ts)
			"swamp":
				pass   # болото рисуется целиком в _draw_swamp
	_draw_swamp()
	_draw_fords(ts)
	_draw_inner_details(ts)
	_coast_reeds()


## ---------- тело воды ----------

func _draw_bodies(ts: float) -> void:
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] != map.TILE_WATER:
				continue
			var t := Vector2i(x, y)
			var kind := _kind_at(t)
			if kind == "swamp":
				continue   # болото рисуется в _draw_swamp
			var tex: Texture2D = _texs[kind]
			var rect := Rect2(Vector2(t) * ts, Vector2(ts, ts))
			if tex != null:
				var variant: int = terrain._hash(x, y, 3)
				draw_texture_rect_region(tex, rect, Rect2(variant * TS, 0, TS, TS))
			# дыхание света: у части тайлов полупрозрачная пелена гуляет
			var ph := float(terrain._hash(x * 3, y, 5)) / 5.0
			if ph < 0.34:
				var a := 0.05 + 0.04 * sin(_time * 1.6 + ph * 18.0)
				draw_rect(rect, Color(1.0, 1.0, 0.92, maxf(0.0, a)))
			# глубина открытой воды (озеро): чем открытее, тем темнее
			if kind == "lake":
				var open: int = _water_neighbors8(t)
				if open >= 6:
					var deep: Color = _deep_color("lake")
					draw_rect(rect, Color(deep, 0.10 + 0.05 * float(open - 6)))


func _base_color(kind: String) -> Color:
	match kind:
		"river":
			return colors.get("water_river", Color("#57b2d4"))
	return colors.get("water_lake", Color("#3f87b5"))


func _deep_color(kind: String) -> Color:
	return colors.get("water_deep", _base_color(kind).darkened(0.28))


## ---------- кромки: мель, пена, направленный объём ----------

## Мель-пояс у стороны к суше: светлая полоса внутри тайла.
func _shallow_strip(t: Vector2i, side: Vector2i, ts: float, col: Color) -> void:
	var w := ts * 0.34
	var p := Vector2(t) * ts
	if side == Vector2i(0, -1):
		draw_rect(Rect2(p, Vector2(ts, w)), col)
	elif side == Vector2i(0, 1):
		draw_rect(Rect2(p + Vector2(0, ts - w), Vector2(ts, w)), col)
	elif side == Vector2i(-1, 0):
		draw_rect(Rect2(p, Vector2(w, ts)), col)
	else:
		draw_rect(Rect2(p + Vector2(ts - w, 0), Vector2(w, ts)), col)


## Скругление выпуклого угла воды: два береговых side сходятся в углу —
## ЧЕТВЕРТЬ-диск травы строго внутри водного тайла (срезает ступеньку,
## сушу не трогает). Только если диагональ — трава/лес (не скала).
func _round_corner(t: Vector2i, s1: Vector2i, s2: Vector2i, ts: float,
		grass: Color) -> void:
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
	# веер четверти круга: бисектриса внутрь тайла ±45°
	var bis := atan2(float(-corner.y), float(-corner.x))
	var pts := PackedVector2Array([c])
	var r := ts * 0.34
	for i in range(9):
		var a := bis + deg_to_rad(-45.0 + 90.0 * float(i) / 8.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, grass.lightened(shade))


## Пена у берега: бегущие штрихи вдоль стороны к суше (две волны на сторону).
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
		var a: Vector2 = c + along * (off - m)
		var b: Vector2 = c + along * (off + m)
		draw_line(a, b, col, 2.4)


func _draw_lake_coast(t: Vector2i, sides: Array, ts: float) -> void:
	var base := _base_color("lake")
	var grass: Color = colors.get("grass", Color("#5ca046"))
	var shallow := Color(base.lightened(_opt("lake", "shallow_light", 0.20)), 0.72)
	for side: Vector2i in sides:
		_shallow_strip(t, side, ts, shallow)
		# направленный объём (свет с СЗ): блик у северного берега,
		# тёмная глубина у южного — вода читается углублением
		if side == Vector2i(0, 1):
			var deep := _deep_color("lake")
			draw_rect(Rect2(Vector2(t) * ts + Vector2(0, ts * 0.62),
					Vector2(ts, ts * 0.30)), Color(deep, _opt("lake", "side_deep_alpha", 0.30)))
		elif side == Vector2i(0, -1):
			var glint := Color(base.lightened(_opt("lake", "shallow_light", 0.20) + 0.08),
					_opt("lake", "side_glint_alpha", 0.30))
			draw_rect(Rect2(Vector2(t) * ts + Vector2(0, ts * 0.08),
					Vector2(ts, ts * 0.22)), glint)
		# пена — только у возмущений (берег всегда возмущение)
		_foam_side(t, side, ts, base)
	# скругление выпуклых углов берега
	for i in sides.size():
		for j in range(i + 1, sides.size()):
			_round_corner(t, sides[i], sides[j], ts, grass)


func _draw_river_coast(t: Vector2i, sides: Array, ts: float) -> void:
	var base := _base_color("river")
	var grass: Color = colors.get("grass", Color("#5ca046"))
	var shallow := Color(base.lightened(_opt("river", "shallow_light", 0.20)), 0.72)
	for side: Vector2i in sides:
		_shallow_strip(t, side, ts, shallow)
		_foam_side(t, side, ts, base)
	for i in sides.size():
		for j in range(i + 1, sides.size()):
			_round_corner(t, sides[i], sides[j], ts, grass)
	# течение: струи бегут вниз по руслу (река течёт по Y)
	if terrain._hash(t.x, t.y, 41) % int(_opt("river", "flow_chance", 2)) == 0:
		var frame := float(int(_time * _fps()) % 6)
		var h: int = terrain._hash(t.x * 5, t.y * 11, 100)
		var px := float(t.x) * ts + 5.0 + float(h % int(ts - 14.0))
		var py0 := float(t.y) * ts + fposmod(float(h) * 0.13 + frame * ts / 6.0, ts)
		var ln := ts * (0.28 + 0.05 * float(h % 3))
		var col := base.lightened(0.45)
		col.a = 0.45
		draw_line(Vector2(px, py0), Vector2(px, minf(py0 + ln, float(t.y + 1) * ts)), col, 1.3)


## ---------- открытая вода: рябь и кувшинки ----------

func _draw_inner_details(ts: float) -> void:
	var lilies := 0
	for t: Vector2i in _inner:
		var kind := _kind_at(t)
		var base := _base_color(kind)
		var h: int = terrain._hash(t.x * 11, t.y * 7, 100)
		# рябь: двойное кольцо, дышит радиусом (референс a602a024)
		if h == 0:
			var c := Vector2(t) * ts + Vector2(ts * 0.5, ts * 0.5)
			var ph := fposmod(_time * 0.5 + float(terrain._hash(t.x, t.y, 9)) / 9.0, 1.0)
			var r1 := ts * (0.16 + 0.20 * ph)
			var col := Color(base.lightened(0.30), 0.30 * (1.0 - ph))
			draw_arc(c, r1, 0.0, TAU, 14, col, 1.1)
			draw_arc(c, r1 * 1.5, 0.0, TAU, 16, Color(col.r, col.g, col.b, col.a * 0.6), 1.0)
		# кувшинки: пара листьев с выемкой (только озёра, до 3 на вид)
		if kind == "lake" and lilies < 3 and terrain._hash(t.x * 5, t.y * 9, 200) == 0:
			lilies += 1
			var c := Vector2(t) * ts + Vector2(6.0 + float(terrain._hash(t.x, t.y, 13) % 14),
					6.0 + float(terrain._hash(t.y, t.x, 13) % 14))
			var r := 3.0 + float(terrain._hash(t.x, t.y, 3))
			var col := Color("#4e7c3a").lightened(0.05 * float(r))
			draw_circle(c, r, col)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, col.lightened(0.25))
			draw_line(c, c + Vector2(r + 0.6, 0.6), Color(base, 0.5), 1.2)


## ---------- болото ----------

func _draw_swamp() -> void:
	if _swamp_tiles.is_empty():
		return
	var ts := float(map.ts)
	var fill_c := Color(String(colors.get("water_tune", {}).get("swamp", {})
			.get("color", "#46523a")))
	var puddle_c := Color(String(colors.get("water_tune", {}).get("swamp", {})
			.get("puddle", "#28322a")))
	var tussock_c := Color(String(colors.get("water_tune", {}).get("swamp", {})
			.get("tussock", "#6a7548")))
	var tex: Texture2D = _texs["swamp"]
	for tk: Vector2i in _swamp_tiles:
		var rect := Rect2(Vector2(tk) * ts, Vector2(ts, ts))
		if tex != null:
			var variant: int = terrain._hash(tk.x, tk.y, 3)
			draw_texture_rect_region(tex, rect, Rect2(variant * TS, 0, TS, TS))
			# тина: зелёная плёнка поверх фактуры
			draw_rect(rect, Color(fill_c, 0.45))
		else:
			draw_rect(rect, fill_c)
		var hx: int = terrain._hash(tk.x * 3, tk.y * 7, 100)
		if hx % 3 == 0:
			var pc := rect.position + Vector2(6.0 + float(hx % int(ts - 14.0)),
					6.0 + float((hx / 5) % int(ts - 14.0)))
			draw_circle(pc, ts * 0.16, puddle_c)
			draw_circle(pc + Vector2(-1.0, -1.0), ts * 0.07, puddle_c.lightened(0.35))
		for i in 1 + hx % 2:
			var h2: int = terrain._hash(tk.x * 7 + i, tk.y * 13 + i, 100)
			var c := rect.position + Vector2(6.0 + float(h2 % int(ts - 12.0)),
					6.0 + float((h2 / 5) % int(ts - 12.0)))
			draw_circle(c, 2.6 + float(h2 % 2), tussock_c)
			draw_circle(c + Vector2(-0.8, -0.8), 1.2, tussock_c.lightened(0.15))
		if terrain._hash(tk.x, tk.y * 3, 4) == 0:
			_draw_reeds(Vector2(tk) * ts, ts, tk.x, tk.y, fill_c.lightened(0.1))
	# тёмно-зелёная земля с камышами ВОКРУГ болота (v1.31.1)
	for c in _coast:
		var st: Vector2i = c["tile"]
		if map.grid[st.y][st.x] != map.TILE_GRASS:
			continue
		if not _near_swamp(st):
			continue
		draw_rect(Rect2(Vector2(st) * ts, Vector2(ts, ts)), Color("#3f4a33", 0.55))
		if terrain._hash(st.x * 3, st.y * 5, 23) % 3 < 2:
			_draw_reeds(Vector2(st) * ts, ts, st.x, st.y, Color("#4e6b34"))


## Камыши у кромки: растут ИЗ воды на мелководье (маскируют границу,
## референс ymPrI2) — стебли качаются по фазе.
func _coast_reeds() -> void:
	var ts := float(map.ts)
	var chance := maxi(2, int(_opt("reed", "water_chance", 25.0)))
	for c in _coast:
		var t: Vector2i = c["tile"]
		var kind := _kind_at(t)
		if kind == "swamp":
			continue   # у болота свои камыши
		if terrain._hash(t.x * 7, t.y * 3, 100) % chance != 0:
			continue
		var origin := Vector2(t) * ts
		# тёмный плёс под пучком — пучок растёт из воды
		draw_circle(origin + Vector2(ts * 0.5, ts * 0.72), ts * 0.20,
				Color("#2c3f33", 0.55))
		_draw_reeds(origin + Vector2(0, ts * 0.18), ts * 1.05, t.x, t.y,
				Color("#3f5a2e"), _base_color(kind))


func _draw_reeds(origin: Vector2, ts: float, x: int, y: int,
		stem: Color, water: Color = Color(0, 0, 0, 0)) -> void:
	var head := Color("#7a5230")
	var n: int = 2 + terrain._hash(x, y, 5) % 3
	var sway := 1.0 + 0.25 * sin(_time * 2.0 + float(terrain._hash(x, y, 9)))
	for i in n:
		var h: int = terrain._hash(x * 7 + i, y * 11 + i, 100)
		var base := origin + Vector2(5.0 + float(h % int(ts - 10.0)), ts * 0.85)
		var lean := (1.6 + float(h % 3) * 0.8) * sway
		var top := base + Vector2(lean, -ts * (0.5 + 0.14 * float(h % 3)))
		draw_line(base, top, stem, 1.4)
		draw_line(top, top + Vector2(lean * 0.5, -3.0), stem, 1.1)
		# шишка камыша — тёмная капсула на конце
		draw_line(top + Vector2(lean * 0.5, -3.0), top + Vector2(lean * 0.6, -7.0), head, 2.4)
		draw_circle(top + Vector2(lean * 0.6, -7.0), 1.2, head.darkened(0.2))
	if water.a > 0.0:
		# круг ряби вокруг пучка в воде
		var ph := fposmod(_time * 0.4 + float(terrain._hash(x, y, 9)) / 9.0, 1.0)
		draw_arc(origin + Vector2(ts * 0.5, ts * 0.62), ts * (0.3 + 0.25 * ph),
				0.0, TAU, 12, Color(water.lightened(0.3), 0.28 * (1.0 - ph)), 1.1)


## ---------- броды ----------

## Брод: светлая вода, песчаное дно, искорки-блики (игровой ориентир).
func _draw_fords(ts: float) -> void:
	var base: Color = colors.get("water_river", Color("#57b2d4"))
	var frame := float(int(_time * _fps()) % 6)
	for tk: Vector2i in _ford_tiles:
		var rect := Rect2(Vector2(tk) * ts, Vector2(ts, ts))
		draw_rect(rect, Color(base, 0.55))
		var h1: int = terrain._hash(tk.x, tk.y, 77)
		for i in 3:
			var h2: int = terrain._hash(tk.x * 11 + i, tk.y * 7 + i, 100)
			var c := rect.position + Vector2(4.0 + float(h2 % int(ts - 8.0)),
					4.0 + float((h2 / 7) % int(ts - 8.0)))
			draw_circle(c, 2.0 + float(h2 % 2), Color("#c8b183", 0.65))
		# искорки: блики переливаются по фазе кадра
		var sp := fposmod(float(h1) * 0.17 + frame / 6.0, 1.0)
		if sp < 0.4:
			draw_circle(rect.position + Vector2(ts * (0.3 + 0.4 * sp), ts * 0.55),
					1.5, Color(1.0, 1.0, 0.9, 0.5 * (1.0 - sp * 2.0)))


func _near_swamp(t: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = t + d
		if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER \
				and map.water_kind_at(n) == "swamp":
			return true
	return false
