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
## v1.48.1: region (тайлы) — только свой чанк запечки.
func draw_plateaus(ts: float, region := Rect2i()) -> void:
	if t.map.height.is_empty():
		return
	var x0 := maxi(0, region.position.x)
	var y0 := maxi(0, region.position.y)
	var x1: int = t.map.w if region.size == Vector2i.ZERO else mini(t.map.w, region.end.x + 1)
	var y1: int = t.map.h if region.size == Vector2i.ZERO else mini(t.map.h, region.end.y + 1)
	# 1) верхние грани: плато светлее равнины, терраса — ещё светлее
	for y in range(y0, y1):
		for x in range(x0, x1):
			var lv: int = t.map.height_at(Vector2i(x, y))
			if lv <= 0:
				continue
			var a := opt("top_light", 0.10) if lv == 1 else opt("top_light2", 0.16)
			t._drawer.draw_rect(Rect2(x * ts, y * ts, ts, ts),
					Color(1.0, 0.97, 0.82, a))
	# 2) мягкая тень на траве у подножия южных кромок
	_draw_shadows(ts, region)
	# 3) кромки: грани по сторонам света, срезы к югу, лестницы, столбики
	for y in range(y0, y1):
		for x in range(x0, x1):
			var p := Vector2i(x, y)
			var lv: int = t.map.height_at(p)
			if lv <= 0:
				continue
			_draw_rims(p, lv, ts)
	for y in range(y0, y1):
		for x in range(x0, x1):
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


## v1.80.5: холмы на ПОЛОТНЕ — кромки в тон мха (ярко-зелёные линейки и
## чистый серый камень читались прямоугольными коробками), высота губы
## дрожит по хэшу тайла — контур органический, не линейка.
func _moss() -> Color:
	return t._biome_grass_color()


func _jit(p: Vector2i, salt: int) -> float:
	return float(t._hash(p.x, p.y, salt) % 100) / 100.0


func _draw_rims(p: Vector2i, lv: int, ts: float) -> void:
	# v1.80.5: на полотне холм читается светом и тенью — камни только
	# редкими акцентами (каждый 2-3-й тайл кромки, по хэшу)
	if t._biome_canvas == null:
		return
	var moss: Color = _moss()
	var stone := col("stone", "#8a8072").lerp(moss, 0.3)
	var edge := _nb_lv(p, Vector2i(-1, 0)) < lv or _nb_lv(p, Vector2i(1, 0)) < lv
	if not edge or t._hash(p.x, p.y, 61) % 3 != 0:
		return
	var c1 := Vector2(p.x * ts + ts * (0.2 + 0.6 * _jit(p, 63)),
			p.y * ts + ts * (0.2 + 0.6 * _jit(p, 65)))
	t._drawer.draw_circle(c1, ts * (0.09 + 0.06 * _jit(p, 67)),
			stone.lightened(0.05 + 0.14 * _jit(p, 69)))
	t._drawer.draw_circle(c1 + Vector2(-2, -2), ts * 0.05,
			stone.lightened(0.18))


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
		face_h *= opt("terrace_face_mult", 1.3)
	face_h *= 0.9 + 0.2 * _jit(p, 15)
	var y0 := y + ts - face_h
	var moss: Color = _moss()
	var stone := col("stone", "#8a8072").lerp(moss, 0.3)
	var lip_h := ts * 0.12
	if t.map.is_stair(p):
		var stone0 := col("stone", "#8a8072")
		var stone_d0 := col("stone_dark", "#5d574c")
		t._drawer.draw_rect(Rect2(x, y0 + lip_h, ts, face_h - lip_h),
				stone0.lightened(0.05))
		t._drawer.draw_rect(Rect2(x, y0, ts, lip_h), moss.darkened(0.24))
		_draw_stairs(p, x, y0 + lip_h, ts, face_h - lip_h, stone0, stone_d0)
		return
	# v1.80.5: срез = мягкая тёмная масса (холм читается тенью, не линией)
	t._drawer.draw_rect(Rect2(x, y0 + lip_h, ts, face_h - lip_h),
			Color(moss.darkened(0.5), 0.5))
	# губа мха нависает
	t._drawer.draw_rect(Rect2(x, y0, ts, lip_h), moss.darkened(0.24))
	# редкие валуны-акценты (каждый 2-й тайл)
	if t._hash(p.x, p.y, 71) % 2 == 0:
		var bx := x + ts * (0.2 + 0.6 * _jit(p, 73))
		var by := y0 + lip_h + (face_h - lip_h) * (0.3 + 0.5 * _jit(p, 75))
		var br := ts * (0.09 + 0.09 * _jit(p, 77))
		t._drawer.draw_circle(Vector2(bx, by), br,
				stone.lightened(0.05 + 0.14 * _jit(p, 79)))
		t._drawer.draw_circle(Vector2(bx - br * 0.3, by - br * 0.35),
				br * 0.4, stone.lightened(0.2))
	# контактная тень у подножия
	t._drawer.draw_line(Vector2(x, y + ts - 1.0), Vector2(x + ts, y + ts - 1.0),
			Color(moss.darkened(0.55), 0.7), 2.0)
	if _nb_lv(p, Vector2i(1, 0)) < lv:
		_post(x + ts - 3.0, y0 - 2.0, face_h + 2.0, moss.darkened(0.45))
	if _nb_lv(p, Vector2i(-1, 0)) < lv:
		_post(x, y0 - 2.0, face_h + 2.0, moss.darkened(0.45))


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
func _draw_shadows(ts: float, region := Rect2i()) -> void:
	var base := opt("shadow_alpha", 0.22)
	var x0 := maxi(0, region.position.x)
	var y0 := maxi(0, region.position.y)
	var x1: int = t.map.w if region.size == Vector2i.ZERO else mini(t.map.w, region.end.x + 1)
	var y1: int = t.map.h if region.size == Vector2i.ZERO else mini(t.map.h, region.end.y + 1)
	for y in range(y0, y1):
		for x in range(x0, x1):
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
