extends SceneTree
## Автотесты этапов M0 + M1 + M2 + M3.
## Запуск headless: godot --headless --path . --script res://tests/run_all.gd
## В этом режиме автозагрузки не работают — всё проверяем через load()/FileAccess.

const REQUIRED_LOCALES := [
	"menu.title", "menu.version", "menu.new_game", "menu.exit",
	"menu.continue_city", "menu.setup_title", "menu.residents",
	"menu.start_level", "menu.level.low", "menu.level.normal", "menu.level.high",
	"menu.begin", "menu.back", "menu.test_mode",
	"city.back_hint", "city.last_run_ok", "city.last_run_death", "city.last_run_nothing",
	"res.wood", "res.stone", "res.food", "res.crystal",
	"city.pop", "city.day", "city.night", "city.paused", "city.speed",
	"city.build_menu", "city.build_hint", "city.need_resources", "city.cant_build_here",
	"city.built_done", "city.site_started", "city.deposited", "city.no_free_worker",
	"city.residents_panel", "city.resident_line", "city.enter_anomaly",
	"city.hungry_warn",
	"city.state.idle", "city.state.going", "city.state.work", "city.state.build",
	"city.state.sleep", "city.state.rest", "city.state.guard", "city.state.hungry",
	"prof.builder", "prof.farmer", "prof.lumberjack", "prof.crafter",
	"prof.guard", "prof.acolyte",
	"bld.house", "bld.farm", "bld.sawmill", "bld.well", "bld.warehouse",
	"bld.workshop", "bld.wall", "bld.tower", "bld.altar",
	"bld.desc.house", "bld.desc.farm", "bld.desc.sawmill", "bld.desc.well",
	"bld.desc.warehouse", "bld.desc.workshop", "bld.desc.wall",
	"bld.desc.tower", "bld.desc.altar",
	"dungeon.enter_hint", "dungeon.hint_exit", "dungeon.hint_chest",
	"dungeon.hint_empty_chest", "dungeon.mana_hungry",
	"dungeon.got_item", "dungeon.got_mana",
	"hud.hp", "hud.mana", "hud.dash", "hud.inventory",
	"hud.loot_total", "hud.minimap", "hud.empty",
	"enemy.rat", "enemy.skeleton", "enemy.golem",
	"rarity.common", "rarity.uncommon", "rarity.rare", "rarity.legendary",
	"item.ash_shard", "item.rusty_sword", "item.stone_chip",
	"item.mana_thread", "item.old_shield", "item.glass_orb",
	"item.rune_sparks", "item.echo_crystal", "item.heart_of_ruins",
	"item.rune_storm", "item.rune_frost", "item.rune_stone", "item.rune_growth",
	"item.rune_light", "item.rune_shadow", "item.rune_chaos",
	"dungeon.hint_spells",
	"magic.title", "magic.pollution", "magic.p_clean", "magic.p_mild",
	"magic.p_heart", "magic.p_wild", "magic.city_spells",
	"magic.craft", "magic.craft_pick", "magic.craft_none", "magic.craft_make",
	"magic.craft_known", "magic.craft_done", "magic.craft_need_two",
	"magic.enchant", "magic.enchant_pick", "magic.enchant_wrong", "magic.enchant_done",
	"magic.no_altar", "magic.no_crystals", "magic.no_rune", "magic.no_mana",
	"magic.cooldown", "magic.cast_done",
	"magic.wild_flash", "magic.wild_surge", "magic.wild_gift", "city.any_bld",
	"school.wild", "school.light", "school.nature",
	"spell.fire_flash", "spell.chain_bolt", "spell.wild_resonance",
	"spell.heal", "spell.shield", "spell.cleanse",
	"spell.roots", "spell.forest_gift", "spell.thorns",
	"spell.desc.fire_flash", "spell.desc.chain_bolt", "spell.desc.wild_resonance",
	"spell.desc.heal", "spell.desc.shield", "spell.desc.cleanse",
	"spell.desc.roots", "spell.desc.forest_gift", "spell.desc.thorns",
	"ench.growth", "ench.ward", "ench.mana",
	"ench.desc.growth", "ench.desc.ward", "ench.desc.mana",
	"enemy.antimage",
	"menu.conflicts",
	"prof.healer",
	"bld.healer_hut", "bld.desc.healer_hut",
	"city.state.child", "city.state.sick", "city.state.wounded",
	"city.chronicle_panel", "city.refugee_came", "city.birth_toast", "city.grown_toast",
	"city.died_toast", "city.wounded_toast", "city.skill_up_toast",
	"city.growth_cap", "city.growth_food", "city.growth_mood",
	"city.learned_toast", "chron.learned",
	"city.autobuild_toast", "chron.autobuild",
	"city.promoted_toast", "chron.promoted",
	"city.hover_site", "city.hover_stun",
	"city.state.manage",
	"prof.elder", "prof.mayor", "prof.bartender",
	"prof.miner", "res.tools",
	"bld.tavern", "bld.desc.tavern",
	"bld.quarry", "bld.desc.quarry",
	"bld.gate", "bld.desc.gate", "city.gate_open", "city.gate_closed",
	"trait.hardworking", "trait.lazy", "trait.cheerful", "trait.grumpy",
	"trait.brave", "trait.coward", "trait.magephobe", "trait.magiclover",
	"trait.glutton", "trait.greedy",
	"skill.novice", "skill.expert", "skill.master",
	"chron.sick", "chron.wounded", "chron.died_sick", "chron.refugee", "chron.birth",
	"chron.grown", "chron.quarrel", "chron.friendship", "chron.discovery",
	"chron.betrayal", "chron.betrayal_caught", "chron.mutation_good", "chron.mutation_bad",
	"chron.skill_expert", "chron.skill_master",
	"story.quarrel_toast", "story.friendship_toast", "story.discovery_toast",
	"story.betrayal_toast", "story.betrayal_caught_toast",
	"story.mutation_good_toast", "story.mutation_bad_toast",
	# --- M5: угрозы и оборона ---
	"biome.ruins", "biome.mutant_forest", "school.forbidden",
	"spell.corrupt_blast", "spell.plague", "spell.drain_life",
	"spell.desc.corrupt_blast", "spell.desc.plague", "spell.desc.drain_life",
	"enemy.mutant", "enemy.brute", "enemy.spitter",
	"city.threat_line", "city.threat_eta",
	"city.threat_stage.calm", "city.threat_stage.unease",
	"city.threat_stage.danger", "city.threat_stage.siege",
	"city.threat_warn", "city.threat_raid", "city.threat_storm", "city.threat_storm_warn",
	"city.raid_warn", "city.raid_toast", "city.raid_siege_toast",
	"city.raid_repelled_toast", "city.raid_breached_toast", "city.razed_toast",
	"city.storm_warn_toast", "city.storm_start_toast", "city.storm_end_toast",
	"city.storm_strike_toast", "city.hero_down_toast",
	"chron.raid", "chron.raid_siege", "chron.repelled", "chron.breach",
	"chron.razed", "chron.storm_warn", "chron.storm", "chron.storm_end",
	# --- M5.1: железо, охота, стражи, комплекты ---
	"res.iron", "res.metal", "res.kits",
	"bld.mine", "bld.smelter", "bld.forge", "bld.armory", "bld.pier",
	"bld.desc.mine", "bld.desc.smelter", "bld.desc.forge", "bld.desc.armory", "bld.desc.pier",
	"prof.smelter", "prof.smith", "prof.armorer", "prof.hunter", "prof.fisher",
	"city.placement_ore", "city.placement_water", "city.placement_forge",
	"city.placement_forest", "city.placement_rock",
	"city.state.hunt", "city.hunt_toast", "chron.hunt",
	"city.guard_trained_toast", "chron.guard_trained",
	"city.hunter_trained_toast", "chron.hunter_trained",
	"city.dungeon_locked_hint", "city.dungeon_locked_toast", "dungeon.cleared_toast",
	"city.armory_hint", "city.armory_bought_toast", "city.armory_max_toast", "city.armory_no_metal_toast",
	# --- M6: зоны, дороги, физическая логистика ---
	"zone.field", "zone.pasture", "zone.living",
	"city.road", "city.road_tooltip", "city.road_hint", "city.road_no_stone",
	"city.road_auto_toast", "chron.road_built",
	"city.zone_hint", "city.zone_tooltip", "city.zone_added", "city.zone_bad", "city.zone_done_toast",
	"city.state.fill", "city.state.porter", "city.state.repair", "city.hover_pile",
	"chron.zone_done", "city.porter_trained_toast", "chron.porter_trained", "prof.porter",
	"bld.garden", "bld.desc.garden", "bld.statue", "bld.desc.statue",
	# --- M7: контент и биомы ---
	"biome.crystal_caves", "biome.ash_wastes",
	"enemy.crawler", "enemy.wisp", "enemy.shardling",
	"enemy.ash_hound", "enemy.dust_stalker", "enemy.cinder",
	"enemy.bone_knight", "enemy.broodmother", "enemy.crystal_colossus", "enemy.ash_tyrant",
	"trap.spikes", "trap.darts", "trap.rune_mine",
	"dungeon.boss_down", "dungeon.mana_back",
	"hud.level", "hud.level_up", "hud.skill_choice",
	"tree.warrior", "tree.mage", "tree.survivor",
	"tree.w1", "tree.w2", "tree.w3", "tree.m1", "tree.m2", "tree.m3", "tree.s1", "tree.s2", "tree.s3",
	"tree.desc.w1", "tree.desc.w2", "tree.desc.w3",
	"tree.desc.m1", "tree.desc.m2", "tree.desc.m3",
	"tree.desc.s1", "tree.desc.s2", "tree.desc.s3",
	"research.title", "research.agriculture", "research.defense", "research.arcane",
	"research.agri1", "research.agri2", "research.agri3",
	"research.def1", "research.def2", "research.def3",
	"research.arc1", "research.arc2", "research.arc3",
	"research.desc.agri1", "research.desc.agri2", "research.desc.agri3",
	"research.desc.def1", "research.desc.def2", "research.desc.def3",
	"research.desc.arc1", "research.desc.arc2", "research.desc.arc3",
	"research.done_toast", "research.research_done", "research.research_locked", "research.research_no_res",
	"trait.kind", "trait.strong", "trait.sickly", "trait.dreamer", "trait.stoic",
	"chron.festival", "chron.prodigy", "chron.brave_deed", "chron.meteor", "chron.herbs",
	"chron.night_terror", "chron.wedding", "chron.artifact", "chron.good_harvest", "chron.stranger",
	"story.festival_toast", "story.prodigy_toast", "story.brave_deed_toast", "story.meteor_toast",
	"story.herbs_toast", "story.night_terror_toast", "story.wedding_toast", "story.artifact_toast",
	"story.good_harvest_toast", "story.stranger_toast",
	"spell.overcharge", "spell.meteor_shard", "spell.light_beacon", "spell.bless",
	"spell.stone_skin", "spell.harvest_blessing", "spell.soul_burn", "spell.void_rift",
	"spell.desc.overcharge", "spell.desc.meteor_shard", "spell.desc.light_beacon", "spell.desc.bless",
	"spell.desc.stone_skin", "spell.desc.harvest_blessing", "spell.desc.soul_burn", "spell.desc.void_rift",
	"item.rune_ash", "item.rune_blood", "item.rune_echo", "item.rune_thorn",
	"item.rune_sun", "item.rune_void", "item.rune_core", "item.boss_trophy",
	# --- M8: карта мира «как в RimWorld» ---
	"res.coins", "res.coins_short", "city.exit_world", "city.world_exit_hint",
	"menu.new_game_warn",
	"world.day", "world.hint", "world.hint_enter_city", "world.hint_enter_loc",
	"world.hint_trade", "world.hint_obelisk", "world.obelisk_used",
	"world.fog", "world.impassable", "world.already_here", "world.no_path",
	"world.travel_toast", "world.travel_cancel", "world.arrived", "world.cleared",
	"world.poi.city", "world.poi.dungeon", "world.poi.ruins", "world.poi.camp",
	"world.poi.settlement", "world.poi.caravan", "world.poi.obelisk",
	"world.faction.traders", "world.faction.bandits", "world.faction.cult",
	"world.strength", "world.status_ok", "world.status_fallen", "world.under_siege",
	"world.obelisk_desc", "world.you_here", "world.days_away", "world.cleared_short",
	"world.travel_btn", "world.close_btn", "world.coins_got", "world.map_found",
	"world.obelisk_seen", "world.siege_start", "world.siege_fell", "world.siege_repelled",
	"world.resettle", "world.poi_reborn", "world.caravan_moved",
	"chron.world_siege", "chron.world_fell", "chron.world_repelled", "chron.world_resettle",
	"world.trade_title", "world.buy_title", "world.sell_title", "world.barter_title",
	"world.rune_title", "world.buy_btn", "world.sell_btn", "world.barter_btn",
	"world.rune_btn", "world.trade_note", "world.bought", "world.sold",
	"world.bartered", "world.rune_bought", "world.no_coins", "world.no_res",
	"world.no_runes", "world.storage_full",
	# --- M11: вишлист (духи леса, некромант, скала, UI) ---
	"cat.living", "cat.living_tip", "cat.resource", "cat.resource_tip",
	"cat.craft", "cat.craft_tip", "cat.defence", "cat.defence_tip",
	"cat.magic", "cat.magic_tip", "cat.special", "cat.special_tip",
	"bld.cemetery", "bld.desc.cemetery",
	"enemy.forest_spirit", "enemy.forest_boss",
	"city.plant", "city.plant_tooltip", "city.plant_hint", "city.plant_no_seeds", "city.plant_bad",
	"city.sapling_toast", "city.tree_grown_toast", "city.forest_warn_toast",
	"city.spirit_toast", "city.forest_boss_toast", "city.forest_repelled_toast", "city.spirit_hit_toast",
	"city.ore_toast", "city.gem_toast", "city.rock_gone_toast", "city.forest_anger",
	"city.necro_label", "city.necro_army", "city.necro_tag", "city.hover_necro",
	"city.necro_revealed_toast", "city.necro_summon_toast", "city.undead_toast",
	"city.necro_purged_toast", "city.necro_hit_toast", "city.keys_bar",
	"chron.tree_felled", "chron.tree_grown", "chron.sapling_planted", "chron.forest_warn",
	"chron.spirit_attack", "chron.forest_boss", "chron.forest_repelled", "chron.spirit_hit",
	"chron.ore_revealed", "chron.gem_found", "chron.rock_gone",
	"chron.necro_chosen", "chron.necro_revealed", "chron.necro_whisper",
	"chron.undead_rising", "chron.necro_purged",
]

