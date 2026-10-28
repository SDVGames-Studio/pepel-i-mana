extends SceneTree
## Отладка сценария лесоруба из test_life_a на карте тестов (сид 7, без реки):
## почему дерево не рубится за 60 тиков.

func _init() -> void:
	var cfg: Variant = _read_json("res://data/city.json")
	var city_map = load("res://scripts/city_map.gd").new()
	var gen_cfg: Dictionary = (cfg as Dictionary).duplicate(true)
	gen_cfg["river"] = false
	gen_cfg["map_w"] = 80
	gen_cfg["map_h"] = 60
	city_map.generate(7, gen_cfg)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(city_map, cfg, 6, "normal")
	sim._last_daily_day = 1
	sim._next_raid_at = 999999999.0
	# первое дерево по скану
	var tree := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_TREE:
				tree = Vector2i(x, y)
				break
		if tree.x >= 0:
			break
	print("первое дерево: ", tree, " тип=", sim.map.water_kind_at(tree))
	# лесопилка рядом (как в тесте: не накрывает дерево)
	var spot := Vector2i(-1, -1)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t := tree + Vector2i(dx, dy)
			if not sim.is_buildable_rect("sawmill", t) or sim.placement_block("sawmill", t) != "":
				continue
			var covers := false
			for cell in sim.bld_cells({"type": "sawmill", "tile": t, "w": 2}):
				if cell == tree:
					covers = true
					break
			if not covers:
				spot = t
				break
	print("лесопилка: ", spot, " заложена=", sim.place_building("sawmill", spot))
	var lj := {}
	for r in sim.residents:
		if String(r["prof"]) == "lumberjack":
			lj = r
			break
	print("лесоруб id=", lj.get("id"), " traits=", lj.get("traits"))
	lj["mood"] = 100.0
	lj["traits"] = []
	lj["pos"] = sim.map.tile_center_px(tree)
	lj["target"] = Vector2i(-1, -1)
	lj["path"] = PackedVector2Array()
	sim.cfg["food_per_resident_day"] = 0.0
	sim.res["saplings"] = 0.0
	sim.time = 10.0
	var guard := 0
	while sim.map.grid[tree.y][tree.x] == sim.map.TILE_TREE and guard < 60:
		guard += 1
		sim.tick(2.0)
		sim.time = fmod(sim.time, float(sim.cfg["day_length"]) * 0.5) + 5.0
		if guard % 5 == 0 or guard < 8:
			var b: Variant = lj.get("bld")
			print("t%02d state=%s pos=%s gath=%s bld=%s chop_t=%.1f fatigue=%.2f work=%.2f" % [
					guard, lj["state"], lj["pos"],
					lj.get("gath_tile", Vector2i(-1, -1)),
					"да" if (b != null and not (b as Dictionary).is_empty()) else "нет",
					float(lj.get("chop_t", 0.0)), float(lj.get("fatigue", 0.0)),
					sim.work_mult(lj)])
	print("дерево после цикла: ", sim.map.grid[tree.y][tree.x], " (0=трава) тиков=", guard)
	quit()


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var v: Variant = JSON.parse_string(f.get_as_text())
	return v
