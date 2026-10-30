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
	# земля (зоны/дороги/плиты площади) запечена в текстуру ландшафта
	# city_terrain.gd (v1.22); растения и полосы обустройства — живые
	_draw_plaza_pulse()
	_draw_field_live()
	_draw_water_glints()
	_draw_swaying_grass()
	_draw_anomaly()
	_draw_world_exit()
	_draw_world_sorted()
	_draw_ghost()


## Прямоугольник карты, видимый камерой (запас 3 тайла на высокие деревья).
var _vis := Rect2(-1e9, -1e9, 2e9, 2e9)


## Живой блеск воды (v1.27): медленные светлые штрихи на водных тайлах —
## пруды «дышат» на солнце. Список тайлов воды постоянен — считается один раз.
var _water_tiles: Array = []
var _water_ready := false


## Колышущаяся трава (v1.28): кончики травинок качаются по синусу — луга
## «дышат» ветром. Каждая вторая трава по хэшу, только видимая область.
var _grass_tiles: Array = []
var _grass_ready := false


func _draw_swaying_grass() -> void:
	if map == null:
		return
	if not _grass_ready:
		_grass_ready = true
		for y in map.h:
			for x in map.w:
				if map.grid[y][x] == map.TILE_GRASS and _hash(x, y, 3) % 2 == 0:
					_grass_tiles.append(Vector2i(x, y))
	var ts := float(map.ts)
	for t: Vector2i in _grass_tiles:
		var rect := Rect2(Vector2(t) * ts, Vector2(ts, ts))
		if not _vis.intersects(rect):
			continue
		var ph := float(t.x * 5 + t.y * 11)
		var sway := sin(_anim_time * 1.9 + ph) * 2.0
		var base := rect.position + Vector2(ts * (0.3 + 0.4 * sin(ph * 0.7)), ts * 0.78)
		var tip := base + Vector2(sway, -7.0)
		var tip2 := base + Vector2(-sway * 0.7 + 2.0, -5.0)
		# v1.32: в тон текстурной траве (grass L/M/D)
		draw_line(base, tip, Color("#3f7a34"), 1.1)
		draw_line(base + Vector2(2.0, 0), tip2, Color("#66aa50"), 1.0)


func _draw_water_glints() -> void:
	if map == null:
		return
	if not _water_ready:
		_water_ready = true
		for y in map.h:
			for x in map.w:
				if map.grid[y][x] == map.TILE_WATER:
					_water_tiles.append(Vector2i(x, y))
	var ts := float(map.ts)
	for t: Vector2i in _water_tiles:
		# плотность бликов прорежена хэшем (FPS-замер 2026-10-27): мерцает
		# половина тайлов — картинка та же, команд вдвое меньше
		if _hash(t.x, t.y, 3) % 2 == 0:
			continue
		var rect := Rect2(Vector2(t) * ts, Vector2(ts, ts))
		if not _vis.intersects(rect):
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
func _draw_world_sorted() -> void:
	var ts := float(map.ts)
	# обитатели внутри домов (этап 2, аспект 2): для светящихся окон
	_inside_homes.clear()
	for r in sim.residents:
		if int(r.get("inside", 0)) > 0 and r.get("home") != null and not (r["home"] as Dictionary).is_empty():
			_inside_homes[int((r["home"] as Dictionary)["id"])] = true
	if _trees_dirty:
		_trees_dirty = false
		_trees_cache = []
		for y in map.h:
			for x in map.w:
				var t: int = map.grid[y][x]
				if t == map.TILE_TREE or map.stumps.has(Vector2i(x, y)) or map.saplings.has(Vector2i(x, y)):
					_trees_cache.append(_build_tree_desc(Vector2i(x, y), ts))
		_trees_cache.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	# статичный набор (деревья + здания) пересобирается только когда ландшафт
	# или список зданий меняются; в кадре он готов к слиянию
	if _static_sorted_blds != sim.buildings.size():
		_static_sorted_blds = sim.buildings.size()
		_static_sorted = _trees_cache.duplicate(false)
		for b in sim.buildings:
			# Y-якорь — нижняя линия прямоугольника здания (2×2: tile.y + 1);
			# v1.36.1: здание на плато приподнято вместе с плоскостью плато
			var bw: int = sim.bld_w(b)
			_static_sorted.append([float(Vector2(b["tile"]).y + bw - 1) * ts + ts - 2.0
					- _bld_lift(b), "bld", b])
		_static_sorted.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	# динамический набор — короткий: брёвна, останки, кучи, звери, скот, люди, герой
	var dyn: Array = []
	# поваленные брёвна (v1.21.2): герой валит — лесопилка унесёт и распилит
	for tile: Vector2i in map.logs.keys():
		dyn.append([float(tile.y) * ts + ts * 0.78 - _static_lift(tile), "log", tile])
	# останки павших врагов (v1.23): лежат, пока кто-то не снесёт на кладбище
	for c in sim.corpses:
		var ct: Vector2i = c["tile"]
		dyn.append([float(ct.y) * ts + ts * 0.7 - _static_lift(ct), "corpse", c])
	for b in sim.buildings:
		if bool(b["done"]) and (b as Dictionary).has("pile") and _pile_total(b) >= 0.5:
			dyn.append([float(Vector2(b["tile"]).y + sim.bld_w(b) - 1) * ts + ts * 0.88
					- _bld_lift(b), "pile", b])
	for a in sim.animals:
		dyn.append([Vector2(a["pos"]).y, "animal", a])
	for a in sim.livestock:
		dyn.append([Vector2(a["pos"]).y, "stock", a])
	for w in sim.wanderers:
		dyn.append([Vector2(w["pos"]).y, "wanderer", w])
	for r in sim.raiders:
		dyn.append([Vector2(r["pos"]).y, "raider", r])
	for r in sim.residents:
		if int(r.get("inside", 0)) > 0:
			continue   # спит/лежит/прячется внутри дома — с карты не виден
		dyn.append([Vector2(r["pos"]).y, "res", r])
	if city != null and city.hero != null and not city.hero.dead:
		dyn.append([city.hero.global_position.y, "hero", city.hero])
	dyn.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	_draw_campfire()
	_draw_founded_cemetery()   # могилы кладбища без здания (v1.23)
	# слияние двух отсортированных списков: O(n+m) вместо sort всей карты
	var si := 0
	var di := 0
	while si < _static_sorted.size() or di < dyn.size():
		var e: Array
		if di >= dyn.size():
			e = _static_sorted[si]
			si += 1
		elif si >= _static_sorted.size() or float(dyn[di][0]) < float(_static_sorted[si][0]):
			e = dyn[di]
			di += 1
		else:
			e = _static_sorted[si]
			si += 1
		match String(e[1]):
			"tree":
				# v1.21.5: дескриптор из кэша; v1.22: тень впечена в текстуру
				if not _vis.intersects(e[5]):
					continue   # за экраном — дерево целиком пропускаем
				draw_texture_rect_region(e[3], e[5], e[4])
			"sapling":
				if not _vis.has_point(e[6]):
					continue
				_draw_sapling(e[2], e[6], ts)
			"stump":
				if not _vis.has_point(e[6]):
					continue
				_draw_stump(e[6], ts, _hash(e[2].x, e[2].y, STUMP_PALS.size()))
			"log":
				_draw_log_at(e[2])
			"corpse":
				_draw_corpse(e[2])
			"bld":
				_draw_building(e[2])
			"pile":
				_draw_pile(e[2])
			"animal":
				_draw_animal(e[2])
			"stock":
				_draw_stock(e[2])
			"wanderer":
				_draw_wanderer(e[2])
			"raider":
				_draw_raider(e[2])
			"res":
				_draw_resident(e[2])
			"hero":
				_draw_hero(e[2])


