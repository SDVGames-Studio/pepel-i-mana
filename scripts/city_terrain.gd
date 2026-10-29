extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Статический слой города (M9/M10, переработан в M11): ландшафт не меняется
## в течение игры. v1.21.5: ландшафт ЗАПЕКАЕТСЯ в текстуру SubViewport и
## рисуется одним квадратом — раньше ~12 000 векторных команд карты рендерер
## перемалывал каждый кадр (это и держало город на 10–15 FPS). Перевыпечка —
## по rebake() (сцена зовёт при sim.terrain_dirty, не чаще 2 раз/сек).
##
## M11 по замечаниям заказчика:
##  - земля без «шахматного порядка»: плавные пятна травы (шум крупными
##    блоками) плюс мелкое зерно яркости на каждом тайле;
##  - скалы — ЕДИНАЯ гряда: тёмное основание связывает тайлы в массив,
##    внутренние тайлы крупнее и темнее, края светлее; трещины по мере выработки.

var map = null
var sim = null                   # город (v1.22): зоны/дороги/плиты площади в духовке
var colors: Dictionary = {}
var _zone_colors: Dictionary = {}   # тип зоны -> цвет заливки (v1.22)
var _grass_shades: Array = []
var _rock_deep := Color("#565248")
var _water_lake := Color("#3f87b5")   # v1.29.1: озеро — яркая синь
var _water_river := Color("#57b2d4")  # v1.29.1: река — светло-бирюзовая
var _rock_hp_default := 80.0
var _vp: SubViewport = null
var _drawer: Node2D = null
var _tex: Texture2D = null
# v1.28.1: второй слой — «надстройки» (зоны/дороги/плиты). Они меняются
# часто (обустройство полей), а полная перевыпечка земли (тысячи команд
# травы) стоила ~0.3 с и давала регулярные фризы.
var _vp2: SubViewport = null
var _drawer2: Node2D = null
var _tex2: Texture2D = null


func setup(city_map, city_cfg: Dictionary, city_sim = null) -> void:
	map = city_map
	sim = city_sim
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		colors[key] = Color(String(c[key]))
	for t in city_cfg.get("zones", {}).get("types", {}):
		_zone_colors[String(t)] = Color(String(city_cfg["zones"]["types"][t]["color"]))
	_grass_shades = [colors["grass"], colors.get("grass_alt", colors["grass"]),
			colors.get("grass2", colors["grass"]).darkened(0.03)]
	_rock_deep = colors.get("rock_deep", Color("#565248"))
	_water_lake = colors.get("water_lake", _water_lake)
	_water_river = colors.get("water_river", _water_river)
	_rock_hp_default = float(city_cfg.get("mountain", {}).get("hp", 80.0))
	# духовка: SubViewport размером с карту, содержимое — те же тайлы.
	# Сама выпечка — в _ready(): до входа в дерево SubViewport не рендерится
	# (UPDATE_ONCE сгорает впустую — на этом ловились пустые текстуры).
	_vp = SubViewport.new()
	_vp.size = Vector2i(map.w * map.ts, map.h * map.ts)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_drawer = Node2D.new()
	_drawer.draw.connect(_draw_tiles)
	_vp.add_child(_drawer)
	_tex = _vp.get_texture()
	_vp2 = SubViewport.new()
	_vp2.size = _vp.size
	_vp2.transparent_bg = true
	_vp2.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp2.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp2)
	_drawer2 = Node2D.new()
	_drawer2.draw.connect(_draw_static_content)
	_vp2.add_child(_drawer2)
	_tex2 = _vp2.get_texture()
	queue_redraw()


func _ready() -> void:
	rebake(true)   # первый bake: кэш блобов строится обязательно
	# v1.30.1: страховка «пустого ландшафта» после смены сцены (смерть в
	# данже): первый UPDATE_ONCE SubViewport изредка сгорает впустую в кадре
	# смены сцены — переводыпекаем ещё раз следующим кадром (дёшево)
	_bake_guard.call_deferred()


func _bake_guard() -> void:
	if _vp == null or not is_inside_tree():
		return
	_drawer.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Перевыпечь слой земли (скалу выработали, воду замостили мостом...) —
## heavy=true и версия сетки изменились: пересчитать блобы и всё поле.
## false: перерисовать ТОЛЬКО надстройки (зоны/дороги/плиты) — дёшево.
## v1.28.1 (фикс фризов): полная перевыпечка земли = тысячи draw-команд
## травы (~0.3 с), а вызывалась на каждое обустройство клетки/дорогу.
var _rebake_count := 0
var _blob_cache_ver := -1     # версия сетки, на которую построен кэш блобов
var _blob_cache_dirty := true # кэш требует пересчёта (первый bake или смена сетки)
var _water_cached: Array = []   # [{loop, tris, depth, kind, tiles}...]
var _rock_cached: Array = []    # [{loop, tris}...]
var _water_tile_kind: Dictionary = {}   # Vector2i -> "lake"|"river"|"swamp"


func rebake(heavy := false, grid_ver := -1) -> void:
	if _vp == null:
		return
	_rebake_count += 1
	if heavy and map != null and _blob_cache_ver != grid_ver:
		_blob_cache_ver = grid_ver
		_blob_cache_dirty = true
		_drawer.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# надстройки всегда перерисовываются — их мало (сотни команд)
	_drawer2.queue_redraw()
	_vp2.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp2.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _draw() -> void:
	if OS.get_environment("TERRAIN_DIRECT") != "":
		# временная ветка сравнения (v1.21.5): рисуем тайлы напрямую, без духовки
		var keep := _drawer
		_drawer = self
		_draw_tiles()
		_drawer = keep
		return
	if _tex == null or map == null:
		return
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(map.w * map.ts, map.h * map.ts)), false)
	if _tex2 != null:
		draw_texture_rect(_tex2, Rect2(Vector2.ZERO, Vector2(map.w * map.ts, map.h * map.ts)), false)


