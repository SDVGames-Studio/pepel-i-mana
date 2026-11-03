extends "res://tests/test_base.gd"
## Улей мутантов («Новый мир v2» этап 2, v1.44): уровни от запаса, радиусы,
## роли, размер волн, следы героя, награда за разорение. Чистая логика
## HiveSim headless + сейв-круговорот блока улья.


func _test_hive_levels() -> void:
	print("[Улей: уровни и роли]")
	_check(HiveSim.level_for(0) == 1, "пустой улей — уровень 1")
	_check(HiveSim.level_for(59) == 1, "59 запаса — уровень 1")
	_check(HiveSim.level_for(60) == 2, "60 запаса — уровень 2")
	_check(HiveSim.level_for(160) == 3, "160 запаса — уровень 3")
	_check(HiveSim.level_for(100500) == 4, "сверх запаса — уровень 4 (макс)")
	_check(HiveSim.radius_for(1) > 10.0 and HiveSim.radius_for(4) > HiveSim.radius_for(1),
			"радиус поиска растёт с уровнем")
	var r1: Array = HiveSim.roles_for(1)
	var r3: Array = HiveSim.roles_for(3)
	_check(int(r1[0]) < int(r3[0]) and int(r1[1]) < int(r3[1]) and int(r1[2]) <= int(r3[2]),
			"ролей с уровнем больше (стражи/добытчики/скауты)")
	var w1: int = HiveSim.wave_size(1, 0, 0)
	var w4: int = HiveSim.wave_size(4, 300, 6)
	_check(w4 > w1 and w4 <= 14, "волна сильнее с уровнем и успехом (%d → %d)" % [w1, w4])
	_check(HiveSim.wave_days(4) < HiveSim.wave_days(1), "волны ходят чаще с уровнем")


func _test_hive_tracks() -> void:
	print("[Улей: следы героя]")
	var tracks: Array = []
	tracks = HiveSim.push_track(tracks, Vector2(0, 0), 0.0, 128.0)
	tracks = HiveSim.push_track(tracks, Vector2(8, 0), 0.5, 128.0)
	_check(tracks.size() == 1, "слишком близкий след не пишется (шаг по скорости)")
	tracks = HiveSim.push_track(tracks, Vector2(64, 0), 1.0, 128.0)
	_check(tracks.size() == 2, "дистанционный след пишется")
	var near: Vector2 = HiveSim.track_near(tracks, Vector2(60, 0), 100.0, 2.0)
	_check(near == Vector2(64, 0), "скаут находит свежий след в радиусе")
	var gone: Vector2 = HiveSim.track_near(tracks, Vector2(60, 0), 100.0, 999.0)
	_check(gone == Vector2.INF, "протухший след скаут не читает")


func _test_hive_loot() -> void:
	print("[Улей: награда]")
	var l1: Dictionary = HiveSim.loot_for(1)
	var l4: Dictionary = HiveSim.loot_for(4)
	_check(int(l4["coins"]) > int(l1["coins"]) and int(l4["crystal"]) > int(l1["crystal"]),
			"награда за разорение растёт с уровнем")


func _test_hive_sim_integration() -> void:
	print("[Улей: интеграция с симуляцией города]")
	OS.set_environment("PEPEL_HIVE_ON", "1")
	var sim = load("res://scripts/city_sim.gd").new()
	var cfg: Dictionary = _read_json("res://data/city.json")
	var map = load("res://scripts/city_map.gd").new()
	map.generate(4242, cfg, {})
	sim.setup(map, cfg, 8, "normal")
	sim.autonomous = true
	# улей строится на start_day — прогоняем дни
	sim.day = 1
	sim._update_threat(0.1, 120.0)
	_check(sim.hive.is_empty(), "до срока улья нет")
	sim.day = int(HiveSim.START_DAY) + 1
	OS.set_environment("GEN_DEBUG", "")
	sim._update_threat(0.1, 120.0)
	_check(not sim.hive.is_empty() and bool(sim.hive.get("active", false)),
			"ульевое поселение отстроилось у аномалии")
	# роли добираются тиками
	for i in 40:
		sim._update_threat(0.1, 120.0)
	var counts: Array = sim._hive_role_counts()
	_check(int(counts[0]) >= 2 and int(counts[1]) >= 3,
			"стражи и добытчики спавнятся (%s)" % str(counts))
	# сбор: скармливаем улею запас → уровень
	sim.hive["stock"] = 60
	var lvl: int = int(sim.hive["level"])
	sim._update_threat(0.1, 120.0)
	_check(int(sim.hive["level"]) == 2 and lvl == 1, "запас растит уровень улья")
	# разорение: награда и кулдаун отрастания
	var coins0: float = float(sim.res.get("coins", 0.0))
	sim.hive["hp"] = 1.0
	sim._hive_take_damage(10)
	_check(not bool(sim.hive.get("active", true)), "разбитый улей гаснет")
	_check(float(sim.res["coins"]) > coins0, "награда за разорение в общий пул")
	_check(float(sim.hive.get("respawn_day", 0.0)) > 0.0, "аномалия отстроит улей через 10 дней")


func _test_hive_save() -> void:
	print("[Улей: сейв]")
	OS.set_environment("PEPEL_HIVE_ON", "1")
	var sim = load("res://scripts/city_sim.gd").new()
	var cfg: Dictionary = _read_json("res://data/city.json")
	var map = load("res://scripts/city_map.gd").new()
	map.generate(777, cfg, {})
	sim.setup(map, cfg, 8, "normal")
	sim.day = 10
	sim._update_threat(0.1, 120.0)
	sim.hive["stock"] = 25
	var sv: Script = load("res://scripts/save_game.gd")
	var block: Dictionary = sv._city_block(sim)
	_check(block.has("hive") and int(block["hive"].get("stock", -1)) == 25,
			"состояние улья уходит в сейв")
	var map2 = load("res://scripts/city_map.gd").new()
	map2.generate(777, cfg, {})
	var sim2 = load("res://scripts/city_sim.gd").new()
	sim2.setup(map2, cfg, 8, "normal")
	sv._apply_city_sim(sim2, block)
	_check(not sim2.hive.is_empty() and int(sim2.hive.get("stock", -1)) == 25
			and bool(sim2.hive.get("active", false)),
			"ульевое состояние восстанавливается из сейва")


const HiveSim := preload("res://scripts/hive_sim.gd")