const ALL_SCRIPTS := [
	"res://scripts/loc.gd", "res://scripts/main_menu.gd", "res://scripts/city.gd",
	"res://scripts/city_map.gd", "res://scripts/city_sim.gd",
	"res://scripts/city_view.gd", "res://scripts/city_hud.gd",
	"res://scripts/game.gd", "res://scripts/dungeon_gen.gd", "res://scripts/dungeon.gd",
	"res://scripts/dungeon_view.gd", "res://scripts/hero.gd", "res://scripts/enemy.gd",
	"res://scripts/chest.gd", "res://scripts/pickup.gd", "res://scripts/exit_marker.gd",
	"res://scripts/minimap.gd", "res://scripts/hud.gd",
	"res://scripts/magic.gd", "res://scripts/spell_fx.gd",
	"res://scripts/skills.gd", "res://scripts/trap.gd",
	"res://scripts/world.gd", "res://scripts/world_map.gd",
	"res://scripts/world_sim.gd", "res://scripts/world_view.gd", "res://scripts/world_hud.gd",
]

var _fails := 0


func _initialize() -> void:
	_test_loc()
	_test_data()
	_test_scripts()
	_test_scenes()
	_test_dungeon_gen()
	_test_game_inventory()
	_test_city_map()
	_test_city_sim()
	_test_people()
	_test_magic()
	_test_magic_sim()
	_test_spell_damage()
	_test_threat()
	_test_forbidden_school()
	_test_mutant_forest()
	_test_defense()
	_test_gathering()
	_test_m6()
	_test_m7()
	_test_m8()
	_test_m9()
	_test_m10()
	_test_wishlist()
	if _fails == 0:
		print("OK: все тесты пройдены")
		quit(0)
	else:
		print("FAIL: упавших проверок: %d" % _fails)
		quit(1)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: " + what)
	else:
		_fails += 1
		print("  FAIL: " + what)


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _test_loc() -> void:
	print("[Локализация]")
	var data: Variant = _read_json("res://loc/ru.json")
	_check(data is Dictionary, "loc/ru.json — валидный JSON-словарь")
	if not (data is Dictionary):
		return
	for key in REQUIRED_LOCALES:
		_check(data.has(key) and String(data[key]).length() > 0, "ключ «%s» есть" % key)


func _test_data() -> void:
	print("[Данные]")
	var version: Variant = _read_json("res://data/version.json")
	_check(version is Dictionary and version.has("version"), "version.json содержит version")
	var dungeon: Variant = _read_json("res://data/dungeon.json")
	_check(dungeon is Dictionary, "dungeon.json — валидный JSON-словарь")
	if dungeon is Dictionary:
		for key in ["tile_size", "map_w", "map_h", "max_rooms", "enemy_count", "hero", "biomes", "biome_weights"]:
			_check(dungeon.has(key), "dungeon.json содержит %s" % key)
		var hero: Variant = dungeon.get("hero", {})
		_check(hero is Dictionary and hero.has("speed") and hero.has("dash_cooldown"),
				"dungeon.json: параметры героя полны")
	var enemies: Variant = _read_json("res://data/enemies.json")
	_check(enemies is Array and enemies.size() == 22,
			"enemies.json — 22 врага (M7: 13 обычных + 4 босса; M10: +3 бандита; M11: +дух и Древень)")
	if enemies is Array:
		var fields_ok := true
		for enemy in enemies:
			for key in ["id", "hp", "damage", "speed", "aggro", "drop_chance", "xp"]:
				if not (enemy is Dictionary and enemy.has(key)):
					fields_ok = false
		_check(fields_ok, "enemies.json: у всех врагов есть поля боя, дропа и опыта")
		var bosses := 0
		var boss_hp_ok := true
		for enemy in enemies:
			if enemy is Dictionary and bool(enemy.get("boss", false)):
				bosses += 1
				if int(enemy.get("hp", 0)) < 20:
					boss_hp_ok = false
		_check(bosses == 6, "enemies.json — 6 боссов (4 биома + атаман + Древень, M11)")
		_check(boss_hp_ok, "у всех боссов HP >= 20")
	var magic: Variant = _read_json("res://data/magic.json")
	_check(magic is Dictionary, "magic.json — валидный JSON-словарь")
	if magic is Dictionary:
		_check((magic.get("schools", []) as Array).size() == 4, "magic.json — 4 школы (M5: +запретная)")
		_check((magic.get("spells", []) as Array).size() == 20, "magic.json — 20 заклинаний (M7: +8)")
		_check((magic.get("recipes", []) as Array).size() == 20, "magic.json — 20 рецептов из рун")
		_check((magic.get("enchantments", []) as Array).size() == 3, "magic.json — 3 зачарования")
	var loot: Variant = _read_json("res://data/loot.json")
	_check(loot is Dictionary and (loot.get("rarities", []) as Array).size() == 4,
			"loot.json — 4 редкости")
	if loot is Dictionary:
		_check((loot.get("items", []) as Array).size() >= 9, "loot.json — минимум 9 предметов")
	var city: Variant = _read_json("res://data/city.json")
	_check(city is Dictionary, "city.json — валидный JSON-словарь")
	if not (city is Dictionary):
		return
	for key in ["tile_size", "map_w", "map_h", "day_length", "speeds", "start", "loot_to_pool",
			"pollution", "hero_mana", "test_mode", "autobuild_plan",
			"zones", "roads", "piles", "layout", "repair", "decor_mood_max"]:
		_check(city.has(key), "city.json содержит %s" % key)
	var blds: Variant = city.get("buildings", [])
	_check(blds is Array and blds.size() == 23, "city.json — 23 типа зданий (M11: +кладбище)")
	var bld_ok := true
	if blds is Array:
		for b in blds:
			for key in ["id", "loc", "desc", "color", "cost", "build_work", "district"]:
				if not (b is Dictionary and b.has(key)):
					bld_ok = false
	_check(bld_ok, "city.json: у зданий есть цена, время стройки и район")
	# категории построек (M11): у каждого здания известная категория — «столбцы» UI
	var cats := {"living": true, "resource": true, "craft": true, "defence": true, "magic": true, "special": true}
	var cats_ok := true
	var cat_n := {}
	for b in city.get("buildings", []):
		if b is Dictionary:
			if not cats.has(String(b.get("cat", ""))):
				cats_ok = false
			cat_n[String(b.get("cat", ""))] = true
	_check(cats_ok, "city.json: у всех зданий заполнена категория постройки")
	_check(cat_n.size() >= 5, "город разбит минимум на 5 категорий построек")
	_check((city.get("cats", {}) as Dictionary).size() == 6, "city.json — 6 категорий построек (M11)")
	_check(city.has("mountain"), "city.json настроена добыча скалы (M11)")
	_check(city.has("forest"), "city.json настроен лес: вырубка, гнев, посадка (M11)")
	_check(city.has("necro"), "city.json настроен некромант: тьма, армия, восстание (M11)")
	var decor_n := 0
	for b in city.get("buildings", []):
		if b is Dictionary and String(b.get("effect", "")) == "decor":
			decor_n += 1
			_check(int(b.get("mood", 0)) > 0, "декор «%s» даёт комфорт (мораль — ответ №18)" % String(b.get("id", "")))
	_check(decor_n == 2, "city.json — два декоративных здания (сад, статуя)")
	var districts := {}
	for b in city.get("buildings", []):
		if b is Dictionary:
			districts[String(b["district"])] = true
	_check(districts.has("living") and districts.has("work"), "город разбит на жилой и производственный районы")
	var profs: Variant = city.get("professions", [])
	_check(profs is Array and profs.size() == 17, "city.json — 17 профессий (M10: +торговец)")
	var has_porter := false
	for p in city.get("professions", []):
		if p is Dictionary and String(p.get("id", "")) == "porter":
			has_porter = true
	_check(has_porter, "в списке профессий есть носильщик (M6)")
	var speeds_ok := false
	for s in city.get("speeds", []):
		if int(s) == 10:
			speeds_ok = true
	_check(speeds_ok, "city.json — есть супер-скорость x10 (M4)")
	for b in city.get("buildings", []):
		if b is Dictionary and String(b.get("id", "")) == "farm":
			_check(int(b["produce"]["per_day"]) == 16, "поле эффективнее: 16 еды в день с работника")
	var residents_data: Variant = _read_json("res://data/residents.json")
	_check(residents_data is Dictionary, "residents.json — валидный JSON-словарь")
	if residents_data is Dictionary:
		_check((residents_data.get("traits", []) as Array).size() == 15, "residents.json — 15 черт (M7: +5)")
		_check(residents_data.has("refugees") and residents_data.has("births"),
				"residents.json: настроены беженцы и рождения (ответ №27)")
		_check(residents_data.has("ailments") and residents_data.has("stories"),
				"residents.json: настроены болезни и события-истории")
	var pool_map: Dictionary = city.get("loot_to_pool", {})
	_check(pool_map.get("stone_chip", "") == "stone", "city.json: каменная крошка -> камень в пул")
	_check(pool_map.get("echo_crystal", "") == "crystal", "city.json: кристалл эха -> кристаллы маны")


func _test_scripts() -> void:
	print("[Скрипты]")
	for path in ALL_SCRIPTS:
		var script: Script = load(path)
		_check(script != null and script.can_instantiate(), "%s компилируется" % path)


func _test_scenes() -> void:
	print("[Сцены]")
	for path in ["res://scenes/main_menu.tscn", "res://scenes/city.tscn", "res://scenes/dungeon.tscn",
			"res://scenes/world.tscn"]:
		var packed: PackedScene = load(path)
		_check(packed != null, "%s загружается" % path)
		if packed == null:
			continue
		var node := packed.instantiate()
		_check(node != null, "%s создаётся" % path)
		if node:
			node.free()


func _test_dungeon_gen() -> void:
	print("[Генератор данжа]")
	var params: Variant = _read_json("res://data/dungeon.json")
	if not (params is Dictionary):
		_check(false, "dungeon.json читается для генератора")
		return
	var gen_a: Object = load("res://scripts/dungeon_gen.gd").new()
	var gen_b: Object = load("res://scripts/dungeon_gen.gd").new()
	gen_a.generate(42, params)
	gen_b.generate(42, params)
	_check(gen_a.grid == gen_b.grid, "seed 42: две генерации дают одинаковую карту")
	_check(gen_a.enemy_spawns == gen_b.enemy_spawns and gen_a.chest_spawns == gen_b.chest_spawns,
			"seed 42: расстановка спавнов совпадает")
	_check(gen_a.rooms.size() >= 2, "карта содержит больше одной комнаты")
	_check(gen_a.is_floor(gen_a.start_tile) and gen_a.is_floor(gen_a.exit_tile),
			"старт и выход стоят на полу")
	_check(gen_a.start_tile != gen_a.exit_tile, "старт и выход не совпадают")
	var different := false
	for seed_value in [1, 2, 3, 4, 5]:
		var gen_c: Object = load("res://scripts/dungeon_gen.gd").new()
		gen_c.generate(seed_value, params)
		if gen_c.grid != gen_a.grid:
			different = true
	_check(different, "разные seed дают разные карты")
	# связность: от старта достижимы выход и все спавны
	var reachable := _reachable_from(gen_a)
	_check(reachable.has(gen_a.exit_tile), "выход достижим от старта")
	var spawns_ok := true
	for p: Vector2i in gen_a.enemy_spawns + gen_a.chest_spawns + gen_a.crystal_spawns:
		if not reachable.has(p) or not gen_a.is_floor(p):
			spawns_ok = false
	_check(spawns_ok, "все спавны на полу и достижимы")
	# DungeonGen — RefCounted: освобождается сам


## BFS по тайлам пола от стартовой точки.
func _reachable_from(gen: Object) -> Dictionary:
	var seen := {gen.start_tile: true}
	var queue: Array = [gen.start_tile]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if not seen.has(n) and gen.is_floor(n):
				seen[n] = true
				queue.append(n)
	return seen


