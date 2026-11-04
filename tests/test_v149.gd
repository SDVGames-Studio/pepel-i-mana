# v1.49 («Город живёт»): текстуры зданий/жителя/героя, потолок скорости боя,
# XP героя за оборону города, боевые заклинания героя в городе, темп улья.
extends "res://tests/test_base.gd"


func _test_v149_combat() -> void:
	print("[v1.49: бой в городе]")
	var sim := _make_sim()
	# потолок скорости боя: конфиг читается, ускорение x10 бой не разгоняет
	_check(sim.cfg.has("combat_speed_cap"), "в city.json есть combat_speed_cap")
	var cap: float = float(sim.cfg.get("combat_speed_cap", 3.0))
	_check(cap < 10.0 and cap >= 2.0, "потолок боя разумный (%.1f < x10)" % cap)
	# волна + убийство РУКАМИ ГЕРОЯ даёт событие hero_kill с XP
	sim._next_raid_at = 999999999.0
	sim._spawn_raid(2, false)
	_check(sim.raiders.size() == 2, "волна из двух мутантов для теста")
	var r0: Dictionary = sim.raiders[0]
	var xp_expect: int = int(r0["p"].get("xp", 0))
	_check(xp_expect > 0, "у мутанта есть XP (%d)" % xp_expect)
	sim.events.clear()
	sim._hit_raider(r0, 99999, Vector2i(-9999, -9999), "hero")
	var found := false
	for ev in sim.events:
		if String(ev["type"]) == "hero_kill" and int(ev["xp"]) == xp_expect:
			found = true
	_check(found, "убийство героем — событие hero_kill с XP")
	# чужая рука (вышка) — события нет
	sim.events.clear()
	if not sim.raiders.is_empty():
		sim._hit_raider(sim.raiders[0], 99999, Vector2i(-9999, -9999), "tower")
		found = false
		for ev in sim.events:
			if String(ev["type"]) == "hero_kill":
				found = true
		_check(not found, "убийство вышкой XP герою не даёт")
	# боевое заклинание: burst бьет ближайших, возвращает суммарный урон
	sim.raiders.clear()
	sim.raid_active = false
	var def: Dictionary = {}
	for e in sim._read_json_file("res://data/enemies.json"):
		if String(e["id"]) == "rat":
			def = e
			break
	_check(not def.is_empty(), "деф крысы для теста найден")
	var base: Vector2 = sim.map.tile_center_px(sim.map.spawn_tile)
	var near := { "id": 1, "type": "rat", "p": def, "hp": int(def["hp"]), "max_hp": int(def["hp"]),
			"pos": base + Vector2(20, 0), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "atk_cd": 0.0, "mode": "advance" }
	var far := { "id": 2, "type": "rat", "p": def, "hp": int(def["hp"]), "max_hp": int(def["hp"]),
			"pos": base + Vector2(400, 0), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "atk_cd": 0.0, "mode": "advance" }
	sim.raiders.append(near)
	sim.raiders.append(far)
	var res: Dictionary = sim.hero_spell_burst(base, 60.0, 99, 1)
	_check(int(res["hits"]) == 1, "burst с лимитом бьет одного")
	_check(int(res["dmg"]) == int(def["hp"]), "суммарный урон посчитан (%d)" % int(res["dmg"]))
	_check(sim.raiders.size() == 1 and sim.raiders[0]["id"] == 2,
			"ближайший поражен, дальний жив (цепная молния)")
	# замедление корнями: оставшаяся крыса — дальняя (base+400,0)
	sim.slow_raiders_at(sim.raiders[0]["pos"], 60.0, 3.0)
	_check(float(sim.raiders[0].get("slow_left", 0.0)) > 0.0, "корни ставят slow_left")


func _test_v149_assets() -> void:
	print("[v1.49: ассеты героя и жителей]")
	var HeroSc = load("res://scripts/hero.gd")
	var frames: SpriteFrames = HeroSc.build_knight_frames()
	_check(frames != null, "SpriteFrames рыцаря построился")
	for anim in ["idle", "run", "attack", "roll", "death"]:
		_check(frames.has_animation(anim), "анимация рыцаря: %s" % anim)
	_check(frames.get_frame_count("idle") == 10, "idle — 10 кадров FreeKnight")
	_check(frames.get_frame_count("attack") == 4, "attack — 4 кадра")
	# жители: маппинг профессий на листы Minifolks
	var AssetsSc = load("res://scripts/assets.gd")
	_check(AssetsSc.VILLAGER_PROF.has("lumberjack"), "лесоруб имеет лист Minifolks")
	_check(not AssetsSc.VILLAGER_PROF.has("guard"), "страж без листа — кружок (листа нет)")
	_check(AssetsSc.tex("res://assets/sprites/villagers/MiniLumberjack.png") != null,
			"лист лесоруба загружается")
	_check(AssetsSc.tex("res://assets/sprites/hero/knight_Idle.png") != null,
			"лист героя загружается")


func _test_v149_configs() -> void:
	print("[v1.49: конфиги живого города]")
	var c: Dictionary = _read_json("res://data/city.json")
	var en: Dictionary = c.get("extra_nature", {})
	_check(int(en.get("trees", 0)) >= 500, "добор леса >= 500 (всего ~850)")
	_check(int(en.get("rocks", 0)) >= 4, "добор скал >= 4")
	_check(int(en.get("ponds", 0)) >= 3, "новых прудов >= 3")
	var h: Dictionary = c.get("hunting", {})
	_check(int(h.get("animals", 0)) >= 35, "зверя >= 35")
	var w: Dictionary = _read_json("res://data/world.json")
	var nc: Dictionary = w.get("npc_city", {})
	_check(int(nc.get("map_w", 0)) == 192 and int(nc.get("map_h", 0)) == 144,
			"поселения НПС 192×144")
	# спрайты зданий подключены
	var spr := {}
	for b in c.get("buildings", []):
		spr[String(b["id"])] = String(b.get("sprite", ""))
	_check(spr.get("tavern", "") == "b:таверна", "таверна — текстура Celianna")
	_check(spr.get("forge", "") == "b:кузница", "кузница — текстура Celianna")
	_check(spr.get("warehouse", "") == "b:склад", "склад — текстура Celianna")
	_check(String(spr.get("house", "")).begins_with("b:дом_жителей"), "дом — craftpix")
	# темп улья v1.49
	var HiveSim = load("res://scripts/hive_sim.gd")
	_check(HiveSim.wave_days(1) >= 3.5, "улей: первая волна не чаще ~4 дней")
	_check(HiveSim.RESPAWN_DAYS >= 12, "разорённый улей отрастает не быстро")


## Чтение JSON без автозагрузок (как в test_core).
func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
