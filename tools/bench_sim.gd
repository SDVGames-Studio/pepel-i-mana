extends SceneTree
## Бенч симуляции города (v2.4, «проверь оптимизацию»): прогон дней под
## нагрузкой (волны/улей/ищейка/духи/чемпион/следы/лагеря) с замерами
## фаз тика (SIM_PROF), сквозного темпа (дней/сек) и микрозамеров новых
## систем v2.2. Запуск:
##   godot --headless --path . --script res://tools/bench_sim.gd
## Переменные: DAYS (сколько дней, по умолчанию 30), SEED.

const Tracks := preload("res://scripts/city_tracks.gd")


func _mk_sim(seed_v: int):
	var cfg: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/city.json", FileAccess.READ).get_as_text())
	var gen: Dictionary = cfg.duplicate(true)
	gen["river"] = false
	gen["plateaus"] = {}
	gen["map_w"] = 80
	gen["map_h"] = 60
	var cmap = load("res://scripts/city_map.gd").new()
	cmap.generate(seed_v, gen)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(cmap, cfg, 12, "normal")
	return sim


func _micro(name: String, fn: Callable, iters: int) -> void:
	var t0 := Time.get_ticks_usec()
	for i in iters:
		fn.call()
	var dt := float(Time.get_ticks_usec() - t0) / float(iters)
	print("  микро %s: %.1f мкс/вызов (%d итераций)" % [name, dt, iters])


func _init() -> void:
	var days := 30
	var env_days := OS.get_environment("DAYS")
	if env_days != "":
		days = int(env_days)
	var seed_v := 20261123
	var env_seed := OS.get_environment("SEED")
	if env_seed != "":
		seed_v = int(env_seed)
	OS.set_environment("PEPEL_HIVE_ON", "1")   # улей/ищейка/волны — в нагрузке
	OS.set_environment("SIM_PROF", "1")

	print("=== БЕНЧ СИМУЛЯЦИИ (сид %d, %d дней) ===" % [seed_v, days])
	var t0 := Time.get_ticks_msec()
	var sim = _mk_sim(seed_v)
	print("setup города: %d мс" % [Time.get_ticks_msec() - t0])

	# население и стройка под нагрузку (город ~20 жителей, стены, кузня)
	sim._ensure_elder()
	for i in 14:
		sim.residents.append({
			"id": 700 + i, "name": "Горожанин %d" % i, "prof": "",
			"goal": "", "log": [], "pos": Vector2(100 + i * 20, 100),
			"bld": null, "site": null, "ail": "", "mood": 60.0,
			"skill": 2.0, "rank": 1, "age_days": 120.0, "state": "idle",
			"inside": 0, "traits": [], "secret": "", "fatigue": 0.0,
			"prof_extra": [], "tavern_asked": false,
		})
	sim.res["wood"] = 400.0
	sim.res["stone"] = 300.0
	sim.res["food"] = 200.0
	var day_len := float(sim.cfg["day_length"])
	# кузня и стены, чтобы оборонный рывок не мешал замерам
	var ft: Vector2i = sim.map.spawn_tile + Vector2i(3, 1)
	sim.buildings.append({"id": 800, "type": "forge", "tile": ft, "done": true,
			"worker": -1, "progress": 0.0, "hp": 1.0})

	# сквозной прогон: волны по расписанию, рейд активен периодически
	t0 = Time.get_ticks_msec()
	var ticks := 0
	var raid_ticks := 0
	for d in days:
		sim.day = d + 1
		sim.time = float(sim.day) * day_len
		sim._last_daily_day = sim.day - 1   # дневные блоки идут каждый день
		sim._next_raid_at = sim.time + day_len * 2.5   # волна раз в 2.5 дня
		var half := int(day_len / 2.0)
		for i in half:
			sim.tick(1.0)
			ticks += 1
			if sim.raid_active:
				raid_ticks += 1
		sim.raid_active = false
		sim.raiders.clear()
	var wall_ms := float(Time.get_ticks_msec() - t0)
	var per_day := wall_ms / float(days)
	var per_tick_ms := wall_ms * 1000.0 / float(maxi(1, ticks))
	print("прогон: %d дней, %d тиков (в волнах %d%%) — %d мс всего" %
			[days, ticks, raid_ticks * 100 / maxi(1, ticks), int(wall_ms)])
	print("темп: %.2f дней/сек | тик %.3f мс (бюджет кадра 16.6 мс)" %
			[float(days) * 1000.0 / wall_ms, per_tick_ms])

	# --- микрозамеры систем v2.2 на реальном состоянии ---
	print("=== МИКРО (состояние после прогона) ===")
	print("  следов: %d | духов: %d | жителей: %d | рейдеров: %d | построек: %d" %
			[sim.city_tracks.size(), sim.spirits.size(), sim.residents.size(),
			sim.raiders.size(), sim.buildings.size()])
	_micro("тик следов (_update_tracks)", func() -> void:
		sim._track_accum = 0.9
		sim._update_tracks(1.0, day_len), 200)
	_micro("поиск следа (Tracks.near, кто=res)", func() -> void:
		Tracks.near(sim.city_tracks, Vector2(400, 300), 90.0,
				float(sim.time), 100000.0, "res"), 500)
	_micro("цепочка (Tracks.chain, 12 звеньев)", func() -> void:
		Tracks.chain(sim.city_tracks, Vector2(400, 300), 90.0,
				float(sim.time), 100000.0, "", 12), 200)
	# ищейка нюхает следы
	var seeker_upd := func() -> void:
		if sim.raiders.is_empty():
			return
		sim._hive_seeker_update(sim.raiders[0], 0.016)
	_micro("нюх ищейки (_hive_seeker_update)", seeker_upd, 300)
	# дух: тик духов (стройка+добыча)
	if sim.spirits.is_empty():
		var altar: Vector2i = sim.map.spawn_tile + Vector2i(4, 2)
		sim.buildings.append({"id": 801, "type": "grace_altar", "tile": altar,
				"done": true, "worker": -1, "progress": 0.0, "hp": 1.0,
				"spirit_respawn_day": -1})
		sim.spirit_summon(sim.buildings[sim.buildings.size() - 1])
		sim.spirits[0]["mode"] = "gather"
	_micro("тик духов (_update_spirits)", func() -> void:
		sim._update_spirits(0.016), 300)
	# чемпион
	sim.champion = {"name": "Ратмир", "hp": 60.0, "hp_max": 60.0, "atk": 9.0,
			"speed": 80.0, "pos": Vector2(500, 400), "target": Vector2i(-1, -1),
			"cd": 0.0, "alive": true}
	_micro("тик чемпиона (_update_champion)", func() -> void:
		sim._update_champion(0.016), 300)
	# чистка следов (раз в день)
	_micro("prune следов (раз в день)", func() -> void:
		Tracks.prune(sim.city_tracks, float(sim.time) + 0.001,
				1.2 * day_len), 50)

	print("=== ГОТОВО ===")
	quit(0)
