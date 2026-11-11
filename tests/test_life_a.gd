# Жизнь: вишлист, M12-M13, сейв M14-A.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
# v1.62.0: от Test_life_a (1561 строк) отделены M14-B/D (test_life_a2.gd)
# и M14-E/F (test_life_a3.gd).
extends "res://tests/test_base.gd"

func _test_wishlist() -> void:
	print("[Вишлист M11: лес, скала, некромант]")

	# гряда: единые массивы скал с запасом прочности
	var sim := _make_sim()
	var rocks := 0
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_ROCK:
				rocks += 1
	_check(rocks >= 25, "скальных гряд достаточно (%d тайлов)" % rocks)
	_check(sim.map.rock_hp.size() >= 25, "у тайлов гряды есть запас прочности")

	# вырубка: лесоруб валит дерево — пень, гнев леса
	var sim_f := _make_sim()
	var tree_tile := Vector2i(-1, -1)
	# дерево — из ДОСТИЖИМЫХ от старта (v1.29.4): карта режется рекой, первое
	# по скану дерево могло оказаться на другом берегу без моста — лесоруб
	# до него не дойдёт, и тест ловил флак по сиду
	var reach: Dictionary = sim_f.map._reachable_from(sim_f.map.spawn_tile)
	for y in sim_f.map.h:
		for x in sim_f.map.w:
			if sim_f.map.grid[y][x] == sim_f.map.TILE_TREE \
					and reach.has(Vector2i(x, y)):
				tree_tile = Vector2i(x, y)
				break
		if tree_tile.x >= 0:
			break
	_check(tree_tile != Vector2i(-1, -1), "на карте есть дерево для вырубки")
	# размер дерева малый (v1.29.4): бюджет тиков рассчитан на малое/среднее —
	# первое по скану дерево могло стать большим (1 день рубки) и цикл
	# заканчивался за тик до падения (flak по сдвигу потока RNG)
	sim_f.map.tree_size[tree_tile] = sim_f.map.TREE_SMALL
	sim_f.cfg["piles"] = {"chunk": 2.0, "max": 60.0, "carry": 10.0}
	var spot := Vector2i(-1, -1)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t := tree_tile + Vector2i(dx, dy)
			# этап 2, аспект 2: лесопилка 2×2 — прямоугольник годен и не накрывает дерево
			if not sim_f.is_buildable_rect("sawmill", t) or sim_f.placement_block("sawmill", t) != "":
				continue
			var covers := false
			for cell in sim_f.bld_cells({"type": "sawmill", "tile": t, "w": 2}):
				if cell == tree_tile:
					covers = true
					break
			if not covers:
				spot = t
				break
		if spot != Vector2i(-1, -1):
			break
	_check(spot != Vector2i(-1, -1), "у дерева есть место под лесопилку")
	_check(sim_f.place_building("sawmill", spot), "лесопилка заложена у дерева")
	var builder_f: Dictionary = _resident_by_prof(sim_f, "builder")
	builder_f["mood"] = 100.0
	builder_f["traits"] = []
	_teleport(sim_f, builder_f, spot)
	sim_f.tick(25.5)
	_check(bool(sim_f.building_at(spot)["done"]), "лесопилка достроена")
	var lumberjack: Dictionary = _resident_by_prof(sim_f, "lumberjack")
	_check(not lumberjack.is_empty(), "лесоруб есть среди жителей")
	_teleport(sim_f, lumberjack, tree_tile)
	sim_f.cfg["food_per_resident_day"] = 0.0
	sim_f.time = 10.0
	var guard_ticks := 0
	while sim_f.map.grid[tree_tile.y][tree_tile.x] == sim_f.map.TILE_TREE and guard_ticks < 150:
		guard_ticks += 1
		sim_f.tick(2.0)
		sim_f.time = fmod(sim_f.time, float(sim_f.cfg["day_length"]) * 0.5) + 5.0
	_check(sim_f.map.grid[tree_tile.y][tree_tile.x] == sim_f.map.TILE_GRASS, "лесоруб срубил дерево")
	_check(sim_f.map.stumps.has(tree_tile), "на месте сруба остался пень")
	_check(float(sim_f.forest_anger) > 0.0, "гнев леса вырос от вырубки")
	_check(bool(sim_f.terrain_dirty), "ландшафт помечен к перерисовке")

	# посадка: саженец из пула -> дерево, гнев спадает (v1.21: саженцы
	# выпадают из срубленных деревьев; семена остались для грядок)
	sim_f.res["saplings"] = 5.0
	var anger_before := float(sim_f.forest_anger)
	var plant_tile := tree_tile
	for i in 40:
		if sim_f.can_plant_at(plant_tile):
			break
		plant_tile += Vector2i(1, 0)
	_check(sim_f.can_plant_at(plant_tile), "рядом есть место под саженец")
	_check(String(sim_f.plant_sapling(plant_tile)) == "", "саженец посажен из пула")
	_check(sim_f.map.saplings.has(plant_tile), "саженец отмечен на карте")
	var seed_after: float = float(sim_f.res["saplings"])
	_check(seed_after == 4.0, "посадка потратила саженец")
	sim_f.map.saplings[plant_tile]["t"] = float(sim_f.cfg["forest"]["grow_days"]) \
			* float(sim_f.cfg["day_length"]) + 1.0
	sim_f.tick(0.5)
	_check(sim_f.map.grid[plant_tile.y][plant_tile.x] == sim_f.map.TILE_TREE, "саженец вырос в дерево")
	_check(float(sim_f.forest_anger) < anger_before, "выросший лес успокоил гнев")

	# духи: сильный гнев — волна с Древенем, отбита — гнев спал
	sim_f.forest_anger = 30.0
	sim_f._forest_cooldown = 0.0
	sim_f._update_forest(0.5, float(sim_f.cfg["day_length"]))
	_check(sim_f.raid_active and not sim_f.raiders.is_empty(), "разозлённый лес послал духов")
	_check(String(sim_f._raid_kind) == "forest", "волна помечена как лесная (не срывает план мутантов)")
	var any_boss := false
	for rr in sim_f.raiders:
		if String(rr["type"]) == "forest_boss":
			any_boss = true
	_check(any_boss, "при сильном гневе из чащи вышел Древень")
	sim_f.raiders.clear()
	sim_f._raid_end(true)
	_check(not sim_f.raid_active, "волна леса кончилась")
	_check(float(sim_f.forest_anger) < 30.0, "после отпора гнев леса спал")

	# скала: каменотёс вырабатывает тайл — жила руды / кристалл / осыпь
	var sim_q := _make_sim()
	sim_q.cfg["mountain"]["rate"] = 5000.0   # мгновенная выработка — для теста
	sim_q.cfg["piles"] = {"chunk": 1.0, "max": 60.0, "carry": 10.0}
	var rock_tile := Vector2i(-1, -1)
	var qspot := Vector2i(-1, -1)
	# v1.28: перебираем ВСЕ скалы, пока у какой-нибудь не найдётся место
	# под каменоломню (составные озёра могли запереть первую попавшуюся)
	for y in sim_q.map.h:
		for x in sim_q.map.w:
			var rt := Vector2i(x, y)
			if sim_q.map.grid[y][x] != sim_q.map.TILE_ROCK:
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var t2 := rt + Vector2i(dx, dy)
					# v1.28: карьер 2×2 — проверяем ПЛОЩАДЬ (не одну клетку),
					# и берём скалу поближе к спавну: у края rect не влезает
					if sim_q.is_buildable_rect("quarry", t2) \
							and sim_q.placement_block("quarry", t2) == "" \
							and sim_q.placement_gap_ok("quarry", t2) \
							and (qspot == Vector2i(-1, -1)
									or t2.distance_to(sim_q.map.spawn_tile)
									< qspot.distance_to(sim_q.map.spawn_tile)):
						rock_tile = rt
						qspot = t2
						break
	_check(qspot != Vector2i(-1, -1), "у скалы есть место под каменоломню")
	_check(sim_q.place_building("quarry", qspot), "каменоломня заложена у скалы")
	var builder_q: Dictionary = _resident_by_prof(sim_q, "builder")
	builder_q["mood"] = 100.0
	builder_q["traits"] = []
	_teleport(sim_q, builder_q, qspot)
	sim_q.tick(25.5)
	var miner_q: Dictionary = _resident_by_prof(sim_q, "miner")
	if miner_q.is_empty():
		miner_q = sim_q._new_resident("Герд", "miner", sim_q.map.spawn_tile)
		sim_q.residents.append(miner_q)
		sim_q._next_id += 1
	sim_q._assign_jobs()
	_teleport(sim_q, miner_q, qspot)
	sim_q.cfg["food_per_resident_day"] = 0.0
	sim_q.time = 10.0
	var qticks := 0
	var changed := false
	while not changed and qticks < 40:
		qticks += 1
		sim_q.tick(1.0)
		sim_q.time = fmod(sim_q.time, float(sim_q.cfg["day_length"]) * 0.5) + 5.0
		for ev in sim_q.events:
			if String(ev["type"]) in ["ore_revealed", "gem_found", "rock_gone"]:
				changed = true
	_check(changed, "выработка скалы дала событие (жила/кристалл/осыпь)")

	# некромант: кладбище темнеет, армия растёт тайно, восстание, зачистка героем
	# v1.23: зов слышен только к закопанному праху, армия растёт от ночных
	# ритуалов некроманта у могил (дальше — test_v123), тьму кормят закопанные
	var sim_n := _make_sim()
	sim_n.cfg["necro"]["dark_per_night"] = 0.5
	sim_n.cfg["necro"]["call_chance"] = 1.0
	sim_n.cfg["necro"]["rise_at"] = 3
	sim_n.cfg["necro"]["storm_chance"] = 0.0   # v1.24: буря не должна рвать тест вольным случаем
	var cem := _build_now(sim_n, "cemetery")
	_check(bool(cem["done"]), "кладбище построено")
	var cem_tile: Vector2i = cem["tile"]
	for gi in 4:   # тьму кормит закопанный прах — несколько могил
		sim_n.graves.append({"tile": cem_tile + Vector2i(1 + gi, 1), "name": "Старик",
				"ready": true, "rite": "bury"})
	sim_n._roll_necro()
	_check(float(sim_n.necro_dark) > 0.0, "тьма кладбища растёт")
	_check(bool(sim_n.necro_known), "некромантия раскрыта по тьме")
	var has_secret := false
	for r in sim_n.residents:
		if String(r.get("secret", "")) == "necromancer":
			has_secret = true
	_check(has_secret, "в городе завёлся тайный некромант")
	# ночь у могил: армия крепнет от ритуала (шанс 1.0, ритуал мгновенный)
	var necro: Dictionary = {}
	for r in sim_n.residents:
		if String(r.get("secret", "")) == "necromancer":
			necro = r
	necro["fatigue"] = 0.0
	necro["bld"] = null
	necro["site"] = null
	necro["necro_study"] = 9999.0
	sim_n.cfg["necro"]["army_per_ritual_chance"] = 1.0
	for r in sim_n.residents:   # город спит по домам — некроманта не видно
		if r != necro:
			r["state"] = "sleep"
			r["inside"] = 1
	_teleport(sim_n, necro, sim_n.map.nearest_walkable(cem_tile))
	necro["necro_phase"] = "rite"
	sim_n._necro_night_walk(necro, 0.1)
	_check(int(sim_n.necro_army) > 0, "скелеты собираются тайно")
	var attempts := 0
	while not sim_n.raid_active and attempts < 8:
		attempts += 1
		sim_n.necro_army = maxi(sim_n.necro_army, int(sim_n.cfg["necro"]["rise_at"]))
		sim_n._roll_necro()
	_check(sim_n.raid_active and String(sim_n._raid_kind) == "undead", "мертвецы восстали из кладбища")
	var skel_seen := false
	for rr2 in sim_n.raiders:
		if String(rr2["type"]) == "skeleton":
			skel_seen = true
	_check(skel_seen, "восставшие — скелеты")
	sim_n.raiders.clear()
	sim_n._raid_end(true)
	_check(not sim_n.raid_active, "восстание подавлено")
	var hit := String(sim_n.hero_hit_building(
			sim_n.map.tile_center_px(cem_tile) + Vector2(64, 0), Vector2(-1, 0), 96.0, 360.0, 100))
	_check(hit == "necro_purged", "герой выкорчевал кладбище")
	_check(int(sim_n.necro_army) == 0, "тайная армия рассыпалась")
	_check(bool(sim_n.building_at(cem_tile).get("razed", false)),
			"кладбище разрушено ударом героя (руины на месте, этап 2, аспект 5)")


