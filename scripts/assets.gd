class_name Assets
extends Object
## Спрайты и текстуры (M9). Единый кэш: атлас Kenney Tiny Dungeon (16×16,
## сетка 12×11) + отдельные PNG в assets/sprites/. Ссылка на спрайт — строка:
##   "k:<индекс>"   — тайл атласа Kenney (индекс = ряд * 12 + колонка),
##   "img:<имя>"    — файл assets/sprites/<имя>.png (img:knight — герой),
##   "b:<id>"       — здание assets/sprites/buildings/<id>.png (генератор).
## Индексы подобраны по контрольному листу tools/spritemap.png.

const ATLAS := "res://assets/sprites/kenney.png"
const ATLAS_SPRITES := "res://assets/sprites/kenney_sprites.png"
const ATLAS_COLS := 12
const ATLAS_TS := 16
const SPRITE_FROM := 60  # тайлы 60+ — существа/предметы, фон вырезан (prepare_atlas.py)

static var _cache: Dictionary = {}


static func tex(path: String) -> Texture2D:
	if not _cache.has(path):
		var t: Texture2D = load(path)
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


## Размер по высоте (ширина с пропорциями) — для расчёта прямоугольников.
static func ref_size(ref: String, size_px: float) -> Vector2:
	var t := sprite(ref)
	if t == null:
		return Vector2(size_px, size_px)
	var s := size_px / float(t.get_height())
	return Vector2(t.get_width() * s, size_px)
