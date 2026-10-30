extends RefCounted
## ПЛАТО И УТЁСЫ — рендер многоуровневого рельефа города (v1.36, этап
## «Многоуровневый рельеф», ответы №113–115). Схема Hills (Sprout Lands,
## структурный референс) + тон «скал» из референсов «для Z.ai»:
##   верхняя грань травы (светлее равнины — свет с СЗ)
##   → тёмная «губа» кромки
##   → срез утёса в 3 тона камня с напластованиями
##   → контактная тень и мягкая тень на траве у подножия.
## Лестницы-проходы — ступени в срезе + столбики на углах.
## Один файл = одна подсистема; тюнинг — data/city.json → colors → plateau.

var t   # city_terrain — контекст (drawer, map, цвета, шум)


func setup(terrain: Node) -> void:
	t = terrain


func opt(key: String, def: float) -> float:
	return float(t.colors.get("plateau", {}).get(key, def))


func col(key: String, def: String) -> Color:
	return Color(String(t.colors.get("plateau", {}).get(key, def)))


## Главный вход: рисует все плато поверх травы/скал/воды (до бахромы).
func draw_plateaus(ts: float) -> void:
	if t.map.height.is_empty():
		return
	# 1) верхние грани: плато светлее равнины, терраса — ещё светлее
	for y in t.map.h:
		for x in t.map.w:
			var lv: int = t.map.height_at(Vector2i(x, y))
			if lv <= 0:
				continue
			var a := opt("top_light", 0.06) if lv == 1 else opt("top_light2", 0.10)
			t._drawer.draw_rect(Rect2(x * ts, y * ts, ts, ts),
					Color(1.0, 0.97, 0.82, a))
	# 2) мягкая тень на траве у подножия южных кромок
	_draw_shadows(ts)
	# 3) кромки: грани по сторонам света, срезы к югу, лестницы, столбики
	for y in t.map.h:
		for x in t.map.w:
			var p := Vector2i(x, y)
			var lv: int = t.map.height_at(p)
			if lv <= 0:
				continue
			_draw_rims(p, lv, ts)
	for y in t.map.h:
		for x in t.map.w:
			var p := Vector2i(x, y)
			var lv: int = t.map.height_at(p)
			if lv <= 0:
				continue
			_draw_south_face(p, lv, ts)


func _nb_lv(p: Vector2i, d: Vector2i) -> int:
	var n: Vector2i = p + d
	if not t.map.in_bounds(n):
		return 0
	return t.map.height_at(n)


func _draw_rims(p: Vector2i, lv: int, ts: float) -> void:
	var x := float(p.x * ts)
	var y := float(p.y * ts)
	var grass: Color = t.colors.get("grass", Color("#5ca046"))
	var stone := col("stone", "#8a8072")
	# север ниже — солнечная кромка (свет с СЗ)
	if _nb_lv(p, Vector2i(0, -1)) < lv:
		t._drawer.draw_rect(Rect2(x, y, ts, ts * 0.10),
				grass.lightened(0.16))
	# запад ниже — светлое ребро камня
	if _nb_lv(p, Vector2i(-1, 0)) < lv:
		t._drawer.draw_rect(Rect2(x, y, ts * 0.08, ts),
				stone.lightened(0.10))
	# восток ниже — тёмное ребро (объём)
	if _nb_lv(p, Vector2i(1, 0)) < lv:
		t._drawer.draw_rect(Rect2(x + ts * 0.92, y, ts * 0.08, ts),
				stone.darkened(0.22))


