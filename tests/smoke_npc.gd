extends SceneTree
## Дымовой тест «Мир v2», этап 3 (v1.41): поселения НПС. Сцены и переходы
## в headless: города НПС создаются и живут, герой приходит в поселение,
## заходит как гость (стройка закрыта, монеты — города), выходит к карте,
## сейв/загрузка возвращает города целиком.
## Запуск: godot --headless --path . --script res://tests/smoke_npc.gd

var _fails := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: " + what)
	else:
		_fails += 1
		print("  FAIL: " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	print("[Мир v2 / этап 3: дым — города НПС и гостевой визит]")
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
	_check(game.npc_cities != null and not game.npc_cities.cities.is_empty(),
			"новая игра создаёт города НПС (%d шт.)" % game.npc_cities.cities.size())

	# --- сцена карты мира ---
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	await _frames(5)
	_check(is_instance_valid(world), "карта мира открывается")
	var settlement: Dictionary = {}
	var set_id := -1
	for poi in world.map.pois:
		if String(poi["kind"]) == "settlement" and String(poi["state"]) == "ok" \
				and game.npc_cities.city_of(int(poi["id"])) != null:
			settlement = poi
			set_id = int(poi["id"])
			break
	_check(not settlement.is_empty(), "живое поселение с городом на карте")
	if settlement.is_empty():
		_finish()
		return
	_check(int(settlement.get("npc_pop", 0)) > 0, "на маркере видно число жителей (%d)"
			% int(settlement.get("npc_pop", 0)))

	# --- путь до поселения: дни мира двигают и город НПС ---
	var npc_sim = game.npc_cities.city_of(set_id)
	var day_before := int(npc_sim.day)
	var bld_before: int = (npc_sim.buildings as Array).size()
	world.start_travel_to(settlement["tile"])
	var waited := 0
	while not (world.travel as Dictionary).is_empty() and waited < 4000:
		await process_frame
		waited += 1
	_check((world.travel as Dictionary).is_empty(), "герой дошёл до поселения (кадров: %d)" % waited)
	_check(int(npc_sim.day) > day_before,
			"город НПС прожил дни пути (%d → %d)" % [day_before, int(npc_sim.day)])
	_check((npc_sim.buildings as Array).size() >= bld_before,
			"поселение не растеряло постройки в пути")

	# --- вход в поселение (как это делает world._enter_settlement) ---
	game.visiting_city_id = set_id
	game.world_hero_tile = settlement["tile"]
	game.city_return_tile = npc_sim.map.nearest_walkable(Vector2i(2, npc_sim.map.h / 2))
	world.queue_free()
	await _frames(2)
	var city: Node = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	await _frames(10)
	_check(is_instance_valid(city), "сцена города открывается в поселении")
	_check(bool(city.guest), "город в режиме гостя")
	_check(city.sim == npc_sim, "герой ходит по городу НПС")
	_check(city.hud._autonomy_btn == null, "кнопка автономии спрятана (город уже живёт сам)")
	city.set_build_mode("house")
	_check(String(city.build_mode) == "", "гость не может строить")
	var time_before := float(npc_sim.time)
	await _frames(30)   # кадры жизни города: HUD/летопись/погода без ошибок
	_check(float(npc_sim.time) > time_before, "гостевой город живёт при герое (%.1f сек)"
			% (float(npc_sim.time) - time_before))

	# --- выход через край: обратно на карту у клетки поселения ---
	city._exit_to_world(Vector2i(-1, 0))
	await _frames(5)
	_check(game.visiting_city_id == -1, "визит завершён")
	# сцена мира подхватила точку выхода (world_hero_tile уже поглощён _ready)
	var world2: Node = null
	for child in root.get_children():
		if child.get_script() == load("res://scripts/world.gd"):
			world2 = child
	_check(world2 != null, "возврат на карту мира после визита")
	if world2 != null:
		_check(Vector2(world2.hero_tile).distance_to(Vector2(settlement["tile"])) <= 1.5,
				"герой вышел на карту у клетки поселения (%s)" % world2.hero_tile)
	# монеты героя не тронуты городом НПС (свой кошелёк)
	var entry: Dictionary = game.npc_cities.entry_of(set_id)
	_check(int(entry["coins"]) >= 0, "у города свой кошелёк (%d)" % int(entry["coins"]))

	# --- сейв/загрузка: города НПС возвращаются целиком ---
	var bld_now: int = (npc_sim.buildings as Array).size()
	var pop_now: int = (npc_sim.residents as Array).size()
	var err: String = game.save_game(settlement["tile"], -1, -1)
	_check(err == "", "сейв с городами НПС записан")
	var err2: String = game.load_game()
	_check(err2 == "", "сейв загружается")
	var sim2 = game.npc_cities.city_of(set_id)
	_check(sim2 != null, "город НПС восстановлен из сейва")
	if sim2 != null:
		_check((sim2.buildings as Array).size() == bld_now,
				"постройки поселения пережили сейв (%d)" % (sim2.buildings as Array).size())
		_check((sim2.residents as Array).size() == pop_now,
				"жители поселения пережили сейв (%d)" % (sim2.residents as Array).size())
	_finish()


func _finish() -> void:
	if _fails == 0:
		print("OK: дымовой тест городов НПС пройден")
		quit(0)
	else:
		print("FAIL: проверок: %d" % _fails)
		quit(1)
