extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Отрисовка карты мира (M8): биомы цветом, туман войны, точки интереса,
## маршрут героя. Только показ — логика в world_map.gd/world_sim.gd.
##
## v1.35.1 (правки приёмки «Мир v2» этапа 1): ландшафт ЗАПЕКАЕТСЯ в текстуру
## светотеневым рельефом — билинейное сглаживание цветов биомов и высот
## (никаких квадратных тайлов), освещение с северо-запада (склоны читаются
## рельефом, а не пятном цвета), высотная подсветка + скальный тон у вершин,
## светлая мель у берегов. Выпечка кэшируется на карте мира (map._terrain_bake)
## — сцена пересоздаётся, текстура живёт, пока жива карта. Дороги — линии,
## туман — «облачная» масса из кружков с мягкой волнистой кромкой.

const KIND_COLORS := {
	"city": "#7cb342",
	"dungeon": "#b46ee0",
	"ruins": "#c8b07a",
	"camp": "#e57373",
	"settlement": "#ffd54f",
	"caravan": "#ffb300",
	"trade_camp": "#ffca28",
	"obelisk": "#4dd0e1",
	"dragon_castle": "#ef5350",
	"vampire_keep": "#b71c1c",
	"lich_tower": "#9575cd",
}

# спрайты точек интереса (M9): Kenney + сгенерированные здания
const KIND_SPRITES := {
	"city": "b:house",
	"dungeon": "b:altar",
	"ruins": "k:65",
	"camp": "k:112",
	"settlement": "k:85",
	"caravan": "k:98",
	"trade_camp": "e:cart",
	"obelisk": "b:statue",
	"dragon_castle": "b:castle",
	"vampire_keep": "b:vampire_keep",
	"lich_tower": "b:lich_tower",
}

var map = null
var hero_px := Vector2.ZERO
var hero_tile := Vector2i.ZERO
var selected_tile := Vector2i(-1, -1)
var _time := 0.0
var _vp: SubViewport = null    # духовка статики (v1.40.1)
var _sd: Node2D = null
var _static_tex: Texture2D = null
var _bake_fog_ver := -1
# туман (v1.40.2): отдельная текстура ПОЛНОГО покрытия, раскрытие = стирание
var _fog_img: Image = null
var _fog_tex: Texture2D = null
var _fog_hts := 16.0           # полтайла на пиксель тумана


var _bake_k := 1.0             # кап запечки (v1.43: карта ×5 — текстуры ≤4096)


func setup(world_map) -> void:
	map = world_map
	# v1.43 (карта ×5): текстуры не растут с картой — кап 4096 по длинной
	# стороне, канвас вьюпорта масштабируется, _draw растягивает обратно
	_bake_k = minf(1.0, 4096.0 / float(maxi(map.w, map.h) * map.ts))
	_vp = SubViewport.new()
	_vp.size = Vector2i(maxi(1, int(float(map.w * map.ts) * _bake_k)),
			maxi(1, int(float(map.h * map.ts) * _bake_k)))
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_vp.canvas_transform = Transform2D().scaled(Vector2(_bake_k, _bake_k))
	add_child(_vp)
	_sd = Node2D.new()
	_sd.draw.connect(_draw_static)
	_vp.add_child(_sd)
	_static_tex = _vp.get_texture()


func _ready() -> void:
	_do_bake()
	_build_fog_layer()


func _process(delta: float) -> void:
	_time += delta
	# раскрытие тумана: стираем круги из текстуры (дёшево, каждый шаг)
	if map != null and map.get("fog_new") != null and not (map.fog_new as Array).is_empty():
		_erase_fog(map.fog_new)
		map.fog_new.clear()


