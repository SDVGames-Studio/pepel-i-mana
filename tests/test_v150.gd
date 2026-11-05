# v1.50 «Живая земля»: лесные массивы и скальные хребты (своим RNG, сиды
# целы), бригадная починка домов (целый день, ресурсы/голыми руками/брёвна),
# конфиги зума и новой природы, ассеты ForgottenMemories, заяц и лиса.
extends "res://tests/test_base.gd"


func _test_v150_configs() -> void:
	print("[v1.50: конфиги «Живой земли»]")
	var c: Dictionary = _read_json("res://data/city.json")
	var en: Dictionary = c.get("extra_nature", {})
	_check(bool(en.get("enabled", false)), "добор природы включён")
	var f: Dictionary = en.get("forests", {})
	_check(int(f.get("size_min", 0)) >= 30 and int(f.get("size_max", 0)) <= 120
			and int(f.get("size_min", 0)) < int(f.get("size_max", 0)),
			"лесные массивы: кластеры 30–120 деревьев (%d–%d)" % [
			int(f.get("size_min", 0)), int(f.get("size_max", 0))])
	_check(float(f.get("chance", 0.0)) < 1.0, "лес — не на каждой карте (chance=%.2f)" % float(f.get("chance", 0.0)))
	var r: Dictionary = en.get("ridges", {})
	_check(int(r.get("len_min", 0)) >= 20 and int(r.get("len_max", 0)) <= 60,
			"хребты: гряды 20–60 тайлов (%d–%d)" % [
			int(r.get("len_min", 0)), int(r.get("len_max", 0))])
	_check(float(r.get("chance", 0.0)) < 1.0, "хребты — не на каждой карте (chance=%.2f)" % float(r.get("chance", 0.0)))
	_check(bool(en.get("lone_big", false)), "деревья-одиночки покрупнее (lone_big)")
	# зум карты колесом
	var z: Dictionary = c.get("zoom", {})
	_check(float(z.get("min", 0.0)) < float(z.get("max", 0.0)),
			"зум города: min < max (%.1f..%.1f)" % [float(z.get("min", 0.0)), float(z.get("max", 0.0))])
	# фауна: заяц и лиса
	var fz: Dictionary = _read_json("res://data/fauna.json")
	var kinds: Array = []
	for s in fz.get("species", []):
		kinds.append(String(s["id"]))
	_check("hare" in kinds, "фауна: есть заяц")
	_check("fox" in kinds, "фауна: есть лиса")
	# строки интерфейса
	var ru: Dictionary = _read_json("res://loc/ru.json")
	for key in ["fauna.hare", "fauna.fox"]:
		_check(not String(ru.get(key, "")).is_empty(), "ключ «%s» есть" % key)
	# ассеты ForgottenMemories на месте
	for n in ["fm_grass_L0", "fm_grass_L1", "fm_grass_L2", "fm_grass_L3",
			"fm_grass_D0", "fm_grass_D1", "fm_grass_D2", "fm_grass_D3",
			"fm_dirt_0", "fm_dirt_1", "fm_dirt_2", "fm_dirt_3"]:
		var t: Texture2D = load("res://assets/sprites/env/%s.png" % n)
		_check(t != null, "текстура природы %s.png есть" % n)
	var w: Texture2D = load("res://assets/sprites/env/fm_water.png")
	_check(w != null and w.get_width() == 192 and w.get_height() == 96,
			"анимированная вода fm_water — полоса 6 кадров × 3 ряда")


