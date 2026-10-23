extends SceneTree
## Проверка запечённого ландшафта (v1.21.5): доли зелени/воды/скал в кадре
## до и после перевыпечки должны совпадать по порядку величины.


func _fractions(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var green := 0
	var blue := 0
	var gray := 0
	var n := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			n += 1
			if c.g > 0.28 and c.g > c.r * 1.25 and c.g > c.b * 1.25:
				green += 1
			elif c.b > 0.25 and c.b > c.r * 1.3 and c.b > c.g * 1.05:
				blue += 1
			elif absf(c.r - c.g) < 0.06 and absf(c.g - c.b) < 0.06 and c.r > 0.25 and c.r < 0.75:
				gray += 1
	return {"green": 100.0 * float(green) / float(n), "water": 100.0 * float(blue) / float(n),
			"rock": 100.0 * float(gray) / float(n)}


func _init() -> void:
	var a := Image.load_from_file("res://tools/shot_ab_baked.png")
	var b := Image.load_from_file("res://tools/shot_ab_direct.png")
	if a == null or b == null:
		print("нет файлов")
		quit(1)
		return
	print("A запечённый:  %s" % str(_fractions(a)))
	print("B прямой:      %s" % str(_fractions(b)))
	# попиксельная разница A/B одного и того же мира: у совпадающей выпечки
	# отличаются только анимированные пятна (костёр, свечение, спрайты кадров)
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var strong := 0
	var total := 0.0
	var n := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := Vector3(absf(ca.r - cb.r), absf(ca.g - cb.g), absf(ca.b - cb.b)).length()
			total += d
			n += 1
			if d > 0.18:
				strong += 1
	print("средняя разница: %.4f, заметно отличающихся: %.1f%%" % [
			total / float(n), 100.0 * float(strong) / float(n)])
	quit(0)
