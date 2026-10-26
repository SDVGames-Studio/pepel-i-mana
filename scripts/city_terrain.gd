extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Статический слой города (M9/M10, переработан в M11): ландшафт не меняется
## в течение игры. v1.21.5: ландшафт ЗАПЕКАЕТСЯ в текстуру SubViewport и
## рисуется одним квадратом — раньше ~12 000 векторных команд карты рендерер
## перемалывал каждый кадр (это и держало город на 10–15 FPS). Перевыпечка —
## по rebake() (сцена зовёт при sim.terrain_dirty, не чаще 2 раз/сек).
##
## M11 по замечаниям заказчика:
##  - земля без «шахматного порядка»: плавные пятна травы (шум крупными
##    блоками) плюс мелкое зерно яркости на каждом тайле;
##  - скалы — ЕДИНАЯ гряда: тёмное основание связывает тайлы в массив,
##    внутренние тайлы крупнее и темнее, края светлее; трещины по мере выработки.

var map = null
var sim = null                   # город (v1.22): зоны/дороги/плиты площади в духовке
var colors: Dictionary = {}
var _zone_colors: Dictionary = {}   # тип зоны -> цвет заливки (v1.22)
var _grass_shades: Array = []
var _rock_deep := Color("#565248")
var _rock_hp_default := 80.0
var _vp: SubViewport = null
var _drawer: Node2D = null
var _tex: Texture2D = null


func setup(city_map, city_cfg: Dictionary, city_sim = null) -> void:
	map = city_map
	sim = city_sim
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		colors[key] = Color(String(c[key]))
	for t in city_cfg.get("zones", {}).get("types", {}):
		_zone_colors[String(t)] = Color(String(city_cfg["zones"]["types"][t]["color"]))
	_grass_shades = [colors["grass"], colors.get("grass_alt", colors["grass"]),
			colors.get("grass2", colors["grass"]).darkened(0.03)]
	_rock_deep = colors.get("rock_deep", Color("#565248"))
	_rock_hp_default = float(city_cfg.get("mountain", {}).get("hp", 80.0))
	# духовка: SubViewport размером с карту, содержимое — те же тайлы.
	# Сама выпечка — в _ready(): до входа в дерево SubViewport не рендерится
	# (UPDATE_ONCE сгорает впустую — на этом ловились пустые текстуры).
	_vp = SubViewport.new()
	_vp.size = Vector2i(map.w * map.ts, map.h * map.ts)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_drawer = Node2D.new()
	_drawer.draw.connect(_draw_tiles)
	_vp.add_child(_drawer)
	_tex = _vp.get_texture()
	queue_redraw()


func _ready() -> void:
	rebake()


## Перевыпечь ландшафт (дерево спилили, скала выработана...) — вызвать
## вместо queue_redraw(): перерисовать духовку и обновить квадрат.
func rebake() -> void:
	if _vp == null:
		return
	_drawer.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _draw() -> void:
	if OS.get_environment("TERRAIN_DIRECT") != "":
		# временная ветка сравнения (v1.21.5): рисуем тайлы напрямую, без духовки
		var keep := _drawer
		_drawer = self
		_draw_tiles()
		_drawer = keep
		return
	if _tex == null or map == null:
		return
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(map.w * map.ts, map.h * map.ts)), false)


## Отрисовка тайлов — в холст духовки (те же команды, что рисовали в _draw
## до v1.21.5; вызывающий холст — _drawer, а не сам слой).
## v1.22: сюда же запечены «наземные» покрытия — дороги, зоны (заливки,
## борозды, точки пастбищ, заборы) и каменные плиты площади. Раньше это
## пересобиралось живым слоем каждый кадр (~500 команд), теперь живёт
## в текстуре ландшафта и меняется только по sim.static_dirty (rebake).
func _draw_tiles() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	# проход 1: земля (трава/скалы) — вода рисуется после, чтобы берега
	# и скругления углов ложились поверх травы
	for y in map.h:
		for x in map.w:
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			var base := _grass_at(x, y)
			match tile:
				map.TILE_GRASS, map.TILE_TREE:
					_drawer.draw_rect(rect, base)
					_draw_grass_detail(x, y, rect, base, ts)
				map.TILE_DEADROCK:
					_draw_deadrock(x, y, rect, ts)
				map.TILE_ROCK, map.TILE_ORE:
					_draw_rock(x, y, tile == map.TILE_ORE, ts)
	# проход 2: вода — плита, глубина, песчаный берег, скругления углов
	_draw_water_pass(ts)
	_draw_roads_baked()
	_draw_zones_baked()
	_draw_plaza_baked()