## Южный срез — «лицо» утёса: губа травы, три тона камня, напластования,
## контактная тень. На лестнице срез превращается в ступени.
func _draw_south_face(p: Vector2i, lv: int, ts: float) -> void:
	var diff: int = lv - _nb_lv(p, Vector2i(0, 1))
	if diff <= 0:
		return
	var x := float(p.x * ts)
	var y := float(p.y * ts)
	var face_h := ts * (opt("face_h2", 0.60) if diff >= 2 else opt("face_h1", 0.38))
	if lv == 2 and diff == 1:
		# срез террасы повыше кромки плато — два уровня читаются сразу
		face_h *= opt("terrace_face_mult", 1.3)
	var y0 := y + ts - face_h
	var stone := col("stone", "#8a8072")
	var stone_dark := col("stone_dark", "#5d574c")
	var lip_c: Color = t.colors.get("grass", Color("#5ca046")).darkened(opt("lip_dark", 0.24))
	var lip_h := ts * 0.12
	# тело среза: тон камня слегка дышит по тайлам (как фасеты гряды)
	var tone := 1.0 + 0.05 * float(t._hash(p.x, p.y, 3) - 1) / 10.0
	t._drawer.draw_rect(Rect2(x, y0 + lip_h, ts, face_h - lip_h),
			stone.lightened((tone - 1.0) * 0.5))
	# губа кромки — тёмная трава нависает над срезом
	t._drawer.draw_rect(Rect2(x, y0, ts, lip_h), lip_c)
	if t.map.is_stair(p):
		_draw_stairs(p, x, y0 + lip_h, ts, face_h - lip_h, stone, stone_dark)
	else:
		# три тона: светлая верхняя полоса, тёмное основание, линия контакта
		t._drawer.draw_rect(Rect2(x, y0 + lip_h, ts, ts * 0.08),
				stone.lightened(0.14))
		t._drawer.draw_rect(Rect2(x, y + ts - ts * 0.10, ts, ts * 0.10),
				stone_dark)
		# напластования: 1–2 горизонтальные трещины по хэшу тайла
		var n_cracks: int = 1 + t._hash(p.x * 3, p.y * 7, 2)
		for i in n_cracks:
			var cy := y0 + lip_h + (face_h - lip_h) * (0.45 + 0.25 * float(i))
			t._drawer.draw_line(Vector2(x + 3.0, cy), Vector2(x + ts - 3.0, cy),
					Color(stone_dark, 0.55), 1.4)
	# контактная тень у подножия среза
	t._drawer.draw_line(Vector2(x, y + ts - 1.0), Vector2(x + ts, y + ts - 1.0),
			Color(stone_dark.darkened(0.2), 0.8), 2.0)
	# столбики на выпуклых углах кромки (юг+восток / юг+запад) — как в Hills
	if _nb_lv(p, Vector2i(1, 0)) < lv:
		_post(x + ts - 3.0, y0 - 2.0, face_h + 2.0, stone_dark)
	if _nb_lv(p, Vector2i(-1, 0)) < lv:
		_post(x, y0 - 2.0, face_h + 2.0, stone_dark)


## Ступени-лестница в срезе: 3 каменные ступени с тенью подступёнка.
func _draw_stairs(p: Vector2i, x: float, y0: float, ts: float, h: float,
		stone: Color, stone_dark: Color) -> void:
	var steps := 3
	var sh := h / float(steps)
	for i in steps:
		var sy := y0 + sh * float(i)
		# проступь светлее, чередование тонов — ступени читаются
		var tone := stone.lightened(0.16 if i % 2 == 0 else 0.06)
		t._drawer.draw_rect(Rect2(x + 2.0, sy, ts - 4.0, sh - 1.0), tone)
		# подступёнок — тёмная линия под ступенью
		t._drawer.draw_line(Vector2(x + 2.0, sy + sh - 1.0),
				Vector2(x + ts - 2.0, sy + sh - 1.0),
				Color(stone_dark, 0.8), 1.6)


func _post(x: float, y: float, h: float, stone_dark: Color) -> void:
	t._drawer.draw_rect(Rect2(x, y, 3.0, h), stone_dark.lightened(0.08))
	t._drawer.draw_rect(Rect2(x - 1.0, y - 1.0, 5.0, 3.0),
			stone_dark.darkened(0.15))


## Тень у подножия: 3 полосы с затуханием на траве к югу от кромки.
func _draw_shadows(ts: float) -> void:
	var base := opt("shadow_alpha", 0.22)
	for y in t.map.h:
		for x in t.map.w:
			var p := Vector2i(x, y)
			var lv: int = t.map.height_at(p)
			if lv <= 0:
				continue
			var diff: int = lv - _nb_lv(p, Vector2i(0, 1))
			if diff <= 0 or not t.map.in_bounds(p + Vector2i(0, 1)):
				continue
			var sy := float((p.y + 1) * ts)
			var bands := 2 + mini(diff, 2)
			for i in bands:
				var a := base * (1.0 - 0.34 * float(i))
				t._drawer.draw_rect(Rect2(float(p.x * ts), sy + ts * 0.16 * float(i),
						ts, ts * 0.18), Color(0.05, 0.08, 0.05, a))
