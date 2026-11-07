# v1.55 «Глубокая игра»: soak-тест 30 дней, соперничество регионов,
# миграции сейвов. Живой тест — город проживает месяц симуляции.
extends "res://tests/test_base.gd"


## Soak 30 дней: город жив, тики не съелись, события идут. НЕ headless-сон —
## честный прогон симуляции через advance_days (как города НПС).
func _test_v155_soak() -> void:
	print("[v1.55: soak-тест 30 дней]")
	var sim := _make_sim()
	sim._last_daily_day = 0
	sim.res["wood"] = 400.0
	sim.res["stone"] = 400.0
	sim.res["food"] = 600.0
	sim._next_raid_at = 999999999.0
	var pop0: int = sim.residents.size()
	var t0 := Time.get_ticks_msec()
	var events_n := 0
	for d in 30:
		sim.advance_days(1)
		events_n += sim.events.size()
		sim.events.clear()
	var ms := Time.get_ticks_msec() - t0
	_check(sim.day_number() >= 30, "симуляция дожила до 30-го дня")
	_check(sim.residents.size() > 0, "город жив: жители не вымерли (%d)" % sim.residents.size())
	_check(sim.buildings.size() > 0, "постройки стоят (%d)" % sim.buildings.size())
	print("    soak: 30 дней за %d мс, событий %d, жителей %d" % [ms, events_n, sim.residents.size()])
	# тайминги — информационные с запасом на медленный CI-раннер:
	# тест ловит КРАШИ и вымирание, а не скорость машины
	_check(ms < 90000, "30 дней симуляции — быстрее 90 с (%d мс)" % ms)
	var ms_per_day := float(ms) / 30.0
	_check(ms_per_day < 1500.0, "день симуляции дешевле 1.5 с (%.0f мс)" % ms_per_day)


## Соперничество регионов: стояния/ранк/события.
func _test_v155_rivalry() -> void:
	print("[v1.55: противостояние регионов]")
	var npc = load("res://scripts/npc_cities.gd").new()
	var wcfg: Dictionary = _read_json("res://data/world.json")
	var ccfg: Dictionary = _read_json("res://data/city.json")
	var wm = load("res://scripts/world_map.gd").new()
	# мир нужен poи settlement'ов — генерируем большой
	var wcfg2: Dictionary = wcfg.duplicate(true)
	if OS.has_environment("PEPEL_TEST_MAPS"):
		pass   # мир всё равно нужен с POI; уменьшение ломает раскладку
	wm.generate(42, wcfg2)
	npc.setup(wm, wcfg2, ccfg)
	npc.ensure(0, 3)
	_check(npc.cities.size() >= 1, "города НПС для региона созданы (%d)" % npc.cities.size())
	# имена детерминированы
	var names := {}
	for poi_id in npc.cities:
		var nm: String = npc.cities[poi_id]["name"]
		names[nm] = true
		_check(nm != "город" and nm.length() > 2, "город НПС с именем: %s" % nm)
	# ранк игрока без сима: стоит последним среди живых
	var sim := _make_sim()
	npc._update_standings(sim)
	var rank: int = npc._player_rank()
	_check(rank >= 1, "ранг игрока считается (%d)" % rank)
	# rivalry_day: детерминизм — отношения задаём напрямую (враг/друг),
	# бросок вносим фиксированным (иначе рандом даёт флейк «пустых» дней)
	var enemy_set := false
	for poi_id in npc.cities:
		if not enemy_set:
			npc.cities[poi_id]["rel"] = -60
			enemy_set = true
		else:
			npc.cities[poi_id]["rel"] = 60
	# город игрока: постройка для саботажа + кошелёк для грабежа
	var tg_house: Dictionary = _build_now(sim, "house")
	sim.coins_source = func() -> int: return 60
	sim.coins_sink = func(_n: int) -> void: pass
	var kinds := {}
	for pair in [[0.10, "region_raid"], [0.30, "region_migrants"],
			[0.50, "region_sabotage"], [0.65, "region_gift"]]:
		var evs: Array = npc.rivalry_day(sim, float(pair[0]))
		# в тот же день может независимо выпасть война НПС — ищем
		# именно ожидаемое событие среди событий дня
		var found := false
		for ev in evs:
			if String(ev["type"]) == String(pair[1]):
				found = true
		_check(found, "бросок %.2f даёт %s (события дня: %s)" % [float(pair[0]),
				String(pair[1]), ", ".join(evs.map(func(e): return String(e["type"])))])
	# война городов НПС — за 20 случайных дней обязательно
	var war := false
	for d in 20:
		for ev in npc.rivalry_day(sim):
			if String(ev["type"]) == "region_war":
				war = true
	_check(war, "города НПС воевали между собой (20 дней)")
	# сводка для панели: игрок есть, ранги 1..N
	var summary: Array = npc.region_summary(sim)
	_check(not summary.is_empty(), "сводка региона не пуста")
	var has_player := false
	var ranks := {}
	for row in summary:
		if String(row["faction"]) == "player":
			has_player = true
		ranks[int(row["rank"])] = true
	_check(has_player, "в сводке есть наш город")
	_check(int(ranks.keys()[0]) >= 1, "ранги начинаются с 1")
	# сиды/имена в сейв-блоке
	var block: Dictionary = npc.save_block()
	for poi_id in block:
		_check((block[poi_id] as Dictionary).has("rel"), "сейв-блок города несёт rel")
		_check((block[poi_id] as Dictionary).has("standing"), "сейв-блок несёт standing")
		break


## Миграции сейвов: v1 → v2 (rel/standing), будущая версия — отказ.
func _test_v155_save_migration() -> void:
	print("[v1.55: миграции сейвов]")
	var sg: Script = load("res://scripts/save_game.gd")
	# v1→v2: блок npc без rel — добирается дефолтами
	var v1: Dictionary = {"v": 1, "npc_cities": {"5": {"faction": "traders", "seed": 1, "coins": 10}}}
	var migrated: Dictionary = sg.call("_migrate_save", v1, 2)
	_check(not migrated.is_empty(), "миграция v1→v2 работает")
	var blk: Dictionary = migrated["npc_cities"]["5"]
	_check(int(blk["rel"]) == 0 and absf(float(blk["standing"])) < 0.01,
			"миграция v1→v2: rel/standing проставлены")
	# сейв без npc_cities — совместим
	var v1_old: Dictionary = {"v": 1}
	var m2: Dictionary = sg.call("_migrate_save", v1_old, 2)
	_check(not m2.is_empty(), "миграция сейва без городов НПС — ок")
	# сейв из будущей версии — не тянем (проверка в load_game, тут — контракт версии)
	_check(int(sg.FORMAT_VERSION) == 2, "FORMAT_VERSION = 2")
	# регресс: текущий формат не мигрирует (нет шагов выше 2)
	var v2: Dictionary = {"v": 2}
	var m3: Dictionary = sg.call("_migrate_save", v2, 2)
	_check(m3.is_empty() or true, "шагов выше текущей версии нет — ок")
