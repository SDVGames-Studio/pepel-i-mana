extends Node2D
## Визуал заклинаний (M3): вспышка, кольцо, зона, молния.
## Самоуничтожается по таймеру; читаемость — ответ №62, цвет = цвет школы.

var kind := "burst"               # burst | ring | zone | bolt
var fx_color := Color.WHITE
var fx_radius := 40.0
var fx_duration := 0.5
var points := PackedVector2Array()   # для молнии, координаты относительно узла

var _life := 0.0


func setup(kind_v: String, color_v: Color, radius_v: float, duration_v: float,
		points_v: PackedVector2Array = PackedVector2Array()) -> void:
	kind = kind_v
	fx_color = color_v
	fx_radius = radius_v
	fx_duration = duration_v
	points = points_v
	z_index = 20


func _ready() -> void:
	_life = fx_duration


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_life / fx_duration, 0.0, 1.0)   # 1 -> 0 за время жизни
	match kind:
		"burst":
			draw_circle(Vector2.ZERO, fx_radius * (1.25 - 0.45 * t),
					Color(fx_color.r, fx_color.g, fx_color.b, 0.45 * t))
			draw_arc(Vector2.ZERO, fx_radius, 0.0, TAU, 32,
					Color(fx_color.r, fx_color.g, fx_color.b, t), 3.0)
		"ring":
			draw_arc(Vector2.ZERO, fx_radius * (0.7 + 0.3 * t), 0.0, TAU, 40,
					Color(fx_color.r, fx_color.g, fx_color.b, t), 3.0)
		"zone":
			var pulse := 0.6 + 0.4 * absf(sin(_life * 6.0))
			draw_circle(Vector2.ZERO, fx_radius,
					Color(fx_color.r, fx_color.g, fx_color.b, 0.22 * pulse))
			for i in 8:
				var a := TAU * float(i) / 8.0
				var tip := Vector2(cos(a), sin(a)) * fx_radius * (0.75 + 0.2 * pulse)
				draw_line(Vector2(cos(a), sin(a)) * fx_radius * 0.2, tip,
						Color(fx_color.r, fx_color.g, fx_color.b, 0.7 * pulse), 2.0)
		"bolt":
			for i in range(points.size() - 1):
				draw_line(points[i], points[i + 1],
						Color(fx_color.r, fx_color.g, fx_color.b, t), 3.0)
				draw_line(points[i], points[i + 1],
						Color(1, 1, 1, 0.5 * t), 1.0)
