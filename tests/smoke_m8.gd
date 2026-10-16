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
	world.queue_free()
	await _frames(2)

	# --- возврат в город: герой появляется у выхода на карту мира ---
	game.city_return_tile = game.city_sim.map.world_exit_tile
	var city: Node = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	await _frames(5)
	_check(is_instance_valid(city), "город открывается без ошибок")
	print("  [dbg] hero=", city.hero.position, " exit=", city.map.tile_center_px(city.map.world_exit_tile),
			" ret=", game.city_return_tile, " spawn=", city.map.tile_center_px(city.map.spawn_tile))
	# герой вернулся к краю города: тайл героя — это выход или соседний с ним
	var hero_back_tile: Vector2i = city.map.tile_of_px(city.hero.position)
	var near_exit: bool = hero_back_tile == city.map.world_exit_tile \
			or hero_back_tile.distance_to(city.map.world_exit_tile) <= 1.5
	_check(near_exit, "герой вернулся в город у края, откуда выходил (M8)")
	city.queue_free()
	await _frames(2)

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
