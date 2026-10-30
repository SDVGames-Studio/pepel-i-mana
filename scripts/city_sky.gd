extends Node2D
## Солнечный цикл города (v1.27). Один скрипт — два слоя (поле mode):
##   "shadows" — мировые тени: от деревьев/зданий/скал, ползут с солнцем
##   (утром на запад, в полдень короткие, вечером на восток); в пасмурную
##   погоду свет рассеянный — тени бледнеют, по земле плывут тени облаков;
##   ночью — слабые лунные тени.
##   "sky" — небо поверх мира (CanvasLayer): солнце/луна/звёзды на экране,
##   свечение рассвета и заката; характер дня (ясный, облачный, туманный,
##   золотистый, розовый, хмурый) и палитра заката — детерминированы по дню.
## Чистые статические функции (фазы, палитры) вынесены для автотестов.

var mode := "shadows"
var map = null
var sim = null
var cfg: Dictionary = {}
var _time := 0.0

# --- характеры дня (детерминированы по номеру дня, погода сильнее) ---
const MOOD_CLEAR := 0
const MOOD_OVERCAST := 1
const MOOD_FOGGY := 2
const MOOD_GOLDEN := 3
const MOOD_ROSY := 4
const MOOD_GLOOMY := 5
# подброска: ясных дней больше (индекс в мешке 7 зёрен)
const MOOD_BAG := [0, 0, 1, 2, 3, 4, 5]
const MOOD_TINTS := [
	Color(1.0, 1.0, 1.0),        # ясный
	Color(0.92, 0.94, 0.99),     # облачный — ровный холодный свет
	Color(0.96, 0.95, 0.90),     # туманный — молочный
	Color(1.0, 0.93, 0.76),      # золотистый — тёплый весь день
	Color(1.0, 0.91, 0.88),      # розовый — мягкий
	Color(0.82, 0.84, 0.92),     # хмурый — низкое серое небо
]
const NIGHT_TINTS := [
	Color(0.30, 0.33, 0.52), Color(0.27, 0.29, 0.44), Color(0.30, 0.32, 0.47),
	Color(0.31, 0.32, 0.50), Color(0.31, 0.32, 0.50), Color(0.26, 0.27, 0.40),
]
# палитры закатов: алый, пурпурный, золотой, розовый, огненный, медный
const SUNSETS := [
	Color(1.0, 0.52, 0.38), Color(0.82, 0.55, 0.95), Color(1.0, 0.72, 0.38),
	Color(1.0, 0.62, 0.72), Color(1.0, 0.45, 0.25), Color(0.95, 0.60, 0.35),
]
# во сколько раз тени длиннее объекта: закат/рассвет против полудня
const SHADOW_LONG := 1.5
const SHADOW_NOON := 0.18

# --- кэш объектов для теней ---
var _objs_dirty := true
var _objs: Array = []            # [kind, pos/rect, h]
var _blds_count := -1
var _layer: CanvasLayer = null
var _painter: Node2D = null
# FPS-оптимизация (замер 2026-10-27: 130→40 FPS при краске каждый кадр):
# CanvasItem кэширует геометрию — солнце/тени ползут медленно, содержимое
# достаточно обновлять 12–15 раз в секунду, а не каждый кадр
const REDRAW_HZ := 12.0
const SKY_REDRAW_HZ := 15.0
var _redraw_accum := 0.0


func setup(city_map, city_sim, city_cfg: Dictionary) -> void:
	map = city_map
	sim = city_sim
	cfg = city_cfg
	if mode == "sky":
		_layer = CanvasLayer.new()
		_layer.layer = 1   # над миром, под HUD (он добавлен позже в дерево)
		_painter = Node2D.new()
		_layer.add_child(_painter)
		# рисование идёт в canvas painter'а — ему передаётся контекст
		_painter.draw.connect(_draw_sky_screen.bind(_painter))
		add_child(_layer)


