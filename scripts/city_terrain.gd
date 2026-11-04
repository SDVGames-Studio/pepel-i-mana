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
# v1.32: трава — ЗАПЕЧЁННЫЕ текстуры-тайлы (стиль dual-grid видео jess::codes):
# 3 тона-семейства (L/M/D) × 2 варианта, генератор tools/make_video_grass.py.
# Семейство выбирает крупный шум (пятна луга), вариант — хэш тайла.
var _grass_texs: Array = []
var _rock_deep := Color("#565248")
var _water_lake := Color("#3f87b5")   # v1.29.1: озеро — яркая синь
var _water_river := Color("#57b2d4")  # v1.29.1: река — светло-бирюзовая
var _rock_hp_default := 80.0
var _vp: SubViewport = null
var _drawer: Node2D = null      # ЦЕЛЕВОЙ холст рисования: полный слой или кисть чанка
var _bs := 32                   # v1.43: px/тайл в запечке (большие карты — 8)
# v1.43: запечка ЧАНКАМИ 32×32 тайла (карта ×4 = 27к тайлов, полная
# перевыпечка стоила бы ~1.2 с; чанк — ~10 мс). Чанки копируются из
# кисти-вьюпорта в отдельные текстуры и кэшируются между визитами.
const CHUNK_TILES := 32
var _chunks: Dictionary = {}        # Vector2i(чанк) -> Texture2D
var _chunk_queue: Array = []        # очередь выпечки (прогрессивно, по N за кадр)
var _brushes: Array = []            # [{vp, drawer, wait}] — 2 кисти в конвейере
var _cache_key := ""                # ключ кэша запечки (Game.city_bake_cache)
var _tex: Texture2D = null          # устарело (оставлено для совместимости веток)
# v1.28.1: второй слой — «надстройки» (зоны/дороги/плиты). Они меняются
# часто (обустройство полей), а полная перевыпечка земли (тысячи команд
# травы) стоила ~0.3 с и давала регулярные фризы.
var _vp2: SubViewport = null
var _drawer2: Node2D = null
var _tex2: Texture2D = null


func setup(city_map, city_cfg: Dictionary, city_sim = null, cache_key := "") -> void:
	map = city_map
	sim = city_sim
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		# v1.34.1: water_tune — словарь тюнинга (не цвет), его не парсим
		if c[key] is String:
			colors[key] = Color(String(c[key]))
		elif c[key] is Dictionary:
			colors[key] = c[key]
	for t in city_cfg.get("zones", {}).get("types", {}):
		_zone_colors[String(t)] = Color(String(city_cfg["zones"]["types"][t]["color"]))
	_grass_shades = [colors["grass"], colors.get("grass_alt", colors["grass"]),
			colors.get("grass2", colors["grass"]).darkened(0.03)]
	for fam in ["L", "M", "D"]:
		for v in 2:
			_grass_texs.append(Assets.tex(
					"res://assets/sprites/env/grass_%s%d.png" % [fam, v + 1]))
	_rock_deep = colors.get("rock_deep", Color("#565248"))
	_water_lake = colors.get("water_lake", _water_lake)
	_water_river = colors.get("water_river", _water_river)
	_rock_hp_default = float(city_cfg.get("mountain", {}).get("hp", 80.0))
	# v1.43: масштаб запечки — большие карты пекутся 8px/тайл (LINEAR при
	# уменьшении, глобальный NEAREST при растяжении — чётко и в 16 раз
	# дешевле по памяти); мелкие карты — 1:1 как раньше
	_bs = 8 if maxi(map.w, map.h) > 150 else 32
	var k := float(_bs) / float(map.ts)
	# духовка земли: ЧАНКИ (см. rebake) через 2 кисти-вьюпорта; полная
	# выпечка — прогрессивно, по несколько чанков за кадр, без фриза
	_vp = SubViewport.new()
	_vp.size = Vector2i(map.w * _bs, map.h * _bs)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_vp.canvas_transform = Transform2D().scaled(Vector2(k, k))
	add_child(_vp)
	_drawer = Node2D.new()
	_full_drawer = _drawer
	_drawer.draw.connect(_draw_full)
	_vp.add_child(_drawer)
	_vp2 = SubViewport.new()
	_vp2.size = Vector2i(map.w * _bs, map.h * _bs)
	_vp2.transparent_bg = true
	_vp2.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp2.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_vp2.canvas_transform = Transform2D().scaled(Vector2(k, k))
	add_child(_vp2)
	_drawer2 = Node2D.new()
	_drawer2.draw.connect(_draw_static_content)
	_vp2.add_child(_drawer2)
	_tex2 = _vp2.get_texture()
	# кисти чанков (2 в конвейере: пока один копируется, второй рисуется)
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(CHUNK_TILES * _bs, CHUNK_TILES * _bs)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		add_child(vp)
		var dr := Node2D.new()
		dr.draw.connect(_draw_chunkBrush.bind(i))
		vp.add_child(dr)
		_brushes.append({"vp": vp, "drawer": dr, "wait": Vector2i(-9, -9)})
	# кэш запечки между визитами (Game — автозагрузка): та же версия сетки
	# и тот же масштаб — чанки переиспользуются, вход в город без выпечки
	_cache_key = String(cache_key)
	var Game: Node = _game()
	if Game != null and _cache_key != "":
		var cached: Dictionary = Game.city_bake_cache.get(_cache_key, {})
		if int(cached.get("grid_ver", -9)) == int(map.grid_ver) and int(cached.get("bs", 0)) == _bs 				and (cached.get("chunks", {}) as Dictionary).size() >= _chunk_count():
			_chunks = cached["chunks"]
			_chunk_queue.clear()
	queue_redraw()