## Дороги (M6): тёплые плитки с камешками — в духовке (v1.22).
func _draw_roads_baked() -> void:
	var col: Color = colors.get("road", Color("#6e5f4a"))
	for tile: Vector2i in map.road:
		var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
		_drawer.draw_rect(rect, col)
		_drawer.draw_circle(rect.position + Vector2(map.ts * 0.3, map.ts * 0.4), 2.0, col.lightened(0.2))
		_drawer.draw_circle(rect.position + Vector2(map.ts * 0.65, map.ts * 0.65), 1.6, col.lightened(0.15))


## Зоны (M6, v1.22 в духовке): заливка типа, борозды поля, точки пастбища,
## забор по периметру. Растения и полосы прогресса обустройства остаются
## в живом слое — стадии роста меняются слишком часто для перевыпечки.
func _draw_zones_baked() -> void:
	if sim == null:
		return
	var fill_work: float = float(sim.cfg.get("zones", {}).get("fill_work", 4.0))
	for z in sim.zones:
		var col: Color = _zone_colors.get(String(z["type"]), Color(0.7, 0.7, 0.4))
		for i in (z["cells"] as Array).size():
			var tile: Vector2i = z["cells"][i]
			var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
			var filled: bool = float(z["progress"][i]) >= fill_work
			_drawer.draw_rect(rect, Color(col.r, col.g, col.b, 0.42 if filled else 0.32))
			if String(z["type"]) == "field":
				for k: int in 3:
					var y: float = rect.position.y + map.ts * (0.25 + 0.25 * k)
					_drawer.draw_line(Vector2(rect.position.x + 4, y),
							Vector2(rect.position.x + map.ts - 4, y),
							col.darkened(0.3 if filled else 0.15),
							1.5 if filled else 1.0)
				if filled:
					_drawer.draw_rect(rect.grow(-2), col.darkened(0.15), false, 1.5)
			else:
				_drawer.draw_circle(rect.position + Vector2(10, 20), 3.0, col.darkened(0.35))
				_drawer.draw_circle(rect.position + Vector2(22, 12), 3.0, col.darkened(0.35))
		if String(z["type"]) == "pasture":
			_draw_zone_fence_baked(z)


## Забор пастбища: по внешним рёбрам клеток зоны — перекладина и столбики.
func _draw_zone_fence_baked(z: Dictionary) -> void:
	var ts := float(map.ts)
	var inside := {}
	for c in z["cells"]:
		inside[Vector2i(c)] = true
	var wood := Color("#7a5a3a")
	var dark := Color("#5d4030")
	for c: Vector2i in inside.keys():
		var p := Vector2(c) * ts
		var edges := []
		if not inside.has(c + Vector2i(1, 0)):
			edges.append([p + Vector2(ts, 0), p + Vector2(ts, ts), p + Vector2(ts, ts * 0.5)])
		if not inside.has(c + Vector2i(-1, 0)):
			edges.append([p, p + Vector2(0, ts), p + Vector2(0, ts * 0.5)])
		if not inside.has(c + Vector2i(0, 1)):
			edges.append([p + Vector2(0, ts), p + Vector2(ts, ts), p + Vector2(ts * 0.5, ts)])
		if not inside.has(c + Vector2i(0, -1)):
			edges.append([p, p + Vector2(ts, 0), p + Vector2(ts * 0.5, 0)])
		for e in edges:
			_drawer.draw_line(e[0], e[1], wood, 2.5)
			_drawer.draw_line(e[2], e[2] + Vector2(0, -8), dark, 2.5)
			_drawer.draw_circle(e[2] + Vector2(0, -8), 1.6, dark)


