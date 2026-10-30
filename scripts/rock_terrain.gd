extends RefCounted
## СКАЛЫ И РУДНЫЕ ЖИЛЫ — рендер и настройка (v1.34.2, выделено из
## city_terrain.gd; переработано v1.37.0 по поручению приёмки: «вот бы
## ещё скалы так» — гряды тем же языком ВЫСОТЫ, что и плато).
##
## Гряда читается приподнятым массивом (схема Hills, как plateau_terrain):
##   верхняя грань (свет с СЗ, заметно светлее) + редкая зелень сверху
##   → трёхтоновый СРЕЗ по южной дуге (свет-полоса / тело / тёмное основание)
##   → контактная тень и мягкая тень на траве у подножия.
## Фасеты и трещины добычи остались; руда — кристаллы с блеском.
##
## Тюнинг: data/city.json → colors → "water_tune" → "rocks":
##   color/tone_amp — базовый цвет породы (дышит по блобу)
##   top_light/top_shrink — верхняя грань (свет и сжатие контура)
##   cut_light/cut_dark/cut_h — срез (яркость полос и высота в тайлах)
##   shadow_alpha/shadow_off — тень у подножия
##   top_grass — шанс пучка травы на верхней грани («шапки» референсов)

var t   # city_terrain — контекст (drawer, map, цвета, геометрия блобов)


func setup(terrain: Node) -> void:
	t = terrain


func opt(key: String, def: float) -> float:
	return float(t.colors.get("water_tune", {}).get("rocks", {}).get(key, def))


func base_color() -> Color:
	return Color(String(t.colors.get("water_tune", {}).get("rocks", {}).get("color", "#857e71")))


func build_cache() -> Array:
	var raw_loops: Array = t._mask_loops(func(tk: Vector2i) -> bool:
		return t.map.grid[tk.y][tk.x] == t.map.TILE_ROCK or t.map.grid[tk.y][tk.x] == t.map.TILE_ORE)
	var out: Array = []
	for raw in raw_loops:
		var sm: PackedVector2Array = t._smooth_loop(raw)
		# v1.34.1: чистка контура — дубли и коллинеарные точки роняют ear-clipping
		var clean: PackedVector2Array = t._clean_loop(sm)
		var tris: PackedInt32Array = Geometry2D.triangulate_polygon(clean) \
				if clean.size() >= 3 else PackedInt32Array()
		if tris.is_empty():
			# крайний случай: честные квадратные тайлы скалы вместо дырки
			out.append({"loop": PackedVector2Array(), "tris": PackedInt32Array(),
					"tiles": t._loop_tiles(clean if clean.size() >= 3 else sm, t.map.ts),
					"simple": false})
			continue
		out.append({"loop": clean, "tris": tris, "tiles": [], "simple": true})
	return out


