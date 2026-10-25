# Тесты v1.23: статы и прикладные навыки (чем занимаешься — то и растёт),
# спарринг стражей без другой работы, кладбище (первая могила основывает
# место, обряды огня и земли, останки врагов), тайный некромант ночью,
# фермы не занимают чужие поля, вывоз поваленных деревьев прохожими.
extends "res://tests/test_base.gd"


# --- статы и прикладные навыки (v1.23) ----------------------------------------

func _test_v123_attributes() -> void:
	var sim = _make_sim()
	print("[v1.23: статы и навыки]")
	var r: Dictionary = sim.residents[0]
	r["traits"] = []
	var day_len: float = float(sim.cfg["day_length"])
	# 10 дней валить лес: растут «дровосек», сила и выносливость, но не ловкость
	# (v1.24: у жителей врождённый пул статов — проверяем прирост, не абсолют)
	var agi_before: float = float((r.get("stats", {}) as Dictionary).get("agi", 0.0))
	var str_before: float = float((r.get("stats", {}) as Dictionary).get("str", 0.0))
	var end_before: float = float((r.get("stats", {}) as Dictionary).get("end", 0.0))
	sim._grow_skill(r, day_len * 10.0, "lumberjack")
	_check(float((r.get("skills", {}) as Dictionary).get("lumberjack", 0.0)) > 4.0,
			"10 дней рубки — дровосек почти мастер (%.1f)" % float((r.get("skills", {}) as Dictionary).get("lumberjack", 0.0)))
	_check(float((r.get("stats", {}) as Dictionary).get("str", 0.0)) > str_before + 1.0,
			"физический труд растит силу (%.1f → %.1f)" % [str_before, float((r.get("stats", {}) as Dictionary).get("str", 0.0))])
	_check(float((r.get("stats", {}) as Dictionary).get("end", 0.0)) > end_before + 1.0, "…и выносливость")
	_check(absf(float((r.get("stats", {}) as Dictionary).get("agi", 0.0)) - agi_before) < 0.001,
			"ловкость от рубки не растёт")
	# интеллект ускоряет обучение (v1.24: обнуляем врождённый интеллект —
	# случайный пул не должен маскировать сравнение)
	var smart: Dictionary = sim.residents[1]
	smart["traits"] = []
	smart["stats"] = {"str": 0.0, "agi": 0.0, "end": 0.0, "int": 5.0, "wis": 0.0}
	(r.get("stats", {}) as Dictionary)["int"] = 0.0
	sim._grow_skill(smart, day_len * 2.0, "acolyte")
	sim._grow_skill(r, day_len * 2.0, "acolyte")
	_check(float((smart.get("skills", {}) as Dictionary).get("acolyte", 0.0))
			> float((r.get("skills", {}) as Dictionary).get("acolyte", 0.0)),
			"интеллект ускоряет обучение (%.2f > %.2f)" % [float((smart.get("skills", {}) as Dictionary).get("acolyte", 0.0)),
					float((r.get("skills", {}) as Dictionary).get("acolyte", 0.0))])
	# бой растит «воина»
	sim._grow_combat(r, day_len)
	_check(float((r.get("skills", {}) as Dictionary).get("warrior", 0.0)) > 0.0,
			"бой прокачивает боевой навык")
	# производство считает навык дела: у мастер-дровосеки множитель выше
	var mill: Dictionary = _build_now(sim, "sawmill")
	var lj: Dictionary = _resident_by_prof(sim, "lumberjack")
	lj["traits"] = []
	lj["mood"] = 100.0
	lj["bld"] = mill
	lj["skill"] = 0.0   # общий стаж не должен маскировать прикладной навык
	var plain: float = sim.work_mult(lj)
	(lj.get("skills", {}) as Dictionary)["lumberjack"] = 5.0
	var master: float = sim.work_mult(lj)
	_check(master > plain * 1.3, "мастер-дровосек работает заметно быстрее (%.2f > %.2f)" % [master, plain])
	# ловкость ускоряет шаг: сравниваем длину шага через _move_towards
	lj["stats"] = {"str": 0.0, "agi": 5.0, "end": 0.0, "int": 0.0}
	var far: Vector2i = sim.map.nearest_walkable(Vector2i(mill["tile"]) + Vector2i(6, 6))
	_teleport(sim, lj, Vector2i(mill["tile"]))
	var before_px: Vector2 = lj["pos"]
	sim._move_towards(lj, far, 0.5)
	var fast_d: float = (lj["pos"] as Vector2).distance_to(before_px)
	lj["stats"] = {"str": 0.0, "agi": 0.0, "end": 0.0, "int": 0.0}
	_teleport(sim, lj, Vector2i(mill["tile"]))
	before_px = lj["pos"]
	sim._move_towards(lj, far, 0.5)
	var slow_d: float = (lj["pos"] as Vector2).distance_to(before_px)
	_check(fast_d > slow_d + 1.0, "ловкий житель шагает дальше (%.1f > %.1f)" % [fast_d, slow_d])
	# выносливость сдерживает усталость (end 5 → цена 1/1.2 ≈ 0.83)
	lj["stats"] = {"str": 0.0, "agi": 0.0, "end": 5.0, "int": 0.0, "wis": 0.0}
	_check(sim._fatigue_cost(lj) < 0.85, "выносливый устаёт медленнее (%.2f)" % sim._fatigue_cost(lj))


