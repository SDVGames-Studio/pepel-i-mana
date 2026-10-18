extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Статический слой города (M9/M10, переработан в M11): ландшафт не меняется
## в течение игры — рисуется один раз (перерисовка — по флагу sim.terrain_dirty).
##
## M11 по замечаниям заказчика:
##  - земля без «шахматного порядка»: плавные пятна травы (шум крупными
##    блоками) плюс мелкое зерно яркости на каждом тайле;
##  - скалы — ЕДИНАЯ гряда: тёмное основание связывает тайлы в массив,
##    внутренние тайлы крупнее и темнее, края светлее; трещины по мере выработки;
##  - деревья с явным стволом (свои спрайты tree_oak/pine/birch/autumn/fruit2/old),
##    пни на месте срубленных, саженцы двух стадий.

var map = null
var colors: Dictionary = {}
var _grass_shades: Array = []
var _rock_deep := Color("#565248")
var _rock_hp_default := 80.0


func setup(city_map, city_cfg: Dictionary) -> void:
	map = city_map
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		colors[key] = Color(String(c[key]))
	_grass_shades = [colors["grass"], colors.get("grass_alt", colors["grass"]),
			colors.get("grass2", colors["grass"]).darkened(0.03)]
	_rock_deep = colors.get("rock_deep", Color("#565248"))
	_rock_hp_default = float(city_cfg.get("mountain", {}).get("hp", 80.0))
	queue_redraw()


## Детерминированный «шум» тайла: 0..n-1 (одинаков при каждой перерисовке).
static func _hash(x: int, y: int, n: int, salt: int = 0) -> int:
	var v := int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791))
	return absi(v) % maxi(1, n)


func _draw() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	# M12: деревья/пни/саженцы переехали в общий Y-сортированный слой
	# (city_view._draw_world_sorted) — здесь только земля, вода и скалы
	for y in map.h:
		for x in map.w:
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			var base := _grass_at(x, y)
			match tile:
				map.TILE_GRASS, map.TILE_TREE:
					draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
				map.TILE_WATER:
					draw_rect(rect, colors["water"])
					_draw_water_detail(x, y, rect, ts)
				map.TILE_ROCK, map.TILE_ORE:
					draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
					_draw_rock(x, y, tile == map.TILE_ORE, ts)


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


## Травинки: 3 короткие штриха темнее/светлее по хэшу — земля не «пластмассит».
func _draw_grass_detail(x: int, y: int, rect: Rect2, base: Color, ts: float) -> void:
	var dark := base.darkened(0.14)
	var light := base.lightened(0.08)
	for i in 3:
		var h := _hash(x * 3 + i, y * 7 + i, 100)
		var px := rect.position.x + 4.0 + float(h % int(ts - 8.0))
		var py := rect.position.y + 5.0 + float((h / 7) % int(ts - 10.0))
		var col := dark if i % 2 == 0 else light
		draw_line(Vector2(px, py), Vector2(px + 1.0, py - 3.0 - float(h % 3)), col, 1.0)


## Блики воды: пара светлых чёрточек по хэшу.
func _draw_water_detail(x: int, y: int, rect: Rect2, ts: float) -> void:
	var col: Color = colors.get("water", Color("#2e5f7a"))
	col = col.lightened(0.35)
	col.a = 0.4
	for i in 2:
		var h := _hash(x * 5 + i, y * 11 + i, 100)
		var px := rect.position.x + 5.0 + float(h % int(ts - 14.0))
		var py := rect.position.y + 6.0 + float((h / 5) % int(ts - 12.0))
		draw_line(Vector2(px, py), Vector2(px + 4.0 + float(h % 4), py), col, 1.2)


## Сколько соседей — скала (для формы гряды: внутренние тайлы темнее и крупнее).
func _rock_neighbors(x: int, y: int) -> int:
	var n := 0
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var t: Vector2i = Vector2i(x, y) + d
		if map.in_bounds(t) and (map.grid[t.y][t.x] == map.TILE_ROCK or map.grid[t.y][t.x] == map.TILE_ORE):
			n += 1
	return n