## Каменные плиты площади 2×2 (правки v1.20, v1.22 в духовке). Пульс «места
## сбора» остался в живом слое.
func _draw_plaza_baked() -> void:
	if sim == null or sim.plaza == Vector2i(-1, -1):
		return
	var ts := float(map.ts)
	var origin := Vector2(sim.plaza) * ts
	var rect := Rect2(origin, Vector2(ts * 2.0, ts * 2.0))
	_drawer.draw_rect(rect, Color("#9aa0a8"))
	for i in 4:
		var cx := origin.x + ts * (0.5 + float(i % 2))
		var cy := origin.y + ts * (0.5 + float(i / 2))
		_drawer.draw_rect(Rect2(cx - ts * 0.42, cy - ts * 0.42, ts * 0.84, ts * 0.84), Color("#8a9098"))
	_drawer.draw_rect(rect, Color("#5d6470"), false, 2.0)
	_drawer.draw_circle(origin + Vector2(ts, ts), ts * 0.16, Color("#e8e2d0"))


## Детерминированный «шум» тайла: 0..n-1 (одинаков при каждой перерисовке).
static func _hash(x: int, y: int, n: int, salt: int = 0) -> int:
	var v := int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791))
	return absi(v) % maxi(1, n)


## Пустая порода выработанного массива (v1.21): тёмная осыпь щебня — по ней
## видно, что гряда вычерпана, и сюда можно ставить шахту.
func _draw_deadrock(x: int, y: int, rect: Rect2, ts: float) -> void:
	var base := Color("#4a463f").lightened(0.03 * float(_hash(x, y, 3) - 1))
	_drawer.draw_rect(rect, base)
	# щебень: крупные тёмные глыбы и мелкая крошка по хэшу
	for i in 5:
		var h := _hash(x * 7 + i, y * 13 + i, 100)
		var cx := rect.position.x + 4.0 + float(h % int(ts - 8.0))
		var cy := rect.position.y + 5.0 + float((h / 4) % int(ts - 10.0))
		var r := 1.4 + float(h % 3) * 0.7
		_drawer.draw_circle(Vector2(cx, cy), r, base.darkened(0.18 if i % 2 == 0 else 0.08))
	# блик блужающего металла — намёк на жилы под породой
	var hx := _hash(x, y * 3, 4)
	if hx == 0:
		_drawer.draw_circle(rect.get_center() + Vector2(3.0, -4.0), 1.4, Color("#8a7f6a"))
	_drawer.draw_rect(rect, Color("#2e2b26"), false, 1.0)


## Трава: плавные пятна (билинейный шум, без прямых краёв блоков) + зерно яркости.
func _noise2(xf: float, yf: float, n: int, salt: int) -> float:
	var x0 := int(floorf(xf))
	var y0 := int(floorf(yf))
	var fx := xf - float(x0)
	var fy := yf - float(y0)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := float(_hash(x0, y0, n, salt))
	var b := float(_hash(x0 + 1, y0, n, salt))
	var c := float(_hash(x0, y0 + 1, n, salt))
	var d := float(_hash(x0 + 1, y0 + 1, n, salt))
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


func _grass_at(x: int, y: int) -> Color:
	var idx := int(_noise2(x / 7.0, y / 7.0, _grass_shades.size(), 11))
	var shade: Color = _grass_shades[clampi(idx, 0, _grass_shades.size() - 1)]
	var j := _hash(x, y, 9) - 4   # -4..4
	if j > 0:
		return shade.lightened(0.01 * j)
	return shade.darkened(0.01 * -j)


