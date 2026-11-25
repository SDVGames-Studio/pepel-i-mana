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
	cmap.generate(20261123, gen)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(cmap, cfg, 6, "normal")
	sim._next_raid_at = 999999999.0
	sim.forest_anger = 20.0
	var dl: float = float(sim.cfg["day_length"])
	sim.time = float(sim.day) * dl
	sim._update_forest(0.5, dl)
	print("рейдеров после волны леса:", sim.raiders.size())
	if sim.raiders.is_empty():
		print("волна не пришла — anger/day условия не сошлись")
		quit(0)
		return
	var sp: Dictionary = sim.raiders[0]
	print("дух: hp=", sp["hp"], " type=", sp["type"], " mode=", sp.get("mode"))
	var facing: Vector2 = ((sp["pos"] as Vector2) - (sp["pos"] as Vector2))
	facing = Vector2(1, 0)
	sim.raiders[0]["pos"] = sim.hero_pos + Vector2(40, 0) if sim.hero_alive else (sp["pos"] as Vector2)
	# удар строго по позиции духа
	var origin: Vector2 = (sp["pos"] as Vector2) - Vector2(30, 0)
	var hits: int = sim.hero_slash(origin, Vector2(1, 0), 60.0, 120.0, 12)
	print("hero_slash задел:", hits, " | hp духа после:", sp["hp"])
	print("дух ещё в списке:", sim.raiders.has(sp))
	quit(0)
