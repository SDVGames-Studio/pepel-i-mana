# Жизнь: личности v3 (части g-l), правки v1.12, труд героя.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_m14_g() -> void:
	print("[M14-G: навыки следов]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var world_cfg: Dictionary = _read_json("res://data/world.json")
	var nests: Dictionary = world_cfg.get("nests", {})
	_check(nests.has("track_hide_per_level") and nests.has("track_len_shrink_per_level"),
			"настройки прятания следов в world.json")

	# длина цепочки падает с уровнем гнезда (3 уровня)
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(11, world_cfg)
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, world_cfg, 5)
	wsim._rng.seed = 77
	var len0: int = wsim._track_length_for(nests, 0)
	wsim._rng.seed = 77
	var len3: int = wsim._track_length_for(nests, 3)
	_check(len3 < len0, "следы гнезда 3 уровня короче (%d < %d)" % [len3, len0])

	# шанс появления падает с уровнем: много бросков на фиксированном сиде
	# (следы оставляют только гнёзда уровня >= 1; тайлы — проходимые)
	var rolls := 600
	var count1 := 0
	var count3 := 0
	var walk1: Vector2i = wmap.nearest_walkable(wmap.city_tile + Vector2i(10, 0))
	var walk3: Vector2i = wmap.nearest_walkable(wmap.city_tile + Vector2i(20, 0))
	var camp1: Dictionary = {"kind": "camp", "cleared_day": -1, "id": 900, "tile": walk1, "nest_level": 1}
	var camp3: Dictionary = {"kind": "camp", "cleared_day": -1, "id": 901, "tile": walk3, "nest_level": 3}
	for i in rolls:
		wsim.tracks = {}
		wsim._rng.seed = 3000 + i
		wsim.map.pois.append(camp1)
		wsim._roll_tracks()
		count1 += wsim.tracks.size()
		wsim.map.pois.erase(camp1)
		wsim.tracks = {}
		wsim._rng.seed = 3000 + i
		wsim.map.pois.append(camp3)
		wsim._roll_tracks()
		count3 += wsim.tracks.size()
		wsim.map.pois.erase(camp3)
	_check(count3 < count1, "гнездо 3 уровня заметает следы (%d < %d следов)" % [count3, count1])

	# узел «выжившего»: бонусы track_spot/track_wipe
	var sk = load("res://scripts/skills.gd").new()
	sk.setup(_read_json("res://data/skills.json"))
	sk.add_xp(400)   # XP на 4 узла
	for node_id in ["s1", "s2", "s3", "s4"]:
		sk.choose(node_id)
	var bonuses: Dictionary = sk.bonuses()
	_check(int(bonuses.get("track_spot", 0)) == 2 and int(bonuses.get("track_wipe", 0)) == 1,
			"узел выжившего даёт track_spot 2 и track_wipe 1")
	# замечание: неоткрытое гнездо рядом, след в 3 тайлах — без бонуса не виден
	var hero_tile: Vector2i = wmap.city_tile + Vector2i(5, 0)
	var hidden_camp: Dictionary = {"id": 998, "kind": "camp", "cleared_day": -1,
			"tile": hero_tile + Vector2i(4, 0), "discovered": false, "biome": "",
			"faction": "bandits", "strength": 1.0, "state": "ok"}
	wsim.map.pois.append(hidden_camp)
	wsim.tracks = {hero_tile + Vector2i(3, 0): {"dir": Vector2i(1, 0), "camp": 998, "age": 0}}
	var res_far: Dictionary = wsim.track_scout(hero_tile, 0, 0)
	_check(not bool(res_far["found"]), "след в 3 тайлах без бонуса не замечен (радиус 2)")
	var res_near: Dictionary = wsim.track_scout(hero_tile, 2, 0)
	_check(bool(res_near["found"]), "с узлом выжившего след замечен")
	wsim.map.pois.erase(hidden_camp)
	# заметание шире: след в 1 тайле стирается только с бонусом
	wsim.tracks = {hero_tile + Vector2i(1, 0): {"dir": Vector2i(1, 0), "camp": 999, "age": 0}}
	var res_wipe0: Dictionary = wsim.track_scout(hero_tile, 0, 0)
	_check(not bool(res_wipe0["wiped"]), "без бонуса след в 1 тайле не затёрт")
	var res_wipe1: Dictionary = wsim.track_scout(hero_tile, 0, 1)
	_check(bool(res_wipe1["wiped"]), "с бонусом след затёрт шире")
	_check(String(loc.get("tree.s4", "")) != "" and String(loc.get("tree.desc.s4", "")) != "",
			"узел s4 описан в локализации")
	print("[M14-G] готово")


# --- M14-H: законы, вера, дипломатия (issue #3) ------------------------------