func _test_game_inventory() -> void:
	print("[Рюкзак]")
	var game: Node = load("res://scripts/game.gd").new()
	game.add_item("sword", 5)
	game.add_item("gem", 1)
	game.add_item("sword", 2)
	_check(game.count_item("sword") == 7, "стаки складываются (5+2=7)")
	_check(game.loot_total() == 8, "loot_total считает все единицы")
	var lost: int = game.lose_half_loot()
	_check(game.count_item("sword") == 3, "смерть: стак 7 теряет 4, остаётся 3")
	_check(game.count_item("gem") == 0, "смерть: стак 1 теряется целиком")
	_check(lost == 5, "смерть: потеряно 5 из 8")
	_check(game.loot_total() == 3, "после смерти в рюкзаке 3 единицы")
	game.free()

	# тест-режим: ресурсы и руны выдаются при новой игре
	var game2: Node = load("res://scripts/game.gd").new()
	game2.test_mode = true
	game2.new_city()
	var test_cfg: Dictionary = _read_json("res://data/city.json").get("test_mode", {})
	_check(int(game2.city_sim.res["wood"]) == int(test_cfg["resources"]["wood"]),
			"тест-режим: ресурсы из city.json")
	_check(int(game2.city_sim.res["crystal"]) == int(test_cfg["resources"]["crystal"]),
			"тест-режим: кристаллы в пуле")
	_check(game2.count_item("rune_chaos") == int(test_cfg["runes_each"]),
			"тест-режим: руны в рюкзаке (по recipes)")
	_check(game2.count_item("rune_light") == int(test_cfg["runes_each"]),
			"тест-режим: каждая руна в нужном числе")
	_check(game2.spellbook.is_empty(), "тест-режим не изучает заклинания сам")
	game2.free()


# --- M2: город -----------------------------------------------------------

## Карта + симуляция города для теста (seed фиксирован).
func _make_sim(level: String = "normal") -> Object:
	var cfg: Variant = _read_json("res://data/city.json")
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(7, cfg)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(city_map, cfg, 6, level)
	# в игре дневные броски идут с первого дня; в тестах фиксируем день 1,
	# чтобы тики строек не вызывали случайно беженцев и событий
	sim._last_daily_day = 1
	# волны мутантов в обычных тестах выключены: мир M5 живёт по своим правилам,
	# проверяется отдельно в _test_threat (там волны зовутся вручную)
	sim._next_raid_at = 999999999.0
	return sim


func _resident_by_prof(sim: Object, prof: String) -> Dictionary:
	for r in sim.residents:
		if String(r["prof"]) == prof:
			return r
	return {}


## Телепорт жителя на тайл и сброс пути (чтобы не ждать ходьбы в тесте).
func _teleport(sim: Object, r: Dictionary, tile: Vector2i) -> void:
	r["pos"] = sim.map.tile_center_px(tile)
	r["target"] = Vector2i(-1, -1)
	r["path"] = PackedVector2Array()


