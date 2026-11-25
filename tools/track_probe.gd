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
	var dl: float = float(sim.cfg["day_length"])
	var r: Dictionary = sim.residents[0]
	print("res0: name=", r["name"], " prof=", r["prof"], " pos=", r["pos"])
	r["inside"] = 0
	r["pos"] = Vector2(100, 100)
	sim.time = float(sim.day) * dl
	sim._track_accum = 0.9
	sim._update_tracks(1.0, dl)
	print("после 1: tracks=", sim.city_tracks.size(), " last_keys=", sim._track_last.keys())
	r["pos"] = Vector2(140, 100)
	sim._track_accum = 0.9
	sim._update_tracks(1.0, dl)
	for tr in sim.city_tracks:
		print("  track who=", tr["who"], " pos=", tr["pos"], " t=", tr["t"])
	print("животных:", sim.animals.size(), " путников:", sim.wanderers.size())
	quit(0)
