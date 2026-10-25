# Этапы M6-M10: зоны/дороги/носильщик, биомы, карта мира, полировка, рынок и скот.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_m6() -> void:
	print("[M6: зоны, дороги, носильщик, декор]")

	# --- зоны: разбивка, отсев негодных клеток, заполнение жителями ---
	# (правки v1.20: остались только Поле и Пастбище — проверяем на пастбище)
	var sim := _make_sim()
	sim._last_daily_day = 999
	sim.cfg["food_per_resident_day"] = 0.0
	var cells: Array = _grass_tiles(sim, sim.map.spawn_tile + Vector2i(-2, -2), 4)
	_check(cells.size() == 4, "у центра есть чистая трава под зону")
	# в зону попадают только годные клетки: воду и скалы сим отсекает сама
	var mixed: Array = cells.duplicate()
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_WATER:
				mixed.append(Vector2i(x, y))
				break
		if mixed.size() > cells.size():
			break
	var added: int = sim.add_zone("pasture", mixed)
	_check(added == cells.size(), "зона разбита: вода и скалы отсечены")
	_check(sim.zones.size() == 1, "зона сохранена в симуляции")
	_check(sim.add_zone("pasture", cells) == 0, "второй раз на те же клетки зону не разбить")
	_check(sim.add_zone("unknown", cells) == 0, "неизвестный тип зоны отвергается")
	_check(sim.add_zone("living", cells) == 0, "жилая зона убрана из конфига (v1.20)")
	_check(sim.add_zone("industrial", cells) == 0, "зоны-слои убраны из конфига (v1.20)")
	# обустроенные клетки пастбища кормят: житель сам идёт к ближайшей незаполненной
	var zliving: Dictionary = sim.zones[0]
	var farmer_z: Dictionary = _resident_by_prof(sim, "farmer")
	farmer_z["traits"] = []
	farmer_z["mood"] = 100.0
	for i in (zliving["cells"] as Array).size():
		_teleport(sim, farmer_z, zliving["cells"][i])
		sim.tick(6.0)
	var done_seen := false
	for ev in sim.events:
		if String(ev["type"]) == "zone_done":
			done_seen = true
	_check(done_seen, "заполненная целиком зона объявлена событием")

	# --- поле: обустроенные клетки дают еду в пул ---
	var sim_f := _make_sim()
	sim_f._last_daily_day = 999
	sim_f.cfg["food_per_resident_day"] = 0.0
	var fcells: Array = _grass_tiles(sim_f, sim_f.map.spawn_tile + Vector2i(3, 3), 4)
	_check(sim_f.add_zone("field", fcells) == fcells.size(), "поле разбито")
	var zfield: Dictionary = sim_f.zones[0]
	var worker_f: Dictionary = _resident_by_prof(sim_f, "lumberjack")
	worker_f["traits"] = []
	worker_f["mood"] = 100.0
	for i in (zfield["cells"] as Array).size():
		_teleport(sim_f, worker_f, zfield["cells"][i])
		sim_f.tick(6.0)
	var food0: float = float(sim_f.res["food"])
	# M10 + этап 2/аспект 3: поле работает циклами посев→рост→урожай.
	# v1.21: репа зреет 3.2 дня (стадии 4 × 0.8) — даём до двух циклов
	sim_f.cfg["food_per_resident_day"] = 0.0   # меряем чистый урожай без трат
	var food1: float = float(sim_f.res["food"])
	var expected: float = fcells.size() * float(sim_f.crop_def("turnip")["harvest"])
	var grown := 0.0
	for i in 24:
		sim_f.tick(float(sim_f.cfg["day_length"]) / 2.0)
		grown = float(sim_f.res["food"]) - food1
		if grown >= expected - 0.6:
			break
	_check(grown >= expected - 0.6 or float(sim_f.res["food"]) >= food0 + expected - 0.6,
			"поле собрало урожай: %d клетки × %.1f" % [fcells.size(), expected])
	_check(float(sim_f.res["seeds"]) >= 1.0 or (sim_f.zones[0]["crops"] as Array).size() > 0,
			"урожай вернул семена — цикл поля замкнулся")

	# --- зона и стройка (v1.21): пастбище уступает клетку, поле — нет ---
	# (v1.20: у спавна площадь с запретом стройки — зона подальше)
	var sim_z2 := _make_sim()
	sim_z2._last_daily_day = 999
	var zcells: Array = _grass_tiles(sim_z2, sim_z2.map.spawn_tile + Vector2i(7, 7), 4)
	sim_z2.add_zone("pasture", zcells)
	var before_n: int = (sim_z2.zones[0]["cells"] as Array).size()
	sim_z2.place_building("wall", zcells[0])
	_check((sim_z2.zones[0]["cells"] as Array).size() == before_n - 1,
			"здание на клетке пастбища убирает клетку из зоны")
	# клетки поля фермы (и ручного поля) стройке запрещены (v1.21)
	var fcells_z: Array = _grass_tiles(sim_z2, sim_z2.map.spawn_tile + Vector2i(-7, 7), 2)
	sim_z2.add_zone("field", fcells_z)
	_check(sim_z2.placement_block("wall", fcells_z[0]) == "city.placement_field",
			"на клетке поля строить нельзя (v1.21)")

	# --- дороги: камень за тайл, ускорение по дороге ---
	var sim_r := _make_sim()
	sim_r._last_daily_day = 999
	sim_r.res["stone"] = 50.0
	var road_cells: Array = _grass_tiles(sim_r, sim_r.map.spawn_tile, 5)
	# прямая линия по траве вправо
	var line: Array = []
	var base: Vector2i = road_cells[0]
	for i in 4:
		var t: Vector2i = base + Vector2i(i, 0)
		if sim_r.map.in_bounds(t) and sim_r.map.is_nature_walkable(t) and sim_r.building_at(t).is_empty():
			line.append(t)
	_check(line.size() >= 3, "нашлась прямая под дорогу")
	var stone0r: float = float(sim_r.res["stone"])
	for t in line:
		_check(sim_r.place_road(t) == "", "дорога проложена на %s" % str(t))
	_check(sim_r.map.has_road(line[0]), "дорога попала в слой карты")
	_check(float(sim_r.res["stone"]) < stone0r, "за дорогу заплачен камень")
	_check(sim_r.place_road(Vector2i(-5, -5)) == "bad", "вне карты дорогу не проложить")
	# ускорение: строитель по дороге проходит больше за тот же тик
	# (у него есть цель — стройка в конце пути)
	var sim_p := _make_sim()
	sim_p._last_daily_day = 999
	var dest: Vector2i = line[line.size() - 1] + Vector2i(3, 0)
	while not (sim_r.map.in_bounds(dest) and sim_r.is_buildable_tile(dest) and sim_p.is_buildable_tile(dest)):
		dest += Vector2i(1, 0)
	sim_r.place_building("wall", dest)
	sim_p.place_building("wall", dest)
	var walker_r: Dictionary = _resident_by_prof(sim_r, "builder")
	_teleport(sim_r, walker_r, line[0])
	sim_r.time = 10.0
	sim_r.tick(1.0)
	var d_road: float = (walker_r["pos"] as Vector2).distance_to(sim_r.map.tile_center_px(line[0]))
	var walker_p: Dictionary = _resident_by_prof(sim_p, "builder")
	_teleport(sim_p, walker_p, line[0])
	sim_p.time = 10.0
	sim_p.tick(1.0)
	var d_plain: float = (walker_p["pos"] as Vector2).distance_to(sim_p.map.tile_center_px(line[0]))
	_check(d_road > d_plain + 5.0, "по дороге житель идёт быстрее (%.0f > %.0f)" % [d_road, d_plain])
	# ходьба протаптывает тропы: износ копится на тайлах
	var wear_sum := 0.0
	for t in sim_r.map.wear:
		wear_sum += float(sim_r.map.wear[t])
	_check(wear_sum > 0.0, "жители протаптывают тропы: износ копится (%.1f)" % wear_sum)

	# --- автодороги: изношенная тропа сама становится дорогой ---
	var sim_a := _make_sim()
	sim_a._last_daily_day = 999
	sim_a.res["stone"] = 50.0
	var atile: Vector2i = _grass_tiles(sim_a, sim_a.map.spawn_tile + Vector2i(1, 1), 1)[0]
	sim_a.map.add_wear(atile, 30.0)   # тропу натоптали выше порога
	sim_a._roll_auto_roads()
	_check(sim_a.map.has_road(atile), "изношенная тропа сама стала дорогой")
	_check(float(sim_a.res["stone"]) < 50.0, "за автодорогу заплачен камень города")
	_check(not sim_a.map.wear.has(atile), "износ снят после прокладки дороги")
	# лимит: три тропы, за один день только auto_per_day
	var more: Array = _grass_tiles(sim_a, sim_a.map.spawn_tile + Vector2i(4, 4), 3)
	var limit: int = int(sim_a.cfg["roads"]["auto_per_day"])
	for i in more.size():
		sim_a.map.add_wear(more[i], 30.0)
	sim_a.res["stone"] = 50.0
	sim_a._roll_auto_roads()
	var built_now := 0
	for t in more:
		if sim_a.map.has_road(t):
			built_now += 1
	_check(built_now == limit, "за день город тянет не больше %d автодорог (проложено %d)" % [limit, built_now])
	# зоны автодороги обходят
	var ztile: Vector2i = _grass_tiles(sim_a, sim_a.map.spawn_tile + Vector2i(-3, 3), 1)[0]
	sim_a.add_zone("field", [ztile])
	sim_a.map.add_wear(ztile, 30.0)
	sim_a._roll_auto_roads()
	_check(not sim_a.map.has_road(ztile), "через зону автодорога не прокладывается")
	# резерв камня: не в ущерб стройке
	var sim_b := _make_sim()
	sim_b._last_daily_day = 999
	sim_b.res["stone"] = 5.0
	var btile: Vector2i = _grass_tiles(sim_b, sim_b.map.spawn_tile + Vector2i(1, 1), 1)[0]
	sim_b.map.add_wear(btile, 30.0)
	sim_b._roll_auto_roads()
	_check(not sim_b.map.has_road(btile), "камня меньше резерва — город дороги сам не тянет")
	# без старосты дорогами никто не занимается
	var sim_c := _make_sim()
	sim_c._last_daily_day = 999
	for r in sim_c.residents:
		if String(r["prof"]) == "elder":
			r["prof"] = "crafter"
	sim_c.res["stone"] = 50.0
	var ctile: Vector2i = _grass_tiles(sim_c, sim_c.map.spawn_tile + Vector2i(1, 1), 1)[0]
	sim_c.map.add_wear(ctile, 30.0)
	sim_c._roll_auto_roads()
	_check(not sim_c.map.has_road(ctile), "без старосты автодорог нет — как и самостроя")

	# --- v1.25: производство сразу в общий пул — кучи и носильщик упразднены ---
	var sim_pg := _make_sim()
	sim_pg._last_daily_day = 999
	sim_pg.cfg["food_per_resident_day"] = 0.0
	sim_pg.res["wood"] = 50.0
	sim_pg.res["stone"] = 50.0
	var ws_pg := _build_now(sim_pg, "workshop")
	var crafter_pg: Dictionary = _resident_by_prof(sim_pg, "crafter")
	_check(not crafter_pg.is_empty(), "среди жителей есть ремесленник")
	crafter_pg["traits"] = []
	crafter_pg["mood"] = 100.0
	_teleport(sim_pg, crafter_pg, ws_pg["tile"])
	var tools_pg0: float = float(sim_pg.res.get("tools", 0.0))
	for i in 30:   # полминуты у верстака
		sim_pg.tick(1.0)
	_check(float(sim_pg.res.get("tools", 0.0)) > tools_pg0,
			"мастерская кладёт изделия сразу в общий пул (%.1f → %.1f)"
					% [tools_pg0, float(sim_pg.res.get("tools", 0.0))])
	_check((ws_pg.get("pile", {}) as Dictionary).is_empty(),
			"куча у здания больше не растёт (v1.25)")
	# готовых куч нет — город больше не обучает носильщиков
	sim_pg._roll_porter()
	var porter_any := false
	for r in sim_pg.residents:
		if String(r["prof"]) == "porter":
			porter_any = true
	_check(not porter_any, "носильщик не нужен — город его не обучает (v1.25)")

	# --- бонус планировки: склад рядом с производством ускоряет его ---
	# v1.21: ферма больше не «производит» (её урожай — грядки), бонус планировки
	# проверяем на плавильне; v1.21.1: районы глушим — предмет теста дальняя
	# плавильня, а правило ветки требует строить её у первой
	var sim_l := _make_sim()
	sim_l._last_daily_day = 999
	sim_l.cfg["district"] = {}
	sim_l.res["iron"] = 50.0
	sim_l.res["wood"] = 60.0   # v1.21: на склад и две плавильни хватает дерева
	sim_l.res["stone"] = 60.0
	var barn_l := _build_now(sim_l, "warehouse")
	# этап 2: зазор 1 — плавильня в трёх клетках от склада (в радиусе бонуса 4)
	var smelt_tile_l: Vector2i = sim_l.map.nearest_walkable((barn_l["tile"] as Vector2i) + Vector2i(3, 0))
	var smelt_l := _build_at(sim_l, "smelter", smelt_tile_l)
	_check(bool(smelt_l["done"]), "плавильня у склада построена")
	_check(absf(float(sim_l.production_mult(smelt_l)) - float(sim_l.cfg["layout"]["warehouse_mult"])) < 0.001,
			"склад рядом с производством даёт +25% скорости (бонус планировки)")
	# дальняя плавильня: заведомо за пределами радиуса склада
	var smelt_far := Vector2i(-1, -1)
	for radius in range(8, 14):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t: Vector2i = sim_l.map.spawn_tile + Vector2i(dx, dy)
				if sim_l.is_buildable_rect("smelter", t) \
						and Vector2(t).distance_to(Vector2(barn_l["tile"])) > 5.0:
					smelt_far = t
					break
			if smelt_far != Vector2i(-1, -1):
				break
		if smelt_far != Vector2i(-1, -1):
			break
	_check(smelt_far != Vector2i(-1, -1), "нашлось место под дальнюю плавильню")
	var smelt_l2 := _build_at(sim_l, "smelter", smelt_far)
	var mult_far: float = float(sim_l.production_mult(smelt_l2))
	_check(mult_far < 1.2, "далёкая от склада плавильня без бонуса (%.2f)" % mult_far)

	# --- декор: сад и статуя поднимают мораль городу ---
	var sim_d := _make_sim()
	sim_d._last_daily_day = 999
	var probe: Dictionary = {"traits": [], "mood": 50.0, "fatigue": 0.0, "home": {}, "friend": -1, "ail": ""}
	var mood_plain: float = float(sim_d._mood_target(probe))
	_build_now(sim_d, "garden")
	_build_now(sim_d, "statue")
	var decor_sum: int = 0
	for b in sim_d.cfg["buildings"]:
		if String(b.get("effect", "")) == "decor":
			decor_sum += int(b["mood"])
	_check(absf(float(sim_d.decor_mood()) - float(decor_sum)) < 0.001, "декор суммируется (сад + статуя)")
	_check(absf(float(sim_d._mood_target(probe)) - mood_plain - float(decor_sum)) < 0.001,
			"декор поднимает мораль всем жителям (ответ №18)")
	sim_d.cfg["decor_mood_max"] = float(decor_sum) - 1.0
	_check(absf(float(sim_d.decor_mood()) - float(decor_sum - 1)) < 0.001, "комфорт ограничен потолком")

	# --- мастерская: чинит повреждённые здания, целые — переработка ---
	var sim_w := _make_sim()
	sim_w._last_daily_day = 999
	sim_w.cfg["repair"] = {"per_day": 240.0}
	for r in sim_w.residents:   # v1.20: среди стартовых есть крафтер — уводим
		if String(r["prof"]) == "crafter":
			r["prof"] = "lumberjack"
	var crafter_w: Dictionary = _add_resident(sim_w, "Кира", "crafter")
	var workshop_w := _build_now(sim_w, "workshop")
	_check(int(workshop_w["worker"]) == int(crafter_w["id"]), "мастер в мастерской")
	var house_w := _build_now(sim_w, "house")
	house_w["hp"] = 4.0   # дом повреждён бурей
	_teleport(sim_w, crafter_w, workshop_w["tile"])
	sim_w.time = 10.0
	for i in 6:   # дойти до повреждённого дома и чинить (2×2: подход у входа)
		sim_w.tick(3.0)
	_check(float(house_w["hp"]) > 4.0, "мастерская чинит повреждённое здание")
	var max_hp: float = float(sim_w._bld_max_hp("house"))
	house_w["hp"] = max_hp
	sim_w.res["wood"] = 20.0
	sim_w.res["stone"] = 20.0
	var tools_w0: float = float(sim_w.res.get("tools", 0.0))
	_teleport(sim_w, crafter_w, workshop_w["tile"])
	sim_w.time = 10.0
	sim_w.tick(20.0)
	_check(float(sim_w.res.get("tools", 0.0)) > tools_w0,
			"чинить нечего — мастерская перерабатывает излишки в инструменты (сразу в пул)")

	# --- дорога под зданием исчезает; путь строится как раньше ---
	var sim_wr := _make_sim()
	sim_wr._last_daily_day = 999
	sim_wr.res["stone"] = 50.0
	var rtile: Vector2i = _grass_tiles(sim_wr, sim_wr.map.spawn_tile + Vector2i(6, 6), 1)[0]   # v1.20: вне радиуса площади
	sim_wr.place_road(rtile)
	_check(sim_wr.map.has_road(rtile), "дорога перед стройкой есть")
	sim_wr.place_building("wall", rtile)
	_check(not sim_wr.map.has_road(rtile), "здание на тайле убирает дорогу")



