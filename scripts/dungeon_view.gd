extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Отрисовка тайлов данжа (M1→M9): спрайты Kenney Tiny Dungeon 16×16 (×2),
## подкрашенные цветами биома. Спрайты статичны — перерисовка один раз на забег.

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
	var wall_col := Color(String(biome["wall_color"]))
	draw_rect(Rect2(0, 0, gen.w * ts, gen.h * ts), Color(String(biome["bg_color"])))
	var floor_ref := String(biome.get("floor_sprite", ""))
	var wall_ref := String(biome.get("wall_sprite", ""))
	var floor_color := Color(String(biome["floor_color"]))
	var floor_color_alt := floor_color.darkened(0.07)
	for y in gen.h:
		for x in gen.w:
			var tile: int = gen.grid[y][x]
			var pos := Vector2(x, y) * ts
			if tile == gen.TILE_FLOOR:
				if floor_ref == "":
					draw_rect(Rect2(pos, Vector2(ts, ts)),
							floor_color if (x + y) % 2 == 0 else floor_color_alt)
					continue
				Assets.draw_ref(self, floor_ref, pos + Vector2(ts, ts) * 0.5, float(ts),
						false, floor_color if (x + y) % 2 == 0 else floor_color_alt)
			else:
				draw_rect(Rect2(pos, Vector2(ts, ts)), wall_col.darkened(0.25))
				Assets.draw_ref(self, wall_ref, pos + Vector2(ts, ts) * 0.5, float(ts), false, wall_col)