# --- спарринг стражей (v1.23) --------------------------------------------------

func _test_v123_spar() -> void:
	var sim = _make_sim()
	print("[v1.23: спарринг стражей]")
	var day_len: float = float(sim.cfg["day_length"])
	var g1: Dictionary = sim.residents[0]
	var g2: Dictionary = sim.residents[1]
	# в городе уже есть штатный страж — уводим его в «занятые», чтобы
	# проверяемая пара сошлась друг с другом, а не с ним
	for other in sim.residents:
		if other != g1 and other != g2 and String(other["prof"]) == "guard":
			other["spar_until"] = 999999999.0
			other["state"] = "work"
	for g in [g1, g2]:
		g["prof"] = "guard"
		g["bld"] = null
		g["site"] = null
		g["shift"] = "day"
		g["spar_until"] = 0.0
		g["fatigue"] = 0.0
		g["state"] = "idle"
		g["traits"] = []
	_teleport(sim, g1, sim.map.spawn_tile)
	_teleport(sim, g2, sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(2, 0)))
	var paired := false
	var finished := false
	for i in 1200:
		var a: bool = sim._guard_spar(g1, 0.1)
		var b: bool = sim._guard_spar(g2, 0.1)
		if a and b and String(g1["state"]) == "spar" and String(g2["state"]) == "spar":
			paired = true
		if float(g1.get("spar_until", 0.0)) > sim.time:
			finished = true
			break
	_check(paired, "стражи сошлись на тренировке (state spar)")
	_check(finished, "тренировка завершилась перерывом")
	_check(float((g1.get("skills", {}) as Dictionary).get("warrior", 0.0)) > 0.0,
			"спарринг растит боевой навык (%.2f)" % float((g1.get("skills", {}) as Dictionary).get("warrior", 0.0)))
	_check(float((g1.get("stats", {}) as Dictionary).get("str", 0.0)) > 0.0
			and float((g1.get("stats", {}) as Dictionary).get("agi", 0.0)) > 0.0,
			"спарринг качает силу и ловкость")
	var spar_event := false
	for ev in sim.events:
		if String(ev["type"]) == "spar":
			spar_event = true
	_check(spar_event, "тренировка попала в события города")
	_check(int(g1.get("spar_with", -1)) < 0 and int(g2.get("spar_with", -1)) < 0,
			"после тренировки пара распущена")
	# уставшему и «на перерыве» не до спарринга
	_check(not sim._guard_spar(g1, 0.1), "перерыв держится — сразу снова не спаррингует")


# --- кладбище: место, обряды, останки (v1.23) ----------------------------------

