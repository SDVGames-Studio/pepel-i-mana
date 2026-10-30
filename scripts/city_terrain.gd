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
# v1.32: трава — ЗАПЕЧЁННЫЕ текстуры-тайлы (стиль dual-grid видео jess::codes):
# 3 тона-семейства (L/M/D) × 2 варианта, генератор tools/make_video_grass.py.
# Семейство выбирает крупный шум (пятна луга), вариант — хэш тайла.
var _grass_texs: Array = []
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
		# v1.34.1: water_tune — словарь тюнинга (не цвет), его не парсим
		if c[key] is String:
			colors[key] = Color(String(c[key]))
		elif c[key] is Dictionary:
			colors[key] = c[key]
	for t in city_cfg.get("zones", {}).get("types", {}):
		_zone_colors[String(t)] = Color(String(city_cfg["zones"]["types"][t]["color"]))
	_grass_shades = [colors["grass"], colors.get("grass_alt", colors["grass"]),
			colors.get("grass2", colors["grass"]).darkened(0.03)]
	for fam in ["L", "M", "D"]:
		for v in 2:
			_grass_texs.append(Assets.tex(
					"res://assets/sprites/env/grass_%s%d.png" % [fam, v + 1]))
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
var _water_covered: Dictionary = {}   # v1.34.1: тайлы, залитые блобами
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
var _lake_view = null    # water_lake.gd — рендер озера (v1.34.2)
var _river_view = null   # water_river.gd — рендер реки
var _swamp_view = null   # water_swamp.gd — рендер болота
var _rock_view = null    # rock_terrain.gd — рендер скал и жил
var _plateau_view = null # plateau_terrain.gd — рендер плато и утёсов (v1.36)


## Вью-файлы воды и скал: один тип — один файл, тюнинг в data/city.json
## (colors → "water_tune"). Подключаются лениво при первой выпечке.
func _ensure_views() -> void:
	if _lake_view == null:
		_lake_view = load("res://scripts/water_lake.gd").new()
		_lake_view.setup(self)
	if _river_view == null:
		_river_view = load("res://scripts/water_river.gd").new()
		_river_view.setup(self)
	if _swamp_view == null:
		_swamp_view = load("res://scripts/water_swamp.gd").new()
		_swamp_view.setup(self)
	if _rock_view == null:
		_rock_view = load("res://scripts/rock_terrain.gd").new()
		_rock_view.setup(self)
	if _plateau_view == null:
		_plateau_view = load("res://scripts/plateau_terrain.gd").new()
		_plateau_view.setup(self)


