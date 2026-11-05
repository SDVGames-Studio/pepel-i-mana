# v1.51 «Карта и место»: обзорная карта города (данные/легенда) и выбор
# места города на старте (валидация клетки, перенос города на карте мира).
extends "res://tests/test_base.gd"


func _test_v151_overview() -> void:
	print("[v1.51: обзорная карта города]")
	var sim := _make_sim()
	var ov = load("res://scripts/city_overview.gd").new()
	ov.setup(sim.map, sim)
	_check(ov.legend_entries().size() >= 8, "легенда: есть ключевые цвета")
	# цвет тайла — чистая функция: вода/скала/руда/дерево/луг/дорога
	var m = sim.map
	var kinds := {"water": false, "rock": false, "tree": false, "grass": false}
	for y in m.h:
		for x in m.w:
			var t := Vector2i(x, y)
			var g: int = m.grid[y][x]
			var c: Color = ov._tile_color(t)
			if g == m.TILE_WATER and c == Color(0.25, 0.47, 0.68):
				kinds["water"] = true
			elif g == m.TILE_ROCK and c == Color(0.55, 0.55, 0.58):
				kinds["rock"] = true
			elif g == m.TILE_TREE and c == Color(0.16, 0.34, 0.16):
				kinds["tree"] = true
			elif g == m.TILE_GRASS and not m.road.has(t) \
					and c == Color(0.35, 0.62, 0.28):
				kinds["grass"] = true
	_check(kinds["water"], "обзор: вода своим цветом")
	_check(kinds["rock"], "обзор: скалы своим цветом")
	_check(kinds["tree"], "обзор: лес своим цветом")
	_check(kinds["grass"], "обзор: луг своим цветом")
	# запечка карты в текстуру: размер = тайлы карты
	ov._rebake_map()
	_check(ov._tex != null and int(ov._tex.get_width()) == m.w
			and int(ov._tex.get_height()) == m.h,
			"обзор: земля запечена 1px/тайл (%dx%d)" % [int(ov._tex.get_width()), int(ov._tex.get_height())])
	ov.free()


func _test_v151_city_found() -> void:
	print("[v1.52: выбор места города на КАРТЕ ГОРОДА]")
	var cfg: Dictionary = _read_json("res://data/city.json")
	var gen_cfg: Dictionary = cfg.duplicate(true)
	gen_cfg["river"] = false
	gen_cfg["map_w"] = 96
	gen_cfg["map_h"] = 72
	# карта города для выбора места (как prepare_city_map, но с фикс. сидом)
	var m = load("res://scripts/city_map.gd").new()
	m.generate(42, gen_cfg)
	# валидатор: годная клетка есть, вода/край/аномалия — отказ
	var land := Vector2i(-1, -1)
	var bad_water := Vector2i(-1, -1)
	for y in range(8, m.h - 9):
		for x in range(8, m.w - 9):
			var t := Vector2i(x, y)
			if land == Vector2i(-1, -1) and m.can_found_at(t) == "":
				land = t
			if bad_water == Vector2i(-1, -1) and m.grid[t.y][t.x] == m.TILE_WATER:
				bad_water = t
	_check(land != Vector2i(-1, -1), "валидатор: годное место на карте города есть")
	_check(m.can_found_at(Vector2i(0, 0)) == "pick.bad_edge",
			"валидатор: у края карты город не ставится")
	_check(m.can_found_at(m.anomaly_tile) == "pick.bad_anomaly",
			"валидатор: у аномалии город не ставится")
	if bad_water != Vector2i(-1, -1):
		_check(m.can_found_at(bad_water) == "pick.bad_water",
				"валидатор: на воде/скале город не ставится")
	# основание: spawn переносится, площадка чистится, все достижимо,
	# симуляция встаёт у НОВОГО места (жители/площадь/голем)
	m.found_at(land)
	_check(m.spawn_tile == land, "found_at: точка появления перенесена")
	var reach: Dictionary = m._reachable_from(m.spawn_tile)
	_check(reach.has(m.anomaly_tile) and reach.has(m.world_exit_tile),
			"после основания аномалия и выход достижимы от нового города")
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(m, cfg, 1, "normal")
	_check(sim.residents.size() >= 1, "симуляция создана на найденном месте")
	var near_ok := true
	for r in sim.residents:
		if Vector2(r["pos"]).distance_to(m.tile_center_px(m.spawn_tile)) > 6.0 * float(m.ts):
			near_ok = false
	_check(near_ok, "жители появляются у выбранного места города")
	_check(sim.plaza != Vector2i(-1, -1)
			and Vector2(sim.plaza).distance_to(Vector2(m.spawn_tile)) <= 3.0,
			"площадь накрывает новое место города")
	# Полный путь Game.prepare_city_map/found_city покрывает живой прогон
	# (автозагрузки в headless-тестах недоступны — грабли AGENTS.md).
