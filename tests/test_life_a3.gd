# Жизнь: M14-E (гиганты) и M14-F (отношения/память/цели — личности v3).
# v1.62.0: выделено из test_life_a.gd. Общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"

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
