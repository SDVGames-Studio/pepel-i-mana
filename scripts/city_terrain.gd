# Часть: статический слой города — отрисовка тайлов в чанки, статический
# снимок и инкремент, маски-сглаживания. Корень цепочки.
extends "res://scripts/city_terrain_base.gd"

func _draw_chunkBrush(i: int) -> void:
	var b: Dictionary = _brushes[i]
	var cc := Vector2i(b.get("chunk", Vector2i(-1, -1)))
	if cc.x < 0:
		return
	_drawer = b["drawer"]
	var region := Rect2i(cc.x * CHUNK_TILES, cc.y * CHUNK_TILES, CHUNK_TILES, CHUNK_TILES)
	_draw_tiles(region)
	_drawer = _full_drawer


func _draw_tiles(region: Rect2i) -> void:
	if map == null:
		return
	_ensure_views()
	var ts := float(map.ts)
	var x0 := maxi(0, region.position.x)
	var y0 := maxi(0, region.position.y)
	var x1 := mini(map.w, region.end.x)
	var y1 := mini(map.h, region.end.y)
	# проход 1: земля (трава/осыпи) — вода и скалы рисуются поверх
	for y in range(y0, y1):
		for x in range(x0, x1):
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			match tile:
				map.TILE_GRASS, map.TILE_TREE:
					var tex: Texture2D = _grass_texture_at(x, y)
					if tex != null:
						_drawer.draw_texture_rect(tex, rect, false)
					else:
						_drawer.draw_rect(rect, _grass_at(x, y))
					# v1.50: декор луга — цветы полянами, камешки, кусты/валуны.
					# Запекается В ЧАНК (раньше — живой слой: тысячи команд
					# каждый кадр; теперь ноль, и декор есть и на карте ×4,
					# где запечка 8px/тайл прежде его вообще не тянула)
					if tile == map.TILE_GRASS:
						_draw_meadow_decor(x, y, rect)
				map.TILE_DEADROCK:
					_rock_view.draw_deadrock(x, y, rect, ts)
				map.TILE_RUIN:
					# v1.48: куча древних камней (руины городской карты) —
					# 3 «блока» детерминированно по хэшу тайла
					_drawer.draw_rect(rect, _rock_deep.darkened(0.1))
					var hh := x * 7 + y * 13
					for k in 3:
						var ox := float((hh + k * 11) % 10) - 5.0
						var oy := float((hh + k * 17) % 10) - 5.0
						var sz := 7.0 + float((hh + k * 5) % 6)
						_drawer.draw_rect(
								Rect2(rect.position + Vector2(6.0 + ox, 6.0 + oy), Vector2(sz, sz)),
								_rock_deep.lightened(0.12 if k % 2 == 0 else 0.0))
	# проход 2: скалы и жилы — «Природа 2.0» (v1.39.0): фактурные утёсы
	# с травяными шапками языком высот плато (rock_terrain.gd).
	# Вода в духовке НЕ рисуется: она живая (water_terrain.gd, город).
	_rebuild_rock_cache()
	_rock_view.draw_blobs(ts, region)
	# проход 4: плато и утёсы (v1.36) — верхние грани, срезы-кромки
	# по схеме Hills, лестницы-проходы и тени у подножия
	_plateau_view.draw_plateaus(ts, region)


## Надстройки (v1.28.1 — отдельный дешёвый слой): зоны, дороги, плиты
## площади. Меняются часто, но команд здесь сотни, а не тысячи.
func _draw_static_content() -> void:
	if map == null:
		return
	_draw_roads_baked()
	_draw_zones_baked()
	_draw_plaza_baked()


## Снять содержимое духовки №2 в историю (после полного бейка).
func _snapshot_static() -> void:
	if _vp2 == null or not is_inside_tree():
		return
	var img := _vp2.get_texture().get_image()
	if img != null:
		_static_img = img
		if _static_tex == null:
			_static_tex = ImageTexture.create_from_image(_static_img)
		else:
			_static_tex.update(_static_img)
		_static_full_bake = false


