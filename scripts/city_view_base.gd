# Часть: отрисовка города — кэши, setup, главный _draw, живой слой (трава/вода/
# площадь/поля), псевдо-3D «lift» и композиты деревьев.
# Структура v1.62.0: бывший city_view.gd (1588 строк) разрезан на
# extends-цепочку Node2D (city_view_base -> city_view_nature -> city_view.gd) —
# это один класс, сцена создаёт его по-прежнему через city_view.gd.
extends Node2D

const Assets := preload("res://scripts/assets.gd")
## Отрисовка города (M2): тайлы ландшафта, аномалия, здания/стройплощадки,
## жители, призрак стройки. Цветные примитивы — пиксель-арт в M8.
## M6: дороги, зоны с прогрессом обустройства, кучи ресурсов у зданий,
## груз носильщика, предпросмотр выделения зоны.

var map = null
var sim = null
var fauna_cfg: Dictionary = {}   # data/fauna.json — виды дикой фауны города
var colors: Dictionary = {}
var build_mode := ""            # выбранный тип здания (призрак под мышью)
var enchant_mode := ""          # выбранное зачарование (подсветка здания)
var enchant_colors: Dictionary = {}
var zone_mode := ""             # инструмент зоны (M6): выделение областью
var road_mode := false          # инструмент дороги (M6): рисование мышью
var plant_mode := false         # инструмент посадки леса (M11)
var move_mode := false          # инструмент переноса зданий (этап 2, аспект 5)
var move_bld_id := -1           # здание, снятое для переноса (id), -1 — не выбрано
var plaza_mode := false         # перенос главной площади (правки v1.20)