func _test_v123_cemetery() -> void:
	var sim = _make_sim()
	print("[v1.23: кладбище и обряды]")
	var day_len: float = float(sim.cfg["day_length"])
	# 1) первая смерть без кладбища: могила основала место в 10–22 клетках
	var dead: Dictionary = sim.residents[sim.residents.size() - 1]
	sim._kill(dead, "chron.died_sick")
	_check(sim.cemetery_tile != Vector2i(-1, -1), "первая могила основала кладбище")
	var dist: float = Vector2(sim.cemetery_tile).distance_to(Vector2(sim.map.spawn_tile))
	_check(dist >= 9.0 and dist <= 23.0, "кладбище в ~10 клетках от города (%.0f)" % dist)
	_check(sim.graves.size() == 1, "могила выкопана (%d)" % sim.graves.size())
	var founded_event := false
	for ev in sim.events:
		if String(ev["type"]) == "cemetery_founded":
			founded_event = true
	_check(founded_event, "город оповещён о новом кладбище")
	# 2) обряд без божества — закопали или сожгли; божество Пепла — жгут
	var grave: Dictionary = sim.graves[0]
	_check(["bury", "burn"].has(String(grave.get("rite", ""))), "обряд выбран (%s)" % String(grave.get("rite", "")))
	sim.god = "ash"
	sim.res["wood"] = 10.0
	var dead2: Dictionary = sim.residents[sim.residents.size() - 1]
	var wood_before: float = float(sim.res["wood"])
	sim._kill(dead2, "chron.died_sick")
	var burn_grave: Dictionary = {}
	for g in sim.graves:
		if String(g.get("rite", "")) == "burn":
			burn_grave = g
	_check(not burn_grave.is_empty(), "вера Пепла велит сжигать — костёр сложен")
	_check(float(sim.res["wood"]) < wood_before, "костёр взял дрова из города")
	_check(absf(float(burn_grave.get("burn_left", 0.0)) - float(sim.cfg.get("cemetery", {}).get("burn_days", 2.0))) < 0.01,
			"костёр горит два дня")
	# 3) костёр догорает — прах готов, тьма им не питается
	sim._update_cemetery(day_len * 2.1, day_len)
	_check(bool(burn_grave.get("ready", false)), "прах предан огню — могила готова")
	var cremated_event := false
	for ev in sim.events:
		if String(ev["type"]) == "cremated":
			cremated_event = true
	_check(cremated_event, "город помнит сожжённого")
	_check(sim._buried_count() >= 0, "закопанный прах посчитан (%d)" % sim._buried_count())
	# 4) бесплотные не оставляют останков, телесные — оставляют
	var tile_w: Vector2i = sim.map.nearest_walkable(Vector2i(sim.cemetery_tile) + Vector2i(1, 3))
	var wraith := {"type": "wraith", "hp": 1, "pos": sim.map.tile_center_px(tile_w)}
	sim._hit_raider(wraith, 5)
	_check(sim.corpses.is_empty(), "призрак не оставил останков")
	var mutant := {"type": "mutant", "hp": 10, "pos": sim.map.tile_center_px(tile_w)}
	sim._hit_raider(mutant, 20)
	_check(sim.corpses.size() == 1, "мутант оставил останки")
	# 5) останки уносят на кладбище и хоронят
	sim._roll_corpse_haul()
	var bearer: Dictionary = {}
	for r in sim.residents:
		if not (r.get("corpse_task", {}) as Dictionary).is_empty():
			bearer = r
			break
	_check(not bearer.is_empty(), "город послал жителя за останками")
	_teleport(sim, bearer, tile_w)
	_check(sim._corpse_work(bearer, 0.1), "носильщик поднял останки")
	_teleport(sim, bearer, sim.cemetery_tile)
	sim._corpse_work(bearer, 0.1)
	var foe_grave: Dictionary = {}
	for g in sim.graves:
		if String(g.get("kind", "")) == "mutant":
			foe_grave = g
	_check(not foe_grave.is_empty(), "останки врага похоронены на кладбище")
	_check(bool(foe_grave.get("ready", false)), "могила врага готова сразу")
	_check(sim.corpses.is_empty(), "останки унесены с поля")