var _cache_key_in := ""
var _new_brushes_this_frame := 0   # v1.48.1: лимит кистей/кадр (рендер в конце кадра)
var _full_drawer: Node2D = null   # холст полного слоя (для возврата из кисти)


func _game():
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	var g := tree.root.get_node_or_null("Game")
	return g


func _chunk_count() -> int:
	return ceili(float(map.w) / CHUNK_TILES) * ceili(float(map.h) / CHUNK_TILES)


## v1.48.1: чанки возле героя — ПЕРВЫМИ (игрок сразу видит обжитой центр,
## окраины доезжают фоном по бюджету времени).
func _sort_chunks_near_hero(wanted: Array) -> void:
	if _hero_px() == Vector2.INF:
		return
	var hero_c := Vector2(_hero_px()) / float(CHUNK_TILES * map.ts)
	wanted.sort_custom(func(a, b) -> bool:
		return Vector2(a).distance_squared_to(hero_c) < Vector2(b).distance_squared_to(hero_c))


func _hero_px() -> Vector2:
	var g = _game()
	if g != null and g.get("city_sim") != null and g.city_sim.map != null 			and not g.city_sim.hero_pos.is_zero_approx():
		return g.city_sim.hero_pos
	var vp := get_viewport()
	if vp != null:
		return vp.get_camera_2d().global_position if vp.get_camera_2d() != null 				else Vector2.INF
	return Vector2.INF


func _chunk_keys_all() -> Array:
	var out: Array = []
	for cy in ceili(float(map.h) / CHUNK_TILES):
		for cx in ceili(float(map.w) / CHUNK_TILES):
			out.append(Vector2i(cx, cy))
	return out


func _ready() -> void:
	rebake(true)   # первый bake: кэш блобов строится обязательно
	# v1.30.1: страховка «пустого ландшафта» после смены сцены (смерть в
	# данже): первый UPDATE_ONCE SubViewport изредка сгорает впустую в кадре
	# смены сцены — переводыпекаем ещё раз следующим кадром (дёшево)
	_bake_guard.call_deferred()


func _bake_guard() -> void:
	# v1.48.1: полный холст больше НЕ рисуем (контент — чанки; полный
	# UPDATE_ONCE по 27к тайлов давал фризы начала игры)
	if _vp == null or not is_inside_tree():
		return
	queue_redraw()


## Перевыпечь слой земли (скалу выработали, воду замостили мостом...) —
## heavy=true и версия сетки изменились: пересчитать блобы и всё поле.
## false: перерисовать ТОЛЬКО надстройки (зоны/дороги/плиты) — дёшево.
## v1.28.1 (фикс фризов): полная перевыпечка земли = тысячи draw-команд
## травы (~0.3 с), а вызывалась на каждое обустройство клетки/дорогу.
var _rebake_count := 0
var _blob_cache_ver := -1     # v1.38.0: кэши блобов воды/скал удалены вместе
var _blob_cache_dirty := true  # с их рендером; версия сетки осталась для
                               # перевыпечки при изменениях рельефа


## Перевыпечка. heavy: изменилась маска скал/воды (grid_ver) — пекутся
## ЧАНКИ с правками (edited: Vector2i-список от city_map.note_edit);
## без списка — все чанки (прогрессивно). Лёгкий вызов — только
## надстройки (дёшево при любом размере карты).
func rebake(heavy := false, grid_ver := -1, edited: Array = []) -> void:
	if _vp == null:
		return
	_rebake_count += 1
	if heavy and map != null and _blob_cache_ver != grid_ver:
		_blob_cache_ver = grid_ver
		_blob_cache_dirty = true
		var wanted: Array = []
		if edited.is_empty():
			wanted = _chunk_keys_all()
			_sort_chunks_near_hero(wanted)
		else:
			for e in edited:
				var t := Vector2i(e)
				var cc := Vector2i(int(t.x) / CHUNK_TILES, int(t.y) / CHUNK_TILES)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nb := cc + Vector2i(dx, dy)
						if nb.x >= 0 and nb.y >= 0 								and nb.x < ceili(float(map.w) / CHUNK_TILES) 								and nb.y < ceili(float(map.h) / CHUNK_TILES) 								and not wanted.has(nb):
							wanted.append(nb)
		for c in wanted:
			if not _chunk_queue.has(c):
				_chunk_queue.append(c)
	# надстройки всегда перерисовываются — их мало (сотни команд)
	_drawer2.queue_redraw()
	_vp2.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp2.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


