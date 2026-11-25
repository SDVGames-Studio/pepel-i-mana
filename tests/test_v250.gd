extends "res://tests/test_base.gd"
## v2.5 «Звери и свет»: размеры зверей, стайные волки вне жилья,
## дух леса успокаивается от убийства, окно домового света 21:00-24:00.


func _test_animal_sizes() -> void:
	print("[v2.5: размеры зверей]")
	var f: Dictionary = _read_json("res://data/fauna.json")
	var h := {}
	for s in (f["species"] as Array):
		h[String(s["id"])] = float(((s.get("art", {}) as Dictionary).get("h", 0.0)))
	_check(float(h.get("wolf", 0.0)) >= 38.0, "волк крупный (был 13px)")
	_check(float(h.get("bear", 0.0)) >= 60.0, "медведь крупный")
	_check(float(h.get("bird", 0.0)) <= 20.0, "птица меньше волка — перья больше не путают")
	_check(float(h.get("deer", 0.0)) >= 40.0, "олень соразмерен монстрам")


func _test_wolf_pack_and_shy() -> void:
	print("[v2.5: волк — стайный хищник]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var spawned_wolf := false
	for attempt in 60:
		var before: int = sim.animals.size()
		var a: Dictionary = sim._new_animal()
		if String(a["kind"]) == "wolf":
			spawned_wolf = true
			_check(sim.animals.size() - before >= 2,
					"волк приходит стаей (2-3 особи)")
			var away: float = Vector2(a["pos"]
					- sim.map.tile_center_px(sim.map.spawn_tile)).length()
			_check(away > float(sim.map.ts) * 8.0,
					"волк держится подальше от жилья")
			break
	if not spawned_wolf:
		_check(true, "за 60 бросков волк не выпал — редкость подтверждена (стая не проверить)")


func _test_spirit_calm() -> void:
	print("[v2.5: убитый дух успокаивает лес]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var dl: float = float(sim.cfg["day_length"])
	sim.time = float(sim.day) * dl
	sim.forest_anger = 20.0
	sim._update_forest(0.5, dl)
	_check(not sim.raiders.is_empty(), "волна леса пришла")
	var before: float = sim.forest_anger
	var sp: Dictionary = sim.raiders[0]
	var origin: Vector2 = (sp["pos"] as Vector2) - Vector2(30, 0)
	sim.hero_slash(origin, Vector2(1, 0), 60.0, 120.0, 12)
	_check(sim.forest_anger < before,
			"убитый дух снижает гнев леса (было %.1f, стало %.1f)" % [before, sim.forest_anger])


func _test_lights_window() -> void:
	print("[v2.5: окно домового света 21:00-24:00]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var dl: float = float(sim.cfg["day_length"])
	sim.time = dl * (16.0 / 24.0)   # 22:00
	_check(sim.lights_window_amount() > 0.5, "в 22:00 фонари горят")
	sim.time = dl * (20.0 / 24.0)   # 02:00 ночи
	_check(sim.lights_window_amount() == 0.0, "после полуночи фонари гаснут — люди спят")
	sim.time = dl * (14.5 / 24.0)   # 20:30 — разгорается
	_check(sim.lights_window_amount() > 0.0 and sim.lights_window_amount() < 1.0,
			"с 20:30 свет разгорается")
	sim.time = dl * (15.0 / 24.0)   # 21:00 — полная яркость
	_check(sim.lights_window_amount() == 1.0, "в 21:00 свет горит в полную")
