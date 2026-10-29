extends Node2D
## Погода города (M14-J): дождь (косые струи), снег (хлопья), туман (вуаль),
## пепельная буря (рыжая взвесь). Читает weather у сцены (city.gd прокидывает
## погодный узел симуляции). Дёшево: один узел, одна перерисовка.

var weather := "clear"
var season := "spring"
var night := 0.0          # 0..1 — насколько темно (задаёт city.gd)
var map_span := Vector2(1920, 1080)   # размер карты в px (задаёт city.gd)
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


## Тинт осадков/вуали по времени суток (v1.30.2): днём нейтральный, ночью
## тёмно-синий — вуаль темнеет вместе с миром (иначе «белая река ночью»).
static func night_tint(night: float) -> Color:
	return Color(1, 1, 1).lerp(Color(0.38, 0.42, 0.55), clampf(night, 0.0, 1.0))


func _draw() -> void:
	var vp := get_viewport_rect().size
	# v1.30.2: туманная вуаль и осадки — в МИРОВЫХ координатах на всю карту
	# (экранный transform-трюк v1.29.4 рисовал вейл диагональной полосой —
	# «белая река ночью», замечание заказчика). Ночью вуаль темнеет вместе
	# с миром (night 0..1 задаёт city.gd).
	var span := Vector2(maxf(vp.x, map_span.x), maxf(vp.y, map_span.y))
	var tint := night_tint(night)
	match weather:
		"rain":
			for i in DROPS:
				var x: float = fposmod(_drop_x[i] + sin(_time * 2.0 + float(i)) * 6.0, span.x)
				var y: float = fposmod(_time * 520.0 + float(i) * 37.0, span.y + 40.0) - 20.0
				draw_line(Vector2(x, y), Vector2(x - 4.0, y + 12.0),
						Color(0.65 * tint.r, 0.75 * tint.g, 0.95 * tint.b, 0.35), 1.2)
		"snow":
			if season == "winter":
				draw_rect(Rect2(Vector2.ZERO, span),
						Color(0.85 * tint.r, 0.9 * tint.g, 1.0 * tint.b, 0.06))
			for i in FLAKES:
				var x: float = fposmod(_flake_x[i] + sin(_time * 0.9 + float(i)) * 14.0, span.x)
				var y: float = fposmod(_time * 60.0 + float(i) * 53.0, span.y + 20.0) - 10.0
				draw_circle(Vector2(x, y), 1.6 + float(i % 3),
						Color(tint.r, tint.g, tint.b, 0.55))
		"fog":
			for i in 3:
				var fc := Color(0.75 * tint.r, 0.78 * tint.g, 0.8 * tint.b,
						0.10 + 0.04 * i + 0.02 * sin(_time + float(i)))
				draw_rect(Rect2(Vector2.ZERO, span), fc)
		"ash_storm":
			draw_rect(Rect2(Vector2.ZERO, span),
					Color(0.9 * tint.r, 0.5 * tint.g, 0.2 * tint.b, 0.08))
			for i in ASH:
				var x: float = fposmod(_ash_x[i] + _time * 180.0 + float(i) * 29.0, span.x + 30.0) - 15.0
				var y: float = fposmod(_time * 90.0 + float(i) * 41.0, span.y + 20.0) - 10.0
				draw_circle(Vector2(x, y), 1.4,
						Color(0.9 * tint.r, 0.55 * tint.g, 0.25 * tint.b, 0.5))