# --- M14-A: сейв/загрузка (issue #3) -----------------------------------------

## Фейковый Game для сейва: только поля, которые читает save_game.gd.
func _test_m12() -> void:
	print("[M12: живой город — досуг, разговоры, похороны]")
	var sim := _make_sim()
	var day_len := float(sim.cfg["day_length"])
	# вечер распознаётся, день — нет
	sim.time = 0.3 * day_len
	_check(not sim._is_evening(), "днём вечер не начинается")
	sim.time = (1.0 - float(sim.cfg["night_fraction"]) - 0.05) * day_len
	_check(sim._is_evening(), "вечером город отдыхает")
	# работник уходит в досуг: таверны нет — идёт к костру (центр)
	var sim2 := _make_sim()
	sim2.time = (1.0 - float(sim2.cfg["night_fraction"]) - 0.05) * day_len
	var farmer := _resident_by_prof(sim2, "farmer")
	_teleport(sim2, farmer, Vector2i(40, 30))
	sim2.tick(0.8)
	_check(["leisure", "chat", "going"].has(String(farmer["state"])),
			"вечером житель не работает, а отдыхает")
	# разговор: два праздных рядом обмениваются репликой.
	# v1.28: дневные броски заморожены — иначе на границе дня планёрка
	# переassign-ит жителей, и досуг не наступает (предмет теста — вечер).
	sim2._last_daily_day = 999
	var a := _add_resident(sim2, "Ада", "crafter")
	var b := _add_resident(sim2, "Борис", "porter")
	a["traits"] = []
	b["traits"] = []
	_teleport(sim2, a, Vector2i(40, 31))
	_teleport(sim2, b, Vector2i(40, 32))
	sim2.time = (1.0 - float(sim2.cfg["night_fraction"]) - 0.05) * day_len
	var evening_t := (1.0 - float(sim2.cfg["night_fraction"]) - 0.05) * day_len
	# v1.28: ловим МОМЕНТ разговора (реплика живёт 4 с, потом кулдаун)
	for i in 10:
		sim2.time = evening_t   # держим вечер: уход в ночь усыпит жителей
		sim2.tick(2.0)
		if String(a.get("chat_key", "")) != "" or String(b.get("chat_key", "")) != "":
			break
	_check(String(a.get("chat_key", "")) != "" or String(b.get("chat_key", "")) != "",
			"двое рядом на досуге беседуют облачком")
	# тревога (v1.25, заказчик: «жители стояли пару дней в ожидании атаки
	# и ничего не делали»): ПРЕДУПРЕЖДЕНИЕ больше не останавливает город —
	# жители работают до самой волны; у костра собираются лишь при атаке
	sim2._raid_warned = true
	sim2.time = 10.0
	var c := _add_resident(sim2, "Вера", "farmer")
	c["traits"] = []   # не трусливая: трус прячется, только когда волна пришла
	var fire_t: Vector2i = sim2.fire_tile()
	_teleport(sim2, c, sim2.map.nearest_walkable(fire_t + Vector2i(-6, 0)))
	for i in 6:
		sim2.tick(5.0)
	_check(String(c["state"]) != "gather",
			"во время предупреждения житель не сидит у костра — работает (%s)" % String(c["state"]))
	# трус: на предупреждении тоже работает (прячется лишь когда волна
	# реально пришла — это проверяется в test_threat)
	var coward2 := _add_resident(sim2, "Трус", "farmer")
	coward2["traits"] = ["coward"]
	coward2["state"] = "idle"
	_teleport(sim2, coward2, sim2.map.spawn_tile)
	sim2.tick(1.0)
	_check(String(coward2["state"]) != "hide",
			"на предупреждении трус ещё не прячется — работает (%s)" % String(coward2["state"]))
	sim2._raid_warned = false   # дальше — мирные проверки
	# похороны: кладбище, смерть жителя → процессия и могилка
	# v1.23: горожане выбирают обряд — бог «Дом» велит хоронить в землю,
	# иначе 25% уходит на погребальный костёр (2 дня, проверяется в v123)
	sim2.god = "home"
	var cem := _build_now(sim2, "cemetery")
	_check(bool(cem["done"]), "кладбище построено")
	var victim := _add_resident(sim2, "Гриб", "farmer")
	_teleport(sim2, victim, Vector2i(42, 32))
	sim2.time = 10.0
	sim2.tick(0.7)
	sim2._kill(victim, "chron.plague")
	_check(sim2.graves.size() == 1, "после смерти готовится могилка")
	var mourners := 0
	for r in sim2.residents:
		if int(r.get("funeral", 0)) > 0:
			mourners += 1
	_check(mourners >= 1, "процессию провожают жители")
	sim2.time = 10.0
	for i in 12:   # дойти до кладбища (2×2: у входа) и выждать прощание
		sim2.tick(10.0)
	_check(bool(sim2.graves[0]["ready"]), "могилка готова после прощания")

	# --- гнёзда и следы (M12C): живые колонии бандитов на карте мира ---
	var ws_cfg: Dictionary = _read_json("res://data/world.json")
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(11, ws_cfg)
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, ws_cfg, 5)
	var camp: Dictionary = {}
	for poi in wmap.pois:
		if String(poi["kind"]) == "camp":
			camp = poi
			break
	_check(not camp.is_empty(), "на карте есть лагерь бандитов")
	for i in 12:
		wsim.advance_day()
	_check(int(camp.get("nest_level", 0)) >= 1,
			"гнездо растёт со временем (ур. %d)" % int(camp.get("nest_level", 0)))
	_check(float(camp.get("plunder", 0.0)) > 0.0, "добытчики носят добычу в гнездо")
	_check(wsim.location_scale(camp) > 0.5, "строители укрепляют лагерь — враги сильнее")
	_check(wsim.coin_reward(camp) >= 8 + int(float(camp.get("plunder", 0.0))),
			"зачистка богатого гнезда жирнее награждает")
	# следы: скауты оставляют цепочку, герой заметает и выслеживает
	camp["nest_level"] = 2
	wsim.cfg["nests"]["track_chance"] = 1.0
	wsim.tracks = {}
	wsim._roll_tracks()
	_check(wsim.tracks.size() >= 2, "скауты оставили цепочку следов (%d)" % wsim.tracks.size())
	var t0: Vector2i = wsim.tracks.keys()[0]
	var r1: Dictionary = wsim.track_scout(t0)
	_check(bool(r1["wiped"]) and not wsim.tracks.has(t0), "герой заметает след под ногами")
	camp["discovered"] = false
	wsim.tracks = {}
	wsim._roll_tracks()
	var r2: Dictionary = wsim.track_scout(wsim.tracks.keys()[0])
	_check(bool(r2["found"]), "след ведёт к скрытому гнезду — тайл цепочки открыт")
	# большой рейд: гнездо верхнего уровня присылает усиленный отряд (×1.5)
	var target_poi: Dictionary = {}
	for poi in wmap.pois:
		if String(poi["kind"]) == "settlement" and String(poi["state"]) == "ok":
			target_poi = poi
			break
	if not target_poi.is_empty():
		camp["strength"] = 12.0
		camp["nest_level"] = 3
		wsim.sieges = [{"settlement_id": int(target_poi["id"]), "camp_id": int(camp["id"]),
				"left": 0, "big": true}]
		var evs: Array = wsim._update_sieges()
		var fell := false
		for e in evs:
			if String(e["type"]) == "siege_fell":
				fell = true
		_check(fell, "большой рейд гнезда (×1.5) гарантированно берёт поселение")
	# следы стареют и исчезают
	wsim.tracks = {Vector2i(5, 5): {"dir": Vector2i(1, 0), "camp": int(camp["id"]), "age": 99}}
	wsim._update_tracks()
	_check(wsim.tracks.is_empty(), "старые следы стираются")