func draw_blobs(ts: float) -> void:
	for entry in t._rock_cached:
		if not bool(entry.get("simple", true)):
			# v1.34.1: триангуляция не удалась — честные квадратные тайлы
			for tk: Vector2i in entry["tiles"]:
				t._drawer.draw_rect(Rect2(Vector2(tk) * ts, Vector2(ts, ts)), base_color())
			continue
		var loop: PackedVector2Array = entry["loop"]
		var c: Vector2 = t._poly_centroid(loop)
		# тон дышит по блобу — массивы не одинаковые
		var tone: float = t._noise2(c.x / (ts * 3.0), c.y / (ts * 3.0), 30, 91) / 29.0
		var base := base_color().lightened(opt("tone_amp", 0.05) * tone - opt("tone_amp", 0.05) * 0.5)
		var area: float = t._loop_area(loop)
		if area <= 6.0 * ts * ts:
			# малый валун/руда (v1.37.1): тоже читается приподнятым —
			# мини-срез (2 тона) и тень, но без штрихов и зелени
			_foot_shadow(loop, c, ts)
			t._fill_loop_cached(loop, entry["tris"], base)
			_stroke_run(run_of(loop, c), 0.0, 2.0, base.darkened(opt("cut_dark", 0.30) + 0.10))
			_stroke_run(run_of(loop, c), ts * 0.08, ts * 0.16,
					base.darkened(opt("cut_dark", 0.30)))
			_stroke_run(run_of(loop, c), ts * 0.20, ts * 0.08,
					base.lightened(opt("cut_light", 0.14)))
			continue
		# 1) ТЕНЬ у подножия — ДО заливки: мягкие полосы на траве к югу
		_foot_shadow(loop, c, ts)
		# 2) тело массы — средний тон породы
		t._fill_loop_cached(loop, entry["tris"], base)
		# 3) ВЕРХНЯЯ ГРАНЬ: сжатый контур, поднятый к СЗ — свет ложится
		# сверху-слева, гряда читается объёмом (как вершины плато)
		var top: PackedVector2Array = t._shrunk_loop(loop, opt("top_shrink", 0.80))
		for i in top.size():
			top[i] += Vector2(-ts * 0.02, -ts * 0.07)
		t._fill_loop_cached(top, Geometry2D.triangulate_polygon(top),
				base.lightened(opt("top_light", 0.10)))
		# 4) СРЕЗ по южной дуге — трёхтоновая кромка обрыва (язык плато)
		_cut_rim(loop, c, ts, base)
		# восточное ребро — тонкая тёмная линия: объём против света с СЗ
		_edge_rim(loop, c, ts, base)
		# 5) фасеты: мягкие сколы на верхней грани (v1.29.4)
		var r_in := sqrt(area / PI) * 0.45
		var n := 3 + int(area / (26.0 * ts * ts))
		for f in mini(n, 5):
			var a0 := TAU * float(t._hash(f * 31, int(c.x), 100)) / 100.0
			var p0 := c + Vector2(cos(a0), sin(a0) * 0.75) * r_in
			var rr := sqrt(area / PI) * (0.22 + 0.1 * float(t._hash(f * 7, int(c.y), 100)) / 100.0)
			var fc := base.darkened(0.05) if f % 2 == 0 else base.lightened(0.05)
			t._draw_ellipse(p0, rr, rr * 0.72, Color(fc, 0.55))
		# 6) редкая зелень на верхней грани — «шапки» референсов скал
		_top_grass(top, ts)
	# трещины добычи и руда — по тайлам внутри массива
	for y in t.map.h:
		for x in t.map.w:
			var tk := Vector2i(x, y)
			var g: int = t.map.grid[y][x]
			if g != t.map.TILE_ROCK and g != t.map.TILE_ORE:
				continue
			draw_tile_detail(x, y, g == t.map.TILE_ORE, ts)


## Весь южный прогон одним куском (для малых масс — без дробления).
func run_of(loop: PackedVector2Array, c: Vector2) -> Array:
	var runs: Array = t.dir_runs(loop, c, Vector2(0, 1), 0.15, 3)
	if runs.is_empty():
		runs = t.dir_runs(loop, c, Vector2(0, -1), 0.15, 3)
	return runs[0] if not runs.is_empty() else []


## Прогоны контура — общая геометрия city_terrain.dir_runs (v1.37.1);
## здесь только тонкие обёртки под старые имена.
func _dir_runs(loop: PackedVector2Array, c: Vector2, dir_v: Vector2,
		dot_min: float, min_len: int) -> Array:
	return t.dir_runs(loop, c, dir_v, dot_min, min_len)


func _stroke_run(run: Array, off: float, width: float, col: Color) -> void:
	t.stroke_run(run, off, width, col)


func _stroke_run_off(run: Array, off: float, width: float, col: Color) -> void:
	t.stroke_run_out(run, off, width, col)


## Трёхтоновый СРЕЗ по южной дуге (снизу вверх от контура: контактное
## тёмное основание → тело породы → светлая полоса под верхней гранью) +
## короткие штрихи-напластования поперёк среза.
func _cut_rim(loop: PackedVector2Array, c: Vector2, ts: float, base: Color) -> void:
	var cut_h := ts * opt("cut_h", 0.34)
	for run in _dir_runs(loop, c, Vector2(0, 1), 0.30, 6):
		# контактная тень — по самому контуру
		_stroke_run(run, 0.0, 2.0, base.darkened(opt("cut_dark", 0.30) + 0.12))
		# тёмное основание среза
		_stroke_run(run, cut_h * 0.22, ts * 0.11, base.darkened(opt("cut_dark", 0.30)))
		# тело среза — основной тон
		_stroke_run(run, cut_h * 0.52, ts * 0.20, base)
		# светлая полоса у верхней грани (свет с СЗ ловит кромку)
		_stroke_run(run, cut_h * 0.88, ts * 0.09, base.lightened(opt("cut_light", 0.14)))
		# напластования: штрихи поперёк среза каждые ~0.55 тайла
		var acc := 0.0
		for i in run.size():
			var e: Array = run[i]
			var p: Vector2 = e[0]
			var nrm: Vector2 = e[1]
			if i > 0:
				acc += p.distance_to(run[i - 1][0])
			if acc < ts * 0.55:
				continue
			acc = 0.0
			var from := p - nrm * (cut_h * 0.10)
			var to := p - nrm * (cut_h * 0.80)
			t._drawer.draw_line(from, to, Color(base.darkened(0.24), 0.7), 1.4)


