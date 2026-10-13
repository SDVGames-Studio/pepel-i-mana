extends Node2D
## Отрисовка тайлов данжа (M1): цветные тайлы биома «руины».
## Пиксель-арт-спрайты приходят на этапе M8.

var gen: Object = null
var ts := 32
var biome: Dictionary = {}


func setup(dungeon_gen: Object, tile_size: int, biome_data: Dictionary) -> void:
	gen = dungeon_gen
	ts = tile_size
	biome = biome_data
	queue_redraw()


func _draw() -> void:
	if gen == null:
		return
	draw_rect(Rect2(0, 0, gen.w * ts, gen.h * ts), Color(String(biome["wall_color"])))
	var floor_color := Color(String(biome["floor_color"]))
	var floor_color_alt := floor_color.darkened(0.07)
	for y in gen.h:
		for x in gen.w:
			if gen.grid[y][x] != gen.TILE_FLOOR:
				continue
			var c := floor_color if (x + y) % 2 == 0 else floor_color_alt
			draw_rect(Rect2(x * ts, y * ts, ts, ts), c)
