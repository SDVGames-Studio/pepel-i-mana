extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Статический слой города (M9): ландшафт (трава/вода/скалы/руда/лес) не меняется
## в течение игры — рисуется один раз вместо перерисовки ~2800 тайлов каждый кадр.

var map = null
var colors: Dictionary = {}


func setup(city_map, city_cfg: Dictionary) -> void:
	map = city_map
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		colors[key] = Color(String(c[key]))
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	var grass: Color = colors["grass"]
	var grass_alt: Color = colors["grass_alt"]
	for y in map.h:
		for x in map.w:
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			var base := grass if (x + y) % 2 == 0 else grass_alt
			var cx: float = x * float(map.ts) + float(map.ts) / 2.0
			var cy: float = y * float(map.ts) + float(map.ts) / 2.0
			match tile:
				map.TILE_GRASS:
					draw_rect(rect, base)
				map.TILE_WATER:
					draw_rect(rect, colors["water"])
				map.TILE_ROCK:
					draw_rect(rect, base)
					Assets.draw_ref(self, "img:rock", Vector2(cx, cy + 2), float(map.ts))
				map.TILE_ORE:
					draw_rect(rect, base)
					Assets.draw_ref(self, "img:ore", Vector2(cx, cy + 2), float(map.ts))
				map.TILE_TREE:
					draw_rect(rect, base)
					Assets.draw_ref(self, "img:tree", Vector2(cx, cy + 2), float(map.ts) * 1.25)
