extends SceneTree
## Генератор спрайтов славянской нечисти (v1.30, док 14 — «тёмный гримм»).
## Пиксель-арт 32×40, тёмные палитры, светящиеся глаза, тёмная обводка.
## Запуск: godot --headless --path . --script res://tools/make_creatures.gd
## Выход: assets/sprites/creatures/<id>.png — ссылки "img:creatures/<id>".

const OUT := Color("#14121a")   # обводка

var img: Image = null


func _init() -> void:
	var dir := "res://assets/sprites/creatures/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for id in ["leshy", "vodyanoy", "kikimora", "rusalka", "upyr", "volkolak",
			"bannik", "polevik", "nochnitsa", "black_hen", "viy", "baba_yaga",
			"koshchei", "death_needle"]:
		img = Image.create(32, 40, false, Image.FORMAT_RGBA8)
		match id:
			"leshy": _leshy()
			"vodyanoy": _vodyanoy()
			"kikimora": _kikimora()
			"rusalka": _rusalka()
			"upyr": _upyr()
			"volkolak": _volkolak()
			"bannik": _bannik()
			"polevik": _polevik()
			"nochnitsa": _nochnitsa()
			"black_hen": _black_hen()
			"viy": _viy()
			"baba_yaga": _baba_yaga()
			"koshchei": _koshchei()
			"death_needle": _needle()
		_outline()
		img.save_png(ProjectSettings.globalize_path(dir + id + ".png"))
	print("creatures: 14 спрайтов записано в assets/sprites/creatures/")
	quit()


# --- helpers -----------------------------------------------------------------