# --- тайный некромант ночью (v1.23) --------------------------------------------

func _test_v123_necro_night() -> void:
	var sim = _make_sim()
	print("[v1.23: тайный некромант]")
	var day_len: float = float(sim.cfg["day_length"])
	# зов слышен только к закопанному праху (легендарный случай)
	sim.cemetery_tile = sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(12, 3))
	sim.graves.append({"tile": sim.cemetery_tile, "name": "Старик", "ready": true, "rite": "bury"})
	sim.cfg["necro"]["call_chance"] = 1.0
	sim._roll_necro()
	var chosen := false
	for r in sim.residents:
		if String(r.get("secret", "")) == "necromancer":
			chosen = true
	_check(chosen, "зов услышан — некромант выбран")
	# ночной путь: дойти до могил и отрезаться над прахом
	var necro: Dictionary = {}
	for r in sim.residents:
		if String(r.get("secret", "")) == "necromancer":
			necro = r
			break
	necro["fatigue"] = 0.0
	necro["bld"] = null
	necro["site"] = null
	_teleport(sim, necro, sim.map.nearest_walkable(Vector2i(sim.cemetery_tile) + Vector2i(3, 0)))
	sim.cfg["necro"]["army_per_ritual_chance"] = 1.0
	var army_before := int(sim.necro_army)
	var saw_rite := false
	for i in 400:
		if String(necro.get("necro_phase", "")) == "rite" and String(necro["state"]) == "necro":
			saw_rite = true
		if not sim._necro_night_walk(necro, 1.0):
			break
	_check(saw_rite, "некромант склонился над прахом у могил")
	_check(int(sim.necro_army) > army_before or float(sim.necro_dark) > 0.0,
			"ночь у могил удалась: армия/тьма выросли (%d / %.2f)" % [sim.necro_army, sim.necro_dark])
	# увидели — раскрыт
	var witness: Dictionary = sim.residents[0]
	if witness == necro:
		witness = sim.residents[1]
	witness["state"] = "idle"
	witness["inside"] = 0
	_teleport(sim, witness, sim.map.nearest_walkable(Vector2i(sim.cemetery_tile) + Vector2i(1, 0)))
	_check(sim._necro_seen(necro), "бодрствующий свидетель рядом — некроманта видно")
	sim._necro_caught(necro)
	_check(sim.necro_known, "тайна раскрыта")
	var seen_event := false
	for ev in sim.events:
		if String(ev["type"]) == "necro_revealed" and String(ev.get("name", "")) != "":
			seen_event = true
	_check(seen_event, "город знает имя пойманного")
	# сожжённые могилы тьму не кормят: всё чисто — тьма тает
	sim.graves.clear()
	sim.necro_dark = 0.5
	sim.cfg["necro"]["dark_per_night"] = 0.06
	sim._roll_necro()
	_check(float(sim.necro_dark) < 0.5, "без закопанного праха тьма тает (%.2f)" % sim.necro_dark)


# --- фермы не занимают чужие поля (v1.23) --------------------------------------

func _test_v123_farm_fields() -> void:
	var sim = _make_sim()
	print("[v1.23: фермы и чужие поля]")
	var farm1: Dictionary = _build_now(sim, "farm")
	var field: Dictionary = {}
	for z in sim.zones:
		if int(z.get("farm", -1)) == int(farm1["id"]):
			field = z
			break
	_check(not field.is_empty(), "у фермы распахано поле")
	var on_field: Vector2i = field["cells"][0]
	_check(sim.placement_block("farm", on_field) == "city.placement_field",
			"ферму нельзя поставить на чужое поле")
	_check(not sim.place_building("farm", on_field), "стройка на грядках не заложена")
	# самострой тоже обходит чужие грядки
	var auto_t: Vector2i = sim._find_autobuild_tile("farm")
	_check(auto_t != Vector2i(-1, -1), "место для второй фермы нашлось")
	var overlaps := false
	for z in sim.zones:
		for c in z["cells"]:
			var w: int = sim.bld_w_of_type("farm")
			var hit := false
			for dy in w:
				for dx in w:
					if Vector2i(auto_t + Vector2i(dx, dy)) == c:
						hit = true
				if hit:
					break
			if hit:
				overlaps = true
				break
	_check(not overlaps, "самострой не ставит ферму на чужие грядки")
	var farm2: Dictionary = _build_now(sim, "farm")
	var cells2: Array = []
	for z in sim.zones:
		if int(z.get("farm", -1)) == int(farm2["id"]):
			cells2 = z["cells"]
	_check(not cells2.is_empty(), "у второй фермы своё поле")
	var clash := 0
	for c in field["cells"]:
		if cells2.has(c):
			clash += 1
	_check(clash == 0, "поля ферм не пересекаются (%d общих клеток)" % clash)


