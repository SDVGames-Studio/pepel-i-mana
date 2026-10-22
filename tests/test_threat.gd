# Угрозы: волны и осады, запретная школа, мутант-лес, оборона, добытчики.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_threat() -> void:
	print("[Угрозы и оборона]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0   # автоплан волн отключён — зовём вручную
	_check(not sim.raid_active and sim.raiders.is_empty(), "старт: атак нет")
	_check(sim.threat_value() >= 0.0, "угроза считается с первого дня")
	_check(String(sim.threat_stage()) == "calm", "стадия на старте — «тихо»")
	# кривая угрозы: время и рост города её поднимают
	var t0: float = sim.threat_value()
	sim.time += 20.0 * float(sim.cfg["day_length"])
	sim.day = 21
	var grown_by_time: float = sim.threat_value() - t0
	_check(grown_by_time > 0.5, "угроза растёт со временем (+%.2f за 20 дней)" % grown_by_time)
	sim._last_daily_day = 999   # дневные броски (автостройка/беженцы) в тесте выключены
	var farm := _build_at(sim, "farm", _find_free_tile(sim, sim.map.spawn_tile))
	_check(bool(farm["done"]), "ферма построена")
	var grown_by_city: float = sim.threat_value() - t0
	_check(grown_by_city > grown_by_time, "готовые здания добавляют угрозы")

	# ворота: со стражем у вышки открыты (стройки — ДО волны: страх режет работу)
	var gate_tile := Vector2i(-1, -1)
	for off in sim._gate_offsets():
		var t: Vector2i = sim.map.spawn_tile + (off as Vector2i)
		# этап 2: ворота держат 3 клетки до дома (правило стены) — ищем годную
		if sim.is_buildable_tile(t) and sim.placement_gap_ok("gate", t):
			gate_tile = t
			break
	_check(gate_tile != Vector2i(-1, -1), "нашёлся проём под ворота")
	var gate := _build_at(sim, "gate", gate_tile)
	_check(bool(gate["done"]), "ворота достроены")
	var tower_g := _build_at(sim, "tower", _find_free_tile(sim, gate_tile, "tower"))
	_check(bool(tower_g["done"]), "вышка у ворот достроена")
	var guard_g: Dictionary = _resident_by_prof(sim, "guard")
	_teleport(sim, guard_g, tower_g["tile"])
	for i in 6:   # выйти из сплошной вышки (2×2) и встать на вход
		sim.tick(0.5)
	_check(sim._gate_open(gate), "страж на ближней вышке открывает ворота")

	# волна: прямым вызовом (детерминированно)
	var mood_before: float = float(sim.residents[0]["mood"])
	sim._spawn_raid(3, false)
	_check(sim.raid_active, "волна началась")
	_check(sim.raiders.size() == 3, "в волне 3 мутанта")
	_check(sim.raid_count == 1, "счётчик волн увеличился")
	_check(float(sim.residents[0]["mood"]) < mood_before, "город напуган атакой")
	sim._spawn_raid(1, false)
	_check(not sim._gate_open(gate), "при атаке ворота захлопнуты")
	# отбитая волна: конец, награда, событие
	sim.raiders.clear()
	sim._raid_end(true)
	var crystal_before: int = int(sim.res["crystal"])
	sim._spawn_raid(1, false)
	sim.raiders.clear()
	sim._raid_end(true)
	_check(not sim.raid_active, "волна кончилась, когда мутантов не осталось")
	_check(int(sim.res["crystal"]) > crystal_before, "за отбитую атаку — кристаллы")
	var repelled_seen := false
	for ev in sim.events:
		if String(ev["type"]) == "raid_repelled":
			repelled_seen = true
	_check(repelled_seen, "событие «атака отбита» дошло до сцены")

	# мутант ломает стену (площадь у спавна: строим за её запретным радиусом, v1.20)
	var sim2 := _make_sim()
	sim2._next_raid_at = 999999999.0
	sim2._last_daily_day = 999
	sim2.time = 10.0 * float(sim2.cfg["day_length"])
	var wall_tile: Vector2i = sim2.map.spawn_tile + Vector2i(7, 0)
	while not sim2.is_buildable_rect("wall", wall_tile):
		wall_tile += Vector2i(1, 0)
	var grass_w: Array = _grass_tiles(sim2, wall_tile, 4)
	if not grass_w.is_empty():
		wall_tile = grass_w[0]
	var wall := _build_at(sim2, "wall", wall_tile)
	_check(bool(wall["done"]), "стена у города достроена")
	_check(not sim2.map.is_walkable(wall_tile), "готовая стена непроходима")
	# страж-житель и ополчение дерутся с мутантами — для чистоты осады оставляем
	# только строителя (занят) и старосту, черты обнуляем (храбрые уходят в бой)
	for r in sim2.residents.duplicate():
		if String(r["prof"]) != "builder" and String(r["prof"]) != "elder":
			sim2.residents.erase(r)
	for r in sim2.residents:
		r["traits"] = []
	var brute_tile: Vector2i = sim2.map.nearest_walkable(wall_tile + Vector2i(2, 0))
	sim2._raid_rng.seed = 7   # детерминированный спавн/поведение мутанта (анти-флейк)
	_spawn_one_raider(sim2, "brute", brute_tile)
	var razed_seen := false
	for i in 2600:   # этап 2: рельеф сплошной в A* — обходы длиннее
		sim2.tick(0.2)
		# этап 2, аспект 5: разрушенное здание остаётся руинами
		var wall_now: Dictionary = sim2.building_at(wall_tile)
		if wall_now.is_empty() or bool(wall_now.get("razed", false)):
			razed_seen = true
			break
	_check(razed_seen, "осадный мутант разрушил стену")
	_check(sim2.map.is_walkable(wall_tile), "на месте стены снова можно ходить")
	_check(int(sim2.razed_this_raid) >= 1, "разрушение учтено в счёте осады")
	# норма потерь набрана — осада удалась, мутанты уходят, город жив
	var defeat_razes: int = int(sim2.cfg["threat"]["defeat_razes"])
	sim2.razed_this_raid = defeat_razes
	sim2._spawn_raid(1, false)
	sim2.razed_this_raid = defeat_razes
	sim2.tick(0.1)
	_check(not sim2.raid_active, "волна уходит, когда разрушена норма зданий")
	_check(sim2.residents.size() > 0, "провал осады не убивает игру")

	# вышка со стражем отстреливает мутанта
	var sim3 := _make_sim()
	sim3._next_raid_at = 999999999.0
	sim3._last_daily_day = 999
	sim3.time = 10.0 * float(sim3.cfg["day_length"])
	var tower := _build_now(sim3, "tower")
	_check(bool(tower["done"]), "вышка построена")
	var guard: Dictionary = _resident_by_prof(sim3, "guard")
	_check(int(tower["worker"]) == int(guard["id"]), "страж закреплён за вышкой")
	_teleport(sim3, guard, tower["tile"])
	# ополчение перебило бы мутанта раньше вышки — оставляем стража и строителя
	for r in sim3.residents.duplicate():
		if not (r == guard or String(r["prof"]) == "builder"):
			sim3.residents.erase(r)
	for r in sim3.residents:
		r["traits"] = []
	_spawn_one_raider(sim3, "mutant", tower["tile"] + Vector2i(3, 0))
	for i in 150:
		sim3.tick(0.2)
		if sim3.raiders.is_empty():
			break
	_check(sim3.raiders.is_empty(), "вышка со стражем отстрелила мутанта")

	# удар героя в городе
	var sim4 := _make_sim()
	sim4._next_raid_at = 999999999.0
	sim4._last_daily_day = 999
	var target := _spawn_one_raider(sim4, "mutant", sim4.map.spawn_tile + Vector2i(1, 0))
	var hp_before: int = int(target["hp"])
	var hits: int = sim4.hero_slash(sim4.map.tile_center_px(sim4.map.spawn_tile),
			Vector2.RIGHT, 60.0, 90.0, 5)
	_check(hits >= 1, "герой задел мутанта в дуге удара")
	_check(int(target["hp"]) < hp_before, "урон героя дошёл до мутанта")
	var misses: int = sim4.hero_slash(sim4.map.tile_center_px(sim4.map.spawn_tile),
			Vector2.LEFT, 60.0, 90.0, 5)
	_check(misses == 0, "удар в другую сторону не задевает")

	# магическая буря: предупреждение, удары по зданиям, рост порчи
	var sim5 := _make_sim()
	sim5._next_raid_at = 999999999.0
	sim5._last_daily_day = 999
	var barn := _build_now(sim5, "warehouse")
	_check(bool(barn["done"]), "склад построен под удар бури")
	sim5.storm_state = "warn"
	sim5.storm_left = 0.1
	sim5.tick(0.2)
	_check(String(sim5.storm_state) == "active", "после предупреждения буря началась")
	var struck := false
	for i in 200:
		sim5.tick(0.5)
		var cur: Dictionary = sim5.building_at(barn["tile"])
		if cur.is_empty() or float(cur["hp"]) < float(sim5._bld_max_hp("warehouse")):
			struck = true
			break
	_check(struck, "буря бьёт по зданиям")
	_check(sim5.pollution > 0.0, "буря растит загрязнение")
	# «Оберег» защищает: кроме зачарованного склада есть незаищищённая ферма
	var sim6 := _make_sim()
	sim6._next_raid_at = 999999999.0
	sim6._last_daily_day = 999
	var warded := _build_now(sim6, "warehouse")
	warded["enchant"] = "ward"
	_build_now(sim6, "farm")
	var day_len: float = float(sim6.cfg["day_length"])
	sim6.storm_state = "active"
	sim6.storm_left = 2.0 * day_len
	sim6._storm_struck_at = sim6.time - day_len
	var farm_ever_struck := false
	for i in 80:
		sim6.tick(0.5)
		# этап 2, аспект 5: удар может и разрушить — здание остаётся руинами
		var farm_now: Dictionary = sim6.building_at(_ward_test_farm_tile(sim6))
		if farm_now.is_empty() or bool(farm_now.get("razed", false)) \
				or float(farm_now["hp"]) < float(sim6._bld_max_hp("farm")):
			farm_ever_struck = true
	_check(farm_ever_struck, "удары бури уходят в незаищищённые здания")
	var warded_now: Dictionary = sim6.building_at(warded["tile"])
	_check(not warded_now.is_empty() and float(warded_now["hp"]) >= float(sim6._bld_max_hp("warehouse")),
			"«Оберег» оберегает здание от удара бури")

	# планировщик волн: предупреждение заранее, старт по расписанию
	var sim7 := _make_sim()
	sim7._last_daily_day = 999
	sim7.time = 13.0 * float(sim7.cfg["day_length"])
	sim7.day = 14
	sim7._next_raid_at = sim7.time + 1.0
	sim7.tick(0.1)
	_check(sim7._raid_warned, "предупреждение о волне объявлено заранее")
	var warn_seen := false
	for ev in sim7.events:
		if String(ev["type"]) == "raid_warn":
			warn_seen = true
	_check(warn_seen, "событие-предупреждение ушло в сцену")
	sim7.events.clear()
	sim7.tick(1.5)
	_check(sim7.raid_active and sim7.raiders.size() >= 1, "волна началась по расписанию")


## Тайл фермы в sim6 теста бури (первое готовое здание без «Оберега»).
func _test_forbidden_school() -> void:
	print("[Запретная школа]")
	var magic: Variant = _read_json("res://data/magic.json")
	var schools := {}
	for s: Dictionary in magic["schools"]:
		schools[String(s["id"])] = s
	_check(schools.has("forbidden"), "школа «запретная» есть в data/magic.json")
	var magic_obj = load("res://scripts/magic.gd").new()
	magic_obj.setup(magic)
	# рецепты из существующих рун
	_check(String(magic_obj.recipe_result("rune_shadow", "rune_chaos")) == "corrupt_blast",
			"тень+хаос = Порча-взрыв")
	_check(String(magic_obj.recipe_result("rune_shadow", "rune_shadow")) == "plague",
			"тень+тень = Чума")
	_check(String(magic_obj.recipe_result("rune_chaos", "rune_frost")) == "drain_life",
			"хаос+стужа = Вытягивание жизни")
	var spells := {}
	for sp: Dictionary in magic["spells"]:
		spells[String(sp["id"])] = sp
	for id in ["corrupt_blast", "plague", "drain_life"]:
		_check(spells.has(id), "заклинание «%s» описано" % id)
		if spells.has(id):
			_check(String(spells[id]["school"]) == "forbidden", "%s — запретная школа" % id)
			_check(float(spells[id].get("pollution", 0.0)) > 0.0,
					"%s имеет цену: порчу города" % id)
	# мутанты уязвимы к запретной школе
	var enemies: Array = _read_json("res://data/enemies.json")
	var by_id := {}
	for e: Dictionary in enemies:
		by_id[String(e["id"])] = e
	var enemy_script: Script = load("res://scripts/enemy.gd")
	for m in ["mutant", "brute", "spitter"]:
		_check(by_id.has(m), "враг «%s» есть в данных" % m)
		if by_id.has(m):
			_check(String(by_id[m]["weak_school"]) == "forbidden", "%s уязвим к запретной школе" % m)
	_check(int(enemy_script.calc_spell_damage(by_id["mutant"], 4, "forbidden")) == 8,
			"запретная школа бьёт мутанта ×2")
	# каст городских проверок не требует — портит город при касте в данже:
	# полю pollution у заклинаний доверяет dungeon.gd (строки каста), тут проверяем сим
	var sim := _make_sim()
	var pol0: float = sim.pollution
	sim.add_pollution(float(spells["corrupt_blast"]["pollution"]))
	_check(sim.pollution > pol0, "цена запретной школы растит загрязнение города")


func _test_mutant_forest() -> void:
	print("[Лес-мутант: биом данжа]")
	var params: Variant = _read_json("res://data/dungeon.json")
	_check(params.has("biomes") and params.has("biome_weights"), "биомы и веса описаны в data/dungeon.json")
	var biomes: Dictionary = params["biomes"]
	_check(biomes.has("ruins") and biomes.has("mutant_forest"), "ровно два биома: руины и лес-мутант")
	var mf: Dictionary = biomes["mutant_forest"]
	for key in ["floor_color", "wall_color", "ambient", "enemy_weights", "loot_bonus", "pollution_on_visit"]:
		_check(mf.has(key), "у леса-мутанта есть «%s»" % key)
	_check(int(mf.get("loot_bonus", 0)) > 0, "лес-мутант жирнее по луту")
	_check(float(mf.get("pollution_on_visit", 0.0)) > 0.0, "визит в лес портит город")
	var weights: Dictionary = mf["enemy_weights"]
	_check(int(weights.get("mutant", 0)) > 0 and int(weights.get("brute", 0)) > 0,
			"в лесу живут мутанты и осадные громилы")
	# генератор данжа работает на структуре без старого ключа "biome"
	var gen = load("res://scripts/dungeon_gen.gd").new()
	var cfg: Dictionary = params
	gen.generate(13, cfg)
	_check(gen.rooms.size() >= 2, "генератор строит данж на новых данных биомов")
	var dungeon_script: Script = load("res://scripts/dungeon.gd")
	_check(dungeon_script.can_instantiate(), "скрипт данжа парсится (выбор биома внутри)")


# --- M6: зоны, дороги, физическая логистика ----------------------------------

## Первые n тайлов чистой травы рядом с точкой (для зон и дорог в тестах).
func _test_defense() -> void:
	print("[M5.1: железо, охота, стражи, комплекты]")
	var sim := _make_sim()
	# размещения: шахта — на руде, пирс — у воды, оружейная — у кузни
	var ore_tile: Vector2i = _ore_tile_of(sim)
	_check(ore_tile != Vector2i(-1, -1), "на карте есть рудные жилы")
	_check(sim.placement_block("mine", ore_tile) == "", "шахта ставится на руду")
	_check(sim.placement_block("mine", sim.map.spawn_tile) != "", "шахта не ставится на траву")
	var miner_r := _add_resident(sim, "Герд", "miner")   # шахтёр должен быть ДО достройки
	var mine := _build_at(sim, "mine", ore_tile)
	print("DBG mine: done=", mine.get("done"), " empty=", mine.is_empty(), " res=", sim.res,
			" worker=", mine.get("worker"), " tile=", mine.get("tile"))
	_check(bool(mine["done"]), "шахта построена прямо на жиле")
	_teleport(sim, miner_r, mine["tile"])
	var pier_tile := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] != sim.map.TILE_WATER:
				continue
			for n in [Vector2i(x, y) + Vector2i(1, 0), Vector2i(x, y) + Vector2i(-1, 0),
					Vector2i(x, y) + Vector2i(0, 1), Vector2i(x, y) + Vector2i(0, -1)]:
				if sim.is_buildable_tile(n, "pier") and sim.placement_block("pier", n) == "":
					pier_tile = n
					break
			if pier_tile != Vector2i(-1, -1):
				break
		if pier_tile != Vector2i(-1, -1):
			break
	_check(pier_tile != Vector2i(-1, -1), "у воды нашлось место под пирс")
	_check(sim.placement_block("pier", sim.map.spawn_tile) != "", "пирс вдали от воды не ставится")
	var forge := _build_at(sim, "forge", _find_free_tile(sim, sim.map.spawn_tile))
	_check(bool(forge["done"]), "кузня построена")
	var near_forge: Vector2i = _find_free_tile(sim, forge["tile"], "armory")
	_check(sim.placement_block("armory", near_forge) == "", "оружейная ставится рядом с кузней")
	var far_tile: Vector2i = _find_free_tile(sim, sim.map.spawn_tile + Vector2i(10, 0))
	_check(sim.placement_block("armory", far_tile) != "", "оружейная вдали от кузни не ставится")

	# цепочка металла: руда → металл → инструменты/комплекты
	# (тики копят время: тест уходит в ночь — возвращаем утро, иначе рабочие спят)
	# M6: всё производство оседает кучами у зданий, в пул его сносит носильщик
	sim.time = 10.0
	sim.tick(20.0)
	_check(float((mine["pile"] as Dictionary).get("iron", 0.0)) > 0.0, "шахта добывает руду в кучу у здания")
	var smelter_r := _add_resident(sim, "Ада", "smelter")
	var smelt := _build_at(sim, "smelter", _find_free_tile(sim, sim.map.spawn_tile))
	_check(bool(smelt["done"]) and int(smelt["worker"]) == int(smelter_r["id"]), "плавильщик в плавильне")
	sim.time = 10.0
	sim.res["iron"] = 20.0
	sim.res["metal"] = 0.0
	_teleport(sim, smelter_r, smelt["tile"])
	for i in 8:   # выйти из сплошной плавильни (2×2) и встать на вход
		sim.tick(4.0)
	_check(float((smelt["pile"] as Dictionary).get("metal", 0.0)) > 0.0, "плавильня превращает руду в металл (куча)")
	sim.time = 10.0
	var smith_r := _add_resident(sim, "Борн", "smith")
	sim.res["metal"] = 10.0
	sim.res["tools"] = 0.0
	_teleport(sim, smith_r, forge["tile"])
	for i in 10:   # выйти из сплошной кузни (2×2) и ковать на входе
		sim.tick(3.0)
	_check(float((forge["pile"] as Dictionary).get("tools", 0.0)) > 0.0, "кузня куёт металлические инструменты (куча)")
	sim.res["stone"] = 30.0   # плавильня и кузня съели весь камень
	sim.res["metal"] = 20.0
	# оружейная требует кузню в радиусе 2 по прямой — ищем такой тайл честно
	var armory_tile := Vector2i(-1, -1)
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t: Vector2i = (forge["tile"] as Vector2i) + Vector2i(dx, dy)
				if sim.is_buildable_rect("armory", t) and sim.placement_block("armory", t) == "":
					armory_tile = t
					break
			if armory_tile != Vector2i(-1, -1):
				break
		if armory_tile != Vector2i(-1, -1):
			break
	_check(armory_tile != Vector2i(-1, -1), "рядом с кузней нашлось место под оружейную")
	var armorer_r := _add_resident(sim, "Нива", "armorer")   # работник до достройки
	var armory := _build_at(sim, "armory", armory_tile)
	_check(bool(armory["done"]), "оружейная построена у кузни")
	sim.res["metal"] = 20.0
	sim.res["kits"] = 0.0
	sim.time = 10.0
	_teleport(sim, armorer_r, armory["tile"])
	for i in 12:   # выйти из сплошной оружейной (2×2) и работать на входе
		sim.tick(5.0)
	_check(float((armory["pile"] as Dictionary).get("kits", 0.0)) > 0.0, "оружейная собирает боевые комплекты (куча)")

	# охота: охотник добывает зверя, еда в пул (зверь бродит — даём время на погоню)
	var sim_h := _make_sim()
	sim_h._last_daily_day = 999
	_check(not sim_h.animals.is_empty(), "зверь ходит по карте")
	var hunter_r := _add_resident(sim_h, "Ярл", "hunter")
	var prey: Dictionary = sim_h.animals[0]
	# M14-C: волки в городе охотятся на зверей — убираем их, чтобы не съели добычу теста
	sim_h.animals = sim_h.animals.filter(
			func(a: Dictionary) -> bool: return String(a.get("kind", "deer")) != "wolf")
	prey = sim_h.animals[0]
	prey["kind"] = "deer"
	_teleport(sim_h, hunter_r, sim_h.map.tile_of_px(prey["pos"]))
	var food0: float = float(sim_h.res["food"])
	var animals0: int = sim_h.animals.size()
	for i in 300:
		if sim_h.time > 70.0:
			sim_h.time = 10.0   # не уходить в ночь: охотник уснёт
		sim_h.tick(0.5)
		if sim_h.animals.size() < animals0:
			break
	_check(float(sim_h.res["food"]) > food0, "охотник принёс еду")
	_check(sim_h.animals.size() < animals0, "зверь добыт")

	# стражи: двое на постоянке, смены день/ночь
	var sim_g2 := _make_sim()
	sim_g2._last_daily_day = 0
	sim_g2.tick(0.2)
	var guards := 0
	var shifts := {}
	for r in sim_g2.residents:
		if String(r["prof"]) == "guard":
			guards += 1
			shifts[String(r.get("shift", "day"))] = true
	_check(guards >= 2, "на постоянке минимум двое стражей")
	_check(shifts.has("day") and shifts.has("night"), "смены: дневная и ночная")

	# ополчение: свободный житель бьёт мутанта
	var sim_m2 := _make_sim()
	sim_m2._last_daily_day = 999
	var fighter: Dictionary = _resident_by_prof(sim_m2, "acolyte")
	fighter["traits"] = []
	var raider_m := _spawn_one_raider(sim_m2, "mutant", sim_m2.map.spawn_tile + Vector2i(2, 0))
	_teleport(sim_m2, fighter, sim_m2.map.spawn_tile + Vector2i(1, 0))
	var hp_m0: int = int(raider_m["hp"])
	sim_m2.tick(0.3)
	_check(int(raider_m["hp"]) < hp_m0, "ополченец бьёт мутанта")

	# комплект: боец берёт его в оружейке и бьёт вдвое сильнее
	var sim_k2 := _make_sim()
	sim_k2._last_daily_day = 999
	sim_k2.res["metal"] = 20.0
	sim_k2.res["stone"] = 30.0
	for r in sim_k2.residents.duplicate():
		if not (String(r["prof"]) in ["acolyte", "builder", "elder"]):
			sim_k2.residents.erase(r)
	for r in sim_k2.residents:
		r["traits"] = []
	var forge_k := _build_at(sim_k2, "forge", _find_free_tile(sim_k2, sim_k2.map.spawn_tile))
	var armory_k_tile := Vector2i(-1, -1)
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t: Vector2i = (forge_k["tile"] as Vector2i) + Vector2i(dx, dy)
				if sim_k2.is_buildable_rect("armory", t) and sim_k2.placement_block("armory", t) == "":
					armory_k_tile = t
					break
			if armory_k_tile != Vector2i(-1, -1):
				break
		if armory_k_tile != Vector2i(-1, -1):
			break
	_check(armory_k_tile != Vector2i(-1, -1), "в кит-тесте нашлось место у кузни")
	var armory_k := _build_at(sim_k2, "armory", armory_k_tile)
	_check(bool(armory_k["done"]), "оружейная в кит-тесте построена")
	# строитель больше не нужен: он тоже ополченец и перехватил бы комплект и мутанта
	for r in sim_k2.residents.duplicate():
		if String(r["prof"]) == "builder":
			sim_k2.residents.erase(r)
	var soldier: Dictionary = _resident_by_prof(sim_k2, "acolyte")
	# подмена M4 могла усадить ученика в кузню/оружейную — освобождаем бойца
	if soldier["bld"] != null:
		(soldier["bld"] as Dictionary)["worker"] = -1
	if soldier["site"] != null:
		(soldier["site"] as Dictionary)["worker"] = -1
	soldier["bld"] = null
	soldier["site"] = null
	soldier["sub_prof"] = ""
	sim_k2.res["kits"] = 1.0
	_teleport(sim_k2, soldier, armory_k["tile"])
	# волна живёт, но рейдер далеко (у аномалии): боец успевает снарядиться
	var raider_k := _spawn_one_raider(sim_k2, "mutant", sim_k2.map.anomaly_tile)
	sim_k2.tick(0.1)
	_check(bool(soldier.get("kit", false)) and float(sim_k2.res["kits"]) == 0.0,
			"боец взял комплект в оружейке")
	_teleport(sim_k2, raider_k, armory_k["tile"] + Vector2i(1, 0))
	_teleport(sim_k2, soldier, armory_k["tile"])
	var hp_k0: int = int(raider_k["hp"])
	sim_k2.tick(0.3)
	_check(hp_k0 - int(raider_k["hp"]) == 2, "с комплектом удар вдвое сильнее (1×2)")

	# трус прячется уже при предупреждении
	var sim_c2 := _make_sim()
	sim_c2._last_daily_day = 999
	var coward: Dictionary = _resident_by_prof(sim_c2, "farmer")
	coward["traits"] = ["coward"]
	sim_c2._raid_warned = true
	sim_c2.tick(0.1)
	_check(String(coward["state"]) == "hide", "трус прячется с момента предупреждения")

	# расписание волн (правка 2026-10-21): ровный интервал из конфига, волны
	# ослаблены — размера и здоровья с номером волны почти не добавляется
	var sim_w2 := _make_sim()
	sim_w2._last_daily_day = 999
	sim_w2._next_raid_at = 999999999.0
	sim_w2._spawn_raid(1, false)
	sim_w2.raiders.clear()
	sim_w2._raid_end(true)
	var eta: float = sim_w2.raid_eta_days()
	_check(absf(eta - float(sim_w2.cfg["threat"]["raid_every_days"])) < 0.1,
			"после волны следующая через %.1f дня (ровный интервал)" % eta)
	sim_w2._spawn_raid(1, false)
	var r2: Dictionary = sim_w2.raiders[0]
	var expected: int = int(round(float(r2["p"]["hp"]) * (1.0 + sim_w2.threat_value()
			* float(sim_w2.cfg["threat"]["hp_per_threat"]) + 1.0 * float(sim_w2.cfg["threat"]["wave_growth_hp"]))))
	_check(int(r2["max_hp"]) == expected, "волна крепчает только по формуле конфига")

	# данж: зачистка закрывает его на 10 дней, герой носит комплекты
	var game3: Node = load("res://scripts/game.gd").new()
	_check(game3.dungeon_available(0), "новый данж доступен")
	game3.register_dungeon_clear(5, 10)
	_check(game3.dungeon_clears == 1, "зачистка посчитана")
	_check(not game3.dungeon_available(10), "сразу после зачистки данж закрыт")
	_check(game3.dungeon_available(15), "через 10 дней данж снова работает")
	game3.free()
	var game4: Node = load("res://scripts/game.gd").new()
	var sim_k3 := _make_sim()
	sim_k3.res["metal"] = 10.0
	_check(String(game4.buy_hero_kit(sim_k3.cfg, sim_k3)) == "", "герой купил комплект")
	_check(int(game4.hero_kits) == 1 and float(sim_k3.res["metal"]) == 7.0, "металл списан за комплект")
	var kit_bonus: Dictionary = game4.hero_kit_bonus(sim_k3.cfg)
	_check(int(kit_bonus["damage"]) == 2 and int(kit_bonus["armor"]) == 1, "комплект: +2 урона, +1 броня")
	game4.buy_hero_kit(sim_k3.cfg, sim_k3)
	game4.buy_hero_kit(sim_k3.cfg, sim_k3)
	_check(String(game4.buy_hero_kit(sim_k3.cfg, sim_k3)) == "armory_max", "больше трёх комплектов нельзя")
	sim_k3.res["metal"] = 0.0
	var game5: Node = load("res://scripts/game.gd").new()
	_check(String(game5.buy_hero_kit(sim_k3.cfg, sim_k3)) == "no_metal", "без металла комплект не собрать")
	game4.free()
	game5.free()

	# стартовый город: герой начинает ОДИН + голем-староста у площади (v1.20)
	var game6: Node = load("res://scripts/game.gd").new()
	game6.new_city()
	_check(game6.city_sim.residents.size() == 2, "новый город: основатель + голем-староста")
	_check(game6.city_sim.pop_cap() >= 2, "лимит жителей вмещает основателя и голема")
	game6.free()

	# страж вне смены помогает на стройке (заказчик: стража тоже должна помогать)
	var sim_gh := _make_sim()
	sim_gh._last_daily_day = 999
	var guard_h: Dictionary = _resident_by_prof(sim_gh, "guard")
	guard_h["shift"] = "night"   # сейчас день — он вне смены
	var site_tile: Vector2i = _find_free_tile(sim_gh, sim_gh.map.spawn_tile)
	sim_gh.place_building("wall", site_tile)
	_teleport(sim_gh, guard_h, site_tile)
	sim_gh.time = 10.0
	var prog0: float = float(sim_gh.building_at(site_tile)["progress"])
	sim_gh.tick(1.0)
	_check(float(sim_gh.building_at(site_tile)["progress"]) > prog0,
			"страж вне смены помогает строить")

	# волны не выходят раньше 10-го дня, как бы ни разросся город (на 4-й день пришла)
	var sim_e1 := _make_sim()
	sim_e1._last_daily_day = 999
	sim_e1.time = 5.0 * float(sim_e1.cfg["day_length"])
	sim_e1.day = 6
	sim_e1._next_raid_at = sim_e1.time + 0.5   # планировщик зовёт волну прямо сейчас
	sim_e1.tick(1.0)
	_check(not sim_e1.raid_active and sim_e1.raiders.is_empty(), "до 10-го дня волн нет")
	sim_e1.time = 10.5 * float(sim_e1.cfg["day_length"])
	sim_e1.day = 11
	sim_e1.cfg["threat"]["min_threat"] = 0.0   # маленький город не откладывает волну
	sim_e1._next_raid_at = sim_e1.time + 0.5
	sim_e1.tick(1.0)
	_check(sim_e1.raid_active, "после 10-го дня волна приходит по расписанию")

	# еда идёт в минус — город строит ферму, даже если запас ещё есть (заказчик)
	var sim_f1 := _make_sim()
	sim_f1._last_daily_day = 0   # дневные броски включены — работает самострой
	# случайные броски M4 в этом тесте не при чём: болезнь старосты или беженец
	# могут сорвать самострой (флаки) — глушим
	sim_f1.people["ailments"]["sick_chance"] = 0.0
	sim_f1.people["refugees"]["chance_per_day"] = 0.0
	sim_f1.people["births"]["chance_per_day"] = 0.0
	sim_f1.people["stories"]["chance_per_day"] = 0.0
	var extra := 0
	while sim_f1.residents.size() < 9:
		var r_x: Dictionary = sim_f1._new_resident("Тар%d" % extra, "farmer", sim_f1.map.spawn_tile)
		sim_f1.residents.append(r_x)
		sim_f1._next_id += 1
		extra += 1
	sim_f1.res["food"] = 200.0   # запас полный — старое правило «меньше дня еды» молчало бы
	var farms_before := 0
	for b in sim_f1.buildings:
		if String(b["type"]) == "farm":
			farms_before += 1
	sim_f1.tick(0.2)
	var farms_after := 0
	var farm_site := false
	for b in sim_f1.buildings:
		if String(b["type"]) == "farm":
			farms_after += 1
			if not bool(b["done"]):
				farm_site = true
	_check(sim_f1._food_deficit(), "баланс еды отрицательный (9 ртов против одной фермы)")
	_check(farms_after > farms_before and farm_site, "при дефиците еды заложена ферма")


