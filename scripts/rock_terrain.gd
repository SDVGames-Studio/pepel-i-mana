extends RefCounted
## СКАЛЫ И РУДНЫЕ ЖИЛЫ — «Природа 2.0» (v1.39.0), с нуля по ассетам
## ForgottenMemories (директива заказчика 2026-10-30: русские папки —
## первоисточник) и референсам «для Z.ai/скалы» (035a333a — модульные
## утёсы с травяными шапками; b3421be4 — валуны; 9b132112 — каньон).
##
## Рендер PER-TILE, ровно язык принятых плато v1.36 (EdgeLang):
##   тело тайла — фактурный серо-синий камень (make_nature2.py, 32px)
##   → северная солнечная кромка / светлое западное и тёмное восточное ребро
##   → южный срез: губа травы, тело среза, светлая полоса, тёмное основание
##   → травяные «шапки» на верхней грани и зелёная «юбка» у подножия
##   → мягкая тень на траве к югу от среза.
## Модульность = тайлы: гряда любой формы собирается из одинаковых кусков
## (референс 035a333a). Блобы НЕ используются: их сглаженный контур не
## совпадает с фактурой тайлов (урок v1.39.0 — «кратеры»).
##
## Тюнинг: data/city.json → colors → "rock2":
##   color/tone_alpha — базовый тон породы и сила сплачивающей заливки
##   cap_chance       — шанс травяной шапки на внутреннем тайле
##   skirt_chance     — шанс травинки-«юбки» у подножия
##   shadow_alpha     — тень у подножия (EdgeLang)
##   ore_chance_gold  — шанс золотой жилы (в коде хэш, исторически)

const EdgeLangC := preload("res://scripts/edge_lang.gd")

var t   # city_terrain — контекст (drawer, map, цвета, хэш)
var _stone_texs: Array = []


func setup(terrain: Node) -> void:
	t = terrain
	for v in 3:
		_stone_texs.append(Assets.tex("res://assets/sprites/env/n2_stone%d.png" % (v + 1)))


func opt(key: String, def: float) -> float:
	return float(t.colors.get("rock2", {}).get(key, def))


func col(key: String, def: String) -> Color:
	return Color(String(t.colors.get("rock2", {}).get(key, def)))


func base_color() -> Color:
	return col("color", "#66707e")


## Совместимость с city_terrain (кэш блобов больше не нужен — рендер per-tile).
func build_cache() -> Array:
	return []


func draw_blobs(ts: float) -> void:
	for y in t.map.h:
		for x in t.map.w:
			var tk := Vector2i(x, y)
			var g: int = t.map.grid[y][x]
			if g == t.map.TILE_ROCK or g == t.map.TILE_ORE:
				_draw_rock_tile(tk, g == t.map.TILE_ORE, ts)
			elif g == t.map.TILE_GRASS:
				_draw_skirt(tk, ts)


func _is_rock(tk: Vector2i) -> bool:
	if not t.map.in_bounds(tk):
		return false
	var g: int = t.map.grid[tk.y][tk.x]
	return g == t.map.TILE_ROCK or g == t.map.TILE_ORE