## Восточное ребро: тонкая тёмная линия — масса повёрнута к свету с СЗ.
func _edge_rim(loop: PackedVector2Array, c: Vector2, ts: float, base: Color) -> void:
	for run in _dir_runs(loop, c, Vector2(1, 0), 0.55, 5):
		_stroke_run(run, ts * 0.05, ts * 0.08, base.darkened(0.18))


## Мягкая тень на траве у подножия: полосы южнее контура с затуханием.
func _foot_shadow(loop: PackedVector2Array, c: Vector2, ts: float) -> void:
	var a0 := opt("shadow_alpha", 0.20)
	var off := ts * opt("shadow_off", 0.30)
	for run in _dir_runs(loop, c, Vector2(0, 1), 0.30, 6):
		_stroke_run_off(run, off, ts * 0.26, Color(0.05, 0.08, 0.05, a0))
		_stroke_run_off(run, off + ts * 0.24, ts * 0.22, Color(0.05, 0.08, 0.05, a0 * 0.45))


## Обводка прогона со смещением НАРУЖУ (тень ложится на траву за контуром)
## — общая city_terrain.stroke_run_out (v1.37.1, обёртка убрана).
## Тёмное подножие по нижней дуге: малые валуны (страховка).
func _stroke_bottom_rim(loop: PackedVector2Array, ts: float, base: Color) -> void:
	var c: Vector2 = t._poly_centroid(loop)
	for run in t.dir_runs(loop, c, Vector2(0, 1), 0.25, 4):
		t.stroke_run(run, 0.0, ts * 0.14, base.darkened(0.22))


## Редкие пучки травы на верхней грани («редкая зелень сверху» —
## референсы скал): по тайлям грани, шанс top_grass.
func _top_grass(top: PackedVector2Array, ts: float) -> void:
	var chance := opt("top_grass", 0.35)
	if chance <= 0.0:
		return
	var dark := Color("#4e7a36").darkened(0.15)
	var light := Color("#6f9a4c")
	for tk: Vector2i in t._loop_tiles(top, ts):
		var h: int = t._hash(tk.x * 5, tk.y * 3, 100)
		if float(h) >= chance * 100.0:
			continue
		var blades: Vector2 = t.map.tile_center_px(tk) + Vector2(
				float(t._hash(tk.x, tk.y, 7) - 3) * 1.6,
				float(t._hash(tk.y, tk.x, 5) - 3) * 1.2)
		for b in 2:
			var lean := Vector2(1.4 * (1 if b == 0 else -1), -4.5 - float(h % 3))
			t._drawer.draw_line(blades, blades + lean, dark if b == 0 else light, 1.3)


## Фактура тайла: трещины добычи (скала «оседает») и руда кристаллами.
func draw_tile_detail(x: int, y: int, ore: bool, ts: float) -> void:
	var rect := Rect2(Vector2(x * ts, y * ts), Vector2(ts, ts))
	var key := Vector2i(x, y)
	if t.map.rock_hp.has(key):
		var frac: float = clampf(float(t.map.rock_hp[key]) / maxf(1.0, t._rock_hp_default), 0.0, 1.0)
		if frac < 0.66:
			t._drawer.draw_line(rect.position + Vector2(ts * 0.3, ts * 0.35),
					rect.position + Vector2(ts * 0.5, ts * 0.7), Color(0.12, 0.11, 0.09, 0.85), 1.6)
		if frac < 0.33:
			t._drawer.draw_line(rect.position + Vector2(ts * 0.65, ts * 0.2),
					rect.position + Vector2(ts * 0.5, ts * 0.55), Color(0.12, 0.11, 0.09, 0.85), 1.4)
	if ore:
		# рудная жила: кристаллы-ромбики с блеском вместо точек-горошин
		var gold: bool = t._hash(x, y, 4) == 0
		var col := Color("#e0b13e") if gold else Color("#b0684a")
		for i in 3:
			var h2: int = t._hash(x * 13 + i, y * 17 + i, 100)
			var fx := rect.position.x + 6.0 + float(h2 % int(ts - 12.0))
			var fy := rect.position.y + 9.0 + float((h2 / 3) % int(ts - 16.0))
			t._draw_diamond(Vector2(fx, fy), 2.4 + float(h2 % 3), col)
			t._draw_diamond(Vector2(fx - 1.0, fy - 1.2), 1.1, col.lightened(0.4))