## Трава: пучки травинок + редкие камешки + ЦВЕТОЧНЫЕ ПОЛЯНЫ (v1.27):
## крупноячеистый шум выделяет луга, на них по хэшу цветут 2–4 цветка
## (белый/жёлтый/розовый/василёк/мак) — поляны, а не рассыпанный горох.
const FLOWER_COLS := [
	Color("#f2f0e4"), Color("#e8d44d"), Color("#e88bb0"),
	Color("#8fb4e8"), Color("#d9584f"),
]


func _draw_grass_detail(x: int, y: int, rect: Rect2, base: Color, ts: float) -> void:
	var dark := base.darkened(0.14)
	var light := base.lightened(0.08)
	# пучки: 3 травинки с изломом — земля не «пластмассит»
	for i in 3:
		var h := _hash(x * 3 + i, y * 7 + i, 100)
		var px := rect.position.x + 4.0 + float(h % int(ts - 8.0))
		var py := rect.position.y + 5.0 + float((h / 7) % int(ts - 10.0))
		var col := dark if i % 2 == 0 else light
		_drawer.draw_line(Vector2(px, py), Vector2(px + 1.0, py - 3.0 - float(h % 3)), col, 1.0)
	# камешек: редкий серый бугорок
	if _hash(x * 13, y * 3, 200) == 0:
		_drawer.draw_circle(rect.position + Vector2(8.0 + float(_hash(x, y, 40) % 14), 9.0), 1.8,
				Color("#9a958a"))
		_drawer.draw_circle(rect.position + Vector2(7.4, 8.4), 0.9, Color("#b5b0a4"))
	# цветочная поляна: шум крупными пятнами + хэш внутри пятна
	var field := _noise2(x / 5.0, y / 5.0, 100, 71)
	if field > 0.74:
		var blooms := 1 + _hash(x, y, 13) % 3
		for i in blooms:
			var h2 := _hash(x * 17 + i, y * 19 + i, 100)
			var c := rect.position + Vector2(5.0 + float(h2 % int(ts - 10.0)),
					5.0 + float((h2 / 7) % int(ts - 10.0)))
			var fcol: Color = FLOWER_COLS[_hash(x + i, y - i, FLOWER_COLS.size())]
			# цветок: 4 лепестка и жёлтая серединка (при 32px — читаемая точка)
			_drawer.draw_circle(c + Vector2(-1.3, -1.3), 1.1, fcol)
			_drawer.draw_circle(c + Vector2(1.3, -1.3), 1.1, fcol)
			_drawer.draw_circle(c + Vector2(-1.3, 1.3), 1.1, fcol)
			_drawer.draw_circle(c + Vector2(1.3, 1.3), 1.1, fcol)
			_drawer.draw_circle(c, 0.9, Color("#e8c94d"))


## Вода (v1.27): плиты с глубиной (центр пруда темнее, отмель светлее),
## песчаная кромка по берегу и СКРУГЛЁННЫЕ углы — водоёмы читаются
## природными кляксами, а не квадратами. Поверх — кувшинки и камыши.
func _draw_water_pass(ts: float) -> void:
	var deep_col: Color = colors.get("water_deep", colors["water"].darkened(0.28))
	var shore_col: Color = colors.get("shore", Color("#c8b183"))
	# плиты с глубиной
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] != map.TILE_WATER:
				continue
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			var deep := _water_deep(x, y)   # 0 отмель .. 8 глубина
			var col: Color = colors["water"].lerp(deep_col, clampf(deep / 6.0, 0.0, 1.0))
			if deep == 0:
				col = col.lightened(0.10)   # отмель у берега светлее
			_drawer.draw_rect(rect, col)
			_draw_water_detail(x, y, rect, ts)
	# берег: песчаная кромка и скругления углов
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] != map.TILE_WATER:
				continue
			_draw_water_edges(x, y, ts, shore_col)
	# кувшинки на отмелях и камыши на берегу
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if map.grid[y][x] == map.TILE_WATER:
				if _water_deep(x, y) <= 2 and _hash(x, y, 17) == 0:
					_draw_lily_pads(Vector2(x * ts, y * ts), ts, x, y)
			elif map.grid[y][x] == map.TILE_GRASS:
				if _near_water(t) and _hash(x * 3, y * 5, 23) < 3:
					_draw_reeds(Vector2(x * ts, y * ts), ts, x, y)