## Запечь статику карты: рельеф + реки + дороги + туман (не из _draw!).
func _do_bake() -> void:
	if _vp == null or not is_inside_tree() or map == null:
		return
	if map.get("_terrain_bake") == null:
		_bake_terrain()
	_bake_fog_ver = int(map.fog_ver)
	_sd.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Содержимое запечки: рельеф-квад + реки + дороги (БЕЗ тумана — v1.40.2:
## туман живёт отдельной текстурой и стирается по тайлам при раскрытии,
## статика карты больше НЕ перепекается при ходьбе — это и роняло FPS).
## Всё рисуется В _sd (урок v1.39.1: голые draw_* отбрасываются движком).
func _draw_static() -> void:
	var ts := float(map.ts)
	_sd.draw_texture_rect(map._terrain_bake,
			Rect2(Vector2.ZERO, Vector2(map.w * ts, map.h * ts)), false)
	_rivers_into(_sd, ts)
	_roads_into(_sd, ts)


func _draw() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	# v1.40.1: статичный слой (рельеф + реки + дороги + туман) — одним
	# квадом из запечки; перепекается при раскрытии тумана (fog_ver)
	if _static_tex != null:
		draw_texture_rect(_static_tex,
				Rect2(Vector2.ZERO, Vector2(map.w * ts, map.h * ts)), false)
	# туман поверх (чёрная пелена с дырами на раскрытом)
	if _fog_tex != null:
		draw_texture_rect(_fog_tex,
				Rect2(Vector2.ZERO, Vector2(map.w * ts, map.h * ts)), false)
	# точки интереса (только найденные и на исследованной земле —
	# на пергаменте маркеров нет, v1.40)
	for poi in map.pois:
		if not bool(poi["discovered"]):
			continue
		if not map.is_explored(poi["tile"]):
			continue
		_draw_poi(poi, ts)
	# следы бандитов (M12): стрелки на исследованных тайлах — ведут от гнезда
	var sim = get_parent().get("sim") if get_parent() != null else null
	if sim != null and sim.tracks != null:
		for t: Vector2i in sim.tracks:
			if not map.is_explored(t):
				continue
			_draw_track(t, Vector2i(sim.tracks[t]["dir"]), ts)
	# фауна (M14-C/T01): звери видны рядом с героем
	var fauna = get_parent().get("fauna") if get_parent() != null else null
	if fauna != null and fauna.fauna != null:
		for a in fauna.fauna:
			_draw_animal(a, fauna.species_def(String(a["kind"])))
	# гиганты (M14-E): крупные маркеры, видны издалека
	var giants = get_parent().get("sim").giants if get_parent() != null and get_parent().get("sim") != null else null
	if giants != null:
		for g in giants.giants:
			_draw_giant(g, giants.cfg.get("contact_px", 28.0))
	# легендарные странники (v1.22): звёздный маркер на исследованной земле
	if sim != null and sim.get("legends") != null:
		for l in sim.legends:
			if String(l["state"]) == "gone":
				continue
			var lt: Vector2i = l["tile"]
			if not map.is_explored(lt) and Vector2(lt).distance_to(Vector2(hero_tile)) > 4.0:
				continue   # в тумане странника не видно — он тоже тень
			_draw_legend(l, ts)
	# маршрут в пути
	_draw_route(ts)
	# герой (M9): спрайт воина с лёгким бобингом и тенью
	var bob := absf(sin(_time * 6.0)) * 2.0
	draw_circle(hero_px + Vector2(0, 6), 6.0, Color(0, 0, 0, 0.3))
	Assets.draw_ref(self, "img:knight", hero_px + Vector2(0, -2 - bob), 26.0)


## Реки — рисуются в канвас (в запечку; вызывается из _draw_static).
func _rivers_into(canvas: CanvasItem, ts: float) -> void:
	if map.river == null or map.river.is_empty():
		return
	var biomes: Dictionary = map.cfg.get("biomes", {})
	var col := Color(String(biomes.get("river", {}).get("color", "#57b2d4")))
	var vein := col.lightened(0.25)
	var links := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(-1, 1)]
	for t: Vector2i in map.river:
		if not map.is_explored(t):
			continue
		var c: Vector2 = map.tile_center_px(t)
		var linked := false
		for d: Vector2i in links:
			var n := t + d
			if map.river.has(n) and map.is_explored(n):
				var nc: Vector2 = map.tile_center_px(n)
				canvas.draw_line(c, nc, col, ts * 0.5)
				canvas.draw_line(c, nc, vein, ts * 0.16)
				linked = true
		if not linked:
			canvas.draw_circle(c, ts * 0.26, col)
			canvas.draw_circle(c, ts * 0.09, vein)


