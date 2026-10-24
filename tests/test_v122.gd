# Тесты v1.22: сезонные культуры и зимняя готовность города, легендарные
# странники на карте мира, случайные встречи в пути, оптимизация земли
# (static_dirty → перевыпечка духовки).
extends "res://tests/test_base.gd"


# --- сезонные культуры и зимняя готовность (v1.22) ---------------------------

func _test_v122_seasons() -> void:
	var sim = _make_sim()
	print("[v1.22: сезонные культуры и зима]")
	# 1) дни до зимы: сезоны по 12 дней (весна 1–12, лето 13–24, осень 25–36,
	# зима 37–48); день 34 — до зимы 3 дня, день 30 — 7, зимой — до следующей
	sim.day = 34
	_check(sim.days_to_winter() == 3, "дней до зимы: 34-й день → 3 (есть %d)" % sim.days_to_winter())
	sim.day = 30
	_check(sim.days_to_winter() == 7, "30-й день → 7 дней до зимы")
	sim.day = 37
	_check(sim.season() == "winter", "37-й день — зима")
	_check(sim.days_to_winter() == 48, "зимой счёт до СЛЕДУЮЩЕЙ зимы (48)")
	# 2) окно готовности и «зима близко»
	sim.day = 34
	_check(sim.winter_coming(), "34-й день — зима на пороге (окно 4)")
	sim.day = 30
	_check(not sim.winter_coming(), "30-й день — готовиться рано")
	# 3) сезонность культур: репа всегда, пшеница только в тёплый сезон
	_check(sim.crop_in_season("turnip"), "репа растёт в любой сезон")
	_check(sim.crop_in_season("wheat"), "пшеница растёт летом")
	sim.day = 37
	_check(not sim.crop_in_season("wheat"), "зимой пшеница спит")
	# 4) рост: пшеница зимой не тикает, летом зреет; репа зимует как раньше
	var cells: Array = []
	var here: Vector2i = sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(2, 2))
	for dy in 2:
		for dx in 2:
			cells.append(here + Vector2i(dx, dy))
	var added: int = sim.add_zone("field", cells, "wheat")
	_check(added >= 1, "поле пшеницы размечено (%d клеток из 4)" % added)
	var zone: Dictionary = sim.zones[0]
	for i in (zone["cells"] as Array).size():
		zone["progress"][i] = 99.0   # обустроено
	zone["crops"] = []
	sim.res["seeds"] = 10.0
	var day_len: float = float(sim.cfg["day_length"])
	sim._update_zones(day_len * 0.5, day_len)   # зима: посев не идёт
	var crops: Array = zone.get("crops", [])
	_check(crops.is_empty() or (crops[0] as Dictionary).is_empty(),
			"зимой пшеница не сеется — семена целы")
	sim.day = 13   # лето
	sim._update_zones(day_len * 0.1, day_len)
	crops = zone.get("crops", [])
	var sown := false
	for c in crops:
		if not (c as Dictionary).is_empty():
			sown = true
	_check(sown, "летом пшеница сеется сама")
	# 5) планёрка видит зиму: в окно готовности в плане есть блок winter
	sim.day = 34
	sim.static_dirty = false
	var plan: Dictionary = sim.morning_plan()
	_check(plan.has("winter"), "план старосты знает про зиму")
	_check(int(plan["winter"]["days"]) == 3, "в плане: до зимы 3 дня")
	var has_event := false
	for ev in sim.events:
		if String(ev["type"]) == "winter_soon":
			has_event = true
	_check(has_event, "событие «зима близко» объявлено городу")
	# 6) город понимает еду на нос
	sim.res["food"] = 30.0
	_check(absf(sim.food_per_resident() - 30.0 / maxf(1.0, float(sim.residents.size()))) < 0.001,
			"еда на жителя посчитана")


# --- легендарные странники (v1.22) -------------------------------------------

func _test_v122_legends() -> void:
	print("[v1.22: легендарные странники]")
	var ws_cfg: Dictionary = _read_json("res://data/world.json")
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(21, ws_cfg)
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, ws_cfg, 7)
	_check(wsim.legends.size() == 3, "странников трое (%d)" % wsim.legends.size())
	for l in wsim.legends:
		_check(String(l["state"]) == "rest" and (l["def"] as Dictionary).has("prof"),
				"странник %s ждёт с профессией" % String(l["def"]["id"]))
	# цели: дальние незачищенные боевые точки вне двора города
	var targets: Array = wsim._legend_targets()
	_check(not targets.is_empty(), "дальние цели для странников есть")
	for poi in targets:
		_check(Vector2(poi["tile"]).distance_to(Vector2(wmap.city_tile)) > 6.0,
				"цель вне двора города (гонка за дальними)")
	# зачистка: странник у цели закрывает её за clear_days
	var legend: Dictionary = wsim.legends[0]
	var poi: Dictionary = targets[0]
	legend["state"] = "clear"
	legend["target_poi"] = int(poi["id"])
	legend["days_left"] = 2
	wsim.advance_day()
	wsim.advance_day()
	_check(int(poi["cleared_day"]) >= 0, "странник зачистил данж (cleared_day поставлен)")
	var ev_cleared := false
	for ev in wsim.events:
		if String(ev["type"]) == "legend_cleared":
			ev_cleared = true
	_check(ev_cleared, "о зачистке вышло событие (лут достался страннику)")
	# встреча у ног: legend_near находит, invite уводит в город, rumor раз в визит
	legend["state"] = "visit"
	legend["rumor_used"] = false
	legend["tile"] = wmap.city_tile + Vector2i(1, 0)
	var found: Dictionary = wsim.legend_near(wmap.city_tile)
	_check(int(found["id"]) == int(legend["id"]), "странник найден у ворот города")
	var def: Dictionary = wsim.legend_invite(int(legend["id"]))
	_check(not def.is_empty() and String(legend["state"]) == "gone",
			"приглашённый странник уходит с карты (def на руках)")
	_check(wsim.legend_near(wmap.city_tile).is_empty(), "ушедший странник больше не находится")
	# слухи: раз за визит открывают землю
	var l2: Dictionary = wsim.legends[1]
	l2["state"] = "visit"
	l2["rumor_used"] = false
	l2["tile"] = wmap.city_tile
	var opened: int = wsim.legend_rumor(int(l2["id"]))
	_check(opened >= 0 and bool(l2["rumor_used"]), "слухи странника расходятся (флаг поставлен)")
	_check(wsim.legend_rumor(int(l2["id"])) == 0, "второй раз за визит странник молчит")
	# город принимает легенду сильным жителем
	var sim = _make_sim()
	var before: int = sim.residents.size()
	var r: Dictionary = sim.add_legend_resident("Сивый Плащ", "hunter", 3.0)
	_check(sim.residents.size() == before + 1 and float(r["skill"]) == 3.0,
			"легенда поселилась в городе с высоким навыком")