## Конвейер чанков: кисть рисует (UPDATE_ONCE — кадр), следующий кадр
## содержимое копируется в отдельную текстуру чанка и пишется в кэш.
## v1.48.1: бюджет времени ~10 мс/кадр (было 2 чанка за кадр без limit —
## первые секунды города падали до 1–2 FPS).
func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	var done_all := _chunk_queue.is_empty() and _chunks.size() >= _chunk_count()
	var budget_ms := 10.0
	var frame_t0 := Time.get_ticks_usec()
	_new_brushes_this_frame = 0
	for b in _brushes:
		var wait: Vector2i = b["wait"]
		if wait.x > -8:
			var t0u := Time.get_ticks_usec()
			var img: Image = (b["vp"] as SubViewport).get_texture().get_image()
			var t1u := Time.get_ticks_usec()
			if img != null:
				_chunks[wait] = ImageTexture.create_from_image(img)
			if OS.get_environment("CHUNK_DEBUG") != "":
				print("[chunk] copy %d us, tex %d us, budget_left %.0f ms" % [
						t1u - t0u, Time.get_ticks_usec() - t1u,
						budget_ms - float(Time.get_ticks_usec() - frame_t0) / 1000.0])
			b["wait"] = Vector2i(-9, -9)
			queue_redraw()
		elif not _chunk_queue.is_empty():
			var c: Vector2i = _chunk_queue.pop_front()
			if _chunks.has(c) and _chunk_queue.is_empty():
				continue
			b["chunk"] = c
			var k := float(_bs) / float(map.ts)
			var xf := Transform2D().scaled(Vector2(k, k))
			xf.origin = -Vector2(float(c.x), float(c.y)) * float(CHUNK_TILES * map.ts) * k
			(b["vp"] as SubViewport).canvas_transform = xf
			(b["drawer"] as Node2D).queue_redraw()
			(b["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
			(b["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
			b["wait"] = c
		if Time.get_ticks_usec() - frame_t0 > budget_ms * 1000.0:
			break
	# кэш: только когда ВСЁ пропечено
	if done_all and _cache_key != "":
		var g = _game()
		if g != null:
			var cache: Dictionary = g.city_bake_cache
			cache[_cache_key] = {"grid_ver": int(map.grid_ver), "bs": _bs,
					"chunks": _chunks, "stamp": Time.get_ticks_msec()}
			while cache.size() > 2:
				var oldest := ""
				var oldest_t := 0x7fffffff
				for key in cache:
					if key != _cache_key and int(cache[key].get("stamp", 0)) < oldest_t:
						oldest_t = int(cache[key].get("stamp", 0))
						oldest = key
				if oldest == "":
					break
				cache.erase(oldest)


func _draw() -> void:
	if OS.get_environment("TERRAIN_DIRECT") != "":
		# временная ветка сравнения (v1.21.5): рисуем тайлы напрямую, без духовки
		var keep := _drawer
		_drawer = self
		_draw_tiles(Rect2i(0, 0, map.w, map.h))
		_drawer = keep
		return
	if map == null:
		return
	var cts := float(CHUNK_TILES * map.ts)
	for cy in ceili(float(map.h) / CHUNK_TILES):
		for cx in ceili(float(map.w) / CHUNK_TILES):
			var key := Vector2i(cx, cy)
			var rect := Rect2(float(cx) * cts, float(cy) * cts, cts, cts)
			var tex: Texture2D = _chunks.get(key)
			if tex != null:
				draw_texture_rect(tex, rect, false)
			else:
				# чанк ещё печётся — плоская земля без деталей
				draw_rect(rect, _grass_shades[0].darkened(0.05) if not _grass_shades.is_empty() 						else Color("#5d7a3a"))
	if _tex2 != null:
		draw_texture_rect(_tex2, Rect2(Vector2.ZERO, Vector2(map.w * map.ts, map.h * map.ts)), false)


## Отрисовка тайлов — в холст духовки (те же команды, что рисовали в _draw
## до v1.21.5; вызывающий холст — _drawer, а не сам слой).
## v1.22: сюда же запечены «наземные» покрытия — дороги, зоны (заливки,
## борозды, точки пастбищ, заборы) и каменные плиты площади. Раньше это
## пересобиралось живым слоем каждый кадр (~500 команд), теперь живёт
## в текстуре ландшафта и меняется только по sim.static_dirty (rebake).
## v1.38.0 (поручение заказчика): код отрисовки скал/жил и водоёмов
## (rock_terrain.gd, water_lake/river/swamp.gd, блобы-«органика»,
## кромки, ряби, камыши) УДАЛЕН ПОЛНОСТЬЮ — вода и скалы рисуются
## плоской заливкой по типу. Переделка визуала природы с нуля —
## этап «Природа 2.0» (следующий чат).
var _plateau_view = null # plateau_terrain.gd — рендер плато и утёсов (v1.36)
var _rock_view = null    # rock_terrain.gd — скалы/жилы «Природы 2.0» (v1.39.0)


func _ensure_views() -> void:
	if _plateau_view == null:
		_plateau_view = load("res://scripts/plateau_terrain.gd").new()
		_plateau_view.setup(self)
	if _rock_view == null:
		_rock_view = load("res://scripts/rock_terrain.gd").new()
		_rock_view.setup(self)


## Кэш блобов скал: перестраивается при смене версии сетки (выработка
## породы, мост) — та же метка dirty, что управляла блобами воды до v1.38.0.
func _rebuild_rock_cache() -> void:
	if _rock_view != null and _blob_cache_dirty:
		_rock_cached = _rock_view.build_cache()
		_blob_cache_dirty = false


## Полный слой (весь холст духовки) — ныне используется как «стряхивание»
## старого пути; содержимое собирают ЧАНКИ (см. _process/_draw_chunkBrush).
func _draw_full() -> void:
	_draw_tiles(Rect2i(0, 0, map.w if map != null else 0, map.h if map != null else 0))


## Кисть чанка i: рисует ТОЛЬКО тайлы своего региона в холст кисти;
## блобы скал/плато рисуются целиком — вьюпорт сам отсекает лишнее.
func _draw_chunkBrush(i: int) -> void:
	var b: Dictionary = _brushes[i]
	var cc := Vector2i(b.get("chunk", Vector2i(-1, -1)))
	if cc.x < 0:
		return
	_drawer = b["drawer"]
	var region := Rect2i(cc.x * CHUNK_TILES, cc.y * CHUNK_TILES, CHUNK_TILES, CHUNK_TILES)
	_draw_tiles(region)
	_drawer = _full_drawer


func _draw_tiles(region: Rect2i) -> void:
	if map == null:
		return
	_ensure_views()
	var ts := float(map.ts)
	var x0 := maxi(0, region.position.x)
	var y0 := maxi(0, region.position.y)
	var x1 := mini(map.w, region.end.x)
	var y1 := mini(map.h, region.end.y)
	# проход 1: земля (трава/осыпи) — вода и скалы рисуются поверх
	for y in range(y0, y1):
		for x in range(x0, x1):
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			match tile:
				map.TILE_GRASS, map.TILE_TREE:
					var tex: Texture2D = _grass_texture_at(x, y)
					if tex != null:
						_drawer.draw_texture_rect(tex, rect, false)
					else:
						_drawer.draw_rect(rect, _grass_at(x, y))
					# v1.48.1: при уменьшенной запечке (bs<32) детали травы
					# мельче пикселя — пропускаем (чанк печётся в разы быстрее)
					if _bs >= 32:
						_draw_grass_detail(x, y, rect, ts)
						_draw_grass_prop(x, y, rect, ts)
				map.TILE_DEADROCK:
					_rock_view.draw_deadrock(x, y, rect, ts)
				map.TILE_RUIN:
					# v1.48: куча древних камней (руины городской карты) —
					# 3 «блока» детерминированно по хэшу тайла
					_drawer.draw_rect(rect, _rock_deep.darkened(0.1))
					var hh := x * 7 + y * 13
					for k in 3:
						var ox := float((hh + k * 11) % 10) - 5.0
						var oy := float((hh + k * 17) % 10) - 5.0
						var sz := 7.0 + float((hh + k * 5) % 6)
						_drawer.draw_rect(
								Rect2(rect.position + Vector2(6.0 + ox, 6.0 + oy), Vector2(sz, sz)),
								_rock_deep.lightened(0.12 if k % 2 == 0 else 0.0))
	# проход 2: скалы и жилы — «Природа 2.0» (v1.39.0): фактурные утёсы
	# с травяными шапками языком высот плато (rock_terrain.gd).
	# Вода в духовке НЕ рисуется: она живая (water_terrain.gd, город).
	_rebuild_rock_cache()
	_rock_view.draw_blobs(ts, region)
	# проход 3: плато и утёсы (v1.36) — верхние грани, срезы-кромки
	# по схеме Hills, лестницы-проходы и тени у подножия
	_plateau_view.draw_plateaus(ts, region)


## Надстройки (v1.28.1 — отдельный дешёвый слой): зоны, дороги, плиты
## площади. Меняются часто, но команд здесь сотни, а не тысячи.
func _draw_static_content() -> void:
	if map == null:
		return
	_draw_roads_baked()
	_draw_zones_baked()
	_draw_plaza_baked()


## ---------- блобы: marching squares + сглаживание ----------

## Несглаженные замкнутые контуры маски тайлов (углы = центры тайлов).
## Контур идёт по серединам рёбер между «сухим» и «мокрым» тайлом.
func _mask_loops(is_set: Callable) -> Array:
	var ts := float(map.ts)
	var edges := {}   # ключ точки -> массив соседних точек (ключи)
	# сегмент одной клетки: связь двух середин рёбер
	var add_seg := func(a: Vector2, b: Vector2) -> void:
		var ka := _pt_key(a, ts)
		var kb := _pt_key(b, ts)
		if not edges.has(ka):
			edges[ka] = []
		edges[ka].append([kb, b])
		if not edges.has(kb):
			edges[kb] = []
		edges[kb].append([ka, a])
	for j in range(-1, map.h):
		for i in range(-1, map.w):
			var tl := _wet_at(is_set, i, j)
			var tr := _wet_at(is_set, i + 1, j)
			var bl := _wet_at(is_set, i, j + 1)
			var br := _wet_at(is_set, i + 1, j + 1)
			var idx: int = (1 if tl else 0) + (2 if tr else 0) + (4 if bl else 0) + (8 if br else 0)
			if idx == 0 or idx == 15:
				continue
			var top := Vector2((i + 1) * ts, (j + 0.5) * ts)
			var bottom := Vector2((i + 1) * ts, (j + 1.5) * ts)
			var left := Vector2((i + 0.5) * ts, (j + 1) * ts)
			var right := Vector2((i + 1.5) * ts, (j + 1) * ts)
			match idx:
				1, 14:
					add_seg.call(left, top)
				2, 13:
					add_seg.call(top, right)
				3, 12:
					add_seg.call(left, right)
				4, 11:
					add_seg.call(left, bottom)
				6, 9:
					add_seg.call(top, bottom)
				7, 8:
					add_seg.call(right, bottom)
				5:
					# седловая точка tl+br: связываем мокрые по диагонали
					# (без «щипка» в центре клетки)
					add_seg.call(left, bottom)
					add_seg.call(top, right)
				10:
					# седловая точка tr+bl: та же диагональная связность
					add_seg.call(left, top)
					add_seg.call(bottom, right)
	# сшить сегменты в кольца: при использовании ребра удаляем ОБЕ записи
	# (прямую и встречную) — иначе обход откатывается и кольцо складывается
	# вдвое (самопересечение, is_point_in_polygon ломается, заливка пустая)
	var loops: Array = []
	for start_key in edges.keys():
		while (edges[start_key] as Array).size() > 0:
			var loop := PackedVector2Array()
			var cur_key: Vector2i = start_key
			while true:
				var lst: Array = edges[cur_key]
				if lst.is_empty():
					break
				var nxt: Array = lst.pop_back()
				var rec: Array = edges[nxt[0]]
				for idx in range(rec.size()):
					if rec[idx][0] == cur_key:
						rec.remove_at(idx)
						break
				loop.append(nxt[1])
				cur_key = nxt[0]
			if loop.size() >= 3:
				loops.append(loop)
	return loops


func _wet_at(is_set: Callable, i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= map.w or j >= map.h:
		return false
	return is_set.call(Vector2i(i, j))


## Ключ точки на полусетке (целые числа — без ошибок сравнения float).
func _pt_key(p: Vector2, ts: float) -> Vector2i:
	return Vector2i(roundi(p.x / (ts * 0.5)), roundi(p.y / (ts * 0.5)))


## Сгладить контур: квадратичные Безье через середины рёбер — углы
## Блобы v1.34.2: marching squares + сглаживание ЧАЙКИНОМ (2 прохода).
## Срез углов сохраняет простоту контура — Безье на вогнутых прогонах
## больших блобов выходил «восьмёркой», триангуляция падала, и озёра
## деградировали в квадраты тайлов («почему мир квадратный» — приёмка
## v1.34.0). Органичный вид тот же: углы становятся плавными дугами.
func _smooth_loop(raw: PackedVector2Array) -> PackedVector2Array:
	var n := raw.size()
	if n < 3:
		return PackedVector2Array()
	var pts := raw
	for pass_i in 2:
		var out := PackedVector2Array()
		var m := pts.size()
		for i in m:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % m]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		pts = out
	return pts


func _loop_area(loop: PackedVector2Array) -> float:
	var a := 0.0
	for i in loop.size():
		var p := loop[i]
		var q := loop[(i + 1) % loop.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


func _poly_centroid(loop: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in loop:
		c += p
	return c / float(maxi(1, loop.size()))


## Глубина вложенности контура (острова в воде, пруды на островах).
func _loop_depth(loop: PackedVector2Array, all_loops: Array) -> int:
	var c := _poly_centroid(loop)
	var depth := 0
	for other in all_loops:
		if other != loop and _loop_area(other) > _loop_area(loop) \
				and Geometry2D.is_point_in_polygon(c, other):
			depth += 1
	return depth


## Прост ли контур: без самопересечений (сегменты не-соседей не пересекаются)
## и без вырожденных рёбер. Гладкий контур изредка выходил самопересечением —
## мусорная триангуляция красила чужие тайлы (v1.30.1).
## v1.34.1: убрать из замкнутого контура дубли точек и вершины, лежащие
## на прямой между соседями — нулевая площадь ушей роняет ear-clipping
## (Geometry2D.triangulate_polygon), заливка блоба не рисовалась.
static func _clean_loop(loop: PackedVector2Array) -> PackedVector2Array:
	var n := loop.size()
	if n < 3:
		return PackedVector2Array()
	var pts := PackedVector2Array()
	for i in n:
		var p: Vector2 = loop[i]
		if not pts.is_empty() and p.distance_to(pts[pts.size() - 1]) < 0.05:
			continue
		pts.append(p)
	while pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) < 0.05:
		pts.remove_at(pts.size() - 1)
	var changed := true
	while changed and pts.size() > 3:
		changed = false
		var out := PackedVector2Array()
		var m := pts.size()
		for i in m:
			var a: Vector2 = pts[(i - 1 + m) % m]
			var b: Vector2 = pts[i]
			var c: Vector2 = pts[(i + 1) % m]
			var cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
			var dot := (b.x - a.x) * (c.x - a.x) + (b.y - a.y) * (c.y - a.y)
			if absf(cross) < 0.05 and dot > 0.0:
				changed = true
				continue
			out.append(b)
		pts = out
	return pts if pts.size() >= 3 else PackedVector2Array()

func _loop_is_simple(loop: PackedVector2Array) -> bool:
	var n := loop.size()
	if n < 4:
		return true
	for i in n:
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[(i + 1) % n]
		if a.distance_to(b) < 0.5:
			return false
		for j in range(i + 1, n):
			if j == i or (j + 1) % n == i or (i + 1) % n == j:
				continue   # соседние сегменты
			var c: Vector2 = loop[j]
			var d: Vector2 = loop[(j + 1) % n]
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if hit == null:
				continue
			var hv: Vector2 = hit
			if hv == Vector2.INF or (is_nan(hv.x) and is_nan(hv.y)):
				continue
			# касание концами (общие вершины/углы) — не дефект
			if hv.is_equal_approx(a) or hv.is_equal_approx(b):
				continue
			if hv.is_equal_approx(c) or hv.is_equal_approx(d):
				continue
			return false
	return true


## Вписать контур к центроиду (внутренняя заливка глубины).
func _shrunk_loop(loop: PackedVector2Array, f: float) -> PackedVector2Array:
	var c := _poly_centroid(loop)
	var out := PackedVector2Array()
	for p in loop:
		out.append(c + (p - c) * f)
	return out


## Надёжная заливка региона: тайлы внутри контура (триангуляция большого
## сглаженного полигона нестабильна — падает на почти-коллинеарных точках).
## Гладкость края даёт _stroke_inside поверх.
var _fill_debug_count := 0


## Прогоны контура, где наружная нормаль смотрит в сторону dir_v (общая
## геометрия «языка высоты»: v1.37 — срез/тень скал, v1.37.1 — объём озёр).
## Возвращает массив прогонов [[точка, нормаль]...] по порядку обхода.
func dir_runs(loop: PackedVector2Array, c: Vector2, dir_v: Vector2,
		dot_min: float, min_len: int) -> Array:
	var runs: Array = []
	var run: Array = []
	var n := loop.size()
	for i in n + 1:
		var idx := i % n
		var p: Vector2 = loop[idx]
		var q: Vector2 = loop[(idx + 1) % n]
		var dir := q - p
		if dir.length() < 0.001:
			continue
		var nrm := Vector2(dir.y, -dir.x).normalized()
		if nrm.dot(p - c) < 0.0:
			nrm = -nrm   # наружу от центроида
		if nrm.dot(dir_v) >= dot_min:
			run.append([p, nrm])
		else:
			if run.size() >= min_len:
				runs.append(run)
			run = []
	if run.size() >= min_len:
		runs.append(run)
	return runs


## Обводка прогона со смещением вдоль нормали: off>0 — ВНУТРЬ региона
## (минус наружная нормаль), тень/вынос наружу — stroke_run_out.
func stroke_run(run: Array, off: float, width: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for e in run:
		pts.append((e[0] as Vector2) - (e[1] as Vector2) * off)
	pts.append(pts[0])
	_drawer.draw_polyline(pts, col, width)


## Обводка прогона со смещением НАРУЖУ (тень на траве за контуром).
func stroke_run_out(run: Array, off: float, width: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for e in run:
		pts.append((e[0] as Vector2) + (e[1] as Vector2) * off)
	pts.append(pts[0])
	_drawer.draw_polyline(pts, col, width)


## Заливка региона: полигон (контур теперь простой — починен сшивкой),
## при отказе триангуляции — деградация к тайлам по центрам.
## Заливка региона: кэшированная триангуляция (быстрый путь, v1.28.1) или
## разовая триангуляция/тайлы. Триангуляция большого сглаженного полигона
## дорога — потому кэшируется вместе с контуром.
func _fill_loop_cached(loop: PackedVector2Array, tris: PackedInt32Array, col: Color) -> void:
	if tris.is_empty():
		# v1.34.1: страховка заливки — чистим контур и триангулируем заново.
		# Раньше падение ear-clipping означало дырку: просвечивал серый фон
		# («сухая река», серые пятна на скриншотах приёмки v1.34.0).
		var clean := _clean_loop(loop)
		if clean.size() >= 3:
			var t2 := Geometry2D.triangulate_polygon(clean)
			if not t2.is_empty():
				_fill_loop_cached(clean, t2, col)
				return
			_drawer.draw_colored_polygon(clean, col)
		return
	var cols := PackedColorArray()
	cols.resize(loop.size())
	cols.fill(col)
	# draw_polygon не принимает индексы — пишем триангуляцию через RS
	RenderingServer.canvas_item_add_triangle_array(_drawer.get_canvas_item(),
			tris, loop, cols)


func _fill_loop(loop: PackedVector2Array, col: Color, ts: float) -> void:
	if Geometry2D.triangulate_polygon(loop).is_empty():
		_fill_loop_tiles(loop, col, ts)
		return
	_drawer.draw_colored_polygon(loop, col)


func _fill_loop_tiles(loop: PackedVector2Array, col: Color, ts: float) -> void:
	_fill_debug_count = 0
	for y in map.h:
		for x in map.w:
			var c := Vector2((x + 0.5) * ts, (y + 0.5) * ts)
			if Geometry2D.is_point_in_polygon(c, loop):
				_drawer.draw_rect(Rect2(Vector2(x * ts, y * ts), Vector2(ts, ts)), col)
				_fill_debug_count += 1


## Широкая обводка чуть внутри контура — сглаживает ступенчатый край тайлов.
func _stroke_inside(loop: PackedVector2Array, f: float, width: float, col: Color) -> void:
	var pts := _shrunk_loop(loop, f)
	if pts.size() < 2:
		return
	pts.append(pts[0])
	_drawer.draw_polyline(pts, col, width)


## Обводка прямо по контуру (пляж/кромка массива): гасит ступени тайлов,
## выступающие из-под сглаженной кривой (~0.35 тайла на углах).
func _stroke_on_loop(loop: PackedVector2Array, width: float, col: Color) -> void:
	if loop.size() < 2:
		return
	var pts := loop.duplicate()
	pts.append(pts[0])
	_drawer.draw_polyline(pts, col, width)


## Дороги (M6): тёплые плитки с камешками — в духовке (v1.22).
func _draw_roads_baked() -> void:
	var col: Color = colors.get("road", Color("#6e5f4a"))
	for tile: Vector2i in map.road:
		var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
		_drawer2.draw_rect(rect, col)
		_drawer2.draw_circle(rect.position + Vector2(map.ts * 0.3, map.ts * 0.4), 2.0, col.lightened(0.2))
		_drawer2.draw_circle(rect.position + Vector2(map.ts * 0.65, map.ts * 0.65), 1.6, col.lightened(0.15))


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
			_drawer2.draw_rect(rect, Color(col.r, col.g, col.b, 0.42 if filled else 0.32))
			if String(z["type"]) == "field":
				for k: int in 3:
					var y: float = rect.position.y + map.ts * (0.25 + 0.25 * k)
					_drawer2.draw_line(Vector2(rect.position.x + 4, y),
							Vector2(rect.position.x + map.ts - 4, y),
							col.darkened(0.3 if filled else 0.15),
							1.5 if filled else 1.0)
				if filled:
					_drawer2.draw_rect(rect.grow(-2), col.darkened(0.15), false, 1.5)
			else:
				_drawer2.draw_circle(rect.position + Vector2(10, 20), 3.0, col.darkened(0.35))
				_drawer2.draw_circle(rect.position + Vector2(22, 12), 3.0, col.darkened(0.35))
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
			_drawer2.draw_line(e[0], e[1], wood, 2.5)
			_drawer2.draw_line(e[2], e[2] + Vector2(0, -8), dark, 2.5)
			_drawer2.draw_circle(e[2] + Vector2(0, -8), 1.6, dark)


## Каменные плиты площади 2×2 (правки v1.20, v1.22 в духовке). Пульс «места
## сбора» остался в живом слое.
func _draw_plaza_baked() -> void:
	if sim == null or sim.plaza == Vector2i(-1, -1):
		return
	var ts := float(map.ts)
	var origin := Vector2(sim.plaza) * ts
	var rect := Rect2(origin, Vector2(ts * 2.0, ts * 2.0))
	_drawer2.draw_rect(rect, Color("#9aa0a8"))
	for i in 4:
		var cx := origin.x + ts * (0.5 + float(i % 2))
		var cy := origin.y + ts * (0.5 + float(i / 2))
		_drawer2.draw_rect(Rect2(cx - ts * 0.42, cy - ts * 0.42, ts * 0.84, ts * 0.84), Color("#8a9098"))
	_drawer2.draw_rect(rect, Color("#5d6470"), false, 2.0)
	_drawer2.draw_circle(origin + Vector2(ts, ts), ts * 0.16, Color("#e8e2d0"))


## Детерминированный «шум» тайла: 0..n-1 (одинаков при каждой перерисовке).
static func _hash(x: int, y: int, n: int, salt: int = 0) -> int:
	var v := int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791))
	return absi(v) % maxi(1, n)


## Пустая порода выработанного массива — рисует rock_terrain.gd (v1.39.1:
## каменная текстура — «шапка снята, видно камень»).
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


## Текстура травяного тайла: семейство тонов — крупный шум (пятна луга,
## тот же масштаб, что выбирает и _grass_at), вариант внутри семейства —
## хэш тайла (соседние тайлы всегда разные, повтор 32px не ловится глазом).
func _grass_texture_at(x: int, y: int) -> Texture2D:
	if _grass_texs.is_empty():
		return null
	var fam := clampi(int(_noise2(x / 7.0, y / 7.0, 3, 11)), 0, 2)
	var v: int = _hash(x, y, 2)
	return _grass_texs[fam * 2 + v]


## Трава: редкие камешки + ЦВЕТОЧНЫЕ ПОЛЯНЫ (v1.27) поверх текстурного
## тайла (v1.32: пучки травинок теперь живут В текстуре — tools/
## make_video_grass.py — и живом слое колыхания city_view.gd).
## Крупноячеистый шум выделяет луга, на них по хэшу цветут 2–4 цветка
## (белый/жёлтый/розовый/василёк/мак) — поляны, а не рассыпанный горох.
const FLOWER_COLS := [
	Color("#f2f0e4"), Color("#e8d44d"), Color("#e88bb0"),
	Color("#8fb4e8"), Color("#d9584f"),
]


func _draw_grass_detail(x: int, y: int, rect: Rect2, ts: float) -> void:
	# камешек: редкий серый бугорок (v1.49: гуще — карта «ожила»)
	if _hash(x * 13, y * 3, 120) == 0:
		_drawer.draw_circle(rect.position + Vector2(8.0 + float(_hash(x, y, 40) % 14), 9.0), 1.8,
				Color("#9a958a"))
		_drawer.draw_circle(rect.position + Vector2(7.4, 8.4), 0.9, Color("#b5b0a4"))
	# цветочная поляна: шум крупными пятнами (нормирован 0..1), цветёт
	# только сердцевина пятна — поляна читается островом среди луга
	var field := _noise2(x / 6.0, y / 6.0, 100, 71) / 99.0
	if field > 0.72:
		var blooms := 1 + _hash(x, y, 13) % 2
		for i in blooms:
			var h2 := _hash(x * 17 + i, y * 19 + i, 100)
			var c := rect.position + Vector2(5.0 + float(h2 % int(ts - 10.0)),
					5.0 + float((h2 / 7) % int(ts - 10.0)))
			var fcol: Color = FLOWER_COLS[_hash(x + i, y - i, FLOWER_COLS.size())]
			# цветок: 4 лепестка и жёлтая серединка (при 32px — читаемая точка)
			_drawer.draw_circle(c + Vector2(-1.0, -1.0), 0.9, fcol)
			_drawer.draw_circle(c + Vector2(1.0, -1.0), 0.9, fcol)
			_drawer.draw_circle(c + Vector2(-1.0, 1.0), 0.9, fcol)
			_drawer.draw_circle(c + Vector2(1.0, 1.0), 0.9, fcol)
			_drawer.draw_circle(c, 0.7, Color("#e8c94d"))

## ---------- Природа 2.0 (v1.39.0) -------------------------------------------
## Вода — живой слой (water_terrain.gd, добавлен городом над ландшафтом);
## скалы/жилы — rock_terrain.gd (проход 2 духовки). Здесь остались только
## статичные пропсы травы и ромб-кристалл руды (общая утилита).

var _rock_cached: Array = []   # блобы скал (кэш, перестройка по grid_ver)
var _prop_texs: Dictionary = {}  # имя -> Texture2D (кусты/камни пака)


## Пропсы на лугу: кусты и валуны ForgottenMemories — редкие, по хэшу
## (маскируют «пустоту» ровного газона; у воды гуще — по соседству).
func _draw_grass_prop(x: int, y: int, rect: Rect2, ts: float) -> void:
	if _prop_texs.is_empty():
		for n in ["bush2_a", "bush2_b", "bush2_c", "bush2_d", "stone2_a", "stone2_b"]:
			_prop_texs[n] = Assets.tex("res://assets/sprites/props/%s.png" % n)
	var h: int = _hash(x * 17, y * 11, 1000)
	var near_water := false
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var p: Vector2i = Vector2i(x, y) + d
		if map.in_bounds(p) and map.grid[p.y][p.x] == map.TILE_WATER:
			near_water = true
			break
	# шанс: у воды 12%, на лугу 6% (v1.49: кустов/валунов вдвое больше)
	var threshold := 120 if near_water else 60
	if h >= threshold:
		return
	var idx: int = _hash(x * 3, y * 5, _prop_texs.size())
	var name: String = _prop_texs.keys()[idx]
	var tex: Texture2D = _prop_texs[name]
	if tex == null:
		return
	var scale := (0.42 + 0.14 * float(_hash(x, y, 7))) * ts
	var s := scale / float(tex.get_height())
	var w := tex.get_width() * s
	var pos := rect.get_center() + Vector2(
			float(_hash(x * 5, y, 9) - 4) * ts * 0.02,
			float(_hash(x, y * 5, 9) - 4) * ts * 0.02)
	_drawer.draw_texture_rect(tex, Rect2(
			Vector2(pos.x - w * 0.5, pos.y - scale * 0.62), Vector2(w, scale)), false)


## Ромб-кристалл (руда) с центром center и полудиагональю r.
func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	if r < 0.8:
		return
	_drawer.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r * 0.7, 0),
		center + Vector2(0, r), center + Vector2(-r * 0.7, 0),
	]), col)
