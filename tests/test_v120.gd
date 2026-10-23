# Правки v1.19.1-v1.20.1: жители, поля, площадь, планёрка, рост, саженцы.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_fixes_v1191() -> void:
	print("[Правки v1.19.1: жители, данж-волны, поля героя, зоны]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	var dungeon_cfg: Variant = _read_json("res://data/dungeon.json")
	_check(city is Dictionary and loc is Dictionary and dungeon_cfg is Dictionary,
			"конфиги читаются")
	if not (city is Dictionary and loc is Dictionary and dungeon_cfg is Dictionary):
		return
	var day_len: float = float(city["day_length"])

	# --- 1. соло-старт: город строит и растёт, беженцы приходят ---------------
	var solo_map = load("res://scripts/city_map.gd").new()
	solo_map.generate(7, city)
	var solo = load("res://scripts/city_sim.gd").new()
	seed(11)   # глобальный RNG ДО setup: погода/досуг тянут randf()
	solo.setup(solo_map, city, 1, "normal")
	# setup() внутри делает _event_rng.randomize() и бросает черты характера
	# основателя (±15% скорости стройки) ДО нашей установки seed — обнуляем
	# черты сразу после setup: единственный оставшийся источник недетерминизма
	for r in solo.residents:
		r["traits"] = []
	solo._event_rng.seed = 11
	solo._next_raid_at = 999999999.0   # волны отдельно: здесь — рост города
	# болезни глушим (гигиена теста): больной староста в соло может умереть —
	# это честная игра, но не предмет этой проверки
	solo.people["ailments"]["sick_chance"] = 0.0
	solo.people["ailments"]["wounded_on_surge"] = 0
	var step := day_len / 4.0
	for i in 25 * 4:
		solo.tick(step)
	_check(solo.pop_cap() > 1, "соло-старт: староста достроил дома, кап %d" % solo.pop_cap())
	_check(solo.residents.size() > 1,
			"соло-старт: к 25-му дню пришли поселенцы (жителей %d)" % solo.residents.size())
	var housed := 0
	for r in solo.residents:
		if not solo._homeless(r):
			housed += 1
	# временная диагностика соло-экономики v1.21 (убрать после стабилизации)
	var dbg_types := PackedStringArray()
	for b in solo.buildings:
		dbg_types.append(String(b["type"]) + ("" if bool(b["done"]) else "+"))
	print("DBG solo: [", ", ".join(dbg_types), "] wood=", int(solo.res["wood"]),
			" food=", int(solo.res["food"]), " stone=", int(solo.res["stone"]),
			" anger=", solo.forest_anger, " zones=", solo.zones.size())
	for r in solo.residents:
		var hm: Variant = r.get("home", null)
		print("DBG res: ", String(r["name"]), " prof=", String(r["prof"]),
				" state=", String(r["state"]), " home=", "yes" if hm is Dictionary and not (hm as Dictionary).is_empty() else "none",
				" bld=", String(r["bld"]["type"]) if r["bld"] != null else "-",
				" site=", String(r["site"]["type"]) if r["site"] != null else "-",
				" inside=", int(r.get("inside", 0)))
	_check(housed > 0, "жители заселяют дома (с homeless %d чел.)" % housed)

	# --- 2. расписание волн: раз в 10 дней, зачистка данжа сдвигает на 20 -----
	var sim := _make_sim()
	sim.time = 0.0
	sim._raid_not_before = 0.0
	sim._next_raid_at = 0.0
	sim._schedule_next_raid()
	_check(absf(sim._raid_gap_days - float(city["threat"]["raid_every_days"])) < 0.01,
			"интервал волн из конфига — 10 дней")
	_check(absf(sim._next_raid_at / day_len - 10.0) < 0.01, "первая волна — на 10-й день")
	sim.delay_raids_after_dungeon_clear()
	_check(absf((sim._raid_not_before - sim.time) / day_len
			- float(city["threat"]["clear_raid_delay_days"])) < 0.01,
			"зачистка данжа у города сдвигает волны на 20 дней")
	_check(sim._next_raid_at >= sim._raid_not_before, "следующая волна не раньше перезарядки")
	var calm_seen := false
	for ev in sim.events:
		if String(ev["type"]) == "dungeon_calm":
			calm_seen = true
	_check(calm_seen, "событие «данж затих» дошло до сцены")
	# отбили волну — новая тоже уважает сдвиг
	sim._raid_kind = "mutant"
	sim._spawn_raid(2, false)
	sim.raiders.clear()
	sim._raid_end(true)
	_check(sim._next_raid_at >= sim._raid_not_before,
			"после отбитой волны новая не раньше перезарядки данжа")

	# --- 3. волны ослаблены: размер не растёт с номером, потолок 6 -----------
	var sim2 := _make_sim()
	sim2._next_raid_at = 999999999.0
	sim2._last_daily_day = 999
	sim2.time = 30.0 * day_len
	sim2.day = 31
	sim2.raid_count = 0
	sim2._spawn_raid(20, false)
	_check(sim2.raiders.size() <= int(city["threat"]["raid_size_max"]),
			"волна не больше потолка %d (пришло %d)" % [int(city["threat"]["raid_size_max"]),
					sim2.raiders.size()])
	var wave1_size: int = sim2.raiders.size()
	sim2.raiders.clear()
	sim2.raid_active = false
	sim2.raid_count = 5   # шестая волна
	sim2._spawn_raid(20, false)
	_check(sim2.raiders.size() <= maxi(wave1_size, int(city["threat"]["raid_size_max"])),
			"размер волны не растёт с номером (волна 6: %d)" % sim2.raiders.size())
	var brute_base := 0
	var brute_now := 0
	var enemies: Array = _read_json("res://data/enemies.json")
	for e in enemies:
		if String(e["id"]) == "brute":
			brute_base = int(e["hp"])
	for r in sim2.raiders:
		if String(r["type"]) == "brute":
			brute_now = maxi(brute_now, int(r["hp"]))
	var hp_cap: float = (1.0 + float(city["threat"]["hp_per_threat"]) * sim2.threat_value()
			+ 5.0 * float(city["threat"]["wave_growth_hp"])) * float(brute_base)
	_check(brute_now == 0 or float(brute_now) <= hp_cap + 0.5,
			"здоровье мутантов ослаблено (бутан hp %d <= %.0f)" % [brute_now, hp_cap])

	# --- 4. данж: перезарядка 20 дней, светлеет по мере убийств --------------
	_check(int((dungeon_cfg as Dictionary).get("clear_growth", {}).get("lock_days", 0)) == 20,
			"данж перезаряжается 20 дней")
	var light_cfg: Dictionary = (dungeon_cfg as Dictionary).get("clear_light", {})
	_check(not light_cfg.is_empty(), "конфиг подсветки данжа есть")
	var DS: Script = load("res://scripts/dungeon.gd")
	var base_dark := Color("#090910")
	var l0: Color = DS.bright_ambient(base_dark, 0.0, light_cfg)
	var l_half: Color = DS.bright_ambient(base_dark, 0.5, light_cfg)
	var l_full: Color = DS.bright_ambient(base_dark, 1.0, light_cfg)
	_check(l0 == base_dark, "в начале данж тёмный, как в биоме")
	_check(l_half.v > l0.v and l_full.v > l_half.v,
			"с каждым убитым монстром данж светлеет")

	# --- 5. герой сам пашет, сеет и собирает поле -----------------------------
	var sim3 := _make_sim()
	sim3._last_daily_day = 999
	var cells: Array = []
	var base: Vector2i = sim3.map.spawn_tile + Vector2i(3, 3)
	for dy in 2:
		for dx in 2:
			cells.append(base + Vector2i(dx, dy))
	_check(sim3.add_zone("field", cells, "turnip") == 4, "поле 2×2 создано")
	var z: Dictionary = sim3.zones[0]
	var px: Vector2 = sim3.map.tile_center_px(base)
	_check(not sim3.hero_till_near(px).is_empty(), "герой видит невспаханную клетку поля")
	_check(sim3.hero_till(px) == "tilled", "один E вспахивает клетку целиком (fill_per_hit)")
	_check(float(z["progress"][0]) >= 4.0, "клетка обустроена (fill_work)")
	# остальные клетки поля считают обустроенными (жители/герой уже прошли их)
	z["progress"] = [9.0, 9.0, 9.0, 9.0]
	sim3.res["seeds"] = 5.0
	_check(sim3.hero_sow_near(px).is_empty() == false, "герой видит пустую клетку под посев")
	_check(sim3.hero_sow(px) == "sow", "E сеет клетку за семя")
	var cell0: Dictionary = (z["crops"] as Array)[0]
	_check(not cell0.is_empty() and int(cell0["stage"]) == 0, "росток посажен")
	_check(float(sim3.res["seeds"]) < 5.0, "семя потрачено из пула")
	# созревание и сбор
	var crops_arr: Array = z["crops"]
	while crops_arr.size() < 4:
		crops_arr.append({})
	crops_arr[1] = {"stage": 9, "t": 0.0, "ripe": true}
	var food0: float = float(sim3.res["food"])
	var px1: Vector2 = sim3.map.tile_center_px(base + Vector2i(1, 0))
	_check(sim3.hero_harvest(px1) == "food", "E собирает спелую грядку")
	_check(float(sim3.res["food"]) > food0, "еда за спелую клетку в пуле")
	# без семян посев честно отказывает
	sim3.res["seeds"] = 0.0
	while (z["crops"] as Array).size() < 3:
		(z["crops"] as Array).append({})
	(z["crops"] as Array)[2] = {}
	_check(sim3.hero_sow(sim3.map.tile_center_px(base + Vector2i(0, 1))) == "no_seeds",
			"без семян герой не сеет (тост объясняет)")

	# --- 6. зоны: цвета Поле/Пастбище различимы, подписи при наведении --------
	var ztypes: Dictionary = (city as Dictionary).get("zones", {}).get("types", {})
	_check(Color(String(ztypes["field"]["color"])) != Color(String(ztypes["pasture"]["color"])),
			"поле и пастбище разных цветов")
	_check(Color(String(ztypes["field"]["color"])) != Color(String(city["colors"]["grass"])),
			"поле отличается от травы")
	_check(Color(String(ztypes["pasture"]["color"])) != Color(String(city["colors"]["grass"])),
			"пастбище отличается от травы")
	_check(not sim3.zone_at(base).is_empty(), "zone_at находит зону по тайлу")
	_check(sim3.zone_at(sim3.map.spawn_tile).is_empty(), "zone_at не врёт вне зоны")
	var st: Dictionary = sim3.field_stats(z)
	_check(int(st["total"]) == 4 and int(st["filled"]) >= 2, "статистика поля для подписи считается")
	for key in ["city.hint_sow", "city.hero_sow_done", "city.hero_sow_no_seeds",
			"city.hint_till", "city.hero_till_done", "city.hover_field",
			"city.hover_field_ripe", "city.hover_pasture", "city.hover_zone_progress",
			"city.dungeon_calm_toast"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	# староста-строитель: без строителей староста замещает стройку
	var sim4 := _make_sim()
	sim4._last_daily_day = 999
	for r in sim4.residents.duplicate():
		if String(r["prof"]) != "elder":
			sim4.residents.erase(r)
	var tile_b: Vector2i = _find_free_tile(sim4, sim4.map.spawn_tile)
	_check(sim4.place_building("house", tile_b), "стройплощадка поставлена")
	var site: Dictionary = {}
	for b in sim4.buildings:
		if not bool(b["done"]):
			site = b
	_check(not site.is_empty(), "стройка нашлась")
	sim4._assign_jobs()
	var elder: Dictionary = {}
	for r in sim4.residents:
		if String(r["prof"]) == "elder":
			elder = r
	_check(elder["site"] == site, "староста в одиночном городе берёт стройку сам")

	# --- 7. правки v1.19.2: староста работает, кучу можно унести, ферма живёт -
	# староста обустраивает зоны сам (соло: «ставлю поле — ничего нет»)
	var sim5 := _make_sim()
	sim5._last_daily_day = 999
	sim5._next_raid_at = 999999999.0
	for r in sim5.residents.duplicate():
		if String(r["prof"]) != "elder":
			sim5.residents.erase(r)
	var cells5: Array = []
	var base5: Vector2i = sim5.map.spawn_tile + Vector2i(3, 3)
	for dy in 2:
		for dx in 2:
			cells5.append(base5 + Vector2i(dx, dy))
	_check(sim5.add_zone("field", cells5, "turnip") == 4, "поле для старосты создано")
	var prog0 := float((sim5.zones[0]["progress"] as Array)[0])
	for i in 4 * 8:   # ~2 дня: дойти и вспахать
		sim5.tick(30.0)
	var prog1 := float((sim5.zones[0]["progress"] as Array)[0])
	_check(prog1 > prog0, "староста сам обустраивает клетки поля (%.1f → %.1f)" % [prog0, prog1])
	# староста замещает фермера: ферма без работника не стоит в соло
	# (v1.20: голем устал на поле — перед стройкой дадим ему «отдохнуть»)
	var elder5pre: Dictionary = {}
	for r in sim5.residents:
		if String(r["prof"]) == "elder":
			elder5pre = r
	elder5pre["fatigue"] = 0.0
	var ftile := _find_free_tile(sim5, sim5.map.spawn_tile)
	_check(ftile != Vector2i(-1, -1), "место под ферму найдено")
	_check(sim5.place_building("farm", ftile), "ферма заложена")
	var farm5: Dictionary = sim5.building_at(ftile)
	sim5._complete_site(farm5)
	sim5.tick(0.1)   # работник освобождается от готовой стройки на следующем тике
	_check(bool(farm5["done"]), "ферма достроена")
	sim5._assign_jobs()
	var farm_worker: int = int(farm5["worker"])
	var elder5: Dictionary = {}
	for r in sim5.residents:
		if String(r["prof"]) == "elder":
			elder5 = r
	_check(farm_worker == int(elder5["id"]), "староста замещает фермера в соло-городе")
	# герой уносит кучу со здания в пул по E
	var food5 := float(sim5.res["food"])
	farm5["pile"] = {"food": 12.0}
	var fpx: Vector2 = sim5.map.tile_center_px(Vector2i(farm5["tile"]))
	_check(not sim5.hero_haul_near(fpx).is_empty(), "герой видит кучу у фермы")
	_check(sim5.hero_haul(fpx) == "haul", "E уносит кучу фермы на склад")
	_check(float(sim5.res["food"]) >= food5 + 12.0 - 0.01, "еда из кучи в общем пуле")
	_check(not farm5.has("pile"), "куча опустела")
	var haul_ev := false
	for ev in sim5.events:
		if String(ev["type"]) == "hero_haul":
			haul_ev = true
	_check(haul_ev, "событие «куча доставлена» дошло до сцены")
	for key in ["city.hint_haul", "city.hero_haul_done"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[Правки v1.19.1] готово")


## Правки приёмки v1.20 (второй чат правок, 2026-10-22): жители-кружки
## с цветом специальности, жильё «один дом — один человек» (+пара и дети),
## голем-староста с главной площадью 2×2, утренняя планёрка с цветовым
## распределением и дефицитами, мысли жителей в журнале, анти-застревание.
func _test_fixes_v120() -> void:
	print("[Правки v1.20: кружки, жильё, площадь, планёрка]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	_check(city is Dictionary and loc is Dictionary, "конфиги читаются")
	if not (city is Dictionary and loc is Dictionary):
		return
	var wcolors: Dictionary = city.get("work_colors", {})
	_check(float(wcolors.get("extra_mult", 0.0)) < 1.0 and float(wcolors.get("off_mult", 0.0)) < 1.0,
			"цветовая система: доп. и чужой цвет хуже основного")
	_check(float(wcolors.get("dilution_per_color", 0.0)) > 0.0,
			"баланс: каждый лишний цвет размывает мастера")
	var profs: Dictionary = {}
	for p in city.get("professions", []):
		profs[String(p["id"])] = p
	_check(String(profs.get("elder", {}).get("color", "")) == "#ffffff",
			"староста-голем — белый кружок")
	var colors_set := {}
	for pid in profs:
		colors_set[String(profs[pid]["color"])] = true
	_check(colors_set.size() >= 10, "цветов специальностей много — кружки различимы")

	# --- цветовая эффективность: dilution за каждый лишний цвет ---
	var sim := _make_sim()
	var r_x: Dictionary = {"prof": "builder", "prof_extra": ["farmer", "miner", "smith"],
			"mood": 50.0, "skill": 0.0, "friend": -1, "work_bonus": 0.0, "traits": [],
			"bld": null, "site": null}
	var m1: float = sim.color_work_mult(r_x, "farmer")
	var many: float = sim.color_work_mult(r_x, "smith")
	_check(is_equal_approx(m1, float(wcolors["extra_mult"]) * (1.0 - 2.0 * float(wcolors["dilution_per_color"]))),
			"третий цвет работает хуже второго (dilution)")
	_check(many >= float(wcolors.get("extra_floor", 0.4)) - 0.001,
			"дно эффективности дополнительных цветов — extra_floor")
	var golem_r: Dictionary = {"prof": "elder", "golem": true, "prof_extra": [], "mood": 50.0,
			"skill": 0.0, "friend": -1, "work_bonus": 0.0, "traits": [], "bld": null, "site": null}
	_check(is_equal_approx(sim.color_work_mult(golem_r, "farmer"), float(wcolors.get("golem_mult", 0.75))),
			"голем работает без цветового бонуса (golem_mult)")

	# --- кружок жителя: цвет из профессии, голем — белый ---
	var villager: Dictionary = sim.residents[0]
	_check(sim.resident_color(villager) != Color.WHITE, "жителю — цвет его специальности")
	var golem_v: Dictionary = {}
	for r in sim.residents:
		if String(r["prof"]) == "elder":
			golem_v = r
	_check(not golem_v.is_empty() and sim.resident_color(golem_v) == Color.WHITE,
			"голему — белый кружок")
	_check(String(golem_v["name"]) == "Голем" and bool(golem_v.get("golem", false)),
			"голем-староста пришёл с именем Голем")

	# --- жильё: один дом — один человек; пара — один дом + дети ---
	var sim_h := _make_sim()
	sim_h._last_daily_day = 999
	var h1: Dictionary = _build_now(sim_h, "house")
	var h2: Dictionary = _build_now(sim_h, "house")
	var a: Dictionary = sim_h.residents[0]
	var b: Dictionary = sim_h.residents[1]
	a["home"] = h1
	b["home"] = h1   # двое чужих взрослых в одном доме — один должен выехать
	sim_h._sleep(a, 0.1)
	sim_h._sleep(b, 0.1)
	var a_home: Dictionary = a["home"]
	var b_home: Dictionary = b["home"]
	_check(not _homeless_t(a) and not _homeless_t(b), "оба жильца при домах (домов хватает)")
	_check(int(a_home["id"]) != int(b_home["id"]),
			"чужие взрослые не живут в одном доме (1 дом = 1 человек)")
	# пара: b выписывается из своего дома, оба живут в одном
	a["partner"] = int(b["id"])
	b["partner"] = int(a["id"])
	a["home"] = h1
	b["home"] = h2
	sim_h._wedding_unify_home(a, b)
	_check(int((a["home"] as Dictionary)["id"]) == int((b["home"] as Dictionary)["id"]),
			"пара живёт в одном доме")
	var freed_home_ev := false
	for e in sim_h.chronicle:
		if String(e["key"]) == "chron.wedding_home":
			freed_home_ev = true
	_check(freed_home_ev, "«выписался из дома» записан в летопись")
	# ребёнок живёт с родителями
	var kid: Dictionary = sim_h._new_resident("Малыш", "", sim_h.map.spawn_tile)
	kid["parents"] = [int(a["id"]), int(b["id"])]
	kid["home"] = null
	sim_h.residents.append(kid)
	sim_h._sleep(kid, 0.1)
	var kid_home: Dictionary = kid["home"]
	_check(not _homeless_t(kid) and int(kid_home["id"]) == int((a["home"] as Dictionary)["id"]),
			"ребёнок живёт в доме родителей")

	# --- утренний план: профильные цвета, конфликт компетентности,
	#     дефицит жизненно важного, один житель — одно назначение ---
	var sim_p := _make_sim()
	sim_p._last_daily_day = 999
	sim_p.res["wood"] = 500.0
	sim_p.res["stone"] = 500.0
	var farm_p: Dictionary = _build_now(sim_p, "farm")
	var farm2_p: Dictionary = _build_now(sim_p, "farm", sim_p.map.spawn_tile + Vector2i(14, 8))
	var plan: Dictionary = sim_p.morning_plan()
	_check(int(plan["day"]) == sim_p.day, "план знает свой день")
	_check((plan["profile"] as Array).size() > 0, "профильные назначения по цветам есть")
	_check(int(farm_p["worker"]) > 0 and int(farm2_p["worker"]) > 0,
			"фермы получили работников по плану")
	var assigned_n := 0
	var names := {}
	var names_ok := true
	for r in sim_p.residents:
		if r["bld"] != null or r["site"] != null:
			assigned_n += 1
			if names.has(String(r["name"])):
				names_ok = false
			names[String(r["name"])] = true
	_check(names_ok, "один житель — одно назначение (без дублей)")
	var covered := 0
	for bld_p in sim_p.buildings:
		if int(bld_p["worker"]) > 0:
			covered += 1
	_check(covered == assigned_n, "у каждого занятого места — ровно один работник")
	_check((sim_p.day_plans as Array).size() >= 1, "план сохранён в журнале дня")
	# конфликт за место: два фермера, одна ферма — берёт компетентнее (skill),
	# тай-брейк — меньший id; проигравший не теряется — идёт дальше по шагам
	var sim_c := _make_sim()
	sim_c._last_daily_day = 999
	var f1c: Dictionary = _build_now(sim_c, "farm")
	var farmer_a: Dictionary = _resident_by_prof(sim_c, "farmer")
	var farmer_b: Dictionary = _add_resident(sim_c, "Ферра", "farmer")
	farmer_a["skill"] = 3.0
	farmer_b["skill"] = 1.0
	var plan_c: Dictionary = sim_c.morning_plan()
	_check(int(f1c["worker"]) == int(farmer_a["id"]),
			"конфликт за ферму: победил более компетентный")
	var conflict_ok := false
	for c in plan_c["conflicts"]:
		if String(c["bld"]) == "farm" and String(c["chosen"]) == String(farmer_a["name"]):
			conflict_ok = true
	_check(conflict_ok, "причина выбора при конфликте отмечена в плане")
	# вторая ферма — проигравший фермер не потерян
	var f2c: Dictionary = _build_now(sim_c, "farm", sim_c.map.spawn_tile + Vector2i(14, 8))
	sim_c.morning_plan()
	_check(int(f2c["worker"]) == int(farmer_b["id"]), "проигравший конфликт занял вторую ферму")
	# дефицит: жизненно важное без людей — план обязан это показать
	var sim_d2 := _make_sim()
	sim_d2._last_daily_day = 999
	for r in sim_d2.residents.duplicate():
		if not (String(r["prof"]) in ["elder"]):
			sim_d2.residents.erase(r)
	# фермы ставим и достраиваем вручную: строитель в городе — только голем
	for btype in ["farm", "sawmill"]:
		var bt: Vector2i = _find_free_tile(sim_d2, sim_d2.map.spawn_tile, btype)
		_check(bt != Vector2i(-1, -1), "место для «%s» найдено" % btype)
		_check(sim_d2.place_building(btype, bt), "«%s» заложена" % btype)
		var bsite: Dictionary = sim_d2.building_at(bt)
		bsite["done"] = true
		sim_d2._complete_site(bsite)
	var plan_d: Dictionary = sim_d2.morning_plan()
	var deficit_seen := (plan_d["deficits"] as Array).size() > 0 \
			or int((plan_d["vital"] as Array).size()) > 0
	_check(deficit_seen, "незакрытое жизненно важное видно в плане (дефицит/голем)")
	var workers_d := 0
	for r in sim_d2.residents:
		if r["bld"] != null or r["site"] != null:
			workers_d += 1
	_check(workers_d >= 1, "голем-староста закрыл жизненно важное в одиночном городе")

	# --- планёрка: жители идут к площади утром ---
	var sim_m := _make_sim()
	sim_m._last_daily_day = 0
	sim_m._next_raid_at = 999999999.0
	sim_m.people["refugees"]["chance_per_day"] = 0.0
	sim_m.people["ailments"]["sick_chance"] = 0.0
	sim_m.tick(float(sim_m.cfg["day_length"]) + 0.1)   # граница дня = утро
	var meeting_n := 0
	for r in sim_m.residents:
		if float(r.get("meeting_until", 0.0)) > sim_m.time:
			meeting_n += 1
	_check(meeting_n > 0, "утро: жители получили зов на планёрку")
	var plaza_center: Vector2i = sim_m.plaza + Vector2i(1, 1)
	var at_plaza := 0
	for i in 20:   # планёрка короткая (7 сек) — ловим момент сбора в окне
		sim_m.tick(0.5)
		at_plaza = 0
		for r in sim_m.residents:
			if (r["pos"] as Vector2).distance_to(sim_m.map.tile_center_px(plaza_center)) < float(sim_m.map.ts) * 3.5:
				at_plaza += 1
		if at_plaza > 0:
			break
	_check(at_plaza > 0, "жители собрались у главной площади на планёрку")

	# --- мысли жителей: строка для тултипа и журнал наведения ---
	var think: String = sim.resident_thought(golem_v)
	_check(think != "", "мысль жителя формируется («о чём думает»)")
	sim.log_thought(golem_v)
	sim.log_thought(golem_v)
	var logged := 0
	for t in sim.thought_log:
		if String(t.get("text", "")).contains("Голем"):
			logged += 1
	_check(logged == 1, "наведение пишет мысль в журнал один раз (без спама)")

	# --- анти-застревание: замерший работник получает пинок ---
	var sim_st2 := _make_sim()
	sim_st2._last_daily_day = 999
	var stuck: Dictionary = sim_st2.residents[0]
	stuck["state"] = "going"
	stuck["pos"] = sim_st2.map.tile_center_px(sim_st2.map.spawn_tile + Vector2i(5, 5))
	stuck["_watch_pos"] = stuck["pos"]
	stuck["_watch_state"] = "going"
	sim_st2._watchdog_stuck()
	_check(String(stuck.get("state", "going")) != "going",
			"застрявший в пути житель растормошен (путь сброшен)")
	print("[Правки v1.20] готово")


func _test_fixes_v1201() -> void:
	print("[Правки v1.20.1: рост поля, снос куч, саженцы, липкие цели]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	_check(float(city["farming"]["crops"]["turnip"]["stage_days"]) >= 0.3,
			"культура растёт днями (stage_days в конфиге)")
	for key in ["res.saplings", "chron.sapling_planted", "city.hauled_toast"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)

	# --- рост поля: стадия не прыгает за секунды ---
	var sim := _make_sim()
	sim._last_daily_day = 999
	sim.cfg["food_per_resident_day"] = 0.0
	var cells: Array = _grass_tiles(sim, sim.map.spawn_tile + Vector2i(8, 8), 4)
	_check(sim.add_zone("field", cells) == 4, "поле разбито")
	var z: Dictionary = sim.zones[0]
	for i in 4:
		z["progress"][i] = 99.0   # вспахано
	sim.tick(2.0)   # пара секунд — только засеять
	var c0: Dictionary = (z["crops"] as Array)[0]
	_check(not c0.is_empty() and int(c0["stage"]) == 0 and not bool(c0["ripe"]),
			"после посева стадия 0 — рост не мгновенный (v1.20.1)")
	var stage_days: float = float(sim.crop_def("turnip")["stage_days"])
	var day_len: float = float(sim.cfg["day_length"])
	var food_a: float = float(sim.res["food"])
	var ripe_or_harvested := false
	for i in 6:   # стадия растёт раз в тик — дробим полный цикл репы в днях
		sim.tick(day_len * stage_days)
		var cc: Dictionary = (z["crops"] as Array)[0]
		if bool(cc.get("ripe", false)) or float(sim.res["food"]) > food_a:
			ripe_or_harvested = true
			break
	_check(ripe_or_harvested, "через полный цикл (дни) репа созрела")

	# --- вечерний снос: работник уносит кучу своего здания ---
	var sim_e := _make_sim()
	sim_e._last_daily_day = 999
	sim_e.cfg["food_per_resident_day"] = 0.0
	var farmer_e: Dictionary = _resident_by_prof(sim_e, "farmer")
	farmer_e["traits"] = []
	farmer_e["mood"] = 100.0
	var farm_e: Dictionary = _build_now(sim_e, "farm", sim_e.map.spawn_tile + Vector2i(14, 8))
	farm_e["pile"] = {"food": 9.0}
	farmer_e["bld"] = farm_e
	farm_e["worker"] = int(farmer_e["id"])
	_teleport(sim_e, farmer_e, farm_e["tile"])
	var food0: float = float(sim_e.res["food"])
	sim_e.time = day_len * 0.75   # вечер
	for i in 300:
		sim_e._evening_haul(farmer_e, 0.5)
		if int(farmer_e.get("hauled_day", 0)) == sim_e.day:
			break
	_check(int(farmer_e.get("hauled_day", 0)) == sim_e.day, "вечером работник снёс кучу")
	_check(float(sim_e.res["food"]) >= food0 + 9.0 - 0.01, "продукция из кучи — в общем пуле")
	_check(float(sim_e._pile_total(farm_e)) < 0.5, "куча у здания пуста")
	var hauled_ev := false
	for e in sim_e.events:
		if String(e["type"]) == "hauled":
			hauled_ev = true
	_check(hauled_ev, "снос пришёл событием (тост)")
	_check(not sim_e._evening_haul(farmer_e, 0.1), "за вечер одна ходка — дальше отдых")

	# --- саженцы: падают из срубленных деревьев ---
	var sim_s := _make_sim()
	sim_s._last_daily_day = 999
	sim_s.cfg["forest"]["sapling_drop_chance"] = 1.0
	var tree_t := Vector2i(-1, -1)
	for radius in range(1, 25):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t: Vector2i = sim_s.map.spawn_tile + Vector2i(dx, dy)
				if sim_s.map.in_bounds(t) and sim_s.map.grid[t.y][t.x] == sim_s.map.TILE_TREE:
					tree_t = t
					break
			if tree_t != Vector2i(-1, -1):
				break
		if tree_t != Vector2i(-1, -1):
			break
	_check(tree_t != Vector2i(-1, -1), "у города есть дерево")
	var hits_need: int = sim_s._hero_chop_hits(sim_s.map.tree_kind(tree_t))
	var fell := ""
	for i in hits_need:
		fell = sim_s.hero_chop(sim_s.map.tile_center_px(tree_t))
	_check(fell == "fell", "герой повалил дерево")
	_check(float(sim_s.res.get("saplings", 0.0)) >= 1.0, "из дерева выпали саженцы (шанс 100%)")
	_check(float(sim_s.res.get("saplings", 0.0)) <= 2.0, "не больше двух саженцев с дерева")

	# --- лесоруб сажает саженцы у лесопилки (v1.21: посадка лес не злит) ---
	var sim_p := _make_sim()
	sim_p._last_daily_day = 999
	sim_p.cfg["food_per_resident_day"] = 0.0
	sim_p.res["saplings"] = 5.0
	sim_p.forest_anger = 0.0
	var saw_p: Dictionary = _build_now(sim_p, "sawmill")
	_check(not saw_p.is_empty(), "лесопилка построена")
	var lumber_p: Dictionary = {}
	for r in sim_p.residents:
		if r["bld"] == saw_p:
			lumber_p = r
	_check(not lumber_p.is_empty() and String(lumber_p["prof"]) == "lumberjack",
			"за лесопилкой закреплён лесоруб")
	lumber_p["traits"] = []
	lumber_p["mood"] = 100.0
	_teleport(sim_p, lumber_p, saw_p["tile"])
	sim_p.time = 10.0   # утро дня
	for i in 240:   # дойти до саженца и посадить (до 2 в день)
		sim_p.tick(0.5)
		if (sim_p.map.saplings as Dictionary).size() >= 1 \
				and int(lumber_p.get("plant_n", 0)) >= 1:
			break
	_check((sim_p.map.saplings as Dictionary).size() >= 1, "лесоруб посадил саженец у лесопилки")
	_check(float(sim_p.res.get("saplings", 0.0)) < 5.0, "саженец списан из пула")
	_check(sim_p.forest_anger == 0.0, "посадка леса не гневит лес (v1.21)")
	# выросшее посаженное дерево успокаивает лес (v1.21); рубку исключаем,
	# чтобы гнев меняли только рост и успокоение
	saw_p["worker"] = -1
	lumber_p["bld"] = null
	sim_p.forest_anger = 5.0
	var day_len_p: float = float(sim_p.cfg["day_length"])
	sim_p.tick(day_len_p * 5.5)   # 5 дней роста саженца
	var grown := false
	for e in sim_p.events:
		if String(e["type"]) == "tree_grown":
			grown = true
	_check(grown, "посаженное дерево выросло")
	_check(sim_p.forest_anger < 3.0, "выросшее дерево гасит гнев леса")

	# --- липкие цели: начатую клетку не меняют на «поближе» ---
	var sim_t := _make_sim()
	sim_t._last_daily_day = 999
	var res_t: Dictionary = sim_t.residents[0]
	var far_cells: Array = _grass_tiles(sim_t, sim_t.map.spawn_tile + Vector2i(9, 9), 1)
	_check(sim_t.add_zone("pasture", far_cells) == 1, "зона с дальней клеткой")
	var first: Dictionary = sim_t._nearest_zone_cell(res_t)
	_check(not first.is_empty(), "цель обустройства выбрана")
	var near_cells: Array = _grass_tiles(sim_t, sim_t.map.spawn_tile + Vector2i(-9, 9), 1)
	sim_t.add_zone("pasture", near_cells)
	var again: Dictionary = sim_t._nearest_zone_cell(res_t)
	_check(int(again["idx"]) == int(first["idx"]) \
			and int((again["zone"] as Dictionary)["id"]) == int((first["zone"] as Dictionary)["id"]),
			"цель липкая: ближе появившуюся клетку не перебирает на ходу")
	print("[Правки v1.20.1] готово")