# --- M13: вишлист 2 — ангелы/демоны/нежить, замки драконов, пары и праздник --

func _test_m13() -> void:
	print("[M13: бестиарий, замки драконов, пары и День основания]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var enemies: Array = _read_json("res://data/enemies.json")
	var dungeon: Dictionary = _read_json("res://data/dungeon.json")
	var world_cfg: Dictionary = _read_json("res://data/world.json")

	# --- новый бестиарий: 9 существ, локализация, боссы ---
	var by_id := {}
	for e in enemies:
		by_id[String(e["id"])] = e
	var new_kinds := {"ghoul": false, "wraith": false, "imp": false, "hellcaller": false,
			"fallen": false, "dragon_whelp": false,
			"seraph_of_ash": true, "demon_lord": true, "ancient_dragon": true}
	for id in new_kinds:
		_check(by_id.has(id), "враг %s есть в enemies.json" % id)
		if not by_id.has(id):
			continue
		var e: Dictionary = by_id[id]
		_check(String(loc.get(String(e["loc"]), "")) != "", "у %s есть имя в ru.json" % id)
		_check(bool(e.get("boss", false)) == bool(new_kinds[id]), "у %s флаг босса верный" % id)
		_check(String(loc.get("school." + String(e.get("weak_school", "")), "")) != ""
				or String(e.get("weak_school", "")) == "",
				"у %s корректная школа уязвимости" % id)

	# --- три новых биома: население существует, босс на месте ---
	var biomes: Dictionary = dungeon.get("biomes", {})
	var eids := {}
	for e in enemies:
		eids[String(e["id"])] = true
	for biome_id in ["cursed_hall", "demon_lair", "dragon_lair"]:
		_check(biomes.has(biome_id), "биом %s есть в dungeon.json" % biome_id)
		if not biomes.has(biome_id):
			continue
		var b: Dictionary = biomes[biome_id]
		_check(String(loc.get(String(b["loc"]), "")) != "", "у биома %s есть название" % biome_id)
		_check(eids.has(String(b["boss"])), "босс биома %s существует" % biome_id)
		var weights: Dictionary = b.get("enemy_weights", {})
		_check(not weights.is_empty(), "у биома %s задано население" % biome_id)
		var ok_pop := true
		for w_id in weights:
			if not eids.has(String(w_id)):
				ok_pop = false
		_check(ok_pop, "население биома %s — известные враги" % biome_id)

	# --- мир: замок дракона на карте, входит и возрождается ---
	var pconf: Dictionary = world_cfg.get("pois", {})
	_check(int(pconf.get("dragon_castles", 0)) >= 1, "на карте есть замок дракона")
	var biome_list: Array = pconf.get("dungeon_biomes", [])
	_check("cursed_hall" in biome_list and "demon_lair" in biome_list,
			"аномалии бывают проклятыми и демоническими")
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(13, world_cfg)
	var castle: Dictionary = {}
	for poi in wmap.pois:
		if String(poi["kind"]) == "dragon_castle":
			castle = poi
			break
	_check(not castle.is_empty(), "замок дракона сгенерирован")
	if not castle.is_empty():
		_check(String(castle["biome"]) == "dragon_lair", "замок ведёт в логово дракона")
		var dist := int(Vector2(castle["tile"]).distance_to(Vector2(wmap.city_tile)))
		_check(dist >= int(world_cfg["distances"]["dragon_castle"][0]),
				"замок далеко от города (%d тайлов)" % dist)
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, world_cfg, 7)
	if not castle.is_empty():
		_check(wsim.poi_enterable(castle), "в замок можно войти, пока он не зачищен")
		wsim.day = 20   # зачистка давно в прошлом — замок готов возродиться
		castle["cleared_day"] = 10
		_check(not wsim.poi_enterable(castle), "зачищенный замок закрыт до возрождения")
		var coins: int = wsim.coin_reward(castle)
		_check(coins >= 30 and coins <= 60, "сокровищница даёт %d монет" % coins)
		var evs: Array = wsim._roll_dungeon_resets()
		var reborn := false
		for ev in evs:
			if String(ev["b"]) == "dragon_castle":
				reborn = true
		_check(reborn, "замок дракона возрождается как остальные данжи")

	# --- пары: друзья женятся, поддержка, вдовство ---
	var sim := _make_sim()
	sim.people["couples"]["chance_per_day"] = 1.0   # детерминизм теста
	var a := _add_resident(sim, "Ада", "crafter")
	var b := _add_resident(sim, "Борис", "porter")
	a["traits"] = []
	b["traits"] = []
	a["friend"] = int(b["id"])
	b["friend"] = int(a["id"])
	a["mood"] = 80.0
	b["mood"] = 80.0
	sim._roll_couples()
	_check(int(a["partner"]) == int(b["id"]) and int(b["partner"]) == int(a["id"]),
			"друзья с хорошим настроением создали пару")
	_check(float(a["mood"]) > 80.0, "свадьба подняла настроение")
	var has_wed := false
	for ev in sim.events:
		if String(ev["type"]) == "wedding":
			has_wed = true
	_check(has_wed, "свадьба объявлена городом")
	# поддержка пары: каждый день настроения понемногу прибавляется
	var mood_before := float(a["mood"])
	sim.events.clear()
	sim._roll_couples()
	_check(float(a["mood"]) > mood_before, "пара поддерживает друг друга")
	# вдовство: сброс пары и двойное горе
	sim._kill(a, "chron.test")
	_check(int(b["partner"]) == -1, "после смерти партнёра пара распалась")
	var has_widow := false
	for ev in sim.events:
		if String(ev["type"]) == "widow":
			has_widow = true
	_check(has_widow, "город узнал о вдовце")
	_check(String(loc.get("chron.widow", "")) != "" and String(loc.get("story.widow_toast", "")) != "",
			"вдовство описано в локализации")

	# --- День основания: раз в N дней, еда за настроение ---
	sim.cfg["life"]["festival_every_days"] = 1   # в тесте — каждый день (день 1)
	_check(sim._festival_today(), "в День основания город гуляет")
	sim.time = float(sim.cfg["day_length"]) * 0.9
	_check(not sim._festival_today(), "ночью праздник затихает")
	sim.time = 0.0
	sim.res["food"] = 100.0
	var mood_before2 := 0.0
	for r in sim.residents:
		r["traits"] = []
		if String(r["prof"]) != "":
			r["mood"] = 50.0
			mood_before2 += 50.0
	sim._roll_festival()
	_check(float(sim.res["food"]) < 100.0, "праздник расходует еду")
	var mood_after := 0.0
	for r in sim.residents:
		if String(r["prof"]) != "":
			mood_after += float(r["mood"])
	_check(mood_after > mood_before2, "праздник поднял настроение городу")
	var has_found := false
	for ev in sim.events:
		if String(ev["type"]) == "found_day":
			has_found = true
	_check(has_found, "День основания объявлен")
	# нехватка еды — праздник отменяется
	sim.events.clear()
	sim.res["food"] = 0.0
	sim._roll_festival()
	var has_skip := false
	for ev in sim.events:
		if String(ev["type"]) == "found_skip":
			has_skip = true
	_check(has_skip, "без еды праздник отменяется с летописью")

	# --- вечер пары: план корректен, реплики локализованы ---
	var sim2 := _make_sim()
	sim2.cfg["life"]["festival_every_days"] = 0   # выключаем праздник для чистоты
	var p1 := _add_resident(sim2, "Павел", "farmer")
	var p2 := _add_resident(sim2, "Ольга", "crafter")
	p1["traits"] = []
	p2["traits"] = []
	p1["partner"] = int(p2["id"])
	p2["partner"] = int(p1["id"])
	var day_len := float(sim2.cfg["day_length"])
	sim2.time = (1.0 - float(sim2.cfg["night_fraction"]) - 0.05) * day_len
	_teleport(sim2, p1, Vector2i(20, 20))
	var plan: Dictionary = sim2._pick_leisure(p1)
	var goal: Vector2i = Vector2i(plan.get("tile", Vector2i(-1, -1)))
	_check(sim2.map.in_bounds(goal), "план вечера пары — корректный тайл")
	_check(String(loc.get("love.0", "")) != "" and String(loc.get("fest.0", "")) != "",
			"реплики любви и праздника локализованы")
	print("[M13] готово")


