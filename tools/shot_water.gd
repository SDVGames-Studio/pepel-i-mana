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
	_goto_water.call_deferred(city, game)
	process_frame.connect(_on_frame)


func _goto_water(city: Node, game: Node) -> void:
	_game = game
	_city = city
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
	# телепорт после выпечки ландшафта (двойная выпечка v1.30.1 успевает)
	if _frames == 20:
		_goto_water(_city, _game)
	if _frames < 70:
		return
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tools/shot_water.png")
	print("shot_water: сохранён tools/shot_water.png")
	quit(0)
