extends Node2D
## Туман войны данжа с ПЛАВНЫМ краем (v1.33.2–v1.33.3). Неисследованное —
## чёрное, изученное — приглушённая «память», у героя — чистый тёплый свет.
## Край — сетка квадратов с альфой в ВЕРШИНАХ (билинейная интерполяция)
## и радиальным спадом smoothstep от героя: никаких квадратных ступеней
## (замечание заказчика «расплываться плавнее», «плавный свет и тени»).
##
## v1.33.3: ТЕНИ ОТ СТЕН тоже рисует этот слой — по линии взгляда (LOS,
## словарь visible_now из dungeon.gd::_update_fog): тайл в радиусе света,
## но ЗА стеной, затемнён до «памяти» — тёплая лужа света обрезается
## стенами с мягким градиентным краем. Движковые тени PointLight2D
## отключены (экструзия больших окклюдеров глючила — глохла вся лужа).
##
## Альфа вершины = MAX( база_состояния × радиальный_спад,
##                       MEMORY × (1 − видимость_LOS) )
##   LOS-тайл у героя  → 0 (чистый свет фонаря)
##   LOS-тайл на краю  → база × спад (плавное расплывание в дымку)
##   за стеной         → MEMORY (тень стены, мягкая по вершинам)
##   неисследованное   → 1.0 (чёрное)
## База/видимость в вершине — минимум/максимум по 4 смежным тайлам
## (диагональные края сглаживаются сами).

var gen = null
var ts := 32
var visited: Dictionary = {}      # изученные полы (накопительно)
var visible_now: Dictionary = {}  # полы в поле зрения героя сейчас (LOS)
var hero_pos := Vector2.ZERO      # центр мягкого круга (мировые px)
# «память»: изученное вне света темнее живого обзора, но читается
const MEMORY_ALPHA := 0.45
# Мягкий переход (в тайлах): внутри fade_in — чисто (работает свет
# фонаря радиусом 5.0), к fade_out туман расплывается полным; полоса
# ~4 тайла — тёплый спад света перетекает в дымку без подрезки
var fade_in := 5.0
var fade_out := 9.0


func setup(dungeon_gen: Object, tile_size: int) -> void:
	gen = dungeon_gen
	ts = tile_size
	z_index = 40


## Базовая альфа тайла: неизвестное — 1.0, изученное — «память».
func _tile_base(t: Vector2i) -> float:
	if visited.has(t) or _any_neighbor_visited(t):
		return MEMORY_ALPHA
	return 1.0


func _any_neighbor_visited(t: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if visited.has(t + Vector2i(dx, dy)):
				return true
	return false


## Глубинный войд (не-пол дальше кольца от пола) уже нарисован чёрным
## в dungeon_view — непрозрачный туман поверх него не нужен.
func _near_floor(t: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if gen.is_floor(t + Vector2i(dx, dy)):
				return true
	return false


func _draw() -> void:
	if gen == null:
		return
	var w: int = gen.w
	var h: int = gen.h
	# 1) вершины сетки: база (мин по 4 тайлам) и LOS-видимость (макс)
	var corners := PackedFloat32Array()
	corners.resize((w + 1) * (h + 1))
	var lit := PackedFloat32Array()
	lit.resize((w + 1) * (h + 1))
	var offs: Array = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]
	for cy in h + 1:
		for cx in w + 1:
			var base := 1.0
			var see := 0.0
			for d in offs:
				var t: Vector2i = Vector2i(cx, cy) + d
				if t.x < 0 or t.y < 0 or t.x >= w or t.y >= h:
					continue
				var b := _tile_base(t)
				if b < base:
					base = b
				if visible_now.has(t):
					see = 1.0
			corners[cy * (w + 1) + cx] = base
			lit[cy * (w + 1) + cx] = see
	# 2) отрисовка: альфа угла = max(база × спад, MEMORY × (1 − LOS))
	var black := Color(0.008, 0.008, 0.014)
	var fi_px := fade_in * float(ts)
	var fi_w := fade_out * float(ts) - fi_px
	for y in h:
		for x in w:
			var i00 := corners[y * (w + 1) + x]           # верх-лево
			var i10 := corners[y * (w + 1) + x + 1]       # верх-право
			var i01 := corners[(y + 1) * (w + 1) + x]     # низ-лево
			var i11 := corners[(y + 1) * (w + 1) + x + 1] # низ-право
			if i00 >= 0.999 and i10 >= 0.999 and i01 >= 0.999 and i11 >= 0.999 \
					and not _near_floor(Vector2i(x, y)):
				continue   # сплошная тьма над войдом — уже чёрное
			if maxf(maxf(i00, i10), maxf(i01, i11)) <= 0.01:
				continue   # изученного рядом нет — внутри света/тьмы рисуем только тьму
			var p := Vector2(x, y) * ts
			var quad := PackedVector2Array([
				p, p + Vector2(ts, 0), p + Vector2(ts, ts), p + Vector2(0, ts)])
			var cols := PackedColorArray([
				_corner_col(black, i00, lit[y * (w + 1) + x], quad[0], fi_px, fi_w),
				_corner_col(black, i10, lit[y * (w + 1) + x + 1], quad[1], fi_px, fi_w),
				_corner_col(black, i11, lit[(y + 1) * (w + 1) + x + 1], quad[2], fi_px, fi_w),
				_corner_col(black, i01, lit[(y + 1) * (w + 1) + x], quad[3], fi_px, fi_w),
			])
			if cols[0].a <= 0.004 and cols[1].a <= 0.004 \
					and cols[2].a <= 0.004 and cols[3].a <= 0.004:
				continue
			draw_polygon(quad, cols)


## Цвет угла квадрата тумана: альфа = max(база × радиальный спад,
## MEMORY × (1 − LOS)) — тень стены не перекрывает чистый свет рядом.
func _corner_col(black: Color, base: float, see: float, pt: Vector2,
		fi_px: float, fi_w: float) -> Color:
	var a := maxf(base * _fade_at(pt, fi_px, fi_w), MEMORY_ALPHA * (1.0 - see))
	return Color(black.r, black.g, black.b, a)


## Радиальный спад 0..1 в точке (0 у героя, 1 за fade_out).
func _fade_at(pt: Vector2, fi_px: float, fi_w: float) -> float:
	var u := clampf((hero_pos.distance_to(pt) - fi_px) / maxf(1.0, fi_w), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)   # smoothstep
