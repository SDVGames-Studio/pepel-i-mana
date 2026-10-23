# Правки v1.21: три размера деревьев и распилка, сырой камень и переработка,
# пустая порода и шахта, поле фермы, липкая цель голема, FPS-счётчик.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_v121_balance() -> void:
	print("[v1.21: баланс леса, горы, фермы]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	_check(city is Dictionary and loc is Dictionary, "конфиги читаются")
	if not (city is Dictionary and loc is Dictionary):
		return
	var forest: Dictionary = city.get("forest", {})
	var sizes: Array = ["small", "medium", "large"]
	for key in ["chop_days", "planks_per_tree", "carry_mult"]:
		_check((forest.get(key, {}) as Dictionary).has_all(sizes),
				"forest.%s — таблица по трём размерам" % key)
	var planks: Dictionary = forest.get("planks_per_tree", {})
	_check(int(planks.get("small", 0)) == 10 and int(planks.get("medium", 0)) == 20 \
			and int(planks.get("large", 0)) == 35,
			"доски с дерева: 10/20/35 (заказчик)")
	var chop: Dictionary = forest.get("chop_days", {})
	_check(float(chop.get("small", 9)) < float(chop.get("medium", 0)) \
			and float(chop.get("medium", 0)) < float(chop.get("large", 0)),
			"большое дерево рубить дольше малого и среднего")
	var carry: Dictionary = forest.get("carry_mult", {})
	_check(float(carry.get("small", 0)) > float(carry.get("medium", 0)) \
			and float(carry.get("medium", 0)) > float(carry.get("large", 0)),
			"большое бревно тащить тяжелее")
	_check(absf(float(forest.get("anger_per_tree", 0)) - 1.0) < 0.001,
			"сруб дерева — ровно +1 гнева (заказчик)")
	_check(absf(float(forest.get("anger_per_sawing", 0)) - 0.5) < 0.001,
			"распилка дерева — +0.5 гнева (заказчик)")
	_check(absf(float(forest.get("grow_days", 0)) - 5.0) < 0.001 \
			and absf(float(forest.get("grow_days_medium", 0)) - 5.0) < 0.001 \
			and absf(float(forest.get("grow_days_large", 0)) - 10.0) < 0.001,
			"рост дерева: 5 дней до малого, +5 до среднего, +10 до большого")
	var mountain: Dictionary = city.get("mountain", {})
	_check(float(mountain.get("raw_per_tile", 0)) > 0.0 and float(mountain.get("carry_raw", 0)) > 0.0,
			"гора: сырой камень добывается и переносится руками")
	for key in ["by_iron", "by_gems", "by_crystal"]:
		_check(float(mountain.get(key, 1.0)) > 0.0 and float(mountain.get(key, 0)) < 1.0,
				"гора: шанс %s — небольшой, но есть" % key)
	_check(int(mountain.get("mine", {}).get("range", 0)) == 2,
			"шахта добывает в радиусе 2 клеток (заказчик)")
	var farming: Dictionary = city.get("farming", {})
	_check(int(farming.get("field_radius", 0)) == 2, "поле фермы — 2 клетки вокруг")
	var saw_def := {}
	var farm_def := {}
	var mine_def := {}
	for b in city.get("buildings", []):
		match String(b.get("id", "")):
			"sawmill":
				saw_def = b
			"farm":
				farm_def = b
			"mine":
				mine_def = b
	_check(not saw_def.has("place"), "лесопилка ставится где угодно (без place)")
	_check(String(saw_def.get("place", "")) != "forest", "лесопилка больше не привязана к лесу")
	_check(not farm_def.has("produce") and bool(farm_def.get("field", false)),
			"ферма: без пассивной еды, распахивает поле")
	_check(String(mine_def.get("place", "")) == "veins", "шахта — у жил/выработанного массива")
	for key in ["res.gems", "city.placement_field", "city.zone_field_farm",
			"chron.tree_sawed", "city.quarry_bonus_toast", "city.farm_field_toast",
			"city.state.chop", "city.state.prep", "city.state.saw", "chron.farm_field",
			"chron.gems_found", "city.zone_tooltip_field"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	# стоимости: ранние здания дешевле поздних, всё достижимо деревом и камнем
	_check(int((saw_def.get("cost", {}) as Dictionary).get("wood", 99)) <= 12,
			"лесопилка доступна ранней игре (дерево ≤ 12)")
	_check(int((farm_def.get("cost", {}) as Dictionary).get("wood", 99)) <= 10,
			"ферма доступна ранней игре (дерево ≤ 10)")


func _test_v121_trees() -> void:
	print("[v1.21: размеры деревьев, рост, доски героя]")
	var sim := _make_sim()
	sim._last_daily_day = 999
	sim.cfg["food_per_resident_day"] = 0.0
	# всем деревьям карты назначен размер
	var tree_tiles := 0
	var sized := 0
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_TREE:
				tree_tiles += 1
				if sim.map.tree_size.has(Vector2i(x, y)):
					sized += 1
	_check(tree_tiles > 0 and tree_tiles == sized, "каждому дереву карты назначен размер")
	# герой: удары и доски по размеру
	_check(sim._hero_chop_hits(sim.map.TREE_SMALL) == 4 \
			and sim._hero_chop_hits(sim.map.TREE_MEDIUM) == 7 \
			and sim._hero_chop_hits(sim.map.TREE_LARGE) == 11,
			"герой валит: малое 4 удара, среднее 7, большое 11")
	_check(sim._planks_for(sim.map.TREE_SMALL) == 10.0 \
			and sim._planks_for(sim.map.TREE_MEDIUM) == 20.0 \
			and sim._planks_for(sim.map.TREE_LARGE) == 35.0,
			"досок с дерева: 10/20/35")
	# вырубка и посадка: саженец растёт 5 дней до малого, потом дичает до большого
	var plant_cells: Array = _grass_tiles(sim, sim.map.spawn_tile + Vector2i(6, 6), 1)
	_check(not plant_cells.is_empty(), "нашлась трава под саженец")
	var tile: Vector2i = plant_cells[0]
	sim.res["saplings"] = 3.0
	_check(sim.plant_sapling(tile) == "", "герой посадил саженец из пула")
	var day_len: float = float(sim.cfg["day_length"])
	sim.tick(day_len * 5.05)
	_check(sim.map.grid[tile.y][tile.x] == sim.map.TILE_TREE \
			and int(sim.map.tree_size.get(tile, 0)) == sim.map.TREE_SMALL,
			"через 5 дней саженец — малое дерево")
	sim.tick(day_len * 5.05)
	_check(int(sim.map.tree_size.get(tile, 0)) == sim.map.TREE_MEDIUM,
			"ещё 5 дней — среднее")
	sim.tick(day_len * 10.05)
	_check(int(sim.map.tree_size.get(tile, 0)) == sim.map.TREE_LARGE,
			"ещё 10 дней — большое")


func _test_v121_quarry() -> void:
	print("[v1.21: каменоломня — сырой камень, переработка, пустая порода]")
	var sim := _make_sim()
	sim._last_daily_day = 999
	sim.cfg["food_per_resident_day"] = 0.0
	# форсируем: жилы не вскрываются, переработка всегда даёт железо
	sim.cfg["mountain"]["ore_reveal"] = 0.0
	sim.cfg["mountain"]["by_iron"] = 1.0
	var miner := _add_resident(sim, "Герд", "miner")
	miner["traits"] = []
	miner["mood"] = 100.0
	var qtile: Vector2i = _find_free_tile(sim, sim.map.spawn_tile, "quarry")
	_check(qtile != Vector2i(-1, -1), "нашлось место у скал")
	var quarry := _build_at(sim, "quarry", qtile)
	_check(bool(quarry["done"]), "каменоломня построена")
	var rock_t: Vector2i = sim._nature_near_rect("quarry", qtile, [sim.map.TILE_ROCK, sim.map.TILE_ORE], 2.0)
	_check(rock_t != Vector2i(-1, -1), "у каменоломни есть гряда")
	_teleport(sim, miner, qtile)
	sim.time = 10.0
	var hauled := false
	for i in 80:   # тайл 80 hp по 55/день + ходьба — пара ходок
		sim.tick(12.0)
		if float((quarry["pile"] as Dictionary).get("stone", 0.0)) > 0.0:
			hauled = true
			break
	_check(hauled, "шахтёр принёс сырой камень — переработан в стройкамень (куча)")
	_check(float((quarry["pile"] as Dictionary).get("iron", 0.0)) > 0.0,
			"переработка камня даёт железо (шанс 100% в тесте)")
	# выработанная гряда НЕ пропадает: жила или пустая порода (место под шахту)
	var deadrock_seen := false
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_DEADROCK:
				deadrock_seen = true
	if not deadrock_seen:
		# гряда могла ещё не выработаться — докрутим того же шахтёра
		for i in 120:
			sim.tick(12.0)
			for y2 in sim.map.h:
				for x2 in sim.map.w:
					if sim.map.grid[y2][x2] == sim.map.TILE_DEADROCK:
						deadrock_seen = true
	_check(deadrock_seen, "выработанная скала остаётся пустой породой (не травой)")
	# на пустую породу можно поставить шахту (в радиусе 2)
	var mine_ok := false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t: Vector2i = rock_t + Vector2i(dx, dy)
			if sim.placement_block("mine", t) == "" and sim.is_buildable_rect("mine", t):
				mine_ok = true
	if deadrock_seen:
		_check(mine_ok, "у пустой породы ставится шахта")


func _test_v21_golem_commit() -> void:
	print("[v1.21: голем-староста доводит цель]")
	var sim := _make_sim()
	sim._last_daily_day = 999
	var golem: Dictionary = {}
	for r in sim.residents:
		if String(r["prof"]) == "elder":
			golem = r
	_check(not golem.is_empty(), "голем-староста на месте")
	# пастбище с дальней клеткой — голем её начал
	var far_cells: Array = _grass_tiles(sim, sim.map.spawn_tile + Vector2i(9, 9), 1)
	_check(sim.add_zone("pasture", far_cells) == 1, "зона с дальней клеткой")
	var target: Dictionary = sim._nearest_zone_cell(golem)
	golem["_fill_zone"] = int((target["zone"] as Dictionary)["id"])
	golem["_fill_idx"] = int(target["idx"])
	golem["pos"] = sim.map.tile_center_px(sim.map.spawn_tile)   # стоит далеко
	# рядом поспела грядка — старая правка гнала голема к еде с полпути
	var field_cells: Array = _grass_tiles(sim, sim.map.spawn_tile + Vector2i(1, 1), 2)
	sim.add_zone("field", field_cells)
	var zfield: Dictionary = sim.zones[sim.zones.size() - 1]
	if not zfield.has("crops"):
		zfield["crops"] = []
	for i in (zfield["cells"] as Array).size():
		zfield["progress"][i] = 99.0
	while (zfield["crops"] as Array).size() < (zfield["cells"] as Array).size():
		(zfield["crops"] as Array).append({})
	(zfield["crops"] as Array)[0] = {"stage": 9, "t": 0.0, "ripe": true}
	# голем НЕ бросает начатую клетку ради спелой грядки (v1.21)
	sim._zone_fill_work(golem, 0.2)
	_check(Vector2i(golem["target"]) == Vector2i(target["tile"]),
			"начатая клетка доводится до конца — спелая грядка не перебивает")
	# а свободный от обязательств житель идёт к грядке
	var free_r: Dictionary = sim.residents[0]
	free_r["_fill_zone"] = -1
	free_r["_fill_idx"] = -1
	free_r["_ripe_zone"] = -1
	free_r["_ripe_idx"] = -1
	free_r["pos"] = sim.map.tile_center_px(sim.map.spawn_tile)
	sim._zone_fill_work(free_r, 0.2)
	_check(String(free_r["state"]) == "going" and Vector2i(free_r["target"]) == Vector2i(field_cells[0]),
			"свободный житель собирает спелую грядку")


func _test_v21_fps_counter() -> void:
	print("[v1.21: FPS-счётчик и лёгкий HUD]")
	var f := FileAccess.open("res://scripts/game.gd", FileAccess.READ)
	var text := f.get_as_text() if f != null else ""
	f = null
	_check(text.contains("get_frames_per_second"), "FPS-счётчик в игре (правый верх)")
	_check(text.contains("_fps_accum") and text.contains("0.25"),
			"счётчик обновляется 4 раза в секунду (не режет кадр)")
	var fc := FileAccess.open("res://scripts/city.gd", FileAccess.READ)
	var ctext := fc.get_as_text() if fc != null else ""
	fc = null
	_check(ctext.contains("_hud_refresh_accum"), "панели HUD обновляются по таймеру, не каждый кадр")
	_check(ctext.contains("_terrain_redraw_accum"), "перерисовка ландшафта — не чаще 2 раз в секунду")
