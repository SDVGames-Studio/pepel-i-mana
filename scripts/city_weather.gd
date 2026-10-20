extends Node2D
## Погода города (M14-J): дождь (косые струи), снег (хлопья), туман (вуаль),
## пепельная буря (рыжая взвесь). Читает weather у сцены (city.gd прокидывает
## погодный узел симуляции). Дёшево: один узел, одна перерисовка.

var weather := "clear"
var season := "spring"
var _time := 0.0

const DROPS := 60
const FLAKES := 50
const ASH := 40

var _drop_x: Array = []
var _flake_x: Array = []
var _ash_x: Array = []


func _ready() -> void:
	set_process(true)
	var w := 1280.0
	for i in DROPS:
		_drop_x.append(randf_range(0.0, w))
	for i in FLAKES:
		_flake_x.append(randf_range(0.0, w))
	for i in ASH:
		_ash_x.append(randf_range(0.0, w))


func _process(delta: float) -> void:
	_time += delta
	if weather != "clear":
		queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	match weather:
		"rain":
			for i in DROPS:
				var x: float = fposmod(_drop_x[i] + sin(_time * 2.0 + float(i)) * 6.0, vp.x)
				var y: float = fposmod(_time * 520.0 + float(i) * 37.0, vp.y + 40.0) - 20.0
				draw_line(Vector2(x, y), Vector2(x - 4.0, y + 12.0), Color(0.65, 0.75, 0.95, 0.35), 1.2)
		"snow":
			if season == "winter":
				draw_rect(Rect2(Vector2.ZERO, vp), Color(0.85, 0.9, 1.0, 0.06))
			for i in FLAKES:
				var x: float = fposmod(_flake_x[i] + sin(_time * 0.9 + float(i)) * 14.0, vp.x)
				var y: float = fposmod(_time * 60.0 + float(i) * 53.0, vp.y + 20.0) - 10.0
				draw_circle(Vector2(x, y), 1.6 + (float(i) % 3), Color(1, 1, 1, 0.55))
		"fog":
			for i in 3:
				draw_rect(Rect2(Vector2.ZERO, vp), Color(0.75, 0.78, 0.8, 0.10 + 0.04 * i + 0.02 * sin(_time + float(i))))
		"ash_storm":
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.9, 0.5, 0.2, 0.08))
			for i in ASH:
				var x: float = fposmod(_ash_x[i] + _time * 180.0 + float(i) * 29.0, vp.x + 30.0) - 15.0
				var y: float = fposmod(_time * 90.0 + float(i) * 41.0, vp.y + 20.0) - 10.0
				draw_circle(Vector2(x, y), 1.4, Color(0.9, 0.55, 0.25, 0.5))
