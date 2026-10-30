extends RefCounted
## РЕКА — рендер и настройка (v1.34.2, выделено из city_terrain.gd).
## Один тип воды — один файл (правило заказчика), тюнинг без кода.
##
## Тюнинг: data/city.json → colors → "water_tune" → "river":
##   shallow_light — насколько светлый мель-пояс у берега (0…0.5)
##   shallow_width — ширина мель-пояса в долях тайла
##   core_alpha    — тёмная сердцевина течения (прозрачность 0…1)
##   flow_chance   — густота струй течения (2 = каждый второй тайл)
## Цвет воды — colors.water_river.

var t   # city_terrain — контекст (drawer, map, цвета, геометрия блобов)


func setup(terrain: Node) -> void:
	t = terrain


func opt(key: String, def: float) -> float:
	return float(t.colors.get("water_tune", {}).get("river", {}).get(key, def))


## Тело реки: заливка + мель-пояс + тёмная сердцевина течения.
func draw_body(entry: Dictionary, ts: float) -> void:
	var loop: PackedVector2Array = entry["loop"]
	var base: Color = t._water_river
	t._fill_loop_cached(loop, entry["tris"], base)
	var deep: Color = t.colors.get("water_deep", t.colors["water"].darkened(0.28))
	var area: float = t._loop_area(loop)
	var w_sh := ts * opt("shallow_width", 0.45)
	var f_sh := 0.975
	if area < 12.0 * ts * ts:
		w_sh = ts * 0.26
		f_sh = 0.96
	t._stroke_inside(loop, f_sh, w_sh, Color(base.lightened(opt("shallow_light", 0.20)), 0.6))
	# сердцевина: течение глубже посередине (только широкие реки)
	if area > 14.0 * ts * ts:
		t._stroke_inside(loop, 0.55, ts * 0.5, Color(deep, opt("core_alpha", 0.30)))


## Течение: направленные струи вдоль русла (река течёт по Y, меандр по X).
## Никаких кувшинок — вода бежит.
func draw_flow(x: int, y: int, rect: Rect2, ts: float) -> void:
	if t._hash(x, y, 41) % int(opt("flow_chance", 2)) != 0:
		return
	var col: Color = t._water_river.lightened(0.45)
	col.a = 0.5
	for i in 2:
		var h: int = t._hash(x * 5 + i, y * 11 + i, 100)
		var px := rect.position.x + 5.0 + float(h % int(ts - 14.0))
		var py := rect.position.y + 4.0 + float((h / 5) % int(ts - 16.0))
		var ln := ts * (0.3 + 0.06 * float(h % 3))
		t._drawer.draw_line(Vector2(px, py), Vector2(px, py + ln), col, 1.3)
		t._drawer.draw_line(Vector2(px, py + ln), Vector2(px, py + ln + 3.0),
				Color(col.r, col.g, col.b, col.a * 0.5), 1.0)


## Мелководье-брод (v1.31): светлая вода, видно песчаное дно и камешки,
## рябь по краям. Читается проходом.
func draw_fords(ts: float) -> void:
	for t2: Vector2i in t.map.fords:
		if not t.map.in_bounds(t2) or t.map.grid[t2.y][t2.x] != t.map.TILE_WATER:
			continue
		var rect := Rect2(Vector2(t2) * ts, Vector2(ts, ts))
		var shallow: Color = t._water_river.lightened(0.34)
		t._drawer.draw_rect(rect, shallow)
		# песчаное дно проступает сквозь воду
		var h1: int = t._hash(t2.x, t2.y, 77)
		for i in 3:
			var h2: int = t._hash(t2.x * 11 + i, t2.y * 7 + i, 100)
			var c := rect.position + Vector2(4.0 + float(h2 % int(ts - 8.0)),
					4.0 + float((h2 / 7) % int(ts - 8.0)))
			t._drawer.draw_circle(c, 2.0 + float(h2 % 2), Color("#c8b183", 0.65))
		# рябь по углам и камешки-ориентиры
		t._drawer.draw_arc(rect.position + Vector2(ts * 0.3, ts * 0.3), ts * 0.18,
				0.0, PI, 8, Color(1.0, 1.0, 0.9, 0.5), 1.0)
		t._drawer.draw_arc(rect.position + Vector2(ts * 0.7, ts * 0.62), ts * 0.16,
				PI, TAU, 8, Color(1.0, 1.0, 0.9, 0.5), 1.0)
		if h1 % 2 == 0:
			t._drawer.draw_circle(rect.get_center() + Vector2(-3.0, 2.0), 1.6, Color("#8a8478"))
			t._drawer.draw_circle(rect.get_center() + Vector2(4.0, -2.0), 1.2, Color("#9a958a"))