## Сколько водных соседей по 8 направлениям (глубина плиты).
func _water_deep(x: int, y: int) -> int:
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var t := Vector2i(x + dx, y + dy)
			if map.in_bounds(t) and map.grid[t.y][t.x] == map.TILE_WATER:
				n += 1
	return n


func _near_water(t: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = t + d
		if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER:
			return true
	return false


## Кромка воды: песчаная полоса по береговым рёбрам + четверть-круги на углах.
## Внешний угол (оба ортогональных соседа — земля) закрашивается травой —
## плита воды становится «кляксой»; внутренний угол (соседи вода, диагональ —
## земля) заливается водой — залив округляется без квадратной выемки.
func _draw_water_edges(x: int, y: int, ts: float, shore_col: Color) -> void:
	var rect := Rect2(x * ts, y * ts, ts, ts)
	var p := rect.position
	var wet := func(off: Vector2i) -> bool:
		var t := Vector2i(x, y) + off
		return map.in_bounds(t) and map.grid[t.y][t.x] == map.TILE_WATER
	var grass := func(off: Vector2i) -> Color:
		var t := Vector2i(x, y) + off
		return _grass_at(t.x, t.y) if map.in_bounds(t) else _grass_at(x, y)
	# песчаная кромка по рёбрам к земле
	var sw := 3.0
	if not wet.call(Vector2i(1, 0)):
		_drawer.draw_rect(Rect2(p + Vector2(ts - sw, 0), Vector2(sw, ts)), shore_col)
	if not wet.call(Vector2i(-1, 0)):
		_drawer.draw_rect(Rect2(p, Vector2(sw, ts)), shore_col)
	if not wet.call(Vector2i(0, 1)):
		_drawer.draw_rect(Rect2(p + Vector2(0, ts - sw), Vector2(ts, sw)), shore_col)
	if not wet.call(Vector2i(0, -1)):
		_drawer.draw_rect(Rect2(p, Vector2(ts, sw)), shore_col)
	# скругления: внешний угол — трава накрывает угол плиты,
	# внутренний — вода заполняет угол соседней травы
	var r := ts * 0.42
	var corners := [
		[Vector2i(1, -1), p + Vector2(ts, 0), Vector2(-1, 1)],
		[Vector2i(-1, -1), p, Vector2(1, 1)],
		[Vector2i(-1, 1), p + Vector2(0, ts), Vector2(1, -1)],
		[Vector2i(1, 1), p + Vector2(ts, ts), Vector2(-1, -1)],
	]
	for c in corners:
		var diag: Vector2i = c[0]
		var corner: Vector2 = c[1]
		var inward: Vector2 = c[2]
		var h: Vector2i = Vector2i(int(inward.x), 0)
		var v: Vector2i = Vector2i(0, int(inward.y))
		if wet.call(h) and wet.call(v):
			# внутренний угол: диагональ — земля, зальём её угол водой
			# (круглая бухта); вода идёт НАРУЖУ от плиты — направление -inward
			if not wet.call(diag):
				_water_quarter(corner, -inward, r, colors["water"].lightened(0.06))
		elif not wet.call(h) and not wet.call(v):
			# внешний угол: накрываем угол плиты травой соседа — плита воды
			# становится «кляксой», песчаная кромка по рёбрам сохраняется
			var gcol: Color = grass.call(h)
			_water_quarter(corner, inward, r + sw * 0.5, gcol)


## Четверть круга из угла corner в направлении inward (полигон-веер).
func _water_quarter(corner: Vector2, inward: Vector2, r: float, col: Color) -> void:
	if r < 1.0:
		return
	var dx := signf(inward.x)
	var dy := signf(inward.y)
	var pts := PackedVector2Array([corner])
	var steps := 7
	for i in range(steps + 1):
		var a := (float(i) / float(steps)) * (PI / 2.0)
		pts.append(corner + Vector2(dx * cos(a), dy * sin(a)) * r)
	_drawer.draw_colored_polygon(pts, col)


## Кувшинки: пара листьев-эллипсов с выемкой и бликом.
func _draw_lily_pads(origin: Vector2, ts: float, x: int, y: int) -> void:
	for i in 2:
		var h := _hash(x * 5 + i, y * 9 + i, 100)
		var c := origin + Vector2(6.0 + float(h % int(ts - 14.0)), 6.0 + float((h / 5) % int(ts - 14.0)))
		var r := 3.0 + float(h % 3)
		var col := Color("#4e7c3a").lightened(0.05 * float(i))
		_drawer.draw_circle(c, r, col)
		_drawer.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, col.lightened(0.25))
		# выемка листа — тёмный клин
		_drawer.draw_line(c, c + Vector2(r + 0.6, 0.6), colors["water"].lightened(0.08), 1.2)