## Инкремент надстроек: пересчитать изменённые тайлы на CPU (мини-Image
## на клетку: фон прозрачен, сверху дорога/зона) и влить в историю.
## Полная перевыпечка больше не нужна — фризов в вебе нет.
func _static_increment(edits: Array) -> void:
	if _static_img == null:
		_static_full_bake = true
		return
	var ts := float(map.ts)
	var px := _bs
	for e in edits:
		var t: Vector2i = e
		var cell := Image.create(px, px, false, Image.FORMAT_RGBA8)
		cell.fill(Color(0, 0, 0, 0))
		_cell_static_into(cell, t, ts)
		_static_img.blit_rect(cell, Rect2i(Vector2i.ZERO, Vector2i(px, px)),
				Vector2i(t.x * px, t.y * px))
	if _static_tex == null:
		_static_tex = ImageTexture.create_from_image(_static_img)
	else:
		_static_tex.update(_static_img)


## Содержимое одной клетки надстроек (дорога/зона/площадь) в мини-Image.
## Пиксельные координаты масштабируются от тайла к px-клетке истории.
func _cell_static_into(cell: Image, t: Vector2i, ts: float) -> void:
	if map.road.has(t):
		var col: Color = colors.get("road", Color("#6e5f4a"))
		_cell_fill(cell, ts, t, Vector2.ZERO, Vector2(ts, ts), col)
		_cell_fill(cell, ts, t, Vector2(ts * 0.24, ts * 0.33), Vector2(3.5, 3.5), col.lightened(0.2))
		_cell_fill(cell, ts, t, Vector2(ts * 0.53, ts * 0.55), Vector2(2.8, 2.8), col.lightened(0.15))
	if sim != null:
		var fill_work: float = float(sim.cfg.get("zones", {}).get("fill_work", 4.0))
		for z in sim.zones:
			var cells: Array = z["cells"]
			var idx: int = cells.find(t)
			if idx < 0:
				continue
			var zc: Color = _zone_colors.get(String(z["type"]), Color(0.7, 0.7, 0.4))
			var filled: bool = float(z["progress"][idx]) >= fill_work
			_cell_fill(cell, ts, t, Vector2.ZERO, Vector2(ts, ts),
					Color(zc.r, zc.g, zc.b, 0.42 if filled else 0.32))
			break


## Заливка прямоугольника (координаты тайла) в мини-Image клетки истории.
func _cell_fill(cell: Image, ts: float, t: Vector2i, off: Vector2, sz: Vector2,
		col: Color) -> void:
	var s := float(_bs) / ts
	var r := Rect2i(Vector2((Vector2(t) * ts + off) * s), Vector2(sz * s))
	r = r.intersection(Rect2i(0, 0, _bs, _bs))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	cell.fill_rect(r, col)


## ---------- блобы: marching squares + сглаживание ----------