func _process(delta: float) -> void:
	_time += delta
	_redraw_accum += delta
	if mode == "shadows":
		if sim != null and sim.buildings.size() != _blds_count:
			_objs_dirty = true
		# редрав по расписанию; перестройка кэша требует немедленного кадра
		if _objs_dirty or _redraw_accum >= 1.0 / REDRAW_HZ:
			_redraw_accum = 0.0
			queue_redraw()
	elif _painter != null:
		if _redraw_accum >= 1.0 / SKY_REDRAW_HZ:
			_redraw_accum = 0.0
			_painter.queue_redraw()


func rebuild() -> void:
	_objs_dirty = true


# ============================ ЧИСТАЯ МАТЕМАТИКА ============================

## Доля суток 0..1 (0 — рассвет, 1-nf — закат, дальше ночь).
static func day_frac(time: float, day_len: float) -> float:
	return fmod(maxf(time, 0.0), maxf(0.1, day_len)) / maxf(0.1, day_len)


static func is_daylight(t: float, nf: float) -> bool:
	return t < 1.0 - nf


## Доля прошедшего дня 0..1 внутри светлой части суток.
static func day_u(t: float, nf: float) -> float:
	return clampf(t / maxf(0.001, 1.0 - nf), 0.0, 1.0)


## Высота солнца над горизонтом 0..1 (1 — полдень).
static func sun_elev(t: float, nf: float) -> float:
	return sin(PI * day_u(t, nf))


## Знак направления теней по X: утром < 0 (солнце на востоке),
## вечером > 0 (солнце на западе). Ноль — полдень.
static func shadow_dir_x(t: float, nf: float) -> float:
	return -cos(PI * day_u(t, nf))


## Длина тени в долях высоты объекта: длинная по краям дня, короткая в полдень.
static func shadow_len(t: float, nf: float) -> float:
	return lerpf(SHADOW_LONG, SHADOW_NOON, sun_elev(t, nf))


## Смещение тени для объекта высотой h (лёгкий наклон к югу для читаемости).
## tilt — сезонный наклон дуги (заказчик 2026-10-27): весной/осенью солнце
## встаёт точно на востоке (tilt 0), летом — на северо-востоке (тени
## утром/вечером косые К ЮГУ), зимой — на юго-востоке (к северу).
static func shadow_offset(t: float, nf: float, h: float, tilt := 0.0) -> Vector2:
	return Vector2(shadow_dir_x(t, nf),
			0.30 * (1.0 - sun_elev(t, nf)) + tilt * absf(shadow_dir_x(t, nf))) \
			* shadow_len(t, nf) * h


## Сезонный наклон солнечной дуги: лето +0.45 (восход на СВ), зима -0.45
## (восход на ЮВ), весна/осень — 0 (равноденствие, точно на востоке).
static func season_tilt(season: String) -> float:
	match season:
		"summer":
			return 0.45
		"winter":
			return -0.45
		_:
			return 0.0


## Луна: направление и высота в ночной части суток (те же формулы по u_night).
static func moon_u(t: float, nf: float) -> float:
	return clampf((t - (1.0 - nf)) / maxf(0.001, nf), 0.0, 1.0)


## Характер дня: погода сильнее календаря; в ясную погоду — по дню.
static func mood_of(day: int, weather: String) -> int:
	match weather:
		"rain", "snow":
			return MOOD_OVERCAST
		"fog":
			return MOOD_FOGGY
		"ash_storm":
			return MOOD_GLOOMY
	var v := int((day * 73856093) ^ (31 * 19349663))
	return MOOD_BAG[absi(v) % MOOD_BAG.size()]


## Палитра заката этого дня (разные закаты — детерминированно).
static func sunset_color(day: int) -> Color:
	var v := int((day * 19349663) ^ (77 * 73856093))
	return SUNSETS[absi(v) % SUNSETS.size()]


