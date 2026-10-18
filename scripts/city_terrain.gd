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
const TREE_REFS := ["e:tree_oak", "e:tree_pine", "e:tree_birch", "e:tree_autumn",
		"e:tree_oak", "e:tree_pine", "e:tree_fruit2", "e:tree_birch"]


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
static func _hash(x: int, y: int, n: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, n)


func _draw() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	for y in map.h:
		for x in map.w:
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			var base := _grass_at(x, y)
			var bottom := Vector2(x * map.ts + map.ts / 2.0, y * map.ts + map.ts * 0.92)
			var cx: float = x * float(map.ts) + float(map.ts) / 2.0
			var cy: float = y * float(map.ts) + float(map.ts) / 2.0
			match tile:
				map.TILE_GRASS:
					draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
					if map.stumps.has(Vector2i(x, y)):
						_draw_shadow(bottom, ts * 0.3)
						Assets.draw_ref(self, "e:stump", bottom, ts * 0.8)
				map.TILE_WATER:
					draw_rect(rect, colors["water"])
					_draw_water_detail(x, y, rect, ts)
				map.TILE_ROCK, map.TILE_ORE:
					draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
					_draw_rock(x, y, tile == map.TILE_ORE, ts)
					if tile == map.TILE_ORE:
						_draw_ore_flecks(cx, cy, ts, x, y)
				map.TILE_TREE:
					draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
					var key := Vector2i(x, y)
					if map.saplings.has(key):
						_draw_sapling(key, bottom, ts)
					else:
						_draw_shadow(bottom + Vector2(0, 2), ts * 0.6)
						Assets.draw_ref(self, TREE_REFS[_hash(x, y, TREE_REFS.size())],
								bottom + Vector2(0, -2), ts * 2.6)


## Трава: плавные пятна (шум блоками 5x5) + зерно яркости тайла — без шахматки.
func _grass_at(x: int, y: int) -> Color:
	var shade: Color = _grass_shades[_hash(int(x / 5.0), int(y / 5.0), _grass_shades.size())]
	var j := _hash(x, y, 9) - 4   # -4..4
	if j > 0:
		return shade.lightened(0.008 * j)
	return shade.darkened(0.008 * -j)


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


## Единая скальная гряда (M11): тёмная подошва связывает тайлы, внутренние
## тайлы — крупные тёмные глыбы, крайние — светлые камни; при выработке — трещины.
func _draw_rock(x: int, y: int, ore: bool, ts: float) -> void:
	var key := Vector2i(x, y)
	var nb := _rock_neighbors(x, y)
	var rect := Rect2(Vector2(x * map.ts, y * map.ts), Vector2(ts, ts))
	var inner := nb >= 5
	# подошва массива: тянется к соседям, гряда читается одним куском
	var pad := 6.0 if inner else 3.0
	var l := pad if _rock_at(x - 1, y) else 1.0
	var t := pad if _rock_at(x, y - 1) else 1.0
	var r := pad if _rock_at(x + 1, y) else 1.0
	var b := pad if _rock_at(x, y + 1) else 1.0
	var grown := Rect2(rect.position - Vector2(l, t), rect.size + Vector2(l + r, t + b))
	draw_rect(grown, _rock_deep)
	var bottom := rect.get_center() + Vector2(0, ts * 0.42)
	_draw_shadow(bottom, ts * (0.62 if inner else 0.55))
	if inner:
		Assets.draw_ref(self, "e:mrock%d" % (1 + _hash(x, y, 2)), bottom, ts * 1.75,
				_hash(x + 7, y, 2) == 0, Color(0.82, 0.82, 0.85))
	else:
		Assets.draw_ref(self, "e:mrock%d" % (3 + _hash(x, y, 2)), bottom, ts * 1.2,
				_hash(x + 3, y, 2) == 0, Color.WHITE)
	# трещины по мере добычи: скала «оседает»
	if map.rock_hp.has(key):
		var frac: float = clampf(float(map.rock_hp[key]) / maxf(1.0, _rock_hp_default), 0.0, 1.0)
		if frac < 0.66:
			draw_line(rect.position + Vector2(ts * 0.3, ts * 0.35),
					rect.position + Vector2(ts * 0.45, ts * 0.7), Color(0.1, 0.1, 0.1, 0.6), 1.5)
		if frac < 0.33:
			draw_line(rect.position + Vector2(ts * 0.62, ts * 0.25),
					rect.position + Vector2(ts * 0.52, ts * 0.62), Color(0.1, 0.1, 0.1, 0.6), 1.5)


func _rock_at(x: int, y: int) -> bool:
	return map.in_bounds(Vector2i(x, y)) \
			and (map.grid[y][x] == map.TILE_ROCK or map.grid[y][x] == map.TILE_ORE)


## Руда: вкрапления цвета металла поверх скалы (железо — рыжий, золото — тёплый).
func _draw_ore_flecks(cx: float, cy: float, ts: float, x: int, y: int) -> void:
	var gold := _hash(x, y, 4) == 0
	var col := Color("#e0b13e") if gold else Color("#b0684a")
	for i in 4:
		var h := _hash(x * 13 + i, y * 17 + i, 100)
		var fx := cx - ts * 0.28 + float(h % int(ts * 0.56))
		var fy := cy - ts * 0.2 + float((h / 3) % int(ts * 0.4))
		draw_circle(Vector2(fx, fy), 1.6 + float(h % 2), col)


## Саженец: две стадии роста (малый росток, кустик).
func _draw_sapling(key: Vector2i, bottom: Vector2, ts: float) -> void:
	var s: Dictionary = map.saplings[key]
	var frac: float = clampf(float(s.get("t", 0.0)) / maxf(0.1, float(s.get("grow_days", 1.2))), 0.0, 1.0)
	var ref := "e:sap1" if frac < 0.5 else "e:sap2"
	_draw_shadow(bottom, ts * 0.2)
	Assets.draw_ref(self, ref, bottom, ts * (0.5 if frac < 0.5 else 0.85))


func _draw_shadow(pos: Vector2, radius: float) -> void:
	draw_circle(pos, radius * 0.5, Color(0, 0, 0, 0.18))