## Один модуль утёса: фактура + кромки высоты + шапка/руда/трещины.
func _draw_rock_tile(tk: Vector2i, is_ore: bool, ts: float) -> void:
	var x := float(tk.x * ts)
	var y := float(tk.y * ts)
	var base := base_color()
	# тело: фактура + лёгкий тон (сплачивает массив в породу)
	var tex: Texture2D = _stone_texs[t._hash(tk.x, tk.y, _stone_texs.size())]
	if tex != null:
		t._drawer.draw_texture_rect(tex, Rect2(x, y, ts, ts), false)
	t._drawer.draw_rect(Rect2(x, y, ts, ts), Color(base, opt("tone_alpha", 0.20)))
	# ВЕРХНЯЯ ГРАНЬ светлее (свет с СЗ ложит на горизонтальную поверхность):
	# светлая пелена на весь тайл — южный срез ниже затемнит свою полосу
	t._drawer.draw_rect(Rect2(x, y, ts, ts), Color(1.0, 0.99, 0.95,
			opt("top_light", 0.10)))
	# север ниже — солнечная кромка (свет с СЗ)
	if not _is_rock(tk + Vector2i(0, -1)):
		t._drawer.draw_rect(Rect2(x, y, ts, ts * EdgeLangC.N_RIM),
				base.lightened(0.26))
	# запад ниже — светлое ребро; восток ниже — тёмное (объём)
	if not _is_rock(tk + Vector2i(-1, 0)):
		t._drawer.draw_rect(Rect2(x, y, ts * EdgeLangC.W_RIM, ts),
				base.lightened(0.16))
	if not _is_rock(tk + Vector2i(1, 0)):
		t._drawer.draw_rect(Rect2(x + ts * (1.0 - EdgeLangC.E_RIM), y,
				ts * EdgeLangC.E_RIM, ts), base.darkened(0.24))
	# южный срез — «лицо» утёса (язык плато: губа/тело/свет/тень)
	var south_open := not _is_rock(tk + Vector2i(0, 1))
	if south_open:
		_draw_south_face(tk, x, y, ts, base)
	# травяная «шапка»: НАВИСАЕТ над северной кромкой (референс 035a333a —
	# луг ползёт на утёс сверху); внутри массива — только редкая зелень
	if not _is_rock(tk + Vector2i(0, -1)):
		_grass_cap(Vector2(x, y), ts,
				t.colors.get("grass", Color("#5ca046")), 0.42)
	elif t._hash(tk.x * 3, tk.y * 5, 100) < int(opt("cap_chance", 0.12) * 100.0):
		_grass_cap(Vector2(x, y), ts, t.colors.get("grass", Color("#5ca046")),
				0.16 + 0.08 * float(t._hash(tk.x, tk.y, 3)))
	# руда и трещины добычи
	if is_ore:
		_draw_ore(tk, Vector2(x, y), ts)
	elif t.map.rock_hp.has(tk):
		_draw_cracks(tk, Vector2(x, y), ts)


## Южный срез тайла: губа тёмной травы, тело среза, светлая полоса у губы,
## тёмное основание, контактная тень. Пропорции — EdgeLang (как плато).
## Тело среза ТЕМНЕЕ верхней грани: свет с СЗ, вертикаль в тени.
func _draw_south_face(tk: Vector2i, x: float, y: float, ts: float, base: Color) -> void:
	var stone := base.darkened(opt("cut_dark", 0.18) * 0.6)
	var stone_dark := base.darkened(opt("cut_dark", 0.30) + 0.06)
	var grass: Color = t.colors.get("grass", Color("#5ca046"))
	var face_h := ts * EdgeLangC.FACE_H1
	var lip_h := ts * EdgeLangC.LIP_H
	var y0 := y + ts - face_h
	# тело среза
	t._drawer.draw_rect(Rect2(x, y0 + lip_h, ts, face_h - lip_h), stone)
	# светлая полоса у губы (верх среза ловит свет)
	t._drawer.draw_rect(Rect2(x, y0 + lip_h, ts, (face_h - lip_h) * EdgeLangC.TOP_STRIPE),
			stone.lightened(0.12))
	# тёмное основание
	t._drawer.draw_rect(Rect2(x, y + ts - face_h * EdgeLangC.BOTTOM_STRIPE,
			ts, face_h * EdgeLangC.BOTTOM_STRIPE), stone_dark)
	# губа: тёмная трава нависает над срезом
	t._drawer.draw_rect(Rect2(x, y0, ts, lip_h),
			grass.darkened(opt("lip_dark", 0.24)))
	# напластования: 1-2 горизонтальные трещины по хэшу тайла
	var n_cracks: int = 1 + t._hash(tk.x * 3, tk.y * 7, 2)
	for i in n_cracks:
		var cy := y0 + lip_h + (face_h - lip_h) * (0.45 + 0.25 * float(i))
		t._drawer.draw_line(Vector2(x + 3.0, cy), Vector2(x + ts - 3.0, cy),
				Color(stone_dark, 0.55), 1.4)
	# контактная тень у подножия + мягкие полосы на траве (EdgeLang)
	t._drawer.draw_line(Vector2(x, y + ts - 1.0), Vector2(x + ts, y + ts - 1.0),
			Color(stone_dark.darkened(0.2), 0.8), 2.0)
	EdgeLangC.draw_foot_shadow(t._drawer, x, y + ts, ts, ts, 1,
			opt("shadow_alpha", 0.20))