## Городской костёр (M12): горит вечером, ночью и при тревоге — точка сбора
## жителей и вечерних посиделок (рисуется под сортированным слоем).
func _draw_campfire() -> void:
	var fire := _fire_tile()
	var evening := false
	var day_len := float(sim.cfg["day_length"])
	var life: Dictionary = sim.cfg.get("life", {})
	var t := fmod(sim.time, day_len) / day_len
	var nf := float(sim.cfg["night_fraction"])
	evening = t >= maxf(0.0, 1.0 - nf - float(life.get("evening_len", 0.14)))
	if not evening and not sim.is_night() and not sim._raid_warned:
		return
	var pos: Vector2 = map.tile_center_px(fire) + Vector2(0, 4)
	var glow := 0.14 + 0.05 * sin(Time.get_ticks_msec() / 180.0)
	draw_circle(pos, map.ts * 1.6, Color(1.0, 0.6, 0.25, glow))
	Assets.draw_sheet(self, "fire", int(_anim_time * 9.0) % 5, pos, map.ts * 0.9)


## Точка костра: у колодца, если он есть, иначе в центре (как в симуляции).
func _fire_tile() -> Vector2i:
	for b in sim.buildings:
		if sim._active(b) and String(b["type"]) == "well":
			return Vector2i(b["tile"]) + Vector2i(1, 0)
	return map.spawn_tile


## Могилки вокруг кладбища (M12): маленькие кресты, появляются после похорон.
## v1.23: погребальный костёр горит два дня (обряд «предать огню»), прах
## после сожжения — тёмный курган; могилы растут до grow_radius клеток.
func _draw_graves(anchor: Vector2) -> void:
	var radius_px: float = float(sim.cfg.get("cemetery", {}).get("grow_radius", 5)) * float(map.ts) + float(map.ts)
	for g in sim.graves:
		var pos: Vector2 = map.tile_center_px(Vector2i(g["tile"]))
		if pos.distance_to(anchor) > radius_px:
			continue
		if String(g.get("rite", "bury")) == "burn" and not bool(g.get("ready", false)):
			# погребальный костёр: столб и живое пламя
			draw_line(pos + Vector2(0, 2), pos + Vector2(0, -14), Color("#5d4037"), 3.0)
			var flame := 0.6 + 0.4 * sin(_anim_time * 8.0 + pos.x)
			draw_circle(pos + Vector2(0, -12), 5.0 * flame, Color(1.0, 0.55, 0.2, 0.8))
			draw_circle(pos + Vector2(0, -16), 3.0 * flame, Color(1.0, 0.75, 0.3, 0.7))
			continue
		if bool(g.get("ready", false)):
			if String(g.get("rite", "bury")) == "burn":
				# прах под тёмным курганом-плитой
				draw_circle(pos + Vector2(0, 1), 5.0, Color("#7a6a5a"))
				draw_circle(pos + Vector2(0, -1), 4.0, Color("#8d7d6d"))
				continue
			draw_line(pos + Vector2(-3, -8), pos + Vector2(3, -8), Color(0.86, 0.84, 0.78), 2.0)
			draw_line(pos + Vector2(0, -11), pos + Vector2(0, -2), Color(0.86, 0.84, 0.78), 2.0)
			draw_line(pos + Vector2(-3, 0), pos + Vector2(3, 0), Color(0.55, 0.52, 0.45), 2.0)


## Кладбище без здания (v1.23): первая могила основала место — кресты
## и оградка из колышков, пока горожане не поставят настоящее кладбище.
func _draw_founded_cemetery() -> void:
	if sim.cemetery_tile == Vector2i(-1, -1):
		return
	for b in sim.buildings:
		if sim._active(b) and String(b["type"]) == "cemetery":
			return   # есть настоящее кладбище — могилки рисует оно
	var anchor: Vector2 = map.tile_center_px(sim.cemetery_tile)
	var ts := float(map.ts)
	for n in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var p: Vector2 = map.tile_center_px(sim.cemetery_tile + n) + Vector2(0, ts * 0.3)
		draw_line(p - Vector2(3, 5), p + Vector2(3, 5), Color("#5d4037"), 2.0)
		draw_line(p + Vector2(3, -5), p - Vector2(3, 5), Color("#5d4037"), 2.0)
	_draw_graves(anchor)


## Останки павшего врага (v1.23): тёмный остов и кости — контраст с травой,
## чтобы игрок видел, что городу есть что унести на кладбище.
func _draw_corpse(c: Dictionary) -> void:
	var ts := float(map.ts)
	var pos: Vector2 = map.tile_center_px(Vector2i(c["tile"])) + Vector2(0, ts * 0.15)
	pos.y -= _static_lift(Vector2i(c["tile"]))   # v1.36.1: плоскость плато
	var rot := clampf(float(c.get("rot", 0.0)) / 3.0, 0.0, 1.0)
	var col := Color(0.24, 0.2, 0.18).lerp(Color(0.42, 0.4, 0.34), rot)
	_draw_shadow(pos + Vector2(0, 4), ts * 0.34)
	draw_circle(pos, ts * 0.26, col)
	draw_line(pos + Vector2(-5, -2), pos + Vector2(5, -2), Color(0.85, 0.82, 0.75), 1.5)
	draw_circle(pos + Vector2(-6, -2), 2.0, Color(0.85, 0.82, 0.75))
	draw_circle(pos + Vector2(6, -2), 2.0, Color(0.85, 0.82, 0.75))


## Дерево/пень/саженец (M12 — из статического слоя; v1.21.5 — деревья
## выдаются готовыми дескрипторами из _trees_cache, пень и саженец —
## редкие, рисуются как раньше). Пень подбирается под тип дерева тем же
## хешом, что выбрал спрайт. Правки v1.21: три размера дерева.