## Единая скальная гряда (M11): сплошное тело без щелей — серые плиты с
## травяной бровкой по верхней кромке, тёмной передней стенкой по нижней,
## лёгким рельефом и трещинами по мере добычи. Читается одним массивом.
func _draw_rock(x: int, y: int, ore: bool, ts: float) -> void:
	var key := Vector2i(x, y)
	var rect := Rect2(Vector2(x * ts, y * ts), Vector2(ts, ts))
	var inner_top := _rock_at(x, y - 1)
	var inner_bottom := _rock_at(x, y + 1)
	var inner_left := _rock_at(x - 1, y)
	var inner_right := _rock_at(x + 1, y)
	# базовый тон плиты с лёгкой вариацией по тайлу
	var base := Color("#716c60").lightened(0.02 * float(_hash(x, y, 5) - 2))
	draw_rect(rect, base)
	# рельеф: светлое пятно сверху и пара тёмных сколов по хэшу
	var hx := _hash(x, y, 30)
	var hy := _hash(y * 7, x * 3, 30)
	_draw_ellipse(rect.position + Vector2(10.0 + float(hx % 12), 9.0 + float(hy % 8)),
			8.0 + float(hx % 6), 5.0 + float(hy % 3), base.lightened(0.04))
	draw_line(rect.position + Vector2(4.0 + float(hy % 10), 14.0 + float(hx % 12)),
			rect.position + Vector2(12.0 + float(hx % 14), 22.0 + float(hy % 6)),
			base.darkened(0.12), 2.0)
	# верхняя кромка: травяная бровка и тень под ней (гряда лежит на земле)
	if not inner_top:
		draw_rect(Rect2(rect.position, Vector2(ts, 6.0)), _grass_shades[0].darkened(0.1))
		draw_rect(Rect2(rect.position + Vector2(0, 6.0), Vector2(ts, 3.0)), base.lightened(0.12))
	# нижняя кромка: передняя стенка обрыва с трещинами
	if not inner_bottom:
		var face := Rect2(rect.position + Vector2(0, ts - 10.0), Vector2(ts, 10.0))
		draw_rect(face, Color("#454137"))
		for i in 3:
			var cxp := rect.position.x + 4.0 + float((_hash(x * 5 + i, y, 20) % int(ts - 8.0)))
			draw_line(Vector2(cxp, face.position.y + 2.0), Vector2(cxp + 1.5, face.position.y + 9.0),
					Color(0.1, 0.09, 0.07, 0.8), 1.4)
	# боковые кромки
	if not inner_left:
		draw_rect(Rect2(rect.position, Vector2(2.5, ts)), Color("#565248"))
	if not inner_right:
		draw_rect(Rect2(rect.position + Vector2(ts - 2.5, 0), Vector2(2.5, ts)), Color("#565248"))
	# трещины по мере добычи: скала «оседает»
	if map.rock_hp.has(key):
		var frac: float = clampf(float(map.rock_hp[key]) / maxf(1.0, _rock_hp_default), 0.0, 1.0)
		if frac < 0.66:
			draw_line(rect.position + Vector2(ts * 0.3, ts * 0.35),
					rect.position + Vector2(ts * 0.5, ts * 0.7), Color(0.12, 0.11, 0.09, 0.85), 1.6)
		if frac < 0.33:
			draw_line(rect.position + Vector2(ts * 0.65, ts * 0.2),
					rect.position + Vector2(ts * 0.5, ts * 0.55), Color(0.12, 0.11, 0.09, 0.85), 1.4)
	# руда: золотые или рыжие вкрапления
	if ore:
		var gold := _hash(x, y, 4) == 0
		var col := Color("#e0b13e") if gold else Color("#b0684a")
		for i in 4:
			var h2 := _hash(x * 13 + i, y * 17 + i, 100)
			var fx := rect.position.x + 5.0 + float(h2 % int(ts - 10.0))
			var fy := rect.position.y + 10.0 + float((h2 / 3) % int(ts - 16.0))
			draw_circle(Vector2(fx, fy), 1.6 + float(h2 % 2), col)


## Заполненный эллипс полигоном (для глыб гряды).
func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.5 or ry <= 0.5:
		return
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _rock_at(x: int, y: int) -> bool:
	return map.in_bounds(Vector2i(x, y)) \
			and (map.grid[y][x] == map.TILE_ROCK or map.grid[y][x] == map.TILE_ORE)