func _test_v150_forests_ridges() -> void:
	print("[v1.50: лесные массивы и скальные хребты]")
	var cfg: Dictionary = _read_json("res://data/city.json")
	# маленькая карта, ядро добора подальше от центра — чтобы кластеры влезали
	var gen_cfg: Dictionary = cfg.duplicate(true)
	gen_cfg["river"] = false
	gen_cfg["plateaus"] = {}
	gen_cfg["map_w"] = 96
	gen_cfg["map_h"] = 72
	gen_cfg["lakes"] = 0
	gen_cfg["swamps"] = 0
	gen_cfg["rocks"] = 0
	gen_cfg["ore_spots"] = 0
	gen_cfg["trees"] = 30
	var en: Dictionary = {
		"enabled": true, "trees": 10, "ponds": 0, "rocks": 0,
		"min_radius": 10, "anomaly_radius": 3, "lone_big": false,
		"forests": {"enabled": true, "chance": 1.0, "count_max": 1,
			"size_min": 30, "size_max": 120, "radius_min": 5, "radius_max": 8,
			"density": 0.85, "clearing": 0.14},
		"ridges": {"enabled": false},
	}
	gen_cfg["extra_nature"] = en
	# детерминизм: тот же сид — та же карта (деревья/скалы по хэшу сетки)
	var grid_a := _gen_grid_hash(911, gen_cfg)
	var grid_b := _gen_grid_hash(911, gen_cfg)
	_check(grid_a == grid_b, "лес/добор детерминированы по сиду")
	# кластеры: на нескольких сидах появляются леса по 30+ деревьев
	var forest_maps := 0
	for seed_v in [11, 22, 33, 44, 55, 66]:
		var counts := _gen_counts(seed_v, gen_cfg)
		if int(counts["trees"]) >= 30 + 10 + 20:
			forest_maps += 1
	_check(forest_maps >= 3,
			"лесные массивы выходят гуще базовых деревьев (%d/6 карт)" % forest_maps)
	# хребты: сплошная гряда из 20+ тайлов скалы, связность карты цела
	var rgen: Dictionary = gen_cfg.duplicate(true)
	rgen["extra_nature"] = {
		"enabled": true, "trees": 0, "ponds": 0, "rocks": 0,
		"min_radius": 10, "anomaly_radius": 3,
		"forests": {"enabled": false},
		"ridges": {"enabled": true, "chance": 1.0, "count_max": 2,
			"len_min": 20, "len_max": 40, "width": 1.6},
	}
	var ridge_maps := 0
	for seed_v in [11, 22, 33, 44, 55, 66]:
		var counts := _gen_counts(seed_v, rgen)
		if int(counts["rocks"]) >= 20:
			ridge_maps += 1
	_check(ridge_maps >= 3, "скальные хребты выходят грядами 20+ тайлов (%d/6 карт)" % ridge_maps)
	# связность после хребтов: аномалия и выход достижимы от старта
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(33, rgen)
	var reach: Dictionary = city_map._reachable_from(city_map.spawn_tile)
	_check(reach.has(city_map.anomaly_tile) and reach.has(city_map.world_exit_tile),
			"хребты не отрезают аномалию/выход от старта")


func _gen_grid_hash(seed_v: int, gen_cfg: Dictionary) -> int:
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(seed_v, gen_cfg)
	var acc := 0
	for y in city_map.h:
		for x in city_map.w:
			acc = (acc * 31 + int(city_map.grid[y][x])) % 1000000007
			if city_map.tree_size.has(Vector2i(x, y)):
				acc = (acc * 31 + int(city_map.tree_size[Vector2i(x, y)])) % 1000000007
	return acc


func _gen_counts(seed_v: int, gen_cfg: Dictionary) -> Dictionary:
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(seed_v, gen_cfg)
	var trees := 0
	var rocks := 0
	for y in city_map.h:
		for x in city_map.w:
			if int(city_map.grid[y][x]) == city_map.TILE_TREE:
				trees += 1
			elif int(city_map.grid[y][x]) == city_map.TILE_ROCK:
				rocks += 1
	return {"trees": trees, "rocks": rocks}


