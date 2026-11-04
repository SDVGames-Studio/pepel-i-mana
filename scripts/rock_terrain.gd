extends RefCounted
## СКАЛЫ И РУДНЫЕ ЖИЛЫ — «Природа 2.0» (v1.39.0; схема «травяная гряда
## с каменным обрывом» — v1.39.1 по референсам заказчика).
##
## КАК ЧИТАЕТСЯ ГРЯДА (референсы: каменный обрыв + травяной верх, лужайка
## и деревья сверху, ступени камня в тени):
##   ВЕРХ массива — ЛУЖАЙКА: та же трава, что вокруг, чуть светлее
##   (свет с СЗ); на ней — редкие кустики/камешки/цветы;
##   ВИДИМАЯ СТОРОНА (юг) — КАМЕННЫЙ ОБРЫВ: губа тёмной травы нависает,
##   тело обрыва — фактурный серо-синий камень с напластованиями и
##   вертикальными трещинами, светлая полоса у губы, тёмное основание,
##   контактная тень и мягкая тень на траве (язык принятых плато v1.36,
##   обрыв ВЫШЕ платового — скала массивнее);
##   запад — светлое ребро, восток — тёмное;
##   ДОБЫЧА: выработанный тайл (TILE_DEADROCK) рисуется КАМЕННОЙ
##   ТЕКСТУРОЙ — «шапка» снята, видно камень (поручение заказчика:
##   «добытый блок пропадает и видно ещё блоки с каменной текстурой»).
##
## Руда: кристаллы железа/золота на лужайке тайла (видно, куда ставить
## шахту). Тюнинг: data/city.json → colors → "rock2".

const EdgeLangC := preload("res://scripts/edge_lang.gd")
const TS := 32

var t   # city_terrain — контекст (drawer, map, цвета, хэш, трава)
var _stone_texs: Array = []
var _pebble_texs: Array = []   # мелкие валуны-пропсы на лужайке (16px)


func setup(terrain: Node) -> void:
	t = terrain
	for v in 3:
		_stone_texs.append(Assets.tex("res://assets/sprites/env/n2_stone%d.png" % (v + 1)))
	for n in ["rock2_a5", "rock2_b5", "rock2_c5"]:
		_pebble_texs.append(Assets.tex("res://assets/sprites/env/%s.png" % n))


func opt(key: String, def: float) -> float:
	return float(t.colors.get("rock2", {}).get(key, def))


func col(key: String, def: String) -> Color:
	return Color(String(t.colors.get("rock2", {}).get(key, def)))


func base_color() -> Color:
	return col("color", "#5f6875")


## Совместимость с city_terrain (рендер per-tile, кэшей не нужно).
func build_cache() -> Array:
	return []


## v1.48.1: region (тайлы) — рисуем только свой чанк запечки (вся карта
## на каждый чанк = сотни мс GDScript-циклов).
func draw_blobs(ts: float, region := Rect2i()) -> void:
	var x0 := maxi(0, region.position.x)
	var y0 := maxi(0, region.position.y)
	var x1: int = t.map.w if region.size == Vector2i.ZERO else mini(t.map.w, region.end.x + 1)
	var y1: int = t.map.h if region.size == Vector2i.ZERO else mini(t.map.h, region.end.y + 1)
	# проход 1: лужайка верха массива + обрывы к югу
	for y in range(y0, y1):
		for x in range(x0, x1):
			var tk := Vector2i(x, y)
			var g: int = t.map.grid[y][x]
			if g == t.map.TILE_ROCK or g == t.map.TILE_ORE:
				_draw_rock_tile(tk, g == t.map.TILE_ORE, ts)
	# проход 2: зелёная «юбка» на траве у подножия
	for y in range(y0, y1):
		for x in range(x0, x1):
			if t.map.grid[y][x] == t.map.TILE_GRASS:
				_draw_skirt(Vector2i(x, y), ts)


func _is_rock(tk: Vector2i) -> bool:
	if not t.map.in_bounds(tk):
		return false
	var g: int = t.map.grid[tk.y][tk.x]
	return g == t.map.TILE_ROCK or g == t.map.TILE_ORE