## ---------- запечённый светотеневой рельеф (v1.35.1) ----------
## Поле тайлов → гладкая карта: цвета биомов и высоты сглаживаются
## билинейно (границы биомов и берега — плавные, без сетки квадратов),
## затем рельеф подсвечивается светом с северо-запада: северо-западные
## склоны светлее, юго-восточные темнее — высота читается как высота,
## а не как пятно цвета. Вершины получают скальный тон и высотную
## подсветку, у берегов светлая мель. Выпечка 3 суб-пикселя/тайл →
## масштабирование билинейно до полного размера (быстро, гладко).
## v1.40.1: СТАТИКА карты (рельеф + реки + дороги + туман) запекается в
## собственный SubViewport — в кадре один квад (раньше туман был ~1500
## кружков + реки/дороги по всей карте КАЖДЫЙ кадр — это держало карту
## на 1–3 FPS). Перепечка при раскрытии тумана (map.fog_ver). Туман —
## ОБЛАКА (светло-серые кучные массы). Разрешение запечки 3→6 суб-пикс.

const BAKE_SUB := 6   # суб-пикселей на тайл при выпечке (v1.40.1: резче, «мыла» меньше)
const BAKE_PIXEL_BUDGET := 1_400_000   # v1.43: бюджет CPU-прохода рельефа
const BAKE_CAP := 4096.0               # v1.43: кап длинной стороны текстур карты


## Суб-пикселей на тайл: бюджет ~1.4 Мп на CPU-проход (карта ×5 —
## суб-пиксели автоматически ниже, финал всё равно упирается в кап 4096).
func _bake_sub() -> int:
	return clampi(int(sqrt(float(BAKE_PIXEL_BUDGET) / float(map.w * map.h))), 2, BAKE_SUB)
const BAKE_ROCK := Color("#8a8276")   # скальный тон вершин