## Несглаженные замкнутые контуры маски тайлов (углы = центры тайлов).
## Контур идёт по серединам рёбер между «сухим» и «мокрым» тайлом.
## v1.50: необязательный регион (изначально вся карта) — кромки земляных
## пятен считаются ПО ЧАНКУ с запасом 2 тайла; маска — чистая функция
## координат, контуры на стыках чанков совпадают (швов нет).
func _mask_loops(is_set: Callable, from := Vector2i(-1, -1), to := Vector2i(-1, -1)) -> Array:
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
	var i0: int = from.x if from.x > -1 else -1
	var j0: int = from.y if from.y > -1 else -1
	var i1: int = to.x if to.x > -1 else int(map.w)
	var j1: int = to.y if to.y > -1 else int(map.h)
	for j in range(j0, j1):
		for i in range(i0, i1):
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
		_drawer2.draw_rect(rect, col)
		_drawer2.draw_circle(rect.position + Vector2(map.ts * 0.3, map.ts * 0.4), 2.0, col.lightened(0.2))
		_drawer2.draw_circle(rect.position + Vector2(map.ts * 0.65, map.ts * 0.65), 1.6, col.lightened(0.15))


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
			_drawer2.draw_rect(rect, Color(col.r, col.g, col.b, 0.42 if filled else 0.32))
			if String(z["type"]) == "field":
				for k: int in 3:
					var y: float = rect.position.y + map.ts * (0.25 + 0.25 * k)
					_drawer2.draw_line(Vector2(rect.position.x + 4, y),
							Vector2(rect.position.x + map.ts - 4, y),
							col.darkened(0.3 if filled else 0.15),
							1.5 if filled else 1.0)
				if filled:
					_drawer2.draw_rect(rect.grow(-2), col.darkened(0.15), false, 1.5)
			else:
				_drawer2.draw_circle(rect.position + Vector2(10, 20), 3.0, col.darkened(0.35))
				_drawer2.draw_circle(rect.position + Vector2(22, 12), 3.0, col.darkened(0.35))
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
			_drawer2.draw_line(e[0], e[1], wood, 2.5)
			_drawer2.draw_line(e[2], e[2] + Vector2(0, -8), dark, 2.5)
			_drawer2.draw_circle(e[2] + Vector2(0, -8), 1.6, dark)


## Каменные плиты площади 2×2 (правки v1.20, v1.22 в духовке). Пульс «места
## сбора» остался в живом слое.
func _draw_plaza_baked() -> void:
	if sim == null or sim.plaza == Vector2i(-1, -1):
		return
	var ts := float(map.ts)
	var origin := Vector2(sim.plaza) * ts
	var rect := Rect2(origin, Vector2(ts * 2.0, ts * 2.0))
	_drawer2.draw_rect(rect, Color("#9aa0a8"))
	for i in 4:
		var cx := origin.x + ts * (0.5 + float(i % 2))
		var cy := origin.y + ts * (0.5 + float(i / 2))
		_drawer2.draw_rect(Rect2(cx - ts * 0.42, cy - ts * 0.42, ts * 0.84, ts * 0.84), Color("#8a9098"))
	_drawer2.draw_rect(rect, Color("#5d6470"), false, 2.0)
	_drawer2.draw_circle(origin + Vector2(ts, ts), ts * 0.16, Color("#e8e2d0"))


## Детерминированный «шум» тайла: 0..n-1 (одинаков при каждой перерисовке).
static func _hash(x: int, y: int, n: int, salt: int = 0) -> int:
	var v := int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791))
	return absi(v) % maxi(1, n)


## Пустая порода выработанного массива — рисует rock_terrain.gd (v1.39.1:
## каменная текстура — «шапка снята, видно камень»).
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


## Текстура травяного тайла — как в принятой v1.32: семейство тонов
## (L/M/D) — крупный шум пятен луга, вариант внутри семейства — хэш тайла
## (соседние тайлы всегда разные, повтор 32px не ловится глазом).
func _grass_texture_at(x: int, y: int) -> Texture2D:
	if _grass_texs.is_empty():
		return null
	var fam := clampi(int(_noise2(x / 7.0, y / 7.0, 3, 11)), 0, 2)
	var v: int = _hash(x, y, 2)
	return _grass_texs[fam * 2 + v]


## ---------- декор луга и земляные проплешины (v1.50 «Живая земля») ----------

const FLOWER_COLS := [
	Color("#f2f0e4"), Color("#e8d44d"), Color("#e88bb0"),
	Color("#8fb4e8"), Color("#d9584f"),
]

var _prop_texs: Array = []   # кусты/валуны ForgottenMemories (кэш)