## Тайл гряды: лужайка сверху + кромки + (юг открыт) каменный обрыв.
func _draw_rock_tile(tk: Vector2i, is_ore: bool, ts: float) -> void:
	var x := float(tk.x * ts)
	var y := float(tk.y * ts)
	var grass_top: Color = t.colors.get("grass", Color("#5ca046"))
	# ВЕРХ — лужайка: та же трава (текстура), чуть светлее — свет с СЗ
	var tex: Texture2D = t._grass_texture_at(tk.x, tk.y)
	if tex != null:
		t._drawer.draw_texture_rect(tex, Rect2(x, y, ts, ts), false)
	t._drawer.draw_rect(Rect2(x, y, ts, ts),
			Color(1.0, 0.99, 0.88, opt("top_light", 0.10)))
	# север ниже — солнечная кромка луга (светлая полоса, свес травы)
	if not _is_rock(tk + Vector2i(0, -1)):
		t._drawer.draw_rect(Rect2(x, y, ts, ts * 0.14),
				grass_top.lightened(0.20))
	# запад ниже — светлое ребро камня; восток ниже — тёмное
	if not _is_rock(tk + Vector2i(-1, 0)):
		t._drawer.draw_rect(Rect2(x, y, ts * EdgeLangC.W_RIM, ts),
				base_color().lightened(0.16))
	if not _is_rock(tk + Vector2i(1, 0)):
		_draw_east_face(tk, x, y, ts)
	# юг ниже — КАМЕННЫЙ ОБРЫВ (видимая сторона скалы)
	if not _is_rock(tk + Vector2i(0, 1)):
		_draw_cliff_face(tk, x, y, ts)
	# декор лужайки / руда
	if is_ore:
		_draw_ore(tk, Vector2(x, y), ts)
	else:
		_draw_top_decor(tk, x, y, ts)
	# трещины выработки — на обрыве этого тайла
	if t.map.rock_hp.has(tk):
		_draw_cracks(tk, x, y, ts)


## Восточная грань: узкая каменная полоса во всю высоту (вид с ЮВ,
## как на референсах заказчика) — темнее южного, вертикаль в тени.
func _draw_east_face(tk: Vector2i, x: float, y: float, ts: float) -> void:
	var stone_dark := base_color().darkened(opt("cut_dark", 0.30))
	var w := ts * 0.20
	var stex: Texture2D = _stone_texs[t._hash(tk.x * 7, tk.y * 5, _stone_texs.size())]
	if stex != null:
		t._drawer.draw_texture_rect_region(stex,
				Rect2(x + ts - w, y, w, ts), Rect2(TS - 8, 0, 8, TS))
	t._drawer.draw_rect(Rect2(x + ts - w, y, w, ts), Color(stone_dark, 0.55))
	# вертикальные складки ребра
	for i in 2:
		var h: int = t._hash(tk.x * 13 + i, tk.y * 11 + i, 100)
		var cy := y + 3.0 + float(h % int(ts - 8.0))
		t._drawer.draw_line(Vector2(x + ts - w + 1.5, cy),
				Vector2(x + ts - 1.5, cy + 2.0), Color(stone_dark.darkened(0.2), 0.6), 1.2)