func _bake_terrain() -> void:
	var biomes: Dictionary = map.cfg.get("biomes", {})
	var plains := Color(String(biomes.get("plains", {}).get("color", "#5d7a3a")))
	var water := Color(String(biomes.get("water", {}).get("color", "#2e5f7a")))
	var forest := Color(String(biomes.get("forest", {}).get("color", "#3e5a2a")))
	var hills := Color(String(biomes.get("hills", {}).get("color", "#6e6a63")))
	var waste := Color(String(biomes.get("waste", {}).get("color", "#7a6a55")))
	var swamp := Color(String(biomes.get("swamp", {}).get("color", "#5a6b4a")))
	var hill_thr := float(map.cfg.get("hydro", {}).get("hill_threshold", 0.62))
	# базовые цвета тайлов: дороги красятся линией поверх — в поле они
	# равнина; лёгкая пятнистость по хэшу тайла оживляет массу биома.
	# Биом-регионы (v1.40): снег/вулкан/пустыня/мёртвель перекрашивают
	# сушу своими цветами из world.json → regions.list[].colors
	var cols: Array = []
	var wmask: Array = []
	var tile_names := {
		map.TILE_PLAINS: "plains", map.TILE_FOREST: "forest",
		map.TILE_HILL: "hills", map.TILE_WASTE: "waste",
	}
	for y in map.h:
		var rowc: Array = []
		var roww: Array = []
		rowc.resize(map.w)
		roww.resize(map.w)
		for x in map.w:
			var c := plains
			var t: int = map.grid[y][x]
			match t:
				map.TILE_WATER:
					c = water
				map.TILE_FOREST:
					c = forest
				map.TILE_HILL:
					c = hills
				map.TILE_WASTE:
					c = waste
				map.TILE_SWAMP:
					c = swamp
			var rid: String = map.region_at(Vector2i(x, y)) if map.get("region") != null else ""
			if rid != "" and tile_names.has(t):
				var rc: Dictionary = map.region_def(rid).get("colors", {})
				if rc.has(tile_names[t]):
					c = Color(String(rc[tile_names[t]]))
			roww[x] = 1.0 if t == map.TILE_WATER else 0.0
			rowc[x] = c.lightened(0.02 * float(_hash2(x, y, 5) - 2))
		cols.append(rowc)
		wmask.append(roww)
	var sub := _bake_sub()
	var iw := int(map.w) * sub
	var ih := int(map.h) * sub
	# проход 1: сглаженное поле высот (сосед для светотени — чтение из сетки)
	var hgrid: Array = []
	for py in ih:
		var fy := (float(py) + 0.5) / float(sub) - 0.5
		var row: Array = []
		row.resize(iw)
		for px in iw:
			var fx := (float(px) + 0.5) / float(BAKE_SUB) - 0.5
			row[px] = _bilinear_f(map.height, fx, fy)
		hgrid.append(row)
	# проход 2: цвет пикселя — сглаженный биом + светотень + высота + мель
	var img := Image.create_empty(iw, ih, false, Image.FORMAT_RGB8)
	for py in ih:
		var fy := (float(py) + 0.5) / float(sub) - 0.5
		for px in iw:
			var fx := (float(px) + 0.5) / float(BAKE_SUB) - 0.5
			var col: Color = _bilinear_col(cols, fx, fy)
			var wmk := clampf(_bilinear_f(wmask, fx, fy), 0.0, 1.0)
			var land := 1.0 - wmk
			var hgt := float(hgrid[py][px])
			var nw := float(hgrid[maxi(0, py - sub)][maxi(0, px - sub)])
			# свет с северо-запада — ТОЛЬКО на суше; вода держит свой цвет
			# (v1.35.2: раньше множитель «не рельефить воду» чернил воду
			# до чёрной массы — внутренние моря читались дырой в карте)
			var shade := clampf(1.0 + (hgt - nw) * 6.5 * land, 0.55, 1.45)
			col = col * ((0.88 + 0.22 * hgt) * land + (1.0 - 0.06 * wmk) * wmk) * shade
			# вершины — скальный тон (по высоте, поверх биома)
			col = col.lerp(BAKE_ROCK, clampf((hgt - (hill_thr - 0.05)) * 2.6, 0.0, 0.78) * land)
			# светлая мель у кромки воды
			col = col.lightened(0.12 * (1.0 - absf(wmk * 2.0 - 1.0)))
			img.set_pixel(px, py, col)
	var tw := maxi(1, int(float(map.w * map.ts) * _bake_k))
	var th := maxi(1, int(float(map.h * map.ts) * _bake_k))
	img.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	map._terrain_bake = ImageTexture.create_from_image(img)


## Билинейная выборка числового поля (центры тайлов — целые координаты).
func _bilinear_f(field: Array, fx: float, fy: float) -> float:
	var fh: int = field.size()
	var fw: int = (field[0] as Array).size()
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var xa := clampi(x0, 0, fw - 1)
	var xb := clampi(x0 + 1, 0, fw - 1)
	var ya := clampi(y0, 0, fh - 1)
	var yb := clampi(y0 + 1, 0, fh - 1)
	var a := float(field[ya][xa])
	var b := float(field[ya][xb])
	var c := float(field[yb][xa])
	var d := float(field[yb][xb])
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## Билинейная выборка поля цветов — плавные границы биомов.
func _bilinear_col(field: Array, fx: float, fy: float) -> Color:
	var fh: int = field.size()
	var fw: int = (field[0] as Array).size()
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var xa := clampi(x0, 0, fw - 1)
	var xb := clampi(x0 + 1, 0, fw - 1)
	var ya := clampi(y0, 0, fh - 1)
	var yb := clampi(y0 + 1, 0, fh - 1)
	var a: Color = field[ya][xa]
	var b: Color = field[ya][xb]
	var c: Color = field[yb][xa]
	var d: Color = field[yb][xb]
	return a.lerp(b, tx).lerp(c.lerp(d, tx), ty)


static func _hash2(x: int, y: int, n: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, n)


