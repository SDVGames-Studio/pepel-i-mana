extends SceneTree
## Автотесты этапов M0 + M1.
## Запуск headless: godot --headless --path . --script res://tests/run_all.gd
## В этом режиме автозагрузки не работают — всё проверяем через load()/FileAccess.

const REQUIRED_LOCALES := [
	"menu.title", "menu.version", "menu.new_game", "menu.exit",
	"city.stub_hint", "city.back_hint",
	"city.last_run_ok", "city.last_run_death", "city.last_run_nothing",
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
]

const M1_SCRIPTS := [
	"res://scripts/loc.gd", "res://scripts/main_menu.gd", "res://scripts/city.gd",
	"res://scripts/game.gd", "res://scripts/dungeon_gen.gd", "res://scripts/dungeon.gd",
	"res://scripts/dungeon_view.gd", "res://scripts/hero.gd", "res://scripts/enemy.gd",
	"res://scripts/chest.gd", "res://scripts/pickup.gd", "res://scripts/exit_marker.gd",
	"res://scripts/minimap.gd", "res://scripts/hud.gd",
]

var _fails := 0


func _initialize() -> void:
	_test_loc()
	_test_data()
	_test_scripts()
	_test_scenes()
	_test_dungeon_gen()
	_test_game_inventory()
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
	_check(enemies is Array and enemies.size() == 3, "enemies.json — ровно 3 типа врагов")
	if enemies is Array:
		var fields_ok := true
		for enemy in enemies:
			for key in ["id", "hp", "damage", "speed", "aggro", "drop_chance"]:
				if not (enemy is Dictionary and enemy.has(key)):
					fields_ok = false
		_check(fields_ok, "enemies.json: у всех врагов есть поля боя и дропа")
	var loot: Variant = _read_json("res://data/loot.json")
	_check(loot is Dictionary and (loot.get("rarities", []) as Array).size() == 4,
			"loot.json — 4 редкости")
	if loot is Dictionary:
		_check((loot.get("items", []) as Array).size() >= 9, "loot.json — минимум 9 предметов")


func _test_scripts() -> void:
	print("[Скрипты]")
	for path in M1_SCRIPTS:
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