## Каменный обрыв: губа травы, тело из фактурного камня, напластования,
## вертикальные трещины, тёмное основание, тени (язык плато, выше).
func _draw_cliff_face(tk: Vector2i, x: float, y: float, ts: float) -> void:
	var stone := base_color().lightened(opt("cut_light", 0.10))
	var stone_dark := base_color().darkened(opt("cut_dark", 0.30))
	var grass: Color = t.colors.get("grass", Color("#5ca046"))
	var face_h := ts * opt("face_h", 0.58)
	var lip_h := ts * EdgeLangC.LIP_H
	var y0 := y + ts - face_h
	# тело обрыва: фактура камня (вертикаль в тени — тон гасит)
	var stex: Texture2D = _stone_texs[t._hash(tk.x * 5, tk.y * 3, _stone_texs.size())]
	if stex != null:
		t._drawer.draw_texture_rect_region(stex,
				Rect2(x, y0 + lip_h, ts, face_h - lip_h),
				Rect2(0, 0, TS, TS))
	t._drawer.draw_rect(Rect2(x, y0 + lip_h, ts, face_h - lip_h),
			Color(base_color(), 0.30))
	# стена нависает на траву у подножия (массивность обрыва)
	t._drawer.draw_rect(Rect2(x, y + ts, ts, 4.0), base_color().darkened(0.34))
	# светлая полоса у губы (кромка ловит свет)
	t._drawer.draw_rect(Rect2(x, y0 + lip_h, ts, (face_h - lip_h) * EdgeLangC.TOP_STRIPE),
			stone.lightened(0.18))
	# тёмное основание
	t._drawer.draw_rect(Rect2(x, y + ts - face_h * EdgeLangC.BOTTOM_STRIPE,
			ts, face_h * EdgeLangC.BOTTOM_STRIPE), stone_dark)
	# напластования: 1-2 горизонтальные трещины
	var n_layers: int = 1 + t._hash(tk.x * 3, tk.y * 7, 2)
	for i in n_layers:
		var cy := y0 + lip_h + (face_h - lip_h) * (0.42 + 0.26 * float(i))
		t._drawer.draw_line(Vector2(x + 2.0, cy), Vector2(x + ts - 2.0, cy),
				Color(stone_dark, 0.6), 1.4)
	# вертикальные трещины кладки: 1-2 по хэшу (фактура «блоков»)
	var n_cracks: int = t._hash(tk.x * 7, tk.y * 5, 3)
	for i in n_cracks:
		var h: int = t._hash(tk.x * 11 + i, tk.y * 13 + i, 100)
		var cx := x + 4.0 + float(h % int(ts - 8.0))
		var cy0 := y0 + lip_h + 2.0
		var cy1 := y + ts - face_h * EdgeLangC.BOTTOM_STRIPE + 2.0
		t._drawer.draw_line(Vector2(cx, cy0), Vector2(cx + 1.0, cy1),
				Color(stone_dark, 0.45), 1.2)
	# губа: тёмная трава нависает над обрывом
	t._drawer.draw_rect(Rect2(x, y0, ts, lip_h),
			grass.darkened(opt("lip_dark", 0.24)))
	# пучки травы свисают с губы (референс 6: кромка «бахромится»)
	for i in 2 + t._hash(tk.x, tk.y, 2):
		var h2: int = t._hash(tk.x * 17 + i, tk.y * 19 + i, 100)
		var gx := x + 3.0 + float(h2 % int(ts - 6.0))
		t._drawer.draw_line(Vector2(gx, y0 + lip_h),
				Vector2(gx + 1.0, y0 + lip_h + 4.0 + float(h2 % 3)),
				grass.darkened(0.16), 1.4)
	# контактная тень у подножия + мягкие полосы на траве (обрыв высокий)
	t._drawer.draw_line(Vector2(x, y + ts + 3.0), Vector2(x + ts, y + ts + 3.0),
			Color(stone_dark.darkened(0.2), 0.8), 2.0)
	EdgeLangC.draw_foot_shadow(t._drawer, x, y + ts, ts, ts, 2,
			opt("shadow_alpha", 0.20))


## Руда: кристаллы на лужайке (железо/золото) — видно, куда ставить шахту.
func _draw_ore(tk: Vector2i, origin: Vector2, ts: float) -> void:
	var gold: bool = t._hash(tk.x, tk.y, 4) == 0
	var col := Color("#e0b13e") if gold else Color("#b0684a")
	for i in 3:
		var h: int = t._hash(tk.x * 13 + i, tk.y * 17 + i, 100)
		var fx := origin.x + 6.0 + float(h % int(ts - 12.0))
		var fy := origin.y + 8.0 + float((h / 3) % int(ts - 14.0))
		t._draw_diamond(Vector2(fx, fy), 2.4 + float(h % 3), col)
		t._draw_diamond(Vector2(fx - 1.0, fy - 1.2), 1.1, col.lightened(0.4))