## Отрисовка тайлов — в холст духовки (те же команды, что рисовали в _draw
## до v1.21.5; вызывающий холст — _drawer, а не сам слой).
## v1.22: сюда же запечены «наземные» покрытия — дороги, зоны (заливки,
## борозды, точки пастбищ, заборы) и каменные плиты площади. Раньше это
## пересобиралось живым слоем каждый кадр (~500 команд), теперь живёт
## в текстуре ландшафта и меняется только по sim.static_dirty (rebake).
func _draw_tiles() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	# проход 1: земля (трава/осыпи) — вода и скалы рисуются блобами поверх
	for y in map.h:
		for x in map.w:
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			var base := _grass_at(x, y)
			match tile:
				map.TILE_GRASS, map.TILE_TREE:
					_drawer.draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
				map.TILE_DEADROCK:
					_draw_deadrock(x, y, rect, ts)
	# проход 2: скальная гряда и вода — ОРГАНИЧНЫЕ блобы (marching squares,
	# сглаживание Безье — стиль RimWorld/Dwarf Fortress, не по тайлам)
	_draw_rock_blobs(ts)
	_draw_water_blobs(ts)


## Надстройки (v1.28.1 — отдельный дешёвый слой): зоны, дороги, плиты
## площади. Меняются часто, но команд здесь сотни, а не тысячи.
func _draw_static_content() -> void:
	if map == null:
		return
	_draw_roads_baked()
	_draw_zones_baked()
	_draw_plaza_baked()


## ---------- блобы: marching squares + сглаживание ----------

## Несглаженные замкнутые контуры маски тайлов (углы = центры тайлов).
## Контур идёт по серединам рёбер между «сухим» и «мокрым» тайлом.
func _mask_loops(is_set: Callable) -> Array:
	var ts := float(map.ts)
	var edges := {}   # ключ точки -> массив соседних точек (ключи)
	# сегмент одной клетки: связь двух середин рёбер
	var add_seg := func(a: Vector2, b: Vector2) -> void:
		var ka := _pt_key(a, ts)
		var kb := _pt_key(b, ts)
		if not edges.has(ka):
			edges[ka] = []
		edges[ka].append([kb, b])
		if not edges.has(kb):
			edges[kb] = []
		edges[kb].append([ka, a])
	for j in range(-1, map.h):
		for i in range(-1, map.w):
			var tl := _wet_at(is_set, i, j)
			var tr := _wet_at(is_set, i + 1, j)
			var bl := _wet_at(is_set, i, j + 1)
			var br := _wet_at(is_set, i + 1, j + 1)
			var idx: int = (1 if tl else 0) + (2 if tr else 0) + (4 if bl else 0) + (8 if br else 0)
			if idx == 0 or idx == 15:
				continue
			var top := Vector2((i + 1) * ts, (j + 0.5) * ts)
			var bottom := Vector2((i + 1) * ts, (j + 1.5) * ts)
			var left := Vector2((i + 0.5) * ts, (j + 1) * ts)
			var right := Vector2((i + 1.5) * ts, (j + 1) * ts)
			match idx:
				1, 14:
					add_seg.call(left, top)
				2, 13:
					add_seg.call(top, right)
				3, 12:
					add_seg.call(left, right)
				4, 11:
					add_seg.call(left, bottom)
				6, 9:
					add_seg.call(top, bottom)
				7, 8:
					add_seg.call(right, bottom)
				5:
					# седловая точка tl+br: связываем мокрые по диагонали
					# (без «щипка» в центре клетки)
					add_seg.call(left, bottom)
					add_seg.call(top, right)
				10:
					# седловая точка tr+bl: та же диагональная связность
					add_seg.call(left, top)
					add_seg.call(bottom, right)
	# сшить сегменты в кольца: при использовании ребра удаляем ОБЕ записи
	# (прямую и встречную) — иначе обход откатывается и кольцо складывается
	# вдвое (самопересечение, is_point_in_polygon ломается, заливка пустая)
	var loops: Array = []
	for start_key in edges.keys():
		while (edges[start_key] as Array).size() > 0:
			var loop := PackedVector2Array()
			var cur_key: Vector2i = start_key
			while true:
				var lst: Array = edges[cur_key]
				if lst.is_empty():
					break
				var nxt: Array = lst.pop_back()
				var rec: Array = edges[nxt[0]]
				for idx in range(rec.size()):
					if rec[idx][0] == cur_key:
						rec.remove_at(idx)
						break
				loop.append(nxt[1])
				cur_key = nxt[0]
			if loop.size() >= 3:
				loops.append(loop)
	return loops


