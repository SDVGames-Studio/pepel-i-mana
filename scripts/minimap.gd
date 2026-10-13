extends Control
## Миникарта (M1): рисуется по мере исследования — видны только пройденные тайлы.

var gen: Object = null
var cell := 4.0
var hero_tile := Vector2i.ZERO
var visited: Dictionary = {}


func setup(dungeon_gen: Object) -> void:
	gen = dungeon_gen
	custom_minimum_size = Vector2(gen.w, gen.h) * cell
	queue_redraw()


func update_state(new_hero_tile: Vector2i, visited_tiles: Dictionary) -> void:
	hero_tile = new_hero_tile
	visited = visited_tiles
	queue_redraw()


func _draw() -> void:
	if gen == null:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(gen.w, gen.h) * cell), Color(0, 0, 0, 0.55))
	var floor_color := Color(0.72, 0.69, 0.62, 0.9)
	for tile: Vector2i in visited:
		if gen.is_floor(tile):
			draw_rect(Rect2(Vector2(tile) * cell, Vector2(cell, cell)), floor_color)
	if visited.has(gen.exit_tile):
		draw_rect(Rect2(Vector2(gen.exit_tile) * cell, Vector2(cell, cell)), Color("#d8c27a"))
	draw_rect(Rect2(Vector2(hero_tile) * cell, Vector2(cell, cell)), Color("#e0b060"))
	draw_string(ThemeDB.fallback_font, Vector2(4, 12), Loc.t("hud.minimap"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