## Симметричный эллипс с центром cx (заливка).
func _ell(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	for y in range(maxi(0, int(cy - ry)), mini(40, int(cy + ry) + 1)):
		for x in range(maxi(0, int(cx - rx)), mini(32, int(cx + rx) + 1)):
			var dx := (float(x) + 0.5 - cx) / rx
			var dy := (float(y) + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, col)


## Вертикальная линия.
func _line(x: int, y0: int, y1: int, col: Color) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		if x >= 0 and x < 32 and y >= 0 and y < 40:
			img.set_pixel(x, y, col)


## Горизонтальная линия.
func _hline(x0: int, x1: int, y: int, col: Color) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		if x >= 0 and x < 32 and y >= 0 and y < 40:
			img.set_pixel(x, y, col)


func _px(x: int, y: int, col: Color) -> void:
	if x >= 0 and x < 32 and y >= 0 and y < 40:
		img.set_pixel(x, y, col)


## Пара светящихся глаз.
func _eyes(x1: int, x2: int, y: int, col: Color) -> void:
	_px(x1, y, col)
	_px(x1, y + 1, Color(col, 0.5))
	_px(x2, y, col)
	_px(x2, y + 1, Color(col, 0.5))


## Тёмная обводка вокруг непрозрачных пикселей.
func _outline() -> void:
	var src := img.duplicate()
	for y in 40:
		for x in 32:
			if src.get_pixel(x, y).a > 0.0:
				continue
			var near := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < 32 and n.y < 40 \
						and src.get_pixel(n.x, n.y).a > 0.0:
					near = true
					break
			if near:
				img.set_pixel(x, y, OUT)


# --- существа ----------------------------------------------------------------

## Леший: мшистый великан с рогами-ветками и бородой.
func _leshy() -> void:
	_ell(16, 22, 9, 13, Color("#3d5527"))       # тело мох
	_ell(16, 10, 7, 6, Color("#48612c"))        # голова
	_ell(16, 27, 7, 7, Color("#2e4220"))        # тень низа
	_line(9, 8, 1, Color("#5a4a2a"))            # рога-ветки
	_line(23, 8, 1, Color("#5a4a2a"))
	_line(8, 4, 2, Color("#5a4a2a"))
	_line(24, 4, 2, Color("#5a4a2a"))
	_ell(16, 15, 4, 3, Color("#6a7a4a"))        # борода мох
	_eyes(12, 20, 9, Color("#c8e04a"))
	for i in 6:                                  # мох-крапинки
		_px(10 + (i * 5) % 12, 18 + (i * 7) % 16, Color("#557030"))


## Водяной: тёмная тварь с плавниками и белёсыми глазами.
func _vodyanoy() -> void:
	_ell(16, 24, 10, 11, Color("#245a4d"))
	_ell(16, 11, 7, 6, Color("#2c6a58"))
	_px(5, 20, Color("#1a4038"))                # плавники
	_line(4, 21, 27, Color("#1a4038"))
	_line(5, 22, 28, Color("#1a4038"))
	_px(27, 20, Color("#1a4038"))
	_line(28, 21, 27, Color("#1a4038"))
	_ell(13, 10, 2, 2, Color("#b8d8c8"))        # выпуклые глаза
	_ell(19, 10, 2, 2, Color("#b8d8c8"))
	_px(13, 10, Color("#183028"))
	_px(19, 10, Color("#183028"))
	_hline(11, 21, 15, Color("#0e241e"))        # рот
	for x in range(12, 21, 2):
		_px(x, 15, Color("#c8d8c0"))            # зубы


## Кикимора: сутулая, лохмотья, дикие волосы, красные глазки.
func _kikimora() -> void:
	_ell(16, 24, 7, 12, Color("#55604a"))
	_ell(16, 11, 6, 5, Color("#8a9078"))
	_line(10, 9, 2, Color("#2a2a24"))           # волосы
	_line(11, 8, 1, Color("#2a2a24"))
	_line(22, 9, 2, Color("#2a2a24"))
	_line(21, 8, 1, Color("#2a2a24"))
	_line(9, 20, 30, Color("#4a5440"))          # тонкие руки
	_line(23, 20, 30, Color("#4a5440"))
	_eyes(13, 19, 11, Color("#d84a3a"))
	_hline(12, 20, 27, Color("#3a4434"))        # лохмотья низ


## Русалка: бледная кожа, тёмные распущенные волосы.
func _rusalka() -> void:
	_ell(16, 23, 8, 12, Color("#7ab0b8"))
	_ell(16, 10, 6, 5, Color("#8cc0c6"))
	_ell(16, 8, 7, 6, Color("#1e3a30"))         # волосы
	_line(8, 8, 24, Color("#1e3a30"))
	_line(24, 8, 24, Color("#1e3a30"))
	_line(9, 12, 28, Color("#1e3a30"))
	_line(23, 12, 28, Color("#1e3a30"))
	_eyes(13, 19, 10, Color("#183028"))
	_hline(13, 19, 14, Color("#5a8a90"))
	_ell(16, 30, 5, 5, Color("#3a6a60"))        # хвостовой низ


## Упырь: бескровный мертвец в чёрном саване.
func _upyr() -> void:
	_ell(16, 24, 8, 12, Color("#2a2430"))
	_ell(16, 10, 6, 6, Color("#9a8a8a"))
	_ell(16, 25, 5, 9, Color("#1a1620"))        # саван глубже
	_eyes(13, 19, 9, Color("#d84a3a"))
	_line(10, 14, 26, Color("#9a8a8a"))         # костлявые кисти
	_line(22, 14, 26, Color("#9a8a8a"))
	_hline(13, 19, 13, Color("#5a3a3a"))        # рот
	for x in range(13, 20, 2):
		_px(x, 13, Color("#c8c0b8"))            # клыки


## Волколак: чёрный зверь с оскалом и красными глазами.
func _volkolak() -> void:
	_ell(16, 24, 9, 11, Color("#3a3a42"))
	_ell(16, 12, 7, 5, Color("#44444e"))
	_ell(16, 15, 3, 3, Color("#2a2a30"))        # морда
	_line(10, 6, 2, Color("#44444e"))           # уши
	_line(22, 6, 2, Color("#44444e"))
	_eyes(12, 20, 11, Color("#e04a2a"))
	_hline(12, 20, 16, Color("#0e0e12"))
	for x in range(12, 21, 2):
		_px(x, 16, Color("#c8c8c8"))            # оскал
	_line(7, 26, 33, Color("#2a2a30"))          # лапы
	_line(25, 26, 33, Color("#2a2a30"))
	for x in range(5, 8):
		_px(x, 34, Color("#c8c8c8"))            # когти


## Банник: мохнатый дух бани с паром.
func _bannik() -> void:
	_ell(16, 24, 9, 12, Color("#7a5c34"))
	_ell(16, 11, 7, 6, Color("#8a6a3c"))
	_ell(16, 28, 8, 8, Color("#5a4426"))
	_eyes(12, 20, 10, Color("#e8c84a"))
	_hline(12, 20, 14, Color("#3a2c18"))
	for i in 5:                                  # пар
		var px := 8 + i * 4
		_px(px, 4 - (i % 2), Color("#c8c8c8", 0.6))
		_px(px + 1, 2 - (i % 2), Color("#c8c8c8", 0.4))


## Полевик: сухой дед-степ, сужается вниз, волоса соломой.
func _polevik() -> void:
	_ell(16, 22, 8, 10, Color("#a89248"))
	_ell(16, 10, 6, 5, Color("#b8a458"))
	_line(10, 8, 1, Color("#c8b458"))           # волоса-солома
	_line(12, 7, 1, Color("#c8b458"))
	_line(16, 6, 0, Color("#c8b458"))
	_line(20, 7, 1, Color("#c8b458"))
	_line(22, 8, 1, Color("#c8b458"))
	_eyes(13, 19, 10, Color("#3a2c18"))
	for i in 5:                                  # тело сужается пылью
		_ell(16, 30 + i, 6 - i, 1, Color("#a89248", 1.0 - i * 0.15))


## Ночница: мелкий ночной дух с перепончатыми крыльями.
func _nochnitsa() -> void:
	_ell(16, 20, 5, 8, Color("#35314e"))
	_ell(16, 11, 4, 4, Color("#454060"))
	for i in 9:                                  # крылья-перепонки
		var yy := 14 + i
		var w := 12 - absi(i - 4) * 2
		_hline(16 - w, 16 - 6, yy, Color("#2a2740"))
		_hline(16 + 6, 16 + w, yy, Color("#2a2740"))
	_eyes(14, 18, 10, Color("#e8e04a"))
	_px(15, 13, Color("#c8c0b8"))               # клычки
	_px(17, 13, Color("#c8c0b8"))


## Чёрная курица Яги: слуга.
func _black_hen() -> void:
	_ell(16, 24, 7, 8, Color("#1c1a20"))
	_ell(16, 14, 4, 4, Color("#26232c"))
	_ell(20, 12, 2, 2, Color("#26232c"))        # голова
	_ell(23, 13, 1, 2, Color("#c8a03c"))        # клюв
	_ell(19, 8, 1, 2, Color("#b03a2a"))         # гребень
	_line(12, 30, 36, Color("#c8a03c"))         # ноги
	_line(20, 30, 36, Color("#c8a03c"))
	_ell(11, 26, 4, 3, Color("#1c1a20"))        # хвост


## Вий: тяжёлые ВЕКИ поверх лица — взгляд скрыт.
func _viy() -> void:
	_ell(16, 25, 11, 12, Color("#2a2438"))
	_ell(16, 12, 9, 8, Color("#3a3448"))
	_ell(16, 12, 8, 4, Color("#4a4458"))        # грузные веки
	_hline(8, 24, 11, Color("#1a1624"))
	_hline(8, 24, 14, Color("#1a1624"))
	_line(7, 12, 13, Color("#1a1624"))
	_line(25, 12, 13, Color("#1a1624"))
	_hline(13, 19, 18, Color("#1a1624"))        # рот-щель
	_ell(16, 30, 9, 6, Color("#1e1a2a"))
	_ell(16, 4, 8, 2, Color("#1e1a2a"))         # венец тьмы


## Баба-яга: горбатая старуха с носом-крюком и красными глазами.
func _baba_yaga() -> void:
	_ell(16, 25, 8, 11, Color("#6a4a30"))
	_ell(16, 28, 9, 8, Color("#4a3420"))        # юбка/горб
	_ell(16, 11, 6, 5, Color("#8a6a4a"))
	_ell(19, 12, 3, 2, Color("#8a6a4a"))        # нос-крюк
	_line(22, 12, 13, Color("#8a6a4a"))
	_line(9, 8, 16, Color("#c8c0b0"))           # седые волосы
	_line(23, 8, 16, Color("#c8c0b0"))
	_eyes(12, 18, 10, Color("#e04a2a"))
	_hline(13, 18, 15, Color("#3a2a1a"))
	_line(11, 18, 28, Color("#4a3420"))         # костяная палка
	_px(11, 17, Color("#c8c0b0"))


## Кощей: сухой старик в золоте, лицо как череп.
func _koshchei() -> void:
	_ell(16, 24, 7, 12, Color("#5a5248"))
	_ell(16, 10, 6, 6, Color("#8a8272"))
	_ell(13, 9, 1, 2, Color("#181614"))         # впалые глазницы
	_ell(19, 9, 1, 2, Color("#181614"))
	_ell(16, 13, 2, 1, Color("#181614"))
	_hline(9, 23, 4, Color("#c8a03c"))          # золотой венец
	_hline(10, 22, 3, Color("#c8a03c"))
	_hline(10, 22, 18, Color("#c8a03c"))        # золотой ворот
	_hline(10, 22, 28, Color("#c8a03c"))        # золотой пояс
	_line(8, 16, 30, Color("#4a443a"))          # сухие руки
	_line(24, 16, 30, Color("#4a443a"))


## Игла смерти: тонкая игла с ушком — хранитель смерти Кощея.
func _needle() -> void:
	for y in range(6, 36):
		_line(15, y, y, Color("#b8b8c8"))
		_line(16, y, y, Color("#d8d8e4"))
	for y in range(34, 37):                      # ушко
		_hline(13, 18, y, Color("#b8b8c8"))
	_hline(14, 17, 6, Color("#e8e8f0"))
