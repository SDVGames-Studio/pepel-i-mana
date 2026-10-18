extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Отрисовка карты мира (M8): биомы цветом, туман войны, точки интереса,
## маршрут героя. Только показ — логика в world_map.gd/world_sim.gd.

const KIND_COLORS := {
	"city": "#7cb342",
	"dungeon": "#b46ee0",
	"ruins": "#c8b07a",
	"camp": "#e57373",
	"settlement": "#ffd54f",
	"caravan": "#ffb300",
	"trade_camp": "#ffca28",
	"obelisk": "#4dd0e1",
}

# спрайты точек интереса (M9): Kenney + сгенерированные здания
const KIND_SPRITES := {
	"city": "b:house",
	"dungeon": "b:altar",
	"ruins": "k:65",
	"camp": "k:112",
	"settlement": "k:85",
	"caravan": "k:98",
	"trade_camp": "e:cart",
	"obelisk": "b:statue",
}

var map = null
var hero_px := Vector2.ZERO
var hero_tile := Vector2i.ZERO
var selected_tile := Vector2i(-1, -1)
var _time := 0.0


func setup(world_map) -> void:
	map = world_map


func _process(delta: float) -> void:
	_time += delta


func _draw() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	# тайлы: биомы цветом (дороги поверх)
	for y in map.h:
		for x in map.w:
			var p := Vector2i(x, y)
			draw_rect(Rect2(Vector2(x, y) * ts, Vector2(ts, ts)), _tile_color(p), true)
	# туман войны: неисследованное скрыто
	var fog_color := Color(0.04, 0.04, 0.07, 1.0)
	for y in map.h:
		for x in map.w:
			var p := Vector2i(x, y)
			if not map.is_explored(p):
				draw_rect(Rect2(Vector2(x, y) * ts, Vector2(ts, ts)), fog_color, true)
	# границы исследованной области — мягкая кромка
	for p: Vector2i in map.fog:
		if not map.is_explored(p + Vector2i(1, 0)) or not map.is_explored(p + Vector2i(-1, 0)) \
				or not map.is_explored(p + Vector2i(0, 1)) or not map.is_explored(p + Vector2i(0, -1)):
			draw_rect(Rect2(Vector2(p) * ts, Vector2(ts, ts)), Color(0.1, 0.1, 0.16, 0.6), false)
	# точки интереса (только найденные)
	for poi in map.pois:
		if not bool(poi["discovered"]):
			continue
		_draw_poi(poi, ts)
	# маршрут в пути
	_draw_route(ts)
	# герой (M9): спрайт воина с лёгким бобингом и тенью
	var bob := absf(sin(_time * 6.0)) * 2.0
	draw_circle(hero_px + Vector2(0, 6), 6.0, Color(0, 0, 0, 0.3))
	Assets.draw_ref(self, "img:knight", hero_px + Vector2(0, -2 - bob), 26.0)


func _tile_color(p: Vector2i) -> Color:
	var biomes: Dictionary = map.cfg["biomes"]
	match int(map.grid[p.y][p.x]):
		map.TILE_PLAINS: return Color(String(biomes["plains"]["color"]))
		map.TILE_WATER: return Color(String(biomes["water"]["color"]))
		map.TILE_FOREST: return Color(String(biomes["forest"]["color"]))
		map.TILE_HILL: return Color(String(biomes["hills"]["color"]))
		map.TILE_WASTE: return Color(String(biomes["waste"]["color"]))
		map.TILE_ROAD: return Color(String(biomes["road"]["color"]))
	return Color.SILVER


