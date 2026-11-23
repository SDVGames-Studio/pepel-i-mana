class_name Assets
extends Object
## Спрайты и текстуры (M9). Единый кэш: атлас Kenney Tiny Dungeon (16×16,
## сетка 12×11) + отдельные PNG в assets/sprites/. Ссылка на спрайт — строка:
##   "k:<индекс>"   — тайл атласа Kenney (индекс = ряд * 12 + колонка),
##   "img:<имя>"    — файл assets/sprites/<имя>.png (img:knight — герой),
##   "b:<id>"       — здание assets/sprites/buildings/<id>.png (генератор),
##   "e:<имя>"      — файл assets/sprites/env|props|plants/<имя>.png (M10).
## Индексы подобраны по контрольному листу tools/spritemap.png.

const ATLAS := "res://assets/sprites/kenney.png"
const ATLAS_SPRITES := "res://assets/sprites/kenney_sprites.png"
const ATLAS_COLS := 12
const ATLAS_TS := 16
const SPRITE_FROM := 60  # тайлы 60+ — существа/предметы, фон вырезан (prepare_atlas.py)

static var _cache: Dictionary = {}
static var _biome_manifest: Dictionary = {}
static var _biome_manifest_read := false
const TS_G := 32   # размер тайла земли для uniform_ground