## Старые тракты (v1.35.1): линии между соседними дорожными тайлами —
## гладкие тропы вместо квадратов цвета дороги.
## Дороги — рисуются в канвас (в запечку).
func _roads_into(canvas: CanvasItem, ts: float) -> void:
	var col := Color(String(map.cfg.get("biomes", {}).get("road", {}).get("color", "#6e5f4a")))
	var links := [Vector2i(1, 0), Vector2i(0, 1)]
	for y in map.h:
		for x in map.w:
			if int(map.grid[y][x]) != map.TILE_ROAD:
				continue
			var t := Vector2i(x, y)
			var c: Vector2 = map.tile_center_px(t)
			var linked := false
			for d: Vector2i in links:
				var n := t + d
				if map.in_bounds(n) and int(map.grid[n.y][n.x]) == map.TILE_ROAD:
					canvas.draw_line(c, map.tile_center_px(n), col, ts * 0.3)
					linked = true
			if not linked:
				canvas.draw_circle(c, ts * 0.16, col)


## Туман войны — ЧЁРНАЯ ПЕЛЕНА (v1.40.2, правка приёмки: «убери облака,
## оставь чёрную пелену»; прежние стили clouds/parchment доступны через
## fog.style). Софтверный слой в ПОЛОВИННОМ разрешении: построение —
## один раз (кружки мглы по всем нераскрытым тайлам), раскрытие —
## стирание кругов по map.fog_new + update текстуры (дёшево при ходьбе).
func _build_fog_layer() -> void:
	if map == null:
		return
	# v1.43: на большой карте туман реже (кап 3072 по длинной стороне) —
	# вся математика кружков/стирания ниже идёт от _fog_hts, потому ровно
	_fog_hts = minf(map.ts / 2.0, BAKE_CAP * 0.75 / float(maxi(map.w, map.h)))
	var fw := int(map.w * _fog_hts)
	var fh := int(map.h * _fog_hts)
	_fog_img = Image.create_empty(fw, fh, false, Image.FORMAT_RGBA8)
	var fog_cfg: Dictionary = map.cfg.get("fog", {})
	var style := String(fog_cfg.get("style", "dark"))
	var light := Color(String(fog_cfg.get("cloud_light", "#c9cfd6")))
	var dark := Color(String(fog_cfg.get("cloud_dark", "#9aa3ad")))
	for y in map.h:
		for x in map.w:
			if map.is_explored(Vector2i(x, y)):
				continue
			var c := Vector2(float(x) + 0.5, float(y) + 0.5) * _fog_hts
			var h := float(_hash2(x, y, 7)) / 7.0
			match style:
				"parchment":
					var parch := Color(String(fog_cfg.get("parchment", "#d9c49a")))
					var parch_dark := Color(String(fog_cfg.get("parchment_dark", "#a8905e")))
					_stamp_circle(parch_dark.lerp(parch, h), c, _fog_hts * 0.9)
				"clouds":
					var wisp := light.lerp(dark, h)
					_stamp_circle(Color(wisp.r, wisp.g, wisp.b, 0.85), c, _fog_hts * (0.95 + 0.12 * h))
				_:
					# СПЛОШНАЯ чёрная пелена (v1.40.3, заказчик): единый
					# цвет без фактуры, кромка — рваная от кружков
					_stamp_circle(Color(0.02, 0.02, 0.045, 1.0), c, _fog_hts * 0.95)
	_fog_tex = ImageTexture.create_from_image(_fog_img)


## Штамп кружка в Image тумана (сборка слоя, один раз).
func _stamp_circle(col: Color, center: Vector2, r: float) -> void:
	var fw := _fog_img.get_width()
	var fh := _fog_img.get_height()
	var y0 := maxi(0, int(center.y - r))
	var y1 := mini(fh - 1, int(center.y + r))
	var x0 := maxi(0, int(center.x - r))
	var x1 := mini(fw - 1, int(center.x + r))
	var r2 := r * r
	for py in range(y0, y1 + 1):
		var dy := float(py) + 0.5 - center.y
		for px in range(x0, x1 + 1):
			var dx := float(px) + 0.5 - center.x
			if dx * dx + dy * dy <= r2:
				_fog_img.set_pixel(px, py, col)