func _test_m14_h() -> void:
	print("[M14-H: законы, вера, дипломатия]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var laws: Dictionary = _read_json("res://data/laws.json")
	var religion: Dictionary = _read_json("res://data/religion.json")
	var factions: Dictionary = _read_json("res://data/factions.json")
	var city_cfg: Dictionary = _read_json("res://data/city.json")
	var world_cfg: Dictionary = _read_json("res://data/world.json")
	var sim := _make_sim()

	# --- конфиги ---
	var law_ids := {}
	for l: Dictionary in laws.get("laws", []):
		law_ids[String(l["id"])] = true
		_check(String(loc.get(String(l["loc"]), "")) != "" and String(loc.get(String(l["desc"]), "")) != "",
				"закон %s описан" % String(l["id"]))
	for need in ["prohibition", "taxes", "refuge_shelter", "martial_law"]:
		_check(law_ids.has(need), "закон «%s» в laws.json" % need)
	var god_ids := {}
	for g: Dictionary in religion.get("gods", []):
		god_ids[String(g["id"])] = true
		_check(String(loc.get(String(g["loc"]), "")) != "", "божество %s названо" % String(g["id"]))
	_check(god_ids.has("ash") and god_ids.has("mana") and god_ids.has("home"), "пантеон: Пепел, Мана, Дом")
	var faction_ids := {}
	for f: Dictionary in factions.get("factions", []):
		faction_ids[String(f["id"])] = true
	_check(faction_ids.has("traders") and faction_ids.has("bandits") and faction_ids.has("cult"),
			"фракции описаны (торговцы/бандиты/культ + тьма)")
	# храм — здание со служкой
	var temple: Dictionary = {}
	for b: Dictionary in city_cfg.get("buildings", []):
		if String(b["id"]) == "temple":
			temple = b
	_check(not temple.is_empty() and String(temple["worker"]) == "acolyte", "храм со служкой-аколитом")

	# --- совет и голосование ---
	var council: Array = sim.council()
	_check(council.size() >= 3 and council.size() <= int(laws.get("council_size", 4)) + 1,
			"совет из %d жителей" % council.size())
	sim._event_rng.seed = 42
	for r in council:
		r["mood"] = 90.0   # довольный совет принимает
	var res_pass: Dictionary = sim.propose_law("taxes")
	_check(bool(res_pass["ok"]) and sim.has_law("taxes"), "налоги приняты голосованием (%d/%d)" % [int(res_pass["yes"]), int(res_pass["no"])])
	for r in council:
		r["mood"] = 5.0    # недовольный совет отменяет
	var res_repeal: Dictionary = sim.propose_law("taxes")
	_check(bool(res_repeal["ok"]) and not sim.has_law("taxes"), "повторное голосование отменило закон")
	_check(sim.propose_law("nonsense")["err"] == "law.unknown", "неизвестный закон отклонён")

	# --- эффекты законов ---
	sim.active_laws = ["taxes", "prohibition", "martial_law"]
	var farm: Dictionary = {"tile": Vector2i(5, 5), "done": true, "ench_mult": 1.0, "type": "farm"}
	sim.active_laws = ["taxes"]
	var mult_tax: float = sim.production_mult(farm)
	sim.active_laws = ["martial_law"]
	var mult_martial: float = sim.production_mult(farm)
	sim.active_laws = []
	var mult_base: float = sim.production_mult(farm)
	_check(mult_tax > mult_base and mult_martial < mult_base,
			"налоги ускорили (%.2f > %.2f), военное положение замедлило (%.2f < %.2f)" % [mult_tax, mult_base, mult_martial, mult_base])
	# настроение: налоги и сухой закон давят
	var r0: Dictionary = sim.residents[0]
	sim.active_laws = ["taxes", "prohibition"]
	var mood_with: float = sim._mood_target(r0)
	sim.active_laws = []
	var mood_without: float = sim._mood_target(r0)
	_check(mood_with < mood_without, "непопулярные законы давят настроение (%.1f < %.1f)" % [mood_with, mood_without])
	# сухой закон: ссоры реже (50% шанс отмены)
	sim.active_laws = ["prohibition"]
	var quarrel_block := 0
	for i in 200:
		sim._event_rng.seed = 500 + i
		var cnt_before: int = sim.events.size()
		sim._story_quarrel({"quarrel_mood": -1.0})
		if sim.events.size() == cnt_before:
			quarrel_block += 1
	_check(quarrel_block > 60, "сухой закон гасит ссоры (%d из 200)" % quarrel_block)
	sim.active_laws = []
	# военное положение: вышки бьют сильнее
	sim.active_laws = ["martial_law"]
	var mult_tower := 1.0
	for l in laws.get("laws", []):
		if String(l["id"]) == "martial_law":
			mult_tower = float(l["tower_mult"])
	_check(absf(mult_tower - 1.25) < 0.01, "военное положение: вышки ×1.25 (конфиг)")
	sim.active_laws = []

	# --- вера: молитва и благословения ---
	sim.god = ""
	sim.prayed_day = -1
	sim.res["wood"] = 100.0
	sim.res["stone"] = 100.0
	sim.res["crystal"] = 10.0
	_check(sim.pray("mana") == "god.no_temple", "без храма молитва не проходит")
	# строим храм со служкой
	var temple_site: Dictionary = _build_now(sim, "temple")
	_check(not temple_site.is_empty() and sim.temple_staffed(), "храм построен, служка назначен")
	_check(sim.pray("mana") == "", "молитва избирает Ману")
	var mp: Dictionary = sim.hero_mana_params()
	_check(int(mp["cap_extra"]) >= 4, "благословение Маны: +мана (%d)" % int(mp["cap_extra"]))
	sim.god = "home"
	var mt_god: float = sim._mood_target(sim.residents[0])
	sim.god = ""
	var mt_none: float = sim._mood_target(sim.residents[0])
	sim.god = "home"
	_check(mt_god > mt_none, "благословение Дома поддерживает город (%.1f против %.1f)" % [mt_god, mt_none])
	# повторная молитва в тот же день запрещена
	_check(sim.pray("ash") == "god.prayed_today", "молитва раз в день")
	# служба в праздник
	sim.cfg["life"]["festival_every_days"] = 1
	sim.time = 0.0
	sim.res["food"] = 50.0
	sim.chronicle.clear()
	sim._roll_festival()
	var has_service := false
	for e in sim.chronicle:
		if String(e["key"]) == "chron.service":
			has_service = true
	_check(has_service, "в праздник идёт служба в храме")

	# --- дипломатия: репутация ---
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(11, world_cfg)
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(wmap, world_cfg, 7)
	_check(absf(wsim.get_rep("traders")) < 0.01, "репутация с нуля")
	# сделка повышает репутацию торговцев
	var pool: Dictionary = {"wood": 0.0}
	var res_trade: Dictionary = wsim.trade_buy(pool, 100, "wood", 1, {"kind": "caravan"})
	_check(res_trade["err"] == "" and wsim.get_rep("traders") > 0.0, "сделка подняла репутацию торговцев")
	# зачистка лагеря: бандиты −, торговцы +
	var camp: Dictionary = {"kind": "camp", "id": 555, "tile": wmap.city_tile}
	wsim.map.pois.append(camp)
	wsim.mark_cleared(555)
	_check(wsim.get_rep("bandits") < 0.0 and wsim.get_rep("traders") > 0.0,
			"зачистка лагеря: бандиты −, торговцы +")
	# цены лучше с репутацией
	wsim.rep["traders"] = 60.0
	var price_high_rep: float = wsim.buy_price("wood", {"kind": "caravan"})
	wsim.rep["traders"] = 0.0
	var price_zero: float = wsim.buy_price("wood", {"kind": "caravan"})
	_check(price_high_rep < price_zero, "высокая репутация снижает цены (%.2f < %.2f)" % [price_high_rep, price_zero])
	# мир с бандитами останавливает осады
	wsim.rep["bandits"] = 100.0
	wsim.day += 1
	var evs: Array = wsim._roll_sieges()
	_check(evs.is_empty() or not any_siege_start(evs), "мир с бандитами: осад нет")
	# дань
	var ok_tribute: bool = wsim.tribute("cult")
	_check(ok_tribute and wsim.get_rep("cult") == float(factions.get("tribute_rep", 10)), "дань подняла репутацию культа")
	# заказ фракции от порога
	wsim.rep["cult"] = 60.0
	_check(wsim.faction_quest_available("cult"), "заказ культа доступен от репутации")

	for key in ["gov.title", "gov.laws", "gov.propose", "gov.law_passed", "law.taxes",
			"gov.faith", "god.ash", "god.mana", "god.home", "god.prayed", "god.no_temple",
			"gov.diplomacy", "gov.tribute", "city.temple_hint", "bld.temple",
			"chron.law_vote", "chron.service", "world.faction.angels"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[M14-H] готово")


func _test_m14_i() -> void:
	print("[M14-I: вода и болото]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var world_cfg: Dictionary = _read_json("res://data/world.json")
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(11, world_cfg)

	# болотный биом на карте мира с повышенной ценой тайла
	var swamp_tiles := 0
	var swamp_tile := Vector2i(-1, -1)
	for y in wmap.h:
		for x in wmap.w:
			if int(wmap.grid[y][x]) == wmap.TILE_SWAMP:
				swamp_tiles += 1
				if swamp_tile == Vector2i(-1, -1):
					swamp_tile = Vector2i(x, y)
	_check(swamp_tiles > 0, "болота есть на карте (%d тайлов)" % swamp_tiles)
	_check(wmap.tile_cost(swamp_tile) > wmap.tile_cost(wmap.city_tile),
			"болото замедляет путешествие (цена тайла выше)")

	# лодки: через озеро появляется путь
	var lake_tile := Vector2i(-1, -1)
	for y in wmap.h:
		for x in wmap.w:
			if int(wmap.grid[y][x]) == wmap.TILE_WATER:
				lake_tile = Vector2i(x, y)
				break
		if lake_tile.x >= 0:
			break
	_check(lake_tile.x >= 0, "озеро найдено")
	var neighbours := [lake_tile + Vector2i(1, 0), lake_tile + Vector2i(0, 1)]
	var shore_a: Vector2i = wmap.nearest_walkable(neighbours[0])
	var shore_b: Vector2i = wmap.nearest_walkable(neighbours[1])
	wmap.set_boats(false)
	var path_dry: int = wmap.tile_path(shore_a, shore_b).size()
	wmap.set_boats(true)
	var path_boat: int = wmap.tile_path(shore_a, shore_b).size()
	_check(path_boat > 0 and path_boat <= path_dry or path_boat > 0,
			"с лодкой путь через воду существует (%d тайлов)" % path_boat)
	_check(wmap.boats_enabled, "лодки включены")
	wmap.set_boats(false)

	# жаба живёт на болоте
	var fauna: Dictionary = _read_json("res://data/fauna.json")
	var wf = load("res://scripts/world_fauna.gd").new()
	wf.setup(wmap, fauna, 3)
	var swamp_species: Array = wf._species_for_biome("swamp")
	_check(swamp_species.has("toad") and swamp_species.size() == 1,
			"на болоте живёт жаба")
	_check(String(loc.get("fauna.toad", "")) != "", "жаба названа в локализации")

	# данж-биом болотной топи
	var dungeon_cfg: Dictionary = _read_json("res://data/dungeon.json")
	_check(dungeon_cfg["biomes"].has("swamp_mire"), "биом swamp_mire в dungeon.json")
	_check((world_cfg["pois"]["dungeon_biomes"] as Array).has("swamp_mire"),
			"болотные аномалии появляются на карте")

	# мост в городе: строится на воде, соединяет берега
	var sim := _make_sim()
	sim.res["wood"] = 50.0
	var water_t := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_WATER:
				water_t = Vector2i(x, y)
				break
		if water_t.x >= 0:
			break
	_check(water_t.x >= 0, "вода в городе найдена")
	_check(not sim.map.is_walkable(water_t), "вода непроходима до моста")
	_check(sim.is_buildable_tile(water_t, "bridge"), "мост можно заложить на воде")
	_check(not sim.is_buildable_tile(sim.map.spawn_tile, "bridge"), "мост на суше нельзя")
	_check(sim.place_building("bridge", water_t), "мост построен")
	_check(sim.map.is_walkable(water_t), "мост соединил берега")
	_check(sim.map.bridges.has(water_t), "мост зарегистрирован в карте")

	# лодка и лошадь: предметы и слот маунта
	var items: Dictionary = _read_json("res://data/items.json")
	var item_defs := {}
	for it: Dictionary in items.get("items", []):
		item_defs[String(it["id"])] = it
	_check(item_defs.has("boat") and String(item_defs["boat"]["craft"].get("where", "")) == "workshop",
			"лодка крафтится в мастерской")
	_check(item_defs.has("horse") and String(item_defs["horse"]["kind"]) == "mount",
			"лошадь — предмет слота «Ездовое»")
	var g = load("res://scripts/game.gd").new()
	g.add_item("horse", 1)
	_check(g.equip_item("horse") == "" and String(g.equipment["mount"]) == "horse",
			"лошадь надевается в слот маунта")
	var loc_ok := String(loc.get("item.boat", "")) != "" and String(loc.get("item.horse", "")) != "" \
			and String(loc.get("bld.bridge", "")) != "" and String(loc.get("biome.swamp_mire", "")) != ""
	_check(loc_ok, "лодка/лошадь/мост/биом названы в локализации")
	print("[M14-I] готово")


# --- M14-J: погода и сезоны (issue #3) ---------------------------------------

func _test_m14_j() -> void:
	print("[M14-J: погода и сезоны]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var wcfg: Dictionary = _read_json("res://data/weather.json")
	var sim := _make_sim()

	# --- сезоны циклятся по 12 дней ---
	sim.day = 1
	_check(sim.season() == "spring", "день 1 — весна")
	sim.day = 13
	_check(sim.season() == "summer", "день 13 — лето")
	sim.day = 25
	_check(sim.season() == "autumn", "день 25 — осень")
	sim.day = 37
	_check(sim.season() == "winter", "день 37 — зима")
	sim.day = 49
	_check(sim.season() == "spring", "день 49 — снова весна (цикл)")

	# --- погода бросается по весам сезона ---
	sim.day = 1
	var seen := {}
	for i in 400:
		sim._event_rng.seed = 900 + i
		sim._roll_weather()
		seen[sim.weather] = true
	var pool: Dictionary = wcfg["weather_by_season"]["spring"]
	var in_pool := true
	for w in seen:
		if not pool.has(w):
			in_pool = false
	_check(in_pool and seen.size() >= 2, "весенняя погода только из пула сезона (%s)" % ", ".join(seen.keys()))

	# --- эффекты: мультипликаторы урожая ---
	sim.weather = "clear"
	sim.day = 1
	var crop_base: float = sim.crop_mult()
	sim.weather = "rain"
	_check(sim.crop_mult() > crop_base, "дождь поливает поля")
	sim.day = 37   # зима
	sim.weather = "snow"
	_check(sim.crop_mult() < crop_base, "зимний снег глушит поля")
	sim.day = 25   # осень
	sim.weather = "clear"
	_check(sim.crop_mult() > 1.0, "осень жирнее")
	# лето: яблони
	sim.day = 13
	sim.weather = "clear"
	var orch_summer: float = sim.orchard_mult()
	sim.day = 37
	sim.weather = "ash_storm"
	var orch_ash_winter: float = sim.orchard_mult()
	_check(orch_summer > 1.0 and orch_ash_winter < 1.0,
			"лето яблони ×%.1f, буря ×%.1f" % [orch_summer, orch_ash_winter])

	# --- зима: отопление дровами ---
	sim.day = 37
	sim.weather = "snow"
	sim.res["wood"] = 10.0
	var wood_before: float = float(sim.res["wood"])
	var mood_before: float = float(sim.residents[0]["mood"])
	sim._roll_weather()
	_check(float(sim.res["wood"]) < wood_before, "зимой топят печи (дрова уходят)")
	_check(not sim.froze_last_night, "с дровами город не мёрзнет")
	sim.res["wood"] = 0.0
	sim._roll_weather()
	_check(sim.froze_last_night, "без дров город мёрзнет")
	var mood_frozen: float = float(sim.residents[0]["mood"])
	var target_frozen: float = sim._mood_target(sim.residents[0])
	_check(target_frozen <= 60.0, "мёрзлая зима давит настроение")
	# зимняя еда: тратится быстрее
	sim.res["food"] = 100.0
	var food0: float = float(sim.res["food"])
	sim.tick(float(sim.cfg["day_length"]) * 0.5)
	_check(sim.res["food"] < food0, "зимой едят больше")

	# --- туман прячет от рейдов: следующий налёт отложен ---
	sim._next_raid_at = 5000.0
	var got_fog := false
	for i in 200:
		sim._event_rng.seed = 7000 + i
		sim._roll_weather()
		if sim.weather == "fog":
			got_fog = true
			break
	_check(got_fog and sim._next_raid_at > 5000.0, "туман откладывает рейд")

	# --- локализация ---
	for season in ["spring", "summer", "autumn", "winter"]:
		_check(String(loc.get("season." + season, "")) != "", "сезон %s назван" % season)
	for w in ["clear", "rain", "snow", "fog", "ash_storm"]:
		_check(String(loc.get("weather." + w, "")) != "", "погода %s названа" % w)
	print("[M14-J] готово")


# --- M14-K: квесты и кодекс (issue #3) ---------------------------------------

func _test_m14_k() -> void:
	print("[M14-K: квесты и кодекс]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var qcfg: Dictionary = _read_json("res://data/quests.json")
	var sim := _make_sim()

	# --- доска: 3-5 заказов в день, у каждого заказчик ---
	sim._roll_quests()
	_check(sim.quests.size() >= int(qcfg.get("per_day_min", 3)),
			"на доске %d заказов" % sim.quests.size())
	var customers_ok := true
	var kinds_ok := true
	for q in sim.quests:
		if String(q.get("customer", "")) == "":
			customers_ok = false
		if String(q.get("kind", "")) not in ["bring", "hunt", "build"]:
			kinds_ok = false
	_check(customers_ok, "у каждого заказа есть заказчик по имени")
	_check(kinds_ok, "виды заказов: принести/охота/постройка")

	# bring: сдать предметы
	var bring: Dictionary = {}
	for q in sim.quests:
		if String(q["kind"]) == "bring":
			bring = q
			break
	var bring_guard := 0
	while bring.is_empty() and bring_guard < 30:
		sim._spawn_quest(sim._quests_cfg())
		bring_guard += 1
		for q in sim.quests:
			if String(q["kind"]) == "bring":
				bring = q
				break
	_check(not bring.is_empty(), "есть заказ «принести» (досыпали за %d попыток)" % bring_guard)
	var inv: Array = [{"id": String(bring["item"]), "count": int(bring["need"])}]
	var reward0: int = int(bring["reward"])
	_check(sim.quest_deliver(int(bring["id"]), inv) == "", "заказ сдан")
	_check(inv.is_empty() or int(inv[0]["count"]) == 0, "предметы списаны")
	_check(not sim.quests.has(bring), "выполненный заказ снят с доски")
	_check(sim.quest_deliver(int(bring["id"]), inv) == "quest.gone", "повторная сдача невозможна")

	# hunt: счётчик охоты
	var hunt: Dictionary = {}
	for q in sim.quests:
		if String(q["kind"]) == "hunt":
			hunt = q
			break
	if not hunt.is_empty():
		sim.quest_hunted()
		sim.quest_hunted()
		_check(int(hunt["progress"]) >= 2 or not sim.quests.has(hunt),
				"охота двигает заказ")

	# build: постройка закрывает заказ. Доску чистим: случайный дневной заказ
	# «построить сад» мог стоять раньше нашего — quest_built закрывает первый,
	# и проверка флеймит (наблюдение прогонов 2026-10-20)
	sim.quests.clear()
	var build: Dictionary = {"kind": "build", "id": 4242, "customer": "Тест", "type": "garden",
			"need": 1, "progress": 0, "reward": 5, "days": 2}
	sim.quests.append(build)
	sim.quest_built("garden")
	_check(not sim.quests.has(build), "постройка сада закрыла заказ «построить»")

	# тухнут по дням
	var old: Dictionary = {"kind": "hunt", "id": 777, "customer": "Старик", "need": 5,
			"progress": 0, "reward": 1, "days": 0}
	sim.quests.append(old)
	sim._roll_quests()
	_check(not sim.quests.has(old), "просроченные закази уходят")

	# --- кодекс и статистика ---
	var g = load("res://scripts/game.gd").new()
	g.codex_seen("enemies", "rat")
	g.codex_seen("enemies", "rat")
	g.codex_seen("enemies", "skeleton")
	_check(g.codex_count("enemies") == 2, "кодекс не дублирует записи")
	g.add_item("rune_light", 1)
	_check(g.codex_count("items") == 1, "руна попала в кодекс")
	g.learn_spell("heal")
	_check(g.codex_count("spells") == 1, "заклинание в кодексе")
	g.stat("bosses", 2)
	g.stat("days", 12)
	_check(int(g.stats["bosses"]) == 2 and int(g.stats["days"]) == 12, "статистика копится")

	for key in ["quest.title", "quest.bring", "quest.hunt", "quest.build", "quest.deliver",
			"city.quest_done", "codex.title", "codex.enemies", "codex.biomes", "stats.title",
			"stats.days", "stats.bosses"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[M14-K] готово")


# --- M14-L: сюжетная рамка (issue #3) ----------------------------------------

func _test_m14_l() -> void:
	print("[M14-L: сюжетная рамка]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var sim := _make_sim()

	# глава 1 открывается сразу, глава 2 ждёт 10 жителей
	sim._roll_story()
	_check(sim.story_chapter == 1, "глава 1 «Прибытие» открыта")
	var ev_ok := false
	for e in sim.events:
		if String(e["type"]) == "story":
			ev_ok = true
	_check(ev_ok, "глава пришла событием (тост + летопись)")
	sim.events.clear()
	# жители 10 — глава 2
	while sim.residents.size() < 10:
		sim.residents.append({"id": 900 + sim.residents.size(), "name": "Т", "prof": "farmer"})
	sim._roll_story()
	_check(sim.story_chapter == 2, "глава 2 «Рост» открыта (10 жителей)")
	# тьма: визит в тёмный данж
	sim.story_progress("dark_visit", true)
	sim._roll_story()
	_check(sim.story_chapter == 3, "глава 3 «Тьма» открыта визитом")
	# зов: порча 30
	sim.pollution = 35.0
	sim._roll_story()
	_check(sim.story_chapter == 4, "глава 4 «Зов» открыта порчей")
	# финал: без условий не наступает
	sim._roll_story()
	_check(sim.story_chapter == 4 and sim.story_side == "", "финал ждёт выбора города")
	# Пепел: высокая порча
	sim.pollution = 70.0
	sim._roll_story()
	_check(sim.story_side == "ash", "город избрал Пепел (порча 70)")
	sim._roll_story()
	_check(sim.story_chapter == 6, "финал Пепла открыт (глава %d)" % sim.story_chapter)
	# песочница: после финала мир продолжает тикать
	var day_before: int = sim.day_number()
	sim._roll_quests()
	sim._roll_weather()
	_check(sim.day_number() >= day_before, "песочница продолжается после финала")
	var chron_ok := false
	for e in sim.chronicle:
		if String(e["key"]) == "chron.story":
			chron_ok = true
	_check(chron_ok, "сюжет в летописи")
	# ключи глав и сторон
	for key in ["story.arrival", "story.growth", "story.darkness", "story.call",
			"story.finale_mana", "story.finale_ash", "story.side.mana", "story.side.ash"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[M14-L] готово")


# --- Правки по фидбеку v1.12.0 (v1.12.1): соло-старт, поселенцы, автономия ---

func _test_fixes_v121() -> void:
	print("[Правки v1.12.0: соло-старт, поселенцы, автономия]")
	var loc: Dictionary = _read_json("res://loc/ru.json")

	# регрессия v1.11.0: опечатка в city_weather.gd не попала в рукописный список
	# ALL_SCRIPTS, скрипт не грузился — у города пропали HUD и выход на карту
	var weather: Script = load("res://scripts/city_weather.gd")
	_check(weather != null and weather.can_instantiate(),
			"city_weather.gd компилируется (урок v1.11.0: список скриптов сканируется)")

	# --- соло-старт: герой начинает один ---
	var city_cfg: Dictionary = _read_json("res://data/city.json")
	_check(int(city_cfg["start"]["residents_default"]) == 1, "city.json: старт с одного жителя")
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(7, city_cfg)
	var solo = load("res://scripts/city_sim.gd").new()
	solo.setup(city_map, city_cfg, 1, "normal")
	solo._next_raid_at = 999999999.0
	_check(solo.residents.size() == 2, "соло-старт: основатель + голем-староста (v1.20)")
	_check(String(solo.residents[0]["prof"]) != "elder" and String(solo.residents[1]["prof"]) == "elder",
			"основатель — работник, городом правит голем-староста")
	_check(bool(solo.residents[1].get("golem", false)), "староста — голем (белый кружок)")
	_check(solo.pop_cap() >= 2, "лимит населения вмещает основателя и голема")

	# --- поселенцы приходят постепенно: ранний бонус малому городу ---
	var residents_cfg: Dictionary = _read_json("res://data/residents.json")
	var rcfg: Dictionary = residents_cfg["refugees"]
	_check(float(rcfg.get("early_bonus", 0.0)) > 0.0 and int(rcfg.get("early_below", 0)) > 1,
			"residents.json: ранний бонус поселенцам настроен")
	var solo_chance: float = solo._refugee_chance()
	_check(absf(solo_chance - (float(rcfg["chance_per_day"]) + float(rcfg["early_bonus"]))) < 0.0001,
			"одинокому городу положен ранний бонус к поселенцам")
	solo.autonomous = true
	_check(absf(solo._refugee_chance() - solo_chance * float(city_cfg["autonomy"]["refugee_mult"])) < 0.0001,
			"автономная деревня притягивает поселенцев (×%.1f)" % float(city_cfg["autonomy"]["refugee_mult"]))
	solo.autonomous = false

	# --- автономия с 10 поселенцев ---
	var sim := _make_sim()   # 6 жителей
	var autonomy_pop: int = sim.autonomy_pop()
	_check(autonomy_pop == 10, "порог автономии — 10 поселенцев")
	_check(not sim.can_autonomy(), "6 жителей — автономия пока рано")
	_check(sim.go_autonomous() == "city.autonomy_need", "ранняя автономия честно отклоняется")
	while sim.residents.size() < autonomy_pop:
		sim.residents.append(sim._new_resident("Гость %d" % sim.residents.size(), "farmer", sim.map.spawn_tile))
	var mood_before: float = sim._mood_target(sim.residents[0])
	# большому городу ранний бонус уже не положен
	_check(absf(sim._refugee_chance() - float(rcfg["chance_per_day"])) < 0.0001,
			"город с 10 жителями растёт по обычному шансу")
	_check(sim.can_autonomy(), "с %d поселенцев автономия доступна" % autonomy_pop)
	_check(sim.go_autonomous() == "", "автономия объявляется")
	_check(bool(sim.autonomous), "флаг автономии включён")
	_check(sim.go_autonomous() == "city.autonomy_done", "повторное объявление не требуется")
	var ev_ok := false
	for e in sim.events:
		if String(e["type"]) == "autonomy":
			ev_ok = true
	_check(ev_ok, "автономия пришла событием (тост)")
	var chron_ok := false
	for e in sim.chronicle:
		if String(e["key"]) == "chron.autonomy":
			chron_ok = true
	_check(chron_ok, "автономия записана в летопись")
	_check(is_equal_approx(sim._mood_target(sim.residents[0]) - mood_before,
			float(city_cfg["autonomy"]["mood"])),
			"автономия поднимает настроение (+%.0f)" % float(city_cfg["autonomy"]["mood"]))

	# --- автономная деревня строит сверх плана ---
	for t: String in sim.cfg["autobuild_plan"]:
		sim.buildings.append({"type": t, "done": true})
	sim.autonomous = false
	_check(sim._next_plan_need() == "", "базовый план самостроя закрыт")
	_check(sim._next_plan_need() == "", "без автономии сверх плана не строится")
	sim.autonomous = true
	# расширенный план добирает дома раньше храма — проверяем поведение целиком:
	# первый шаг существует в каталоге зданий, и план конечен
	var need_auto: String = sim._next_plan_need()
	_check(need_auto != "", "автономная деревня строит сверх плана (первое: %s)" % need_auto)
	var known := false
	for b: Dictionary in city_cfg["buildings"]:
		if String(b["id"]) == need_auto:
			known = true
	_check(known, "здание из расширенного плана существует: %s" % need_auto)
	var guard := 0
	while need_auto != "" and guard < 100:
		guard += 1
		sim.buildings.append({"type": need_auto, "done": true})
		need_auto = sim._next_plan_need()
	_check(need_auto == "", "расширенный план автономии завершается")

	# --- автономия переживает сейв ---
	var SG: Script = load("res://scripts/save_game.gd")
	SG.clear_save()
	var g1 := _make_game()
	g1.city_sim.autonomous = true
	_check(SG.save_game(g1, g1.city_sim.map.spawn_tile, 7, 3) == "", "сейв автономной деревни сохранён")
	var g2 := FakeGame.new()
	g2.skills = load("res://scripts/skills.gd").new()
	g2.skills.setup(_read_json("res://data/skills.json"))
	_check(SG.load_game(g2) == "", "сейв автономной деревни загружен")
	_check(bool(g2.city_sim.autonomous), "автономия переживает сейв")
	SG.clear_save()

	# --- ключи локализации ---
	for key in ["city.autonomy_btn", "city.autonomy_done_btn", "city.autonomy_need",
			"city.autonomy_done", "city.autonomy_tip", "chron.autonomy", "menu.solo_start"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[Правки v1.12.0] готово")


# --- Правки v1.12.2: ручной труд героя (добыча и стройка) --------------------

func _test_hero_work() -> void:
	print("[Правки v1.12.2: герой добывает и строит]")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	var sim := _make_sim()
	var hw: Dictionary = sim.cfg.get("hero_work", {})
	_check(not hw.is_empty(), "city.json: настроен ручной труд героя")

	# --- рубка дерева ---
	var tree := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_TREE:
				tree = Vector2i(x, y)
				break
		if tree.x >= 0:
			break
	_check(tree.x >= 0, "на карте есть дерево для героя")
	var wood0 := int(sim.res["wood"])
	var anger0 := float(sim.forest_anger)
	var tree_size: int = sim.map.tree_kind(tree)
	var res := ""
	for i in maxi(1, sim._hero_chop_hits(tree_size)):
		res = sim.hero_chop(sim.map.tile_center_px(tree))
	_check(res == "fell", "герой валит дерево за %d ударов" % sim._hero_chop_hits(tree_size))
	_check(sim.map.grid[tree.y][tree.x] == sim.map.TILE_GRASS and sim.map.stumps.has(tree),
			"на месте дерева остался пень")
	_check(int(sim.res["wood"]) == wood0 + int(sim._planks_for(tree_size)),
			"доски по размеру дерева легли в общий пул (v1.21)")
	_check(absf(sim.forest_anger - anger0 - float(sim.cfg["forest"]["anger_per_tree"])) < 0.001,
			"гнев леса растёт по тем же правилам, что у лесоруба")
	# вдали от леса герой не рубит (ищем тайл без деревьев вокруг)
	var lonely := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			var t := Vector2i(x, y)
			if not sim.map.is_walkable(t):
				continue
			var clean := true
			for n in [t, t + Vector2i(1, 0), t + Vector2i(-1, 0), t + Vector2i(0, 1), t + Vector2i(0, -1)]:
				if sim.map.in_bounds(n) and sim.map.grid[n.y][n.x] == sim.map.TILE_TREE:
					clean = false
					break
			if clean:
				lonely = t
				break
	_check(lonely.x >= 0 and sim.hero_chop(sim.map.tile_center_px(lonely)) == "",
			"вдали от леса герой не рубит")

	# --- добыча скалы ---
	var near_rock := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			var t := Vector2i(x, y)
			if sim.map.is_walkable(t) and not sim._rock_tile_near(sim.map.tile_center_px(t)) == Vector2i(-1, -1):
				near_rock = t
				break
		if near_rock.x >= 0:
			break
	_check(near_rock.x >= 0, "на карте есть скала в шаге от проходимого тайла")
	var target: Vector2i = sim._rock_tile_near(sim.map.tile_center_px(near_rock))
	var stone0 := int(sim.res["stone"])
	var hp0 := float(sim.map.rock_hp.get(target, 0.0))
	res = sim.hero_mine(sim.map.tile_center_px(near_rock))
	_check(res == "hit", "удар киркой засчитан")
	_check(int(sim.res["stone"]) == stone0 + int(hw.get("stone_per_hit", 2)), "камень в общий пул за удар")
	_check(float(sim.map.rock_hp.get(target, 0.0)) < hp0, "жила вырабатывается")
	res = ""
	var guard := 0
	while not res in ["ore", "gem", "stone"] and guard < 10:
		guard += 1
		res = sim.hero_mine(sim.map.tile_center_px(near_rock))
	_check(res in ["ore", "gem", "stone"], "выработанная жила даёт исход: " + res)
	_check(int(sim.res["stone"]) > stone0, "добыча не пропала даром")

	# --- стройка героем (соло-старт) ---
	# правка 2026-10-21: староста — последний резерв стройки (иначе соло-город
	# вечно стоит на площадках и жители не приходят), герой помогает руками
	var elder_only = load("res://scripts/city_sim.gd").new()
	elder_only.setup(sim.map, sim.cfg, 1, "normal")
	elder_only._last_daily_day = 1
	var spot := _find_free_tile(elder_only, elder_only.map.spawn_tile)
	_check(spot != Vector2i(-1, -1), "найдено место под дом")
	_check(elder_only.place_building("house", spot), "герой поставил площадку дома")
	var site: Dictionary = elder_only.building_at(spot)
	_check(not site.is_empty() and not bool(site["done"]), "стройка ждёт мастера")
	elder_only._assign_jobs()
	var elder_r: Dictionary = {}
	for r in elder_only.residents:
		if String(r["prof"]) == "elder":
			elder_r = r
	_check(int(site["worker"]) == int(elder_r["id"]) or int(site["worker"]) == int(elder_only.residents[0]["id"]),
			"при соло-старте стройку берёт основатель или голем-староста (резерв строителя)")
	var guard2 := 0
	res = ""
	while not bool(site["done"]) and guard2 < 100:
		guard2 += 1
		res = elder_only.hero_build(elder_only.map.tile_center_px(spot))
	_check(res == "done", "герой достраивает дом сам")
	_check(bool(site["done"]), "дом готов")
	var built_ev := false
	for e in elder_only.events:
		if String(e["type"]) == "built" and String(e["bld"]) == "house":
			built_ev = true
	_check(built_ev, "достройка пришла событием (тост)")
	_check(elder_only.hero_build(elder_only.map.tile_center_px(Vector2i(0, 0))) == "",
			"вдали от стройки герой не стучит")

	# --- ключи локализации ---
	for key in ["city.hint_build", "city.hint_chop", "city.hint_mine", "city.hint_mine_ore",
			"city.hero_tree_felled", "city.hero_rock_done", "city.hero_ore_found",
			"city.hero_gem_found", "city.founder_hint"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[Правки v1.12.2] готово")


## Этап 2, аспект 1 — схематичный режим зданий: данные должны быть полными
## (категория с цветом, краткая и полная подписи у каждого здания).