# --- M7: контент и биомы ------------------------------------------------------

func _test_m7() -> void:
	print("[M7: биомы, боссы, ловушки, навыки, дисциплины, баланс]")
	var dungeon_cfg: Dictionary = _read_json("res://data/dungeon.json")
	var enemies: Array = _read_json("res://data/enemies.json")

	# --- 4 биома: цвета, веса врагов, босс существует ---
	var biomes: Dictionary = dungeon_cfg.get("biomes", {})
	var weights: Dictionary = dungeon_cfg.get("biome_weights", {})
	_check(biomes.size() == 11 and weights.size() == 4,
			"11 биомов данжа (…+ M14-D: вампир/лич, M14-I: топь)")
	var enemy_ids := {}
	var bosses_by_id := {}
	for e in enemies:
		enemy_ids[String(e["id"])] = true
		if bool(e.get("boss", false)):
			bosses_by_id[String(e["id"])] = true
	var biome_ok := true
	for biome_id in biomes:
		var b: Dictionary = biomes[biome_id]
		for key in ["loc", "floor_color", "wall_color", "ambient", "boss"]:
			if not b.has(key):
				biome_ok = false
		if not bosses_by_id.has(String(b.get("boss", ""))):
			biome_ok = false
		for enemy_id in b.get("enemy_weights", {}):
			if not enemy_ids.has(String(enemy_id)):
				biome_ok = false
	_check(biome_ok, "у каждого биома есть босс и свои враги из enemies.json")

	# --- ловушки: 3 типа с параметрами, спавнятся на полу ---
	var traps: Dictionary = dungeon_cfg.get("traps", {})
	var kinds: Array = traps.get("types", [])
	_check(kinds.size() == 3, "3 типа ловушек (M7)")
	var trap_cfg_ok := kinds.size() == 3
	for k in kinds:
		if not (traps.get(String(k), {}) as Dictionary).has("damage"):
			trap_cfg_ok = false
	_check(trap_cfg_ok, "у каждой ловушки есть урон в конфиге")
	var gen = load("res://scripts/dungeon_gen.gd").new()
	gen.generate(777, dungeon_cfg)
	var trap_spawns_ok: bool = gen.trap_spawns.size() == int(traps.get("count", 0))
	for t in gen.trap_spawns:
		if not gen.is_floor(t["tile"]) or not (kinds.has(t["kind"])):
			trap_spawns_ok = false
	_check(trap_spawns_ok, "ловушки размещены по числу конфига, на полу, типов из списка")

	# --- разминирование ловушек по E (issue #2): шипы перестают жалить, дарты — стрелять ---
	var fake_hero := FakeInteractHero.new()
	var trap_sp = load("res://scripts/trap.gd")
	var spike = trap_sp.new()
	spike.setup("spikes", (traps.get("spikes", {}) as Dictionary), gen, fake_hero)
	spike.position = Vector2(300, 300)
	fake_hero.global_position = spike.position
	tree.root.add_child(spike)
	spike._phase = 0.0  # активная фаза шипов — точно жалит
	spike._process(0.016)
	_check(int(fake_hero.hits) == 1, "заряженные шипы жалят героя на тайле")
	spike.disarm()
	spike._process(0.016)
	_check(int(fake_hero.hits) == 1 and bool(spike.disarmed), "после разминирования шипы не жалят")
	var dart = trap_sp.new()
	dart.setup("darts", (traps.get("darts", {}) as Dictionary), gen, fake_hero)
	var dtile: Vector2i = Vector2i((spike.position / 32.0).floor()) + Vector2i(1, 0)
	while not gen.is_floor(dtile):
		dtile += Vector2i(1, 0)
	dart.position = Vector2(dtile) * 32.0 + Vector2(16, 16)
	tree.root.add_child(dart)
	fake_hero.global_position = dart.position  # герой на тайле дартов — линия чиста точно
	dart._dart_cd = 0.0
	dart._process(0.016)
	var live_hits := int(fake_hero.hits)
	_check(live_hits == 2, "дарты стреляют до разминирования")
	dart.disarm()
	dart._dart_cd = 0.0
	dart._process(0.016)
	_check(int(fake_hero.hits) == live_hits and bool(dart.disarmed), "после разминирования дарты молчат (disarm один на все типы)")
	spike.free()
	dart.free()

	# --- дерево навыков: XP, уровни, выбор узла, бонусы ---
	var skills = load("res://scripts/skills.gd").new()
	skills.setup(_read_json("res://data/skills.json"))
	var branches: Array = skills.cfg.get("branches", [])
	_check(branches.size() == 3, "дерево навыков — 3 ветки")
	var nodes_ok := branches.size() == 3
	var node_total := 0
	for branch in branches:
		node_total += (branch.get("nodes", []) as Array).size()
		if (branch.get("nodes", []) as Array).size() < 3:
			nodes_ok = false
	_check(nodes_ok and node_total >= 10, "узлы ветвей: минимум 3 на ветку, всего >= 10 (M14-G добавил s4)")
	_check(int(skills.add_xp(11)) == 0 and int(skills.level) == 1, "11 XP — ещё 1 уровень")
	_check(int(skills.add_xp(1)) == 1 and int(skills.level) == 2, "12 XP — уровень 2, выбор навыка")
	_check(int(skills.pending) == 1, "очередь выбора навыка: 1")
	var w1: Dictionary = skills.next_node("warrior")
	_check(String(w1.get("id", "")) == "w1", "первый узел воина — «Клинок ярости»")
	_check(skills.choose("w2").is_empty(), "узел не по порядку взять нельзя")
	var picked: Dictionary = skills.choose("w1")
	_check(not picked.is_empty() and int(skills.pending) == 0, "узел взят, выбор закрыт")
	_check(skills.choose("w1").is_empty(), "повторно тот же узел взять нельзя")
	var bonus: Dictionary = skills.bonuses()
	_check(absf(float(bonus.get("damage", 0.0)) - 1.0) < 0.001, "взятый узел даёт +1 урона")
	# герой применяет бонусы
	var hero = load("res://scripts/hero.gd").new()
	hero.setup({"hp": 20, "damage": 2, "mana": 10, "radius": 10, "speed": 140,
			"attack_range": 30, "attack_arc": 90, "attack_cooldown": 0.4,
			"dash_distance": 38, "dash_time": 0.12, "dash_cooldown": 1.5}, 10)
	# v1.24: статы героя влияют на урон/HP/броню/ману — для точных проверок
	# обнуляем рост (тест про бонусы дерева навыков, не про статы)
	Game.hero_stats = {"str": 0.0, "agi": 0.0, "end": 0.0, "int": 0.0, "wis": 0.0}
	hero.apply_skill_bonuses({"damage": 1.0, "hp": 5.0, "armor": 1.0, "mana": 4.0})
	_check(int(hero.eff_damage()) == 3, "герой: урон 2 + навык 1 = 3")
	_check(int(hero.hp_max()) == 25, "герой: 20 HP + 5 навыка")
	_check(int(hero.mana_max) == 14, "герой: 10 маны + 4 навыка")
	hero.take_damage(2)
	_check(int(hero.hp) == 24, "25 HP, броня 1 поглотила 1 из 2 урона -> 24")
	hero.temp_damage_bonus(8.0, 2)
	_check(int(hero.eff_damage()) == 5, "«Перегрузка»: +2 к урону на время")

	# --- дисциплины города: изучение, запреты, эффекты ---
	var sim := _make_sim()
	sim.res["food"] = 100.0
	sim.res["wood"] = 100.0
	sim.res["stone"] = 100.0
	sim.res["metal"] = 20.0
	sim.res["crystal"] = 20.0
	var rcfg: Dictionary = _read_json("res://data/research.json")
	_check((rcfg.get("branches", []) as Array).size() == 3, "3 ветки дисциплин города")
	_check(String(sim.study_research("agri2")) == "research_locked",
			"второй тир закрыт без первого")
	_check(String(sim.study_research("agri1")) == "", "первый тир земледелия изучен")
	_check(String(sim.study_research("agri1")) == "research_done", "повторно не изучается")
	sim.res["food"] = 10.0
	_check(String(sim.study_research("agri2")) == "research_no_res",
			"без ресурсов дисциплина не изучается")
	sim.res["food"] = 200.0
	sim.res["crystal"] = 20.0
	_check(String(sim.study_research("agri2")) == "", "второй тир изучен после первого")
	_check(absf(float(sim.research_mult("food_prod", 1.0)) - 1.15 * 1.15) < 0.001,
			"«Земледелие»: еда ×1.15 ×1.15")
	_check(String(sim.study_research("def1")) == "", "первый тир обороны изучен")
	_check(absf(float(sim.research_sum("tower_damage")) - 1.0) < 0.001,
			"«Оборона»: +1 к урону вышек")
	_check(String(sim.study_research("arc2")) == "research_locked",
			"«Тайное» тоже требует порядок тиров")
	_check(String(sim.study_research("arc1")) == "", "первый тир тайного изучен")
	_check(absf(float(sim.research_mult("pollution_decay_mult", 1.0)) - 1.5) < 0.001,
			"«Тайное»: порча уходит в 1.5 раза быстрее")

	# --- новые городские заклинания: камень, настроение ---
	var sim3 := _make_sim()
	sim3.res["crystal"] = 10.0
	var magic := _make_magic()
	_build_now(sim3, "altar")
	var acolyte3: Dictionary = _resident_by_prof(sim3, "acolyte")
	_teleport(sim3, acolyte3, sim3.buildings[-1]["tile"])
	sim3.tick(0.3)
	var stone_before: float = float(sim3.res["stone"])
	var err3: String = sim3.cast_city_spell(magic.spell("meteor_shard"))
	_check(err3 == "", "«Оскол метеора» соткан у алтаря")
	_check(absf(float(sim3.res["stone"]) - (stone_before + 30.0)) < 0.001,
			"«Оскол метеора»: +30 камня")
	_check(absf(float(sim3.pollution) - 6.0) < 0.001, "«Оскол метеора»: +6 загрязнения")
	var resident0: Dictionary = sim3.residents[0]
	var mood_before: float = float(resident0["mood"])
	sim3.res["crystal"] = 10.0
	err3 = sim3.cast_city_spell(magic.spell("bless"))
	_check(err3 == "" and absf(float(resident0["mood"]) - (mood_before + 12.0)) < 0.001,
			"«Благословение»: +12 настроения жителю")
	err3 = sim3.cast_city_spell(magic.spell("harvest_blessing"))
	_check(err3 == "" and float(sim3.res["food"]) >= 25.0, "«Благословение урожая»: еда в пул")

	# --- 15 историй, 15 рун, валидные рецепты, гарантированный лут босса ---
	var people: Dictionary = _read_json("res://data/residents.json")
	var story_weights: Dictionary = people.get("stories", {}).get("weights", {})
	_check(story_weights.size() == 15, "15 событий-историй (M7: +10)")
	var runes := 0
	var loot: Dictionary = _read_json("res://data/loot.json")
	for item in loot.get("items", []):
		if String(item["id"]).begins_with("rune_"):
			runes += 1
	_check(runes == 15, "15 рун в луте (M7: +7)")
	var item_ids := {}
	for item in loot.get("items", []):
		item_ids[String(item["id"])] = true
	var recipes_ok := true
	for recipe in _read_json("res://data/magic.json").get("recipes", []):
		if not item_ids.has(String(recipe["a"])) or not item_ids.has(String(recipe["b"])):
			recipes_ok = false
		if not _make_magic().spell(String(recipe["spell"])).has("id"):
			recipes_ok = false
	_check(recipes_ok, "все 20 рецептов ссылаются на существующие руны и заклинания")
	var boss_guaranteed: Array = loot.get("boss_guaranteed", [])
	_check(boss_guaranteed.size() == 2, "босс выкидывает 2 гарантированных предмета")
	var guaranteed_ok := boss_guaranteed.size() == 2
	for item_id in boss_guaranteed:
		if not item_ids.has(String(item_id)):
			guaranteed_ok = false
	_check(guaranteed_ok, "гарантированный лут босса существует в loot.json")

	# --- таблица баланса согласована с рабочими конфигами ---
	var balance: Dictionary = _read_json("res://data/balance.json")
	var city_cfg: Dictionary = _read_json("res://data/city.json")
	var pol_cfg: Dictionary = city_cfg.get("pollution", {})
	var threat_cfg: Dictionary = city_cfg.get("threat", {})
	var skills_cfg: Dictionary = _read_json("res://data/skills.json")
	var food_b: Dictionary = balance.get("food", {})
	var pol_b: Dictionary = balance.get("pollution", {})
	var threat_b: Dictionary = balance.get("threat", {})
	var loot_b: Dictionary = balance.get("loot", {})
	var hero_b: Dictionary = balance.get("hero", {})
	var balance_ok: bool = \
			absf(float(food_b.get("per_resident_day", 0)) - float(city_cfg["food_per_resident_day"])) < 0.001 \
			and int(food_b.get("farm_per_day", 0)) == 12 \
			and absf(float(pol_b.get("decay_per_day", 0)) - float(pol_cfg.get("decay_per_day", 0))) < 0.001 \
			and int(pol_b.get("max", 0)) == 100 \
			and absf(float(threat_b.get("start_day", 0)) - float(threat_cfg.get("start_day", 0))) < 0.001 \
			and int(threat_b.get("wave_size_max", 0)) == int(threat_cfg.get("raid_size_max", 0)) \
			and absf(float(loot_b.get("enemy_drop_chance", 0)) - float(loot.get("enemy_drop_chance", 0))) < 0.001 \
			and int(hero_b.get("xp_per_level_base", 0)) == int(skills_cfg.get("xp_base", 0)) \
			and int(hero_b.get("skill_tree_total_nodes", 0)) == 9 \
			and String(balance.get("_note", "")).length() > 0
	_check(balance_ok, "data/balance.json согласован с city/loot/skills конфигами")