func _test_v150_brigade() -> void:
	print("[v1.50: бригадная починка домов]")
	var sim := _make_sim()
	var rcfg: Dictionary = sim.cfg.get("repair", {})
	sim._last_daily_day = 999999   # дневные броски (автостройка/беженцы) — прочь
	_check(int(rcfg.get("brigade_size", 0)) >= 2, "бригада: размер задан в city.json")
	_check(float(rcfg.get("no_res_mult", 1.0)) > 2.0, "без ресурсов — в разы дольше")
	_check(float(rcfg.get("log_speedup", 1.0)) < 1.0, "брёвна ускоряют починку")
	# дом и руина: руина приоритетнее (rank 0); брёвна изолированы
	# (log_speedup=1) — этот блок проверяет «целый день» чисто
	sim.cfg["repair"]["log_speedup"] = 1.0
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	var house := _build_now(sim, "house")
	var house_hp := float(sim._bld_max_hp("house"))
	sim._damage_building(house, house_hp * 10.0)
	_check(bool(house.get("razed", false)), "дом — руина для теста")
	# бригада: строители свободны — собираются сами
	sim._roll_city_repair()
	_check(not sim.brigade_job.is_empty(), "бригада собралась на руину")
	var bid := int(house["id"])
	_check(int(sim.brigade_job["bld"]) == bid, "цель бригады — самое битое здание")
	var members := 0
	for r in sim.residents:
		if int(r.get("repair_bld", 0)) == bid:
			members += 1
	_check(members >= 1, "члены бригады получили поручение (%d)" % members)
	# сроки: целый бодрствующий день
	var awake: float = maxf(0.3, 1.0 - float(sim.cfg.get("night_fraction", 0.22)))
	var expect: float = float(sim.cfg["day_length"]) * awake * float(rcfg.get("day_frac", 1.0))
	_check(absf(float(sim.brigade_job["need"]) - expect) < 0.5,
			"работа — целый день (%.0f из %.0f сек)" % [float(sim.brigade_job["need"]), expect])
	# члены бригады у здания: без черт и усталости — работа без перерывов
	for r in sim.residents:
		if int(r.get("repair_bld", 0)) == bid:
			r["traits"] = []
			r["fatigue"] = 0.0
			_teleport(sim, r, sim.bld_spot(house))
	var done1 := false
	for i in 12:
		sim.tick(60.0)
		if not bool(house.get("razed", false)):
			done1 = true
			break
	_check(done1, "за день работы бригада подняла руину")
	_check(int(sim.res["wood"]) < 200 or int(sim.res["stone"]) < 200,
			"ресурсы на ремонт взяты из общего пула")
	_check(sim.brigade_job.is_empty(), "работа закрыта после починки")
	# --- брёвна из пула: срубленные деревья ускоряют ---
	sim.cfg["repair"]["log_speedup"] = 0.5
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	var house2 := _build_now(sim, "house")
	var hp2 := float(sim._bld_max_hp("house"))
	sim._damage_building(house2, hp2 * 10.0)
	sim.res["wood"] = 14.0   # 4 брёвна + 10 досок
	sim._roll_city_repair()
	_check(not sim.brigade_job.is_empty(), "вторая бригада собралась")
	_check(bool(sim.brigade_job.get("logs", false)), "брёвна взяты в дело")
	_check(int(sim.res["wood"]) == 10,
			"logs_per_job брёвен списано при старте (14 → 10)")
	_check(absf(float(sim.brigade_job["need"]) - expect * 0.5) < 0.5,
			"с брёвнами починка вдвое быстрее (%.0f < %.0f)" % [float(sim.brigade_job["need"]), expect])
	sim.brigade_job = {}
	for r in sim.residents:
		if int(r.get("repair_bld", 0)) == int(house2["id"]):
			r["repair_bld"] = 0   # работу закрыли вручную — поручения снять
	# --- ресурсов нет: «голыми руками» дольше ---
	# house2 тихо «починен» — единственной руиной остаётся house3
	# (иначе дневной бросок может выбрать прежнюю руину)
	house2["razed"] = false
	house2["hp"] = float(sim._bld_max_hp("house"))
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	var house3 := _build_now(sim, "house")
	var hp3 := float(sim._bld_max_hp("house"))
	sim._damage_building(house3, hp3 * 10.0)
	sim.res["wood"] = 0.0
	sim.res["stone"] = 0.0
	sim.res["food"] = 200.0   # бригада должна голодать, а не бросать работу
	sim._roll_city_repair()
	_check(not sim.brigade_job.is_empty(), "бригада собирается и без ресурсов")
	var mult: float = float(rcfg.get("no_res_mult", 3.5))
	_check(absf(float(sim.brigade_job["need"]) - expect * mult) < 1.0,
			"голыми руками: need ×%.1f (%.0f сек)" % [mult, float(sim.brigade_job["need"])])
	# довели до конца — руина поднята БЕЗ списания ресурсов
	for r in sim.residents:
		if int(r.get("repair_bld", 0)) == int(house3["id"]):
			r["traits"] = []
			r["fatigue"] = 0.0
			_teleport(sim, r, sim.bld_spot(house3))
	var done3 := false
	for i in 24:
		sim.tick(60.0)
		if not bool(house3.get("razed", false)):
			done3 = true
			break
	_check(done3, "и без ресурсов (×3.5 дольше) руину подняли")
	_check(int(sim.res["wood"]) == 0, "без ресурсов пула не тронуты")
	# --- неполная бригада идёт медленнее (dt/total за пришедшего) ---
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	var house4 := _build_now(sim, "house")
	var hp4 := float(sim._bld_max_hp("house"))
	sim._damage_building(house4, hp4 * 10.0)
	sim._roll_city_repair()
	_check(not sim.brigade_job.is_empty(), "четвёртая бригада собралась")
	var bid4 := int(house4["id"])
	var arrived := 0
	for r in sim.residents:
		if int(r.get("repair_bld", 0)) == bid4:
			r["traits"] = []
			r["fatigue"] = 0.0
			_teleport(sim, r, sim.bld_spot(house4))
			arrived += 1
			if arrived == 1:
				break   # пришёл только один из бригады
	var work0: float = float(sim.brigade_job["work"])
	sim.tick(1.0)
	var gained: float = float(sim.brigade_job["work"]) - work0
	_check(gained > 0.0 and gained <= 1.2,
			"работа тикает по пришедшим (за 1 сек +%.2f от need)" % gained)
	sim.brigade_job = {}