## Амбиентный свет дня: характер дня + краска фазы (рассвет/золото/закат).
static func daylight_color(mood: int, t: float, nf: float, day: int) -> Color:
	var base: Color = MOOD_TINTS[clampi(mood, 0, MOOD_TINTS.size() - 1)]
	var u := day_u(t, nf)
	var phase := Color.WHITE
	var strength := 0.0
	if u < 0.16:
		# рассвет: тёплый розовый, тает к утру
		strength = 1.0 - u / 0.16
		phase = Color(1.0, 0.78, 0.66)
	elif u > 0.62:
		var w := (u - 0.62) / 0.38
		if w < 0.45:
			# золотой час
			strength = (w / 0.45) * 0.7
			phase = Color(1.0, 0.84, 0.58)
		else:
			# закат — цвет из палитры дня; верхняя сила ограничена, иначе
			# сцена темнеет и тени (суть эффекта) тонут в подкраске
			strength = 0.45 + 0.35 * (w - 0.45) / 0.55
			phase = sunset_color(day)
	var col := base.lerp(phase, clampf(strength, 0.0, 1.0) * 0.8)
	# смягчение к белому: день не должен «красить» всё слишком сильно
	return Color.WHITE.lerp(col, 0.75)


## Ночной амбиент по характеру дня (пасмурная ночь темнее и глухая).
static func night_color(mood: int) -> Color:
	return NIGHT_TINTS[clampi(mood, 0, NIGHT_TINTS.size() - 1)]


## Сила теней при данном характере дня: рассеянный свет почти не тенит.
static func shadow_alpha(mood: int) -> float:
	match mood:
		MOOD_CLEAR:
			return 0.24
		MOOD_GOLDEN:
			return 0.30
		MOOD_ROSY:
			return 0.20
		MOOD_FOGGY:
			return 0.10
		MOOD_OVERCAST:
			return 0.09
		_:
			return 0.08   # хмурый


# ============================ СЛОЙ ТЕНЕЙ ============================

func _draw() -> void:
	if mode != "shadows" or map == null or sim == null:
		return
	var day_len := float(cfg.get("day_length", 120.0))
	var nf := float(cfg.get("night_fraction", 0.3))
	var t := day_frac(sim.time, day_len)
	var mood := mood_of(sim.day_number(), String(sim.weather))
	var xf := get_viewport_transform()
	var vis := (xf.affine_inverse() * get_viewport_rect()).grow(float(map.ts) * 6.0)
	if _objs_dirty:
		_build_objs()
	var alpha := shadow_alpha(mood)
	var weather: String = String(sim.weather)
	if weather == "rain" or weather == "snow" or weather == "fog":
		alpha *= 0.4   # рассеянный свет — тени едва видны
	var col := Color(0.04, 0.04, 0.09, alpha)
	# тёплые тени золотого часа: тёмно-коричневые (светлые тонут в закатной
	# подкраске — проверено скриншотами 2026-10-27)
	var u := day_u(t, nf)
	if u > 0.62 or u < 0.16:
		col = Color(0.10, 0.05, 0.02, alpha)
	# сезонный наклон дуги (v1.28): лето — восход на СВ, зима — на ЮВ
	var tilt := season_tilt(String(sim.season()))
	if is_daylight(t, nf):
		# реалистичные тени облаков (v1.28): кляксы-скопления кружков, день
		_draw_cloud_shadows(t, nf, mood, vis, weather, tilt, false)
		_draw_object_shadows(t, nf, vis, col, false, tilt)
	else:
		# лунные тени: слабые, холодные; облака тоже дают ночные тени
		_draw_cloud_shadows(t, nf, mood, vis, weather, tilt, true)
		# v1.31.1: лунные тени ТЁМНЫЕ (бледно-голубые полигоны поверх ночного
		# мира читались белёсыми пятнами на воде и у зданий — заказчик)
		_draw_object_shadows(t, nf, vis, Color(0.02, 0.03, 0.06, 0.10), true)


## ---------- тени облаков (правки приёмки v1.29.1) ----------
## Облако — ОДНА мягкая масса: выпуклая оболочка скопления кружков заливается
## одним полигоном с единой альфой. Раньше 4–7 полупрозрачных кружков с
## ореолами накладывались друг на друга — пересветы наложений читались
## «кучей шариков», овечками/корабликами (замечание заказчика). Плывут на
## восток; ночью те же, но бледнее и синее. Туман и пепельная буря скрывают.

const CLOUD_MAX := 10

var _clouds: Array = []   # {hull: PackedVector2Array, y: float, speed: float, phase: float}


