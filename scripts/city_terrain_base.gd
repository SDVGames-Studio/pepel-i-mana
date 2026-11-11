# Часть: статический слой города — конвейер запечки: setup, очередь чанков,
# rebake, покадровый процесс и главный _draw.
# Структура v1.62.0: бывший city_terrain.gd (1094 строки) разрезан на
# extends-цепочку Node2D (city_terrain_base -> city_terrain.gd) — это один
# класс, city.gd создаёт его по-прежнему через city_terrain.gd.
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
# v1.52.2 (веб-фризы): надстройки — инкремент. Духовка №2 полна (первый
# бейк); при static_dirty ПЕРЕРИСОВЫВАЮТСЯ ТОЛЬКО изменённые тайлы:
# содержимое клетки пересчитывается в мини-Image (CPU, без GPU-вьюпорта)
# и блитуется в _static_img; текстура обновляется одним update.
# Прежняя полная перевыпечка (110К тайлов, дорога самостроя каждый день)
# в вебе давала секундные фризы.
var _static_img: Image = null
var _static_tex: ImageTexture = null
var _static_full_bake := true


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
	# v1.50.1 (правка приёмки): трава — ПРИНЯТЫЕ текстуры dual-grid v1.32
	# (3 тона-семейства × 2 варианта, каждый тайл с нарисованными травинками).
	# FM-плоская база давала гигантские одноцветные «плиты» — возвращено.
	# Из ForgottenMemories остались: земля мелких проплешин, вода, декор.
	_grass_texs = []
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
	_tex2 = _vp2.get_texture()   # после первого UPDATE_ONCE уходим на _static_tex
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
		# v1.59: кэш может быть ЧАСТИЧНЫМ (уход в данж посреди запечки) —
		# восстанавливаем всё, что есть; добор докатится по очереди
		if int(cached.get("grid_ver", -9)) == int(map.grid_ver) and int(cached.get("bs", 0)) == _bs 				and (cached.get("chunks", {}) as Dictionary).size() > 0:
			_chunks = (cached.get("chunks", {}) as Dictionary).duplicate()
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
## v1.59: уходим из города — сохранить текущий прогресс запечки. Раньше
## кэш писался только для полностью пропечённой карты: уход в данж до
## конца запечки + смерть = возврат перекраивал ВСЁ с нуля (минуты).
func _exit_tree() -> void:
	if _cache_key == "" or _chunks.is_empty() or map == null:
		return
	var g: Node = _game()
	if g == null:
		return
	var cache: Dictionary = g.city_bake_cache
	var old: Dictionary = cache.get(_cache_key, {})
	var merged: Dictionary = {}
	if int(old.get("grid_ver", -9)) == int(map.grid_ver) and int(old.get("bs", 0)) == _bs:
		merged = (old.get("chunks", {}) as Dictionary).duplicate()
	merged.merge(_chunks)
	cache[_cache_key] = {"grid_ver": int(map.grid_ver), "bs": _bs,
			"chunks": merged, "stamp": Time.get_ticks_msec()}


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
			_chunks.erase(c)   # v1.59: правленый чанк обязан перекроиться
			if not _chunk_queue.has(c):
				_chunk_queue.append(c)
	# надстройки: полный бейк — только первый кадр (или v1-сейв), дальше
	# ИНКРЕМЕНТ по изменённым тайлам (см. _static_increment);
	# sim может потребовать полный ребейк (площадь переехала)
	if sim != null and sim.map.get_meta(&"static_full_rebake", false):
		sim.map.set_meta(&"static_full_rebake", false)
		_static_full_bake = true
	if _static_full_bake:
		_drawer2.queue_redraw()
		_vp2.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_vp2.render_target_update_mode = SubViewport.UPDATE_ONCE
		_snapshot_static.call_deferred()
	else:
		var edits: Array = sim.map.edited_static.duplicate() if sim != null else []
		sim.map.edited_static.clear()
		if not edits.is_empty():
			_static_increment(edits)
	queue_redraw()


## Конвейер чанков: кисть рисует (UPDATE_ONCE — кадр), следующий кадр
## содержимое копируется в отдельную текстуру чанка и пишется в кэш.
## v1.48.1: бюджет времени ~10 мс/кадр (было 2 чанка за кадр без limit —
## первые секунды города падали до 1–2 FPS).
func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	var done_all := _chunk_queue.is_empty() and _chunks.size() >= _chunk_count()
	# v1.59: пока карта не допечена — это «экран загрузки», бюджет шире
	var budget_ms := 24.0 if not done_all else 10.0
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
			# v1.59: готовый чанк не перерисовываем (раньше скип был только
			# для последнего — вход в город перекрашивал все 100+ чанков).
			# Перекраиваемые правками чанки вынимаются из _chunks в rebake().
			if _chunks.has(c):
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
	# v1.50 (FPS): рисуем только чанки в видимой области — при большом
	# зуме-отдалении и так все видны, вблизи экономит десятки квадов
	var xf := get_viewport_transform()
	var vis: Rect2 = (xf.affine_inverse() * get_viewport_rect()).grow(float(CHUNK_TILES * map.ts))
	var cts := float(CHUNK_TILES * map.ts)
	for cy in ceili(float(map.h) / CHUNK_TILES):
		for cx in ceili(float(map.w) / CHUNK_TILES):
			var key := Vector2i(cx, cy)
			var rect := Rect2(float(cx) * cts, float(cy) * cts, cts, cts)
			if not vis.intersects(rect):
				continue
			var tex: Texture2D = _chunks.get(key)
			if tex != null:
				draw_texture_rect(tex, rect, false)
			else:
				# чанк ещё печётся — плоская земля без деталей
				draw_rect(rect, _grass_shades[0].darkened(0.05) if not _grass_shades.is_empty() 					else Color("#5d7a3a"))
	if _static_tex != null:
		draw_texture_rect(_static_tex, Rect2(Vector2.ZERO, Vector2(map.w * map.ts, map.h * map.ts)), false)


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

var _rock_cached: Array = []   # блобы скал (кэш, перестройка по grid_ver)

# --- заглушки для парсера (структура v1.62.0) ------------------------------
# Конвейер запечки зовёт отрисовку, живущую ниже (city_terrain.gd). Реальные
# тела — там. Сигнатуры держите в синхроне.
func _draw_chunkBrush(i: int) -> void:
	pass

func _draw_tiles(region: Rect2i) -> void:
	pass

func _draw_static_content() -> void:
	pass

func _snapshot_static() -> void:
	pass

func _static_increment(edits: Array) -> void:
	pass
