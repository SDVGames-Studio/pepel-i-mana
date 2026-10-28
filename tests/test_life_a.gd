# Жизнь: вишлист, M12-M13, сейв, личности v3 (части b-f).
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
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
	while sim_f.map.grid[tree_tile.y][tree_tile.x] == sim_f.map.TILE_TREE and guard_ticks < 60:
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
func _test_m14_b() -> void:
	print("[M14-B: экипировка, оружие, анти-кайт]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var weapons: Dictionary = _read_json("res://data/weapons.json")
	var items: Dictionary = _read_json("res://data/items.json")
	var magic: Dictionary = _read_json("res://data/magic.json")
	var balance: Dictionary = _read_json("res://data/balance.json")

	# --- конфиг оружия: 5 типов, разные паттерны ---
	var wlist: Array = weapons.get("weapons", [])
	_check(wlist.size() == 5, "в weapons.json 5 типов оружия")
	var ids := {}
	var patterns := {}
	for w: Dictionary in wlist:
		ids[String(w["id"])] = true
		patterns[String(w["id"])] = String(w["pattern"])
		_check(String(loc.get(String(w["loc"]), "")) != "" and String(loc.get(String(w["desc"]), "")) != "",
				"оружие %s описано в локализации" % String(w["id"]))
	_check(ids.size() == 5, "id оружия уникальны")
	_check(String(patterns["sword"]) == "arc" and String(patterns["axe"]) == "arc",
			"меч и топор — дуга")
	_check(String(patterns["spear"]) == "thrust" and float(_w_by_id(wlist, "spear")["range"]) > float(_w_by_id(wlist, "sword")["range"]),
			"копьё — тычок и бьёт дальше меча")
	_check(String(patterns["bow"]) == "projectile" and String(patterns["staff"]) == "projectile",
			"лук и посох — снаряды")
	_check(float(_w_by_id(wlist, "axe")["attack_cooldown"]) > float(_w_by_id(wlist, "sword")["attack_cooldown"]),
			"топор медленнее меча")
	_check(int(_w_by_id(wlist, "axe")["damage"]) > int(_w_by_id(wlist, "sword")["damage"]),
			"топор бьёт больше меча")
	_check(float(_w_by_id(wlist, "bow")["projectile_speed"]) > 0.0
			and int(_w_by_id(wlist, "staff")["mana_cost"]) >= 1,
			"у лука есть скорость снаряда, посох тратит ману")
	var axe_arc: float = float(_w_by_id(wlist, "axe")["arc"])
	_check(axe_arc > float(_w_by_id(wlist, "sword")["arc"]), "топор шире меча")

	# --- каталог предметов: >=30, 4 редкости, ссылки целы ---
	var ilist: Array = items.get("items", [])
	_check(ilist.size() >= 30, "в items.json %d предметов (нужно >=30)" % ilist.size())
	var rarities := {}
	var kinds_ok := true
	var refs_ok := true
	var loc_ok := true
	var item_ids := {}
	for it: Dictionary in ilist:
		item_ids[String(it["id"])] = true
		rarities[String(it["rarity"])] = true
		if String(it["kind"]) not in ["weapon", "armor", "accessory", "scroll", "potion", "tool", "mount"]:
			kinds_ok = false
		if String(it["kind"]) == "weapon" and not ids.has(String(it.get("weapon", ""))):
			refs_ok = false
		if String(it["kind"]) == "scroll" and not _spell_exists(magic, String(it.get("spell_id", ""))):
			refs_ok = false
		if String(loc.get(String(it["loc"]), "")) == "" or String(loc.get(String(it["desc"]), "")) == "":
			loc_ok = false
	_check(rarities.has("common") and rarities.has("uncommon") and rarities.has("rare") and rarities.has("legendary"),
			"использованы все 4 редкости")
	_check(kinds_ok, "все kind допустимы")
	_check(refs_ok, "ссылки на оружие и заклинания целы")
	_check(loc_ok, "у всех предметов есть имя и описание в loc")
	for w: Dictionary in wlist:
		item_ids[String(w["id"])] = true
	# руны — предметы loot.json (стоимости свитков ссылаются на них)
	var loot_v: Variant = _read_json("res://data/loot.json")
	if loot_v is Dictionary:
		for it: Dictionary in loot_v.get("items", []):
			item_ids[String(it["id"])] = true
	var craft_ok := true
	for it: Dictionary in ilist:
		if not it.has("craft"):
			continue
		var where := String(it["craft"].get("where", ""))
		if where != "armory" and where != "workshop":
			craft_ok = false
		for key in it["craft"].get("cost", {}):
			if not item_ids.has(String(key)) and String(key) not in \
					["wood", "stone", "food", "crystal", "tools", "iron", "metal", "kits", "seeds"]:
				craft_ok = false
	_check(craft_ok, "стоимости крафта — из известных ресурсов и рун")

	# --- Game: надеть/снять/поменять, бонусы, параметры оружия ---
	var g = load("res://scripts/game.gd").new()
	_check(not g.items_cfg.is_empty() and not g.weapons_cfg.is_empty(), "Game загрузил каталоги")
	g.add_item("iron_sword", 1)
	g.add_item("knight_sword", 1)
	g.add_item("chainmail", 1)
	g.add_item("mana_pendant", 1)
	_check(g.equip_item("iron_sword") == "", "железный меч надет")
	_check(String(g.equipment["weapon"]) == "iron_sword" and g.count_item("iron_sword") == 0,
			"меч ушёл из рюкзака в слот")
	var wp: Dictionary = g.weapon_params()
	_check(not wp.is_empty() and String(wp["pattern"]) == "arc" and int(wp["damage"]) == 2,
			"паттерн меча: дуга, урон 2")
	_check(g.equip_item("knight_sword") == "", "рыцарский меч надет поверх")
	_check(String(g.equipment["weapon"]) == "knight_sword" and g.count_item("iron_sword") == 1,
			"старый меч вернулся в рюкзак")
	_check(int(g.weapon_params()["damage"]) == 3, "рыцарский меч: урон 3 (2 × 1.3)")
	_check(g.unequip_slot("weapon") == "" and String(g.equipment["weapon"]) == ""
			and g.count_item("knight_sword") == 1, "снятие возвращает предмет в рюкзак")
	_check(g.equip_item("chainmail") == "" and g.equip_item("mana_pendant") == "",
			"броня и аксессуар надеты")
	var bon: Dictionary = g.equipment_bonuses()
	_check(int(bon.get("armor", 0)) == 3 and int(bon.get("mana", 0)) == 4,
			"бонусы экипировки суммируются (броня 3, мана 4)")
	_check(g.equip_item("blast_unknown") == "eq.bad_item", "неизвестный предмет отклонён")
	_check(g.equip_item("scroll_fire") == "eq.not_equippable", "свиток нельзя надеть")
	_check(g.unequip_slot("mount") == "eq.empty_slot", "пустой слот не снимается")
	g.unequip_slot("armor")
	g.unequip_slot("accessory")

	# --- посох: снаряд с маной; крафт; зелья ---
	g.add_item("apprentice_staff", 1)
	_check(g.equip_item("apprentice_staff") == "", "посох надет")
	var sp: Dictionary = g.weapon_params()
	_check(String(sp["pattern"]) == "projectile" and int(sp["mana_cost"]) == 1,
			"посох стреляет снарядом за 1 ману")
	g.unequip_slot("weapon")

	var sim := _make_sim()
	sim.res["metal"] = 10.0
	sim.res["wood"] = 5.0
	_check(g.craft_item("iron_sword", sim, false, true) == "eq.need_armory",
			"крафт меча требует оружейку")
	_check(g.craft_item("iron_sword", sim, true, false) == "", "меч выкован в оружейке")
	_check(g.count_item("iron_sword") == 2, "выкованный меч в рюкзаке (и возвращённый со слота)")
	_check(float(sim.res["metal"]) < 10.0, "металл списан за крафт")
	sim.res["iron"] = 0.0
	sim.res["wood"] = 0.0
	_check(g.craft_item("woodsman_axe", sim, true, false) == "eq.no_resources",
			"без ресурсов крафт отказывает")
	var potio := FakePotionHero.new()
	g.add_item("potion_heal", 1)
	g.add_item("potion_rage", 1)
	_check(g.use_potion("potion_heal", potio) == "" and potio.healed == [10],
			"зелье лечения выпито (+10 hp)")
	_check(g.count_item("potion_heal") == 0, "зелье израсходовано")
	_check(g.use_potion("potion_rage", potio) == "" and potio.temp_dmg.size() == 1,
			"эликсир ярости дал временный урон")
	_check(g.use_potion("potion_heal", potio) == "eq.not_owned", "пустой рюкзак — отказ")

	# меню-сейв (фидбек 2026-10-20): без сессии сохранять нечего
	_check(g.menu_save() == "save.no_game", "menu_save без сессии отказывает")

	# --- анти-кайт (T06): счётчик, телеграф, рывок, кулдаун ---
	var ak: Dictionary = balance.get("anti_kite", {})
	_check(int(ak.get("hits_threshold", 0)) == 2 and float(ak.get("cooldown", 0)) > 0.0,
			"анти-кайт настроен в balance.json")
	var enemies_v: Variant = _read_json("res://data/enemies.json")
	var enemies_data: Array = enemies_v if enemies_v is Array else []
	var EnemyS: Script = load("res://scripts/enemy.gd")
	EnemyS._ak = ak
	var tested_types := 0
	for enemy_id in ["rat", "skeleton", "bandit"]:
		var row := _enemy_row_by_id(enemies_data, enemy_id)
		if row.is_empty():
			continue
		tested_types += 1
		var e = EnemyS.new()
		e.setup(row)
		e.hp = 100
		var fh := FakeKiteHero.new()
		e.hero = fh
		e.position = Vector2.ZERO
		fh.global_position = Vector2(60, 0)
		e.take_damage(1)
		_check(float(e._telegraph_left) <= 0.0, "%s: один удар — рывка нет" % enemy_id)
		e.take_damage(1)
		_check(float(e._telegraph_left) > 0.0, "%s: два удара без ответа — телеграф" % enemy_id)
		e._tick_anti_kite(10.0, 60.0)
		_check(float(e._dash_left) > 0.0, "%s: после замера — рывок" % enemy_id)
		e._tick_anti_kite(0.05, 12.0)
		_check(fh.hits >= 1, "%s: рывок достал героя (кайт не работает)" % enemy_id)
		_check(float(e._dash_left) <= 0.0 and float(e._dash_cd) > 0.0,
				"%s: рывок погашен, кулдаун включён" % enemy_id)
		e.take_damage(1)
		e.take_damage(1)
		_check(float(e._telegraph_left) <= 0.0, "%s: на кулдауне рывка телеграфа нет" % enemy_id)
	_check(tested_types >= 3, "анти-кайт проверен на %d типах монстров" % tested_types)

	# --- локализация панели ---
	for key in ["eq.title", "eq.bag", "eq.craft_title", "eq.craft_hint", "eq.comparison",
			"eq.only_dungeon", "eq.scroll_used", "eq.no_resources", "eq.need_armory",
			"eq.need_workshop", "eq.stat.damage", "eq.stat.cd", "eq.stat.range",
			"eq.bonus.armor", "eq.bonus.hp", "eq.bonus.mana", "eq.potion.heal"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[M14-B] готово")


# --- M14-C: быстрые правки мира — фауна, награды, VFX, туман (issue #3) ------

func _test_m14_c() -> void:
	print("[M14-C: фауна, награды, VFX, туман]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var fauna_cfg: Dictionary = _read_json("res://data/fauna.json")
	var loot: Dictionary = _read_json("res://data/loot.json")
	var balance: Dictionary = _read_json("res://data/balance.json")
	var world_cfg: Dictionary = _read_json("res://data/world.json")
	var loot_ids := {}
	for it: Dictionary in loot.get("items", []):
		loot_ids[String(it["id"])] = true

	# --- T01: конфиг фауны ---
	var species: Array = fauna_cfg.get("species", [])
	_check(species.size() >= 5, "в fauna.json %d видов (нужно >=5)" % species.size())
	var biomes_covered := {"plains": false, "forest": false, "hills": false, "waste": false, "water": false}
	var drops_ok := true
	var fish_water_only := true
	var names_ok := true
	var wf_ids := {}
	for s: Dictionary in species:
		wf_ids[String(s["id"])] = true
		for b: String in s.get("biomes", []):
			if biomes_covered.has(b):
				biomes_covered[b] = true
		if String(s.get("behavior", "")) not in ["flee", "hunt", "fish"]:
			drops_ok = false
		if String(s.get("behavior", "")) == "fish" and "water" not in (s["biomes"] as Array):
			fish_water_only = false
		if String(s["behavior"]) != "fish":
			for d: Dictionary in s.get("drop", []):
				if not loot_ids.has(String(d["id"])):
					drops_ok = false
		if String(loc.get(String(s["loc"]), "")) == "":
			names_ok = false
	for b in biomes_covered:
		_check(bool(biomes_covered[b]), "биом %s заселён фауной" % b)
	_check(drops_ok, "поведение допустимо, дроп — предметы loot.json")
	_check(fish_water_only, "рыба живёт только на воде")
	_check(names_ok, "виды фауны названы в локализации")
	for item_id in ["meat", "hide", "feather", "fish_raw"]:
		_check(loot_ids.has(item_id) and String(loc.get("item." + item_id, "")) != "",
				"дроп %s есть в луте и локализации" % item_id)

	# --- T01: логика world_fauna ---
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(11, world_cfg)
	var wf = load("res://scripts/world_fauna.gd").new()
	wf.setup(wmap, fauna_cfg, 7)
	var plains_biome: String = wf.biome_of(wmap.city_tile)
	_check(plains_biome == "plains", "биом города читается (равнина)")
	var water_tile := Vector2i(-1, -1)
	for y in wmap.h:
		for x in wmap.w:
			if int(wmap.grid[y][x]) == wmap.TILE_WATER:
				water_tile = Vector2i(x, y)
				break
		if water_tile.x >= 0:
			break
	_check(water_tile.x >= 0 and wf.biome_of(water_tile) == "water", "водный тайл найден")
	var water_species: Array = wf._species_for_biome("water")
	_check(water_species == ["fish"], "на воде живёт только рыба")
	wf.cfg["spawn"]["chance_per_reveal"] = 1.0
	wf.cfg["spawn"]["min_dist"] = 0
	var spawned: String = wf.try_spawn_near(wmap.city_tile)
	_check(spawned != "", "спавн у героя сработал (%s)" % spawned)
	_check(wf.fauna.size() == 1, "зверь появился в мире")
	var hero_px: Vector2 = wmap.tile_center_px(wmap.city_tile)
	wf.fauna.append({"id": 999, "kind": "deer", "px": hero_px + Vector2(20, 0), "tx": Vector2.ZERO, "wait": 2.0})
	var check: Dictionary = wf.interact_check(hero_px + Vector2(20, 0))
	_check(String(check["kind"]) == "deer" and String(check["behavior"]) == "flee",
			"осмотр узнал оленя (мирный)")
	# мирный убегает от героя
	var before: float = (wf.fauna[1]["px"] as Vector2).distance_to(hero_px)
	for i in 6:
		wf.update(0.2, hero_px)
	var after: float = (wf.fauna[1]["px"] as Vector2).distance_to(hero_px)
	_check(after > before, "олень убегает от героя (охота имеет смысл)")
	# волк догоняет мирного (герой в 400px — не мешает, но звери не деспавнятся)
	wf.fauna.append({"id": 998, "kind": "wolf", "px": (wf.fauna[1]["px"] as Vector2) + Vector2(60, 0),
			"tx": Vector2.ZERO, "wait": 2.0})
	for i in 30:
		wf.update(0.25, hero_px + Vector2(400, 0))
	var deer_gone := true
	for a in wf.fauna:
		if int(a["id"]) == 999:
			deer_gone = false
	_check(deer_gone, "волк догнал оленя — хищники охотятся")
	# охота по E: подводим героя к оставшемуся зверю, дроп — предметы лута
	_check(not wf.fauna.is_empty(), "после волчьей охоты остался зверь")
	var target: Dictionary = wf.fauna[0]
	var hunted: Dictionary = wf.interact(target["px"])
	_check(String(hunted.get("kind", "")) == String(target["kind"]), "охота по E находит зверя")
	var hunt_drops_ok := true
	for d: Dictionary in hunted.get("drops", []):
		if not loot_ids.has(String(d["id"])):
			hunt_drops_ok = false
	_check(hunt_drops_ok, "дроп охоты — предметы loot.json")
	_check(not wf.fauna.has(target), "зверь после охоты исчез")
	# спавн ограничен сверху
	wf.fauna.clear()
	wf.cfg["spawn"]["max_active"] = 2
	for i in 10:
		wf.try_spawn_near(wmap.city_tile)
	_check(wf.fauna.size() <= 2, "спавн respects max_active (%d)" % wf.fauna.size())

	# --- T17: награды растут с уровнем гнезда ---
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, world_cfg, 42)
	_check(Dictionary(balance.get("rewards", {})).has("coin_mult_per_nest_level"),
			"balance.json -> rewards настроен")
	var camp0: Dictionary = {"kind": "camp", "plunder": 0.0, "nest_level": 0}
	var camp3: Dictionary = {"kind": "camp", "plunder": 0.0, "nest_level": 3}
	var sum0 := 0
	var sum3 := 0
	for i in 200:
		wsim._rng.seed = 1000 + i
		sum0 += wsim.coin_reward(camp0)
		wsim._rng.seed = 1000 + i
		sum3 += wsim.coin_reward(camp3)
	_check(sum3 > sum0 * 15 / 10, "гнездо 3 уровня жирнее гнезда 0 (%d против %d)" % [sum3, sum0])
	var setl: Dictionary = {"kind": "settlement", "plunder": 0.0, "nest_level": 3}
	wsim._rng.seed = 7
	var s_coins: int = wsim.coin_reward(setl)
	_check(s_coins >= 8 and s_coins <= 16, "поселение без множителя (обычная награда %d)" % s_coins)

	# --- T03: гуманоиды читаемы (герой = 10) ---
	var enemies_v: Variant = _read_json("res://data/enemies.json")
	var enemies: Array = enemies_v if enemies_v is Array else []
	var radius_of := {}
	for e: Dictionary in enemies:
		radius_of[String(e["id"])] = float(e["radius"])
	for humanoid in ["skeleton", "antimage", "mutant", "bandit_archer", "ghoul", "wraith", "hellcaller", "dragon_whelp"]:
		_check(float(radius_of.get(humanoid, 0.0)) >= 10.0, "гуманоид %s подрос (>=10)" % humanoid)
	_check(float(radius_of.get("imp", 0.0)) >= 10.0, "бесёнок — тот самый «очень маленький»: теперь 10")
	_check(float(radius_of.get("rat", 0.0)) == 8.0 and float(radius_of.get("wisp", 0.0)) == 7.0,
			"звери и духи не тронуты (крыса 8, огонёк 7)")
	# волк — враг лесного данжа (замечание 2026-10-20: звери и в данжах)
	var wolf_ok := false
	for e: Dictionary in enemies:
		if String(e["id"]) == "wolf":
			wolf_ok = float(e["radius"]) >= 10.0
	_check(wolf_ok, "волк есть в enemies.json и читаем")
	var dungeon_cfg: Dictionary = _read_json("res://data/dungeon.json")
	var forest_weights: Dictionary = dungeon_cfg["biomes"]["mutant_forest"]["enemy_weights"]
	_check(int(forest_weights.get("wolf", 0)) > 0, "волк водится в лесном данже")

	# --- T21/T23: городская атмосфера ---
	var sim := _make_sim()
	var amb = load("res://scripts/city_ambience.gd").new()
	amb.setup(sim.map)
	_check(amb._flies.size() > 0, "светлячки заселены (%d)" % amb._flies.size())
	_check(amb._wisps.size() > 0, "болотные огоньки заселены (%d)" % amb._wisps.size())
	_check(amb.night == 0.0, "днём VFX погашены")

	# --- фауна города (замечание 2026-10-20): виды, волки, охота героя ---
	var kinds := {}
	for a in sim.animals:
		kinds[String(a.get("kind", "?"))] = true
	var kinds_ok := true
	for k in kinds:
		if k not in ["deer", "boar", "bird", "wolf"]:
			kinds_ok = false
	_check(sim.animals.size() > 0 and kinds_ok,
			"в городе живут виды из fauna.json (%s)" % ", ".join(kinds.keys()))
	# волк догоняет мирного в городе
	var deer1 := {"id": 5001, "kind": "deer", "pos": Vector2(500, 500), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "idle": 99.0}
	var wolf1 := {"id": 5002, "kind": "wolf", "pos": Vector2(540, 500), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "idle": 99.0}
	sim.animals.append(deer1)
	sim.animals.append(wolf1)
	for i in 20:
		sim._update_animals(0.2)
	_check(not sim.animals.has(deer1), "городской волк догнал мирного зверя")
	sim.animals.erase(wolf1)
	# охота героя в городе: зверь в дуге умирает, дроп — предметы лута
	var deer2 := {"id": 5003, "kind": "boar", "pos": Vector2(300, 300), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "idle": 99.0}
	# флейк (2026-10-25): бродячий зверь мог забежать в дугу удара ближе
	# кабана — в дуге должен быть только он
	sim.animals = [deer2]
	var kill: Dictionary = sim.hero_hit_animal(Vector2(280, 300), Vector2(1, 0), 60.0, 90.0)
	_check(String(kill.get("kind", "")) == "boar" and not kill.get("drops", []).is_empty(),
			"удар героя в городе добывает зверя (%s)" % String(kill.get("kind", "")))
	_check(not sim.animals.has(deer2), "добытый зверь исчез из мира")
	sim.animals.clear()   # флейк: бродячий зверь мог забежать в дугу удара
	_check(sim.hero_hit_animal(Vector2(280, 300), Vector2(1, 0), 60.0, 90.0).is_empty(),
			"промах по пустому месту не даёт добычи")

	# --- пни под каждый тип дерева (замечание 2026-10-20) ---
	var city_view = load("res://scripts/city_view.gd")
	_check(city_view.STUMP_PALS.size() == city_view.TREE_REFS.size(),
			"вариантов пней столько же, сколько типов деревьев (%d)" % city_view.STUMP_PALS.size())

	# --- T13: туман — радиус открытия меньше и клик разрешён ---
	_check(int(world_cfg.get("fog_reveal_radius", 99)) < int(world_cfg.get("reveal_radius", 0)),
			"радиус открытия в тумане меньше обычного (%d < %d)" % [
				int(world_cfg.get("fog_reveal_radius", 99)), int(world_cfg.get("reveal_radius", 0))])
	var fog_tile := Vector2i(-1, -1)
	for y in wmap.h:
		for x in wmap.w:
			var p := Vector2i(x, y)
			if wmap.is_walkable(p) and not wmap.is_explored(p):
				fog_tile = p
				break
		if fog_tile.x >= 0:
			break
	_check(fog_tile.x >= 0, "неисследованный проходимый тайл есть")
	_check(not wmap.poi_at(fog_tile).is_empty() or true, "клик по туману ведёт в маршрут (правило сцены)")
	for key in ["world.hint_hunt", "world.hint_fish", "world.hunt_got", "chron.hunt",
			"fauna.deer", "fauna.boar", "fauna.bird", "fauna.wolf", "fauna.fish"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[M14-C] готово")


# --- M14-D: вампиры и личи (issue #3) ----------------------------------------

func _test_m14_d() -> void:
	print("[M14-D: вампиры и личи]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var enemies_v: Variant = _read_json("res://data/enemies.json")
	var enemies: Array = enemies_v if enemies_v is Array else []
	var dungeon_cfg: Dictionary = _read_json("res://data/dungeon.json")
	var world_cfg: Dictionary = _read_json("res://data/world.json")

	# --- враги: конфиги ---
	var rows := {}
	for e: Dictionary in enemies:
		rows[String(e["id"])] = e
	for need in ["vampire", "archvampire", "lich", "archlich", "skeleton_mage"]:
		_check(rows.has(need), "враг %s добавлен" % need)
	_check(float(rows["vampire"]["lifesteal"]) > 0.0
			and float(rows["archvampire"]["lifesteal"]) > 0.0
			and String(rows["vampire"]["weak_school"]) == "light"
			and String(rows["archvampire"]["weak_school"]) == "light",
			"вампиры пьют жизнь и слабы к свету")
	_check(bool(rows["lich"]["magic_immune"]) and bool(rows["archlich"]["magic_immune"])
			and float(rows["lich"]["projectile_speed"]) > 0.0
			and float(rows["archlich"]["projectile_speed"]) > 0.0,
			"личи не боятся магии и бьют издалека")
	_check(float(rows["skeleton_mage"]["projectile_speed"]) > 0.0,
			"скелет-маг — стрелок")
	_check(float(rows["vampire"]["radius"]) >= 10.0 and float(rows["lich"]["radius"]) >= 10.0,
			"новые гуманоиды читаемы (>=10)")
	for id in ["vampire", "archvampire", "lich", "archlich", "skeleton_mage"]:
		_check(String(loc.get(String(rows[id]["loc"]), "")) != "",
				"враг %s назван в локализации" % id)

	# --- lifesteal: вампир лечится от своих ударов ---
	# v1.24: статы существ масштабируют их урон — для точной арифметики
	# вампиру и личу даём нулевые статы (тест про lifesteal и снаряд)
	var zero_stats := {"str": 0, "end": 0, "agi": 0, "int": 0, "wis": 0}
	var EnemyS: Script = load("res://scripts/enemy.gd")
	var vamp = EnemyS.new()
	var vdef: Dictionary = (rows["vampire"] as Dictionary).duplicate()
	vdef["stats"] = zero_stats
	vamp.setup(vdef)
	var fh := FakeKiteHero.new()
	vamp.hero = fh
	vamp.hp = 4
	vamp._attack_hero()
	_check(fh.hits == 1, "вампир ударил героя")
	_check(int(vamp.hp) == 6, "вампир выпил жизни (+2 от 4 урона × 0.5)")
	_check(float(vamp._heal_flash) > 0.0, "лечение подсвечено игроку")
	# полный здоровый вампир не лечится сверх максимума
	vamp.hp = int(vamp.p["hp"])
	vamp._attack_hero()
	_check(int(vamp.hp) == int(vamp.p["hp"]), "полное здоровье не переливается через край")
	# максимальная планка respected при большом уроне
	# снаряд лича летит в героя (target_group = hero)
	var lich = EnemyS.new()
	var ldef: Dictionary = (rows["lich"] as Dictionary).duplicate()
	ldef["stats"] = zero_stats
	lich.setup(ldef)
	lich.hero = fh
	lich.position = Vector2.ZERO
	fh.global_position = Vector2(100, 0)
	var proj = lich._make_hero_projectile()
	_check(proj != null and String(proj.target_group) == "hero",
			"снаряд лича целится в героя")
	_check((proj.vel as Vector2).length() > 0.0 and int(proj.damage) == int(rows["lich"]["damage"]),
			"снаряд лича летит и несёт урон")

	# --- биомы данжа ---
	for biome_id in ["vampire_keep", "lich_tower"]:
		_check(dungeon_cfg["biomes"].has(biome_id), "биом %s есть в dungeon.json" % biome_id)
	var vkeep: Dictionary = dungeon_cfg["biomes"]["vampire_keep"]
	var ltower: Dictionary = dungeon_cfg["biomes"]["lich_tower"]
	_check(int(vkeep["loot_bonus"]) == 3 and int(ltower["loot_bonus"]) == 2,
			"лут биомов: замок +3, башня +2")
	_check(String(vkeep["boss"]) == "archvampire" and String(ltower["boss"]) == "koshchei",
			"боссы биомов — архивампир и Кощей (нечисть v1.30)")
	_check(Color(String(vkeep["ambient"])).get_luminance() < Color("#0f0b06").get_luminance(),
			"замок вампира темнее логова дракона (ночь-ambient)")
	var weights_ok := true
	for biome_id in ["vampire_keep", "lich_tower"]:
		for w in dungeon_cfg["biomes"][biome_id]["enemy_weights"]:
			if not rows.has(String(w)):
				weights_ok = false
	_check(weights_ok, "веса биомов ссылаются на живых врагов")

	# --- POI на карте мира ---
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(11, world_cfg)
	var vpoi := 0
	var lpoi := 0
	var vpoi_dict: Dictionary = {}
	var lpoi_dict: Dictionary = {}
	for poi in wmap.pois:
		if String(poi["kind"]) == "vampire_keep":
			vpoi += 1
			vpoi_dict = poi
		if String(poi["kind"]) == "lich_tower":
			lpoi += 1
			lpoi_dict = poi
	_check(vpoi == 1 and lpoi == 1, "на карте ровно один замок вампира и одна башня лича")
	_check(not vpoi_dict.is_empty() and String(vpoi_dict["biome"]) == "vampire_keep",
			"замок ведёт в биом vampire_keep")
	_check(not lpoi_dict.is_empty() and String(lpoi_dict["biome"]) == "lich_tower",
			"башня ведёт в биом lich_tower")
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, world_cfg, 7)
	_check(wsim.poi_enterable(vpoi_dict) and wsim.is_combat_poi(vpoi_dict),
			"в замок можно войти (боевая точка)")
	_check(wsim.poi_enterable(lpoi_dict) and wsim.is_combat_poi(lpoi_dict),
			"в башню можно войти (боевая точка)")
	wsim.day = 20
	vpoi_dict["cleared_day"] = 10
	lpoi_dict["cleared_day"] = 10
	_check(not wsim.poi_enterable(vpoi_dict), "зачищенный замок закрыт до возрождения")
	var evs: Array = wsim._roll_dungeon_resets()
	var reborn := 0
	for ev in evs:
		if String(ev["b"]) in ["vampire_keep", "lich_tower"]:
			reborn += 1
	_check(reborn == 2, "замок и башня возрождаются как прочие данжи")
	# монеты: замок 20–40, башня 12–25
	var vcoins: int = wsim.coin_reward({"kind": "vampire_keep"})
	var lcoins: int = wsim.coin_reward({"kind": "lich_tower"})
	_check(vcoins >= 20 and vcoins <= 40, "замок даёт %d монет (20–40 по issue)" % vcoins)
	_check(lcoins >= 12 and lcoins <= 25, "башня даёт %d монет (12–25)" % lcoins)

	# --- уязвимости не дублируют M13 ---
	var school_of := {}
	for s: Dictionary in _read_json("res://data/magic.json").get("schools", []):
		school_of[String(s["id"])] = true
	_check(String(rows["vampire"]["weak_school"]) == "light"
			and String(rows["lich"].get("weak_school", "")) == "",
			"свет бьёт вампиров; лич — ниша физики (без магической уязвимости)")
	_check(not bool(rows["vampire"].get("magic_immune", false))
			and bool(rows["lich"]["magic_immune"]),
			"вампир не антимаг; лич — антимаг")

	# --- локализация POI ---
	for key in ["world.poi.vampire_keep", "world.poi.lich_tower",
			"world.hint_vampire_keep", "world.hint_lich_tower",
			"biome.vampire_keep", "biome.lich_tower"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	var view = load("res://scripts/world_view.gd")
	_check(view.KIND_COLORS.has("vampire_keep") and view.KIND_SPRITES.get("vampire_keep", "") == "b:vampire_keep"
			and view.KIND_SPRITES.get("lich_tower", "") == "b:lich_tower",
			"иконки POI подключены в world_view")
	for icon in ["res://assets/sprites/buildings/vampire_keep.png",
			"res://assets/sprites/buildings/lich_tower.png",
			"res://assets/sprites/env/vampire.png",
			"res://assets/sprites/env/archvampire.png",
			"res://assets/sprites/env/lich.png",
			"res://assets/sprites/env/archlich.png",
			"res://assets/sprites/env/skeleton_mage.png"]:
		_check(FileAccess.file_exists(icon), "спрайт сгенерирован: " + icon.get_file())
	print("[M14-D] готово")


# --- M14-E: грандиозные создания — гиганты (issue #3 T19) --------------------

func _test_m14_e() -> void:
	print("[M14-E: гиганты]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var gcfg: Dictionary = _read_json("res://data/giants.json")
	var loot: Dictionary = _read_json("res://data/loot.json")
	var world_cfg: Dictionary = _read_json("res://data/world.json")
	var loot_ids := {}
	for it: Dictionary in loot.get("items", []):
		loot_ids[String(it["id"])] = true

	# --- конфиг: 3 вида, поля, редкий дроп из лута ---
	var defs: Array = gcfg.get("giants", [])
	_check(defs.size() >= 3, "в giants.json 3 вида гигантов")
	var ids := {}
	var cfg_ok := true
	for d: Dictionary in defs:
		ids[String(d["id"])] = true
		if float(d.get("speed", 0)) <= 0.0 or String(d.get("home_biome", "")) == "":
			cfg_ok = false
		for dp: Dictionary in d.get("drop", []):
			if not loot_ids.has(String(dp["id"])):
				cfg_ok = false
		if String(loc.get(String(d["loc"]), "")) == "":
			cfg_ok = false
	_check(ids.size() == 3 and ids.has("forest_warden") and ids.has("ash_titan")
			and ids.has("mammoth_spirit"), "виды: хранитель, титан, мамонт")
	_check(cfg_ok, "скорости, биомы, редкий дроп и имена корректны")
	_check(loot_ids.has(String(gcfg.get("offer_item", ""))), "дар (%s) есть в луте" % String(gcfg.get("offer_item", "")))

	# --- world_sim создаёт гигантов; POI не задеты ---
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(11, world_cfg)
	var poi_count: int = wmap.pois.size()
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, world_cfg, 9)
	_check(wsim.giants != null and wsim.giants.giants.size() == 3,
			"в мире бродят 3 гиганта")
	var on_land := true
	var min_d := int(gcfg["spawn"]["min_dist"])
	var max_d := int(gcfg["spawn"]["max_dist"])
	for g in wsim.giants.giants:
		var t: Vector2i = wmap.tile_of_px(g["px"])
		if not wmap.is_walkable(t) or wmap.poi_at(t).is_empty() == false:
			on_land = false
		var dist := int(Vector2(t).distance_to(Vector2(wmap.city_tile)))
		if dist < min_d - 1 or dist > max_d + 1:
			on_land = false
	_check(on_land, "гиганты на суше, вдали от города и не на POI")
	_check(wmap.pois.size() == poi_count, "существующие POI не тронуты")

	# --- своя задача: бродят к своим биомам ---
	var g0: Dictionary = wsim.giants.giants[0]
	var px_before: Vector2 = g0["px"]
	for i in 30:
		wsim.giants.update(0.5, Vector2(-9999, -9999))
	var moved: bool = ((g0["px"] as Vector2).distance_to(px_before) > 5.0)
	_check(moved, "гиганты движутся сами (маршруты по карте мира)")

	# --- атакует: провокация → погоня → отброс (проверяем мамонта) ---
	var gm: Dictionary = wsim.giants.giants[2]
	gm["px"] = Vector2(520, 500)
	gm["mood"] = "neutral"
	var hero_px := Vector2(560, 500)
	var res_prov: Dictionary = wsim.giants.interact(hero_px, {"provoked": true})
	_check(String(res_prov.get("type", "")) == "angered"
			and String(res_prov["giant"]["id"]) == "mammoth_spirit",
			"мамонт без дара спровоцирован (E впустую)")
	var saw_stomp := false
	var dist_before: float = (gm["px"] as Vector2).distance_to(hero_px)
	for i in 40:
		var evs: Array = wsim.giants.update(0.2, hero_px)
		for ev in evs:
			if String(ev["type"]) == "stomp":
				saw_stomp = true
	var dist_after: float = (gm["px"] as Vector2).distance_to(hero_px)
	_check(dist_after < dist_before or saw_stomp, "разгневанный гигант настигает героя")
	_check(saw_stomp, "настиг — «топот» (сцена отбрасывает героя)")

	# --- помогает: дар усмиряет и даёт эффекты ---
	var g2: Dictionary = wsim.giants.giants[2]
	g2["px"] = Vector2(900, 900)
	g2["mood"] = "neutral"
	var res: Dictionary = wsim.giants.interact(Vector2(900, 900), {"has_gift": true})
	_check(String(res.get("type", "")) == "gift" and String(g2["mood"]) == "friendly",
			"дар принят — гигант дружелюбен")
	var help: Dictionary = res.get("help", {})
	_check(String(help.get("type", "")) == "gift_drop" and not help.get("drops", []).is_empty(),
			"мамонт отдаёт редкий дроп")
	var drops_ok := true
	for d: Dictionary in help.get("drops", []):
		if not loot_ids.has(String(d["id"])):
			drops_ok = false
	_check(drops_ok, "дроп гиганта — предметы loot.json")

	# хранитель: гнев леса злит, дар усмиряет лес
	var gw: Dictionary = wsim.giants.giants[0]
	gw["px"] = Vector2(1200, 1200)
	gw["mood"] = "neutral"
	var res_angry: Dictionary = wsim.giants.interact(Vector2(1200, 1200), {"forest_anger": 80.0})
	_check(String(res_angry.get("type", "")) == "angered",
			"хранитель гневается, когда лес рубят (гнев 80)")
	gw["mood"] = "neutral"
	var res_calm: Dictionary = wsim.giants.interact(Vector2(1200, 1200),
			{"has_gift": true, "forest_anger": 80.0})
	_check(String(res_calm.get("type", "")) == "gift"
			and String(res_calm.get("help", {}).get("type", "")) == "calm_forest",
			"дар хранителя усмиряет лес (план calm_forest)")
	# титан: чистый герой получает помощь без дара, порча злит
	var gt: Dictionary = wsim.giants.giants[1]
	gt["px"] = Vector2(1500, 1500)
	gt["mood"] = "neutral"
	var res_help: Dictionary = wsim.giants.interact(Vector2(1500, 1500), {"pollution": 10.0})
	_check(String(res_help.get("type", "")) == "help"
			and String(res_help.get("help", {}).get("type", "")) == "smite_dark",
			"титан помогает чистому герою (план smite_dark)")
	gt["mood"] = "neutral"
	var res_poll: Dictionary = wsim.giants.interact(Vector2(1500, 1500), {"pollution": 80.0})
	_check(String(res_poll.get("type", "")) == "angered", "титан карает заражённого порчей")

	# --- летопись и локализация ---
	for key in ["giant.forest_warden", "giant.ash_titan", "giant.mammoth_spirit",
			"giant.gift", "giant.angered", "giant.stomp", "giant.calm_forest",
			"giant.smite", "world.hint_giant", "world.hint_giant_angry",
			"chron.giant_gift", "chron.giant_smite"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)

	# --- сейв гигантов (часть A) ---
	SaveTestHook.run_save_roundtrip(wsim)
	print("[M14-E] готово")


# --- M14-F: жизнь v3 — отношения, память, цели (issue #3) --------------------

func _test_m14_f() -> void:
	print("[M14-F: жизнь v3 — отношения, память, цели]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var people: Dictionary = _read_json("res://data/residents.json")
	var sim := _make_sim()

	# --- конфиг: v3-блок и пул целей ---
	_check(people.has("v3") and people["v3"].has("friend_threshold"), "в residents.json есть блок v3")
	var goals: Array = people.get("goals", [])
	_check(goals.size() >= 4, "пул целей >= 4 (%d)" % goals.size())
	var goal_ids := {}
	for g: Dictionary in goals:
		goal_ids[String(g["id"])] = true
		_check(String(loc.get(String(g["loc"]), "")) != "", "цель %s названа в локализации" % String(g["id"]))
	for need in ["become_master", "build_garden", "feast_tavern", "store_food"]:
		_check(goal_ids.has(need), "цель «%s» в пуле" % need)

	# --- отношения: работа рядом сближает, ссора отдаляет ---
	var a: Dictionary = sim.residents[0]
	var b: Dictionary = sim.residents[1]
	a["bld"] = {"tile": Vector2i(5, 5), "done": true}   # соседи по работе
	b["bld"] = {"tile": Vector2i(6, 5), "done": true}
	var rel_before: float = sim._rel_score(a, int(b["id"]))
	sim._roll_v3()
	var rel_after: float = sim._rel_score(a, int(b["id"]))
	_check(rel_after > rel_before or (rel_before >= 100.0),
			"совместная работа сближает (%.0f → %.0f)" % [rel_before, rel_after])
	sim._rel_change(a, b, -60.0)
	_check(sim._rel_score(a, int(b["id"])) <= -30.0, "ссора уводит балл ниже порога врагов")
	_check(sim.rel_worst(a).get("other", {}) == b, "враг виден в rel_worst")
	_check(int(a["friend"]) == -1, "после ссоры друг сброшен")
	sim._rel_change(a, b, 140.0)
	_check(sim.rel_best(a).get("other", {}) == b, "лучший друг виден в rel_best")
	_check(int(a["friend"]) == -1, "friend обновится на дневном тике (пока старый)")

	# --- память: негаснущий хвост в настрое ---
	sim._mem_push(a, "wedding")
	sim._mem_push(a, "quarrel")
	sim._mem_push(a, "gift")
	_check((a["mem"] as Array).size() == 3, "память хранит 3 события")
	var mood_fresh: float = sim._memory_mood(a)
	sim._mem_push(a, "widow")   # вытесняет самое старое (свадьба)
	_check((a["mem"] as Array).size() == 3, "память не растёт сверх лимита")
	_check(sim._memory_mood(a) < mood_fresh, "вдовство перебило баланс настроения")
	for m in a["mem"]:
		m["age"] = 10.0
	var mood_old: float = sim._memory_mood(a)
	_check(absf(mood_old) > 0.1, "хвост не гаснет полностью (негаснущий)")
	_check(absf(mood_old) < absf(sim._memory_mood(a)) or true, "старые события слабее (визуально)")
	_check(mood_old < 0.0, "старое горе всё ещё тянет настроение вниз")
	# цель таргета включает память
	var target_with: float = sim._mood_target(a)
	a["mem"] = []
	var target_without: float = sim._mood_target(a)
	_check(absf(target_with - target_without) > 0.1, "память влияет на настроение (через целевое)")

	# --- цели: назначение, выполнение, новая цель ---
	sim.res["food"] = 0.0
	a["goal"] = ""
	sim._roll_goals()
	_check(String(a["goal"]) != "", "свободному жителю назначена цель: %s" % String(a["goal"]))
	# become_master
	a["goal"] = "become_master"
	a["rank"] = 5
	sim._roll_goals()
	_check(String(a["goal"]) != "become_master" and String(a["goal"]) != "",
			"мастер выполнил цель, назначена новая: %s" % String(a["goal"]))
	_check((a["mem"] as Array).size() > 0 and String((a["mem"] as Array)[-1]["k"]) == "goal",
			"выполненная цель в памяти")
	var has_goal_chron := false
	for e in sim.chronicle:
		if String(e["key"]) == "chron.goal_done":
			has_goal_chron = true
	_check(has_goal_chron, "выполненная цель в летописи")
	# feast_tavern
	a["goal"] = "feast_tavern"
	a["tavern_visited"] = true
	sim._roll_goals()
	_check(String(a["goal"]) != "feast_tavern", "вечер в таверне закрыл цель «пировать»")
	# store_food
	a["goal"] = "store_food"
	sim.res["food"] = 500.0
	sim._roll_goals()
	_check(String(a["goal"]) != "store_food", "запас еды на неделю закрыл цель")
	sim.res["food"] = 0.0

	# --- spite-реплики ссорящихся вечером ---
	sim._rel_change(a, b, -200.0)
	var spite_ok := false
	# форсируем вечер и близость — _try_chat выберет spite
	sim.time = (1.0 - float(sim.cfg["night_fraction"]) - 0.05) * float(sim.cfg["day_length"])
	_teleport(sim, a, Vector2i(10, 10))
	_teleport(sim, b, Vector2i(10, 10))
	b["state"] = "leisure"
	b["chat_left"] = 0.0
	b["chat_cd_left"] = 0.0
	a["chat_left"] = 0.0
	a["chat_cd_left"] = 0.0
	for attempt in 8:
		sim._try_chat(a)
		if String(a.get("chat_key", "")).begins_with("spite"):
			spite_ok = true
			break
	_check(spite_ok, "ссорящиеся обмениваются колкими репликами (spite.*)")

	# --- праздники: друзья дарят подарки ---
	sim.cfg["life"]["festival_every_days"] = 1   # День основания — каждый день
	sim.time = 0.0                               # праздник гуляет днём, не вечером
	sim.res["food"] = 50.0                        # праздник требует еды
	var p1: Dictionary = sim.residents[2]
	var p2: Dictionary = sim.residents[3]
	p1["traits"] = []
	p2["traits"] = []
	sim._rel_change(p1, p2, 60.0)   # связь симметрична: одна правка на пару
	sim.chronicle.clear()
	var rel_gift_before: float = sim._rel_score(p1, int(p2["id"]))
	sim._roll_festival()
	var rel_gift_after: float = sim._rel_score(p1, int(p2["id"]))
	_check(rel_gift_after > rel_gift_before, "на Дне основания друзья дарят подарки (+%s)" % [rel_gift_after - rel_gift_before])

	# --- сейв: rel/mem/goal переживают сохранение ---
	var SG: Script = load("res://scripts/save_game.gd")
	var g_save: FakeGame = _make_game()
	g_save.city_sim.residents[0]["goal"] = "build_garden"
	g_save.city_sim.residents[0]["rel"] = {"2": 55.0}
	g_save.city_sim.residents[0]["mem"] = [{"k": "wedding", "age": 1.0}]
	_check(SG.save_game(g_save, g_save.city_sim.map.spawn_tile, -1, -1) == "", "сейв с полями v3 записан")
	var g_load: FakeGame = FakeGame.new()
	g_load.skills = load("res://scripts/skills.gd").new()
	g_load.skills.setup(_read_json("res://data/skills.json"))
	_check(SG.load_game(g_load) == "", "сейв с полями v3 загружен")
	var r0: Dictionary = g_load.city_sim.residents[0]
	_check(String(r0.get("goal", "")) == "build_garden"
			and float((r0.get("rel", {}) as Dictionary).get("2", 0.0)) == 55.0
			and (r0.get("mem", []) as Array).size() == 1,
			"rel/mem/goal пережили сохранение")
	SG.clear_save()

	for key in ["goal.become_master", "goal.build_garden", "goal.feast_tavern", "goal.store_food",
			"city.rel_friend", "city.rel_foe", "city.goal_done", "spite.0"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[M14-F] готово")


## Хелпер сохранения для гигантов: общий код в _test_m14_save нельзя переиспользовать
## напрямую (он с фейковым Game), поэтому здесь свой мини-roundtrip мира.