## Поваленное бревно на земле (v1.21.2): толщина по размеру дерева —
## малое/среднее/большое; лесоруб унесёт его на лесопилку.
func _draw_log_at(tile: Vector2i) -> void:
	var ts := float(map.ts)
	var c: Vector2 = map.tile_center_px(tile) + Vector2(0, ts * 0.2)
	c.y -= _static_lift(tile)   # v1.36.1: плоскость плато
	var size: int = int((map.logs[tile] as Dictionary).get("size", 1))
	var w := ts * 0.55 + ts * 0.18 * float(size)
	var col := Color("#8d6e63") if size < 3 else Color("#6d4c33")
	_draw_shadow(c + Vector2(0, 5), ts * 0.42)
	draw_rect(Rect2(c.x - w * 0.5, c.y - 5.0, w, 10.0), col)
	draw_circle(Vector2(c.x - w * 0.5, c.y), 5.0, col.lightened(0.15))
	draw_circle(Vector2(c.x + w * 0.5, c.y), 5.0, col.lightened(0.15))
	draw_line(Vector2(c.x - w * 0.5 + 2.0, c.y), Vector2(c.x + w * 0.5 - 2.0, c.y),
			col.darkened(0.25), 1.5)


## Пень: срез с годовыми кольцами и кора в палитре своего дерева.
## Порядок — по индексам TREE_REFS (v1.32: под стволы новых деревьев).
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


func _draw_stump(bottom: Vector2, ts: float, variant: int) -> void:
	var pal: Dictionary = STUMP_PALS[variant % STUMP_PALS.size()]
	_draw_shadow(bottom, ts * 0.3)
	var w := ts * 0.46
	var h := ts * 0.26
	# кора (боковина) и светлый срез сверху
	draw_rect(Rect2(bottom + Vector2(-w / 2.0, -h), Vector2(w, h)), pal["side"])
	draw_rect(Rect2(bottom + Vector2(-w / 2.0, -h * 1.7), Vector2(w, h * 0.9)), pal["top"])
	draw_arc(bottom + Vector2(0, -h * 1.25), w * 0.26, 0.0, TAU, 14, pal["ring"], 1.2)
	draw_circle(bottom + Vector2(0, -h * 1.25), w * 0.08, pal["ring"])
	# детали по типу: у берёзы — тёмные чёрточки, у плодового — живой побег,
	# у старого/осеннего — трещина
	var birch := variant == 2 or variant == 7
	var fruit := variant == 6
	var autumn := variant == 3
	if birch:
		draw_rect(Rect2(bottom + Vector2(-w * 0.36, -h * 0.75), Vector2(w * 0.18, h * 0.22)), Color("#424242"))
		draw_rect(Rect2(bottom + Vector2(w * 0.14, -h * 0.4), Vector2(w * 0.16, h * 0.2)), Color("#424242"))
	elif fruit:
		draw_line(bottom + Vector2(0, -h * 1.6), bottom + Vector2(3, -h * 2.4), Color("#7cb342"), 1.4)
		draw_circle(bottom + Vector2(3.6, -h * 2.5), 1.4, Color("#8bc34a"))
	elif autumn:
		draw_line(bottom + Vector2(-w * 0.2, -h * 1.6), bottom + Vector2(w * 0.1, -h * 0.3), Color("#4e342e"), 1.1)


# v1.32 «Деревья как в видео»: пухлые кроноблобы с дизерингом (генератор
# tools/make_video_trees.py): дуб ×2, сосна ×2, берёза ×2, липа ×2,
# осеннее и плодовое — все 10 слотов разные.
const TREE_REFS := ["e:tree_oak", "e:tree_pine", "e:tree_birch", "e:tree_autumn",
		"e:tree_oak2", "e:tree_lime", "e:tree_fruit2", "e:tree_birch2",
		"e:tree_pine2", "e:tree_lime2"]


static func _hash(x: int, y: int, n: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, n)


func _draw_shadow(pos: Vector2, radius: float) -> void:
	draw_circle(pos, radius * 0.5, Color(0, 0, 0, 0.18))


## Саженец: две стадии роста (малый росток, кустик).
func _draw_sapling(key: Vector2i, bottom: Vector2, ts: float) -> void:
	var s: Dictionary = map.saplings[key]
	var frac: float = clampf(float(s.get("t", 0.0)) / maxf(0.1, float(s.get("grow_days", 1.2))), 0.0, 1.0)
	var ref := "e:sap1" if frac < 0.5 else "e:sap2"
	_draw_shadow(bottom, ts * 0.2)
	Assets.draw_ref(self, ref, bottom, ts * (0.5 if frac < 0.5 else 0.85))


func _pile_total(b: Dictionary) -> float:
	var total := 0.0
	for k in b.get("pile", {}):
		total += float(b["pile"][k])
	return total


## Куча ресурса у здания (M6 → M12 сортированный слой).
func _draw_pile(b: Dictionary) -> void:
	var ts := float(map.ts)
	var pile: Dictionary = b["pile"]
	var total := 0.0
	var key := ""
	var best := 0.0
	for k in pile:
		total += float(pile[k])
		if float(pile[k]) > best:
			best = float(pile[k])
			key = String(k)
	if total < 0.5:
		return
	var corner: Vector2 = Vector2(b["tile"]) * ts + Vector2(ts * 0.78, ts * 0.88)
	corner.y -= _bld_lift(b)   # v1.36.1: куча стоит на плоскости плато
	var size := 8.0 + minf(10.0, total / 3.0)
	var tint: Color = _pile_colors.get(key, Color(0.8, 0.8, 0.8)).lightened(0.25)
	Assets.draw_ref(self, PILE_SPRITES.get(key, "k:73"), corner, size, false, tint)


## Дикие животные (M5.1 → M14-C правка): виды из data/fauna.json — индюк
## остался, добавились олени, кабаны, птицы и волки (векторные, в стиле мира).
func _draw_animal(a: Dictionary) -> void:
	var pos: Vector2 = a["pos"]
	# v1.36.1: зверь на плато стоит выше равнины (подъём сглаживается)
	pos.y -= _entity_lift("an%d" % int(a["id"]), a["pos"])
	var vel := Vector2.ZERO
	var pth: PackedVector2Array = a.get("path", PackedVector2Array())
	if not pth.is_empty():
		vel = pth[0] - pos
	var kind := String(a.get("kind", "turkey"))
	if kind == "deer" or kind == "boar" or kind == "wolf" or kind == "bird":
		_draw_fauna_animal(a, kind, pos, vel)
		return
	Assets.draw_animal(self, "turkey", Assets.dir_of(vel), not pth.is_empty(),
			pos + Vector2(0, -4), 20.0, _anim_time + float(a["id"]) * 0.37)