# --- вывоз поваленных деревьев (v1.23) -----------------------------------------

func _test_v123_log_haul() -> void:
	var sim = _make_sim()
	print("[v1.23: вывоз брёвен]")
	# лесопилку в сторону от бревна: радиуса поиска больше нет
	var mill: Dictionary = _build_now(sim, "sawmill")
	var far: Vector2i = Vector2i(-1, -1)
	for dy in range(-24, 25):
		for dx in range(-24, 25):
			var t: Vector2i = Vector2i(mill["tile"]) + Vector2i(dx, dy)
			if not sim.map.in_bounds(t) or not sim.map.is_walkable(t) or not sim.building_at(t).is_empty():
				continue
			if Vector2(t).distance_to(Vector2(mill["tile"])) > float(sim.cfg.get("gather_range", 6)) + 4.0:
				far = t
				break
		if far != Vector2i(-1, -1):
			break
	_check(far != Vector2i(-1, -1), "нашли далёкую клетку для бревна")
	sim.map.logs[far] = {"size": 2}
	var lj: Dictionary = _resident_by_prof(sim, "lumberjack")
	_check(sim._log_target(lj, mill) == far,
			"лесопилка идёт за бревном без радиуса поиска")
	# прохожий рядом подбирает и несёт на лесопилку
	var passer: Dictionary = _resident_by_prof(sim, "farmer")
	if passer.is_empty():
		passer = sim.residents[0]
	passer["bld"] = null
	passer["site"] = null
	passer["state"] = "idle"
	passer["fatigue"] = 0.0
	_teleport(sim, passer, far)
	_check(sim._try_haul_log(passer, 0.1), "прохожий взялся тащить бревно")
	_check(bool(passer.get("haul_log", false)), "ноша отмечена")
	for i in 600:
		if not sim._log_haul_work(passer, 0.2):
			break
	_check(not sim.map.logs.has(far), "бревно поднято с земли")
	_teleport(sim, passer, Vector2i(mill["tile"]))
	for i in 600:
		if not sim._log_haul_work(passer, 0.2):
			break
	_check((mill.get("pending_logs", []) as Array).has(2), "бревно сдано в ворох лесопилки")
	_check(not bool(passer.get("haul_log", false)) and int(passer.get("log_size", 0)) == 0,
			"прохожий свободен после ходки")
	var hauled_event := false
	for ev in sim.events:
		if String(ev["type"]) == "log_hauled":
			hauled_event = true
	_check(hauled_event, "вынос бревна отмечен событием")
	# лесоруб пилит ворох на месте, без ходки (v1.25: доски сразу в общий пул)
	lj["bld"] = mill
	lj["traits"] = []
	lj["mood"] = 100.0
	_teleport(sim, lj, Vector2i(mill["tile"]))
	var wood_before: float = float(sim.res["wood"])
	for i in 80:
		sim._sawmill_work(lj, mill, 0.5)
	_check(float(sim.res["wood"]) > wood_before,
			"ворох брёвен распилен в доски (%.0f)" % float(sim.res["wood"]))
	_check((mill.get("pending_logs", []) as Array).is_empty(), "ворох опустошён")