func _draw_poi(poi: Dictionary, ts: float) -> void:
	var pos: Vector2 = Vector2(poi["tile"]) * ts + Vector2(ts, ts) / 2.0
	var color := Color(String(KIND_COLORS.get(String(poi["kind"]), "#ffffff")))
	# подложка-пятно цвета точки (видно поверх биома) + спрайт (M9)
	var pulse := 0.8 + 0.2 * sin(_time * 2.5)
	draw_circle(pos, ts * 0.62 * pulse, Color(color.r, color.g, color.b, 0.18))
	var ref: String = KIND_SPRITES.get(String(poi["kind"]), "")
	if ref != "":
		var fallen := String(poi["kind"]) == "settlement" and String(poi["state"]) == "fallen"
		Assets.draw_ref(self, ref, pos + Vector2(0, -2), ts * 1.3, false,
				Color(0.55, 0.5, 0.5) if fallen else Color.WHITE)
		if fallen:
			draw_line(pos + Vector2(-9, -11), pos + Vector2(9, 7), Color("#1a1a1a"), 3.0)
			draw_line(pos + Vector2(9, -11), pos + Vector2(-9, 7), Color("#1a1a1a"), 3.0)
	else:
		_draw_poi_fallback(poi, pos, color)
	if poi["tile"] == selected_tile:
		draw_rect(Rect2(pos - Vector2(16, 16), Vector2(32, 32)), Color("#ffffff"), false, 2.0)


## Запасной вид точек (примитивы, M8) — если спрайт не задан.
func _draw_poi_fallback(poi: Dictionary, pos: Vector2, color: Color) -> void:
	match String(poi["kind"]):
		"city":
			draw_rect(Rect2(pos - Vector2(14, 14), Vector2(28, 28)), color)
			draw_rect(Rect2(pos - Vector2(14, 14), Vector2(28, 28)), Color("#3a3128"), false, 2.0)
			draw_rect(Rect2(pos - Vector2(5, 12), Vector2(10, 12)), Color("#c78d5b"))
		"dungeon":
			_draw_diamond(pos, 11.0, color)
			_draw_diamond(pos, 5.0, Color("#2a1f33"))
		"ruins":
			draw_rect(Rect2(pos - Vector2(9, 9), Vector2(18, 18)), color)
			draw_rect(Rect2(pos - Vector2(9, 3), Vector2(7, 12)), Color("#6b6154"))
			draw_rect(Rect2(pos + Vector2(2, -9), Vector2(7, 18)), Color("#6b6154"))
		"camp":
			draw_rect(Rect2(pos - Vector2(1, 10), Vector2(2, 14)), Color("#5d4037"))
			var left := PackedVector2Array([pos + Vector2(-10, 4), pos + Vector2(0, -8), pos + Vector2(1, 4)])
			var right := PackedVector2Array([pos + Vector2(-1, 4), pos + Vector2(10, -6), pos + Vector2(10, 4)])
			draw_colored_polygon(left, color)
			draw_colored_polygon(right, color.darkened(0.2))
		"settlement":
			draw_rect(Rect2(pos - Vector2(10, 4), Vector2(20, 12)), color)
			draw_colored_polygon(PackedVector2Array(
					[pos + Vector2(-12, -4), pos, pos + Vector2(12, -4)]), color.darkened(0.25))
			if String(poi["state"]) == "fallen":
				draw_line(pos + Vector2(-8, -8), pos + Vector2(8, 8), Color("#1a1a1a"), 3.0)
				draw_line(pos + Vector2(8, -8), pos + Vector2(-8, 8), Color("#1a1a1a"), 3.0)
		"caravan":
			draw_circle(pos, 9.0, color)
			draw_circle(pos, 5.0, Color("#5d4037"))
			draw_rect(Rect2(pos + Vector2(1, -12), Vector2(2, 8)), Color("#5d4037"))
		"obelisk":
			draw_rect(Rect2(pos + Vector2(-4, -13), Vector2(8, 26)), color)
			draw_rect(Rect2(pos + Vector2(-2, -11), Vector2(3, 22)), color.lightened(0.3))


func _draw_diamond(pos: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(
			[pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0)]), color)


func _draw_route(ts: float) -> void:
	var world := get_parent()
	if world == null or world.travel == null or (world.travel as Dictionary).is_empty():
		return
	var path: Array = (world.travel as Dictionary)["path"]
	if path.size() < 2:
		return
	var points := PackedVector2Array()
	for i in range(1, path.size()):
		points.append(map.tile_center_px(path[i]))
	for i in points.size():
		draw_circle(points[i], 3.0, Color(1, 1, 1, 0.5) if i % 2 == 0 else Color(1, 1, 1, 0.25))
	draw_circle(points[points.size() - 1], 6.0, Color(1, 1, 1, 0.7))