# --- случайные встречи в пути (v1.22) ----------------------------------------

func _test_v122_encounters() -> void:
	print("[v1.22: встречи в пути]")
	var ws_cfg: Dictionary = _read_json("res://data/world.json")
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(31, ws_cfg)
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, ws_cfg, 9)
	# бросок: с шансом 1 встреча всегда, с 0 — никогда; вид из конфига
	wsim.cfg["encounters"]["chance_per_day"] = 0.0
	_check(wsim.roll_encounter() == "", "шанс 0 — встречи нет")
	wsim.cfg["encounters"]["chance_per_day"] = 1.0
	var kinds: Array = ws_cfg.get("encounters", {}).get("kinds", {}).keys()
	var got: String = wsim.roll_encounter()
	_check(got in kinds, "выпала встреча из конфига (%s)" % got)
	# раненый: еда из пула, репутация торговцев растёт
	wsim.rep = {}
	var pool := {"food": 10.0}
	_check(wsim.encounter_help_wounded(pool), "раненому помогли (−5 еды)")
	_check(absf(float(pool["food"]) - 5.0) < 0.001, "еда списана из пула города")
	_check(wsim.get_rep("traders") > 0.0, "торговцы благодарны (+репутация)")
	pool = {"food": 2.0}
	_check(not wsim.encounter_help_wounded(pool), "без еды помощь не выходит")
	# буря напролом: доля еды теряется
	pool = {"food": 100.0}
	var loss: float = wsim.encounter_storm_loss(pool)
	_check(absf(loss - 10.0) < 0.001 and absf(float(pool["food"]) - 90.0) < 0.001,
			"буря отнимает 10% еды каравана")
	# паломник: монеты за репутацию культа; без монет — отказ
	wsim.rep = {}
	_check(wsim.encounter_pilgrim_donate(10) == 5, "паломник взял 5 монет")
	_check(wsim.get_rep("cult") > 0.0, "культ запомнил пожертвование")
	_check(wsim.encounter_pilgrim_donate(3) == 3, "без монет культ не принимает")
	# схрон и засада: монеты в диапазоне конфига
	for i in 8:
		var coins: int = wsim.encounter_cache_coins()
		_check(coins >= 5 and coins <= 15, "схрон даёт 5–15 монет (%d)" % coins)
		var ambush: int = wsim.encounter_ambush_coins()
		_check(ambush >= 4 and ambush <= 10, "засада награждает 4–10 монет (%d)" % ambush)
		if i > 1:
			break
	_check(wsim.encounter_ambush_scale() > 0.5 and wsim.encounter_ambush_scale() < 1.0,
			"засада слабее полного лагеря (масштаб)")


# --- оптимизация земли: static_dirty (v1.22) ---------------------------------

func _test_v122_static_ground() -> void:
	var sim = _make_sim()
	print("[v1.22: земля в духовке]")
	_check(not sim.static_dirty, "флаг земли чист после создания города")
	var cells: Array = []
	var here: Vector2i = sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(0, 3))
	for dy in 2:
		for dx in 2:
			cells.append(here + Vector2i(dx, dy))
	sim.add_zone("field", cells, "turnip")
	_check(sim.static_dirty, "новая зона пометила землю на перевыпечку")
	sim.static_dirty = false
	sim.place_road(sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(4, 0)))
	_check(sim.static_dirty, "новая дорога пометила землю на перевыпечку")
	sim.static_dirty = false
	var moved := false
	for off in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(3, 3)]:
		if sim.move_plaza(sim.plaza + off) == "":
			moved = sim.static_dirty
			break
	_check(moved, "перенос площади пометил землю на перевыпечку")
	# поп_max поднят до 60 (заказчик): потолок из конфига
	sim.cfg["pop_max"] = 0
	var base_cap: int = sim.pop_cap()
	sim.cfg["pop_max"] = 60
	_check(sim.pop_cap() == mini(60, base_cap), "pop_max=60 конфигурирует потолок населения")