## Стирание раскрытых тайлов: чистые круги радиусом «раскрытие + запас»
## (кромка мглы нераскрытых соседей естественно налезает на край — мягко).
func _erase_fog(tiles: Array) -> void:
	if _fog_img == null or _fog_tex == null:
		return
	var fw := _fog_img.get_width()
	var fh := _fog_img.get_height()
	var r := (float(map.cfg.get("fog_reveal_radius", 3)) + 1.0) * _fog_hts
	var r2 := r * r
	for t: Vector2i in tiles:
		var c := Vector2(float(t.x) + 0.5, float(t.y) + 0.5) * _fog_hts
		var y0 := maxi(0, int(c.y - r))
		var y1 := mini(fh - 1, int(c.y + r))
		var x0 := maxi(0, int(c.x - r))
		var x1 := mini(fw - 1, int(c.x + r))
		for py in range(y0, y1 + 1):
			var dy := float(py) + 0.5 - c.y
			for px in range(x0, x1 + 1):
				var dx := float(px) + 0.5 - c.x
				if dx * dx + dy * dy <= r2:
					_fog_img.set_pixel(px, py, Color(0, 0, 0, 0))
	_fog_tex.update(_fog_img)


func _draw_poi(poi: Dictionary, ts: float) -> void:
	var pos: Vector2 = Vector2(poi["tile"]) * ts + Vector2(ts, ts) / 2.0
	var color := Color(String(KIND_COLORS.get(String(poi["kind"]), "#ffffff")))
	# подложка-пятно цвета точки (видно поверх биома) + спрайт (M9)
	var pulse := 0.8 + 0.2 * sin(_time * 2.5)
	draw_circle(pos, ts * 0.62 * pulse, Color(color.r, color.g, color.b, 0.18))
	var ref: String = KIND_SPRITES.get(String(poi["kind"]), "")
	if ref != "":
		var fallen := String(poi["kind"]) == "settlement" and String(poi["state"]) == "fallen"
		# v1.41 («Мир v2», этап 3): живое поселение растёт — маркер крупнее
		# с числом жителей (город из 8 хижин меньше города в 30 дворов)
		var size := ts * 1.3
		if String(poi["kind"]) == "settlement" and not fallen:
			size *= clampf(1.0 + float(int(poi.get("npc_pop", 8))) / 40.0, 1.0, 1.5)
		Assets.draw_ref(self, ref, pos + Vector2(0, -2), size, false,
				Color(0.55, 0.5, 0.5) if fallen else Color.WHITE)
		if fallen:
			draw_line(pos + Vector2(-9, -11), pos + Vector2(9, 7), Color("#1a1a1a"), 3.0)
			draw_line(pos + Vector2(9, -11), pos + Vector2(-9, 7), Color("#1a1a1a"), 3.0)
	else:
		_draw_poi_fallback(poi, pos, color)
	if poi["tile"] == selected_tile:
		draw_rect(Rect2(pos - Vector2(16, 16), Vector2(32, 32)), Color("#ffffff"), false, 2.0)
	# уровень гнезда (M12): красные метки над лагерем — видно, насколько вырос
	var nest := int(poi.get("nest_level", 0))
	if String(poi["kind"]) == "camp" and nest > 0:
		for i in nest:
			draw_rect(Rect2(pos + Vector2(-9 + i * 7, -23), Vector2(5, 3)), Color("#e57373"))