func _wet_at(is_set: Callable, i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= map.w or j >= map.h:
		return false
	return is_set.call(Vector2i(i, j))


## Ключ точки на полусетке (целые числа — без ошибок сравнения float).
func _pt_key(p: Vector2, ts: float) -> Vector2i:
	return Vector2i(roundi(p.x / (ts * 0.5)), roundi(p.y / (ts * 0.5)))


## Сгладить контур: квадратичные Безье через середины рёбер — углы
## становятся плавными дугами, блоб читается природным.
func _smooth_loop(raw: PackedVector2Array) -> PackedVector2Array:
	var n := raw.size()
	if n < 3:
		return PackedVector2Array()
	var out := PackedVector2Array()
	for i in n:
		var p := raw[i]
		var m0 := (raw[(i - 1 + n) % n] + p) * 0.5
		var m1 := (p + raw[(i + 1) % n]) * 0.5
		for k in range(1, 4):
			var u := float(k) / 4.0
			var a := m0.lerp(p, u)
			var b := p.lerp(m1, u)
			out.append(a.lerp(b, u))
	return out


func _loop_area(loop: PackedVector2Array) -> float:
	var a := 0.0
	for i in loop.size():
		var p := loop[i]
		var q := loop[(i + 1) % loop.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


func _poly_centroid(loop: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in loop:
		c += p
	return c / float(maxi(1, loop.size()))


## Глубина вложенности контура (острова в воде, пруды на островах).
func _loop_depth(loop: PackedVector2Array, all_loops: Array) -> int:
	var c := _poly_centroid(loop)
	var depth := 0
	for other in all_loops:
		if other != loop and _loop_area(other) > _loop_area(loop) \
				and Geometry2D.is_point_in_polygon(c, other):
			depth += 1
	return depth


## Прост ли контур: без самопересечений (сегменты не-соседей не пересекаются)
## и без вырожденных рёбер. Гладкий контур изредка выходил самопересечением —
## мусорная триангуляция красила чужие тайлы (v1.30.1).
func _loop_is_simple(loop: PackedVector2Array) -> bool:
	var n := loop.size()
	if n < 4:
		return true
	for i in n:
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[(i + 1) % n]
		if a.distance_to(b) < 0.5:
			return false
		for j in range(i + 1, n):
			if j == i or (j + 1) % n == i or (i + 1) % n == j:
				continue   # соседние сегменты
			var c: Vector2 = loop[j]
			var d: Vector2 = loop[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != Vector2.INF:
				return false
	return true


## Вписать контур к центроиду (внутренняя заливка глубины).
func _shrunk_loop(loop: PackedVector2Array, f: float) -> PackedVector2Array:
	var c := _poly_centroid(loop)
	var out := PackedVector2Array()
	for p in loop:
		out.append(c + (p - c) * f)
	return out


## Надёжная заливка региона: тайлы внутри контура (триангуляция большого
## сглаженного полигона нестабильна — падает на почти-коллинеарных точках).
## Гладкость края даёт _stroke_inside поверх.
var _fill_debug_count := 0


## Заливка региона: полигон (контур теперь простой — починен сшивкой),
## при отказе триангуляции — деградация к тайлам по центрам.
## Заливка региона: кэшированная триангуляция (быстрый путь, v1.28.1) или
## разовая триангуляция/тайлы. Триангуляция большого сглаженного полигона
## дорога — потому кэшируется вместе с контуром.
func _fill_loop_cached(loop: PackedVector2Array, tris: PackedInt32Array, col: Color) -> void:
	if tris.is_empty():
		_drawer.draw_colored_polygon(loop, col)
		return
	var cols := PackedColorArray()
	cols.resize(loop.size())
	cols.fill(col)
	# draw_polygon не принимает индексы — пишем триангуляцию через RS
	RenderingServer.canvas_item_add_triangle_array(_drawer.get_canvas_item(),
			tris, loop, cols)


func _fill_loop(loop: PackedVector2Array, col: Color, ts: float) -> void:
	if Geometry2D.triangulate_polygon(loop).is_empty():
		_fill_loop_tiles(loop, col, ts)
		return
	_drawer.draw_colored_polygon(loop, col)


func _fill_loop_tiles(loop: PackedVector2Array, col: Color, ts: float) -> void:
	_fill_debug_count = 0
	for y in map.h:
		for x in map.w:
			var c := Vector2((x + 0.5) * ts, (y + 0.5) * ts)
			if Geometry2D.is_point_in_polygon(c, loop):
				_drawer.draw_rect(Rect2(Vector2(x * ts, y * ts), Vector2(ts, ts)), col)
				_fill_debug_count += 1


## Широкая обводка чуть внутри контура — сглаживает ступенчатый край тайлов.
func _stroke_inside(loop: PackedVector2Array, f: float, width: float, col: Color) -> void:
	var pts := _shrunk_loop(loop, f)
	if pts.size() < 2:
		return
	pts.append(pts[0])
	_drawer.draw_polyline(pts, col, width)


## Обводка прямо по контуру (пляж/кромка массива): гасит ступени тайлов,
## выступающие из-под сглаженной кривой (~0.35 тайла на углах).
func _stroke_on_loop(loop: PackedVector2Array, width: float, col: Color) -> void:
	if loop.size() < 2:
		return
	var pts := loop.duplicate()
	pts.append(pts[0])
	_drawer.draw_polyline(pts, col, width)


## Дороги (M6): тёплые плитки с камешками — в духовке (v1.22).
func _draw_roads_baked() -> void:
	var col: Color = colors.get("road", Color("#6e5f4a"))
	for tile: Vector2i in map.road:
		var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
		_drawer.draw_rect(rect, col)
		_drawer.draw_circle(rect.position + Vector2(map.ts * 0.3, map.ts * 0.4), 2.0, col.lightened(0.2))
		_drawer.draw_circle(rect.position + Vector2(map.ts * 0.65, map.ts * 0.65), 1.6, col.lightened(0.15))


## Зоны (M6, v1.22 в духовке): заливка типа, борозды поля, точки пастбища,
## забор по периметру. Растения и полосы прогресса обустройства остаются
## в живом слое — стадии роста меняются слишком часто для перевыпечки.
func _draw_zones_baked() -> void:
	if sim == null:
		return
	var fill_work: float = float(sim.cfg.get("zones", {}).get("fill_work", 4.0))
	for z in sim.zones:
		var col: Color = _zone_colors.get(String(z["type"]), Color(0.7, 0.7, 0.4))
		for i in (z["cells"] as Array).size():
			var tile: Vector2i = z["cells"][i]
			var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
			var filled: bool = float(z["progress"][i]) >= fill_work
			_drawer.draw_rect(rect, Color(col.r, col.g, col.b, 0.42 if filled else 0.32))
			if String(z["type"]) == "field":
				for k: int in 3:
					var y: float = rect.position.y + map.ts * (0.25 + 0.25 * k)
					_drawer.draw_line(Vector2(rect.position.x + 4, y),
							Vector2(rect.position.x + map.ts - 4, y),
							col.darkened(0.3 if filled else 0.15),
							1.5 if filled else 1.0)
				if filled:
					_drawer.draw_rect(rect.grow(-2), col.darkened(0.15), false, 1.5)
			else:
				_drawer.draw_circle(rect.position + Vector2(10, 20), 3.0, col.darkened(0.35))
				_drawer.draw_circle(rect.position + Vector2(22, 12), 3.0, col.darkened(0.35))
		if String(z["type"]) == "pasture":
			_draw_zone_fence_baked(z)


## Забор пастбища: по внешним рёбрам клеток зоны — перекладина и столбики.
func _draw_zone_fence_baked(z: Dictionary) -> void:
	var ts := float(map.ts)
	var inside := {}
	for c in z["cells"]:
		inside[Vector2i(c)] = true
	var wood := Color("#7a5a3a")
	var dark := Color("#5d4030")
	for c: Vector2i in inside.keys():
		var p := Vector2(c) * ts
		var edges := []
		if not inside.has(c + Vector2i(1, 0)):
			edges.append([p + Vector2(ts, 0), p + Vector2(ts, ts), p + Vector2(ts, ts * 0.5)])
		if not inside.has(c + Vector2i(-1, 0)):
			edges.append([p, p + Vector2(0, ts), p + Vector2(0, ts * 0.5)])
		if not inside.has(c + Vector2i(0, 1)):
			edges.append([p + Vector2(0, ts), p + Vector2(ts, ts), p + Vector2(ts * 0.5, ts)])
		if not inside.has(c + Vector2i(0, -1)):
			edges.append([p, p + Vector2(ts, 0), p + Vector2(ts * 0.5, 0)])
		for e in edges:
			_drawer.draw_line(e[0], e[1], wood, 2.5)
			_drawer.draw_line(e[2], e[2] + Vector2(0, -8), dark, 2.5)
			_drawer.draw_circle(e[2] + Vector2(0, -8), 1.6, dark)


## Каменные плиты площади 2×2 (правки v1.20, v1.22 в духовке). Пульс «места
## сбора» остался в живом слое.
func _draw_plaza_baked() -> void:
	if sim == null or sim.plaza == Vector2i(-1, -1):
		return
	var ts := float(map.ts)
	var origin := Vector2(sim.plaza) * ts
	var rect := Rect2(origin, Vector2(ts * 2.0, ts * 2.0))
	_drawer.draw_rect(rect, Color("#9aa0a8"))
	for i in 4:
		var cx := origin.x + ts * (0.5 + float(i % 2))
		var cy := origin.y + ts * (0.5 + float(i / 2))
		_drawer.draw_rect(Rect2(cx - ts * 0.42, cy - ts * 0.42, ts * 0.84, ts * 0.84), Color("#8a9098"))
	_drawer.draw_rect(rect, Color("#5d6470"), false, 2.0)
	_drawer.draw_circle(origin + Vector2(ts, ts), ts * 0.16, Color("#e8e2d0"))


## Детерминированный «шум» тайла: 0..n-1 (одинаков при каждой перерисовке).
static func _hash(x: int, y: int, n: int, salt: int = 0) -> int:
	var v := int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791))
	return absi(v) % maxi(1, n)


## Пустая порода выработанного массива (v1.21): тёмная осыпь щебня — по ней
## видно, что гряда вычерпана, и сюда можно ставить шахту.
func _draw_deadrock(x: int, y: int, rect: Rect2, ts: float) -> void:
	var base := Color("#4a463f").lightened(0.03 * float(_hash(x, y, 3) - 1))
	_drawer.draw_rect(rect, base)
	# щебень: крупные тёмные глыбы и мелкая крошка по хэшу
	for i in 5:
		var h := _hash(x * 7 + i, y * 13 + i, 100)
		var cx := rect.position.x + 4.0 + float(h % int(ts - 8.0))
		var cy := rect.position.y + 5.0 + float((h / 4) % int(ts - 10.0))
		var r := 1.4 + float(h % 3) * 0.7
		_drawer.draw_circle(Vector2(cx, cy), r, base.darkened(0.18 if i % 2 == 0 else 0.08))
	# блик блужающего металла — намёк на жилы под породой
	var hx := _hash(x, y * 3, 4)
	if hx == 0:
		_drawer.draw_circle(rect.get_center() + Vector2(3.0, -4.0), 1.4, Color("#8a7f6a"))
	_drawer.draw_rect(rect, Color("#2e2b26"), false, 1.0)


## Трава: плавные пятна (билинейный шум, без прямых краёв блоков) + зерно яркости.
func _noise2(xf: float, yf: float, n: int, salt: int) -> float:
	var x0 := int(floorf(xf))
	var y0 := int(floorf(yf))
	var fx := xf - float(x0)
	var fy := yf - float(y0)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := float(_hash(x0, y0, n, salt))
	var b := float(_hash(x0 + 1, y0, n, salt))
	var c := float(_hash(x0, y0 + 1, n, salt))
	var d := float(_hash(x0 + 1, y0 + 1, n, salt))
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


func _grass_at(x: int, y: int) -> Color:
	var idx := int(_noise2(x / 7.0, y / 7.0, _grass_shades.size(), 11))
	var shade: Color = _grass_shades[clampi(idx, 0, _grass_shades.size() - 1)]
	var j := _hash(x, y, 9) - 4   # -4..4
	if j > 0:
		return shade.lightened(0.01 * j)
	return shade.darkened(0.01 * -j)


## Трава: пучки травинок + редкие камешки + ЦВЕТОЧНЫЕ ПОЛЯНЫ (v1.27):
## крупноячеистый шум выделяет луга, на них по хэшу цветут 2–4 цветка
## (белый/жёлтый/розовый/василёк/мак) — поляны, а не рассыпанный горох.
const FLOWER_COLS := [
	Color("#f2f0e4"), Color("#e8d44d"), Color("#e88bb0"),
	Color("#8fb4e8"), Color("#d9584f"),
]


func _draw_grass_detail(x: int, y: int, rect: Rect2, base: Color, ts: float) -> void:
	var dark := base.darkened(0.14)
	var light := base.lightened(0.08)
	# пучки: 3 травинки с изломом — земля не «пластмассит»
	for i in 3:
		var h := _hash(x * 3 + i, y * 7 + i, 100)
		var px := rect.position.x + 4.0 + float(h % int(ts - 8.0))
		var py := rect.position.y + 5.0 + float((h / 7) % int(ts - 10.0))
		var col := dark if i % 2 == 0 else light
		_drawer.draw_line(Vector2(px, py), Vector2(px + 1.0, py - 3.0 - float(h % 3)), col, 1.0)
	# камешек: редкий серый бугорок
	if _hash(x * 13, y * 3, 200) == 0:
		_drawer.draw_circle(rect.position + Vector2(8.0 + float(_hash(x, y, 40) % 14), 9.0), 1.8,
				Color("#9a958a"))
		_drawer.draw_circle(rect.position + Vector2(7.4, 8.4), 0.9, Color("#b5b0a4"))
	# цветочная поляна: шум крупными пятнами (нормирован 0..1), цветёт
	# только сердцевина пятна — поляна читается островом среди луга
	var field := _noise2(x / 6.0, y / 6.0, 100, 71) / 99.0
	if field > 0.80:
		var blooms := 1 + _hash(x, y, 13) % 2
		for i in blooms:
			var h2 := _hash(x * 17 + i, y * 19 + i, 100)
			var c := rect.position + Vector2(5.0 + float(h2 % int(ts - 10.0)),
					5.0 + float((h2 / 7) % int(ts - 10.0)))
			var fcol: Color = FLOWER_COLS[_hash(x + i, y - i, FLOWER_COLS.size())]
			# цветок: 4 лепестка и жёлтая серединка (при 32px — читаемая точка)
			_drawer.draw_circle(c + Vector2(-1.0, -1.0), 0.9, fcol)
			_drawer.draw_circle(c + Vector2(1.0, -1.0), 0.9, fcol)
			_drawer.draw_circle(c + Vector2(-1.0, 1.0), 0.9, fcol)
			_drawer.draw_circle(c + Vector2(1.0, 1.0), 0.9, fcol)
			_drawer.draw_circle(c, 0.7, Color("#e8c94d"))


## Вода v1.27.1 — ОРГАНИЧНЫЕ водоёмы (референс RimWorld/Dwarf Fortress):
## контур по marching squares, сглаженный Безье; заливка с глубиной,
## песчаная кромка-обводка, светлая линия уреза. Острова в воде и пруды
## на островах обрабатываются вложенностью контуров. Поверх — блики,
## кувшинки и камыши на берегу.
func _draw_water_blobs(ts: float) -> void:
	var deep_col: Color = colors.get("water_deep", colors["water"].darkened(0.28))
	var shore_col: Color = colors.get("shore", Color("#c8b183"))
	# v1.28.1: контуры+триангуляция — из кэша (маска воды меняется только
	# со сменой сетки); пересчёт — по _blob_cache_dirty из rebake(heavy)
	if _blob_cache_dirty:
		_water_cached = []
		_water_tile_kind = {}
		var raw: Array = _mask_loops(func(t: Vector2i) -> bool:
			return map.grid[t.y][t.x] == map.TILE_WATER)
		raw.sort_custom(func(a, b) -> bool: return _loop_area(a) > _loop_area(b))
		var smootheds: Array = []
		for rl in raw:
			smootheds.append(_smooth_loop(rl))
		for sm in smootheds:
			var tiles := _loop_tiles(sm, ts)
			var simple := _loop_is_simple(sm)
			# v1.29.1: тип водоёма считает КАРТА (он нужен и путям/броду);
			# локальный расчёт по силуэту — страховка для карт без неё
			var kind := ""
			if not tiles.is_empty():
				kind = map.water_kind_at(tiles[0])
			if kind == "":
				kind = _water_kind(sm, ts)
			for t: Vector2i in tiles:
				_water_tile_kind[t] = kind
			# v1.30.1: сглаженный контур бывает САМОПЕРЕСЕКАЮЩИМСЯ — триангуляция
			# и обводки такого контура дают мусорные «пятна» чужого цвета
			# (песок поверх травы). Деградация: заливка по тайлам, без обводок.
			_water_cached.append({"loop": sm,
					"tris": Geometry2D.triangulate_polygon(sm) if simple else PackedInt32Array(),
					"depth": _loop_depth(sm, smootheds),
					"kind": kind, "tiles": tiles, "simple": simple})
		_rock_cached = _build_rock_cache()
		_blob_cache_dirty = false
	for entry in _water_cached:
		var loop: PackedVector2Array = entry["loop"]
		var depth: int = int(entry["depth"])
		var kind := String(entry["kind"])
		var simple := bool(entry.get("simple", true))
		if not simple:
			# мусорный контур: честные квадратные тайлы цветом воды
			for t: Vector2i in entry["tiles"]:
				_drawer.draw_rect(Rect2(Vector2(t) * ts, Vector2(ts, ts)),
						_water_river if kind == "river" else _water_lake)
			continue
		if kind == "swamp":
			# болото рисуется ЧЕСТНЫМИ квадратными тайлами — сглаживанию
			# мелкие кляксы не идут (замечание заказчика 2026-10-28)
			continue
		if depth % 2 == 1:
			var c := _poly_centroid(loop)
			_fill_loop_cached(loop, entry["tris"], _grass_at(int(c.x / ts), int(c.y / ts)))
			_stroke_on_loop(loop, ts * 0.6, Color("#6d8a4e").darkened(0.05))
			continue
		_fill_loop_cached(loop, entry["tris"],
				_water_river if kind == "river" else _water_lake)
		# глубина: один мягкий тёмный контур только у БОЛЬШИХ озёр (у рек
		# течение и так читается струями, у малых прудов контур был «ромбом»)
		if kind == "lake" and _loop_area(loop) > 18.0 * ts * ts:
			_stroke_inside(loop, 0.60, ts * 0.8, Color(deep_col.r, deep_col.g, deep_col.b, 0.4))
	# берег (волна 6): песок ВНУТРИ кромки воды. Раньше штрих шёл по контуру
	# шириной 0.9 тайла — на узкой реке съедал всю воду («реки мутные»), а на
	# малых водоёмах выплёскивался на соседние скалы («текстуры залазят»)
	for entry in _water_cached:
		if String(entry["kind"]) == "swamp" or not bool(entry.get("simple", true)):
			continue
		var loop: PackedVector2Array = entry["loop"]
		if int(entry["depth"]) % 2 == 1:
			continue
		var kind := String(entry["kind"])
		var area := _loop_area(loop)
		# v1.29.4: ширина песка — по размеру водоёма: у малых прудов тонкая
		# (раньше кромка съедала воду — оставалась «голубая щёлочка в глазке»)
		var w := ts * 0.16
		if area > 12.0 * ts * ts:
			w = ts * 0.3
		if kind == "lake" and area > 30.0 * ts * ts:
			w = ts * 0.55
		_stroke_inside(loop, 0.985, w, shore_col)
		# влажный блеск у кромки — только у средних и больших водоёмов
		if area > 12.0 * ts * ts:
			var wcol: Color = _water_river if kind == "river" else _water_lake
			_stroke_inside(loop, 0.955, 1.5, Color(wcol.lightened(0.25), 0.45))
	_draw_swamp_blobs(ts)
	# украшения по тайлам внутри контура — у каждой воды свои
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] != map.TILE_WATER:
				continue
			var rect := Rect2(x * ts, y * ts, ts, ts)
			var kind: String = _water_tile_kind.get(Vector2i(x, y), "lake")
			if kind == "swamp":
				continue   # болото украшено в _draw_swamp_blobs
			if kind == "river":
				_draw_river_flow(x, y, rect, ts)
			else:
				_draw_water_detail(x, y, rect, ts)
				if _water_deep(x, y) <= 2 and _hash(x, y, 17) == 0:
					_draw_lily_pads(Vector2(x * ts, y * ts), ts, x, y)
				# тина (v1.28): болотная плёнка на отмелях озёр
				if _water_deep(x, y) <= 1 and _hash(x * 3, y * 7, 29) % 3 == 0:
					_drawer.draw_circle(rect.position + Vector2(ts * 0.4, ts * 0.5),
							ts * 0.34, Color("#6b7d4f", 0.35))
					_drawer.draw_circle(rect.position + Vector2(ts * 0.65, ts * 0.35),
							ts * 0.22, Color("#7a8d55", 0.28))
	# берег (v1.28): грязевые проплешины на прибрежной траве — топь у озёр
	# и болот; у реки берег песчаный и чистый, только редкий камыш
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if map.grid[y][x] == map.TILE_GRASS and _near_water(t):
				var near_kind := _shore_kind(t)
				var rect2 := Rect2(Vector2(t) * ts, Vector2(ts, ts))
				if near_kind != "river" and _hash(x * 13, y * 3, 31) % 5 == 0:
					_drawer.draw_circle(rect2.get_center() + Vector2(3, -2),
							ts * 0.3, Color("#5f5142", 0.55))
					_drawer.draw_circle(rect2.get_center() + Vector2(-4, 3),
							ts * 0.2, Color("#6b5c4a", 0.45))
				var reed_rarity := 5 if near_kind == "river" else 23
				if _hash(x * 3, y * 5, 23) % reed_rarity < 3:
					_draw_reeds(Vector2(t) * ts, ts, x, y)


## Тип водоёма по силуэту (правки приёмки v1.29.1: «если болото то болото,
## если озеро или река — они разные»): вытянутая лента — река, малое
## компактное пятно — болотце (квадратные тайлы), остальное — озеро.
func _water_kind(loop: PackedVector2Array, ts: float) -> String:
	var mn: Vector2 = loop[0]
	var mx: Vector2 = loop[0]
	for p in loop:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var size := mx - mn
	var long_side := maxf(size.x, size.y)
	var short_side := maxf(1.0, minf(size.x, size.y))
	if long_side / short_side >= 2.8:
		return "river"
	if _loop_area(loop) <= 16.0 * ts * ts:
		return "swamp"
	return "lake"


## Тайлы внутри контура (по центрам клеток) — для квадратных болот и
## справочника «тайл -> тип воды».
func _loop_tiles(loop: PackedVector2Array, ts: float) -> Array:
	var out: Array = []
	for y in map.h:
		for x in map.w:
			if Geometry2D.is_point_in_polygon(Vector2((x + 0.5) * ts, (y + 0.5) * ts), loop):
				out.append(Vector2i(x, y))
	return out


## Тип воды у берега (для грязи/камышей на прибрежной траве): вид ближайшего
## водного соседа; река — если хоть один сосед речной.
func _shore_kind(t: Vector2i) -> String:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := t + Vector2i(dx, dy)
			if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER:
				if String(_water_tile_kind.get(n, "lake")) == "river":
					return "river"
	return "lake"


## Течение реки: направленные струи вдоль русла (река течёт по Y, меандр
## по X — city_map._generate_river). Никаких кувшинок — вода бежит.
func _draw_river_flow(x: int, y: int, rect: Rect2, ts: float) -> void:
	if _hash(x, y, 41) % 2 != 0:
		return
	var col: Color = _water_river.lightened(0.45)
	col.a = 0.5
	for i in 2:
		var h := _hash(x * 5 + i, y * 11 + i, 100)
		var px := rect.position.x + 5.0 + float(h % int(ts - 14.0))
		var py := rect.position.y + 4.0 + float((h / 5) % int(ts - 16.0))
		var ln := ts * (0.3 + 0.06 * float(h % 3))
		_drawer.draw_line(Vector2(px, py), Vector2(px, py + ln), col, 1.3)
		_drawer.draw_line(Vector2(px, py + ln), Vector2(px, py + ln + 3.0),
				Color(col.r, col.g, col.b, col.a * 0.5), 1.0)


## Болотце (правки приёмки v1.29.1): ЧЕСТНЫЕ КВАДРАТНЫЕ тайлы — мутная
## зелёно-бурая жижа с тёмной кромкой плитки, кочки и камыши. Без
## сглаживания: малым кляксам оно не идёт (замечание заказчика).
func _draw_swamp_blobs(ts: float) -> void:
	for entry in _water_cached:
		if String(entry["kind"]) != "swamp":
			continue
		for t: Vector2i in entry["tiles"]:
			var rect := Rect2(Vector2(t) * ts, Vector2(ts, ts))
			var tone := 0.05 * float(_hash(t.x, t.y, 5) - 2)
			# v1.30.1: болото читается ТОПЬЮ, не «маленьким озером» — тёмная
			# трясина без синевы, лужи-оконца, кочки
			var fill := Color("#46523a").lightened(tone)
			_drawer.draw_rect(rect, fill)
			_drawer.draw_rect(rect, fill.darkened(0.25), false, 1.5)
			var hx := _hash(t.x * 3, t.y * 7, 100)
			if hx % 3 == 0:
				# лужа-оконце: тёмная стоячая вода с бликом
				var pc := rect.position + Vector2(6.0 + float(hx % int(ts - 14.0)),
						6.0 + float((hx / 5) % int(ts - 14.0)))
				_drawer.draw_circle(pc, ts * 0.16, Color("#28322a"))
				_drawer.draw_circle(pc + Vector2(-1.0, -1.0), ts * 0.07, Color("#3d4f44"))
			for i in 1 + hx % 2:
				var h2 := _hash(t.x * 7 + i, t.y * 13 + i, 100)
				var c := rect.position + Vector2(6.0 + float(h2 % int(ts - 12.0)),
						6.0 + float((h2 / 5) % int(ts - 12.0)))
				_drawer.draw_circle(c, 2.6 + float(h2 % 2), Color("#6a7548"))
				_drawer.draw_circle(c + Vector2(-0.8, -0.8), 1.2, Color("#7d8a54"))
			if _hash(t.x, t.y * 3, 4) == 0:
				_draw_reeds(rect.position, ts, t.x, t.y)


## Тип водоёма в тайле («lake» | «river» | «swamp») — цвета воды и кромка.
## Первоисточник — карта (water_kind), локальный — страховка.
func water_kind_at(t: Vector2i) -> String:
	var k: String = map.water_kind_at(t)
	return k if k != "" else String(_water_tile_kind.get(t, "lake"))


## Сколько водных соседей по 8 направлениям (глубина плиты).
func _water_deep(x: int, y: int) -> int:
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var t := Vector2i(x + dx, y + dy)
			if map.in_bounds(t) and map.grid[t.y][t.x] == map.TILE_WATER:
				n += 1
	return n


func _near_water(t: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = t + d
		if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER:
			return true
	return false


## Кромка воды: песчаная полоса по береговым рёбрам + четверть-круги на углах.
## Внешний угол (оба ортогональных соседа — земля) закрашивается травой —
## плита воды становится «кляксой»; внутренний угол (соседи вода, диагональ —
## земля) заливается водой — залив округляется без квадратной выемки.
func _draw_water_edges(x: int, y: int, ts: float, shore_col: Color) -> void:
	var rect := Rect2(x * ts, y * ts, ts, ts)
	var p := rect.position
	var wet := func(off: Vector2i) -> bool:
		var t := Vector2i(x, y) + off
		return map.in_bounds(t) and map.grid[t.y][t.x] == map.TILE_WATER
	var grass := func(off: Vector2i) -> Color:
		var t := Vector2i(x, y) + off
		return _grass_at(t.x, t.y) if map.in_bounds(t) else _grass_at(x, y)
	# песчаная кромка по рёбрам к земле
	var sw := 3.0
	if not wet.call(Vector2i(1, 0)):
		_drawer.draw_rect(Rect2(p + Vector2(ts - sw, 0), Vector2(sw, ts)), shore_col)
	if not wet.call(Vector2i(-1, 0)):
		_drawer.draw_rect(Rect2(p, Vector2(sw, ts)), shore_col)
	if not wet.call(Vector2i(0, 1)):
		_drawer.draw_rect(Rect2(p + Vector2(0, ts - sw), Vector2(ts, sw)), shore_col)
	if not wet.call(Vector2i(0, -1)):
		_drawer.draw_rect(Rect2(p, Vector2(ts, sw)), shore_col)
	# скругления: внешний угол — трава накрывает угол плиты,
	# внутренний — вода заполняет угол соседней травы
	var r := ts * 0.42
	var corners := [
		[Vector2i(1, -1), p + Vector2(ts, 0), Vector2(-1, 1)],
		[Vector2i(-1, -1), p, Vector2(1, 1)],
		[Vector2i(-1, 1), p + Vector2(0, ts), Vector2(1, -1)],
		[Vector2i(1, 1), p + Vector2(ts, ts), Vector2(-1, -1)],
	]
	for c in corners:
		var diag: Vector2i = c[0]
		var corner: Vector2 = c[1]
		var inward: Vector2 = c[2]
		var h: Vector2i = Vector2i(int(inward.x), 0)
		var v: Vector2i = Vector2i(0, int(inward.y))
		if wet.call(h) and wet.call(v):
			# внутренний угол: диагональ — земля, зальём её угол водой
			# (круглая бухта); вода идёт НАРУЖУ от плиты — направление -inward
			if not wet.call(diag):
				_water_quarter(corner, -inward, r, colors["water"].lightened(0.06))
		elif not wet.call(h) and not wet.call(v):
			# внешний угол: накрываем угол плиты травой соседа — плита воды
			# становится «кляксой», песчаная кромка по рёбрам сохраняется
			var gcol: Color = grass.call(h)
			_water_quarter(corner, inward, r + sw * 0.5, gcol)


## Четверть круга из угла corner в направлении inward (полигон-веер).
func _water_quarter(corner: Vector2, inward: Vector2, r: float, col: Color) -> void:
	if r < 1.0:
		return
	var dx := signf(inward.x)
	var dy := signf(inward.y)
	var pts := PackedVector2Array([corner])
	var steps := 7
	for i in range(steps + 1):
		var a := (float(i) / float(steps)) * (PI / 2.0)
		pts.append(corner + Vector2(dx * cos(a), dy * sin(a)) * r)
	_drawer.draw_colored_polygon(pts, col)


## Кувшинки: пара листьев-эллипсов с выемкой и бликом.
func _draw_lily_pads(origin: Vector2, ts: float, x: int, y: int) -> void:
	for i in 2:
		var h := _hash(x * 5 + i, y * 9 + i, 100)
		var c := origin + Vector2(6.0 + float(h % int(ts - 14.0)), 6.0 + float((h / 5) % int(ts - 14.0)))
		var r := 3.0 + float(h % 3)
		var col := Color("#4e7c3a").lightened(0.05 * float(i))
		_drawer.draw_circle(c, r, col)
		_drawer.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, col.lightened(0.25))
		# выемка листа — тёмный клин
		_drawer.draw_line(c, c + Vector2(r + 0.6, 0.6), colors["water"].lightened(0.08), 1.2)


## Камыши (v1.27): 2–4 стебля с тёмной шишкой — болотная кромка водоёмов.
func _draw_reeds(origin: Vector2, ts: float, x: int, y: int) -> void:
	var stem := Color("#4e6b34")
	var head := Color("#7a5230")
	var n := 2 + _hash(x, y, 5) % 3
	for i in n:
		var h := _hash(x * 7 + i, y * 11 + i, 100)
		var base := origin + Vector2(5.0 + float(h % int(ts - 10.0)), ts * 0.85)
		var lean := 1.6 + float(h % 3) * 0.8
		var top := base + Vector2(lean, -ts * (0.5 + 0.14 * float(h % 3)))
		_drawer.draw_line(base, top, stem, 1.4)
		_drawer.draw_line(top, top + Vector2(lean * 0.5, -3.0), stem, 1.1)
		# шишка камыша — короткая тёмная капсула на конце
		_drawer.draw_line(top + Vector2(lean * 0.5, -3.0), top + Vector2(lean * 0.6, -7.0), head, 2.4)
		_drawer.draw_circle(top + Vector2(lean * 0.6, -7.0), 1.2, head.darkened(0.2))


## Блики воды: светлые чёрточки по хэшу — прорежены (примерно каждый
## третий тайл, сплошной крап «шумел» на больших прудах).
func _draw_water_detail(x: int, y: int, rect: Rect2, ts: float) -> void:
	if _hash(x, y, 41) % 3 != 0:
		return
	var col: Color = _water_lake
	col = col.lightened(0.35)
	col.a = 0.4
	for i in 2:
		var h := _hash(x * 5 + i, y * 11 + i, 100)
		var px := rect.position.x + 5.0 + float(h % int(ts - 14.0))
		var py := rect.position.y + 6.0 + float((h / 5) % int(ts - 12.0))
		_drawer.draw_line(Vector2(px, py), Vector2(px + 4.0 + float(h % 4), py), col, 1.2)


## Скальная гряда v1.27.2 — СПЛОШНОЙ массив (референс RimWorld/Dwarf
## Fortress, правка заказчика: бледные круги-валуны читались «облаками»).
## Светлая порода, лёгкая пятнистость, тёмная кромка по краю; трещины
## добычи и руда — по тайлам.
func _draw_rock_blobs(ts: float) -> void:
	for entry in _rock_cached:
		var loop: PackedVector2Array = entry["loop"]
		var c := _poly_centroid(loop)
		# v1.29.4 «натуральная гора»: базовый тон массива дышит по блобу,
		# светлая солнечная грань сверху, тёмное подножие — полосой ТОЛЬКО
		# по нижней половине контура (раньше тёмная кромка шла по всему
		# силуэту и читалась «крыльями»), крупные фасеты вместо крапинок
		var tone := _noise2(c.x / (ts * 3.0), c.y / (ts * 3.0), 30, 91) / 29.0
		var base := Color("#857e71").lightened(0.05 * tone - 0.025)
		_fill_loop_cached(loop, entry["tris"], base)
		var area := _loop_area(loop)
		if area > 6.0 * ts * ts:
			# светлая вершина и тёмное подножие: сжатие слабое (0.8), сдвиг
			# малый — на органичном силуэте читается светом/тенью, а не
			# концентрическими кольцами (v1.29.4)
			var top := _shrunk_loop(loop, 0.80)
			for i in top.size():
				top[i] += Vector2(-ts * 0.03, -ts * 0.06)
			_fill_loop_cached(top, Geometry2D.triangulate_polygon(top),
					base.lightened(0.08))
			var foot := _shrunk_loop(loop, 0.80)
			for i in foot.size():
				foot[i] += Vector2(0, ts * 0.09)
			_fill_loop_cached(foot, Geometry2D.triangulate_polygon(foot),
					base.darkened(0.10))
			# грань: 3–5 мягких сколов-пятен ГЛУБОКО внутри силуэта — фактура
			# камня без «горошка» и без вылезания за контур (v1.29.4)
			var r_in := sqrt(area / PI) * 0.45
			var n := 3 + int(area / (26.0 * ts * ts))
			for f in mini(n, 5):
				var a0 := TAU * float(_hash(f * 31, int(c.x), 100)) / 100.0
				var p0 := c + Vector2(cos(a0), sin(a0) * 0.75) * r_in
				var rr := sqrt(area / PI) * (0.22 + 0.1 * float(_hash(f * 7, int(c.y), 100)) / 100.0)
				var fc := base.darkened(0.05) if f % 2 == 0 else base.lightened(0.05)
				_draw_ellipse(p0, rr, rr * 0.72, Color(fc, 0.55))
		# кромка: тёмная полоса только по НИЖНЕЙ половине силуэта —
		# подножие в тени; верхний край наоборот подсвечен
		_stroke_bottom_rim(loop, ts, base)
	# трещины добычи и руда — по тайлам внутри массива
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			var g: int = map.grid[y][x]
			if g != map.TILE_ROCK and g != map.TILE_ORE:
				continue
			_draw_rock_tile_detail(x, y, g == map.TILE_ORE, ts)


## Тёмное подножие по нижней дуге контура: сегменты, чья нормаль смотрит вниз.
func _stroke_bottom_rim(loop: PackedVector2Array, ts: float, base: Color) -> void:
	var cy := _poly_centroid(loop).y
	var band := PackedVector2Array()
	var open := false
	for i in loop.size() + 1:
		var p: Vector2 = loop[i % loop.size()]
		var below: bool = p.y > cy + ts * 0.15
		if below and not open:
			open = true
			band.clear()
		if open:
			band.append(p)
		if open and not below and band.size() >= 3:
			_stroke_on_loop(band, ts * 0.42, base.darkened(0.22))
			open = false
	if open and band.size() >= 3:
		_stroke_on_loop(band, ts * 0.42, base.darkened(0.22))


## Кэш скальных блобов (контуры + триангуляция) — пересчёт только при
## смене сетки (rebake(heavy)), см. v1.28.1.
func _build_rock_cache() -> Array:
	var raw_loops: Array = _mask_loops(func(t: Vector2i) -> bool:
		return map.grid[t.y][t.x] == map.TILE_ROCK or map.grid[t.y][t.x] == map.TILE_ORE)
	var out: Array = []
	for raw in raw_loops:
		var sm := _smooth_loop(raw)
		out.append({"loop": sm, "tris": Geometry2D.triangulate_polygon(sm)})
	return out


## Фактура внутри скального блоба: трещины добычи и руда. Пятнистые точки
## убраны (v1.29.4) — читались «горошком» по массиву; фактуру дают фасеты.
func _draw_rock_tile_detail(x: int, y: int, ore: bool, ts: float) -> void:
	var rect := Rect2(Vector2(x * ts, y * ts), Vector2(ts, ts))
	# трещины по мере добычи: скала «оседает»
	var key := Vector2i(x, y)
	if map.rock_hp.has(key):
		var frac: float = clampf(float(map.rock_hp[key]) / maxf(1.0, _rock_hp_default), 0.0, 1.0)
		if frac < 0.66:
			_drawer.draw_line(rect.position + Vector2(ts * 0.3, ts * 0.35),
					rect.position + Vector2(ts * 0.5, ts * 0.7), Color(0.12, 0.11, 0.09, 0.85), 1.6)
		if frac < 0.33:
			_drawer.draw_line(rect.position + Vector2(ts * 0.65, ts * 0.2),
					rect.position + Vector2(ts * 0.5, ts * 0.55), Color(0.12, 0.11, 0.09, 0.85), 1.4)
	# руда (волна 6): кристаллы-ромбики с блеском вместо точек-горошин
	if ore:
		var gold := _hash(x, y, 4) == 0
		var col := Color("#e0b13e") if gold else Color("#b0684a")
		for i in 3:
			var h2 := _hash(x * 13 + i, y * 17 + i, 100)
			var fx := rect.position.x + 6.0 + float(h2 % int(ts - 12.0))
			var fy := rect.position.y + 9.0 + float((h2 / 3) % int(ts - 16.0))
			_draw_diamond(Vector2(fx, fy), 2.4 + float(h2 % 3), col)
			_draw_diamond(Vector2(fx - 1.0, fy - 1.2), 1.1, col.lightened(0.4))


## Заполненный эллипс полигоном (для глыб гряды).
func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.5 or ry <= 0.5:
		return
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	_drawer.draw_colored_polygon(pts, col)


## Ромб-кристалл (руда) с центром center и полудиагональю r.
func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	if r < 0.8:
		return
	_drawer.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r * 0.7, 0),
		center + Vector2(0, r), center + Vector2(-r * 0.7, 0),
	]), col)