## Зверь из fauna.json: тело/голова/детали вида, цвет и размер из данных.
func _draw_fauna_animal(a: Dictionary, kind: String, pos: Vector2, vel: Vector2) -> void:
	var def: Dictionary = {}
	for s in fauna_cfg.get("species", []):
		if String(s["id"]) == kind:
			def = s
			break
	if def.is_empty():
		Assets.draw_animal(self, "turkey", Assets.dir_of(vel), not vel.is_zero_approx(),
				pos + Vector2(0, -4), 20.0, _anim_time + float(a["id"]) * 0.37)
		return
	var col := Color(String(def.get("color", "#cccccc")))
	var size := float(def.get("size", 1.0))
	var moving := not vel.is_zero_approx()
	var bob := absf(sin(_anim_time * 4.0 + float(a["id"]))) * (1.5 if moving else 0.4)
	draw_circle(pos + Vector2(0, 2), 5.0 * size, Color(0, 0, 0, 0.2))
	draw_circle(pos + Vector2(0, -2.0 * size - bob * 0.2), 4.6 * size, col)
	draw_circle(pos + Vector2(4.0 * size, -4.5 * size - bob * 0.3), 2.6 * size, col.lightened(0.12))
	match kind:
		"deer":
			draw_line(pos + Vector2(3.5 * size, -6.5 * size), pos + Vector2(2.2 * size, -10.5 * size), Color("#6d4c33"), 1.2)
			draw_line(pos + Vector2(4.8 * size, -6.2 * size), pos + Vector2(5.8 * size, -10.0 * size), Color("#6d4c33"), 1.2)
			draw_circle(pos + Vector2(5.6 * size, -4.0 * size), 0.9 * size, Color.WHITE)
		"boar":
			draw_circle(pos + Vector2(6.2 * size, -3.6 * size), 1.1 * size, Color("#e8b0a0"))
			draw_line(pos + Vector2(-4.5 * size, -2.0 * size), pos + Vector2(-6.5 * size, -2.8 * size), col.darkened(0.3), 1.5)
		"wolf":
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(3.0 * size, -6.2 * size), pos + Vector2(3.8 * size, -8.8 * size),
				pos + Vector2(4.9 * size, -6.4 * size)]), col.darkened(0.15))
			draw_line(pos + Vector2(-4.5 * size, -3.0 * size), pos + Vector2(-7.2 * size, -4.6 * size), col.darkened(0.25), 1.6)
		"bird":
			draw_circle(pos + Vector2(4.2 * size, -5.2 * size), 1.7 * size, Color("#3a3a3a"))
			draw_line(pos + Vector2(-3.0 * size, -2.4 * size), pos + Vector2(-6.0 * size, -4.4 * size), col.darkened(0.2), 1.2)


## Скот на пастбищах (M10): коровы/овцы/свиньи/куры, детёныши мельче.
func _draw_stock(a: Dictionary) -> void:
	var pos: Vector2 = a["pos"]
	pos.y -= _entity_lift("stk%d" % int(a["id"]), a["pos"])   # v1.36.1: высота плато
	var kind := String(a["kind"])
	var adult := bool(a["adult"])
	var size := 26.0 if adult else 16.0
	if kind == "chicken" or kind == "chick":
		size *= 0.7
	var moving := bool(a.get("moving", false))
	Assets.draw_animal(self, {"chick": "chicken"}.get(kind, kind),
			String(a.get("dir", "front")), moving, pos + Vector2(0, -4),
			size, _anim_time + float(a["id"]) * 0.53)


## Бродячий торговец (этап 2, аспект 4): гражданин с тюком и жёлтой одеждой;
## у палатки периодически выкрикивает зазывку-облачко.
func _draw_wanderer(w: Dictionary) -> void:
	var pos: Vector2 = w["pos"]
	pos.y -= _entity_lift("wand%d" % int(w["id"]), w["pos"])   # v1.36.1: высота плато
	var pth: PackedVector2Array = w.get("path", PackedVector2Array())
	var moving := not pth.is_empty() and pos.distance_to(pth[pth.size() - 1]) > 2.0
	var dir := String(w.get("dir", "front"))
	var tint := Color("#ffd54f").lerp(Color.WHITE, 0.35)
	Assets.draw_citizen(self, 1 + int(w["id"]) % 4, dir, moving, pos, 50.0,
			_anim_time + float(w["id"]) * 0.47, tint)
	# тюк с товаром за спиной
	draw_circle(pos + Vector2(-11.0, -8.0), 5.0, Color("#8d6e63"))
	draw_circle(pos + Vector2(-10.0, -10.0), 2.5, Color("#a1887f"))
	if String(w.get("mode", "")) == "trade" and fmod(sim.time, 14.0) < 3.0:
		var key := "wshop.%d" % (int(w["id"]) % 4 + 1)
		_draw_speech_bubble(pos, Loc.t(key))


# Зоны, растения грядок, заборы пастбищ и дороги (M6): заливки/борозды/заборы
# запечены в духовку ландшафта city_terrain.gd (v1.22), растения и полосы
# обустройства остались живыми (_draw_field_live) вместе с пульсом площади.


func _draw_anomaly() -> void:
	var c: Color = colors["anomaly"]
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 300.0)
	var center: Vector2 = map.tile_center_px(map.anomaly_tile)
	draw_circle(center, map.ts * 0.55 * pulse, Color(c.r, c.g, c.b, 0.35))
	draw_circle(center, map.ts * 0.32, c)
	draw_circle(center, map.ts * 0.14, c.lightened(0.4))


## Выход на карту мира (M8): вся рамка карты — зона перехода (лёгкая зелёная
## полоса по периметру), на западе — каменная арка с яркого свечением и
## стрелкой: главные ворота на запад, видно издалека.
func _draw_world_exit() -> void:
	var ts: float = float(map.ts)
	# рамка-зона перехода по всему периметру
	var band := Color(0.45, 0.9, 0.5, 0.10)
	draw_rect(Rect2(0, 0, map.w * ts, ts), band)
	draw_rect(Rect2(0, (map.h - 1) * ts, map.w * ts, ts), band)
	draw_rect(Rect2(0, 0, ts, map.h * ts), band)
	draw_rect(Rect2((map.w - 1) * ts, 0, ts, map.h * ts), band)
	var center: Vector2 = map.tile_center_px(map.world_exit_tile)
	var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 350.0)
	var glow := Color(0.45, 0.9, 0.5)
	# свечение-дорога: на запад, за край
	draw_rect(Rect2(center + Vector2(-ts * 0.5, -ts * 0.12), Vector2(ts * 0.5, ts * 0.24)),
			Color(glow.r, glow.g, glow.b, 0.25 + 0.15 * pulse))
	# арка: две опоры и перекладина
	draw_rect(Rect2(center + Vector2(-ts * 0.34, -ts * 0.42), Vector2(ts * 0.16, ts * 0.84)), Color("#8a8a82"))
	draw_rect(Rect2(center + Vector2(ts * 0.18, -ts * 0.42), Vector2(ts * 0.16, ts * 0.84)), Color("#8a8a82"))
	draw_rect(Rect2(center + Vector2(-ts * 0.38, -ts * 0.56), Vector2(ts * 0.76, ts * 0.18)), Color("#7a7a72"))
	# зелёное свечение в проёме
	draw_rect(Rect2(center + Vector2(-ts * 0.18, -ts * 0.36), Vector2(ts * 0.36, ts * 0.78)),
			Color(glow.r, glow.g, glow.b, 0.3 + 0.2 * pulse))
	# стрелка влево — «мир там»
	var y := center.y - ts * 0.08
	draw_line(center + Vector2(ts * 0.05, y), center + Vector2(-ts * 0.2, y),
			Color(glow.r, glow.g, glow.b, 0.6 + 0.3 * pulse), 2.5)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-ts * 0.2, y), center + Vector2(-ts * 0.1, y - 4.5),
		center + Vector2(-ts * 0.1, y + 4.5)]),
		Color(glow.r, glow.g, glow.b, 0.6 + 0.3 * pulse))