# --- M8: карта мира «как в RimWorld» ---------------------------------------

func _test_m8() -> void:
	print("[M8: карта мира]")
	var wcfg_v: Variant = _read_json("res://data/world.json")
	_check(wcfg_v is Dictionary, "world.json — валидный JSON-словарь")
	if not (wcfg_v is Dictionary):
		return
	var wcfg: Dictionary = wcfg_v
	for key in ["map_w", "map_h", "tile_size", "biomes", "pois", "sim", "trade", "tiles_per_day"]:
		_check(wcfg.has(key), "world.json содержит %s" % key)

	# детерминизм: тот же сид — та же карта и те же точки интереса
	var map_a = load("res://scripts/world_map.gd").new()
	var map_b = load("res://scripts/world_map.gd").new()
	map_a.generate(12345, wcfg)
	map_b.generate(12345, wcfg)
	var same: bool = map_a.w == map_b.w and map_a.h == map_b.h and map_a.grid == map_b.grid \
			and map_a.pois.size() == map_b.pois.size()
	if same:
		for i in map_a.pois.size():
			if map_a.pois[i]["tile"] != map_b.pois[i]["tile"] \
					or String(map_a.pois[i]["kind"]) != String(map_b.pois[i]["kind"]):
				same = false
				break
	_check(same, "карта мира детерминирована по сиду")

	# состав точек интереса (пункт плана M8: аномалии-данжи, руины, лагеря, поселения)
	var kinds := {}
	var dungeon_biomes := {}
	for poi in map_a.pois:
		kinds[String(poi["kind"])] = int(kinds.get(String(poi["kind"]), 0)) + 1
		if String(poi["kind"]) == "dungeon" and String(poi["biome"]) != "":
			dungeon_biomes[String(poi["biome"])] = true
	_check(int(kinds.get("city", 0)) == 1, "на карте есть город игрока")
	_check(int(kinds.get("dungeon", 0)) >= 5, "городская аномалия + 4 данжа биомов на карте")
	_check(dungeon_biomes.size() == 7, "данжи всех биомов M7+M13+M14-I представлены")
	_check(int(kinds.get("ruins", 0)) >= 1, "руины на карте")
	_check(int(kinds.get("camp", 0)) >= 1, "лагеря бандитов на карте")
	_check(int(kinds.get("settlement", 0)) >= 3, "3 поселения на карте")
	_check(int(kinds.get("caravan", 0)) >= 1, "караван торговцев на карте")
	_check(int(kinds.get("obelisk", 0)) >= 1, "обелиски на карте")
	var factions := {}
	var pois_on_land := true
	for poi in map_a.pois:
		if String(poi["kind"]) == "settlement":
			factions[String(poi["faction"])] = true
		if not map_a.is_walkable(poi["tile"]):
			pois_on_land = false
	_check(factions.has("traders") and factions.has("cult"), "поселения торговцев и культа (бандиты — в лагерях)")
	_check(pois_on_land, "все точки интереса на проходимой суше")
	var reachable := true
	for poi in map_a.pois:
		if map_a.tile_path(map_a.city_tile, poi["tile"]).is_empty():
			reachable = false
	_check(reachable, "от города до каждой точки интереса есть путь")

	# время пути в днях: биом дороже, дорога быстрее (пункт плана M8)
	var days_to_anomaly := 0
	for poi in map_a.pois:
		if String(poi["kind"]) == "dungeon" and String(poi["biome"]) == "":
			days_to_anomaly = map_a.travel_days(map_a.city_tile, poi["tile"])
	_check(days_to_anomaly >= 1, "время пути считается в днях (до аномалии ≥ 1)")
	var forest_cost := -1.0
	var road_cost := -1.0
	var plains_cost := -1.0
	for y in map_a.h:
		for x in map_a.w:
			var t := Vector2i(x, y)
			match int(map_a.grid[y][x]):
				map_a.TILE_FOREST:
					forest_cost = map_a.tile_cost(t)
				map_a.TILE_ROAD:
					road_cost = map_a.tile_cost(t)
				map_a.TILE_PLAINS:
					plains_cost = map_a.tile_cost(t)
	_check(plains_cost > 0.0 and forest_cost > plains_cost, "лес идётся дороже равнины")
	_check(road_cost > 0.0 and road_cost < plains_cost, "старая дорога быстрее равнины")

	# туман войны
	_check(map_a.is_explored(map_a.city_tile), "окрестности города открыты с самого начала")
	var hidden := 0
	for poi in map_a.pois:
		if not bool(poi["discovered"]):
			hidden += 1
	_check(hidden > 0, "далёкие точки интереса скрыты туманом войны")
	var fog_before: int = map_a.fog.size()
	map_a.reveal_around(map_a.city_tile + Vector2i(12, 8), 5)
	_check(map_a.fog.size() > fog_before, "исследование открывает туман войны")
	var opened: Array = map_a.reveal_far(2)
	_check(opened.size() == 2, "карты и обелиски открывают далёкие места (ответ №24)")

	# мир живёт программно (ответ №92): осады, переселение, воскрешение данжей
	var scfg: Dictionary = wcfg.duplicate(true)
	scfg["sim"] = wcfg["sim"].duplicate(true)
	scfg["sim"]["siege_chance_per_day"] = 0.9
	scfg["sim"]["siege_days"] = 1
	scfg["sim"]["resettle_min_days"] = 1
	scfg["sim"]["resettle_chance"] = 1.0
	scfg["sim"]["dungeon_reset_days"] = 3
	scfg["sim"]["caravan_move_days"] = 2
	sim_m8_setup(map_b, scfg)