func _draw_tiles() -> void:
	if map == null:
		return
	_ensure_views()
	var ts := float(map.ts)
	# проход 1: земля (трава/осыпи) — вода и скалы рисуются блобами поверх.
	# v1.32: трава — текстурные тайлы (стиль видео dual-grid); текстура
	# отсутствует (не импортирована) — откат к плоской заливке _grass_at
	for y in map.h:
		for x in map.w:
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			match tile:
				map.TILE_GRASS, map.TILE_TREE:
					var tex: Texture2D = _grass_texture_at(x, y)
					if tex != null:
						_drawer.draw_texture_rect(tex, rect, false)
					else:
						_drawer.draw_rect(rect, _grass_at(x, y))
					_draw_grass_detail(x, y, rect, ts)
				map.TILE_DEADROCK:
					_draw_deadrock(x, y, rect, ts)
	# проход 2: скальная гряда и вода — ОРГАНИЧНЫЕ блобы (marching squares,
	# сглаживание Безье — стиль RimWorld/Dwarf Fortress, не по тайлам)
	_rock_view.draw_blobs(ts)
	_draw_water_blobs(ts)
	# проход 3: плато и утёсы (v1.36) — верхние грани, срезы-кромки по схеме
	# Hills, лестницы-проходы и тени у подножия; после воды/скал, чтобы тени
	# ложились на готовый ландшафт
	_plateau_view.draw_plateaus(ts)
	# v1.32: травяная бахрома по кромкам воды и скал — травинки «обнимают»
	# берег, как в видео (листья свисаются на границах тайлов)
	_draw_grass_fringe(ts)


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
## Блобы v1.34.2: marching squares + сглаживание ЧАЙКИНОМ (2 прохода).
## Срез углов сохраняет простоту контура — Безье на вогнутых прогонах
## больших блобов выходил «восьмёркой», триангуляция падала, и озёра
## деградировали в квадраты тайлов («почему мир квадратный» — приёмка
## v1.34.0). Органичный вид тот же: углы становятся плавными дугами.
func _smooth_loop(raw: PackedVector2Array) -> PackedVector2Array:
	var n := raw.size()
	if n < 3:
		return PackedVector2Array()
	var pts := raw
	for pass_i in 2:
		var out := PackedVector2Array()
		var m := pts.size()
		for i in m:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % m]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		pts = out
	return pts


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
## v1.34.1: убрать из замкнутого контура дубли точек и вершины, лежащие
## на прямой между соседями — нулевая площадь ушей роняет ear-clipping
## (Geometry2D.triangulate_polygon), заливка блоба не рисовалась.
static func _clean_loop(loop: PackedVector2Array) -> PackedVector2Array:
	var n := loop.size()
	if n < 3:
		return PackedVector2Array()
	var pts := PackedVector2Array()
	for i in n:
		var p: Vector2 = loop[i]
		if not pts.is_empty() and p.distance_to(pts[pts.size() - 1]) < 0.05:
			continue
		pts.append(p)
	while pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) < 0.05:
		pts.remove_at(pts.size() - 1)
	var changed := true
	while changed and pts.size() > 3:
		changed = false
		var out := PackedVector2Array()
		var m := pts.size()
		for i in m:
			var a: Vector2 = pts[(i - 1 + m) % m]
			var b: Vector2 = pts[i]
			var c: Vector2 = pts[(i + 1) % m]
			var cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
			var dot := (b.x - a.x) * (c.x - a.x) + (b.y - a.y) * (c.y - a.y)
			if absf(cross) < 0.05 and dot > 0.0:
				changed = true
				continue
			out.append(b)
		pts = out
	return pts if pts.size() >= 3 else PackedVector2Array()

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
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if hit == null:
				continue
			var hv: Vector2 = hit
			if hv == Vector2.INF or (is_nan(hv.x) and is_nan(hv.y)):
				continue
			# касание концами (общие вершины/углы) — не дефект
			if hv.is_equal_approx(a) or hv.is_equal_approx(b):
				continue
			if hv.is_equal_approx(c) or hv.is_equal_approx(d):
				continue
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


## Прогоны контура, где наружная нормаль смотрит в сторону dir_v (общая
## геометрия «языка высоты»: v1.37 — срез/тень скал, v1.37.1 — объём озёр).
## Возвращает массив прогонов [[точка, нормаль]...] по порядку обхода.
func dir_runs(loop: PackedVector2Array, c: Vector2, dir_v: Vector2,
		dot_min: float, min_len: int) -> Array:
	var runs: Array = []
	var run: Array = []
	var n := loop.size()
	for i in n + 1:
		var idx := i % n
		var p: Vector2 = loop[idx]
		var q: Vector2 = loop[(idx + 1) % n]
		var dir := q - p
		if dir.length() < 0.001:
			continue
		var nrm := Vector2(dir.y, -dir.x).normalized()
		if nrm.dot(p - c) < 0.0:
			nrm = -nrm   # наружу от центроида
		if nrm.dot(dir_v) >= dot_min:
			run.append([p, nrm])
		else:
			if run.size() >= min_len:
				runs.append(run)
			run = []
	if run.size() >= min_len:
		runs.append(run)
	return runs


