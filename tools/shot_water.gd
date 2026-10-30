extends SceneTree
## Снимок водоёмов города (v1.34, этап «Опрятные водоёмы»). Запуск С ГРАФИКОЙ:
## SHOT_SEED=4242 godot --path . --script res://tools/shot_water.gd
## Телепортирует героя к центру крупнейшего водоёма, ждёт кадры, сохраняет
## tools/shot_water.png и выходит. SHOT_ALL=1 — вторым кадром болото/река.

var _frames := 0
var _game: Node = null
var _city: Node = null


func _initialize() -> void:
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		game.name = "Game"
		root.add_child(game)
	var loc: Node = root.get_node_or_null("Loc")
	if loc == null:
		loc = load("res://scripts/loc.gd").new()
		loc.name = "Loc"
		root.add_child(loc)
	if OS.get_environment("SHOT_SEED") != "":
		seed(int(OS.get_environment("SHOT_SEED")))
	game.test_mode = true
	game.new_city()
	var city: Node = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	_game = game
	_city = city
	process_frame.connect(_on_frame)


func _goto_water(city: Node, game: Node) -> void:
	var sim = game.city_sim
	var map = sim.map
	# крупнейший компонент воды (не болото) — к его центру
	var seen := {}
	var best: Array = []
	var best_kind := ""
	# приоритет озеру (компактный блоб читается лучше ленты реки)
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if map.grid[t.y][t.x] != map.TILE_WATER or seen.has(t):
				continue
			if map.water_kind_at(t) == "swamp":
				seen[t] = true
				continue
			# озеро важнее: если уже нашли озеро, ленты-реки пропускаем
			if best_kind == "lake" and map.water_kind_at(t) != "lake":
				seen[t] = true
				continue
			var comp: Array = [t]
			seen[t] = true
			var qi := 0
			while qi < comp.size():
				var c: Vector2i = comp[qi]
				qi += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER \
							and not seen.has(n) and map.water_kind_at(n) != "swamp":
						seen[n] = true
						comp.append(n)
			if comp.size() > best.size():
				best = comp
				best_kind = map.water_kind_at(t)
	if best.is_empty():
		print("shot_water: воды на карте нет")
		quit(1)
		return
	var sum := Vector2.ZERO
	for t: Vector2i in best:
		sum += Vector2(t)
	var center := sum / float(best.size())
	print("shot_water: крупнейший водоём kind=%s tiles=%d center=%s" % [best_kind, best.size(), center])
	# берег рядом с центром водоёма: герой стоит НА ЗЕМЛЕ у воды
	# (в воду телепортировать нельзя — утонет и сломает кадр)
	var center_i := Vector2i(int(center.x), int(center.y))
	var shore := Vector2i(-1, -1)
	# ближайший к центру водоёма СУХОЙ тайл (остров или берег) — камера
	# встанет так, что вода окажется в центре экрана
	for r in range(0, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := center_i + Vector2i(dx, dy)
				if map.in_bounds(t) and map.grid[t.y][t.x] != map.TILE_WATER:
					shore = t
					break
			if shore.x >= 0:
				break
		if shore.x >= 0:
			break
	var hero = city.get("hero")
	if hero != null and shore.x >= 0:
		hero.position = (Vector2(shore) + Vector2(0.5, 0.5)) * map.ts
		# отзумить камеру, чтобы водоём целиком попал в кадр
		var cam: Camera2D = hero.get_node_or_null("Camera")
		if cam != null:
			cam.zoom = Vector2(1.8, 1.8)
		print("shot_water: герой на берегу %s (водных тайлов в водоёме %d)" % [shore, best.size()])
	else:
		print("shot_water: герой или берег не найдены")


func _on_frame() -> void:
	_frames += 1
	if _frames % 10 == 0:
		print("shot_water: frame %d" % _frames)
	# телепорт после выпечки ландшафта (двойная выпечка v1.30.1 успевает)
	if _frames == 20:
		_goto_water(_city, _game)
	if _frames == 30 and OS.get_environment("SHOT_NOSKY") != "":
		_hide_node(_city, "city_sky.gd")
	if _frames == 30 and OS.get_environment("SHOT_NOROCK") != "":
		_norock()
	if _frames == 30 and OS.get_environment("SHOT_PROBE") != "":
		_probe()
	if _frames < 70:
		return
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("res://tools/shot_water.png")
		print("shot_water: сохранён tools/shot_water.png")
	quit(0)


## Спрятать узел по скрипту (SHOT_NOSKY): небо/тени city_sky.
func _hide_node(root: Node, script_name: String) -> void:
	for ch in root.get_children():
		var sc: Script = ch.get_script()
		if sc != null and String(sc.resource_path).ends_with(script_name):
			ch.visible = false
			print("shot_water: скрыт %s" % script_name)
			return
	print("shot_water: %s не найден" % script_name)


## Убрать скалы из кэша (SHOT_NOROCK) — А/Б источник серых полос.
func _norock() -> void:
	for ch in _city.get_children():
		var sc: Script = ch.get_script()
		if sc != null and String(sc.resource_path).ends_with("city_terrain.gd"):
			ch._rock_cached = []
			ch.queue_redraw()
			print("shot_water: скалы убраны из кэша")
			return


## Дамп типов тайлов вокруг героя (SHOT_PROBE=1): W вода, R скала/руда,
## T дерево, D мёртвая порода, . трава; в скобках — тип воды по карте.
func _probe() -> void:
	var sim = _game.city_sim
	var map = sim.map
	# блобы воды в кэше террейна: видимость/размер/заливка
	var ter = _city.get_node_or_null("Terrain")
	if ter == null:
		for n in [_city, _city.get_parent()]:
			if n == null:
				continue
			for ch in n.get_children():
				var sc: Script = ch.get_script()
				if sc != null and String(sc.resource_path).ends_with("city_terrain.gd"):
					ter = ch
	print("probe terrain: %s" % [ter])
	if ter != null:
		print("probe blobs: %d" % [ter._water_cached.size()])
		var raws: Array = ter._mask_loops(func(t: Vector2i) -> bool:
			return map.grid[t.y][t.x] == map.TILE_WATER)
		print("probe raw loops: %d" % [raws.size()])
		for rl in raws:
			print("  raw loop pts=%d area=%.1f" % [rl.size(), ter._loop_area(rl)])
		for e in ter._water_cached:
			print("  blob kind=%s tiles=%d loop=%d tris=%d simple=%s" % [
					e["kind"], e["tiles"].size(), e["loop"].size(),
					e["tris"].size(), e.get("simple")])
	var ht: Vector2i = map.tile_of_px(_city.get("hero").position)
	for dy in range(-8, 9):
		var row := ""
		for dx in range(-6, 7):
			var t := ht + Vector2i(dx, dy)
			if not map.in_bounds(t):
				row += " ##"
				continue
			var g: int = map.grid[t.y][t.x]
			var ch := "."
			if g == map.TILE_WATER:
				ch = "W"
			elif g == map.TILE_ROCK or g == map.TILE_ORE:
				ch = "R"
			elif g == map.TILE_TREE:
				ch = "T"
			elif g == map.TILE_DEADROCK:
				ch = "D"
			if ch == "W":
				ch += "(" + map.water_kind_at(t).left(1) + ")"
			row += " " + ch
		print("probe %3d:%s" % [ht.y + dy, row])
	quit(0)
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tools/shot_water.png")
	print("shot_water: сохранён tools/shot_water.png")
	quit(0)