func _cloud_count(mood: int, weather: String, night: bool) -> int:
	if weather == "fog" or weather == "ash_storm":
		return 0
	if night:
		return 2 if mood == MOOD_CLEAR else 7
	match mood:
		MOOD_CLEAR:
			return 3
		MOOD_ROSY, MOOD_GOLDEN:
			return 4
		MOOD_OVERCAST:
			return 10 if (weather == "rain" or weather == "snow") else 8
		_:
			return 6   # хмурый


## Детерминированный хеш (как в city_terrain) — форма облаков стабильна.
static func _hash(x: int, y: int, n: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, n)


func _build_clouds() -> void:
	_clouds.clear()
	for i in CLOUD_MAX:
		var puffs: Array = []
		var n: int = 4 + _hash(i, 7, 4)   # 4..7 кружков в основе формы
		for p in n:
			var ang := TAU * float(_hash(i * 13 + p, 3, 100)) / 100.0
			var dist := 16.0 + 52.0 * float(_hash(i * 7 + p, 5, 100)) / 100.0
			puffs.append([Vector2(cos(ang) * dist * 1.6, sin(ang) * dist * 0.6),
					24.0 + 42.0 * float(_hash(i * 11 + p, 9, 100)) / 100.0])
		# единый силуэт: обводка кружков точками -> выпуклая оболочка
		var pts := PackedVector2Array()
		for puff in puffs:
			var c: Vector2 = puff[0]
			var r: float = puff[1]
			for k in 12:
				var a := TAU * float(k) / 12.0
				pts.append(c + Vector2(cos(a) * r, sin(a) * r))
		_clouds.append({
			"hull": Geometry2D.convex_hull(pts),
			"speed": 9.0 + 7.0 * float(i % 5),
			"y": (float(i) + 0.5) / float(CLOUD_MAX),
			"phase": float(i) * 3.7,
		})


func _draw_cloud_shadows(_t: float, _nf: float, mood: int, vis: Rect2,
		weather: String, _tilt: float, night: bool) -> void:
	var count := _cloud_count(mood, weather, night)
	if count <= 0:
		return
	if _clouds.is_empty():
		_build_clouds()
	var ts := float(map.ts)
	var span := Vector2(map.w * ts, map.h * ts)
	# плотность и цвет: тени и днём и ночью ТЁМНЫЕ (волна 6: бледно-голубые
	# ночные облака поверх затемнённого мира читались «вода белеет»);
	# ночью — слабее и холоднее
	var base_a := 0.13 if mood == MOOD_OVERCAST else 0.09
	if weather == "rain" or weather == "snow":
		base_a = 0.14
	var col := Color(0.10, 0.11, 0.16, base_a) if not night \
			else Color(0.03, 0.04, 0.08, base_a * 0.7)
	for i in count:
		var cl: Dictionary = _clouds[i]
		var hull: PackedVector2Array = cl["hull"]
		if hull.size() < 3:
			continue
		var cy := span.y * float(cl["y"]) + sin(_time * 0.03 + float(cl["phase"])) * 22.0
		var cx := fposmod(_time * float(cl["speed"]) + float(cl["phase"]) * 160.0,
				span.x + 500.0) - 250.0
		var off := Vector2(cx, cy)
		var bbox := Rect2(hull[0], Vector2.ZERO)
		for k in range(1, hull.size()):
			bbox = bbox.expand(hull[k])
		bbox.position += off
		if not vis.intersects(bbox.grow(4.0)):
			continue
		var shifted := hull.duplicate()
		for k in shifted.size():
			shifted[k] += off
		draw_colored_polygon(shifted, col)