## Здание в общем сортированном слое (M12). Схематичный режим (этап 2,
## аспект 1) + прямоугольник 2×2 с входом (этап 2, аспект 2): заливка
## цвета категории, тёмная кайма, дверной проём у входа, окно светится,
## если кто-то спит внутри. Игровые метки сохранены.
func _draw_building(b: Dictionary) -> void:
	var ts := float(map.ts)
	var bw: int = sim.bld_w(b)
	var rect := Rect2(Vector2(b["tile"]) * ts, Vector2(ts * float(bw), ts * float(bw)))
	# v1.36.1: здание на плато приподнято вместе с плоскостью плато —
	# вся коробка (заливка, дверь, метки, надпись) на высоте уровня
	rect.position.y -= _bld_lift(b)
	var type_id := String(b["type"])
	var col: Color = _bld_fill.get(type_id, Color(0.91, 0.85, 0.62))
	var anchor: Vector2 = Vector2(rect.get_center().x, rect.end.y - 2.0)
	if not b["done"]:
		# стройплощадка: призрачная заливка, каркас и полоса прогресса
		draw_rect(rect.grow(-3), Color(col.r, col.g, col.b, 0.22))
		draw_rect(rect.grow(-3), col.darkened(0.2), false, 2.0)
		var work: float = _build_work(type_id)
		var frac := clampf(float(b["progress"]) / work, 0.0, 1.0) if work > 0.0 else 0.0
		draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 9),
				Vector2((rect.size.x - 8) * frac, 5)), Color("#ffe082"))
		_draw_bld_label(b, rect)
	elif bool(b.get("razed", false)):
		# руины (этап 2, аспект 5): тёмные обломки цвета категории, трещины
		# и метка «разрушено» — чинится героем за 40% стоимости (E)
		var ruin := col.darkened(0.62)
		draw_rect(rect, ruin)
		draw_rect(rect.grow(-2), col.darkened(0.78), false, 2.0)
		draw_line(rect.position + Vector2(ts * 0.25, ts * 0.2),
				rect.position + Vector2(ts * 0.45, ts * 0.55), Color(0.05, 0.04, 0.03), 2.0)
		draw_line(rect.position + Vector2(ts * 0.7, ts * 0.15),
				rect.position + Vector2(ts * 0.5, ts * 0.6), Color(0.05, 0.04, 0.03), 2.0)
		_draw_bld_label(b, rect)
		var font := ThemeDB.fallback_font
		var tag := Loc.t("city.razed_tag")
		var tag_pos := rect.position + Vector2(
				(rect.size.x - font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x) * 0.5, -3.0)
		draw_string_outline(font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3,
				Color(0.2, 0.03, 0.03, 0.9))
		draw_string(font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(1.0, 0.45, 0.4, 0.95))
	else:
		# схематичное здание: заливка категории, тёмная кайма по контуру
		draw_rect(rect, col)
		draw_rect(rect.grow(-2), col.darkened(0.3), false, 2.0)
		if type_id == "tent":
			_draw_tent_awning(rect)   # полосатый навес — торговая читаемость (этап 2)
		_draw_bld_door(b, rect)
		# точка-работник: занятое здание подсвечено
		if int(b["worker"]) > 0:
			draw_circle(rect.position + Vector2(rect.size.x - 6.0, 6.0), 2.5, Color(1, 1, 1, 0.95))
		# яблоневый сад (M10): растёт — полоска стадии, зелёная при спелости
		if type_id == "orchard":
			var stages := float(sim.cfg.get("orchard", {}).get("stages", 3))
			var stage := clampf(float(b.get("apple_stage", 0)) / maxf(1.0, stages), 0.0, 1.0)
			draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 8),
					Vector2((rect.size.x - 8) * stage, 4)),
					Color("#8bc34a") if stage >= 1.0 else Color("#ffe082"))
		_draw_bld_label(b, rect)
	# окно: кто-то спит/лежит внутри — тёплый свет у входа (ночью особенно видно)
	if sim._active(b) and _inside_homes.has(int(b["id"])):
		var door: Vector2 = _bld_door_pos(b, rect)
		var glow := 0.5 + 0.2 * sin(Time.get_ticks_msec() / 350.0)
		draw_circle(door + Vector2(0, -ts * 0.2), ts * 0.28, Color(1.0, 0.85, 0.45, 0.55 + 0.25 * glow))
		draw_circle(door + Vector2(0, -ts * 0.2), ts * 0.12, Color(1.0, 0.93, 0.7, 0.9))
	# кладбище темнеет (M11): тьма ползёт с кладбища, пока некромант работает
	if String(b["type"]) == "cemetery" and bool(b["done"]):
		_draw_graves(anchor - Vector2(0, 0))
		var dark := clampf(float(sim.necro_dark), 0.0, 1.0)
		if dark > 0.02:
			var rings := 4
			for i in rings:
				var rr: float = ts * (0.8 + dark * 2.2) * (float(i + 1) / float(rings))
				draw_circle(anchor - Vector2(0, 4), rr,
						Color(0.08, 0.05, 0.14, 0.05 + 0.1 * dark))
			if sim.necro_known:
				var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 500.0)
				draw_arc(anchor - Vector2(0, 4), ts * (0.9 + dark * 2.0),
						0.0, TAU, 24, Color(0.5, 0.3, 0.7, 0.12 + 0.1 * pulse), 2.0)
		# ночные призывы (M11): скелеты видны у кладбища только ночью
		if sim.is_night() and int(sim.necro_army) > 0:
			var shown: int = mini(3, sim.necro_ghosts.size())
			for g in shown:
				var gpx: Vector2 = sim.necro_ghosts[g]
				var bob := absf(sin(Time.get_ticks_msec() / 320.0 + float(g) * 2.1)) * 2.0
				Assets.draw_ref(self, "k:121", gpx + Vector2(0, -bob),
						ts * 1.1, false, Color(0.75, 0.7, 0.9))
	# зачарование: рамка цветом эффекта (M3)
	if String(b.get("enchant", "")) != "":
		var ecol: Color = enchant_colors.get(String(b["enchant"]), Color(0.8, 0.8, 1.0))
		draw_rect(rect.grow(-1), ecol, false, 2.0)
		draw_circle(rect.position + Vector2(5, 5), 3.0, ecol)
	# дикая вспышка: здание оглушено
	if float(b.get("stun_left", 0.0)) > 0.0:
		draw_rect(rect, Color(0.1, 0.05, 0.15, 0.55))
		var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		draw_arc(rect.get_center(), ts * 0.4, 0.0, TAU, 20,
				Color(0.9, 0.4, 1.0, 0.4 + 0.4 * flash), 2.0)
	# прочность (M5): повреждённое здание показывает полоску (руины — без неё)
	if sim._active(b) and float(b.get("hp", 999.0)) < float(_bld_max_hp(String(b["type"]))):
		var frac2 := clampf(float(b["hp"]) / float(_bld_max_hp(String(b["type"]))), 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(4, -7), Vector2(ts - 8, 4)), Color(0.15, 0.1, 0.1))
		draw_rect(Rect2(rect.position + Vector2(4, -7), Vector2((ts - 8) * frac2, 4)), Color("#8bc34a"))


