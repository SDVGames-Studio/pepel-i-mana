extends SceneTree
## Дымовой тест M8 (карта мира): сцены и переходы в headless-режиме.
## Юнит-тесты (run_all.gd) логику уже проверили — здесь запускаем сами сцены:
## мир создаётся, герой ходит по дням, локация генерируется с биомом точки интереса.
## Запуск: godot --headless --path . --script res://tests/smoke_m8.gd

var _fails := 0


func _initialize() -> void:
	# автозагрузки: движок создаёт их сам (узлы /root/Loc, /root/Game) —
	# если нет, делаем вручную. Важно использовать ОДИН экземпляр Game.
	var loc: Node = root.get_node_or_null("Loc")
	if loc == null:
		loc = load("res://scripts/loc.gd").new()
		loc.name = "Loc"
		root.add_child(loc)
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		game.name = "Game"
		root.add_child(game)
	game.new_city()
	_check(game.world_map != null and game.world_sim != null, "новая игра создаёт город и мир")
	_check(game.coins > 0, "у героя есть стартовые монеты")

	# --- сцена карты мира ---
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	await _frames(5)
	_check(is_instance_valid(world), "сцена карты мира открывается без ошибок")
	_check(world.hero_tile == world.map.city_tile, "герой начинает у города")

	# --- путешествие по дням: до ближайшей точки интереса ---
	var target: Dictionary = {}
	var best := 999999
	for poi in world.map.pois:
		if String(poi["kind"]) == "city":
			continue
		var days: int = world.map.travel_days(world.map.city_tile, poi["tile"])
		if days > 0 and days < best:
			best = days
			target = poi
	_check(not target.is_empty(), "найдена цель для путешествия")
	world.start_travel_to(target["tile"])
	_check(not (world.travel as Dictionary).is_empty(), "путешествие запустилось (маршрут построен)")
	var city_day_before: int = game.city_sim.day_number()
	var waited := 0
	while not (world.travel as Dictionary).is_empty() and waited < 3000:
		await process_frame
		waited += 1
	_check((world.travel as Dictionary).is_empty(), "герой дошёл до цели (кадров: %d)" % waited)
	_check(world.hero_tile == target["tile"], "герой стоит в точке интереса")
	print("  [dbg] день города %d -> %d, день мира %d, дней пути %d" % [
			city_day_before, game.city_sim.day_number(), int(world.sim.day), int(target.get("id", 0))])
	_check(int(game.city_sim.day_number()) >= city_day_before + 1,
			"пока герой шёл, прошёл хотя бы день — город и мир живут")
	_check(int(world.sim.day) >= 1, "мир тикает днями в пути")

	# --- торговля у каравана/поселения, если герой пришёл в торговую точку ---
	if world.sim.is_trade_poi(target):
		var pool: Dictionary = game.city_sim.res
		var before_coins: int = game.coins
		var out: Dictionary = world.sim.trade_buy(pool, game.coins, "food", 1, target, 999999)
		_check(String(out["err"]) == "", "у торговой точки можно купить")

	# --- вход в локацию: данж генерируется с биомом точки интереса ---
	var dungeon_poi: Dictionary = {}
	for poi in world.map.pois:
		if String(poi["kind"]) == "dungeon" and String(poi["biome"]) != "":
			dungeon_poi = poi
			break
	world._enter_location(dungeon_poi)
	var dungeon: Node = load("res://scenes/dungeon.tscn").instantiate()
	root.add_child(dungeon)
	await _frames(5)
	_check(is_instance_valid(dungeon), "локация генерируется без ошибок")
	_check(String(dungeon.biome.get("loc", "")) == "biome." + String(dungeon_poi["biome"]),
			"биом локации взят из точки интереса (M8)")
	dungeon.queue_free()
	await _frames(2)

	# --- возврат в город: герой входит с той стороны, с которой подошёл ---
	# (сцена мира делается текущей — иначе change_scene не сработает в headless)
	current_scene = world
	var hero_before: Vector2i = world.hero_tile
	var city_tile_w: Vector2i = world.map.city_tile
	world._enter_city()
	await _frames(4)
	var city: Node = current_scene
	_check(city != null and city != world and city.get("map") != null,
			"город открывается без ошибок (вход через рамку мира)")
	var back_tile: Vector2i = city.map.tile_of_px(city.hero.position)
	var d: Vector2i = hero_before - city_tile_w
	var side_ok := true
	if d == Vector2i.ZERO:
		side_ok = back_tile.x <= 3   # по умолчанию — западные ворота
	elif absi(d.x) >= absi(d.y):
		side_ok = (back_tile.x <= 3) if d.x < 0 else (back_tile.x >= city.map.w - 4)
	else:
		side_ok = (back_tile.y <= 3) if d.y < 0 else (back_tile.y >= city.map.h - 4)
	_check(side_ok, "в город герой вошёл с той стороны, с которой подошёл (симметрия)")

	# --- шаг на рамку города — автоматический переход на карту мира ---
	var exit_tile := Vector2i(0, city.map.h / 2)   # западный край (чистая зона у арки)
	city.hero.position = city.map.tile_center_px(exit_tile)
	await _frames(3)
	var world2: Node = current_scene
	_check(world2 != null and world2 != city and world2.get("map") != null,
			"шаг на рамку города переносит на карту мира")
	_check(world2.hero_tile == world2.map.city_tile + Vector2i(-1, 0),
			"на карте мира герой появился с запада — с той стороны, откуда вышел")

	if _fails == 0:
		print("SMOKE OK: карта мира работает")
		quit(0)
	else:
		print("SMOKE FAIL: упавших проверок: %d" % _fails)
		quit(1)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: " + what)
	else:
		_fails += 1
		print("  FAIL: " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