func _build_objs() -> void:
	_objs_dirty = false
	_objs = []
	var ts := float(map.ts)
	var rock_cells := {}
	for y in map.h:
		for x in map.w:
			var g: int = map.grid[y][x]
			if g == map.TILE_TREE:
				var kind: int = map.tree_kind(Vector2i(x, y))
				var h := ts * (1.9 if kind == map.TREE_SMALL
						else (2.4 if kind == map.TREE_MEDIUM else 3.0))
				_objs.append([0, Vector2((x + 0.5) * ts, (y + 0.92) * ts), h])
			elif g == map.TILE_ROCK or g == map.TILE_ORE:
				# v1.31.1: рудная жила БЕЗ скал (кристаллы на земле) тень не
				# отбрасывает — «жилы по две тени» (заказчик)
				if g == map.TILE_ORE:
					var solo := true
					for d5 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var n5: Vector2i = Vector2i(x, y) + d5
						if map.in_bounds(n5) and int(map.grid[n5.y][n5.x]) == map.TILE_ROCK:
							solo = false
							break
					if solo:
						continue
				rock_cells[Vector2i(x, y)] = true
	# v1.29.1 (правки приёмки): скала — МАССИВ, тень у него одна. Раньше
	# каждый тайл отбрасывал свою — гряда «рассыпалась» на полосы.
	var seen := {}
	for c: Vector2i in rock_cells:
		if seen.has(c):
			continue
		var queue: Array = [c]
		seen[c] = true
		var mn: Vector2i = c
		var mx: Vector2i = c
		while not queue.is_empty():
			var t: Vector2i = queue.pop_back()
			mn = Vector2i(mini(mn.x, t.x), mini(mn.y, t.y))
			mx = Vector2i(maxi(mx.x, t.x), maxi(mx.y, t.y))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = t + d
				if rock_cells.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		var rect := Rect2(Vector2(mn) * ts, Vector2(mx - mn + Vector2i(1, 1)) * ts)
		# v1.29.4: высота массива — по его размеру (раньше была постоянной,
		# и тень большой гряды не соответствовала массе)
		_objs.append([2, rect, clampf(maxf(rect.size.x, rect.size.y) * 0.6,
				ts * 0.7, ts * 2.4)])
	_blds_count = sim.buildings.size()
	for b in sim.buildings:
		var bw := float(sim.bld_w(b))
		var rect := Rect2(Vector2(b["tile"]) * ts, Vector2(ts * bw, ts * bw))
		_objs.append([1, rect, ts * (0.9 if bool(b["done"]) else 0.45)])


func _draw_object_shadows(t: float, nf: float, vis: Rect2, col: Color,
		moon := false, tilt := 0.0) -> void:
	var ts := float(map.ts)
	for o in _objs:
		var kind: int = o[0]
		var h: float = o[2]
		if kind == 0:
			var base: Vector2 = o[1]
			if not vis.has_point(base):
				continue
			_draw_tree_shadow(base, h, t, nf, col, ts, moon, tilt)
		else:
			var rect: Rect2 = o[1]
			if not vis.intersects(rect.grow(h * SHADOW_LONG)):
				continue
			if kind == 2:
				_draw_rock_shadow(rect, h, t, nf, col, moon, tilt)
			else:
				_draw_box_shadow(rect, h, t, nf, col, moon, tilt)


## Тень дерева — вытянутый клин от основания в сторону от солнца.
## v1.29.4: клин начинается чуть ВНУТРИ ствола и шире у основания — раньше
## он отходил вниз-влево тонкой полосой и читался «оторванной» от дерева
## тенью (дерево «висит на блок выше тени»).
func _draw_tree_shadow(base: Vector2, h: float, t: float, nf: float,
		col: Color, ts: float, moon := false, tilt := 0.0) -> void:
	var off := shadow_offset(t, nf, h, tilt)
	if moon:
		# лунная тень короче и слабее — свет отражённый
		var un := moon_u(t, nf)
		off = Vector2(moon_dir_x_at(t, nf), 0.2) * lerpf(1.1, 0.25, sin(PI * un)) * h * 0.7
	if off.length() < 2.0:
		return
	off.y = maxf(off.y * 0.6, -h * 0.05)   # меньше «подползания» вниз
	var root := base + Vector2(0, -h * 0.12)   # старт от нижней части ствола
	var dirn := off.normalized()
	var perp := Vector2(-dirn.y, dirn.x)
	var w0 := ts * 0.42
	var w1 := ts * 0.12
	var pts := PackedVector2Array([
		root + perp * w0, root + off + perp * w1,
		root + off - perp * w1, root - perp * w0,
	])
	draw_colored_polygon(pts, col)