## Редкий декор лужайки на верху гряды: пучки травы, цветы, мелкие валуны.
func _draw_top_decor(tk: Vector2i, x: float, y: float, ts: float) -> void:
	var h: int = t._hash(tk.x * 3, tk.y * 5, 100)
	if h % 5 == 0:
		# пучок травы
		var grass: Color = t.colors.get("grass", Color("#5ca046"))
		var bx := x + 6.0 + float(t._hash(tk.x, tk.y * 7, 100) % int(ts - 12.0))
		var by := y + 8.0 + float(t._hash(tk.x * 7, tk.y, 100) % int(ts - 14.0))
		for i in 3:
			t._drawer.draw_line(Vector2(bx + float(i) * 2.2, by),
					Vector2(bx + float(i) * 2.2 + 1.0, by - 4.0 - float(i % 2)),
					grass.lightened(0.1 * float(i % 2)), 1.3)
	elif h % 11 == 0 and _pebble_texs[0] != null:
		# мелкий валун на лужайке
		var pt: Texture2D = _pebble_texs[t._hash(tk.x, tk.y, _pebble_texs.size())]
		var s := ts * 0.42
		var sc := s / float(pt.get_height())
		t._drawer.draw_texture_rect(pt,
				Rect2(Vector2(x + ts * 0.3, y + ts * 0.3), Vector2(pt.get_width() * sc, s)),
				false)
	elif h % 17 == 0:
		# цветок
		var c := Vector2(x, y) + Vector2(8.0 + float(t._hash(tk.x, tk.y, 13) % 16),
				8.0 + float(t._hash(tk.y, tk.x, 13) % 16))
		t._drawer.draw_circle(c, 1.4, Color("#e8d44d"))
		t._drawer.draw_circle(c + Vector2(0, -1.2), 0.8, Color("#f2f0e4"))


## Трещины выработки — на обрыве тайла (шапка разбита).
func _draw_cracks(tk: Vector2i, x: float, y: float, ts: float) -> void:
	var frac: float = clampf(float(t.map.rock_hp[tk]) / maxf(1.0, t._rock_hp_default), 0.0, 1.0)
	var face_h := ts * opt("face_h", 0.58)
	var mid := y + ts - face_h * 0.5
	if frac < 0.66:
		t._drawer.draw_line(Vector2(x + ts * 0.3, mid - 3.0),
				Vector2(x + ts * 0.45, mid + 4.0), Color(0.08, 0.09, 0.11, 0.9), 1.6)
	if frac < 0.33:
		t._drawer.draw_line(Vector2(x + ts * 0.65, mid - 5.0),
				Vector2(x + ts * 0.55, mid + 2.0), Color(0.08, 0.09, 0.11, 0.9), 1.4)


## ВЫРАБОТАННЫЙ тайл («шапка» снята — видно камень, поручение заказчика
## v1.39.1): фактурный камень + щебень по краям. Ставится на место
## добытой скалы; шахта добывает дальше.
func draw_deadrock(x: int, y: int, rect: Rect2, ts: float) -> void:
	var stex: Texture2D = _stone_texs[t._hash(x, y, _stone_texs.size())]
	if stex != null:
		t._drawer.draw_texture_rect_region(stex, rect, Rect2(0, 0, TS, TS))
	else:
		t._drawer.draw_rect(rect, base_color().darkened(0.1))
	# щебень: пара тёмных сколов по хэшу — камень «тронут»
	for i in 3:
		var h: int = t._hash(x * 7 + i, y * 13 + i, 100)
		var cx := rect.position.x + 4.0 + float(h % int(ts - 8.0))
		var cy := rect.position.y + 4.0 + float((h / 7) % int(ts - 8.0))
		t._drawer.draw_circle(Vector2(cx, cy), 1.2 + float(h % 2),
				Color(0.10, 0.11, 0.13, 0.5))
	# намёк на жилы под породой — редкий металлический блик
	if t._hash(x, y * 3, 4) == 0:
		t._drawer.draw_circle(rect.get_center() + Vector2(3.0, -4.0), 1.4,
				Color("#8a7f6a"))


## Зелёная «юбка» у подножия обрыва: травинки на траве южнее.
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
