extends Node2D
## Рычаг древнего механизма (v1.83, док 18 — данжи-загадки): главный
## рычаг отпирает запечатанный выход; рычаг риска открывает бонусную
## кладку и поднимает засаду. Рисуется узлом, состояние — pulled.

var lever_id := "main"
var pulled := false


func _draw() -> void:
	# плита механизма в стене
	draw_rect(Rect2(-7, -14, 14, 20), Color(0.42, 0.39, 0.35))
	draw_rect(Rect2(-5, -12, 10, 5), Color(0.55, 0.52, 0.47))
	if pulled:
		# рычаг отведён — механизм сработал
		draw_line(Vector2(0, -6), Vector2(7, -12), Color(0.8, 0.72, 0.5), 3.0)
		draw_circle(Vector2(7, -12), 2.6, Color(0.9, 0.85, 0.65))
		draw_circle(Vector2(0, -6), 2.2, Color(0.35, 0.75, 0.4))
	else:
		draw_line(Vector2(0, -6), Vector2(-5, -13), Color(0.8, 0.72, 0.5), 3.0)
		draw_circle(Vector2(-5, -13), 2.6, Color(0.9, 0.7, 0.35))
		draw_circle(Vector2(0, -6), 2.2, Color(0.8, 0.45, 0.25))
	# мерцание-подсказка: непотянутый рычаг виден в темноте
	if not pulled:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
		draw_circle(Vector2(0, -16), 1.6, Color(1.0, 0.85, 0.4, 0.4 + 0.4 * pulse))