## Обводка прогона со смещением вдоль нормали: off>0 — ВНУТРЬ региона
## (минус наружная нормаль), тень/вынос наружу — stroke_run_out.
func stroke_run(run: Array, off: float, width: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for e in run:
		pts.append((e[0] as Vector2) - (e[1] as Vector2) * off)
	pts.append(pts[0])
	_drawer.draw_polyline(pts, col, width)


## Обводка прогона со смещением НАРУЖУ (тень на траве за контуром).
func stroke_run_out(run: Array, off: float, width: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for e in run:
		pts.append((e[0] as Vector2) + (e[1] as Vector2) * off)
	pts.append(pts[0])
	_drawer.draw_polyline(pts, col, width)


## Заливка региона: полигон (контур теперь простой — починен сшивкой),
## при отказе триангуляции — деградация к тайлам по центрам.
## Заливка региона: кэшированная триангуляция (быстрый путь, v1.28.1) или
## разовая триангуляция/тайлы. Триангуляция большого сглаженного полигона
## дорога — потому кэшируется вместе с контуром.
func _fill_loop_cached(loop: PackedVector2Array, tris: PackedInt32Array, col: Color) -> void:
	if tris.is_empty():
		# v1.34.1: страховка заливки — чистим контур и триангулируем заново.
		# Раньше падение ear-clipping означало дырку: просвечивал серый фон
		# («сухая река», серые пятна на скриншотах приёмки v1.34.0).
		var clean := _clean_loop(loop)
		if clean.size() >= 3:
			var t2 := Geometry2D.triangulate_polygon(clean)
			if not t2.is_empty():
				_fill_loop_cached(clean, t2, col)
				return
			_drawer.draw_colored_polygon(clean, col)
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


## Текстура травяного тайла: семейство тонов — крупный шум (пятна луга,
## тот же масштаб, что выбирает и _grass_at), вариант внутри семейства —
## хэш тайла (соседние тайлы всегда разные, повтор 32px не ловится глазом).
func _grass_texture_at(x: int, y: int) -> Texture2D:
	if _grass_texs.is_empty():
		return null
	var fam := clampi(int(_noise2(x / 7.0, y / 7.0, 3, 11)), 0, 2)
	var v: int = _hash(x, y, 2)
	return _grass_texs[fam * 2 + v]


## Трава: редкие камешки + ЦВЕТОЧНЫЕ ПОЛЯНЫ (v1.27) поверх текстурного
## тайла (v1.32: пучки травинок теперь живут В текстуре — tools/
## make_video_grass.py — и живом слое колыхания city_view.gd).
## Крупноячеистый шум выделяет луга, на них по хэшу цветут 2–4 цветка
## (белый/жёлтый/розовый/василёк/мак) — поляны, а не рассыпанный горох.
const FLOWER_COLS := [
	Color("#f2f0e4"), Color("#e8d44d"), Color("#e88bb0"),
	Color("#8fb4e8"), Color("#d9584f"),
]


func _draw_grass_detail(x: int, y: int, rect: Rect2, ts: float) -> void:
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


## Травяная бахрома по кромкам воды и скальных гряд (v1.32, стиль видео):
## пары травинок на травяной стороне контура — берег «порастает» травой,
## граница читается мягкой, а не геометричной. Кэш контуров уже построен
## (_water_cached/_rock_cached), идём по точкам сглаженного контура.
func _draw_grass_fringe(ts: float) -> void:
	var dark: Color = colors.get("grass2", Color("#498938")).darkened(0.18)
	var light: Color = colors.get("grass", Color("#5ca046")).lightened(0.14)
	for entry in _water_cached:
		if String(entry["kind"]) == "swamp" or not bool(entry.get("simple", true)):
			continue
		_fringe_loop(entry["loop"], _poly_centroid(entry["loop"]), ts, dark, light)
	for entry in _rock_cached:
		# v1.34.1: у честно-тайловых скал (не заполнены) бахромы нет
		if not bool(entry.get("simple", true)):
			continue
		_fringe_loop(entry["loop"], _poly_centroid(entry["loop"]), ts, dark, light)


func _fringe_loop(loop: PackedVector2Array, centroid: Vector2, ts: float,
		dark: Color, light: Color) -> void:
	if loop.size() < 8:
		return
	# нормаль наружу = от центроида; точки контура плотные (4 subdivision
	# на ребро) — шаг 2 даёт травинку каждые ~4–5 px. Травинки тянутся
	# ВВЕРХ с наклоном наружу — силуэт берега «дышит» (v1.32: длиннее
	# и гуще первого варианта, иначе кромка читалась жёсткой)
	var i := 0
	for p in loop:
		if i % 2 != 0:
			i += 1
			continue
		i += 1
		var n := (p - centroid).normalized()
		if n == Vector2.ZERO:
			continue
		var base := p + n * (ts * 0.07)
		var ln := 4.5 + float(_hash(i, i * 7, 4))
		var lean := Vector2(n.x * 0.7, -1.0).normalized() * ln
		var col := dark if i % 4 < 2 else light
		_drawer.draw_line(base, base + lean, col, 1.4)
		if i % 6 == 0:
			var base2 := base + n * 2.5 + Vector2(2.5, 0)
			_drawer.draw_line(base2, base2 + lean * 0.85,
					light if col == dark else dark, 1.1)


## Вода v1.27.1 — ОРГАНИЧНЫЕ водоёмы (референс RimWorld/Dwarf Fortress):
## контур по marching squares, сглаженный Безье; заливка с глубиной,
## песчаная кромка-обводка, светлая линия уреза. Острова в воде и пруды
## на островах обрабатываются вложенностью контуров. Поверх — блики,
## кувшинки и камыши на берегу.
func _draw_water_blobs(ts: float) -> void:
	var shore_col: Color = colors.get("shore", Color("#d9c69b"))   # v1.31.1: белее
	# v1.28.1: контуры+триангуляция — из кэша (маска воды меняется только
	# со сменой сетки); пересчёт — по _blob_cache_dirty из rebake(heavy)
	if _blob_cache_dirty:
		_water_cached = []
		_water_covered = {}
		_water_tile_kind = {}
		var raw: Array = _mask_loops(func(t: Vector2i) -> bool:
			return map.grid[t.y][t.x] == map.TILE_WATER)
		raw.sort_custom(func(a, b) -> bool: return _loop_area(a) > _loop_area(b))
		var smootheds: Array = []
		for rl in raw:
			smootheds.append(_smooth_loop(rl))
		for ri in raw.size():
			var sm: PackedVector2Array = smootheds[ri]
			if not _loop_is_simple(sm):
				# v1.31.1: сглаживание сломало контур — берём СЫРОЙ контур
				# (он всегда простой; квадратные ступени гасит обводка песка)
				sm = raw[ri]
				smootheds[ri] = sm
			# v1.34.1: чистка контура — дубли и коллинеарные точки роняют
			# ear-clipping (Geometry2D.triangulate_polygon), заливка не
			# рисовалась и водоём оставался серой «сухой рекой» (скриншоты
			# приёмки v1.34.0). Чистый контур триангулируется почти всегда,
			# крайний случай — честные тайлы (simple=false ниже).
			var clean := _clean_loop(sm)
			if clean.size() >= 3:
				sm = clean
				smootheds[ri] = sm
			var tiles := _loop_tiles(sm, ts)
			# v1.29.1: тип водоёма считает КАРТА (он нужен и путям/броду);
			# локальный расчёт по силуэту — страховка для карт без неё
			var kind := ""
			if not tiles.is_empty():
				kind = map.water_kind_at(tiles[0])
			if kind == "":
				kind = _water_kind(sm, ts)
			for t: Vector2i in tiles:
				_water_tile_kind[t] = kind
			# v1.31.1: не-простой сглаженный контур заменён СЫРЫМ выше — здесь
			# контур всегда простой, гладкие края и обводки у каждого водоёма
			var tris: PackedInt32Array = Geometry2D.triangulate_polygon(sm)
			# v1.34.1: обрывки контуров (1 тайл) — не «болото», иначе топь
			# рисуется поверх реки; настоящие болота считает карта
			if kind == "swamp" and tiles.size() <= 1:
				kind = "lake"
			for t: Vector2i in tiles:
				_water_covered[t] = true
			_water_cached.append({"loop": sm,
					"tris": tris,
					"depth": _loop_depth(sm, smootheds),
					"kind": kind, "tiles": tiles,
					"simple": not tris.is_empty()})
		_rock_cached = _rock_view.build_cache()
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
			# остров: та же текстурная трава, что и на материке (v1.32),
			# откат — плоская _grass_at
			for t: Vector2i in entry["tiles"]:
				var gtex: Texture2D = _grass_texture_at(t.x, t.y)
				var grect := Rect2(Vector2(t) * ts, Vector2(ts, ts))
				if gtex != null:
					_drawer.draw_texture_rect(gtex, grect, false)
				else:
					_drawer.draw_rect(grect, _grass_at(t.x, t.y))
			_stroke_on_loop(loop, ts * 0.6, Color("#6d8a4e").darkened(0.05))
			continue
		# v1.34.2: тело водоёма рисует файл своего типа (мель/глубина)
		if kind == "river":
			_river_view.draw_body(entry, ts)
		else:
			_lake_view.draw_body(entry, ts)
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
	_river_view.draw_fords(ts)
	_swamp_view.draw_blobs(ts)
	# v1.34.1: гарантия заливки — узкие реки распадаются в marching
	# squares на вырожденные контуры (площадь 0), их тайлы не покрывал
	# ни один блоб и просвечивал серый фон («сухая река» на скриншотах
	# приёмки v1.34.0). Каждый незалитый тайл красим цветом его типа.
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] != map.TILE_WATER:
				continue
			var t := Vector2i(x, y)
			if _water_covered.has(t):
				continue
			var k := water_kind_at(t)
			var col := Color("#46523a") if k == "swamp" 					else (_water_river if k == "river" else _water_lake)
			_drawer.draw_rect(Rect2(Vector2(t) * ts, Vector2(ts, ts)), col)
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
				_river_view.draw_flow(x, y, rect, ts)
			else:
				_lake_view.draw_detail(x, y, rect, ts)
				if _water_deep(x, y) <= 2 and _hash(x, y, 17) == 0:
					_lake_view.draw_lilies(Vector2(x * ts, y * ts), ts, x, y)
				# v1.34: круги ряби на открытой воде — редкие статичные
				# двойные кольца (референс a602a024: кольца вокруг лилий)
				if _water_deep(x, y) >= 6 and _hash(x, y, 53) % 9 == 0:
					_lake_view.draw_ripple(Vector2(x * ts, y * ts), ts)
				# v1.34: камыши на мели — пучки торчат из воды у кромки
				if _water_deep(x, y) <= 2 and _hash(x * 7, y * 3, 61) % 4 == 0:
					_draw_water_reeds(Vector2(x * ts, y * ts), ts, x, y)
				# тина (v1.28): болотная плёнка на отмелях озёр
				if _water_deep(x, y) <= 1 and _hash(x * 3, y * 7, 29) % 3 == 0:
					_drawer.draw_circle(rect.position + Vector2(ts * 0.4, ts * 0.5),
							ts * 0.34, Color("#6b7d4f", 0.35))
					_drawer.draw_circle(rect.position + Vector2(ts * 0.65, ts * 0.35),
							ts * 0.22, Color("#7a8d55", 0.28))
	# вокруг БОЛОТ — тёмно-зелёная земля с камышами (v1.31.1, заказчик)
	for y in map.h:
		for x in map.w:
			var st := Vector2i(x, y)
			if map.grid[y][x] != map.TILE_GRASS or not _near_water(st):
				continue
			if _shore_kind(st) != "swamp":
				continue
			var srect := Rect2(Vector2(st) * ts, Vector2(ts, ts))
			_drawer.draw_rect(srect, Color("#3f4a33", 0.55))
			if _hash(x * 3, y * 5, 23) % 3 < 2:
				_draw_reeds(Vector2(st) * ts, ts, x, y)
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


## Камыши на мели (v1.34): пучок растёт ИЗ воды — тёмное основание-плёс,
## стебли чуть темче береговых. Рисуется поверх мель-пояса.
func _draw_water_reeds(origin: Vector2, ts: float, x: int, y: int) -> void:
	var base := origin + Vector2(ts * 0.5, ts * 0.72)
	_drawer.draw_circle(base, ts * 0.20, Color("#2c3f33", 0.55))
	_drawer.draw_circle(base + Vector2(2.0, 1.0), ts * 0.12, Color("#22322a", 0.45))
	_draw_reeds(origin + Vector2(0, ts * 0.18), ts * 1.05, x, y)


func _near_water(t: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = t + d
		if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER:
			return true
	return false


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