## Камыши (v1.27): 2–4 стебля с тёмной шишкой — болотная кромка водоёмов.
func _draw_reeds(origin: Vector2, ts: float, x: int, y: int) -> void:
	var stem := Color("#4e6b34")
	var head := Color("#7a5230")
	var n := 2 + _hash(x, y, 5) % 3
	for i in n:
		var h := _hash(x * 7 + i, y * 11 + i, 100)
		var base := origin + Vector2(5.0 + float(h % int(ts - 10.0)), ts * 0.85)
		var lean := 1.6 + float(h % 3) * 0.8
		var top := base + Vector2(lean, -ts * (0.5 + 0.14 * float(h % 3)))
		_drawer.draw_line(base, top, stem, 1.4)
		_drawer.draw_line(top, top + Vector2(lean * 0.5, -3.0), stem, 1.1)
		# шишка камыша — короткая тёмная капсула на конце
		_drawer.draw_line(top + Vector2(lean * 0.5, -3.0), top + Vector2(lean * 0.6, -7.0), head, 2.4)
		_drawer.draw_circle(top + Vector2(lean * 0.6, -7.0), 1.2, head.darkened(0.2))


## Блики воды: пара светлых чёрточек по хэшу.
func _draw_water_detail(x: int, y: int, rect: Rect2, ts: float) -> void:
	var col: Color = colors.get("water", Color("#2e5f7a"))
	col = col.lightened(0.35)
	col.a = 0.4
	for i in 2:
		var h := _hash(x * 5 + i, y * 11 + i, 100)
		var px := rect.position.x + 5.0 + float(h % int(ts - 14.0))
		var py := rect.position.y + 6.0 + float((h / 5) % int(ts - 12.0))
		_drawer.draw_line(Vector2(px, py), Vector2(px + 4.0 + float(h % 4), py), col, 1.2)


