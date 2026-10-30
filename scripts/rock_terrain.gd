extends RefCounted
## СКАЛЫ И РУДНЫЕ ЖИЛЫ — рендер и настройка (v1.34.2, выделено из
## city_terrain.gd). Тюнинг без кода.
##
## Тюнинг: data/city.json → colors → "water_tune" → "rocks":
##   color     — базовый цвет породы (тон дышит по блобу ±tone_amp)
##   tone_amp  — амплитуда дыхания тона между массивами
##   top_light — насколько светлее вершина (светлая грань сверху)
##   foot_dark — насколько темнее подножие (полоса по нижней дуге)
## Руда (TILE_ORE) рисуется кристаллами с блеском поверх породы.

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
		# v1.34.1: чистка контура — дубли/коллинеарные точки роняют ear-clipping
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
		# v1.29.4 «натуральная гора»: тон дышит по блобу, светлая грань
		# сверху, тёмное подножие полосой по нижней половине контура,
		# крупные фасеты вместо крапинок
		var tone: float = t._noise2(c.x / (ts * 3.0), c.y / (ts * 3.0), 30, 91) / 29.0
		var base := base_color().lightened(opt("tone_amp", 0.05) * tone - opt("tone_amp", 0.05) * 0.5)
		t._fill_loop_cached(loop, entry["tris"], base)
		var area: float = t._loop_area(loop)
		if area > 6.0 * ts * ts:
			var top: PackedVector2Array = t._shrunk_loop(loop, 0.80)
			for i in top.size():
				top[i] += Vector2(-ts * 0.03, -ts * 0.06)
			t._fill_loop_cached(top, Geometry2D.triangulate_polygon(top),
					base.lightened(opt("top_light", 0.08)))
			var foot: PackedVector2Array = t._shrunk_loop(loop, 0.80)
			for i in foot.size():
				foot[i] += Vector2(0, ts * 0.09)
			t._fill_loop_cached(foot, Geometry2D.triangulate_polygon(foot),
					base.darkened(opt("foot_dark", 0.10)))
			# фасеты: 3–5 мягких сколов ГЛУБОКО внутри силуэта (v1.29.4)
			var r_in := sqrt(area / PI) * 0.45
			var n := 3 + int(area / (26.0 * ts * ts))
			for f in mini(n, 5):
				var a0 := TAU * float(t._hash(f * 31, int(c.x), 100)) / 100.0
				var p0 := c + Vector2(cos(a0), sin(a0) * 0.75) * r_in
				var rr := sqrt(area / PI) * (0.22 + 0.1 * float(t._hash(f * 7, int(c.y), 100)) / 100.0)
				var fc := base.darkened(0.05) if f % 2 == 0 else base.lightened(0.05)
				t._draw_ellipse(p0, rr, rr * 0.72, Color(fc, 0.55))
			_stroke_bottom_rim(loop, ts, base)
	# трещины добычи и руда — по тайлам внутри массива
	for y in t.map.h:
		for x in t.map.w:
			var tk := Vector2i(x, y)
			var g: int = t.map.grid[y][x]
			if g != t.map.TILE_ROCK and g != t.map.TILE_ORE:
				continue
			draw_tile_detail(x, y, g == t.map.TILE_ORE, ts)


## Тёмное подножие по нижней дуге контура: сегменты с нормалью вниз.
func _stroke_bottom_rim(loop: PackedVector2Array, ts: float, base: Color) -> void:
	var cy: float = t._poly_centroid(loop).y
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
			t._stroke_on_loop(band, ts * 0.42, base.darkened(0.22))
			open = false
	if open and band.size() >= 3:
		t._stroke_on_loop(band, ts * 0.42, base.darkened(0.22))


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
