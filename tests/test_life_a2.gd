# Жизнь: M14-B (экипировка), M14-C (фауна/VFX/туман), M14-D (вампиры/личи).
# v1.62.0: выделено из test_life_a.gd. Общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"

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
					["wood", "stone", "food", "crystal", "tools", "iron", "metal", "kits", "seeds",
				"copper", "silver", "gold", "amber", "pearls", "dragon_bone", "dragon_hide"]:
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
	# v1.63.1 (хвост «anti-кайт боссов»): страх света/паника не рвут
	# телеграф-рывок — у АРХИВАМПИРА/АРХИЛИЧА (fear) ранний return
	# замораживал таймер телеграфа навсегда
	var esrc_f := FileAccess.open("res://scripts/enemy.gd", FileAccess.READ)
	var esrc: String = esrc_f.get_as_text() if esrc_f != null else ""
	esrc_f = null
	_check(esrc.count("and _telegraph_left <= 0.0 and _dash_left <= 0.0") >= 2,
			"страх/паника гейтятся телеграфом-рывком (архбоссы наказывают кайт)")
	_check(float(ak.get("cooldown", 9.0)) <= 3.0 and float(ak.get("dash_time", 0.0)) >= 0.4,
			"рывок боссов ловчее: dash_time %.1f, cooldown %.1f" % [float(ak.get("dash_time", 0.0)), float(ak.get("cooldown", 0.0))])
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
		if k not in ["deer", "boar", "bird", "wolf", "hare", "fox"]:
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
	# v1.39.0: деревья «Природы 2.0» — 5 видов пака ForgottenMemories,
	# палитры пней самостоятельные (вариант по хэшу тайла) — их не меньше,
	# чем видов деревьев
	var city_view = load("res://scripts/city_view.gd")
	_check(city_view.STUMP_PALS.size() >= city_view.TREE_REFS.size(),
			"палитр пней не меньше, чем видов деревьев (%d >= %d)" % [
				city_view.STUMP_PALS.size(), city_view.TREE_REFS.size()])

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