## Единая скальная гряда (M11, v1.27 — натурная): гряда из НАЛЕГАЮЩИХ
## валунов — по 2–3 округлых камня на тайл со световым рельефом, углы
## массива скруглены (трава накрывает внешний угол, порода заполняет
## внутренний), у подножия — осыпь и травяная бровка. Руда и трещины
## по мере добычи сохранены.
func _draw_rock(x: int, y: int, ore: bool, ts: float) -> void:
	var key := Vector2i(x, y)
	var rect := Rect2(Vector2(x * ts, y * ts), Vector2(ts, ts))
	# тон плиты с плавной вариацией по шуму (гряда «дышит» оттенком)
	var tone := _noise2(x / 3.0, y / 3.0, 30, 91)
	var base := Color("#716c60").lightened(0.06 * tone - 0.03)
	_drawer.draw_rect(rect, base)
	# валуны: большой камень + меньший рядом, свет сверху-слева
	var hx := _hash(x, y, 30)
	var hy := _hash(y * 7, x * 3, 30)
	var c1 := rect.position + Vector2(ts * 0.42 + float(hx % 6) - 3.0, ts * 0.45 + float(hy % 6) - 3.0)
	_draw_valley_boulder(c1, ts * 0.42, ts * 0.34, base)
	var c2 := rect.position + Vector2(ts * 0.28 + float(hy % 8), ts * 0.72 + float(hx % 5))
	_draw_valley_boulder(c2, ts * 0.26, ts * 0.2, base.darkened(0.06))
	# скругления углов массива (как у воды: внешние — трава, внутренние — порода)
	_draw_rock_edges(x, y, ts, base)
	# трещины по мере добычи: скала «оседает»
	if map.rock_hp.has(key):
		var frac: float = clampf(float(map.rock_hp[key]) / maxf(1.0, _rock_hp_default), 0.0, 1.0)
		if frac < 0.66:
			_drawer.draw_line(rect.position + Vector2(ts * 0.3, ts * 0.35),
					rect.position + Vector2(ts * 0.5, ts * 0.7), Color(0.12, 0.11, 0.09, 0.85), 1.6)
		if frac < 0.33:
			_drawer.draw_line(rect.position + Vector2(ts * 0.65, ts * 0.2),
					rect.position + Vector2(ts * 0.5, ts * 0.55), Color(0.12, 0.11, 0.09, 0.85), 1.4)
	# руда: золотые или рыжие вкрапления
	if ore:
		var gold := _hash(x, y, 4) == 0
		var col := Color("#e0b13e") if gold else Color("#b0684a")
		for i in 4:
			var h2 := _hash(x * 13 + i, y * 17 + i, 100)
			var fx := rect.position.x + 5.0 + float(h2 % int(ts - 10.0))
			var fy := rect.position.y + 10.0 + float((h2 / 3) % int(ts - 16.0))
			_drawer.draw_circle(Vector2(fx, fy), 1.6 + float(h2 % 2), col)


## Валун: округлый камень со световым пятном и тёмным подбоем.
func _draw_valley_boulder(c: Vector2, rx: float, ry: float, base: Color) -> void:
	_draw_ellipse(c, rx, ry, base)
	_draw_ellipse(c + Vector2(-rx * 0.22, -ry * 0.3), rx * 0.55, ry * 0.45, base.lightened(0.09))
	_draw_ellipse(c + Vector2(rx * 0.15, ry * 0.35), rx * 0.6, ry * 0.4, base.darkened(0.1))


## Скругления массива скал: те же четверть-круги, что у воды.
func _draw_rock_edges(x: int, y: int, ts: float, base: Color) -> void:
	var solid := func(off: Vector2i) -> bool:
		var t := Vector2i(x, y) + off
		return map.in_bounds(t) and (map.grid[t.y][t.x] == map.TILE_ROCK
				or map.grid[t.y][t.x] == map.TILE_ORE)
	var p := Vector2(x * ts, y * ts)
	var r := ts * 0.4
	var corners := [
		[Vector2i(1, -1), p + Vector2(ts, 0), Vector2(-1, 1)],
		[Vector2i(-1, -1), p, Vector2(1, 1)],
		[Vector2i(-1, 1), p + Vector2(0, ts), Vector2(1, -1)],
		[Vector2i(1, 1), p + Vector2(ts, ts), Vector2(-1, -1)],
	]
	for c in corners:
		var diag: Vector2i = c[0]
		var corner: Vector2 = c[1]
		var inward: Vector2 = c[2]
		var h: Vector2i = Vector2i(int(inward.x), 0)
		var v: Vector2i = Vector2i(0, int(inward.y))
		if solid.call(h) and solid.call(v):
			if not solid.call(diag):
				_water_quarter(corner, inward, r, base)
		elif not solid.call(h) and not solid.call(v):
			# внешний угол массива: трава накрывает угол — гряда «лежит» на земле
			_water_quarter(corner, inward, r, _grass_at(x, y))


## Заполненный эллипс полигоном (для глыб гряды).
func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.5 or ry <= 0.5:
		return
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	_drawer.draw_colored_polygon(pts, col)