func _test_m9() -> void:
	print("[M9: спрайты и полировка]")
	var assets := _ASSETS
	# базовые файлы на месте
	for path in ["res://assets/sprites/kenney.png", "res://assets/sprites/kenney_sprites.png",
			"res://assets/sprites/knight.png", "res://assets/sprites/tree.png",
			"res://assets/sprites/rock.png", "res://assets/sprites/ore.png", "res://icon.png"]:
		_check(FileAccess.file_exists(path), "файл ассета есть: " + path)
	# резолв ссылок: Kenney-тайлы, воин, здание
	_check(assets.sprite("k:84") != null, "k:84 (маг Kenney) загружается")
	_check(assets.sprite("k:28") != null, "k:28 (пол данжа) загружается")
	_check(assets.sprite("img:knight") != null, "img:knight (герой 32x32) загружается")
	_check(assets.sprite("b:house") != null, "b:house (сгенерированное здание) загружается")
	_check(assets.sprite("") == null, "пустая ссылка — null, без ошибок")
	# каждый враг, профессия, здание и предмет имеют рабочий спрайт
	var missing := 0
	for e: Dictionary in _read_json("res://data/enemies.json"):
		if String(e.get("sprite", "")) == "" or assets.sprite(String(e["sprite"])) == null:
			missing += 1
	_check(missing == 0, "у всех врагов (%d) задан и загружается спрайт" % missing)
	var cfg: Dictionary = _read_json("res://data/city.json")
	missing = 0
	for prof: Dictionary in cfg["professions"]:
		if String(prof.get("sprite", "")) == "" or assets.sprite(String(prof["sprite"])) == null:
			missing += 1
	_check(missing == 0, "у всех профессий задан спрайт (недостающих: %d)" % missing)
	missing = 0
	for b: Dictionary in cfg["buildings"]:
		var ref := String(b.get("sprite", ""))
		# dom_house — маркер: дом выбирается из 7 вариантов dom-пака в отрисовке
		if ref == "dom_house":
			continue
		if ref == "" or assets.sprite(ref) == null:
			missing += 1
	_check(missing == 0 and cfg["buildings"].size() == 26,
			"у всех 25 зданий есть PNG-спрайт (недостающих: %d)" % missing)
	missing = 0
	for it: Dictionary in _read_json("res://data/loot.json")["items"]:
		if String(it.get("sprite", "")) == "" or assets.sprite(String(it["sprite"])) == null:
			missing += 1
	_check(missing == 0, "у всех предметов лута задан спрайт (недостающих: %d)" % missing)
	# тайлы биомов: у каждого биома floor/wall спрайт и он загружается
	var dcfg: Dictionary = _read_json("res://data/dungeon.json")
	missing = 0
	for id in dcfg["biomes"]:
		var b: Dictionary = dcfg["biomes"][id]
		if not b.has("floor_sprite") or not b.has("wall_sprite") \
				or assets.sprite(String(b["floor_sprite"])) == null \
				or assets.sprite(String(b["wall_sprite"])) == null:
			missing += 1
	_check(missing == 0, "у всех %d биомов заданы тайлы пола и стен (недостающих: %d)" % [dcfg["biomes"].size(), missing])
	_check(String(dcfg.get("sprites", {}).get("mana", "")) != "",
			"спрайт мана-кристалла задан в dungeon.json -> sprites")
	# код спрайтовых скриптов компилируется (Assets preload не рвёт остальные)
	for path in ["res://scripts/city_view.gd", "res://scripts/dungeon_view.gd",
			"res://scripts/hero.gd", "res://scripts/enemy.gd", "res://scripts/pickup.gd",
			"res://scripts/chest.gd", "res://scripts/trap.gd", "res://scripts/exit_marker.gd",
			"res://scripts/city_terrain.gd", "res://scripts/world_view.gd",
			"res://scripts/pause_overlay.gd", "res://scripts/game.gd", "res://scripts/main_menu.gd"]:
		var s: Variant = load(path)
		_check(s != null and (s as Script).can_instantiate(), path.get_file() + " компилируется")
	# версия этапа (стабильнее номера: номер растёт с каждой частью)
	var vdata: Variant = _read_json("res://data/version.json")
	_check(vdata is Dictionary and String(vdata.get("stage", "")) == "Этап 2",
			"проект на этапе «Полировка города» (версия %s)" % (String(vdata.get("version", "?")) if vdata is Dictionary else "?"))


