extends Node2D
## Лестница-выход из данжа (M1): стоит у точки входа, выход доступен всегда.

var marker_color := Color("#d8c27a")


func _draw() -> void:
	draw_rect(Rect2(-14, -14, 28, 28), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(-12, -12, 24, 24), marker_color)
	draw_line(Vector2(0, 8), Vector2(0, -8), Color(0.1, 0.08, 0.06), 2.0)
	draw_polyline(
		PackedVector2Array([Vector2(-5, -3), Vector2(0, -8), Vector2(5, -3)]),
		Color(0.1, 0.08, 0.06), 2.0)