## Подпись схематичного здания (этап 2, аспект 1): краткое название
## поверх заливки, обводка для читаемости на любом цвете. Стена —
## сплошное кольцо, её тайлы подписями не метятся (шум); ворота подписаны.
const BLD_NO_LABEL := {"wall": true}


## Полосатый навес палатки (этап 2, аспект 4): жёлто-светлые полосы
## поверх заливки категории — «торговое место» читается с одного взгляда.
func _draw_tent_awning(rect: Rect2) -> void:
	var stripe := rect.size.y * 0.28
	var h := rect.size.y * 0.16
	for i in 2:
		var col := Color("#ffd54f") if i % 2 == 0 else Color("#fff3c4")
		draw_rect(Rect2(rect.position.x + 2.0, rect.position.y + stripe * float(i),
				rect.size.x - 4.0, h), col)


func _draw_bld_label(b: Dictionary, rect: Rect2) -> void:
	var type_id := String(b["type"])
	if bool(BLD_NO_LABEL.get(type_id, false)):
		return
	var key: String = _bld_short.get(type_id, "")
	if key == "":
		return
	# v1.21.4: текст и ширина кэшируются по типу — замер шрифта на каждое
	# здание каждый кадр стоил дороже всей остальной отрисовки подписи
	if not _label_cache.has(type_id):
		var text := Loc.t(key)
		if text == key:
			# краткой подписи нет — падаем на полное название, затем на id
			var full_key: String = _bld_loc.get(type_id, "")
			var full := Loc.t(full_key) if full_key != "" else ""
			text = full if full != full_key and full != "" else type_id
		var font := ThemeDB.fallback_font
		_label_cache[type_id] = [text, font.get_string_size(text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x]
	var cached: Array = _label_cache[type_id]
	var pos := rect.get_center() - Vector2(float(cached[1]) * 0.5, -3.0)
	draw_string_outline(ThemeDB.fallback_font, pos, cached[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color(0.12, 0.09, 0.05, 0.9))
	draw_string(ThemeDB.fallback_font, pos, cached[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 0.96, 0.97))


## Дверной проём (этап 2, аспект 2): тёмная метка на кайме со стороны входа.
func _draw_bld_door(b: Dictionary, rect: Rect2) -> void:
	var door := _bld_door_pos(b, rect)
	var w := rect.size.x * 0.16
	var h := rect.size.y * 0.12
	var horizontal: bool = absf(door.x - rect.get_center().x) > rect.size.x * 0.25
	var r := Rect2(door - Vector2(w if horizontal else h * 0.5, h if horizontal else w * 0.5),
			Vector2(h if horizontal else w, w if horizontal else h))
	draw_rect(r, Color(0.18, 0.13, 0.09, 0.85))


## Точка входа: середина общего ребра между входной клеткой и прямоугольником.
func _bld_door_pos(b: Dictionary, rect: Rect2) -> Vector2:
	var ts := float(map.ts)
	var e: Vector2i = sim.bld_entrance(b)
	if e == Vector2i(-1, -1):
		return Vector2(rect.get_center().x, rect.end.y)
	var t := Vector2i(b["tile"])
	var bw: int = sim.bld_w(b)
	var cx := clampi(e.x, t.x, t.x + bw - 1)
	var cy := clampi(e.y, t.y, t.y + bw - 1)
	var cell_center := Vector2(t) * ts + (Vector2(cx, cy) + Vector2(0.5, 0.5)) * ts
	var e_center := Vector2(e) * ts + Vector2(ts, ts) * 0.5
	return (cell_center + e_center) * 0.5


## Дома с обитателями внутри (спят/лежат/прячутся): id здания → true.
## Собирается один раз за кадр в _draw_world_sorted.
var _inside_homes: Dictionary = {}


## Атакующие (M5 мутанты; M11 духи леса, Древень, скелеты некроманта).
func _draw_raider(r: Dictionary) -> void:
	var refs := {"mutant": "e:mutant", "brute": "e:brute", "spitter": "e:spitter",
			"forest_spirit": "e:spirit", "forest_boss": "e:treant", "skeleton": "k:121"}
	var pos: Vector2 = r["pos"]
	var rad := float(r["p"]["radius"])
	var kind := String(r["type"])
	var ref: String = refs.get(kind, "e:mutant")
	var size := rad * 2.8
	var lift := 0.0
	var hl := _entity_lift("raid%d" % int(r["id"]), pos)   # v1.36.1: высота плато
	var tint := Color.WHITE
	if kind == "forest_spirit" or kind == "forest_boss":
		# духи парят: синус повыше и медленнее, свечение бирюзой
		lift = 4.0 + 2.5 * sin(Time.get_ticks_msec() / 260.0 + float(r["id"]))
		tint = Color(0.8, 1.05, 1.0) if kind == "forest_spirit" else Color(0.9, 1.1, 0.85)
	var phase := pos.x * 0.9 + Time.get_ticks_msec() / 100.0
	var vx := 0.0
	var pth: PackedVector2Array = r.get("path", PackedVector2Array())
	if not pth.is_empty():
		vx = (pth[0] - pos).x
	Assets.draw_ref(self, ref, pos + Vector2(0, -absf(sin(phase)) * 1.5 - lift - hl), size, vx < -1.0, tint)
	if int(r["hp"]) < int(r["max_hp"]):
		var frac := clampf(float(r["hp"]) / float(r["max_hp"]), 0.0, 1.0)
		draw_rect(Rect2(pos + Vector2(-12, -rad - 8 - hl), Vector2(24, 4)), Color(0.15, 0.1, 0.1))
		draw_rect(Rect2(pos + Vector2(-12, -rad - 8 - hl), Vector2(24.0 * frac, 4)), Color(0.9, 0.25, 0.25))
	# осадный мутант и босс леса выделены — видно, кто главный
	# (кольцо — метка тайла, остаётся на «земле» без лифта)
	if kind == "brute" or kind == "forest_boss":
		var ring := Color(0.9, 0.3, 0.2, 0.6) if kind == "brute" else Color(0.5, 0.9, 0.4, 0.7)
		draw_arc(pos, rad + 3.0, 0.0, TAU, 20, ring, 2.0)


func _bld_max_hp(type_id: String) -> float:
	if _hp_max_cache.has(type_id):
		return float(_hp_max_cache[type_id])
	var hp_cfg: Dictionary = sim.cfg.get("threat", {}).get("bld_hp", {})
	var hp := float(hp_cfg.get("default", 20))
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			hp = float(hp_cfg.get(String(d.get("effect", "default")), hp))
			break
	_hp_max_cache[type_id] = hp
	return hp


## Кэш кружков жителей (v1.21.5): тело жителя — тень+кайма+заливка+центр —
## рисовалось пятью командами на каждого; теперь печётся в маленькую
## текстуру по цвету и размеру и рисуется одной командой.
var _res_sprites: Dictionary = {}


func _res_sprite(col: Color, radius: float) -> ImageTexture:
	var key := "%s|%.0f" % [col.to_html(false), radius]
	if _res_sprites.has(key):
		return _res_sprites[key]
	var size := int(ceil(radius * 2.0)) + 6
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0, size / 2.0)
	var shadow_c := c + Vector2(0.0, 2.5)
	var border := col.darkened(0.55)
	var dot := col.darkened(0.5)
	for py in size:
		for px in size:
			var p := Vector2(px + 0.5, py + 0.5)
			var px_col := Color(0, 0, 0, 0)
			if p.distance_to(shadow_c) <= radius:
				px_col = Color(0, 0, 0, 0.25)
			var d := p.distance_to(c)
			if d <= radius:
				px_col = border
			if d <= radius - 1.5:
				px_col = col
			if d <= radius * 0.42:
				px_col = dot
			img.set_pixel(px, py, px_col)
	var tex := ImageTexture.create_from_image(img)
	_res_sprites[key] = tex
	return tex


## Житель (M12: per-object для общего сортированного слоя). Айдл без «марша на
## месте»: движение читается из состояния и пути — раньше флаг moving,
## выставленный в дороге, не сбрасывался у стоящих, и они «маршировали».
## Житель — кружок (правки v1.20): убрали графику, цвет кружка = основная
## специальность; голем-староста — белый; дети — маленькие серо-бежевые.
func _draw_resident(r: Dictionary) -> void:
	# тайный некромант на кладбище (v1.24): ночная тьма прячет его —
	# пока герой не подойдёт на hidden_radius (4) клеток, его не видно
	if city != null and city.hero != null \
			and sim.necro_hidden_from(r, city.hero.global_position):
		return
	var pos: Vector2 = r["pos"]
	var prof := String(r["prof"])
	var child := prof == ""
	var col: Color = sim.resident_color(r)
	var sleeping: bool = r["state"] == "sleep" or r["state"] == "rest"
	# лёгкое покачивание при движении — кружок «живой»
	var pth: PackedVector2Array = r.get("path", PackedVector2Array())
	var moving: bool = not sleeping and not pth.is_empty() \
			and pos.distance_to(pth[pth.size() - 1]) > 2.0
	var phase := float(r["id"]) * 1.7 + _anim_time * (7.0 if moving else 1.5)
	var bob := absf(sin(phase)) * (1.6 if moving else 0.4)
	var radius := 7.0 if child else 9.0
	# v1.36.1: стоя на плато, житель выше равнины (подъём анимируется
	# на лестнице) — высота ощущается, а не плоская текстура
	var lift := _entity_lift("res%d" % int(r["id"]), pos)
	var ail := String(r.get("ail", ""))
	if ail == "sick":
		col = col.lerp(Color(0.7, 0.95, 0.6), 0.5)
	elif ail == "wounded":
		col = col.lerp(Color(1.0, 0.45, 0.45), 0.5)
	if sleeping:
		col = col.darkened(0.4)
	var center := pos + Vector2(0, -3.0 - bob - lift)
	# тело — готовая текстурка (v1.21.5): одна команда вместо пяти
	var body := _res_sprite(col, radius)
	var half := float(body.get_width()) * 0.5
	draw_texture_rect(body, Rect2(center - Vector2(half, half),
			Vector2(float(body.get_width()), float(body.get_width()))), false)
	# голем-староста: белое «лицо» камня поверх кружка (он один на город)
	if _is_elder_golem(r):
		draw_circle(center, radius - 3.0, Color(1.0, 1.0, 1.0, 0.95))
		draw_circle(center + Vector2(-2.0, -1.5), 1.1, Color("#3a3f4a"))
		draw_circle(center + Vector2(2.0, -1.5), 1.1, Color("#3a3f4a"))
	# спарринг стражей (v1.23): перекрёстные клинки над парой
	if String(r.get("state", "")) == "spar":
		var top := center + Vector2(0, -radius - 7.0)
		var clash := 1.0 + 0.3 * sin(_anim_time * 10.0)
		draw_line(top + Vector2(-4.0 * clash, -3.0), top + Vector2(4.0 * clash, 3.0), Color("#e0e0e0"), 1.5)
		draw_line(top + Vector2(-4.0 * clash, 3.0), top + Vector2(4.0 * clash, -3.0), Color("#e0e0e0"), 1.5)
	# груз носильщика (M6): узел цвета ресурса; бревно/сырой камень (v1.21) —
	# покрупнее: видно, что тащит лесоруб и шахтёр (несёт на теле — с лифтом)
	if float(r.get("carry", 0.0)) > 0.0:
		var bag: Color = _pile_colors.get(String(r.get("carry_res", "")), Color(0.8, 0.7, 0.5))
		draw_circle(center + Vector2(radius + 2.0, -1.0), 3.4, bag.darkened(0.1))
		draw_circle(center + Vector2(radius + 1.2, -1.8), 1.6, bag.lightened(0.15))
	if int(r.get("log_size", 0)) > 0:
		var log_col := Color("#8d6e63") if int(r["log_size"]) < 3 else Color("#6d4c33")
		draw_circle(center + Vector2(radius + 3.0, -1.0), 4.2, log_col.darkened(0.2))
		draw_circle(center + Vector2(radius + 1.8, -2.2), 1.8, log_col.lightened(0.2))
	elif float(r.get("raw", 0.0)) > 0.0 or float(r.get("carry_iron", 0.0)) > 0.0 \
			or float(r.get("carry_stone", 0.0)) > 0.0:
		draw_circle(center + Vector2(radius + 3.0, -1.0), 4.2, Color("#9e9e9e").darkened(0.15))
		draw_circle(center + Vector2(radius + 1.8, -2.2), 1.8, Color("#bdbdbd"))
	# разговор-облачко (M12): реплика над головой болтающих
	var chat_key := String(r.get("chat_key", ""))
	if chat_key != "" and String(r["state"]) == "chat":
		_draw_speech_bubble(center, Loc.t(chat_key))


func _is_elder_golem(r: Dictionary) -> bool:
	return String(r.get("prof", "")) == "elder"


## Облачко реплики (M12, имитация жизни): плашка с текстом и хвостиком.
func _draw_speech_bubble(pos: Vector2, text: String) -> void:
	var font := ThemeDB.fallback_font
	var fsize := 10
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + 10.0
	var top := pos + Vector2(-width * 0.5, -58.0)
	var rect := Rect2(top, Vector2(width, 16.0))
	draw_rect(rect, Color(1, 1, 0.96, 0.92))
	draw_rect(rect, Color(0.35, 0.3, 0.25, 0.8), false, 1.0)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-3, -42), pos + Vector2(3, -42), pos + Vector2(0, -36)]),
		Color(1, 1, 0.96, 0.92))
	draw_string(font, top + Vector2(5, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize,
			Color(0.2, 0.16, 0.12))


## Герой в общем сортированном слое (M12): тело и меч рисует сам герой
## в переданный canvas, спрайт-нода в городе скрыта.
## v1.36.1: на плато герой стоит выше равнины (подъём анимируется на
## лестнице) — высота ощущается, а не выглядит плоской текстурой.
func _draw_hero(hero) -> void:
	var lift := _entity_lift("hero", hero.global_position)
	hero.draw_body(self, hero.global_position + Vector2(0, -lift))


func _draw_ghost() -> void:
	if dragging and zone_mode != "":
		_draw_zone_preview()
		return
	if road_mode:
		# режим дороги: подсветка тайла под мышью и уже проложенных дорог
		var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if map.in_bounds(tile):
			var ok: bool = sim._zone_cell_ok(tile) and int(sim.res.get("stone", 0)) >= int(sim.cfg.get("roads", {}).get("cost_stone", 1))
			draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts)),
					Color(0.5, 1.0, 0.5, 0.35) if ok else Color(1.0, 0.3, 0.3, 0.35))
		return
	if plant_mode:
		# посадка леса (M11): саженец под курсором, годность по траве и семенам
		var ptile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if map.in_bounds(ptile):
			var ok2: bool = sim.can_plant_at(ptile)
			draw_rect(Rect2(Vector2(ptile) * map.ts, Vector2(map.ts, map.ts)),
					Color(0.5, 1.0, 0.5, 0.35) if ok2 else Color(1.0, 0.3, 0.3, 0.35))
			var bottom: Vector2 = Vector2(ptile) * map.ts + Vector2(map.ts / 2.0, map.ts * 0.92)
			Assets.draw_ref(self, "e:sap2", bottom, map.ts * 0.9, false,
					Color(1, 1, 1, 0.6))
		return
	if enchant_mode != "":
		# режим зачарования: подсветка тайла под мышью
		var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if not map.in_bounds(tile):
			return
		var col := Color(0.7, 0.5, 1.0, 0.45)
		if city != null and not city.enchant_target_valid(tile):
			col = Color(1.0, 0.3, 0.3, 0.4)
		draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts)), col)
		return
	if move_mode:
		_draw_move_ghost()
		return
	if plaza_mode:
		_draw_plaza_ghost()
		return
	if build_mode == "":
		return
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	var ok: bool = sim.is_buildable_rect(build_mode, tile) and sim.can_afford(_cost_of(build_mode))
	var col := Color(0.5, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	# призрак всего прямоугольника здания (2×2; стены/ворота/мост — 1×1)
	var w := float(sim.bld_w_of_type(build_mode))
	draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts * w, map.ts * w)), col)
	draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts * w, map.ts * w)).grow(-2),
			Color(col.r, col.g, col.b, 0.9), false, 2.0)