# --- M10: релиз v1.0 — craftpix-ассеты, бандиты, скот, поля, рынок, гуляй-город

func _test_m10() -> void:
	print("[M10: правки и улучшения]")
	var assets := _ASSETS
	var cfg: Dictionary = _read_json("res://data/city.json")
	# --- новые окружение и реквизит ---
	for ref in ["e:tree1", "e:tree2", "e:tree3", "e:tree4", "e:rock1", "e:rock4",
			"e:tree_fruit", "e:stump", "e:cart", "e:tent", "e:crate", "e:sack",
			"e:crop0_0", "e:crop1_3", "e:crop2_2"]:
		_check(assets.sprite(ref) != null, "окружение/реквизит загружается: " + ref)
	# --- листы анимаций ---
	_check(assets.SHEETS.size() >= 36, "реестр листов анимаций наполнен (%d)" % assets.SHEETS.size())
	for sheet in ["cit1_d_walk", "cit4_u_idle", "orc1_walk", "orc3_idle", "cow", "sheep", "pig", "chicken", "turkey", "fire"]:
		_check(assets.sheet_frame(sheet, 0) != null, "кадр листа загружается: " + sheet)
	_check(assets.sheet_frame("orc1_walk", 17) != null, "ряд/кадр листа орка считаются (17 = влево, кадр 5)")
	_check(assets.sheet_frame("sheep", 43) != null, "ряд/кадр листа животного считаются (43 = вправо, walk)")
	_check(assets.sheet_frame("нет_такого", 0) == null, "несуществующий лист — null без ошибок")
	_check(Assets.dir_of(Vector2(-5, 1)) == "left" and Assets.dir_of(Vector2(1, 5)) == "front"
			and Assets.dir_of(Vector2(1, -5)) == "back", "dir_of: 4 направления из вектора")
	# --- бандиты-гуманоиды ---
	var enemies: Array = _read_json("res://data/enemies.json")
	var by_id := {}
	for e: Dictionary in enemies:
		by_id[String(e["id"])] = e
	for bandit_id in ["bandit", "bandit_archer", "bandit_chief"]:
		_check(by_id.has(bandit_id), "враг-гуманоид есть: " + bandit_id)
		var info: Array = assets.SHEETS.get(String(by_id[bandit_id].get("sheet", "")) + "_walk", [])
		_check(not info.is_empty(), "у %s лист анимаций зарегистрирован" % bandit_id)
	var dcfg: Dictionary = _read_json("res://data/dungeon.json")
	_check(dcfg["biomes"].has("bandit_camp"), "биом bandit_camp есть в dungeon.json")
	var camp_biome: Dictionary = dcfg["biomes"]["bandit_camp"]
	var weights: Dictionary = camp_biome["enemy_weights"]
	var weights_ok := true
	for enemy_id in weights:
		if not by_id.has(String(enemy_id)):
			weights_ok = false
	_check(weights_ok and weights.has("bandit"),
			"в лагере бандитов водятся только гуманоиды (из enemies.json)")
	_check(String(camp_biome["boss"]) == "bandit_chief", "босс лагеря — атаман-гуманоид")
	# --- карта города больше ---
	_check(int(cfg["map_w"]) >= 80 and int(cfg["map_h"]) >= 60,
			"карта города увеличена (%dx%d)" % [int(cfg["map_w"]), int(cfg["map_h"])])
	# --- здания и профессии M10 ---
	var bld_ids := {}
	for b: Dictionary in cfg["buildings"]:
		bld_ids[String(b["id"])] = b
	_check(bld_ids.has("orchard") and bld_ids.has("market"), "есть яблоневый сад и торговый двор")
	_check(String(bld_ids["market"].get("worker", "")) == "trader", "за торговым двором закреплён торговец")
	var prof_ids := {}
	for p: Dictionary in cfg["professions"]:
		prof_ids[String(p["id"])] = true
	_check(prof_ids.has("trader"), "профессия торговца есть")
	# --- конфиги фермерства/скота/рынка ---
	_check(cfg.has("farming") and int(cfg["farming"]["stages"]) >= 3, "конфиг посевов: стадии роста")
	_check(cfg.has("livestock") and float(cfg["livestock"]["cells_per_animal"]) > 0,
			"конфиг скота: ёмкость пастбища от клеток")
	_check(cfg.has("market") and (cfg["market"]["deals"] as Array).size() >= 3,
			"конфиг рынка: сделки караванов мэра")
	# --- логика: симуляция города headless ---
	var city_sim = load("res://scripts/city_sim.gd").new()
	var cmap = load("res://scripts/city_map.gd").new()
	cmap.generate(777, cfg)
	city_sim.setup(cmap, cfg, 6, "normal")
	_check(float(city_sim.res.get("seeds", 0.0)) >= float(cfg["farming"]["start_seeds"]),
			"стартовые семена выданы")
	# пастбище: ёмкость = клетки/4
	var pasture := {"id": 1, "type": "pasture", "cells": [], "progress": []}
	for i in 16:
		pasture["cells"].append(Vector2i(5 + i % 4, 5 + i / 4))
		pasture["progress"].append(9.0)
	_check(city_sim.pasture_capacity(pasture) == 4, "ёмкость пастбища: 16 клеток -> 4 места")
	# разведение ограничено ёмкостью (не геометрическая прогрессия)
	city_sim.zones.append(pasture)
	for i in 2:
		city_sim.livestock.append({"id": i + 1, "kind": "sheep", "pasture": 1,
				"pos": Vector2(160, 160), "target": Vector2i.ZERO, "path": PackedVector2Array(),
				"idle": 0.0, "adult": true, "age": 99.0})
	city_sim._event_rng.seed = 20260101
	for i in 60:
		city_sim._roll_livestock()
	_check(city_sim.livestock.size() >= 3, "приплод появляется (пара взрослых даёт детёнышей)")
	_check(city_sim.livestock.size() <= 4, "приплод не превысил ёмкость пастбища")
	# поле: посев -> рост -> урожай возвращает семя и даёт еду
	var field := {"id": 2, "type": "field", "cells": [Vector2i(10, 10), Vector2i(11, 10)],
			"progress": [9.0, 9.0], "crops": [{}, {}]}
	city_sim.zones.append(field)
	city_sim.res["seeds"] = 10.0
	city_sim.res["food"] = 10.0   # освобождаем склад: иначе урожай упрётся в кап
	var food0 := float(city_sim.res["food"])
	var day_len := float(cfg["day_length"])
	for i in 30:
		city_sim._update_zones(day_len / 2.0, day_len)
	_check(float(city_sim.res["food"]) > food0, "поле дало урожай через стадии роста")
	_check(float(city_sim.res["seeds"]) >= 8.0, "урожай возвращает семена (цикл замкнулся)")
	# рынок и караваны мэра
	_check(not city_sim.market_ready(), "без торгового двора рынка нет")
	city_sim.buildings.append({"id": 99, "type": "market", "tile": Vector2i(3, 3), "done": true,
			"progress": 0.0, "worker": 3, "enchant": "", "ench_mult": 1.0, "stun_left": 0.0, "hp": 999.0})
	_check(city_sim.market_ready(), "торговый двор с торговцем открывает рынок")
	city_sim.res["food"] = 100.0
	var food_deal := {}
	for d: Dictionary in (cfg["market"]["deals"] as Array):
		if String(d["res"]) == "food":
			food_deal = d
	_coins_log.clear()
	city_sim.coins_sink = func(n: int) -> void: _coins_log.append(n)
	var quick_deal: Dictionary = food_deal.duplicate()
	quick_deal["days"] = 1   # чтобы проверить возврат одним дневным тиком
	var sent: String = city_sim.send_caravan(quick_deal)
	_check(sent == "" and city_sim.caravans_out.size() == 1, "мэр отправил караван по сделке")
	_check(float(city_sim.res["food"]) < 100.0, "товар каравана списан со склада")
	city_sim.cfg["market"]["loss_chance"] = 0.0
	city_sim._tick_caravans()
	_check(city_sim.caravans_out.is_empty() and not _coins_log.is_empty() and _coins_log[0] > 0,
			"караван вернулся с прибылью (монеты через колбэк)")
	city_sim.res["food"] = 100.0
	var sent2: String = city_sim.send_caravan(quick_deal)
	_check(sent2 == "", "второй караван тоже отправлен")
	city_sim.cfg["market"]["loss_chance"] = 1.0
	city_sim._tick_caravans()
	_check(city_sim.caravans_out.is_empty() and _coins_log.size() == 1,
			"караван с риском 100% разграблен — монет нет")
	# торговля с пришедшим караваном (монеты <-> пул)
	city_sim.caravan_here = true
	var purse := {"coins": 100}   # лямбды захватывают по значению — нужен словарь
	city_sim.coins_source = func() -> int: return int(purse["coins"])
	city_sim.coins_sink = func(n: int) -> void: purse["coins"] = int(purse["coins"]) + n
	var price := int(ceilf(city_sim.caravan_price("food")))
	var buy_err: String = city_sim.market_buy("food", 10)
	_check(buy_err == "" and int(purse["coins"]) == 100 - price * 10, "покупка у каравана за монеты")
	var sell_err: String = city_sim.market_sell("food", 10)
	_check(sell_err == "" and int(purse["coins"]) > 100 - price * 10, "продажа каравану приносит монеты")
	city_sim.caravan_here = false
	_check(city_sim.market_buy("food", 1) == "no_caravan", "без каравана торговли нет")
	# --- гуляй-город на карте мира ---
	var wcfg: Dictionary = _read_json("res://data/world.json")
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(4242, wcfg)
	var trade_camp_n := 0
	var camp_poi := {}
	for poi in wmap.pois:
		if String(poi["kind"]) == "trade_camp":
			trade_camp_n += 1
			camp_poi = poi
	_check(trade_camp_n >= 1, "лагерь торговцев размещён на карте мира")
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, wcfg)
	_check(wsim.poi_enterable(camp_poi), "в лагерь торговцев можно войти")
	_check(wsim.trade_discount(camp_poi) < 1.0, "у лагеря торговцев цены со скидкой")
	_check(not wsim.is_combat_poi(camp_poi), "лагерь торговцев — не боевая точка")
	_check(int(wcfg["pois"].get("trade_camps", 0)) >= 1, "число гуляй-городов задаётся в world.json")
	# --- локализация новых строк ---
	var loc_data: Dictionary = _read_json("res://loc/ru.json")
	for key in ["res.seeds", "bld.orchard", "bld.market", "prof.trader", "market.title",
			"market.deal", "market.err_no_market", "city.caravan_arrived_toast",
			"city.livestock_tame_toast", "world.poi.trade_camp", "world.hint_trade_camp",
			"biome.bandit_camp", "enemy.bandit", "enemy.bandit_chief",
			"camp.trade_title", "camp.hint_trade", "animal.sheep", "animal.chick",
			"chron.caravan_returned", "chron.livestock_born",
			# --- M13: бестиарий, замки драконов, пары и праздник ---
			"enemy.ghoul", "enemy.wraith", "enemy.imp", "enemy.hellcaller", "enemy.fallen",
			"enemy.dragon_whelp", "enemy.seraph_of_ash", "enemy.demon_lord",
			"enemy.ancient_dragon", "biome.cursed_hall", "biome.demon_lair",
			"biome.dragon_lair", "world.poi.dragon_castle", "world.hint_dragon_castle",
			"chron.widow", "chron.found_day", "chron.found_skip", "story.widow_toast",
			"city.found_day_toast", "city.found_skip_toast",
			"love.0", "love.1", "love.2", "love.3",
			"fest.0", "fest.1", "fest.2", "fest.3"]:
		_check(loc_data.has(key) and String(loc_data[key]).length() > 0, "ключ локализации: " + key)
	# --- новые и правленые скрипты компилируются ---
	for path in ["res://scripts/world_camp.gd", "res://scripts/city_sim.gd",
			"res://scripts/assets.gd", "res://scripts/city_view.gd", "res://scripts/city_terrain.gd",
			"res://scripts/enemy.gd", "res://scripts/hero.gd", "res://scripts/world.gd",
			"res://scripts/world_sim.gd", "res://scripts/world_map.gd", "res://scripts/city_hud.gd",
			"res://scripts/city.gd", "res://scripts/world_view.gd", "res://scripts/world_hud.gd"]:
		var s: Variant = load(path)
		_check(s != null and (s as Script).can_instantiate(), path.get_file() + " компилируется")
	_check(FileAccess.file_exists("res://scenes/trade_camp.tscn"), "сцена лагеря торговцев есть")