## Запасной вид точек (примитивы, M8) — если спрайт не задан.
func _draw_poi_fallback(poi: Dictionary, pos: Vector2, color: Color) -> void:
	match String(poi["kind"]):
		"city":
			draw_rect(Rect2(pos - Vector2(14, 14), Vector2(28, 28)), color)
			draw_rect(Rect2(pos - Vector2(14, 14), Vector2(28, 28)), Color("#3a3128"), false, 2.0)
			draw_rect(Rect2(pos - Vector2(5, 12), Vector2(10, 12)), Color("#c78d5b"))
		"dungeon":
			_draw_diamond(pos, 11.0, color)
			_draw_diamond(pos, 5.0, Color("#2a1f33"))
		"ruins":
			draw_rect(Rect2(pos - Vector2(9, 9), Vector2(18, 18)), color)
			draw_rect(Rect2(pos - Vector2(9, 3), Vector2(7, 12)), Color("#6b6154"))
			draw_rect(Rect2(pos + Vector2(2, -9), Vector2(7, 18)), Color("#6b6154"))
		"camp":
			draw_rect(Rect2(pos - Vector2(1, 10), Vector2(2, 14)), Color("#5d4037"))
			var left := PackedVector2Array([pos + Vector2(-10, 4), pos + Vector2(0, -8), pos + Vector2(1, 4)])
			var right := PackedVector2Array([pos + Vector2(-1, 4), pos + Vector2(10, -6), pos + Vector2(10, 4)])
			draw_colored_polygon(left, color)
			draw_colored_polygon(right, color.darkened(0.2))
		"settlement":
			draw_rect(Rect2(pos - Vector2(10, 4), Vector2(20, 12)), color)
			draw_colored_polygon(PackedVector2Array(
					[pos + Vector2(-12, -4), pos, pos + Vector2(12, -4)]), color.darkened(0.25))
			if String(poi["state"]) == "fallen":
				draw_line(pos + Vector2(-8, -8), pos + Vector2(8, 8), Color("#1a1a1a"), 3.0)
				draw_line(pos + Vector2(8, -8), pos + Vector2(-8, 8), Color("#1a1a1a"), 3.0)
		"caravan":
			draw_circle(pos, 9.0, color)
			draw_circle(pos, 5.0, Color("#5d4037"))
			draw_rect(Rect2(pos + Vector2(1, -12), Vector2(2, 8)), Color("#5d4037"))
		"obelisk":
			draw_rect(Rect2(pos + Vector2(-4, -13), Vector2(8, 26)), color)
			draw_rect(Rect2(pos + Vector2(-2, -11), Vector2(3, 22)), color.lightened(0.3))


func _draw_diamond(pos: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(
			[pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0)]), color)


## Легендарный странник (v1.22): четырёхлучевая звезда своего цвета с белой
## сердцевиной; у гостящего в городе — мягкий пульс (его видно у ворот).
func _draw_legend(l: Dictionary, ts: float) -> void:
	var pos: Vector2 = map.tile_center_px(l["tile"])
	var def: Dictionary = l["def"]
	var col := Color(String(def.get("color", "#ffffff")))
	var pulse := 0.8 + 0.2 * sin(_time * 2.2 + float(int(l["id"])))
	if String(l["state"]) == "visit":
		draw_circle(pos, ts * 0.55, Color(col.r, col.g, col.b, 0.2 * pulse))
	draw_circle(pos + Vector2(0, 4), 5.0, Color(0, 0, 0, 0.3))
	# звезда: четыре луча ромбом + сердцевина
	var r := ts * 0.34
	draw_colored_polygon(PackedVector2Array(
			[pos + Vector2(0, -r), pos + Vector2(r * 0.35, -r * 0.35), pos + Vector2(r, 0),
			 pos + Vector2(r * 0.35, r * 0.35), pos + Vector2(0, r), pos + Vector2(-r * 0.35, r * 0.35),
			 pos + Vector2(-r, 0), pos + Vector2(-r * 0.35, -r * 0.35)]), col)
	draw_circle(pos, r * 0.38, Color(1, 1, 1, 0.95))


## След (M12): шеврон направления + пара отпечатков — читается как тропа.
func _draw_track(tile: Vector2i, dir: Vector2i, ts: float) -> void:
	var pos: Vector2 = map.tile_center_px(tile)
	var col := Color(0.3, 0.23, 0.15, 0.85)
	var v := Vector2(dir)
	var side := v.rotated(PI / 2.0)
	var tip: Vector2 = pos + v * (ts * 0.28)
	draw_line(tip - v * (ts * 0.22) + side * (ts * 0.16), tip, col, 2.0)
	draw_line(tip - v * (ts * 0.22) - side * (ts * 0.16), tip, col, 2.0)
	draw_circle(pos - v * (ts * 0.12) + side * (ts * 0.14), 1.8, col)
	draw_circle(pos - v * (ts * 0.12) - side * (ts * 0.14), 1.8, col)


