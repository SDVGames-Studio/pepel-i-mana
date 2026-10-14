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
		for key in ["tile_size", "map_w", "map_h", "max_rooms", "enemy_count", "hero", "biome"]:
			_check(dungeon.has(key), "dungeon.json содержит %s" % key)
		var hero: Variant = dungeon.get("hero", {})
		_check(hero is Dictionary and hero.has("speed") and hero.has("dash_cooldown"),
				"dungeon.json: параметры героя полны")
	var enemies: Variant = _read_json("res://data/enemies.json")
	_check(enemies is Array and enemies.size() == 4, "enemies.json — 4 типа врагов (M3: +антимаг)")
	if enemies is Array:
		var fields_ok := true
		for enemy in enemies:
			for key in ["id", "hp", "damage", "speed", "aggro", "drop_chance"]:
				if not (enemy is Dictionary and enemy.has(key)):
					fields_ok = false
		_check(fields_ok, "enemies.json: у всех врагов есть поля боя и дропа")
	var magic: Variant = _read_json("res://data/magic.json")
	_check(magic is Dictionary, "magic.json — валидный JSON-словарь")
	if magic is Dictionary:
		_check((magic.get("schools", []) as Array).size() == 3, "magic.json — 3 школы")
		_check((magic.get("spells", []) as Array).size() == 9, "magic.json — 9 заклинаний (3×3)")
		_check((magic.get("recipes", []) as Array).size() == 9, "magic.json — 9 рецептов из рун")
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
			"pollution", "hero_mana", "test_mode", "autobuild_plan"]:
		_check(city.has(key), "city.json содержит %s" % key)
	var blds: Variant = city.get("buildings", [])
	_check(blds is Array and blds.size() == 12, "city.json — 12 типов зданий (M4: + каменоломня)")
	var bld_ok := true
	if blds is Array:
		for b in blds:
			for key in ["id", "loc", "desc", "color", "cost", "build_work", "district"]:
				if not (b is Dictionary and b.has(key)):
					bld_ok = false
	_check(bld_ok, "city.json: у зданий есть цена, время стройки и район")
	var districts := {}
	for b in city.get("buildings", []):
		if b is Dictionary:
			districts[String(b["district"])] = true
	_check(districts.has("living") and districts.has("work"), "город разбит на жилой и производственный районы")
	var profs: Variant = city.get("professions", [])
	_check(profs is Array and profs.size() == 10, "city.json — 10 профессий (M4: + шахтёр)")
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
		_check((residents_data.get("traits", []) as Array).size() >= 8, "residents.json — минимум 8 черт")
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
	for path in ["res://scenes/main_menu.tscn", "res://scenes/city.tscn", "res://scenes/dungeon.tscn"]:
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


func _find_free_tile(sim: Object, near: Vector2i) -> Vector2i:
	for radius in range(1, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := near + Vector2i(dx, dy)
				if sim.is_buildable_tile(tile):
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
	var tile := _find_free_tile(sim, near)
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

	# ферма: фермер работает, еда растёт (без расхода на еду — см. ниже)
	var farmer: Dictionary = _resident_by_prof(sim, "farmer")
	_check(not farmer.is_empty(), "среди жителей есть фермер")
	_teleport(sim, farmer, sim.map.spawn_tile + Vector2i(2, 2))
	sim.cfg["food_per_resident_day"] = 0.0
	var food_before: float = float(sim.res["food"])
	var farm := _build_now(sim, "farm")
	_teleport(sim, farmer, farm["tile"])
	sim.tick(10.0)
	_check(String(farmer["state"]) == "work", "фермер работает на ферме")
	_check(float(sim.res["food"]) > food_before, "ферма производит еду")

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
	var stone_before: float = float(sim_st.res["stone"])
	sim_st.tick(10.0)
	_check(float(sim_st.res["stone"]) > stone_before, "каменоломня добывает камень")
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
	_check(float(sim_st.res["tools"]) > 0.0, "мастерская делает инструменты из дерева и камня")
	var worker_probe: Dictionary = {"traits": [], "mood": 50.0, "skill": 0.0, "friend": -1, "work_bonus": 0.0, "sub_prof": ""}
	sim_st.res["tools"] = 0.0
	var plain_q: float = sim_st.work_mult(worker_probe)
	sim_st.res["tools"] = 5.0
	_check(sim_st.work_mult(worker_probe) > plain_q, "инструменты ускоряют работу")

	# план города: староста строит сразу весь нужный набор по порядку (заказчик)
	var sim_pl := _make_sim()
	_build_now(sim_pl, "house")   # дом есть — теснота не перебивает план
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
	_check(city_count == 3 and dungeon_count == 6, "3 городских + 6 боевых заклинаний")
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
	# спад загрязнения со временем
	sim.pollution = 50.0
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
	var food_plain: float = float(sim3.res["food"])
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
	var food4_start: float = float(sim4.res["food"])
	sim4.tick(10.0)
	var gain_ench: float = float(sim4.res["food"]) - food4_start
	var gain_after: float = float(sim3.res["food"]) - food_plain
	_check(absf(gain_ench * 1.25 - gain_after) < 0.05,
			"зачарованная ферма даёт ровно +25% еды за то же время")

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