## Блок M5.4: добыча у источника, туман по линии видимости, бездельники заняты.
func _test_gathering() -> void:
	print("[M5.4: добыча у источника]")
	var sim := _make_sim()
	sim._last_daily_day = 999
	# лесопилка — только у леса
	var tree_side := Vector2i(-1, -1)
	var treeless := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			var t := Vector2i(x, y)
			if not sim.is_buildable_tile(t):
				continue
			if tree_side == Vector2i(-1, -1) and sim._nature_near(t, [sim.map.TILE_TREE], 2.0) != Vector2i(-1, -1) \
					and sim.placement_block("sawmill", t) == "":
				tree_side = t
			if treeless == Vector2i(-1, -1) \
					and sim._nature_near(t, [sim.map.TILE_TREE], 2.0) == Vector2i(-1, -1) \
					and sim._nature_near(t, [sim.map.TILE_ROCK, sim.map.TILE_ORE], 2.0) == Vector2i(-1, -1) \
					and sim._water_near(t) == false:
				treeless = t
	_check(tree_side != Vector2i(-1, -1), "нашлось место у леса")
	_check(sim.placement_block("sawmill", tree_side) == "", "лесопилка ставится у леса")
	_check(treeless != Vector2i(-1, -1) and sim.placement_block("sawmill", treeless) != "",
			"лесопилка вдали от леса не ставится")
	# каменоломня — только у скал
	var rock_side := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			var t := Vector2i(x, y)
			if sim.is_buildable_tile(t) and sim._nature_near(t, [sim.map.TILE_ROCK, sim.map.TILE_ORE], 2.0) != Vector2i(-1, -1) \
					and sim.placement_block("quarry", t) == "":
				rock_side = t
				break
		if rock_side != Vector2i(-1, -1):
			break
	_check(rock_side != Vector2i(-1, -1) and sim.placement_block("quarry", rock_side) == "",
			"каменоломня ставится у скал")
	_check(sim.placement_block("quarry", treeless) != "", "каменоломня вдали от скал не ставится")
	# самострой ищет место у ресурса
	var auto_s: Vector2i = sim._find_autobuild_tile("sawmill")
	_check(auto_s != Vector2i(-1, -1) and sim.placement_block("sawmill", auto_s) == "",
			"самострой лесопилки — у леса")

	# лесоруб рубит именно дерево: уходит из здания к лесу, дерево растёт
	var sim_sg := _make_sim()
	sim_sg._last_daily_day = 999
	_add_resident(sim_sg, "Лана", "lumberjack")   # может быть не он назначен — берём закреплённого
	var stile: Vector2i = _find_free_tile(sim_sg, sim_sg.map.spawn_tile, "sawmill")
	var saw := _build_at(sim_sg, "sawmill", stile)
	_check(bool(saw["done"]), "лесопилка построена у леса")
	var worker_sg: Dictionary = {}
	for r in sim_sg.residents:
		if int(r["id"]) == int(saw["worker"]):
			worker_sg = r
	_check(not worker_sg.is_empty(), "за лесопилкой закреплён лесоруб")
	_teleport(sim_sg, worker_sg, stile)
	sim_sg.time = 10.0
	for i in 6:   # выйти из сплошной лесопилки (2×2), дойти до дерева, рубить
		sim_sg.tick(2.0)
	_check(float((saw["pile"] as Dictionary).get("wood", 0.0)) > 0.0,
			"лесоруб добывает дерево у леса — куча растёт (M6)")
	var ptile: Vector2i = sim_sg.map.tile_of_px(worker_sg["pos"])
	_check(sim_sg.map.grid[ptile.y][ptile.x] == sim_sg.map.TILE_TREE,
			"лесоруб работает прямо у дерева, а не в здании")

	# шахта даёт и руду, и камень (заказчик)
	var sim_mi := _make_sim()
	sim_mi._last_daily_day = 999
	var miner_mi := _add_resident(sim_mi, "Герд", "miner")
	var mtile: Vector2i = _ore_tile_of(sim_mi)
	var mine_mi := _build_at(sim_mi, "mine", mtile)
	_check(bool(mine_mi["done"]), "шахта построена")
	_teleport(sim_mi, miner_mi, mtile)
	sim_mi.time = 10.0
	sim_mi.tick(5.0)
	sim_mi.tick(5.0)
	sim_mi.tick(5.0)
	_check(float((mine_mi["pile"] as Dictionary).get("iron", 0.0)) > 0.0, "шахта даёт железную руду (куча)")
	_check(float((mine_mi["pile"] as Dictionary).get("stone", 0.0)) > 0.0, "шахта даёт и камень (куча)")

	# свободный житель в мирное время помогает строить (много бездельников — заказчик)
	var sim_ih := _make_sim()
	sim_ih._last_daily_day = 999
	var farmer_ih: Dictionary = _resident_by_prof(sim_ih, "farmer")
	var tile_ih: Vector2i = _find_free_tile(sim_ih, sim_ih.map.spawn_tile)
	sim_ih.place_building("wall", tile_ih)
	_teleport(sim_ih, farmer_ih, tile_ih)
	sim_ih.time = 10.0
	var prog_ih: float = float(sim_ih.building_at(tile_ih)["progress"])
	sim_ih.tick(1.0)
	_check(float(sim_ih.building_at(tile_ih)["progress"]) > prog_ih,
			"свободный житель помогает строить")

	# город сам обучает охотника, раз зверь водится (никто не охотился)
	var sim_ht := _make_sim()
	sim_ht._last_daily_day = 0
	var hunter_before := false
	for r in sim_ht.residents:
		if String(r["prof"]) == "hunter":
			hunter_before = true
	_check(not hunter_before, "в стартовом наборе нет охотника")
	sim_ht.tick(0.2)
	var hunter_after := false
	for r in sim_ht.residents:
		if String(r["prof"]) == "hunter":
			hunter_after = true
	_check(hunter_after, "город обучил охотника — охота теперь будет")

	# мутант не проходит сквозь стены и скалы (проходит путь, а не режет насквозь)
	var sim_nc := _make_sim()
	sim_nc._last_daily_day = 999
	sim_nc.hero_alive = true
	sim_nc.hero_pos = sim_nc.map.tile_center_px(sim_nc.map.spawn_tile)
	var wall_nc: Vector2i = sim_nc.map.spawn_tile + Vector2i(3, 0)
	var grass_nc: Array = _grass_tiles(sim_nc, wall_nc, 4)
	if not grass_nc.is_empty():
		wall_nc = grass_nc[0]
	_build_at(sim_nc, "wall", wall_nc)
	var spawn_nc: Vector2i = sim_nc.map.nearest_walkable(wall_nc + Vector2i(1, 0))
	_spawn_one_raider(sim_nc, "mutant", spawn_nc)
	var never_clip := true
	for i in 120:
		sim_nc.tick(0.3)
		if sim_nc.raiders.is_empty():
			break
		var rtile: Vector2i = sim_nc.map.tile_of_px(sim_nc.raiders[0]["pos"])
		if not sim_nc.map.is_walkable(rtile):
			never_clip = false
			break
	_check(never_clip, "мутант не проходит сквозь стены и скалы")