## Фейковый герой для проверки разминирования ловушек (issue #2): duck typing —
## trap.gd обращается к global_position/dead/take_damage динамически.
func _test_m14_save() -> void:
	print("[M14-A: сейв/загрузка — roundtrip город+мир, битый сейв]")
	var SG: Script = load("res://scripts/save_game.gd")
	SG.clear_save()
	_check(not SG.has_save(), "до сохранения файла нет")

	var g1 := _make_game()
	var sim1: Object = g1.city_sim
	# живой город: стройка (tick списывает ресурсы и двигает день), дорога, пень
	var bld: Dictionary = _build_now(sim1, "farm")
	_check(not bld.is_empty(), "ферма построена до сейва")
	sim1.chronicle.append({"day": 4, "key": "chron.refugee", "a": "Мира", "b": ""})
	var grass := _grass_tiles(sim1, sim1.map.spawn_tile, 3)
	_check(sim1.place_road(grass[0]) == "", "дорога проложена до сейва")
	var tree_tile := Vector2i(-1, -1)
	for y in sim1.map.h:
		for x in sim1.map.w:
			if sim1.map.grid[y][x] == sim1.map.TILE_TREE:
				tree_tile = Vector2i(x, y)
				break
		if tree_tile.x >= 0:
			break
	if tree_tile.x >= 0:
		sim1.map.grid[tree_tile.y][tree_tile.x] = sim1.map.TILE_GRASS
		sim1.map.stumps[tree_tile] = true
	# контрольные значения ставим ПОСЛЕ всех мутаций, прямо перед сейвом
	sim1.res["wood"] = 234.0
	sim1.res["crystal"] = 17.0
	sim1.time = float(sim1.cfg["day_length"]) * 6.35
	sim1.residents[0]["mood"] = 73.5
	sim1.residents[0]["partner"] = int(sim1.residents[1]["id"])
	sim1.residents[1]["partner"] = int(sim1.residents[0]["id"])
	var g1_residents: int = sim1.residents.size()
	var g1_day: int = sim1.day_number()
	var g1_wood: int = int(sim1.res["wood"])
	var g1_crystal: int = int(sim1.res["crystal"])
	g1.coins = 42
	g1.inventory.append({"id": "rune_light", "count": 3})
	g1.spellbook.append("heal")
	g1.equipment = {"weapon": "iron_sword", "armor": "", "accessory": "mana_pendant", "mount": ""}
	# мир: зачистим один данж и откроем туман рядом с городом
	var dungeon_poi: Dictionary = {}
	for poi in g1.world_map.pois:
		if String(poi["kind"]) == "dungeon" and dungeon_poi.is_empty():
			dungeon_poi = poi
	if not dungeon_poi.is_empty():
		g1.world_sim.mark_cleared(int(dungeon_poi["id"]))
	g1.world_map.reveal_around(g1.world_map.city_tile + Vector2i(6, 0), 3)

	var err: String = SG.save_game(g1, sim1.map.spawn_tile, 7, 3)
	_check(err == "", "сохранение прошло без ошибки")
	_check(SG.has_save(), "файл сейва появился")

	# свежий Game: загружаем и сверяем
	var g2 := FakeGame.new()
	g2.skills = load("res://scripts/skills.gd").new()
	g2.skills.setup(_read_json("res://data/skills.json"))
	var lerr: String = SG.load_game(g2)
	_check(lerr == "", "загрузка прошла без ошибки")
	var sim2: Object = g2.city_sim
	_check(sim2 != null and g2.world_map != null and g2.world_sim != null, "город и мир восстановлены")
	_check(int(sim2.map.w) == int(sim1.map.w) and int(sim2.map.h) == int(sim1.map.h),
			"размеры карты города совпадают")
	var grid_ok := true
	for y in sim1.map.h:
		for x in sim1.map.w:
			if int(sim1.map.grid[y][x]) != int(sim2.map.grid[y][x]):
				grid_ok = false
				break
		if not grid_ok:
			break
	_check(grid_ok, "сетка ландшафта совпадает бит-в-бит")
	_check(sim2.map.road.has(grass[0]), "дорога восстановлена")
	if tree_tile.x >= 0:
		_check(sim2.map.stumps.has(tree_tile), "пень на месте спиленного дерева")
	_check(sim2.map.spawn_tile == sim1.map.spawn_tile
			and sim2.map.anomaly_tile == sim1.map.anomaly_tile,
			"ключевые тайлы (старт/аномалия) совпадают")
	_check(int(sim2.res["wood"]) == g1_wood and int(sim2.res["crystal"]) == g1_crystal,
			"ресурсы совпадают (дерево/кристаллы)")
	_check(absf(float(sim2.time) - float(sim1.time)) < 0.001, "время города совпадает")
	_check(sim2.day_number() == g1_day, "день города совпадает (%d)" % sim2.day_number())
	_check(sim2.residents.size() == g1_residents, "все жители на месте (%d)" % g1_residents)
	var r0: Dictionary = sim2.residents[0]
	_check(absf(float(r0["mood"]) - 73.5) < 0.001, "настроение жителя совпадает")
	_check(int(r0["partner"]) == int(sim1.residents[0]["partner"]), "пара восстановлена по id")
	_check(sim2.buildings.size() == sim1.buildings.size(), "число зданий совпадает")
	var farm2: Dictionary = sim2.building_at(bld["tile"])
	_check(not farm2.is_empty() and bool(farm2["done"]), "ферма восстановлена и готова")
	# v1.20: после загрузки староста сразу строит утренний план (запись в летопись)
	# — сверяем, что старая летопись сохранена как начало новой, без потерь
	var chron_same: bool = sim2.chronicle.size() >= sim1.chronicle.size()
	if chron_same:
		for i in sim1.chronicle.size():
			if int(sim2.chronicle[i]["day"]) != int(sim1.chronicle[i]["day"]) \
					or String(sim2.chronicle[i]["key"]) != String(sim1.chronicle[i]["key"]):
				chron_same = false
	_check(chron_same, "летопись совпадает")
	var morning_after_load := false
	for e in sim2.chronicle:
		if String(e["key"]) == "chron.morning_plan":
			morning_after_load = true
	_check(morning_after_load, "утренний тик после загрузки построил план")
	var ref_ok := true
	for r in sim2.residents:
		var b = r.get("bld")
		if b != null and not (b is Dictionary):
			ref_ok = false
	_check(ref_ok, "ссылки жителей на здания — словари")
	_check(_count_runes(g2, "rune_light") == 3, "рюкзак героя восстановлен")
	_check(g2.spellbook.has("heal"), "гримуар восстановлен")
	_check(g2.coins == 42, "монеты восстановлены")
	_check(g2.skills.level == g1.skills.level and g2.skills.taken == ["w1"],
			"навыки героя восстановлены (уровень %d, узел w1)" % g2.skills.level)
	_check(g2.hero_saved_hp == 7 and g2.hero_saved_mana == 3, "HP/мана героя из сейва")
	_check(String(g2.equipment["weapon"]) == "iron_sword"
			and String(g2.equipment["accessory"]) == "mana_pendant", "экипировка восстановлена из сейва")
	_check(int(g2.world_sim.day) == int(g1.world_sim.day), "день мира совпадает")
	if not dungeon_poi.is_empty():
		var d2: Dictionary = g2.world_map.poi_by_id(int(dungeon_poi["id"]))
		_check(int(d2["cleared_day"]) == int(g1.world_sim.day), "зачистка данжа помнится миром")
	_check(g2.world_map.fog.size() > 20, "туман войны восстановлен (%d тайлов)" % g2.world_map.fog.size())
	_check(g2.world_map.tile_path(g2.world_map.city_tile + Vector2i(1, 0),
			g2.world_map.city_tile + Vector2i(5, 0)).size() > 0,
			"поиск пути мира работает после загрузки")

	# обновление сейва из загруженного состояния — день продолжает расти
	sim2.time += float(sim2.cfg["day_length"]) * 2.0
	_check(SG.save_game(g2, sim2.map.spawn_tile, -1, -1) == "",
			"повторное сохранение из загруженного состояния")
	var g3 := FakeGame.new()
	g3.skills = load("res://scripts/skills.gd").new()
	g3.skills.setup(_read_json("res://data/skills.json"))
	_check(SG.load_game(g3) == "", "повторная загрузка")
	_check(g3.city_sim.day_number() == sim2.day_number(),
			"день вырос и сохранился (%d)" % g3.city_sim.day_number())

	# битый сейв: мусор вместо JSON
	var f := FileAccess.open(SG.SAVE_PATH, FileAccess.WRITE)
	f.store_string("не JSON вовсе")
	f.close()
	var g4 := FakeGame.new()
	g4.skills = load("res://scripts/skills.gd").new()
	_check(SG.load_game(g4) == "save.load_failed", "битый файл отклонён")
	# чужая версия формата
	var fd := FileAccess.open(SG.SAVE_PATH, FileAccess.WRITE)
	fd.store_string('{"v": 999, "city": {}, "world": {}, "game": {}}')
	fd.close()
	_check(SG.load_game(g4) == "save.bad_version", "чужая версия формата отклонена")
	# отсутствие файла
	SG.clear_save()
	_check(SG.load_game(g4) == "save.no_save", "отсутствие файла отклонено")
	# ключи локализации ошибок существуют
	var loc: Dictionary = _read_json("res://loc/ru.json")
	for key in ["save.no_game", "save.no_save", "save.load_failed", "save.bad_version",
			"save.write_failed", "save.dungeon_hint", "menu.save_game", "menu.save_done",
			"menu.autosaved"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	SG.clear_save()
	print("[M14-A] готово")


# --- M14-B: экипировка, оружие, анти-кайт (issue #3) -------------------------

## Фейковый герой для зелий: эффекты записывает, рюкзака не имеет.
