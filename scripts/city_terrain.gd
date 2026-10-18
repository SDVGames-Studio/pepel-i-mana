extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Статический слой города (M9/M10): ландшафт (трава/вода/скалы/руда/лес) не
## меняется в течение игры — рисуется один раз. M10: craftpix-деревья (4
## варианта), скалы (4 варианта), трава с травинками, вода с бликами, руда
## с золотыми/железными вкраплениями. Вариант по хэшу тайла — детерминированно.

var map = null
var colors: Dictionary = {}


func setup(city_map, city_cfg: Dictionary) -> void:
	map = city_map
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		colors[key] = Color(String(c[key]))
	queue_redraw()


## Детерминированный «шум» тайла: 0..n-1 (одинаков при каждой перерисовке).
static func _hash(x: int, y: int, n: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, n)


func _draw() -> void:
	if map == null:
		return
	var grass: Color = colors["grass"]
	var grass_alt: Color = colors["grass_alt"]
	var ts := float(map.ts)
	for y in map.h:
		for x in map.w:
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			var base := grass if (x + y) % 2 == 0 else grass_alt
			var bottom := Vector2(x * map.ts + map.ts / 2.0, y * map.ts + map.ts * 0.92)
			var cx: float = x * float(map.ts) + float(map.ts) / 2.0
			var cy: float = y * float(map.ts) + float(map.ts) / 2.0
			match tile:
				map.TILE_GRASS:
					draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
				map.TILE_WATER:
					draw_rect(rect, colors["water"])
					_draw_water_detail(x, y, rect, ts)
				map.TILE_ROCK:
					draw_rect(rect, base)
					_draw_shadow(bottom, ts * 0.55)
					Assets.draw_ref(self, "e:rock%d" % (1 + _hash(x, y, 4)), bottom, ts * 1.05)
				map.TILE_ORE:
					draw_rect(rect, base)
					_draw_shadow(bottom, ts * 0.55)
					Assets.draw_ref(self, "e:rock%d" % (1 + _hash(x, y, 4)), bottom, ts * 1.05)
					_draw_ore_flecks(cx, cy, ts, x, y)
				map.TILE_TREE:
					draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
					_draw_shadow(bottom + Vector2(0, 2), ts * 0.6)
					Assets.draw_ref(self, "e:tree%d" % (1 + _hash(x, y, 4)), bottom + Vector2(0, -2), ts * 1.9)


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


## Руда: вкрапления цвета металла поверх скалы (железо — рыжий, золото — тёплый).
func _draw_ore_flecks(cx: float, cy: float, ts: float, x: int, y: int) -> void:
	var gold := _hash(x, y, 4) == 0
	var col := Color("#e0b13e") if gold else Color("#b0684a")
	for i in 4:
		var h := _hash(x * 13 + i, y * 17 + i, 100)
		var fx := cx - ts * 0.28 + float(h % int(ts * 0.56))
		var fy := cy - ts * 0.2 + float((h / 3) % int(ts * 0.4))
		draw_circle(Vector2(fx, fy), 1.6 + float(h % 2), col)


func _draw_shadow(pos: Vector2, radius: float) -> void:
	draw_circle(pos, radius * 0.5, Color(0, 0, 0, 0.18))