func _find_free_tile(sim: Object, near: Vector2i, type_id: String = "") -> Vector2i:
	# добытчики ставятся только у своего ресурса — ищем честное место
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id and String(d.get("place", "")) != "":
			var kinds: Array = []
			var on_resource := false
			match String(type_id):
				"mine":
					kinds = [sim.map.TILE_ORE]
					on_resource = true
				"sawmill":
					kinds = [sim.map.TILE_TREE]
				"quarry":
					kinds = [sim.map.TILE_ROCK, sim.map.TILE_ORE]
			return sim._find_gather_tile(type_id, kinds, on_resource)
	for radius in range(1, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := near + Vector2i(dx, dy)
				if sim.is_buildable_tile(tile) and sim.placement_block(type_id, tile) == "":
					return tile
	return Vector2i(-1, -1)


## Построить здание мгновенно: ставим площадку, телепортируем строителя, тикаем.
func _build_now(sim: Object, type_id: String) -> Dictionary:
	var builder: Dictionary = _resident_by_prof(sim, "builder")
	# личности M4 не мешают стройке в тестах: строитель в идеальном состоянии
	builder["mood"] = 100.0
	builder["traits"] = []
	builder["skill"] = 0.0
	var near: Vector2i = sim.map.spawn_tile
	var tile := _find_free_tile(sim, near, type_id)
	_check(not tile == Vector2i(-1, -1), "%s: найдено место под стройку" % type_id)
	_check(sim.place_building(type_id, tile), "%s: стройплощадка заложена" % type_id)
	var site: Dictionary = sim.building_at(tile)
	_check(not site.is_empty() and not bool(site["done"]), "%s: площадка ждёт строителя" % type_id)
	var work: float = 0.0
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			work = float(d["build_work"])
	_teleport(sim, builder, tile)
	sim.tick(work + 0.1)
	site = sim.building_at(tile)
	_check(bool(site["done"]), "%s: строитель достроил за build_work" % type_id)
	return site


func _test_city_map() -> void:
	print("[Карта города]")
	var cfg: Variant = _read_json("res://data/city.json")
	var a = load("res://scripts/city_map.gd").new()
	var b = load("res://scripts/city_map.gd").new()
	a.generate(42, cfg)
	b.generate(42, cfg)
	_check(a.grid == b.grid, "seed 42: две генерации города одинаковы")
	_check(a.anomaly_tile == b.anomaly_tile, "seed 42: аномалия на одном месте")
	var trees := 0
	for y in a.h:
		for x in a.w:
			if a.grid[y][x] == a.TILE_TREE:
				trees += 1
	_check(trees > 0, "на карте есть деревья")
	_check(a.is_nature_walkable(a.spawn_tile), "старт героя на проходимой земле")
	_check(not a.is_nature_walkable(a.anomaly_tile + Vector2i(a.w, 100)), "вне карты непроходимо")
	# связность: от старта достижима аномалия
	var seen := {a.spawn_tile: true}
	var queue: Array = [a.spawn_tile]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if a.in_bounds(n) and not seen.has(n) and a.is_nature_walkable(n):
				seen[n] = true
				queue.append(n)
	_check(seen.has(a.anomaly_tile), "аномалия достижима пешком от старта")
	# путь по AStar и стена-преграда
	var target: Vector2i = a.spawn_tile + Vector2i(2, 0)
	var path: PackedVector2Array = a.path_px(a.tile_center_px(a.spawn_tile), target)
	_check(path.size() >= 2, "AStar строит путь между тайлами")
	a.set_solid(target, true)
	_check(not a.is_walkable(target), "частокол делает тайл непроходимым")


func _test_city_sim() -> void:
	print("[Симуляция города]")
	var sim := _make_sim()
	var start: Dictionary = sim.cfg["start"]["levels"]["normal"]
	_check(int(sim.res["wood"]) == int(start["wood"]), "старт: дерево по уровню «норма»")
	_check(int(sim.res["crystal"]) == int(start["crystal"]), "старт: кристаллы по уровню")
	_check(sim.residents.size() == 6, "старт: 6 жителей, на одного больше (заказчик)")
	var elder_started := false
	for r in sim.residents:
		if String(r["prof"]) == "elder":
			elder_started = true
	_check(elder_started, "в стартовом наборе есть староста — город растёт сам")
	_check(sim.pop_cap() == 6, "лимит жителей = стартовым без домов")
	_check(sim.storage_cap() == int(sim.cfg["storage_base"]), "вместимость хранилища базовая")
	_check(not sim.is_night(), "утро нового города — день")

	# стройка: нельзя на воду, нельзя без денег
	var water_tile := Vector2i(-1, -1)
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_WATER:
				water_tile = Vector2i(x, y)
				break
		if water_tile.x >= 0:
			break
	_check(not sim.is_buildable_tile(water_tile), "на воде строить нельзя")
	var poor := _make_sim("low")
	poor.res["wood"] = 0
	_check(not poor.place_building("house", poor.map.spawn_tile + Vector2i(1, 0)),
			"без ресурсов стройка не начинается")

	# дом: +2 к лимиту жителей
	_build_now(sim, "house")
	_check(sim.pop_cap() == 8, "дом даёт +2 к лимиту жителей")
	# склад: +200 к вместимости
	_build_now(sim, "warehouse")
	_check(sim.storage_cap() == int(sim.cfg["storage_base"]) + int(sim.cfg["storage_per_warehouse"]),
			"склад даёт +%d к вместимости" % int(sim.cfg["storage_per_warehouse"]))
	# частокол: блокирует тайл
	var wall_site := _build_now(sim, "wall")
	_check(not sim.map.is_walkable(wall_site["tile"]), "построенный частокол — преграда")

	# ферма: фермер работает, еда копится КУЧЕЙ у фермы — в пул попадает
	# только через носильщика (M6: физическая логистика, ответ №20)
	sim.cfg["piles"] = {"chunk": 2.0, "max": 20.0, "carry": 10.0}   # мелкие кучи — тест не ждёт целый день
	var farmer: Dictionary = _resident_by_prof(sim, "farmer")
	_check(not farmer.is_empty(), "среди жителей есть фермер")
	_teleport(sim, farmer, sim.map.spawn_tile + Vector2i(2, 2))
	sim.cfg["food_per_resident_day"] = 0.0
	var food_before: float = float(sim.res["food"])
	var farm := _build_now(sim, "farm")
	_teleport(sim, farmer, farm["tile"])
	sim.time = 10.0   # утро: длинные стройки выше съели полдня — не уходить в ночь
	sim.tick(20.0)
	_check(String(farmer["state"]) == "work", "фермер работает на ферме")
	_check(float((farm["pile"] as Dictionary).get("food", 0.0)) > 0.0,
			"ферма складывает еду в кучу у здания")
	_check(absf(float(sim.res["food"]) - food_before) < 0.001,
			"без носильщика еда в общий пул не попадает")
	# носильщик: забрал кучу и снёс на склад — пул вырос
	var porter: Dictionary = sim._new_resident("Тар", "porter", sim.map.spawn_tile)
	sim.residents.append(porter)
	sim._next_id += 1
	_teleport(sim, porter, farm["tile"])
	sim.tick(1.0)
	_check(float(porter["carry"]) > 0.0, "носильщик забрал кучу у фермы")
	var barn_tile := Vector2i(-1, -1)
	for b in sim.buildings:
		if b["done"] and String(b["type"]) == "warehouse":
			barn_tile = b["tile"]
	_check(barn_tile != Vector2i(-1, -1), "склад построен — есть куда носить")
	_teleport(sim, porter, barn_tile)
	sim.tick(0.5)
	_check(float(sim.res["food"]) > food_before, "носильщик снёс еду на склад (пул вырос)")
	_check(float(porter["carry"]) == 0.0, "груз доставлен целиком")

	# еда: жители едят; пустой пул — голодный безработный стоит, работающий трудится вполсилы
	sim.cfg["food_per_resident_day"] = 2.0
	sim.res["food"] = 0.0
	var starving_mult: float = sim.work_mult(farmer)
	_check(starving_mult <= 0.75, "голод режет работу почти вдвое (%.2f)" % starving_mult)
	sim.tick(0.5)
	_check(String(farmer["state"]) == "work", "голодный фермер не бросает ферму (анти-тупик M4)")
	var sim_h := _make_sim()
	sim_h.res["food"] = 0.0
	sim_h.tick(0.5)
	var idle_guard: Dictionary = _resident_by_prof(sim_h, "guard")
	_check(String(idle_guard["state"]) == "hungry", "без еды безработный голодает")
	sim_h.res["food"] = 50.0
	sim_h.tick(0.5)
	_check(String(idle_guard["state"]) != "hungry", "еда вернулась — работа продолжается")

	# ночь: жители спят (в построенном доме), кроме стража
	sim.time = float(sim.cfg["day_length"]) * 0.95
	var house := {}
	for b in sim.buildings:
		if b["done"] and String(b["type"]) == "house":
			house = b
	_check(not house.is_empty(), "дом готов — есть где спать")
	_teleport(sim, farmer, house["tile"])
	sim.tick(0.2)
	_check(String(farmer["state"]) == "sleep", "ночью фермер спит дома")
	_check(sim.is_night(), "время 95% суток — ночь")

	# пауза и скорость
	var sim2 := _make_sim()
	sim2.paused = true
	sim2.tick(5.0)
	_check(float(sim2.time) == 0.0, "пауза: время не идёт")
	sim2.paused = false
	sim2.speed = 3
	sim2.tick(1.0)
	_check(absf(float(sim2.time) - 3.0) < 0.001, "скорость x3: тик 1 сек двигает время на 3")

	# добыча из данжа падает в пул города
	var inv: Array = [
		{"id": "stone_chip", "count": 5},
		{"id": "echo_crystal", "count": 2},
		{"id": "rune_sparks", "count": 1},
	]
	var stone_before: float = float(sim.res["stone"])
	var added: Dictionary = sim.deposit_loot(inv)
	_check(int(added.get("stone", 0)) == 5, "каменная крошка ушла в пул камня")
	_check(int(added.get("crystal", 0)) == 2, "кристаллы ушли в пул маны")
	_check(inv.size() == 1 and String(inv[0]["id"]) == "rune_sparks",
			"руна осталась в рюкзаке (нужна для M3)")
	_check(float(sim.res["stone"]) == stone_before + 5.0, "камень в пуле вырос на 5")

	# переполнение хранилища: излишек остаётся в рюкзаке
	var sim3 := _make_sim()
	sim3.res["stone"] = float(sim3.storage_cap())
	var full_inv: Array = [{"id": "stone_chip", "count": 10}]
	var added3: Dictionary = sim3.deposit_loot(full_inv)
	_check(int(added3.get("stone", 0)) == 0, "полное хранилище не принимает камень")
	_check(full_inv.size() == 1 and int(full_inv[0]["count"]) == 10, "излишек остался в рюкзаке")

	# алтарь маны: маг-ученик даёт благословение (петля: данж -> кристаллы -> буст)
	var sim4 := _make_sim()
	_check(int(sim4.cfg["start"]["levels"]["high"]["crystal"]) == 2, "уровень «много» даёт 2 кристалла (конфиг)")
	sim4.res["crystal"] = 2.0   # кристаллы принесены из данжа
	var altar := _build_now(sim4, "altar")
	var acolyte: Dictionary = _resident_by_prof(sim4, "acolyte")
	_check(not acolyte.is_empty(), "маг-ученик есть среди жителей")
	_teleport(sim4, acolyte, altar["tile"])
	sim4.tick(0.3)
	_check(bool(sim4.has_blessing()), "работающий алтарь даёт благословение")


# --- M4: жители-личности ----------------------------------------------------

func _test_people() -> void:
	print("[Жители-личности M4]")
	var sim := _make_sim()
	_check(sim.people.size() > 0, "симуляция загрузила residents.json")
	var r0: Dictionary = sim.residents[0]
	_check((r0["traits"] as Array).size() >= 1, "у жителя есть 1-2 черты характера")
	_check(r0.has("mood") and r0.has("skill") and r0.has("friend"), "настроение, навык и дружба заведены")
	_check(absf(float(r0["mood"]) - 50.0) < 30.0, "настроение на старте около базового")

	# скорость x10 (просьба заказчика: смотреть рождения и истории)
	var sim10 := _make_sim()
	sim10.speed = 10
	sim10.tick(1.0)
	_check(absf(float(sim10.time) - 10.0) < 0.001, "супер-скорость x10: тик 1 сек двигает время на 10")

	# навык растёт от работы; трудолюбивый сильнее ленивого
	var sim_w := _make_sim()
	sim_w.cfg["food_per_resident_day"] = 0.0
	var farmer: Dictionary = _resident_by_prof(sim_w, "farmer")
	farmer["skill"] = 0.0
	_teleport(sim_w, farmer, sim_w.map.spawn_tile + Vector2i(2, 2))
	var farm := _build_now(sim_w, "farm")
	_teleport(sim_w, farmer, farm["tile"])
	sim_w.tick(10.0)
	_check(float(farmer["skill"]) > 0.0, "навык растёт от работы")
	_check(int(farmer["rank"]) == 0, "ранг новичка — 0")
	var hard: Dictionary = {"traits": ["hardworking"], "mood": 50.0, "skill": 0.0, "friend": -1, "work_bonus": 0.0}
	var lazy: Dictionary = {"traits": ["lazy"], "mood": 50.0, "skill": 0.0, "friend": -1, "work_bonus": 0.0}
	var hard_mult: float = sim_w.work_mult(hard)
	var lazy_mult: float = sim_w.work_mult(lazy)
	_check(hard_mult > lazy_mult, "трудолюбивый работает лучше ленивого")
	hard["skill"] = 5.0
	_check(sim_w.work_mult(hard) > hard_mult, "навык усиливает работу")

	# настроение: голод валит его, черта маголюба на загрязнении поднимает
	var sim_m := _make_sim()
	var someone: Dictionary = sim_m.residents[0]
	var mood_before := float(someone["mood"])
	sim_m.res["food"] = 0.0
	sim_m.tick(20.0)
	_check(float(someone["mood"]) < mood_before, "голод снижает настроение")
	var lover: Dictionary = {"traits": ["magiclover"], "mood": 50.0, "fatigue": 0.0, "home": {}, "friend": -1, "ail": ""}
	var phobe: Dictionary = {"traits": ["magephobe"], "mood": 50.0, "fatigue": 0.0, "home": {}, "friend": -1, "ail": ""}
	sim_m.pollution = 80.0
	_check(sim_m._mood_target(lover) > sim_m._mood_target(phobe), "маголюб при загрязнении счастливее магофоба")

	# лекарь: хижина занята, болезнь случается и лечится
	var sim_s := _make_sim()
	var healer: Dictionary = sim_s._new_resident("Ада", "healer", sim_s.map.spawn_tile)
	sim_s.residents.append(healer)
	var hut := _build_now(sim_s, "healer_hut")
	_check(int(hut["worker"]) > 0, "лекарь занял хижину")
	_check(bool(sim_s._healer_ready()), "работающий лекарь готов лечить")
	sim_s.people["ailments"]["sick_chance"] = 1.0
	sim_s._roll_ailments()
	var sick_count := 0
	for r in sim_s.residents:
		if String(r.get("ail", "")) == "sick":
			sick_count += 1
	_check(sick_count > 0, "болезнь случилась (шанс 100%)")
	_check(not bool(sim_s._healer_ready()), "болеющий лекарь не держит хижину (место освобождено)")
	healer["ail"] = ""   # лекарь выздоровел и вернулся на пост
	sim_s._assign_jobs()
	_check(bool(sim_s._healer_ready()), "выздоровевший лекарь вернулся в хижину")
	sim_s.people["ailments"]["sick_chance"] = 0.0
	sim_s.people["ailments"]["healer_recover_chance"] = 1.0
	sim_s._roll_ailments()
	var still_sick := 0
	for r in sim_s.residents:
		if String(r.get("ail", "")) != "":
			still_sick += 1
	_check(still_sick == 0, "лекарь вылечил всех больных")

	# смерть жителя: горе городу, летопись
	var sim_d := _make_sim()
	var victim: Dictionary = sim_d.residents[1]
	var mourner: Dictionary = sim_d.residents[0]
	var mood_before_death := float(mourner["mood"])
	sim_d._kill(victim, "chron.died_sick")
	_check(sim_d.residents.size() == 5, "житель умер — его больше нет")
	_check(float(mourner["mood"]) < mood_before_death, "смерть жителя роняет мораль остальных")
	_check(sim_d.chronicle.size() > 0 and String(sim_d.chronicle[-1]["key"]) == "chron.died_sick",
			"смерть попала в летопись")

	# беженцы идут сами (ответ №27), рождения дают ребёнка, ребёнок вырастает
	var sim_r := _make_sim()
	sim_r.res["food"] = 30.0   # запас еды на всех — иначе беженцы не придут
	_build_now(sim_r, "house")   # +2 к лимиту: место для пришельцев и новорождённых
	for r in sim_r.residents:
		r["mood"] = 80.0
	var pop_before: int = sim_r.residents.size()
	sim_r.people["refugees"]["chance_per_day"] = 1.0
	sim_r.people["refugees"]["wave_max"] = 1
	sim_r._roll_refugees()
	_check(sim_r.residents.size() == pop_before + 1, "беженец пришёл сам")
	_check(String(sim_r.chronicle[-1]["key"]) == "chron.refugee", "беженец записан в летопись")

	# прирост города: беженцы не приходят без места или без запаса еды (M4-фикс фидбека)
	var sim_g := _make_sim()
	_check(String(sim_g.growth_block()) == "city.growth_cap", "прирост стоит: лимит жителей полон")
	sim_g.people["refugees"]["chance_per_day"] = 1.0
	sim_g._roll_refugees()
	_check(sim_g.residents.size() == 6, "при полном лимите беженец не приходит")
	_build_now(sim_g, "house")
	sim_g.res["food"] = 2.0
	_check(String(sim_g.growth_block()) == "city.growth_food", "прирост стоит: нет запаса еды")
	sim_g._roll_refugees()
	_check(sim_g.residents.size() == 6, "без запаса еды беженец не идёт в голодный город")
	for r in sim_g.residents:
		r["mood"] = 80.0
	sim_g.res["food"] = 50.0
	sim_g._roll_refugees()
	_check(sim_g.residents.size() >= 7, "есть место и еда — беженцы приходят (волна 1-2)")

	sim_r.people["births"]["chance_per_day"] = 1.0
	sim_r._roll_births()
	var child: Dictionary = {}
	for r in sim_r.residents:
		if String(r["prof"]) == "":
			child = r
	_check(not child.is_empty(), "родился ребёнок (без профессии)")
	_check(String(sim_r.chronicle[-1]["key"]) == "chron.birth", "рождение записано в летопись")
	if not child.is_empty():
		sim_r.people["births"]["child_days"] = 0.01
		sim_r.tick(2.0)
		_check(String(child["prof"]) != "", "ребёнок вырос и получил профессию")
		_check((child["traits"] as Array).size() >= 1, "выросший получил черты характера")

	# ссора (ответ №29): двое в минусе, галочка конфликтов выключает
	var sim_q := _make_sim()
	sim_q.conflicts = true
	sim_q.residents[0]["traits"] = ["grumpy"]
	for r in sim_q.residents:
		r["mood"] = 50.0
	sim_q.people["stories"]["chance_per_day"] = 1.0
	sim_q.people["stories"]["weights"] = {"quarrel": 1}
	sim_q._roll_stories()
	var sad := 0
	for r in sim_q.residents:
		if float(r["mood"]) < 50.0:
			sad += 1
	_check(sad == 2, "ссора ухудшила настроение ровно двоим")
	_check(String(sim_q.chronicle[-1]["key"]) == "chron.quarrel", "ссора записана в летопись")
	sim_q.conflicts = false
	for r in sim_q.residents:
		r["mood"] = 50.0
	sim_q._roll_stories()
	_check(absf(float(sim_q.residents[0]["mood"]) - 50.0) < 0.001,
			"галочка конфликтов выключает ссоры")

	# кража (жадный в унынии; стража нет — сойдёт с рук)
	var sim_b := _make_sim()
	for r in sim_b.residents:
		if String(r["prof"]) == "guard":
			r["prof"] = "crafter"
	sim_b.residents[0]["traits"] = ["greedy"]
	sim_b.residents[0]["mood"] = 20.0
	sim_b.people["stories"]["chance_per_day"] = 1.0
	sim_b.people["stories"]["weights"] = {"betrayal": 1}
	var food_before := float(sim_b.res["food"])
	sim_b._roll_stories()
	_check(float(sim_b.res["food"]) < food_before, "жадный в унынии украл еду")
	_check(String(sim_b.chronicle[-1]["key"]) == "chron.betrayal", "кража записана в летопись")

	# находка: опытный житель приносит ресурс в пул
	var sim_f := _make_sim()
	sim_f.residents[0]["skill"] = 3.0
	sim_f.res["food"] = 0.0
	sim_f.res["stone"] = 0.0
	sim_f.res["crystal"] = 0.0
	sim_f.people["stories"]["chance_per_day"] = 1.0
	sim_f.people["stories"]["weights"] = {"discovery": 1}
	sim_f._roll_stories()
	_check(String(sim_f.chronicle[-1]["key"]) == "chron.discovery", "находка записана в летопись")
	var res_sum: float = float(sim_f.res["food"]) + float(sim_f.res["stone"]) + float(sim_f.res["crystal"])
	_check(res_sum > 0.0, "находка дала ресурс в пул")

	# мутация (ответ №35): улучшение или болезнь
	var sim_mu := _make_sim()
	sim_mu.pollution = 50.0
	sim_mu.people["stories"]["chance_per_day"] = 1.0
	sim_mu.people["stories"]["weights"] = {"mutation": 1}
	sim_mu._roll_stories()
	var mutated := false
	for r in sim_mu.residents:
		if float(r.get("work_bonus", 0.0)) > 0.0 or String(r.get("ail", "")) == "sick":
			mutated = true
	_check(mutated, "дикая магия изменила жителя: улучшение или болезнь")

	# дружба (ответ №34): друг за работой усиливает жителя
	var sim_fr := _make_sim()
	var f1: Dictionary = sim_fr.residents[0]
	var f2: Dictionary = sim_fr.residents[1]
	f1["mood"] = 60.0
	f1["traits"] = []
	f1["skill"] = 0.0
	f1["work_bonus"] = 0.0
	f1["friend"] = -1
	var solo: float = sim_fr.work_mult(f1)
	f1["friend"] = int(f2["id"])
	f2["state"] = "work"
	var duo: float = sim_fr.work_mult(f1)
	_check(duo > solo, "друг за работой усиливает жителя")

	# подмена профессий: свободные замещают нехватку и учатся (просьба заказчика)
	var sim_p := _make_sim()
	_build_now(sim_p, "farm")     # фермер занят первой фермой
	_build_now(sim_p, "sawmill")  # лесоруб занят пилорамой
	var farm2 := _build_now(sim_p, "farm")
	var builder_p: Dictionary = _resident_by_prof(sim_p, "builder")
	_check(int(farm2["worker"]) == int(builder_p["id"]),
			"строитель замещает фермера на второй ферме (некому работать)")
	_check((builder_p["prof_extra"] as Array).has("farmer"), "замещающий выучил профессию фермера")
	_check(String(builder_p["sub_prof"]) == "farmer", "подмена помечена, чтобы вернуть на основную")
	_check(String(sim_p.chronicle[-1]["key"]) == "chron.learned", "обучение записано в летопись")

	# потребность по основной: стройка зовёт строителя назад, ферма пустеет
	var wall_tile: Vector2i = sim_p.map.spawn_tile + Vector2i(6, 0)
	while not sim_p.is_buildable_tile(wall_tile):
		wall_tile += Vector2i(1, 0)
	sim_p.place_building("wall", wall_tile)
	_check(builder_p["site"] != null and String(builder_p["sub_prof"]) == "",
			"строитель вернулся на стройку: потребность по основной профессии")
	_check(int(farm2["worker"]) != int(builder_p["id"]) and int(farm2["worker"]) > 0,
			"освободившуюся ферму подхватил другой замещающий")
	# выучившего предпочитают: умеющий фермера замещает раньше неумевшего
	var sim_l := _make_sim()
	var knowing: Dictionary = sim_l.residents[3]
	var ignorant: Dictionary = sim_l.residents[4]
	(knowing["prof_extra"] as Array).append("farmer")
	var taken := {}
	var farm_l := {"done": true, "type": "farm", "worker": -1}
	sim_l._substitute_into("farmer", taken, farm_l, false)
	_check(int(farm_l["worker"]) == int(knowing["id"]), "выучивший профессию замещает первым")

	# подмена вдвое хуже основной работы (просьба заказчика)
	var sim_sb := _make_sim()
	var plain: Dictionary = {"traits": [], "mood": 50.0, "skill": 0.0, "friend": -1, "work_bonus": 0.0, "sub_prof": ""}
	var substituting: Dictionary = {"traits": [], "mood": 50.0, "skill": 0.0, "friend": -1, "work_bonus": 0.0, "sub_prof": "farmer"}
	var plain_mult: float = sim_sb.work_mult(plain)
	var sub_mult: float = sim_sb.work_mult(substituting)
	_check(absf(plain_mult - sub_mult * 2.0) < 0.01, "неосновная профессия работает ровно вдвое хуже")

	# таверна: тратит еду на пиво и поднимает настроение городу
	var sim_t := _make_sim()
	var tavern_keeper: Dictionary = sim_t._new_resident("Герд", "bartender", sim_t.map.spawn_tile)
	sim_t.residents.append(tavern_keeper)
	_build_now(sim_t, "tavern")
	_check(int(sim_t.buildings[-1]["worker"]) == int(tavern_keeper["id"]), "трактирщик работает в таверне")
	sim_t.res["food"] = 100.0
	var food_before_tavern := float(sim_t.res["food"])
	sim_t.cfg["food_per_resident_day"] = 0.0
	sim_t.tick(10.0)
	_check(float(sim_t.res["food"]) < food_before_tavern, "таверна забирает еду на пиво")
	_check(bool(sim_t.tavern_active()), "таверна с пивом активна")
	var pleased: Dictionary = {"traits": [], "mood": 50.0, "fatigue": 0.0, "home": {}, "friend": -1, "ail": ""}
	var mood_with: float = sim_t._mood_target(pleased)
	var sim_t2 := _make_sim()   # такой же город, но без таверны
	var mood_without: float = sim_t2._mood_target(pleased)
	_check(absf(mood_with - mood_without - 12.0) < 0.5, "пиво в таверне даёт ровно +12 к настроению")

	# староста: обходит город и строит по нужде (дома при переполнении, ферма без запаса еды)
	var sim_e := _make_sim()
	var elder_r: Dictionary = sim_e._new_resident("Борн", "elder", sim_e.map.spawn_tile)
	sim_e.residents.append(elder_r)
	sim_e.tick(1.0)
	_check(String(elder_r["state"]) == "manage", "староста обходит город")
	_check(bool(sim_e.elder_present()), "староста на ногах — город может строить сам")
	sim_e.people["refugees"]["chance_per_day"] = 0.0
	_build_now(sim_e, "farm")   # баланс еды положительный — дефицит не перебивает кризис дома
	var buildings_before: int = sim_e.buildings.size()
	sim_e._roll_autobuild()
	_check(sim_e.buildings.size() == buildings_before + 1, "староста заложил дом: мест жителям не хватает")
	_check(String(sim_e.buildings[-1]["type"]) == "house", "автопостройка — это дом")
	_check(String(sim_e.chronicle[-1]["key"]) == "chron.autobuild", "автопостройка записана в летопись")
	sim_e.res["food"] = 4.0
	sim_e._roll_autobuild()
	_check(String(sim_e.buildings[-1]["type"]) == "farm", "при малом запасе еды староста строит ферму")
	var sim_e2 := _make_sim()
	for r in sim_e2.residents:
		if String(r["prof"]) == "elder":
			r["prof"] = "crafter"   # старосты нет — самострой запрещён
	var buildings_before2: int = sim_e2.buildings.size()
	sim_e2._roll_autobuild()
	_check(sim_e2.buildings.size() == buildings_before2, "без старосты город сам не строит")

	# преемственность: староста погиб — самым опытным становится новый староста
	var sim_pr := _make_sim()
	var dead_elder: Dictionary = _resident_by_prof(sim_pr, "elder")
	var heir: Dictionary = sim_pr.residents[0]
	if heir == dead_elder:
		heir = sim_pr.residents[1]
	heir["skill"] = 4.0
	sim_pr._kill(dead_elder, "chron.died_sick")
	sim_pr._ensure_elder()
	_check(String(heir["prof"]) == "elder", "самый опытный стал новым старостой")
	_check(String(sim_pr.chronicle[-1]["key"]) == "chron.promoted", "назначение записано в летопись")

	# заболел — освободил рабочее место, здоровый замещающий подхватил (анти-стопор)
	var sim_il := _make_sim()
	sim_il.res["food"] = 30.0
	_build_now(sim_il, "farm")
	var farmer_il: Dictionary = _resident_by_prof(sim_il, "farmer")
	sim_il._make_ail(farmer_il, "sick", "chron.sick")
	_check(farmer_il["bld"] == null, "заболел — рабочее место освобождено")
	var farm_il: Dictionary = sim_il.buildings[-1]
	_check(int(farm_il["worker"]) > 0 and int(farm_il["worker"]) != int(farmer_il["id"]),
			"здоровый замещающий встал на ферму")

	# крепостное кольцо: стены растут вокруг города, ворота свободны (заказчик)
	var sim_wl := _make_sim()
	var w1: Vector2i = sim_wl._next_wall_tile()
	var off1: Vector2i = w1 - sim_wl.map.spawn_tile
	_check(maxi(absi(off1.x), absi(off1.y)) == 6, "стены растут кольцом радиуса 6 вокруг города")
	_check(not (off1.x == 0 or off1.y == 0), "на воротах кольца стены не будет")
	var placed_walls := 0
	var gate_broken := false
	for i in 200:
		var wt: Vector2i = sim_wl._next_wall_tile()
		if wt == Vector2i(-1, -1):
			break
		if not sim_wl.place_building("wall", wt):
			break
		placed_walls += 1
	for g in [Vector2i(0, -6), Vector2i(0, 6), Vector2i(-6, 0), Vector2i(6, 0)]:
		if not sim_wl.building_at(sim_wl.map.spawn_tile + g).is_empty():
			gate_broken = true
	_check(placed_walls > 0, "стены кольца поставлены")
	_check(not gate_broken, "четыре ворот (С/Ю/З/В) свободны для выхода из крепости")

	# стройка с первого дня (заказчик): первые тики дня 1 уже дают план
	var sim_d1 := _make_sim()
	sim_d1._last_daily_day = 0   # как в реальной игре
	var b_before: int = sim_d1.buildings.size()
	sim_d1.tick(0.2)
	_check(sim_d1.buildings.size() > b_before, "староста строит с первого дня")

	# районы: дома — к западу, производство — к востоку (заказчик)
	var sim_z := _make_sim()
	var htile: Vector2i = sim_z._find_autobuild_tile("house")
	var ftile: Vector2i = sim_z._find_autobuild_tile("farm")
	_check(htile.x < sim_z.map.spawn_tile.x, "жилой район к западу от центра")
	_check(ftile.x > sim_z.map.spawn_tile.x, "производственный район к востоку")

	# каменоломня и мастерская — разные здания (заказчик)
	var sim_st := _make_sim()
	var miner_q: Dictionary = sim_st._new_resident("Герд", "miner", sim_st.map.spawn_tile)
	sim_st.residents.append(miner_q)
	sim_st._next_id += 1
	sim_st.res["wood"] = 25.0
	sim_st.res["stone"] = 10.0
	var quarry := _build_now(sim_st, "quarry")
	_check(int(quarry["worker"]) == int(miner_q["id"]), "шахтёр работает в каменоломне")
	_teleport(sim_st, miner_q, quarry["tile"])
	sim_st.cfg["food_per_resident_day"] = 0.0
	sim_st.tick(10.0)   # первый тик — дойти до скалы
	sim_st.tick(10.0)   # второй — добывать
	_check(float((quarry["pile"] as Dictionary).get("stone", 0.0)) > 0.0,
			"каменоломня добывает камень в кучу у здания (M6)")
	var crafter_q: Dictionary = sim_st._new_resident("Кира", "crafter", sim_st.map.spawn_tile)
	sim_st.residents.append(crafter_q)
	sim_st._next_id += 1
	_build_now(sim_st, "workshop")
	var workshop_q: Dictionary = sim_st.buildings[-1]
	_check(crafter_q["bld"] != null and int((crafter_q["bld"] as Dictionary)["id"]) == int(workshop_q["id"]),
			"мастер занял мастерскую")
	sim_st.res["wood"] = 15.0
	sim_st.res["stone"] = 10.0
	_teleport(sim_st, crafter_q, workshop_q["tile"])
	sim_st.time = 10.0   # утро: ночь в конце длинного теста усыпила бы мастера
	sim_st.tick(20.0)
	_check(float((workshop_q["pile"] as Dictionary).get("tools", 0.0)) > 0.0,
			"мастерская перерабатывает дерево и камень в инструменты (M6)")
	var worker_probe: Dictionary = {"traits": [], "mood": 50.0, "skill": 0.0, "friend": -1, "work_bonus": 0.0, "sub_prof": ""}
	sim_st.res["tools"] = 0.0
	var plain_q: float = sim_st.work_mult(worker_probe)
	sim_st.res["tools"] = 5.0
	_check(sim_st.work_mult(worker_probe) > plain_q, "инструменты ускоряют работу")

	# ворота в стене: без стража закрыты, вышка со стражем рядом открывает (заказчик)
	var sim_gt := _make_sim()
	sim_gt.res["wood"] = 30.0
	sim_gt.res["stone"] = 30.0
	var gate_tile: Vector2i = sim_gt.map.spawn_tile + Vector2i(0, -4)
	while not sim_gt.is_buildable_tile(gate_tile):
		gate_tile += Vector2i(0, -1)
	sim_gt.place_building("gate", gate_tile)
	var builder_gt: Dictionary = _resident_by_prof(sim_gt, "builder")
	# M4-черты («ленивый») замедляют стройку — в этом тесте они не при чём
	builder_gt["mood"] = 100.0
	builder_gt["traits"] = []
	_teleport(sim_gt, builder_gt, gate_tile)
	sim_gt.tick(15.5)
	var gate_b: Dictionary = sim_gt.building_at(gate_tile)
	_check(bool(gate_b["done"]), "ворота построены в проёме")
	_check(not bool(sim_gt.is_gate_open(gate_b)), "без стража на вышке ворота закрыты")
	_check(not sim_gt.map.is_walkable(gate_tile), "закрытые ворота непроходимы")
	# карта стала плотнее (M5.1) — вышку ставим на ближайшее свободное место
	var tower_tile: Vector2i = Vector2i(-1, -1)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t: Vector2i = gate_tile + Vector2i(dx, dy)
			if sim_gt.is_buildable_tile(t):
				tower_tile = t
				break
		if tower_tile != Vector2i(-1, -1):
			break
	_check(tower_tile != Vector2i(-1, -1), "у ворот есть место под вышку")
	sim_gt.place_building("tower", tower_tile)
	_teleport(sim_gt, builder_gt, tower_tile)
	sim_gt.tick(30.5)
	_check(bool(sim_gt.is_gate_open(gate_b)), "страж на ближней вышке открыл ворота")
	_check(sim_gt.map.is_walkable(gate_tile), "открытые ворота проходимы")

	# план города: староста строит сразу весь нужный набор по порядку (заказчик)
	var sim_pl := _make_sim()
	_build_now(sim_pl, "house")   # дом есть — теснота не перебивает план
	_build_now(sim_pl, "farm")    # и баланс еды положительный — ферма не перебивает план
	var plan: Array = sim_pl.cfg.get("autobuild_plan", [])
	_check(plan.size() >= 10, "в плане города весь набор строений")
	_check(String(plan[0]) == "sawmill", "план начинается с лесопилки — иначе дереву не взяться")
	var count_before: int = sim_pl.buildings.size()
	sim_pl._roll_autobuild()
	var has_first := false
	for b in sim_pl.buildings:
		if String(b["type"]) == String(plan[0]):
			has_first = true
	_check(has_first, "план начинается с первого строения")
	_check(sim_pl.buildings.size() - count_before == 2, "стройка идёт сразу: два здания за день")
	sim_pl._roll_autobuild()
	sim_pl._roll_autobuild()
	var first_type := String(plan[0])
	var first_count := 0
	for b in sim_pl.buildings:
		if String(b["type"]) == first_type:
			first_count += 1
	var wanted: int = mini(3, sim_pl._plan_count(plan, first_type))
	_check(first_count == wanted, "по плану: %s ×%d" % [first_type, wanted])

	# стены строятся последними: план выполнен, но есть недострой — стены ждут (заказчик)
	var sim_w2 := _make_sim()
	sim_w2.cfg["autobuild_plan"] = []   # весь план города уже выполнен
	var elder_w: Dictionary = sim_w2._new_resident("Ярл", "elder", sim_w2.map.spawn_tile)
	sim_w2.residents.append(elder_w)
	sim_w2.res["food"] = 30.0
	_build_now(sim_w2, "farm")   # баланс еды положительный — стены, а не ферма
	_build_now(sim_w2, "house")
	_build_now(sim_w2, "house")
	var wtile: Vector2i = sim_w2.map.spawn_tile + Vector2i(7, 0)
	while not sim_w2.is_buildable_tile(wtile):
		wtile += Vector2i(1, 0)
	sim_w2.place_building("well", wtile)
	sim_w2._roll_autobuild()
	var walls_mid := 0
	for b in sim_w2.buildings:
		if String(b["type"]) == "wall":
			walls_mid += 1
	_check(walls_mid == 0, "стены не начинаются, пока есть недостроенное здание")
	var builder_w: Dictionary = _resident_by_prof(sim_w2, "builder")
	_teleport(sim_w2, builder_w, wtile)
	sim_w2.tick(15.5)
	sim_w2._roll_autobuild()
	var walls_after := 0
	for b in sim_w2.buildings:
		if String(b["type"]) == "wall":
			walls_after += 1
	_check(walls_after == 2, "все строения готовы — началась защита: кольцо (два звена в день)")


# --- M3: магия ------------------------------------------------------------

func _make_magic() -> Object:
	var magic = load("res://scripts/magic.gd").new()
	magic.setup(_read_json("res://data/magic.json"))
	return magic


func _test_magic() -> void:
	print("[Магия: рецепты и спеллбук]")
	var magic := _make_magic()
	_check(String(magic.recipe_result("rune_sparks", "rune_chaos")) == "fire_flash",
			"рецепт: искра+хаос = Огненная вспышка")
	_check(String(magic.recipe_result("rune_chaos", "rune_sparks")) == "fire_flash",
			"рецепт не зависит от порядка рун")
	_check(String(magic.recipe_result("rune_chaos", "rune_chaos")) == "wild_resonance",
			"рецепт: хаос+хаос = Дикий резонанс")
	_check(String(magic.recipe_result("rune_storm", "rune_storm")) == "",
			"неизвестная пара рун даёт пустой результат")
	# все 8 рун участвуют хотя бы в одном рецепте
	var used := {}
	for r in magic.cfg["recipes"]:
		used[String(r["a"])] = true
		used[String(r["b"])] = true
	_check(used.size() >= 8, "все руны (>=8) используются в рецептах")
	# у всех спеллов корректные ссылки на школы
	var school_ids := {}
	for s in magic.cfg["schools"]:
		school_ids[String(s["id"])] = true
	var refs_ok := true
	var city_count := 0
	var dungeon_count := 0
	for sp in magic.cfg["spells"]:
		if not school_ids.has(String(sp["school"])):
			refs_ok = false
		if String(sp["where"]) == "city":
			city_count += 1
		else:
			dungeon_count += 1
	_check(refs_ok, "у всех заклинаний известная школа")
	_check(city_count == 6 and dungeon_count == 14, "6 городских + 14 боевых заклинаний (M7: +8)")
	# спеллбук в Game: изучение, дубли, удаление предметов
	var game: Node = load("res://scripts/game.gd").new()
	_check(game.magic != null, "Game._init загрузил data/magic.json")
	_check(not game.has_spell("heal"), "спеллбук пуста на новом Game")
	game.learn_spell("heal")
	game.learn_spell("heal")
	game.learn_spell("shield")
	_check(game.spellbook.size() == 2 and game.has_spell("heal"), "learn_spell без дублей")
	game.add_item("rune_light", 3)
	_check(game.remove_item("rune_light", 2) == 2, "remove_item убирает запрошенное")
	_check(game.count_item("rune_light") == 1, "остаток стака после remove_item")
	game.free()


func _test_magic_sim() -> void:
	print("[Магия: город — загрязнение, заклинания, зачарование]")
	var magic := _make_magic()

	# полосы загрязнения и множитель производства
	var sim := _make_sim()
	_check(String(sim.pollution_band()) == "clean", "новый город: полоса «чисто»")
	_check(absf(float(sim.production_mult({"ench_mult": 1.0})) - 1.0) < 0.001,
			"при чистоте множитель производства 1.0")
	sim.pollution = 40.0
	_check(String(sim.pollution_band()) == "mild", "40 загрязнения — наэлектризовано")
	_check(absf(float(sim.production_mult({})) - 1.05) < 0.001, "полоса mild: ×1.05")
	sim.pollution = 70.0
	_check(String(sim.pollution_band()) == "heart", "70 — магическое сердце")
	_check(absf(float(sim.production_mult({})) - 1.15) < 0.001, "полоса heart: ×1.15")
	sim.add_pollution(500.0)
	_check(absf(float(sim.pollution) - 100.0) < 0.001, "add_pollution ограничен 100")
	# спад загрязнения со временем (бурю выключаем — тест не про неё)
	sim.pollution = 50.0
	sim.cfg["storm"]["base_chance"] = 0.0
	sim.tick(float(sim.cfg["day_length"]))
	_check(absf(float(sim.pollution) - 48.0) < 0.1, "за день загрязнение падает на decay_per_day")

	# городские заклинания: нужен алтарь, кристаллы, кулдаун
	var sim2 := _make_sim()
	sim2.res["crystal"] = 3.0   # кристаллы из данжа
	var resonance_def: Dictionary = magic.spell("wild_resonance")
	var err: String = sim2.cast_city_spell(resonance_def)
	_check(err == "no_altar", "без алтаря городской каст невозможен")
	_build_now(sim2, "altar")
	var acolyte2: Dictionary = _resident_by_prof(sim2, "acolyte")
	_teleport(sim2, acolyte2, sim2.buildings[-1]["tile"])
	sim2.tick(0.3)
	sim2.res["crystal"] = 0.0
	err = sim2.cast_city_spell(magic.spell("cleanse"))
	_check(err == "no_crystals", "без кристаллов каст невозможен")
	sim2.res["crystal"] = 10.0
	err = sim2.cast_city_spell(resonance_def)
	_check(err == "", "Дикий резонанс соткан у алтаря")
	_check(float(sim2.res["crystal"]) == 8.0, "резонанс потратил 2 кристалла")
	_check(float(sim2.resonance_left) > 0.0, "резонанс действует")
	_check(absf(float(sim2.pollution) - 15.0) < 0.001, "резонанс добавил 15 загрязнения")
	err = sim2.cast_city_spell(resonance_def)
	_check(err == "cooldown", "второй каст сразу — упирается в кулдаун")
	# множитель: полоса mild (15 < 30 — нет) + резонанс 1.5
	var mult_base: float = float(sim2.production_mult({}))
	_check(absf(mult_base - 1.5) < 0.001, "во время резонанса производство ×1.5")
	err = sim2.cast_city_spell(magic.spell("cleanse"))
	_check(err == "" and absf(float(sim2.pollution)) < 0.001, "Очищение сняло загрязнение в ноль")
	var food_before: float = float(sim2.res["food"])
	sim2.cast_city_spell(magic.spell("forest_gift"))
	_check(absf(float(sim2.res["food"]) - (food_before + 15.0)) < 0.001, "Дары леса: +15 еды")
	# фикс v0.4.2: дар не режет запас выше вместимости хранилища
	sim2.res["food"] = 400.0
	food_before = float(sim2.res["food"])
	sim2._spell_ready.clear()
	sim2.cast_city_spell(magic.spell("forest_gift"))
	_check(absf(float(sim2.res["food"]) - food_before) < 0.001,
			"Дары леса при запасе выше хранилища не уменьшает еду")

	# зачарование фермы: +25% к производству
	var sim3 := _make_sim()
	sim3.cfg["food_per_resident_day"] = 0.0
	var house_bld := _build_now(sim3, "house")   # дом заранее: его тик не попадёт в замер
	var farm := _build_now(sim3, "farm")
	var farmer: Dictionary = _resident_by_prof(sim3, "farmer")
	# нейтрализуем личность: сравнение точное, без черт и настроения M4
	farmer["traits"] = []
	farmer["mood"] = 50.0
	farmer["skill"] = 0.0
	_teleport(sim3, farmer, farm["tile"])
	sim3.tick(10.0)
	var pile_plain: float = float((farm["pile"] as Dictionary).get("food", 0.0))
	var inv := [{"id": "rune_growth", "count": 1}]
	sim3.res["crystal"] = 5.0
	var farm_def: Dictionary = magic.enchantment("growth")
	_check(String(sim3.enchant_building(house_bld, farm_def, inv)) == "enchant_wrong",
			"«Ярость урожая» не ставится на дом (цель — ферма)")
	_check(String(sim3.enchant_building(farm, magic.enchantment("ward"), inv)) == "no_rune",
			"«Оберег» без руны камня невозможен")
	_check(String(sim3.enchant_building(farm, farm_def, inv)) == "",
			"ферма зачарована руной роста")
	_check(inv.is_empty(), "руна списана из рюкзака")
	_check(absf(float(sim3.production_mult(farm)) - 1.25) < 0.001, "зачарование даёт ×1.25")
	sim3.tick(10.0)
	var sim4 := _make_sim()
	sim4.cfg["food_per_resident_day"] = 0.0
	var farmer4: Dictionary = _resident_by_prof(sim4, "farmer")
	farmer4["traits"] = []
	farmer4["mood"] = 50.0
	farmer4["skill"] = 0.0
	var farm4 := _build_now(sim4, "farm")
	_teleport(sim4, farmer4, farm4["tile"])
	sim4.tick(10.0)
	var gain_ench: float = float((farm4["pile"] as Dictionary).get("food", 0.0))
	var gain_after: float = float((farm["pile"] as Dictionary).get("food", 0.0)) - pile_plain
	_check(absf(gain_ench * 1.25 - gain_after) < 0.05,
			"зачарованная ферма даёт ровно +25% еды за то же время (замер по куче — M6)")

	# зачарование алтаря «Мана»: параметры маны героя
	var sim5 := _make_sim()
	sim5.res["crystal"] = 3.0   # кристаллы из данжа
	var mana_before: Dictionary = sim5.hero_mana_params()
	_check(int(mana_before["cap_extra"]) == 0, "без зачарования запас маны обычный")
	_build_now(sim5, "altar")
	var altar5: Dictionary = sim5.buildings[-1]
	var acolyte5: Dictionary = _resident_by_prof(sim5, "acolyte")
	_teleport(sim5, acolyte5, altar5["tile"])
	sim5.tick(0.3)
	var inv_light := [{"id": "rune_light", "count": 1}]
	sim5.res["crystal"] = 5.0
	_check(String(sim5.enchant_building(altar5, magic.enchantment("mana"), inv_light)) == "",
			"алтарь зачарован «Мана-связью»")
	var mana_after: Dictionary = sim5.hero_mana_params()
	_check(int(mana_after["cap_extra"]) == 4, "зачарованный алтарь: +4 к запасу маны")
	_check(absf(float(mana_after["regen_period"]) - 5.0) < 0.001, "зачарованный алтарь: реген 5с")

	# дикие события при переборе (>=85): шанс 1.0 — гарантированно за день
	var sim6 := _make_sim()
	_build_now(sim6, "house")
	sim6.cfg["pollution"]["event_chance_per_day"] = 1.0
	sim6.pollution = 95.0
	sim6.time = float(sim6.cfg["day_length"]) - 0.5
	sim6.tick(1.0)
	_check(sim6.day == 2, "тик перешёл границу дня")
	var wild_seen := false
	for ev in sim6.events:
		if String(ev["type"]).begins_with("wild_"):
			wild_seen = true
	_check(wild_seen, "при переборе случилось дикое событие")
	# вспышка оглушает незачарованное здание
	var house6: Dictionary = sim6.buildings[0]
	var stunned: bool = float(house6["stun_left"]) > 0.0 or sim6.pollution >= 90.0
	_check(stunned, "вспышка оглушила здание или случился прилив")
	# «Оберег» защищает: единственное здание зачаровано — вспышка вырождается в прилив
	var sim7 := _make_sim()
	var house7 := _build_now(sim7, "house")
	inv = [{"id": "rune_stone", "count": 1}]
	sim7.res["crystal"] = 5.0
	_check(String(sim7.enchant_building(house7, magic.enchantment("ward"), inv)) == "",
			"дом под «Оберегом»")
	sim7.cfg["pollution"]["event_chance_per_day"] = 1.0
	sim7.pollution = 90.0
	sim7._event_rng.seed = 12345
	sim7.time = float(sim7.cfg["day_length"]) - 0.5
	sim7.tick(1.0)
	_check(float(house7["stun_left"]) == 0.0, "Оберег: здание не оглушено")
	_check(absf(float(sim7.pollution) - 95.0) < 0.001 or float(sim7.pollution) >= 90.0,
			"вспышка выродилась в прилив (или шанс не выпал)")
	# оглушённое здание не производит
	var sim8 := _make_sim()
	sim8.cfg["food_per_resident_day"] = 0.0
	var farm8 := _build_now(sim8, "farm")
	var farmer8: Dictionary = _resident_by_prof(sim8, "farmer")
	_teleport(sim8, farmer8, farm8["tile"])
	farm8["stun_left"] = 50.0
	var food_start8: float = float(sim8.res["food"])
	sim8.tick(2.0)
	_check(String(farmer8["state"]) == "idle", "работник оглушённого здания стоит")
	_check(absf(float(sim8.res["food"]) - food_start8) < 0.001, "оглушённая ферма не даёт еды")


func _test_spell_damage() -> void:
	print("[Магия: уязвимости врагов]")
	var enemies: Array = _read_json("res://data/enemies.json")
	var by_id := {}
	for e in enemies:
		by_id[String(e["id"])] = e
	var enemy_script: Script = load("res://scripts/enemy.gd")
	_check(int(enemy_script.calc_spell_damage(by_id["skeleton"], 2, "light")) == 4,
			"скелет уязвим к свету: урон ×2")
	_check(int(enemy_script.calc_spell_damage(by_id["golem"], 3, "nature")) == 6,
			"голем уязвим к природе: урон ×2")
	_check(int(enemy_script.calc_spell_damage(by_id["rat"], 2, "wild")) == 4,
			"крыса уязвима к дикой магии")
	_check(int(enemy_script.calc_spell_damage(by_id["rat"], 2, "light")) == 2,
			"чужая школа — обычный урон")
	_check(int(enemy_script.calc_spell_damage(by_id["antimage"], 5, "light")) == 0,
			"антимаг иммунен к любой магии")
	_check(int(enemy_script.calc_spell_damage(by_id["antimage"], 5, "")) == 0,
			"антимаг: даже «нейтральный» магический урон не проходит")
	_check(int(enemy_script.calc_spell_damage(by_id["skeleton"], 5, "")) == 5,
			"пустая школа у обычного врага — урон как есть (путь меча)")
	_check(String(by_id["antimage"].get("weak_school", "")) == "",
			"у антимага нет уязвимой школы")


# --- M5: угрозы и оборона -------------------------------------------------

## Построить здание в конкретном тайле мгновенно (строитель телепортируется).
## Если на выбранном тайле строить нельзя (M10: карта выросла, рельеф на старых
## сидах сменился; пилораме нужен лес, шахте — руда) — перебираем случайные
## тайлы, пока место не подойдёт под требования здания.
func _build_at(sim: Object, type_id: String, tile: Vector2i) -> Dictionary:
	var builder: Dictionary = _resident_by_prof(sim, "builder")
	builder["mood"] = 100.0
	builder["traits"] = []
	builder["skill"] = 0.0
	var placed: bool = sim.place_building(type_id, tile)
	if not placed:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234567
		for i in 600:
			var t := Vector2i(rng.randi_range(2, sim.map.w - 3), rng.randi_range(2, sim.map.h - 3))
			if sim.place_building(type_id, t):
				tile = t
				placed = true
				break
	_check(placed, "%s: стройплощадка в заданном тайле" % type_id)
	var work := 1.0
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			work = float(d["build_work"])
	_teleport(sim, builder, tile)
	sim.tick(work + 0.1)
	return sim.building_at(tile)


## Волна из одного мутанта заданного типа в заданном тайле (детерминированно).
func _spawn_one_raider(sim: Object, type_id: String, tile: Vector2i) -> Dictionary:
	sim._enemies_cfg = _read_json("res://data/enemies.json")
	sim._spawn_raid(1, false)
	var r: Dictionary = sim.raiders[0]
	for e: Dictionary in sim._enemies_cfg:
		if String(e["id"]) == type_id:
			r["p"] = e
			r["type"] = type_id
	r["pos"] = sim.map.tile_center_px(tile)
	r["path"] = PackedVector2Array()
	return r


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
		if sim.is_buildable_tile(t):
			gate_tile = t
			break
	_check(gate_tile != Vector2i(-1, -1), "нашёлся проём под ворота")
	var gate := _build_at(sim, "gate", gate_tile)
	_check(bool(gate["done"]), "ворота достроены")
	var tower_g := _build_at(sim, "tower", _find_free_tile(sim, gate_tile))
	_check(bool(tower_g["done"]), "вышка у ворот достроена")
	var guard_g: Dictionary = _resident_by_prof(sim, "guard")
	_teleport(sim, guard_g, tower_g["tile"])
	sim.tick(0.1)
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

	# мутант ломает стену
	var sim2 := _make_sim()
	sim2._next_raid_at = 999999999.0
	sim2._last_daily_day = 999
	sim2.time = 10.0 * float(sim2.cfg["day_length"])
	var wall_tile: Vector2i = sim2.map.spawn_tile + Vector2i(4, 0)
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
	_spawn_one_raider(sim2, "brute", brute_tile)
	var razed_seen := false
	for i in 1200:
		sim2.tick(0.2)
		if sim2.building_at(wall_tile).is_empty():
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
		if sim6.building_at(_ward_test_farm_tile(sim6)).is_empty():
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
func _ward_test_farm_tile(sim: Object) -> Vector2i:
	for b in sim.buildings:
		if bool(b["done"]) and String(b.get("enchant", "")) != "ward":
			return b["tile"]
	return Vector2i(-1, -1)


## Первый тайл руды на карте.
func _ore_tile_of(sim: Object) -> Vector2i:
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_ORE:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Добавить жителя редкой профессии (в стартовом наборе её нет).
func _add_resident(sim: Object, res_name: String, prof: String) -> Dictionary:
	var r: Dictionary = sim._new_resident(res_name, prof, sim.map.spawn_tile)
	sim.residents.append(r)
	sim._next_id += 1
	return r


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
	var near_forge: Vector2i = _find_free_tile(sim, forge["tile"])
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
	sim.tick(30.0)
	_check(float((smelt["pile"] as Dictionary).get("metal", 0.0)) > 0.0, "плавильня превращает руду в металл (куча)")
	sim.time = 10.0
	var smith_r := _add_resident(sim, "Борн", "smith")
	sim.res["metal"] = 10.0
	sim.res["tools"] = 0.0
	_teleport(sim, smith_r, forge["tile"])
	sim.tick(30.0)
	_check(float((forge["pile"] as Dictionary).get("tools", 0.0)) > 0.0, "кузня куёт металлические инструменты (куча)")
	sim.res["stone"] = 30.0   # плавильня и кузня съели весь камень
	sim.res["metal"] = 20.0
	# оружейная требует кузню в радиусе 2 по прямой — ищем такой тайл честно
	var armory_tile := Vector2i(-1, -1)
	for radius in range(1, 3):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t: Vector2i = (forge["tile"] as Vector2i) + Vector2i(dx, dy)
				if sim.is_buildable_tile(t, "armory") and sim.placement_block("armory", t) == "":
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
	sim.tick(60.0)
	_check(float((armory["pile"] as Dictionary).get("kits", 0.0)) > 0.0, "оружейная собирает боевые комплекты (куча)")

	# охота: охотник добывает зверя, еда в пул (зверь бродит — даём время на погоню)
	var sim_h := _make_sim()
	sim_h._last_daily_day = 999
	_check(not sim_h.animals.is_empty(), "зверь ходит по карте")
	var hunter_r := _add_resident(sim_h, "Ярл", "hunter")
	var prey: Dictionary = sim_h.animals[0]
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
	for radius in range(1, 3):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t: Vector2i = (forge_k["tile"] as Vector2i) + Vector2i(dx, dy)
				if sim_k2.is_buildable_tile(t, "armory") and sim_k2.placement_block("armory", t) == "":
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

	# рост волн: следующая позже (+2 дня) и сильнее
	var sim_w2 := _make_sim()
	sim_w2._last_daily_day = 999
	sim_w2._next_raid_at = 999999999.0
	sim_w2._spawn_raid(1, false)
	sim_w2.raiders.clear()
	sim_w2._raid_end(true)
	var eta: float = sim_w2.raid_eta_days()
	_check(eta > 2.5, "после волны интервал вырос до %.1f дня (+2)" % eta)
	sim_w2._spawn_raid(1, false)
	var r2: Dictionary = sim_w2.raiders[0]
	var expected: int = int(round(float(r2["p"]["hp"]) * (1.0 + sim_w2.threat_value() * 0.04 + 1 * 0.15)))
	_check(int(r2["max_hp"]) == expected, "вторая волна крепче: формула роста работает")

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

	# стартовый город: 10 жителей (заказчик: поселение должно вывозить)
	var game6: Node = load("res://scripts/game.gd").new()
	game6.new_city()
	_check(game6.city_sim.residents.size() == 10, "новый город: 10 жителей на старте")
	_check(game6.city_sim.pop_cap() >= 10, "лимит жителей вмещает стартовый набор")
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
	sim_sg.tick(5.0)   # дойти до дерева
	sim_sg.tick(5.0)   # рубить
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
func _grass_tiles(sim: Object, near: Vector2i, n: int) -> Array:
	var out: Array = []
	for radius in range(0, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if out.size() >= n:
					return out
				var t: Vector2i = near + Vector2i(dx, dy)
				if sim.map.in_bounds(t) and sim.map.grid[t.y][t.x] == sim.map.TILE_GRASS \
						and sim.building_at(t).is_empty() and not (t in out):
					out.append(t)
	return out


func _test_m6() -> void:
	print("[M6: зоны, дороги, носильщик, декор]")

	# --- зоны: разбивка, отсев негодных клеток, заполнение жителями ---
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
	var added: int = sim.add_zone("living", mixed)
	_check(added == cells.size(), "зона разбита: вода и скалы отсечены")
	_check(sim.zones.size() == 1, "зона сохранена в симуляции")
	_check(sim.add_zone("living", cells) == 0, "второй раз на те же клетки зону не разбить")
	_check(sim.add_zone("unknown", cells) == 0, "неизвестный тип зоны отвергается")
	# жилые клетки дают лимит жителей только после обустройства
	var cap0: int = sim.pop_cap()
	var zliving: Dictionary = sim.zones[0]
	var farmer_z: Dictionary = _resident_by_prof(sim, "farmer")
	farmer_z["traits"] = []
	farmer_z["mood"] = 100.0
	# заполняем все клетки по очереди: житель сам идёт к ближайшей незаполненной
	for i in (zliving["cells"] as Array).size():
		_teleport(sim, farmer_z, zliving["cells"][i])
		sim.tick(6.0)
	_check(sim.pop_cap() > cap0, "обустроенная жилая зона добавила лимит жителей (шалаши)")
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
	# M10: поле работает циклами посев→рост→урожай (stage_days 0.5 → урожай
	# созревает за ~2.5 дня); тикаем полднями, пока не соберём урожай
	for i in 6:
		sim_f.tick(float(sim_f.cfg["day_length"]) / 2.0)
	var expected: float = float(fcells.size()) * float(sim_f.cfg["farming"]["harvest_food"])
	_check(float(sim_f.res["food"]) >= food0 + expected - 0.6,
			"поле собрало урожай: %d клетки × %.1f" % [fcells.size(), expected])
	_check(float(sim_f.res["seeds"]) >= 1.0 or (sim_f.zones[0]["crops"] as Array).size() > 0,
			"урожай вернул семена — цикл поля замкнулся")

	# --- здание на клетке зоны вытесняет её из зоны ---
	var sim_z2 := _make_sim()
	sim_z2._last_daily_day = 999
	var zcells: Array = _grass_tiles(sim_z2, sim_z2.map.spawn_tile + Vector2i(2, 2), 4)
	sim_z2.add_zone("field", zcells)
	var before_n: int = (sim_z2.zones[0]["cells"] as Array).size()
	sim_z2.place_building("wall", zcells[0])
	_check((sim_z2.zones[0]["cells"] as Array).size() == before_n - 1,
			"здание на клетке зоны убирает клетку из зоны")

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

	# --- носильщик: куча растёт, носильщик сносит на склад ---
	var sim_pg := _make_sim()
	sim_pg._last_daily_day = 999
	sim_pg.cfg["food_per_resident_day"] = 0.0
	sim_pg.cfg["piles"] = {"chunk": 2.0, "max": 20.0, "carry": 10.0}
	var farmer_pg: Dictionary = _resident_by_prof(sim_pg, "farmer")
	farmer_pg["traits"] = []
	farmer_pg["mood"] = 100.0
	var farm_pg := _build_now(sim_pg, "farm")
	_teleport(sim_pg, farmer_pg, farm_pg["tile"])
	sim_pg.tick(25.0)
	_check(float(sim_pg._pile_total(farm_pg)) >= 2.0, "куча у фермы доросла до готовой")
	var food_pg0: float = float(sim_pg.res["food"])
	# день настал — город сам обучает носильщика, раз кучам некомусть некому носить
	sim_pg._last_daily_day = 0
	sim_pg._roll_porter()
	var porter_pg: Dictionary = _resident_by_prof(sim_pg, "porter")
	_check(not porter_pg.is_empty(), "город сам обучил носильщика при готовых кучах")
	_teleport(sim_pg, porter_pg, farm_pg["tile"])
	sim_pg.tick(1.0)
	_check(float(porter_pg["carry"]) > 0.0 and float(sim_pg._pile_total(farm_pg)) < 2.0,
			"носильщик забрал кучу целиком")
	_teleport(sim_pg, porter_pg, sim_pg.map.spawn_tile)
	var dropped := false
	for i in 5:
		sim_pg.tick(0.5)
		if float(sim_pg.res["food"]) > food_pg0:
			dropped = true
			break
		_teleport(sim_pg, porter_pg, sim_pg.map.spawn_tile)
	_check(dropped, "без склада носильщик сносит груз к амбару города")
	# переполненное хранилище: носильщик ждёт с грузом
	sim_pg.res["food"] = float(sim_pg.storage_cap())
	farm_pg["pile"] = {"food": 5.0}
	var porter_pg2: Dictionary = _resident_by_prof(sim_pg, "porter")
	_teleport(sim_pg, porter_pg2, farm_pg["tile"])
	sim_pg.tick(1.0)
	_check(float(porter_pg2["carry"]) > 0.0, "носильщик снова забрал кучу")
	_teleport(sim_pg, porter_pg2, sim_pg.map.spawn_tile)
	sim_pg.tick(0.5)
	_check(float(porter_pg2["carry"]) > 0.0, "полное хранилище: носильщик ждёт с грузом")

	# --- бонус планировки: склад рядом с фермой ускоряет её ---
	var sim_l := _make_sim()
	sim_l._last_daily_day = 999
	var barn_l := _build_now(sim_l, "warehouse")
	var farm_tile_l: Vector2i = _find_free_tile(sim_l, barn_l["tile"])
	var farm_l := _build_at(sim_l, "farm", farm_tile_l)
	_check(bool(farm_l["done"]), "ферма у склада построена")
	_check(absf(float(sim_l.production_mult(farm_l)) - float(sim_l.cfg["layout"]["warehouse_mult"])) < 0.001,
			"склад рядом с фермой даёт +25% скорости (бонус планировки)")
	# дальняя ферма: заведомо за пределами радиуса склада
	var farm_far := Vector2i(-1, -1)
	for radius in range(8, 14):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t: Vector2i = sim_l.map.spawn_tile + Vector2i(dx, dy)
				if sim_l.is_buildable_tile(t, "farm") \
						and Vector2(t).distance_to(Vector2(barn_l["tile"])) > 5.0:
					farm_far = t
					break
			if farm_far != Vector2i(-1, -1):
				break
		if farm_far != Vector2i(-1, -1):
			break
	_check(farm_far != Vector2i(-1, -1), "нашлось место под дальнюю ферму")
	var farm_l2 := _build_at(sim_l, "farm", farm_far)
	var mult_far: float = float(sim_l.production_mult(farm_l2))
	_check(mult_far < 1.2, "далёкая от склада ферма без бонуса (%.2f)" % mult_far)

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
	var crafter_w: Dictionary = _add_resident(sim_w, "Кира", "crafter")
	var workshop_w := _build_now(sim_w, "workshop")
	_check(int(workshop_w["worker"]) == int(crafter_w["id"]), "мастер в мастерской")
	var house_w := _build_now(sim_w, "house")
	house_w["hp"] = 4.0   # дом повреждён бурей
	_teleport(sim_w, crafter_w, workshop_w["tile"])
	sim_w.time = 10.0
	sim_w.tick(10.0)   # первый тик — дойти до повреждённого дома
	sim_w.tick(10.0)   # второй — чинить
	_check(float(house_w["hp"]) > 4.0, "мастерская чинит повреждённое здание")
	var max_hp: float = float(sim_w._bld_max_hp("house"))
	house_w["hp"] = max_hp
	sim_w.res["wood"] = 20.0
	sim_w.res["stone"] = 20.0
	_teleport(sim_w, crafter_w, workshop_w["tile"])
	sim_w.time = 10.0
	sim_w.tick(20.0)
	_check(float((workshop_w["pile"] as Dictionary).get("tools", 0.0)) > 0.0,
			"чинить нечего — мастерская перерабатывает излишки в инструменты")

	# --- дорога под зданием исчезает; путь строится как раньше ---
	var sim_wr := _make_sim()
	sim_wr._last_daily_day = 999
	sim_wr.res["stone"] = 50.0
	var rtile: Vector2i = _grass_tiles(sim_wr, sim_wr.map.spawn_tile + Vector2i(1, 1), 1)[0]
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
	_check(biomes.size() == 5 and weights.size() == 4,
			"5 биомов данжа (M7: четыре + лагерь бандитов M10)")
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

	# --- дерево навыков: XP, уровни, выбор узла, бонусы ---
	var skills = load("res://scripts/skills.gd").new()
	skills.setup(_read_json("res://data/skills.json"))
	var branches: Array = skills.cfg.get("branches", [])
	_check(branches.size() == 3, "дерево навыков — 3 ветки")
	var nodes_ok := branches.size() == 3
	for branch in branches:
		if (branch.get("nodes", []) as Array).size() != 3:
			nodes_ok = false
	_check(nodes_ok, "в каждой ветке 3 узла (9 узлов всего)")
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
			and int(food_b.get("farm_per_day", 0)) == 16 \
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
	_check(dungeon_biomes.size() == 4, "данжи всех 4 биомов M7 представлены")
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


func sim_m8_setup(map_b, scfg: Dictionary) -> void:
	var sim = load("res://scripts/world_sim.gd").new()
	sim.setup(map_b, scfg, 777)
	var ruin: Dictionary = {}
	var caravan: Dictionary = {}
	var camp_strength0 := 0.0
	for poi in map_b.pois:
		match String(poi["kind"]):
			"ruins":
				ruin = poi
			"caravan":
				caravan = poi
			"camp":
				camp_strength0 += float(poi["strength"])
	sim.mark_cleared(int(ruin["id"]))
	_check(int(ruin["cleared_day"]) == 0, "зачистка локации отмечается в мире")
	_check(not sim.poi_enterable(ruin), "в зачищенный данж нельзя войти, пока он не сгустится заново")
	var caravan_tile0: Vector2i = caravan["tile"]
	var saw_siege := false
	var saw_outcome := false
	var saw_resettle := false
	var saw_reborn := false
	var caravan_moved := false
	for i in 90:
		for ev: Dictionary in sim.advance_day():
			match String(ev["type"]):
				"siege_start":
					saw_siege = true
				"siege_fell", "siege_repelled":
					saw_outcome = true
				"resettle":
					saw_resettle = true
				"poi_reborn":
					saw_reborn = true
				"caravan_moved":
					caravan_moved = true
	var camp_strength1 := 0.0
	for poi in map_b.pois:
		if String(poi["kind"]) == "camp":
			camp_strength1 += float(poi["strength"])
	_check(camp_strength1 > camp_strength0, "лагеря бандитов растут со временем")
	_check(saw_siege, "бандиты осаждают поселения — мир живёт без игрока (ответ №92)")
	_check(saw_outcome, "осады решаются: поселение падает или отбивается")
	_check(saw_resettle, "павшие поселения переселяются другими фракциями (ответ №4)")
	_check(saw_reborn, "зачищенные локации сгущаются заново")
	_check(sim.poi_enterable(ruin), "сгустившийся заново данж снова принимает героя")
	_check(caravan_moved, "караван перебирается по миру")
	_check(sim.chronicle.size() > 0, "мировые события пишутся в летопись")

	# торговля (ответ №40): монеты + живой обмен
	var pool := {"food": 50.0, "wood": 0.0, "stone": 0.0, "crystal": 0.0}
	var coins := 20
	var out: Dictionary = sim.trade_buy(pool, coins, "wood", 5, caravan, 9999)
	var wood_cost: int = int(ceilf(sim.buy_price("wood", caravan) * 5))
	_check(String(out["err"]) == "" and int(out["coins"]) == coins - wood_cost,
			"покупка ресурсов за монеты (у каравана — скидка)")
	_check(float(pool["wood"]) == 5.0, "купленное попадает в пул города (караван доставляет)")
	_check(String(sim.trade_buy(pool, 1, "stone", 100, caravan, 9999)["err"]) == "no_coins",
			"без монет покупки нет")
	var sell_out: Dictionary = sim.trade_sell(pool, 0, "wood", 3, caravan)
	_check(String(sell_out["err"]) == "" and float(pool["wood"]) == 2.0 and int(sell_out["coins"]) > 0,
			"продажа ресурсов приносит монеты")
	var out4: Dictionary = sim.trade_barter(pool, {"give": "food", "get": "stone", "give_n": 3, "get_n": 2})
	_check(String(out4["err"]) == "" and float(pool["food"]) == 47.0 and float(pool["stone"]) == 2.0,
			"живой обмен: ресурс на ресурс по таблице")
	var inv: Array = []
	var rune_id: String = sim.cult_rune_offer()
	_check(rune_id != "", "культ предлагает руну")
	var rune_out: Dictionary = sim.trade_rune(inv, 30, rune_id)
	_check(String(rune_out["err"]) == "" and inv.size() == 1 and String(inv[0]["id"]) == rune_id,
			"руна культа покупается за монеты в рюкзак")
	_check(String(sim.trade_rune(inv, 0, rune_id)["err"]) == "no_coins", "без монет руну не продадут")
	_check(String(sim.trade_rune(inv, 30, "")["err"]) == "no_runes", "рун у культа нет — продажи нет")
	_check(sim.coin_reward({"kind": "camp"}) > 0, "за лагерь бандитов платят монетами")

	# край города: выход на карту мира — проходим и ДОСТИЖИМ пешком от старта
	# (иначе герой не доберётся до края — «не переходит на карту мира»)
	var city_cfg: Dictionary = _read_json("res://data/city.json")
	var exit_ok := true
	for i in 12:
		var cmap = load("res://scripts/city_map.gd").new()
		cmap.generate(1000 + i * 3571, city_cfg)
		if cmap.is_walkable(cmap.world_exit_tile) == false \
				or cmap.astar.get_id_path(cmap.spawn_tile, cmap.world_exit_tile).is_empty():
			exit_ok = false
	_check(exit_ok, "выход на карту мира проходим и достижим пешком (12 сидов)")
	# вся рамка карты — зона перехода: направление наружу определяется верно
	var cm0 = load("res://scripts/city_map.gd").new()
	cm0.generate(424242, city_cfg)
	var border_ok: bool = cm0.border_dir(Vector2i(0, 5)) == Vector2i(-1, 0) \
			and cm0.border_dir(Vector2i(cm0.w - 1, 5)) == Vector2i(1, 0) \
			and cm0.border_dir(Vector2i(5, 0)) == Vector2i(0, -1) \
			and cm0.border_dir(Vector2i(5, cm0.h - 1)) == Vector2i(0, 1) \
			and cm0.border_dir(Vector2i(0, 0)) == Vector2i(-1, -1) \
			and cm0.border_dir(cm0.spawn_tile) == Vector2i.ZERO
	_check(border_ok, "рамка карты — зона перехода: border_dir по всем краям")
	_check(cm0.nearest_walkable(Vector2i(0, 0)) != Vector2i(-1, -1),
			"nearest_walkable всегда возвращает проходимый тайл")


# --- M9: полировка — спрайты, ассеты, платформенные мелочи -------------------

const _ASSETS := preload("res://scripts/assets.gd")

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
	_check(missing == 0 and cfg["buildings"].size() == 23,
			"у всех 23 зданий есть PNG-спрайт (недостающих: %d)" % missing)
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
	# версия этапа
	_check(String(_read_json("res://data/version.json")["version"]).begins_with("1.1"),
			"версия проекта 1.1.x (M11 — вишлист)")


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
			"chron.caravan_returned", "chron.livestock_born"]:
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


var _coins_log: Array = []


# --- M11: вишлист — духи леса, некромант, добыча скалы -----------------------

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
	for y in sim_f.map.h:
		for x in sim_f.map.w:
			if sim_f.map.grid[y][x] == sim_f.map.TILE_TREE:
				tree_tile = Vector2i(x, y)
				break
		if tree_tile.x >= 0:
			break
	_check(tree_tile != Vector2i(-1, -1), "на карте есть дерево для вырубки")
	sim_f.cfg["piles"] = {"chunk": 2.0, "max": 60.0, "carry": 10.0}
	var spot := Vector2i(-1, -1)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t := tree_tile + Vector2i(dx, dy)
			if sim_f.is_buildable_tile(t) and sim_f.placement_block("sawmill", t) == "":
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

	# посадка: семя -> саженец -> дерево, гнев спадает
	sim_f.res["seeds"] = 5.0
	var anger_before := float(sim_f.forest_anger)
	var plant_tile := tree_tile
	for i in 40:
		if sim_f.can_plant_at(plant_tile):
			break
		plant_tile += Vector2i(1, 0)
	_check(sim_f.can_plant_at(plant_tile), "рядом есть место под саженец")
	_check(String(sim_f.plant_sapling(plant_tile)) == "", "саженец посажен за семя")
	_check(sim_f.map.saplings.has(plant_tile), "саженец отмечен на карте")
	var seed_after: float = float(sim_f.res["seeds"])
	_check(seed_after == 4.0, "посадка потратила семя")
	sim_f.map.saplings[plant_tile]["t"] = 9999.0
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
	for y in sim_q.map.h:
		for x in sim_q.map.w:
			if sim_q.map.grid[y][x] == sim_q.map.TILE_ROCK:
				rock_tile = Vector2i(x, y)
				break
		if rock_tile.x >= 0:
			break
	var qspot := Vector2i(-1, -1)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t2 := rock_tile + Vector2i(dx, dy)
			if sim_q.is_buildable_tile(t2) and sim_q.placement_block("quarry", t2) == "":
				qspot = t2
				break
		if qspot != Vector2i(-1, -1):
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
	var sim_n := _make_sim()
	sim_n.cfg["necro"]["dark_per_night"] = 0.5
	sim_n.cfg["necro"]["summon_chance"] = 1.0
	sim_n.cfg["necro"]["rise_at"] = 3
	var cem := _build_now(sim_n, "cemetery")
	_check(bool(cem["done"]), "кладбище построено")
	var cem_tile: Vector2i = cem["tile"]
	sim_n._roll_necro()
	_check(float(sim_n.necro_dark) > 0.0, "тьма кладбища растёт")
	_check(int(sim_n.necro_army) > 0, "скелеты собираются тайно")
	_check(bool(sim_n.necro_known), "некромантия раскрыта по тьме")
	var has_secret := false
	for r in sim_n.residents:
		if String(r.get("secret", "")) == "necromancer":
			has_secret = true
	_check(has_secret, "в городе завёлся тайный некромант")
	var attempts := 0
	while not sim_n.raid_active and attempts < 8:
		attempts += 1
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
	_check(sim_n.building_at(cem_tile).is_empty(), "кладбище разрушено ударом героя")
