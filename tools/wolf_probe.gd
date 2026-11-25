extends SceneTree
func _init() -> void:
	var cfg: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/city.json", FileAccess.READ).get_as_text())
	var gen: Dictionary = cfg.duplicate(true)
	gen["river"] = false
	gen["plateaus"] = {}
	gen["map_w"] = 80
	gen["map_h"] = 60
	var cmap = load("res://scripts/city_map.gd").new()
	cmap.generate(7, gen)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(cmap, cfg, 6, "normal")
	sim._next_raid_at = 999999999.0
	for i in 30:
		var before: int = sim.animals.size()
		var a: Dictionary = sim._new_animal()
		if String(a["kind"]) == "wolf":
			print("волк! delta=", sim.animals.size() - before, " pos=", a["pos"])
	quit(0)