## Призрак площади 2×2 под курсором: зелёный — годное место, красный — нет.
func _draw_plaza_ghost() -> void:
	var ts := float(map.ts)
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	# проверка без переноса: границы + здания на клетках
	var ok := true
	for dy in 2:
		for dx in 2:
			var c: Vector2i = tile + Vector2i(dx, dy)
			if not map.in_bounds(c) or c == map.anomaly_tile \
					or not sim.building_at(c).is_empty():
				ok = false
	var col := Color(0.6, 0.9, 1.0, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	var rect := Rect2(Vector2(tile) * ts, Vector2(ts * 2.0, ts * 2.0))
	draw_rect(rect, col)
	draw_rect(rect.grow(-2), Color(col.r, col.g, col.b, 0.9), false, 2.0)
var dragging := false           # ЛКМ зажата — идёт выделение/рисование
var drag_from := Vector2i(-1, -1)
var drag_to := Vector2i(-1, -1)

var _prof_colors: Dictionary = {}
var _prof_sprites: Dictionary = {}
var _label_cache: Dictionary = {}   # type_id -> [текст, ширина] (v1.21.4)
var _hp_max_cache: Dictionary = {}  # type_id -> запас прочности (v1.21.4)
var _work_cache: Dictionary = {}    # type_id -> build_work (v1.21.4)
var _bld_fill: Dictionary = {}      # тип здания → цвет категории (схематичный режим)
var _bld_short: Dictionary = {}     # тип здания → ключ краткой подписи (bld.short.*)
var _bld_loc: Dictionary = {}       # тип здания → ключ полного названия (bld.*)
var _zone_colors: Dictionary = {}
var city = null                 # сцена города — для проверки цели зачарования (неглубокая ссылка)
# v1.36.1 (правка приёмки «нет ощущения подъёма»): сглаженный визуальный
# подъём юнитов по уровням рельефа — ключ → текущий подъём в пикселях.
# Стоящий на плато юнит выше равнины на уровень×lift; по лестнице высота
# ДОЕЗЖАЕТ к цели (lift_time на уровень) — герой именно поднимается.
var _lift_db: Dictionary = {}

# цвета куч по ресурсу (M6)
var _pile_colors := {
	"wood": Color("#8d6e63"), "stone": Color("#9e9e9e"), "food": Color("#8bc34a"),
	"iron": Color("#b0684a"), "metal": Color("#cfd8dc"), "tools": Color("#78909c"),
	"kits": Color("#ffb74d"), "crystal": Color("#b46ee0"), "seeds": Color("#c9b458"),
	"gems": Color("#e0b13e"),
}
# спрайты куч (M9): мешок/брёвна/камень — по главному ресурсу
const PILE_SPRITES := {
	"wood": "k:75", "stone": "k:102", "food": "k:126", "iron": "k:102",
	"metal": "k:102", "tools": "k:104", "kits": "k:103", "crystal": "k:116",
	"seeds": "k:126", "gems": "k:116",
}


func setup(city_map, city_sim, city_cfg: Dictionary) -> void:
	map = city_map
	sim = city_sim
	# виды дикой фауны (M14-C правка): цвета и размеры из data/fauna.json
	var f := FileAccess.open("res://data/fauna.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		fauna_cfg = parsed if parsed is Dictionary else {}
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		# v1.34.1: water_tune — словарь тюнинга (не цвет), его не парсим
		if c[key] is String:
			colors[key] = Color(String(c[key]))
		elif c[key] is Dictionary:
			colors[key] = c[key]
	for prof in city_cfg["professions"]:
		_prof_colors[String(prof["id"])] = Color(String(prof["color"]))
		_prof_sprites[String(prof["id"])] = String(prof.get("sprite", ""))
	# схематичный режим (этап 2, аспект 1): цвет здания — цвет его категории
	var cat_colors: Dictionary = {}
	for cid in city_cfg.get("cats", {}):
		cat_colors[String(cid)] = Color(String(city_cfg["cats"][cid]["color"]))
	for b in city_cfg["buildings"]:
		_bld_fill[String(b["id"])] = cat_colors.get(String(b.get("cat", "")), Color(0.91, 0.85, 0.62))
		_bld_short[String(b["id"])] = String(b.get("short", ""))
		_bld_loc[String(b["id"])] = String(b.get("loc", ""))
	for t in city_cfg.get("zones", {}).get("types", {}):
		_zone_colors[String(t)] = Color(String(city_cfg["zones"]["types"][t]["color"]))
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	# видимая область мира (v1.21.5): за камерой не рисуем — раньше деревья
	# и дороги всей карты уходили в кадр даже за экраном
	var xf := get_viewport_transform()
	_vis = (xf.affine_inverse() * get_viewport_rect()).grow(float(map.ts) * 3.0)
	# v1.50 (FPS): уровень детализации — при отдалении (<1.5) покачивание
	# травинок и блики воды мельче пикселя — не рисуем вовсе
	_zoom = 0.0
	var hero_node: Node = city.hero if city != null else null
	if hero_node != null:
		var cam: Node = hero_node.get_node_or_null("Camera")
		if cam != null and (cam is Camera2D):
			_zoom = float((cam as Camera2D).zoom.x)
	var lod := _zoom >= 1.5
	# земля (зоны/дороги/плиты площади) запечена в текстуру ландшафта
	# city_terrain.gd (v1.22); v1.50: декор луга (цветы/камешки/кусты)
	# тоже в запечке — живой слой не платит за него каждый кадр
	_draw_plaza_pulse()
	_draw_field_live()
	if lod:
		# v1.52: три яруса детализации — чем дальше камера, тем реже
		# живые травинки и блики (мельче пикселя — глаз не отличит,
		# команд в разы меньше)
		_grass_step = 4 if _zoom < 2.2 else 2
		_draw_water_glints()
		_draw_swaying_grass()
	_draw_hive()
	_draw_anomaly()
	_draw_world_exit()
	_draw_world_sorted()
	_draw_ghost()

var _zoom := 2.0        # текущий зум камеры города (v1.50: LOD живых деталей)
var _grass_step := 2    # v1.52: шаг прореживания травы/бликов по зуму


## Прямоугольник карты, видимый камерой (запас 3 тайла на высокие деревья).
const HIVE_HP_MAX := 150.0   # = hive_sim.HP
var _vis := Rect2(-1e9, -1e9, 2e9, 2e9)


## Живой блеск воды (v1.27): медленные светлые штрихи на водных тайлах —
## пруды «дышат» на солнце. Список тайлов воды постоянен — считается один раз.


## Колышущаяся трава (v1.28): кончики травинок качаются по синусу — луга
## «дышат» ветром. Каждая вторая трава по хэшу, только видимая область.


func _draw_swaying_grass() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	# v1.43 (карта ×4): цикл по ВИДИМОЙ области — перебор 50к тайлов карты
	# на каждый кадр ронял город до ~20 FPS; видимых тайлов ~2к
	var x0 := clampi(int(_vis.position.x / ts) - 1, 0, map.w - 1)
	var y0 := clampi(int(_vis.position.y / ts) - 1, 0, map.h - 1)
	var x1 := clampi(int(_vis.end.x / ts) + 1, 0, map.w - 1)
	var y1 := clampi(int(_vis.end.y / ts) + 1, 0, map.h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if map.grid[y][x] != map.TILE_GRASS or _hash(x, y, 3) % _grass_step != 0:
				continue
			var t := Vector2i(x, y)
			var ph := float(t.x * 5 + t.y * 11)
			var sway := sin(_anim_time * 1.9 + ph) * 2.0
			var base := Vector2(t) * ts + Vector2(ts * (0.3 + 0.4 * sin(ph * 0.7)), ts * 0.78)
			var tip := base + Vector2(sway, -7.0)
			var tip2 := base + Vector2(-sway * 0.7 + 2.0, -5.0)
			# v1.32: в тон текстурной траве (grass L/M/D)
			draw_line(base, tip, Color("#3f7a34"), 1.1)
			draw_line(base + Vector2(2.0, 0), tip2, Color("#66aa50"), 1.0)


func _draw_water_glints() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	# v1.43 (карта ×4): цикл по ВИДИМОЙ области (см. _draw_swaying_grass)
	var x0 := clampi(int(_vis.position.x / ts) - 1, 0, map.w - 1)
	var y0 := clampi(int(_vis.position.y / ts) - 1, 0, map.h - 1)
	var x1 := clampi(int(_vis.end.x / ts) + 1, 0, map.w - 1)
	var y1 := clampi(int(_vis.end.y / ts) + 1, 0, map.h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if map.grid[y][x] != map.TILE_WATER:
				continue
			var t := Vector2i(x, y)
			# плотность бликов прорежена хэшем (FPS-замер 2026-10-27): мерцает
			# половина тайлов — картинка та же, команд вдвое меньше
			if _hash(t.x, t.y, 3) % _grass_step == 0:
				continue
			var ph := float(t.x * 7 + t.y * 13)
			var s := sin(_anim_time * 1.6 + ph)
			if s < 0.25:
				continue
			var c := Vector2(t) * ts + Vector2(ts * (0.35 + 0.3 * sin(ph * 0.7)), ts * 0.55)
			var w := ts * (0.14 + 0.07 * s)
			# v1.31: солнечные блики гаснут ночью (слабее в ~6 раз и холоднее) —
			# вода ночью ТЁМНАЯ (замечание заказчика «река становится белой»)
			var day := 1.0 - 0.85 * night
			var gcol := Color(1.0, 1.0, 0.95).lerp(Color(0.55, 0.65, 0.9), night)
			draw_line(c - Vector2(w, 0), c + Vector2(w, 0),
					Color(gcol.r, gcol.g, gcol.b, (s - 0.25) * 0.30 * day), 1.2)


## Пульс «места сбора» на площади (правки v1.20): плиты рисует статичный
## слой, здесь только дышащий круг — планёрка собирается по утрам.
func _draw_plaza_pulse() -> void:
	if sim.plaza == Vector2i(-1, -1):
		return
	var ts := float(map.ts)
	var center := Vector2(sim.plaza) * ts + Vector2(ts, ts)
	var pulse := 0.5 + 0.5 * sin(_anim_time * 2.0)
	draw_circle(center, ts * 0.34, Color(0.98, 0.95, 0.85, 0.25 + 0.2 * pulse))


## Живой слой полей (v1.22): заливки/борозды/заборы запечены в ландшафт
## (city_terrain.gd), здесь — то, что меняется часто: растения стадиями
## (печёные спрайты v1.21.5), полосы обустройства неготовых клеток
## и тёплый пульс спелых грядок.
func _draw_field_live() -> void:
	var fill_work: float = float(sim.cfg.get("zones", {}).get("fill_work", 4.0))
	for z in sim.zones:
		var cells: Array = z["cells"]
		var progress: Array = z["progress"]
		var crops: Array = z.get("crops", [])
		var is_field := String(z["type"]) == "field"
		var crop_vis := 0
		if is_field:
			var crop_id := String(z.get("crop", "turnip"))
			if not _crop_vis_cache.has(crop_id):
				_crop_vis_cache[crop_id] = int(sim.crop_def(crop_id).get("sprite", 0))
			crop_vis = int(_crop_vis_cache[crop_id])
		for i in cells.size():
			var rect := Rect2(Vector2(cells[i]) * map.ts, Vector2(map.ts, map.ts))
			if not _vis.intersects(rect):
				continue
			var filled: bool = float(progress[i]) >= fill_work
			if not filled:
				# полоса обустройства: живая, двигается с каждым ударом лопаты
				var frac := clampf(float(progress[i]) / maxf(0.1, fill_work), 0.0, 1.0)
				draw_rect(Rect2(rect.position + Vector2(4, map.ts - 8), Vector2((map.ts - 8) * frac, 4)),
						Color("#ffe082"))
				continue
			if not is_field or i >= crops.size() or (crops[i] as Dictionary).is_empty():
				continue
			var crop: Dictionary = crops[i]
			var stage := int(crop.get("stage", 0)) + (1 if bool(crop.get("ripe", false)) else 0)
			var base := rect.get_center() + Vector2(0.0, map.ts * 0.22)
			var tex := _crop_sprite(crop_vis, clampi(stage, 0, 4))
			draw_texture_rect(tex, Rect2(base - Vector2(11.0, 17.0), Vector2(22.0, 22.0)), false)
			if bool(crop.get("ripe", false)):
				var glow := Color(1.0, 0.95, 0.6, 0.25 + 0.12 * sin(_anim_time * 3.0))
				draw_circle(base + Vector2(0, -6), 7.5, glow)


## Печёные спрайты растений (v1.21.5, возвращены в живой слой в v1.22):
## стадия культуры — маленькая текстура в кэше; вид 3 — золотой колос
## пшеницы (сезонная культура v1.22).
var _crop_sprites: Dictionary = {}
var _crop_vis_cache: Dictionary = {}


func _px_circle(img: Image, c: Vector2, r: float, col: Color) -> void:
	var x0 := maxi(0, int(floor(c.x - r - 1.0)))
	var x1 := mini(img.get_width() - 1, int(ceil(c.x + r + 1.0)))
	var y0 := maxi(0, int(floor(c.y - r - 1.0)))
	var y1 := mini(img.get_height() - 1, int(ceil(c.y + r + 1.0)))
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			if Vector2(px + 0.5, py + 0.5).distance_to(c) <= r:
				img.set_pixel(px, py, col)


func _crop_sprite(crop_vis: int, stage: int) -> ImageTexture:
	var key := "%d|%d" % [crop_vis, stage]
	if _crop_sprites.has(key):
		return _crop_sprites[key]
	var leaf := Color("#5fae4a")
	var leaf_dark := Color("#3f7a33")
	var stem := Color("#4c8a3c")
	var fruit := Color("#c9a8e8")
	var fruit_r := 3.4
	if crop_vis == 2:
		fruit = Color("#e8892c")
		fruit_r = 4.2
	elif crop_vis == 4:
		# хмель: светло-зелёные шишки
		fruit = Color("#a8c860")
		fruit_r = 2.6
	elif crop_vis == 5:
		# виноград: фиолетовые грозди
		fruit = Color("#9a5ab0")
		fruit_r = 2.6
	elif crop_vis == 3:
		# пшеница (v1.22): золотой колос
		leaf = Color("#b7a44a")
		leaf_dark = Color("#93803a")
		stem = Color("#a89a4e")
		fruit = Color("#e8cf6d")
		fruit_r = 3.8
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	var base := Vector2(11.0, 17.0)
	match clampi(stage, 0, 4):
		0:
			_px_circle(img, base + Vector2(-2, -4), 1.6, leaf)
			_px_circle(img, base + Vector2(2, -4), 1.6, leaf)
			_px_circle(img, base + Vector2(0, -2), 1.0, stem)
		1:
			_px_circle(img, base + Vector2(-3, -7), 2.4, leaf)
			_px_circle(img, base + Vector2(3, -7), 2.4, leaf)
			_px_circle(img, base + Vector2(0, -10), 2.0, leaf_dark)
			_px_circle(img, base + Vector2(0, -4), 1.2, stem)
		2:
			_px_circle(img, base + Vector2(-4, -9), 3.2, leaf)
			_px_circle(img, base + Vector2(4, -9), 3.2, leaf)
			_px_circle(img, base + Vector2(0, -12), 3.0, leaf_dark)
			_px_circle(img, base + Vector2(0, -6), 2.2, leaf)
			_px_circle(img, base + Vector2(0, -3), 1.2, stem)
		_:
			_px_circle(img, base + Vector2(-4, -9), 3.0, leaf)
			_px_circle(img, base + Vector2(4, -9), 3.0, leaf)
			_px_circle(img, base + Vector2(0, -5), fruit_r, fruit)
			_px_circle(img, base + Vector2(-1, -6), 1.2, fruit.lightened(0.35))
			_px_circle(img, base + Vector2(0, -3), 1.2, stem)
	var tex := ImageTexture.create_from_image(img)
	_crop_sprites[key] = tex
	return tex


var _anim_time := 0.0
var night := 0.0               # 0..1 — фактор ночи (задаёт city.gd, v1.31)

# кэш тайлов деревьев/пней/саженцев (M12): ландшафт меняется редко —
# список пересобирается по флагу, который ставит сцена при sim.terrain_dirty.
# v1.21.5: кэш предрасчитан до готовых дескрипторов отрисовки (текстура,
# прямоугольники, тень) и отсортирован по Y — в кадре только выдача команд.
# v1.22: тень впечена в текстуру дерева — 1 команда вместо 2, а статичные
# дескрипторы (деревья + здания) сливаются с коротким динамическим списком
# без общей пересортировки кадра.
var _trees_dirty := true
var _trees_cache: Array = []
var _static_sorted: Array = []      # [y, kind, payload] деревья+здания, готово к слиянию
var _static_sorted_blds := -1       # размер sim.buildings при сборке (смена — пересобрать)
var _hero_px := Vector2.INF         # v1.50: герой для прозрачности деревьев


## v1.50 (FPS): первый индекс статики, чья линия ног вошла в видимую
## полосу (список отсортирован по y — двоичный поиск, не линейный проход).
func _static_window_start() -> int:
	var y_min := _vis.position.y - float(map.ts) * 3.0
	var lo := 0
	var hi := _static_sorted.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(_static_sorted[mid][0]) < y_min:
			lo = mid + 1
		else:
			hi = mid
	return lo

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()


## Высота юнита в пикселях (уровень тайла × lift) — мгновенное значение.
func _lift_target(pos: Vector2) -> float:
	return float(map.height_at(map.tile_of_px(pos))) * map.plateau_lift_px()


## Сглаженный подъём юнита: высота анимируется к цели со скоростью
## «один уровень за lift_time» — на лестнице виден шаг вверх/вниз. Ключи —
## id юнитов; на равнине записи не копятся (стираются при нуле).
func _entity_lift(key: String, pos: Vector2) -> float:
	if _lift_db.size() > 512:
		_lift_db.clear()   # после больших волн: перезаймётся незаметно
	var target := _lift_target(pos)
	if not _lift_db.has(key):
		_lift_db[key] = target
		return target
	var cur: float = _lift_db[key]
	if cur != target:
		var speed: float = map.plateau_lift_px() / map.plateau_lift_time()
		cur = move_toward(cur, target, speed * get_process_delta_time())
	if cur == 0.0 and target == 0.0:
		_lift_db.erase(key)
	else:
		_lift_db[key] = cur
	return cur


## Подъём статичного объекта (дерево/здание/куча) — без анимации,
## статика не ходит: просто уровень × lift.
func _static_lift(tile: Vector2i) -> float:
	return float(map.height_at(tile)) * map.plateau_lift_px()


## Подъём здания: прямоугольник 2×2 может стоять на кромке двух уровней —
## берём МАКСИМАЛЬНЫЙ уровень клеток, вся коробка на одной высоте.
func _bld_lift(b: Dictionary) -> float:
	var t: Vector2i = b["tile"]
	var w: int = sim.bld_w(b)
	var lv := 0
	for dy in w:
		for dx in w:
			lv = maxi(lv, map.height_at(t + Vector2i(dx, dy)))
	return float(lv) * map.plateau_lift_px()


## Пересобрать кэш деревьев (вызывает city.gd при sim.terrain_dirty).
## v1.22: заодно пересобирается статичный сортированный набор (деревья+здания)
## — снос/перенос здания тоже меняет порядок слоя.
func mark_trees_dirty() -> void:
	_trees_dirty = true
	_static_sorted_blds = -1


## Дескриптор дерева/пня/саженца: всё, что не меняется между кадрами.
## [y_px, kind, tile, tex, src, dst, точка-якорь, тень-r (пень)]
## v1.22: у дерева tex — композит «спрайт + тень» (печётся один раз на вид
## дерева), в кадре одна команда текстуры вместо круга тени + спрайта.
func _build_tree_desc(tile: Vector2i, ts: float) -> Array:
	var bottom := Vector2(tile.x * ts + ts / 2.0, tile.y * ts + ts * 0.92)
	# v1.36.1: дерево на плато стоит выше равнины — вся статика плато
	# приподнята на уровень×lift, одна плоскость с юнитами
	bottom.y -= _static_lift(tile)
	if map.saplings.has(tile):
		return [bottom.y, "sapling", tile, null, Rect2(), Rect2(), bottom, 0.0]
	var kind: int = map.tree_kind(tile)
	if map.grid[tile.y][tile.x] != map.TILE_TREE:
		return [bottom.y, "stump", tile, null, Rect2(), Rect2(), bottom, ts * 0.3]
	var scale := ts * 1.9 if kind == map.TREE_SMALL \
			else (ts * 2.4 if kind == map.TREE_MEDIUM else ts * 3.0)
	var ref: String = TREE_REFS[_hash(tile.x, tile.y, TREE_REFS.size())]
	# тёмный лес у болот (v1.39.2, заказчик): деревья в 2 тайлах от воды
	# болота рисуются затемнёнными вариантами (мрачная хвоя/ива)
	if _near_swamp(tile):
		# хвоя чаще (компактнее), огромная ива — редкость
		ref = "e:tree2_dark_pine" if _hash(tile.x, tile.y, 5) < 4 else "e:tree2_dark_willow" 
	var t: Texture2D = Assets.sprite(ref)
	var src := Rect2(Vector2.ZERO, t.get_size())
	if t is AtlasTexture:
		src = (t as AtlasTexture).region
	var s := scale / float(t.get_height())
	var w := t.get_width() * s
	# природный сдвиг (v1.27): деревья не стоят по разметке сетки —
	# лёгкий детерминированный дрейф точки посадки по хэшу тайла
	var jit := Vector2(float(_hash(tile.x * 3, tile.y, 5) - 2), float(_hash(tile.x, tile.y * 3, 5) - 2))
	var pos := bottom + Vector2(0, -2) + jit * (ts * 0.035)
	# композит: спрайт + тень под ним; dst растянут пропорционально, низ
	# спрайта попадает в ту же точку «посадки», что и раньше
	var comp: ImageTexture = _tree_composite(ref, t, src)
	var cw := float(comp.get_width()) / maxf(1.0, src.size.x)
	var ch := float(comp.get_height()) / maxf(1.0, src.size.y)
	var dst := Rect2(Vector2(pos.x - w * cw * 0.5, pos.y - scale), Vector2(w * cw, scale * ch))
	return [bottom.y, "tree", tile, comp, Rect2(Vector2.ZERO, comp.get_size()), dst, bottom, 0.0]


## Композит дерева (v1.22): спрайт дерева печётся в одну текстуру один раз
## на вид дерева. v1.28: статичная тень-эллипс УДАЛЕНА — она дублировала
## динамическую тень от солнца/луны (city_sky.gd), у дерева было ДВЕ тени.
var _tree_comp_cache: Dictionary = {}


func _tree_composite(ref: String, t: Texture2D, src: Rect2) -> ImageTexture:
	if _tree_comp_cache.has(ref):
		return _tree_comp_cache[ref]
	var sheet: Image = null
	if t is AtlasTexture:
		sheet = (t as AtlasTexture).atlas.get_image()
	else:
		sheet = t.get_image()
	var pad := int(round(src.size.x * 0.2))
	var cw := int(round(src.size.x)) + pad * 2
	var chh := int(round(src.size.y))
	var img := Image.create(cw, chh, false, Image.FORMAT_RGBA8)
	img.blit_rect(sheet, Rect2i(src), Vector2i(pad, 0))
	# v1.29.4: контактная тень у корней — дерево «стоит на земле», а не висит
	# над динамической тенью от солнца (замечание заказчика)
	var ry := maxf(2.0, chh * 0.055)
	var cy := chh - ry * 0.6
	for py in range(maxi(0, int(cy - ry)), mini(chh, int(cy + ry))):
		for px in range(maxi(0, int(pad - cw * 0.28)), mini(cw, int(pad + cw * 0.28))):
			var nx := float(px - pad) / (cw * 0.28)
			var ny := float(py - cy) / ry
			var d := nx * nx + ny * ny
			if d <= 1.0:
				var a := 0.22 * (1.0 - d * 0.55)
				var under := img.get_pixel(px, py)
				img.set_pixel(px, py, under.lerp(Color(0.06, 0.06, 0.09), a))
	var tex := ImageTexture.create_from_image(img)
	_tree_comp_cache[ref] = tex
	return tex


## Единый Y-сортированный слой (M12): деревья, пни, саженцы, здания, кучи,
## животные, скот, рейдеры, жители и герой рисуются в порядке «линии ног» —
## нижние объекты перекрывают верхние, никто не проваливается сквозь текстуры.
## v1.22: деревья и здания — редкоменяющийся «статичный» набор, он держится
## отсортированным в _static_sorted и в кадре СЛИВАЕТСЯ с коротким динамическим
## списком (живые существа + кучи) — вместо пересортировки всего слоя каждый кадр.


const TREE_REFS := ["e:tree2_red", "e:tree2_pine", "e:tree2_birch",
		"e:tree2_teal", "e:tree2_willow"]


const DARK_TREE_REFS := ["e:tree2_dark_pine", "e:tree2_dark_willow"]

static func _hash(x: int, y: int, n: int, salt: int = 0) -> int:
	var v := int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791))
	return absi(v) % maxi(1, n)


var _inside_homes: Dictionary = {}


const STUMP_PALS := [
	{"side": Color("#4a321e"), "top": Color("#64452c"), "ring": Color("#7e5c3a")},   # дуб
	{"side": Color("#3e2a1a"), "top": Color("#563c24"), "ring": Color("#6e4e30")},   # сосна
	{"side": Color("#d6d6c8"), "top": Color("#f0f0e4"), "ring": Color("#343432")},   # берёза
	{"side": Color("#4a321e"), "top": Color("#64452c"), "ring": Color("#7e5c3a")},   # осеннее
	{"side": Color("#4a321e"), "top": Color("#64452c"), "ring": Color("#7e5c3a")},   # дуб 2
	{"side": Color("#523a24"), "top": Color("#6e5032"), "ring": Color("#8a663e")},   # липа
	{"side": Color("#4a321e"), "top": Color("#64452c"), "ring": Color("#7e5c3a")},   # плодовое
	{"side": Color("#d6d6c8"), "top": Color("#f0f0e4"), "ring": Color("#343432")},   # берёза 2
	{"side": Color("#3e2a1a"), "top": Color("#563c24"), "ring": Color("#6e4e30")},   # сосна 2
	{"side": Color("#523a24"), "top": Color("#6e5032"), "ring": Color("#8a663e")},   # липа 2
]

# --- заглушки для парсера (структура v1.62.0) ------------------------------
# Базовая часть зовёт отрисовку объектов, живущую ниже по цепочке; реальные
# тела — в city_view_nature.gd и city_view.gd. Сигнатуры держите в синхроне.
func _draw_world_sorted() -> void:
	pass

func _near_swamp(tile: Vector2i) -> bool:
	return false

func _draw_anomaly() -> void:
	pass

func _draw_hive() -> void:
	pass

func _draw_world_exit() -> void:
	pass

func _draw_building(b: Dictionary) -> void:
	pass

func _draw_raider(r: Dictionary) -> void:
	pass

func _draw_resident(r: Dictionary) -> void:
	pass

func _draw_speech_bubble(pos: Vector2, text: String) -> void:
	pass

func _draw_hero(hero) -> void:
	pass

func _draw_ghost() -> void:
	pass
