extends RefCounted
## ОЗЕРО — рендер и настройка (v1.34.2, выделено из city_terrain.gd).
## Правило заказчика: один тип воды — один файл, проще править и настраивать.
##
## Тюнинг: data/city.json → colors → "water_tune" → "lake":
##   shallow_light  — насколько светлый мель-пояс у берега (0…0.5)
##   shallow_width  — ширина мель-пояса в долях тайла (большие озёра)
##   shallow_small  — ширина мель-пояса у малых прудов
##   deep_alpha     — тёмная глубина, первый пояс (прозрачность 0…1)
##   deep_alpha2    — тёмная глубина, второй пояс (только большие озёра)
## Цвет воды — colors.water_lake, глубина — colors.water_deep (опционально).

var t   # city_terrain — контекст (drawer, map, цвета, геометрия блобов)


func setup(terrain: Node) -> void:
	t = terrain


func opt(key: String, def: float) -> float:
	return float(t.colors.get("water_tune", {}).get("lake", {}).get(key, def))


## Тело озера: заливка + мель-пояс + глубина (вызывается из прохода блобов).
func draw_body(entry: Dictionary, ts: float) -> void:
	var loop: PackedVector2Array = entry["loop"]
	var base: Color = t._water_lake
	t._fill_loop_cached(loop, entry["tris"], base)
	var deep: Color = t.colors.get("water_deep", t.colors["water"].darkened(0.28))
	var area: float = t._loop_area(loop)
	var w_sh := ts * opt("shallow_width", 0.45)
	var f_sh := 0.975
	if area < 12.0 * ts * ts:
		w_sh = ts * opt("shallow_small", 0.26)
		f_sh = 0.96
	t._stroke_inside(loop, f_sh, w_sh, Color(base.lightened(opt("shallow_light", 0.20)), 0.6))
	# глубина: у больших озёр двухтоновая впадина, малым прудам не идёт
	# (урок v1.27.1 — «ромб» на малом пятне)
	if area > 30.0 * ts * ts:
		t._stroke_inside(loop, 0.72, ts * 0.9, Color(deep, opt("deep_alpha", 0.35)))
		t._stroke_inside(loop, 0.45, ts * 0.7, Color(deep, opt("deep_alpha2", 0.45)))
	elif area > 18.0 * ts * ts:
		t._stroke_inside(loop, 0.60, ts * 0.8, Color(deep, opt("deep_alpha", 0.4)))


## Блики: светлые чёрточки по хэшу (прорежены, сплошной крап «шумел»).
func draw_detail(x: int, y: int, rect: Rect2, ts: float) -> void:
	if t._hash(x, y, 41) % 3 != 0:
		return
	var col: Color = t._water_lake.lightened(0.35)
	col.a = 0.4
	for i in 2:
		var h: int = t._hash(x * 5 + i, y * 11 + i, 100)
		var px := rect.position.x + 5.0 + float(h % int(ts - 14.0))
		var py := rect.position.y + 6.0 + float((h / 5) % int(ts - 12.0))
		t._drawer.draw_line(Vector2(px, py), Vector2(px + 4.0 + float(h % 4), py), col, 1.2)


## Кувшинки: кольцо ряби вокруг группы + пара листьев с выемкой и бликом.
func draw_lilies(origin: Vector2, ts: float, x: int, y: int) -> void:
	t._drawer.draw_arc(origin + Vector2(ts * 0.5, ts * 0.5), ts * 0.42,
			0.0, TAU, 14, Color(t._water_lake.lightened(0.30), 0.30), 1.2)
	for i in 2:
		var h: int = t._hash(x * 5 + i, y * 9 + i, 100)
		var c := origin + Vector2(6.0 + float(h % int(ts - 14.0)), 6.0 + float((h / 5) % int(ts - 14.0)))
		var r := 3.0 + float(h % 3)
		var col := Color("#4e7c3a").lightened(0.05 * float(i))
		t._drawer.draw_circle(c, r, col)
		t._drawer.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, col.lightened(0.25))
		t._drawer.draw_line(c, c + Vector2(r + 0.6, 0.6), t.colors["water"].lightened(0.08), 1.2)


## Круги ряби на стоячей воде: двойное статичное кольцо (референс a602a024).
func draw_ripple(origin: Vector2, ts: float) -> void:
	var c := origin + Vector2(ts * 0.5, ts * 0.5)
	t._drawer.draw_arc(c, ts * 0.30, 0.0, TAU, 12,
			Color(t._water_lake.lightened(0.28), 0.28), 1.1)
	t._drawer.draw_arc(c, ts * 0.44, 0.0, TAU, 16,
			Color(t._water_lake.lightened(0.22), 0.18), 1.0)