## Тень массива скал (v1.29.4): заливается ТОЛЬКО полоса ВНЕ контура массива.
## Раньше тень = смещённый прямоугольник целиком — при малом смещении он
## накрывал сам массив, и гряда темнела (тень «не соответствует поведению»).
## Г-образная полоса: боковая связка по X + нижняя по Y.
func _draw_rock_shadow(rect: Rect2, h: float, t: float, nf: float,
		col: Color, moon := false, tilt := 0.0) -> void:
	var off := shadow_offset(t, nf, h, tilt)
	if moon:
		var un := moon_u(t, nf)
		off = Vector2(moon_dir_x_at(t, nf), 0.2) * lerpf(1.1, 0.25, sin(PI * un)) * h * 0.7
	if off.length() < 2.0:
		return
	var tl := rect.position
	var tr := rect.position + Vector2(rect.size.x, 0)
	var bl := rect.position + Vector2(0, rect.size.y)
	var br := rect.end
	# вырожденные направления (почти горизонтальный свет off.y≈0/отрицательный
	# или свет строго сверху off.x≈0): L-фигура самопересекается и роняет
	# триангуляцию (шум в логе с v1.29.4) — честная выпуклая оболочка
	# «подошва + подошва со смещением»
	if off.y < 0.5 or absf(off.x) < 0.5:
		var hull := Geometry2D.convex_hull(PackedVector2Array([
			tl, tr, bl, br, tl + off, tr + off, bl + off, br + off]))
		if hull.size() >= 3:
			draw_colored_polygon(hull, col)
		return
	# ОДНА L-фигура (юг+бок единым полигоном): раньше два отдельных
	# четырёхугольника читались «двойной тенью» (v1.31.1, заказчик).
	# Ветка влево (v1.39.0): старый порядок вершин с диагональю tl→br
	# самопересекался (триангуляция падала каждый кадр) — зеркальный L.
	if off.x >= 0.0:
		draw_colored_polygon(PackedVector2Array([
			tr, br, bl, bl + Vector2(0, off.y), bl + off, br + off, tr + off]), col)
	else:
		draw_colored_polygon(PackedVector2Array([
			tr, br, br + Vector2(0, off.y), bl + off, tl + off,
			tl + Vector2(0, off.y), tl]), col)



## Тень прямоугольного объекта — выпуклая оболочка «подошва + подошва+смещение».
func _draw_box_shadow(rect: Rect2, h: float, t: float, nf: float,
		col: Color, moon := false, tilt := 0.0) -> void:
	var off := shadow_offset(t, nf, h, tilt)
	if moon:
		# лунная тень короче и слабее — свет отражённый
		var un := moon_u(t, nf)
		off = Vector2(moon_dir_x_at(t, nf), 0.2) * lerpf(1.1, 0.25, sin(PI * un)) * h * 0.7
	if off.length() < 2.0:
		return
	var tl := rect.position
	var tr := rect.position + Vector2(rect.size.x, 0)
	var bl := rect.position + Vector2(0, rect.size.y)
	var br := rect.end
	var pts := PackedVector2Array()
	if off.x >= 0.0:
		pts.append_array([tl, tr, tr + off, br + off, br, bl + off])
	else:
		pts.append_array([tr, tl, tl + off, bl + off, bl, br + off])
	draw_colored_polygon(pts, col)


# ============================ СЛОЙ НЕБА ============================

## Экранное небо: вызывается painter'ом внутри CanvasLayer (координаты экрана).
## v1.29.1 (правки приёмки): ореолы солнца и луны убраны — мягкие круги
## «висели» на экране (замечание заказчика). День/ночь читается амбиентом
## (CanvasModulate) и тенями; слой оставлен как точка подключения будущих
## небесных эффектов.
func _draw_sky_screen(cv: CanvasItem) -> void:
	if sim == null:
		return


static func moon_dir_x_at(t: float, nf: float) -> float:
	return -cos(PI * moon_u(t, nf))
