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
var _blob_cache_ver := -1     # v1.38.0: кэши блобов воды/скал удалены вместе
var _blob_cache_dirty := true  # с их рендером; версия сетки осталась для
                               # перевыпечки при изменениях рельефа


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
## v1.38.0 (поручение заказчика): код отрисовки скал/жил и водоёмов
## (rock_terrain.gd, water_lake/river/swamp.gd, блобы-«органика»,
## кромки, ряби, камыши) УДАЛЕН ПОЛНОСТЬЮ — вода и скалы рисуются
## плоской заливкой по типу. Переделка визуала природы с нуля —
## этап «Природа 2.0» (следующий чат).
var _plateau_view = null # plateau_terrain.gd — рендер плато и утёсов (v1.36)


func _ensure_views() -> void:
	if _plateau_view == null:
		_plateau_view = load("res://scripts/plateau_terrain.gd").new()
		_plateau_view.setup(self)


func _draw_tiles() -> void:
	if map == null:
		return
	_ensure_views()
	var ts := float(map.ts)
	# проход 1: земля (трава/осыпи) — вода и скалы рисуются поверх
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
	# проход 2: вода и скалы — плоская заливка по типу (v1.38.0)
	_draw_water_flat(ts)
	_draw_rocks_flat(ts)
	# проход 3: плато и утёсы (v1.36) — верхние грани, срезы-кромки
	# по схеме Hills, лестницы-проходы и тени у подножия
	_plateau_view.draw_plateaus(ts)


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

## ---------- вода и скалы: плоская заливка (v1.38.0) --------------------------
## Поручение заказчика 2026-10-30: код отрисовки скал/жил и водоёмов удалён
## полностью (блобы, кромки, ряби, камыши, глубины). Вода и скалы — плоские
## тайлы по типу; полный передел визуала природы — этап «Природа 2.0».


## Вода: плоский цвет по типу водоёма (озеро/река/болото), брод — светлее
## с песчаным дном (игровой ориентир переправы).
func _draw_water_flat(ts: float) -> void:
	var swamp := Color(String(colors.get("water_tune", {}).get("swamp", {})
			.get("color", "#46523a")))
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] != map.TILE_WATER:
				continue
			var t := Vector2i(x, y)
			var rect := Rect2(Vector2(t) * ts, Vector2(ts, ts))
			var kind: String = map.water_kind_at(t)
			var col := _water_river if kind == "river" else (_water_lake if kind == "lake" else swamp)
			_drawer.draw_rect(rect, col)
			if map.fords.has(t):
				_drawer.draw_rect(rect, col.lightened(0.32))
				for i in 3:
					var h: int = _hash(t.x * 11 + i, t.y * 7 + i, 100)
					var c := rect.position + Vector2(4.0 + float(h % int(ts - 8.0)),
							4.0 + float((h / 7) % int(ts - 8.0)))
					_drawer.draw_circle(c, 2.0 + float(h % 2), Color("#c8b183", 0.65))


## Скалы и руда: плоский камень; руда — кристалльные точки (видно, куда
## ставить шахту); трещины по мере выработки остаются (информация добычи).
func _draw_rocks_flat(ts: float) -> void:
	var base := Color(String(colors.get("water_tune", {}).get("rocks", {})
			.get("color", "#857e71")))
	var hp_max := _rock_hp_default
	for y in map.h:
		for x in map.w:
			var g: int = map.grid[y][x]
			if g != map.TILE_ROCK and g != map.TILE_ORE:
				continue
			var t := Vector2i(x, y)
			var rect := Rect2(Vector2(t) * ts, Vector2(ts, ts))
			_drawer.draw_rect(rect, base if g == map.TILE_ROCK else base.darkened(0.08))
			if g == map.TILE_ORE:
				var gold: bool = _hash(x, y, 4) == 0
				var col := Color("#e0b13e") if gold else Color("#b0684a")
				for i in 3:
					var h: int = _hash(x * 13 + i, y * 17 + i, 100)
					var fx := rect.position.x + 6.0 + float(h % int(ts - 12.0))
					var fy := rect.position.y + 9.0 + float((h / 3) % int(ts - 16.0))
					_draw_diamond(Vector2(fx, fy), 2.4 + float(h % 3), col)
					_draw_diamond(Vector2(fx - 1.0, fy - 1.2), 1.1, col.lightened(0.4))
			elif map.rock_hp.has(t):
				var frac: float = clampf(float(map.rock_hp[t]) / maxf(1.0, hp_max), 0.0, 1.0)
				if frac < 0.66:
					_drawer.draw_line(rect.position + Vector2(ts * 0.3, ts * 0.35),
							rect.position + Vector2(ts * 0.5, ts * 0.7), Color(0.12, 0.11, 0.09, 0.85), 1.6)
				if frac < 0.33:
					_drawer.draw_line(rect.position + Vector2(ts * 0.65, ts * 0.2),
							rect.position + Vector2(ts * 0.5, ts * 0.55), Color(0.12, 0.11, 0.09, 0.85), 1.4)

## Ромб-кристалл (руда) с центром center и полудиагональю r.
func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	if r < 0.8:
		return
	_drawer.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r * 0.7, 0),
		center + Vector2(0, r), center + Vector2(-r * 0.7, 0),
	]), col)