## Шапка травы: луг нависает над северной кромкой утёса — полоса из
## 2-3 мягких блобов у верхнего края тайла (без «стволов»: круглые
## шапки с черточками читались как деревья на скале — урок v1.39.0).
func _grass_cap(origin: Vector2, ts: float, grass: Color, cover: float) -> void:
	var h := ts * cover
	t._drawer.draw_circle(origin + Vector2(ts * 0.5, h * 0.42), ts * 0.34, grass)
	t._drawer.draw_circle(origin + Vector2(ts * 0.20, h * 0.30), ts * 0.22,
			grass.lightened(0.08))
	t._drawer.draw_circle(origin + Vector2(ts * 0.80, h * 0.34), ts * 0.19,
			grass.darkened(0.06))


## Руда: кристаллы с блеском + намёк на золото (куда ставить шахту).
func _draw_ore(tk: Vector2i, origin: Vector2, ts: float) -> void:
	var gold: bool = t._hash(tk.x, tk.y, 4) == 0
	var col := Color("#e0b13e") if gold else Color("#b0684a")
	# рудное пятно: тонкое затемнение породы вокруг жилы
	t._drawer.draw_circle(origin + Vector2(ts * 0.5, ts * 0.5), ts * 0.42,
			Color(base_color().darkened(0.12), 0.22))
	for i in 3:
		var h: int = t._hash(tk.x * 13 + i, tk.y * 17 + i, 100)
		var fx := origin.x + 6.0 + float(h % int(ts - 12.0))
		var fy := origin.y + 9.0 + float((h / 3) % int(ts - 16.0))
		t._draw_diamond(Vector2(fx, fy), 2.4 + float(h % 3), col)
		t._draw_diamond(Vector2(fx - 1.0, fy - 1.2), 1.1, col.lightened(0.4))


## Трещины выработки: чем меньше запас, тем сильнее разбит тайл.
func _draw_cracks(tk: Vector2i, origin: Vector2, ts: float) -> void:
	var frac: float = clampf(float(t.map.rock_hp[tk]) / maxf(1.0, t._rock_hp_default), 0.0, 1.0)
	if frac < 0.66:
		t._drawer.draw_line(origin + Vector2(ts * 0.3, ts * 0.35),
				origin + Vector2(ts * 0.5, ts * 0.7), Color(0.10, 0.11, 0.13, 0.85), 1.6)
	if frac < 0.33:
		t._drawer.draw_line(origin + Vector2(ts * 0.65, ts * 0.2),
				origin + Vector2(ts * 0.5, ts * 0.55), Color(0.10, 0.11, 0.13, 0.85), 1.4)


## Зелёная «юбка» у подножия: травинки на траве южнее среза.
func _draw_skirt(tk: Vector2i, ts: float) -> void:
	var up := tk + Vector2i(0, -1)
	if not _is_rock(up):
		return
	if t._hash(tk.x * 5, tk.y * 3, 100) >= int(opt("skirt_chance", 0.5) * 100.0):
		return
	var grass: Color = t.colors.get("grass", Color("#5ca046")).darkened(0.10)
	var origin := Vector2(tk.x * ts, tk.y * ts)
	var h: int = t._hash(tk.x, tk.y * 7, 100)
	var bx := origin.x + 4.0 + float(h % int(ts - 8.0))
	var by := origin.y + ts * 0.62
	for i in 3:
		var hh: int = t._hash(tk.x * 7 + i, tk.y * 11 + i, 100)
		t._drawer.draw_line(Vector2(bx + float(i) * 2.4, by),
				Vector2(bx + float(i) * 2.4 + 1.0, by - 4.0 - float(hh % 3)),
				grass.lightened(0.06 * float(i % 2)), 1.3)
