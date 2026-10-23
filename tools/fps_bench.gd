extends SceneTree
## Бенчмарк деградации FPS (правки приёмки v1.21.4): проматывает ~75 игровых
## дней и меряет стоимость тика симуляции по подсистемам + счётчики сущностей.
## Запуск: godot --headless --path . --script res://tools/fps_bench.gd

var sim = null
var dt := 0.25


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _ms(callable: Callable, iters: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in iters:
		callable.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(iters)


func _full_tick() -> void:
	sim.tick(dt)
	sim.events.clear()


func _res_loop() -> void:
	for r in sim.residents:
		sim._update_resident(r, dt)


func _zone_cells() -> int:
	var n := 0
	for z in sim.zones:
		n += (z["cells"] as Array).size()
	return n


func _init() -> void:
	var cfg: Dictionary = _read_json("res://data/city.json")
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(7, cfg)
	sim = load("res://scripts/city_sim.gd").new()
	sim.setup(city_map, cfg, 10, "normal")
	sim.paused = false
	sim.hero_alive = true
	sim.hero_pos = city_map.tile_center_px(city_map.spawn_tile)
	sim.coins_sink = func(_n: int) -> void: pass
	sim.coins_source = func() -> int: return 20
	sim._enemies_cfg = _read_json("res://data/enemies.json")

	var day_len: float = float(cfg["day_length"])
	var target_day := 75.0
	var next_measure := 1.0
	print("=== БЕНЧМАРК ГОРОДА: dt=%.2f, до дня %.0f ===" % [dt, target_day])
	while sim.time < target_day * day_len:
		sim.tick(dt)
		sim.events.clear()
		if float(sim.time) / day_len >= next_measure:
			next_measure += 5.0
			var full := _ms(_full_tick, 200)
			var t_animals := _ms(func() -> void: sim._update_animals(dt), 200)
			var t_stock := _ms(func() -> void: sim._update_livestock(dt), 200)
			var t_wand := _ms(func() -> void: sim._update_wanderers(dt), 200)
			var t_zones := _ms(func() -> void: sim._update_zones(dt, day_len), 200)
			var t_forest := _ms(func() -> void: sim._update_forest(dt, day_len), 200)
			var t_threat := _ms(func() -> void: sim._update_threat(dt, day_len), 200)
			var t_res := _ms(_res_loop, 200)
			var trees_total := 0
			for y in city_map.h:
				for x in city_map.w:
					if int(city_map.grid[y][x]) == city_map.TILE_TREE:
						trees_total += 1
			print("день %3d | tick %.3f мс | res %.3f (n=%d) | threat %.3f | zones %.3f | forest %.3f | animals %.3f | stock %.3f | wand %.3f" % [
					sim.day_number(), full, t_res, sim.residents.size(), t_threat, t_zones,
					t_forest, t_animals, t_stock, t_wand])
			print("        bld=%d trees=%d stumps=%d sapl=%d logs=%d graves=%d animals=%d stock=%d raiders=%d zones=%d cells=%d roads=%d wear=%d chron=%d necro=%d thought=%d" % [
					sim.buildings.size(), trees_total, city_map.stumps.size(), city_map.saplings.size(),
					city_map.logs.size(), sim.graves.size(), sim.animals.size(), sim.livestock.size(),
					sim.raiders.size(), sim.zones.size(), _zone_cells(),
					city_map.road.size(), city_map.wear.size(), sim.chronicle.size(),
					int(sim.necro_army), sim.thought_log.size()])
	quit(0)
