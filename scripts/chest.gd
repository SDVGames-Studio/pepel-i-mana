extends Node2D
## Сундук (M1): прототип — цветной прямоугольник; открытие через сцену данжа (E рядом).

var open := false


func _draw() -> void:
	var body_color := Color("#4a3626") if open else Color("#7a5230")
	draw_rect(Rect2(-10, -9, 20, 18), body_color)
	draw_rect(Rect2(-10, -9, 20, 18), Color(0, 0, 0, 0.35), false, 1.5)
	if not open:
		draw_rect(Rect2(-10, -2, 20, 4), Color("#c9a227"))