## Декор травяного тайла: цветы (поляны по крупному шуму + редкие одиночки),
## камешки и кусты/валуны у воды. Всё детерминировано хэшами — одинаково
## при каждой перевыпечке чанка. Детали масштаба 1px при запечке 8px/тайл.
func _draw_meadow_decor(x: int, y: int, rect: Rect2) -> void:
	var field := _noise2(x / 6.0, y / 6.0, 100, 71) / 99.0
	var blooms := 0
	if field > 0.62:
		blooms = 1 + _hash(x, y, 13) % 2   # сердцевина поляны цветёт гуще
	elif _hash(x * 5, y * 7, 300) == 0:
		blooms = 1   # редкий одиночный цветок
	var dot := 2.5 if _bs >= 32 else 1.2
	for i in blooms:
		var h2 := _hash(x * 17 + i, y * 19 + i, 100)
		var c := rect.position + Vector2(4.0 + float(h2 % 24), 4.0 + float((h2 / 7) % 24))
		var fcol: Color = FLOWER_COLS[_hash(x + i, y - i, FLOWER_COLS.size())]
		_drawer.draw_rect(Rect2(c, Vector2(dot, dot)), fcol)
		if dot >= 2.0:
			_drawer.draw_rect(Rect2(c + Vector2(0.8, 0.8), Vector2(1.0, 1.0)), Color("#e8c94d"))
	# камешек: редкий серый бугорок
	if _hash(x * 13, y * 3, 120) == 0:
		_drawer.draw_rect(Rect2(rect.position + Vector2(8.0 + float(_hash(x, y, 40) % 14), 9.0),
				Vector2(dot, dot)), Color("#9a958a"))
	# кусты/валуны ForgottenMemories: у воды 12%, на лугу 6%
	if _prop_texs.is_empty():
		for n in ["bush2_a", "bush2_b", "bush2_c", "bush2_d", "stone2_a", "stone2_b"]:
			_prop_texs.append(Assets.tex("res://assets/sprites/props/%s.png" % n))
	var near_water := false
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var p: Vector2i = Vector2i(x, y) + d
		if map.in_bounds(p) and map.grid[p.y][p.x] == map.TILE_WATER:
			near_water = true
			break
	if _hash(x * 17, y * 11, 1000) >= (120 if near_water else 60):
		return
	var tex: Texture2D = _prop_texs[_hash(x * 3, y * 5, _prop_texs.size())]
	if tex == null:
		return
	var ts := float(map.ts)
	var scale := (0.42 + 0.14 * float(_hash(x, y, 7))) * ts
	var s := scale / float(tex.get_height())
	var w := tex.get_width() * s
	var pos := rect.get_center() + Vector2(
			float(_hash(x * 5, y, 9) - 4) * ts * 0.02,
			float(_hash(x, y * 5, 9) - 4) * ts * 0.02)
	_drawer.draw_texture_rect(tex, Rect2(
			Vector2(pos.x - w * 0.5, pos.y - scale * 0.62), Vector2(w, scale)), false)


## ---------- земляные проплешины (v1.50 «Живая земля») -----------------------
## Маска — чистая функция (x, y) и типа тайла; кромки считаются ПО ЧАНКУ
## с запасом 2 тайла через _mask_loops (контуры совпадают на стыках),
## поверх — painterly-кольцо: тёмная «губа травы» снаружи, светлый
## срез земли внутри (приём «кромка в 2–3 тона», РЕФЕРЕНСЫ-СТИЛЬ).



## ---------- Природа 2.0 (v1.39.0) -------------------------------------------
## Вода — живой слой (water_terrain.gd, добавлен городом над ландшафтом);
## скалы/жилы — rock_terrain.gd (проход 3 духовки). Цветы/кусты/камешки
## луга — живой декор city_view.gd (v1.50; запечка на больших картах 8px
## их не тянет). Здесь ромб-кристалл руды (общая утилита).



## Ромб-кристалл (руда) с центром center и полудиагональю r.
func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	if r < 0.8:
		return
	_drawer.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r * 0.7, 0),
		center + Vector2(0, r), center + Vector2(-r * 0.7, 0),
	]), col)