## Призрак переноса (этап 2, аспект 5): пока здание не выбрано — подсветка
## здания под курсором (зелёная — годное); после выбора — рамка снимка
## и прямоугольник под мышью (зелёный/красный по правилам места).
func _draw_move_ghost() -> void:
	var ts := float(map.ts)
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	if move_bld_id < 0:
		var b: Dictionary = sim.building_at(tile)
		var ok_b: bool = sim._active(b)
		var hb := Rect2(Vector2(b["tile"]) * ts,
				Vector2(ts * float(sim.bld_w(b)), ts * float(sim.bld_w(b)))) if ok_b \
				else Rect2(Vector2(tile) * ts, Vector2(ts, ts))
		draw_rect(hb.grow(-1), Color(0.5, 1.0, 0.5, 0.8) if ok_b else Color(1.0, 0.3, 0.3, 0.5),
				false, 2.0)
		return
	var picked: Dictionary = {}
	for b2 in sim.buildings:
		if int(b2["id"]) == move_bld_id:
			picked = b2
			break
	if picked.is_empty():
		return
	# рамка выбранного здания пульсирует
	var pw := float(sim.bld_w(picked))
	var pr := Rect2(Vector2(picked["tile"]) * ts, Vector2(ts * pw, ts * pw))
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 220.0)
	draw_rect(pr.grow(-1), Color(1.0, 0.85, 0.3, pulse), false, 2.5)
	# прямоугольник под курсором — годен ли (собственные клетки не мешают)
	var w := float(sim.bld_w_of_type(String(picked["type"])))
	var ok: bool = sim.move_spot_ok(picked, tile)
	var col := Color(0.5, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	draw_rect(Rect2(Vector2(tile) * ts, Vector2(ts * w, ts * w)), col)
	draw_rect(Rect2(Vector2(tile) * ts, Vector2(ts * w, ts * w)).grow(-2),
			Color(col.r, col.g, col.b, 0.9), false, 2.0)


## Выделение зоны (M6): прямоугольник от первой точки до курсора,
## негодные клетки — красным.
func _draw_zone_preview() -> void:
	var col: Color = _zone_colors.get(zone_mode, Color(0.7, 0.7, 0.4))
	var x0 := mini(drag_from.x, drag_to.x)
	var x1 := maxi(drag_from.x, drag_to.x)
	var y0 := mini(drag_from.y, drag_to.y)
	var y1 := maxi(drag_from.y, drag_to.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var tile := Vector2i(x, y)
			if not map.in_bounds(tile):
				continue
			var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
			var ok: bool = sim._zone_cell_ok(tile)
			if ok:
				draw_rect(rect, Color(col.r, col.g, col.b, 0.35))
			else:
				draw_rect(rect, Color(1.0, 0.3, 0.3, 0.3))


func _center(x: int, y: int) -> Vector2:
	return Vector2(x * map.ts + map.ts / 2.0, y * map.ts + map.ts / 2.0)


func _build_work(type_id: String) -> float:
	if _work_cache.has(type_id):
		return float(_work_cache[type_id])
	var work := 1.0
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			work = float(d["build_work"])
			break
	_work_cache[type_id] = work
	return work


func _cost_of(type_id: String) -> Dictionary:
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			return d["cost"]
	return {}