## v1.76.1: манифест биомов заказчика (tools/slice_biomes.py) —
## пути травы/воды/деревьев для сезонных и региональных скинов.
static func biome_manifest() -> Dictionary:
	if not _biome_manifest_read:
		_biome_manifest_read = true
		var f := FileAccess.open("res://assets/sprites/env/biomes/manifest.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_biome_manifest = parsed
		# v1.78.0: собранные в ИГРЕ биомы (композитор) — user://
		var d := DirAccess.open("user://biomes_composed")
		if d != null:
			for dir in d.get_directories():
				var bf := FileAccess.open("user://biomes_composed/%s/biome.json" % dir, FileAccess.READ)
				if bf == null:
					continue
				var bp: Variant = JSON.parse_string(bf.get_as_text())
				if bp is Dictionary:
					_biome_manifest[dir] = bp
	return _biome_manifest

static func reload_biome_manifest() -> void:
	_biome_manifest_read = false
	_biome_manifest = {}

## ЕДИНЫЙ РЕЦЕПТ ЗЕМЛИ (v1.78.0): путям травы -> [текстуры (6),
## подложки (6)]. Общий тон набора, нормализация каналов к нему
## (0.7..1.4), мягкие края (0.35..1.0), сплошная подложка. Используют
## композитор (превью), город и стенд — одинаковая земля везде.
static func uniform_ground(paths: Array) -> Array:
	var imgs: Array = []
	for p in paths:
		var t: Texture2D = tex(String(p))
		if t != null:
			imgs.append(t.get_image())
	return uniform_ground_imgs(imgs)


## v1.78.5: рецепт прямо из Image (композитор нарезает клетки листов
## заказчика в память — путей ещё не существует до сохранения).
static func uniform_ground_imgs(imgs: Array) -> Array:
	if imgs.is_empty():
		return [[], []]
	# v1.78.9: тон между тайлами выравнивается ЖЁСТЧЕ (0.8..1.25 вместо
	# 0.7..1.4) — разнотон соседей читался «композицией из тайлов»
	# (см. _normalize_ratio ниже)
	var means := []
	for im: Image in imgs:
		var sm := Vector3(0, 0, 0)
		var n := 0
		for y in TS_G:
			for x in TS_G:
				var c := im.get_pixel(x, y)
				# v1.78.5: прозрачные пиксели (чистка шашечки листов) не
				# тянут тон вниз — учитываются только видимые
				if c.a >= 0.5:
					sm += Vector3(c.r8, c.g8, c.b8)
					n += 1
		means.append(sm / float(maxi(1, n)))
	var acc := Vector3(0, 0, 0)
	for m in means:
		acc += m
	var shared := acc / float(means.size())
	var shared_c := Color(clampf(shared.x, 1, 254) / 255.0, clampf(shared.y, 1, 254) / 255.0, clampf(shared.z, 1, 254) / 255.0)
	var texs: Array = []
	var fills: Array = []
	for im: Image in imgs:
		var tm: Vector3 = means[imgs.find(im)]
		# v1.78.9: БЕСШОВНОСТЬ — тайлы листов заказчика это кусочки
		# иллюстраций с жёсткими краями: при стыковке каждый читался
		# отдельным квадратиком («композиция из многих тайлов»).
		# Края тайла зеркально сливаются с противоположными (правый край
		# ↔ левый, верх ↔ низ): тайл стыкуется сам с собой бесшовно,
		# а с нормализованным тоном набора — и с любым соседом.
		var W := im.get_width()
		var H := im.get_height()
		var src := []
		for y in H:
			for x in W:
				var c0 := im.get_pixel(x, y)
				var ratio := Vector3(
						clampf(shared.x / maxf(tm.x, 1.0), 0.8, 1.25),
						clampf(shared.y / maxf(tm.y, 1.0), 0.8, 1.25),
						clampf(shared.z / maxf(tm.z, 1.0), 0.8, 1.25))
				if c0.a < 0.5:
					src.append(shared_c)
				else:
					src.append(Color(clampf(c0.r8 * ratio.x, 0, 255) / 255.0,
							clampf(c0.g8 * ratio.y, 0, 255) / 255.0,
							clampf(c0.b8 * ratio.z, 0, 255) / 255.0, 1.0))
		var out := Image.create(TS_G, TS_G, false, Image.FORMAT_RGBA8)
		var F := 7
		for y in TS_G:
			for x in TS_G:
				var c: Color = src[y * W + x]
				var wx := 0.0
				if x < F:
					wx = 0.5 * (1.0 - float(x) / float(F))
				elif x >= W - F:
					wx = 0.5 * (1.0 - float(W - 1 - x) / float(F))
				if wx > 0.0:
					c = c.lerp(src[y * W + (W - 1 - x)], wx)
				var wy := 0.0
				if y < F:
					wy = 0.5 * (1.0 - float(y) / float(F))
				elif y >= H - F:
					wy = 0.5 * (1.0 - float(H - 1 - y) / float(F))
				if wy > 0.0:
					c = c.lerp(src[(H - 1 - y) * W + x], wy)
				out.set_pixel(x, y, c)
		texs.append(ImageTexture.create_from_image(out))
		var fl := Image.create(TS_G, TS_G, false, Image.FORMAT_RGBA8)
		fl.fill(shared_c)
		fills.append(ImageTexture.create_from_image(fl))
	while texs.size() < 6:
		texs.append(texs[texs.size() % maxi(1, texs.size())])
		fills.append(fills[fills.size() % maxi(1, fills.size())])
	return [texs, fills]

## Тег биома для сезона (весна/осень/зима из папок заказчика; лето —
## отдельный принятый атлас env/summer).
static func biome_tag_for_season(season: String) -> String:
	# v1.77.0: собранные заказчиком биомы (compose_biome.py) с полем
	# season перекрывают вшитые сезонные теги
	var mf := biome_manifest()
	for tag in mf:
		if String((mf[tag] as Dictionary).get("season", "")) == season:
			return String(tag)
	match season:
		"spring": return "весна"
		"autumn": return "осень"
		"winter": return "зима"
		"summer": return "summer"
	return ""


static func tex(path: String) -> Texture2D:
	if not _cache.has(path):
		var t: Texture2D = null
		if path.begins_with("user://"):
			# v1.78.5: патчи композитора (user://biomes_composed/...) — мимо
			# импорт-системы редактора, грузим с диска напрямую: биом работает
			# СРАЗУ после сохранения, без переимпорта и в экспорте тоже
			var abs := ProjectSettings.globalize_path(path)
			var im := Image.load_from_file(abs)
			if im != null and not im.is_empty():
				t = ImageTexture.create_from_image(im)
		else:
			t = load(path)
		_cache[path] = t
	return _cache[path]


## Текстура по ссылке "k:N" / "img:имя" / "b:id". Пустая строка — null.
static func sprite(ref: String) -> Texture2D:
	if ref == "":
		return null
	if ref.begins_with("k:"):
		return kenney(int(ref.substr(2)))
	if ref.begins_with("img:"):
		return tex("res://assets/sprites/%s.png" % ref.substr(4))
	if ref.begins_with("b:"):
		return tex("res://assets/sprites/buildings/%s.png" % ref.substr(2))
	if ref.begins_with("e:"):
		var name := ref.substr(2)
		for dir in ["env", "props", "plants"]:
			var path := "res://assets/sprites/%s/%s.png" % [dir, name]
			if ResourceLoader.exists(path):
				return tex(path)
		return null
	if ref.begins_with("p:"):
		# пропы-предметы (M12, tools/make_props.py)
		return tex("res://assets/sprites/props/%s.png" % ref.substr(2))
	if ref.begins_with("pc:"):
		# пропсы города/кладбища (v1.63, нарезка заказчика 118 шт — ASSETS.md)
		return tex("res://assets/sprites/props_city/%s.png" % ref.substr(3))
	return null


## Тайл атласа Kenney как AtlasTexture (кэш по индексу). 0–59 — тайлы среды,
## 60+ — существа/предметы с прозрачным фоном (копия kenney_sprites.png).
static func kenney(idx: int) -> Texture2D:
	var key := "k:%d" % idx
	if not _cache.has(key):
		var base := tex(ATLAS_SPRITES if idx >= SPRITE_FROM else ATLAS)
		if base == null:
			_cache[key] = null
			return null
		var at := AtlasTexture.new()
		at.atlas = base
		@warning_ignore("integer_division")
		at.region = Rect2((idx % ATLAS_COLS) * ATLAS_TS, (idx / ATLAS_COLS) * ATLAS_TS, ATLAS_TS, ATLAS_TS)
		_cache[key] = at
	return _cache[key]


## Нарисовать спрайт в _draw() канваса: центр pos, высота size_px.
## flip — отражение по горизонтали, tint — modulate-цвет.
static func draw_ref(canvas: CanvasItem, ref: String, pos: Vector2, size_px: float,
		flip := false, tint := Color.WHITE) -> void:
	var t := sprite(ref)
	if t == null:
		return
	var src := Rect2(Vector2.ZERO, t.get_size())
	if t is AtlasTexture:
		src = (t as AtlasTexture).region
	var s := size_px / float(t.get_height())
	var w := t.get_width() * s
	var dst := Rect2(pos - Vector2(w, size_px) * 0.5, Vector2(w, size_px))
	if flip:
		dst.size.x = -dst.size.x
	canvas.draw_texture_rect_region(t, dst, src, tint)


## Зверь из листов заказчика (волна 2026-11-23): art = {frames: [...],
## idle_n: N, h: px}. Кадры [0..idle_n) — айдл, хвост — бег (8 fps).
## Возвращает false, если art нет — вызывающий рисует процедурно.
static func draw_animal_art(canvas: CanvasItem, art: Dictionary, pos: Vector2,
		moving: bool, t: float, flip := false) -> bool:
	if art.is_empty() or not art.has("frames"):
		return false
	var frames: Array = art["frames"]
	var idle_n := mini(maxi(1, int(art.get("idle_n", 2))), frames.size())
	var idx: int
	if moving and frames.size() > idle_n:
		idx = idle_n + (int(t * 8.0) % (frames.size() - idle_n))
	else:
		idx = int(t * 2.0) % idle_n
	draw_ref(canvas, String(frames[idx]), pos, float(art.get("h", 20.0)), flip)
	return true


## Размер по высоте (ширина с пропорциями) — для расчёта прямоугольников.
static func ref_size(ref: String, size_px: float) -> Vector2:
	var t := sprite(ref)
	if t == null:
		return Vector2(size_px, size_px)
	var s := size_px / float(t.get_height())
	return Vector2(t.get_width() * s, size_px)


# --- листы анимаций (M10, craftpix) ----------------------------------------
## Имя -> [путь, ширина кадра, высота кадра, кадров в ряду, рядов].
## Граждане: направления d/s/u отдельными файлами (side = левый, правый — отражение).
## Орки/животные: ряды в листе: 0-лицом 1-спиной 2-влево 3-вправо (у животных
## 0-3 idle, 4-7 walk в том же порядке лицом/спиной/влево/вправо).
const SHEETS := {
	"cit1_d_walk": ["res://assets/sprites/citizens/c1_d_walk.png", 48, 48, 6, 1],
	"cit1_s_walk": ["res://assets/sprites/citizens/c1_s_walk.png", 48, 48, 6, 1],
	"cit1_u_walk": ["res://assets/sprites/citizens/c1_u_walk.png", 48, 48, 6, 1],
	"cit1_d_idle": ["res://assets/sprites/citizens/c1_d_idle.png", 48, 48, 4, 1],
	"cit1_s_idle": ["res://assets/sprites/citizens/c1_s_idle.png", 48, 48, 4, 1],
	"cit1_u_idle": ["res://assets/sprites/citizens/c1_u_idle.png", 48, 48, 4, 1],
	"cit2_d_walk": ["res://assets/sprites/citizens/c2_d_walk.png", 48, 48, 6, 1],
	"cit2_s_walk": ["res://assets/sprites/citizens/c2_s_walk.png", 48, 48, 6, 1],
	"cit2_u_walk": ["res://assets/sprites/citizens/c2_u_walk.png", 48, 48, 6, 1],
	"cit2_d_idle": ["res://assets/sprites/citizens/c2_d_idle.png", 48, 48, 4, 1],
	"cit2_s_idle": ["res://assets/sprites/citizens/c2_s_idle.png", 48, 48, 4, 1],
	"cit2_u_idle": ["res://assets/sprites/citizens/c2_u_idle.png", 48, 48, 4, 1],
	"cit3_d_walk": ["res://assets/sprites/citizens/c3_d_walk.png", 48, 48, 6, 1],
	"cit3_s_walk": ["res://assets/sprites/citizens/c3_s_walk.png", 48, 48, 6, 1],
	"cit3_u_walk": ["res://assets/sprites/citizens/c3_u_walk.png", 48, 48, 6, 1],
	"cit3_d_idle": ["res://assets/sprites/citizens/c3_d_idle.png", 48, 48, 4, 1],
	"cit3_s_idle": ["res://assets/sprites/citizens/c3_s_idle.png", 48, 48, 4, 1],
	"cit3_u_idle": ["res://assets/sprites/citizens/c3_u_idle.png", 48, 48, 4, 1],
	"cit4_d_walk": ["res://assets/sprites/citizens/c4_d_walk.png", 48, 48, 6, 1],
	"cit4_s_walk": ["res://assets/sprites/citizens/c4_s_walk.png", 48, 48, 6, 1],
	"cit4_u_walk": ["res://assets/sprites/citizens/c4_u_walk.png", 48, 48, 6, 1],
	"cit4_d_idle": ["res://assets/sprites/citizens/c4_d_idle.png", 48, 48, 4, 1],
	"cit4_s_idle": ["res://assets/sprites/citizens/c4_s_idle.png", 48, 48, 4, 1],
	"cit4_u_idle": ["res://assets/sprites/citizens/c4_u_idle.png", 48, 48, 4, 1],
	"orc1_walk": ["res://assets/sprites/orcs/orc1_walk.png", 64, 64, 6, 4],
	"orc1_idle": ["res://assets/sprites/orcs/orc1_idle.png", 64, 64, 4, 4],
	"orc2_walk": ["res://assets/sprites/orcs/orc2_walk.png", 64, 64, 6, 4],
	"orc2_idle": ["res://assets/sprites/orcs/orc2_idle.png", 64, 64, 4, 4],
	"orc3_walk": ["res://assets/sprites/orcs/orc3_walk.png", 64, 64, 6, 4],
	"orc3_idle": ["res://assets/sprites/orcs/orc3_idle.png", 64, 64, 4, 4],
	"cow": ["res://assets/sprites/animals/cow.png", 32, 32, 6, 8],
	"sheep": ["res://assets/sprites/animals/sheep.png", 32, 32, 6, 8],
	"pig": ["res://assets/sprites/animals/pig.png", 32, 32, 6, 8],
	"chicken": ["res://assets/sprites/animals/chicken.png", 32, 32, 6, 8],
	"turkey": ["res://assets/sprites/animals/turkey.png", 32, 32, 6, 8],
	"fire": ["res://assets/sprites/props/fire.png", 32, 32, 5, 1],
}


## Кадр листа как AtlasTexture (кэш «имя:кадр»).
static func sheet_frame(sheet: String, frame: int) -> Texture2D:
	var key := "%s:%d" % [sheet, frame]
	if not _cache.has(key):
		var info: Array = SHEETS.get(sheet, [])
		if info.is_empty():
			_cache[key] = null
			return null
		var base := tex(String(info[0]))
		if base == null:
			_cache[key] = null
			return null
		var fw := int(info[1])
		var fh := int(info[2])
		var cols := int(info[3])
		@warning_ignore("integer_division")
		var fx := (frame % cols) * fw
		@warning_ignore("integer_division")
		var fy := (frame / cols) * fh
		var at := AtlasTexture.new()
		at.atlas = base
		at.region = Rect2(fx, fy, fw, fh)
		_cache[key] = at
	return _cache[key]


## Нарисовать кадр листа: центр pos, высота size_px (draw_ref-совместимо).
static func draw_sheet(canvas: CanvasItem, sheet: String, frame: int, pos: Vector2,
		size_px: float, flip := false, tint := Color.WHITE) -> void:
	var t := sheet_frame(sheet, frame)
	if t == null:
		return
	var region: Rect2 = (t as AtlasTexture).region
	var s := size_px / region.size.y
	var w := region.size.x * s
	var dst := Rect2(pos - Vector2(w, size_px) * 0.5, Vector2(w, size_px))
	if flip:
		dst.size.x = -dst.size.x
	canvas.draw_texture_rect_region((t as AtlasTexture).atlas, dst, region, tint)


## Направление движения "front|back|left|right" из вектора скорости.
static func dir_of(vel: Vector2) -> String:
	if vel.length() < 0.5:
		return "front"
	if absf(vel.x) >= absf(vel.y):
		return "left" if vel.x < 0.0 else "right"
	return "back" if vel.y < 0.0 else "front"


## Гражданин (4 варианта, направления d/s/u; влево — отражение side).
## variant 1..4, dir front|back|left|right, t — время для кадров.
static func draw_citizen(canvas: CanvasItem, variant: int, dir: String, moving: bool,
		pos: Vector2, size_px: float, t: float, tint := Color.WHITE) -> void:
	var v := clampi(variant, 1, 4)
	var kind := "walk" if moving else "idle"
	var d := "d"
	var flip := false
	match dir:
		"back":
			d = "u"
		"left":
			d = "s"
		"right":
			d = "s"
			flip = true
	var sheet := "cit%d_%s_%s" % [v, d, kind]
	var frames := 6 if moving else 4
	draw_sheet(canvas, sheet, int(t * 8.0) % frames, pos, size_px, flip, tint)


## Орк (лист 4 ряда: лицем/спиной/влево/вправо). anim "walk"|"idle".
static func draw_orc(canvas: CanvasItem, base: String, dir: String, moving: bool,
		pos: Vector2, size_px: float, t: float, tint := Color.WHITE) -> void:
	var row := 0
	match dir:
		"back": row = 1
		"left": row = 2
		"right": row = 3
	var anim := "walk" if moving else "idle"
	var cols := 6 if moving else 4
	var sheet := "%s_%s" % [base, anim]
	draw_sheet(canvas, sheet, row * cols + int(t * 8.0) % cols, pos, size_px, false, tint)


## Животное (лист 8 рядов: 0-3 idle, 4-7 walk; лицем/спиной/влево/вправо).
static func draw_animal(canvas: CanvasItem, kind: String, dir: String, moving: bool,
		pos: Vector2, size_px: float, t: float, tint := Color.WHITE) -> void:
	if not SHEETS.has(kind):
		return
	var d := 0
	match dir:
		"back": d = 1
		"left": d = 2
		"right": d = 3
	var row := d + (4 if moving else 0)
	draw_sheet(canvas, kind, row * 6 + int(t * 6.0) % 6, pos, size_px, false, tint)


# --- жители-профессии Minifolks (v1.49): лист 10×8 кадров 32×32 --------------
# Ряд 0 — покой (4 кадра), ряд 1 — ходьба (10), ряд 2 — работа инструментом (4).
# Листы смотрят вправо — влево отражаем. Профессии без листа -> false (кружок).

const VILLAGER_PROF := {
	"lumberjack": "KitLumberjack",  # v1.71: рубка топором из атласа строителя
	"miner": "KitMiner",            # v1.72: шахтёр-гном (атлас заказчика)
	"smith": "KitSmith",            # v1.72: средневековый кузнец
	"smelter": "KitSmelter",        # v1.72: гном-плавильщик (тигель с жаром)
	"armorer": "KitArmorer",        # v1.72: кузнец-дварф (оружейная)
	"hunter": "KitHunter",          # v1.72: лучник (стрельба из лука)
	"farmer": "KitFarmer",          # v1.71: землёй в присяде (атлас фермера)
	"builder": "KitBuilder",        # v1.71: атлас заказчика «строитель-воин»
	"porter": "KitPorter",          # v1.72: носильщик (бочки/ящики)
	"bartender": "KitBartender",    # v1.72: тавернщик (кружки)
	"trader": "KitTrader",          # v1.72: купец (товар/мешок)
	"healer": "KitHealer",          # v1.72: травница-лекарь (снадобье)
	"acolyte": "KitAcolyte",        # v1.72: маг-ученик (заклинание)
	"guard": "KitGuard",            # v1.72: стражник (щит наперевес)
	"crafter": "KitMaster",         # v1.72: мастер (ремесленный двор, молот)
	"fisher": "KitFisher",          # v1.72: рыбак (улов на руках)
	"elder": "KitElder",            # v1.72.1: староста-гуманоид (старейшина-маг,
	                                #   решение заказчика — вместо голема-кружка)
}

const VILLAGER_FRAME := 32.0     # кадр листа
const VILLAGER_CHAR_H := 26.0    # видимый рост фигуры в Kit-кадре (26/32,
						 # v1.75.2: было 13.5 под старые Minifolks — жители были х2)

const VILLAGER_FEET_Y := 30.0    # ноги от верха кадра
const VILLAGER_VISIBLE_H := 27.0 # целевой видимый рост жителя (рыцарь — 31, v1.67.2)

## Раскладка рядов ИЗМЕРЕНА по каждому листу (у Minifolks она разная):
## idle всегда ряд 0 (4 кадра); walk — ряд с максимумом кадров; work —
## соседний с walk ряд с 3–8 кадрами (walk-1, иначе walk+1).
const VILLAGER_ROWS := {
	"MiniBlacksmithB": [1, 10, 2, 4],
	"MiniGatherer": [2, 10, 1, 5],
	"MiniGraveDigger": [1, 10, 2, 5],
	"MiniHunter": [3, 10, 2, 3],
	"MiniLumberjack": [1, 7, 2, 6],
	"MiniMerchantB": [1, 9, 2, 7],
	"MiniMiner": [1, 6, 2, 5],
	"MiniNun": [2, 6, 1, 3],
	"MiniSuspiciousMerchantB": [1, 7, 2, 6],
	"MiniThief": [1, 10, 2, 6],
	# v1.71: листы кита заказчика (10 колонок): [walk_row, walk_n, work_row, work_n]
	"KitBuilder": [1, 6, 2, 4],
	"KitLumberjack": [1, 6, 2, 4],
	"KitFarmer": [1, 6, 2, 4],
	# v1.72: волна 2 «Жители кита» — 14 листов (walk_n по факту фигур в ряду)
	"KitSmith": [1, 6, 2, 4],
	"KitPorter": [1, 5, 2, 4],
	"KitHealer": [1, 6, 2, 4],
	"KitFisher": [1, 6, 2, 4],
	"KitHunter": [1, 5, 2, 4],
	"KitMaster": [1, 6, 2, 4],
	"KitElder": [1, 6, 2, 4],       # задел: староста в игре — голем (v1.20)
	"KitBartender": [1, 6, 2, 4],
	"KitAcolyte": [1, 6, 2, 4],
	"KitArmorer": [1, 6, 2, 4],
	"KitSmelter": [1, 6, 2, 4],
	"KitTrader": [1, 5, 2, 4],
	"KitGuard": [1, 6, 2, 4],
	"KitMiner": [1, 6, 2, 4],
}

## Размер кадра при отрисовке: из целевого видимого роста.
static func villager_size() -> float:
	return VILLAGER_VISIBLE_H * VILLAGER_FRAME / VILLAGER_CHAR_H

static var _villager_texs: Dictionary = {}   # base -> Texture2D (кэш)

## Житель-профессия листом Minifolks. dir — «left»/«right» (виды спереди);
## working — анимация работы (ряд 2). pos — ТОЧКА НОГ (якорь y-сортировки):
## видимый рост ~23px против 32 у рыцаря. False — листа нет (рисовать кружок).
static func draw_villager(canvas: CanvasItem, prof: String, dir: String, moving: bool,
		working: bool, pos: Vector2, t: float, tint := Color.WHITE, scale := 1.0) -> bool:
	if not VILLAGER_PROF.has(prof) or not VILLAGER_ROWS.has(VILLAGER_PROF[prof]):
		return false
	var base: String = VILLAGER_PROF[prof]
	var rows: Array = VILLAGER_ROWS[base]   # [walk_row, walk_n, work_row, work_n]
	if not _villager_texs.has(base):
		_villager_texs[base] = tex("res://assets/sprites/villagers/%s.png" % base)
	var sheet: Texture2D = _villager_texs[base]
	if sheet == null:
		return false
	var row := 0
	var frames := 4
	var fps := 4.0
	if moving:
		row = int(rows[0])
		frames = int(rows[1])
		fps = maxf(4.0, float(frames) * 0.8)
	elif working:
		row = int(rows[2])
		frames = int(rows[3])
		fps = 5.0
	var f := int(t * fps) % maxi(1, frames)
	var cs := VILLAGER_FRAME
	var src := Rect2(float(f % 10) * cs, float(row) * cs, cs, cs)
	var s := villager_size() * scale   # v1.64: расовый рост (дворф/гном ниже)
	# ноги персонажа (y=30 кадра) стоят в pos; кадр чуть больше видимого тела
	var dst := Rect2(Vector2(pos.x - s * 0.5, pos.y - VILLAGER_FEET_Y / cs * s), Vector2(s, s))
	if dir == "left":
		dst.size.x = -dst.size.x
	canvas.draw_texture_rect_region(sheet, dst, src, tint)
	return true