## Гигант (M14-E/T19): крупный маркер с ореолом; кольцо — настроение
## (красный — разгневан, зелёный — дружелюбен).
func _draw_giant(g: Dictionary, contact_px: float) -> void:
	var pos: Vector2 = g["px"]
	var def: Dictionary = g["def"]
	var col := Color(String(def.get("color", "#999999")))
	var accent := Color(String(def.get("accent", "#ffffff")))
	var size := float(def.get("size", 2.0))
	var pulse := 0.85 + 0.15 * sin(_time * 1.6 + float(def.hash()))
	match String(g.get("mood", "neutral")):
		"angered":
			draw_circle(pos, contact_px + 8.0, Color(0.9, 0.2, 0.2, 0.14))
			draw_arc(pos, contact_px + 4.0, 0.0, TAU, 28, Color(1.0, 0.25, 0.25, 0.6), 2.0)
		"friendly":
			draw_circle(pos, contact_px + 8.0, Color(0.35, 0.9, 0.45, 0.13))
			draw_arc(pos, contact_px + 4.0, 0.0, TAU, 28, Color(0.4, 0.95, 0.5, 0.55), 2.0)
		_:
			draw_circle(pos, contact_px * 0.7, Color(col.r, col.g, col.b, 0.10 * pulse))
	# тень, тело, голова — «великан» крупнее героя втрое
	draw_circle(pos + Vector2(0, 8.0 * size * 0.6), 8.0 * size * 0.6, Color(0, 0, 0, 0.25))
	draw_circle(pos, 7.0 * size * 0.6, col)
	draw_circle(pos + Vector2(0, -7.0 * size * 0.7), 3.6 * size * 0.6, col.lightened(0.15))
	match String(def.get("id", "")):
		"forest_warden":
			# ветви-рога
			draw_line(pos + Vector2(-2, -12), pos + Vector2(-6, -18), accent, 1.6)
			draw_line(pos + Vector2(2, -12), pos + Vector2(6, -18), accent, 1.6)
			draw_circle(pos + Vector2(-3, -6), 1.2, accent)
		"ash_titan":
			# пепельные швы на теле
			draw_line(pos + Vector2(-3, -2), pos + Vector2(3, 3), accent, 1.2)
			draw_line(pos + Vector2(2, -5), pos + Vector2(-1, 0), accent, 1.0)
		"mammoth_spirit":
			# бивни
			draw_line(pos + Vector2(-3, -4), pos + Vector2(-6, 0), accent, 1.4)
			draw_line(pos + Vector2(3, -4), pos + Vector2(6, 0), accent, 1.4)


func _draw_route(ts: float) -> void:
	var world := get_parent()
	if world == null or world.travel == null or (world.travel as Dictionary).is_empty():
		return
	var path: Array = (world.travel as Dictionary)["path"]
	if path.size() < 2:
		return
	var points := PackedVector2Array()
	for i in range(1, path.size()):
		points.append(map.tile_center_px(path[i]))
	for i in points.size():
		draw_circle(points[i], 3.0, Color(1, 1, 1, 0.5) if i % 2 == 0 else Color(1, 1, 1, 0.25))
	draw_circle(points[points.size() - 1], 6.0, Color(1, 1, 1, 0.7))


## Зверь на карте мира (M14-C/T01): тело + голова, у рыбы — плеск-кружки.
func _draw_animal(a: Dictionary, def: Dictionary) -> void:
	if def.is_empty():
		return
	var pos: Vector2 = a["px"]
	var col := Color(String(def.get("color", "#cccccc")))
	var size := float(def.get("size", 1.0))
	var bob := absf(sin(_time * 3.0 + float(a["id"]))) * 1.5
	draw_circle(pos + Vector2(0, 4.0 * size), 5.0 * size, Color(0, 0, 0, 0.25))
	if String(def.get("behavior", "")) == "fish":
		# рыба: круги на воде
		var ripple := fmod(_time * 1.5 + float(a["id"]) * 0.7, 1.0)
		draw_arc(pos, 3.0 + ripple * 7.0, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.5 - ripple * 0.45), 1.5)
		draw_circle(pos, 2.5 * size, col)
		return
	# тело и голова, направление — к цели/от героя
	draw_circle(pos, 5.0 * size, col)
	draw_circle(pos + Vector2(4.0 * size, -2.0 * size - bob * 0.3), 2.8 * size, col.lightened(0.15))
	# хищника помечаем тёмной спинкой, мирных — светлым брюшком
	if String(def.get("behavior", "")) == "hunt":
		draw_circle(pos, 2.2 * size, col.darkened(0.35))
