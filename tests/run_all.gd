extends SceneTree
## Автотесты этапов M0 + M1 + M2 + M3.
## Запуск headless: godot --headless --path . --script res://tests/run_all.gd
## В этом режиме автозагрузки не работают — всё проверяем через load()/FileAccess.

const REQUIRED_LOCALES := [
	"menu.title", "menu.version", "menu.new_game", "menu.exit",
	"menu.continue_city", "menu.setup_title", "menu.residents",
	"menu.start_level", "menu.level.low", "menu.level.normal", "menu.level.high",
	"menu.begin", "menu.back",
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
	for key in ["tile_size", "map_w", "map_h", "day_length", "speeds", "start", "loot_to_pool"]:
		_check(city.has(key), "city.json содержит %s" % key)
	var blds: Variant = city.get("buildings", [])
	_check(blds is Array and blds.size() == 9, "city.json — 9 типов зданий (8 из ТЗ 4.1 + лесопилка)")
	var bld_ok := true
	if blds is Array:
		for b in blds:
			for key in ["id", "loc", "desc", "color", "cost", "build_work"]:
				if not (b is Dictionary and b.has(key)):
					bld_ok = false
	_check(bld_ok, "city.json: у зданий есть цена и время стройки")
	var profs: Variant = city.get("professions", [])
	_check(profs is Array and profs.size() == 6, "city.json — 6 профессий")
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


# --- M2: город -----------------------------------------------------------

## Карта + симуляция города для теста (seed фиксирован).
func _make_sim(level: String = "normal") -> Object:
	var cfg: Variant = _read_json("res://data/city.json")
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(7, cfg)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(city_map, cfg, 5, level)
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
	_check(sim.residents.size() == 5, "старт: 5 жителей (ответ №11)")
	_check(sim.pop_cap() == 5, "лимит жителей = стартовым без домов")
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
	_check(sim.pop_cap() == 7, "дом даёт +2 к лимиту жителей")
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

	# еда: жители едят; пустой пул — голод, работа стоит
	sim.cfg["food_per_resident_day"] = 2.0
	sim.res["food"] = 0.0
	sim.tick(0.5)
	_check(String(farmer["state"]) == "hungry", "без еды житель голодает")
	sim.res["food"] = 50.0
	sim.tick(0.5)
	_check(String(farmer["state"]) != "hungry", "еда вернулась — работа продолжается")

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
	var sim4 := _make_sim("high")
	_check(int(sim4.res["crystal"]) == 2, "уровень «много»: 2 кристалла на старте")
	var altar := _build_now(sim4, "altar")
	var acolyte: Dictionary = _resident_by_prof(sim4, "acolyte")
	_check(not acolyte.is_empty(), "маг-ученик есть среди жителей")
	_teleport(sim4, acolyte, altar["tile"])
	sim4.tick(0.3)
	_check(bool(sim4.has_blessing()), "работающий алтарь даёт благословение")


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
	var sim2 := _make_sim("high")
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

	# зачарование фермы: +25% к производству
	var sim3 := _make_sim()
	sim3.cfg["food_per_resident_day"] = 0.0
	var house_bld := _build_now(sim3, "house")   # дом заранее: его тик не попадёт в замер
	var farm := _build_now(sim3, "farm")
	var farmer: Dictionary = _resident_by_prof(sim3, "farmer")
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
	var farm4 := _build_now(sim4, "farm")
	_teleport(sim4, farmer4, farm4["tile"])
	var food4_start: float = float(sim4.res["food"])
	sim4.tick(10.0)
	var gain_ench: float = float(sim4.res["food"]) - food4_start
	var gain_after: float = float(sim3.res["food"]) - food_plain
	_check(absf(gain_ench * 1.25 - gain_after) < 0.05,
			"зачарованная ферма даёт ровно +25% еды за то же время")

	# зачарование алтаря «Мана»: параметры маны героя
	var sim5 := _make_sim("high")
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

