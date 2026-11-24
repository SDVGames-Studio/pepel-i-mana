extends SceneTree
## Точечная проба духа: почему gather жрёт ~1.3 мс на вызов.

func _init() -> void:
	var cfg: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/city.json", FileAccess.READ).get_as_text())
	var gen: Dictionary = cfg.duplicate(true)
	gen["river"] = false
	gen["plateaus"] = {}
	gen["map_w"] = 80
	gen["map_h"] = 60
	var cmap = load("res://scripts/city_map.gd").new()
	cmap.generate(20261123, gen)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(cmap, cfg, 6, "normal")
	var altar: Vector2i = sim.map.spawn_tile + Vector2i(4, 2)
	sim.buildings.append({"id": 801, "type": "grace_altar", "tile": altar,
			"done": true, "worker": -1, "progress": 0.0, "hp": 1.0,
			"spirit_respawn_day": -1})
	sim.spirit_summon(sim.buildings[sim.buildings.size() - 1])
	sim.spirits[0]["mode"] = "gather"
	var pos: Vector2 = sim.spirits[0]["pos"]
	print("res_ok(-1,-1)=", sim._spirit_res_ok(Vector2i(-1, -1)),
			" | in_bounds=", sim.map.in_bounds(Vector2i(-1, -1)),
			" | find=", sim._spirit_find_res(pos))
	for i in 2:
		print("ДО вызова res_tile=", str(sim.spirits[0].get("res_tile", "НЕТ")))
		var t0 := Time.get_ticks_usec()
		sim._update_spirits(0.016)
		var dt := Time.get_ticks_usec() - t0
		var sp: Dictionary = sim.spirits[0]
		print("вызов %d: %d мкс | res_tile=%s | retry=%s | mode=%s" % [i + 1, dt,
				str(sp.get("res_tile", "НЕТ")), str(sp.get("res_retry", "НЕТ")),
				str(sp["mode"])])
	quit(0)
