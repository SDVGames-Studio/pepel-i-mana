extends Node
## Автозагрузка: состояние между сценами — рюкзак героя, итог последнего
## забега и город (M2). Инвентарь без веса (ответ 52), стеки без лимита.
## Симуляция города тикается здесь: пока герой в данже, город продолжает жить.

const CITY_CFG_PATH := "res://data/city.json"
const CITY_SIM_SCRIPT := "res://scripts/city_sim.gd"
const CITY_MAP_SCRIPT := "res://scripts/city_map.gd"
const MAGIC_SCRIPT := "res://scripts/magic.gd"
const MAGIC_CFG_PATH := "res://data/magic.json"
const SKILLS_SCRIPT := "res://scripts/skills.gd"
const SKILLS_CFG_PATH := "res://data/skills.json"
const WORLD_CFG_PATH := "res://data/world.json"
const WORLD_MAP_SCRIPT := "res://scripts/world_map.gd"
const WORLD_SIM_SCRIPT := "res://scripts/world_sim.gd"
const ITEMS_CFG_PATH := "res://data/items.json"
const WEAPONS_CFG_PATH := "res://data/weapons.json"
const LOOT_CFG_PATH := "res://data/loot.json"

var inventory: Array = []        # [{id: String, count: int}]
var last_run_death := false      # true, если последний забег закончился гибелью
var city_sim = null              # city_sim.gd, нетипизированно (грабли GDScript 4)
var magic = null                 # magic.gd — школы/рецепты/заклинания (M3)
var skills = null                # skills.gd — XP, уровни, дерево навыков героя (M7)
var world_map = null             # world_map.gd — карта мира (M8)
var world_sim = null             # world_sim.gd — мир живёт программно (M8)
var spellbook: Array = []        # изученные заклинания: [id: String]
var coins := 0                   # монеты героя — валюта торговли (M8, ответ №40)
var start_residents := 1         # правки v1.12.0: герой начинает один, поселенцы приходят сами
var start_level := "normal"      # "low" | "normal" | "high"
var test_mode := false           # тест-режим: много ресурсов, рун и добычи
var conflicts_enabled := true    # ссоры и воровство жителей (ответ №29, галочка в меню)
var dungeon_clears := 0          # полных зачисток данжа (M5.1: с каждой сильнее)
var dungeon_lock_day := 0        # данж восстановится к этому дню города (M5.1)
var hero_kits := 0               # боевые комплекты героя из оружейки (M5.1)
# --- контекст локации карты мира (M8) ---
var return_scene := ""           # куда возвращать героя из данжа ("" — в город)
var forced_biome := ""           # биом данжа из точки интереса ("" — случайный)
var dungeon_scale := 1.0         # масштаб локации (руины/лагерь — меньше данжа)
var poi_id := 0                  # id точки интереса, из которой вошли (0 — город)
var poi_coins := 0               # монеты за зачистку лагеря/руин (M8)
var world_hero_tile := Vector2i(-1, -1)   # тайл героя на карте мира
var city_return_tile := Vector2i(-1, -1)  # тайл героя при возврате в город
var world_active := false        # игрок сейчас на карте мира («Продолжить» вернёт туда, M8)
# --- экипировка героя (M14-B, issue #3 B.1) ---------------------------------
var items_cfg: Dictionary = {}   # data/items.json — каталог предметов
var weapons_cfg: Dictionary = {} # data/weapons.json — паттерны атаки
var loot_cfg: Dictionary = {}    # data/loot.json — редкости (цвета/веса)
var equipment := {"weapon": "", "armor": "", "accessory": "", "mount": ""}
const EQUIP_SLOTS := ["weapon", "armor", "accessory", "mount"]
# --- сейв/загрузка (M14-A, issue #3) ----------------------------------------
var in_dungeon := false          # герой в данже — сейв недоступен (данжи транзитны)
var hero_saved_hp := -1          # HP героя из сейва (применится при спавне в городе)
var hero_saved_mana := -1        # мана из сейва (в городе всегда стартует с нуля)
var _autosave_day := 0           # последний день автосейва
# кодекс и статистика (M14-K): {enemies:{}, biomes:{}, spells:{}, items:{}, gods:{}, factions:{}}
var codex := {"enemies": {}, "biomes": {}, "spells": {}, "items": {}, "gods": {}, "factions": {}}
var stats := {"days": 0, "bosses": 0, "buildings": 0, "quests": 0, "hunts": 0}
# снимок героя на момент выхода в меню (Esc) — для «Сохранить игру» в меню
var menu_hero_tile := Vector2i(-1, -1)
var menu_hero_hp := -1
var menu_hero_mana := -1
const SAVE_SCRIPT := "res://scripts/save_game.gd"


func _init() -> void:
	# В _init (не _ready): тесты создают Game через new() вне дерева сцены.
	var data: Variant = _read_json(MAGIC_CFG_PATH)
	if data is Dictionary:
		magic = load(MAGIC_SCRIPT).new()
		magic.setup(data)
	else:
		push_error("Не читается data/magic.json")
	var sk: Variant = _read_json(SKILLS_CFG_PATH)
	if sk is Dictionary:
		skills = load(SKILLS_SCRIPT).new()
		skills.setup(sk)
	else:
		push_error("Не читается data/skills.json")
	for pair in [[ITEMS_CFG_PATH, "items_cfg"], [WEAPONS_CFG_PATH, "weapons_cfg"], [LOOT_CFG_PATH, "loot_cfg"]]:
		var data2: Variant = _read_json(String(pair[0]))
		if data2 is Dictionary:
			set(String(pair[1]), data2)
		else:
			push_error("Не читается %s" % String(pair[0]))


func _process(delta: float) -> void:
	if city_sim != null:
		city_sim.tick(delta)
	_autosave_tick()
	_update_fps(delta)


# --- FPS-счётчик (правки v1.21): маленькая метка в правом верхнем углу ------
# Живёт в автозагрузке — виден в любой сцене; обновляется 4 раза в секунду,
# чтобы сам счётчик не мешал кадру. Создаётся в _ready (внизу файла).
var _fps_label: Label = null
var _fps_accum := 0.0


func _update_fps(delta: float) -> void:
	if _fps_label == null:
		return
	_fps_accum += delta
	if _fps_accum < 0.25:
		return
	_fps_accum = 0.0
	var fps := Engine.get_frames_per_second()
	_fps_label.text = "%d FPS" % fps
	if fps >= 55:
		_fps_label.add_theme_color_override("font_color", Color("#7ddf64"))
	elif fps >= 30:
		_fps_label.add_theme_color_override("font_color", Color("#ffd54f"))
	else:
		_fps_label.add_theme_color_override("font_color", Color("#ff8a65"))


## Автосейв каждое утро города (M14-A): герой в городе (не в данже и не в пути
## по карте мира), начиная со 2-го дня. Тост «сохранено» — через события sim.
func _autosave_tick() -> void:
	if city_sim == null or in_dungeon or world_active:
		return
	var day := int(city_sim.day)
	if day <= 1 or day <= _autosave_day:
		return
	Game.stats["days"] = maxi(int(Game.stats.get("days", 0)), day)   # статистика (M14-K)
	_autosave_day = day
	var sg: Script = load(SAVE_SCRIPT)
	var err: String = sg.save_game(self, sg.city_hero_tile(self), -1, -1)
	if err == "":
		city_sim.events.append({"type": "autosaved"})


## Сохранить игру (обёртка для сцен). hero_tile — текущий тайл героя.
func save_game(hero_tile: Vector2i, hero_hp: int, hero_mana: int) -> String:
	var sg: Script = load(SAVE_SCRIPT)
	var err: String = sg.save_game(self, hero_tile, hero_hp, hero_mana)
	if err == "":
		_autosave_day = int(city_sim.day) if city_sim != null else _autosave_day
	return err


## Загрузить игру из файла в этот инстанс. "" — успех, иначе ключ локализации.
func load_game() -> String:
	var sg: Script = load(SAVE_SCRIPT)
	return sg.load_game(self)


## Сохранить из главного меню (фидбек заказчика 2026-10-20: Esc снова ведёт
## в меню, «Сохранить» теперь здесь). Состояние героя — снимок на момент Esc.
func menu_save() -> String:
	if city_sim == null:
		return "save.no_game"
	if in_dungeon:
		return "save.dungeon_hint"
	var tile := menu_hero_tile
	if tile.x < 0:
		tile = city_return_tile if city_return_tile.x >= 0 else city_sim.map.spawn_tile
	var err: String = save_game(tile, menu_hero_hp, menu_hero_mana)
	if err == "":
		menu_hero_tile = tile   # повторное сохранение в меню — тот же тайл
	return err


func has_save() -> bool:
	var sg: Script = load(SAVE_SCRIPT)
	return sg.has_save()


## Кодекс (M14-K): уникальная запись «увидел/открыл». cat: enemies|biomes|
## spells|items|gods|factions.
func codex_seen(cat: String, id: String) -> void:
	if id == "":
		return
	var cat_dict: Dictionary = codex.get(cat, {})
	if not cat_dict.has(id):
		cat_dict[id] = true
		codex[cat] = cat_dict


func codex_count(cat: String) -> int:
	return (codex.get(cat, {}) as Dictionary).size()


## Статистика (M14-K): дни, боссы, постройки, заказы, охота.
func stat(key: String, delta: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + delta


## --- Платформенные мелочи (M9): полноэкранный режим с запоминанием ---------

const SETTINGS_PATH := "user://settings.cfg"
var fullscreen := false


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		fullscreen = bool(cf.get_value("video", "fullscreen", false))
	if fullscreen:
		_apply_window_mode()
	_setup_fps_counter()   # метка FPS в правом верхнем углу (v1.21)


## Слой с FPS-меткой: поверх всего, мышь не перехватывает.
func _setup_fps_counter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.offset_left = -110.0
	_fps_label.offset_right = -8.0
	_fps_label.offset_top = 6.0
	_fps_label.offset_bottom = 30.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 0.85))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_fps_label.add_theme_constant_override("outline_size", 3)
	root.add_child(_fps_label)


func set_fullscreen(on: bool) -> void:
	if fullscreen == on:
		return
	fullscreen = on
	_apply_window_mode()
	var cf := ConfigFile.new()
	cf.set_value("video", "fullscreen", fullscreen)
	cf.save(SETTINGS_PATH)


func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)


func _apply_window_mode() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)


func _input(event: InputEvent) -> void:
	# F11 — полноэкранный режим из любой сцены
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F11:
		toggle_fullscreen()


## Создать город с настройками старта (новая игра). Рюкзак и спеллбук очищаются.
## Новая игра — новый мир (M8): карта мира генерируется заново.
func new_city() -> void:
	inventory = []
	spellbook = []
	last_run_death = false
	dungeon_clears = 0
	dungeon_lock_day = 0
	hero_kits = 0
	return_scene = ""
	forced_biome = ""
	dungeon_scale = 1.0
	poi_id = 0
	poi_coins = 0
	world_hero_tile = Vector2i(-1, -1)
	city_return_tile = Vector2i(-1, -1)
	world_active = false
	menu_hero_tile = Vector2i(-1, -1)
	menu_hero_hp = -1
	menu_hero_mana = -1
	equipment = {"weapon": "", "armor": "", "accessory": "", "mount": ""}
	in_dungeon = false
	hero_saved_hp = -1
	hero_saved_mana = -1
	_autosave_day = 1   # автосейв — с утра 2-го дня
	codex = {"enemies": {}, "biomes": {}, "spells": {}, "items": {}, "gods": {}, "factions": {}}
	stats = {"days": 0, "bosses": 0, "buildings": 0, "quests": 0, "hunts": 0}
	if skills != null:
		skills.reset()
	new_world()
	var cfg: Variant = _read_json(CITY_CFG_PATH)
	if not (cfg is Dictionary):
		push_error("Не читается data/city.json")
		return
	var map_script: Script = load(CITY_MAP_SCRIPT)
	var sim_script: Script = load(CITY_SIM_SCRIPT)
	var city_map = map_script.new()
	city_map.generate(randi(), cfg)
	city_sim = sim_script.new()
	city_sim.setup(city_map, cfg, start_residents, start_level)
	city_sim.conflicts = conflicts_enabled
	if test_mode:
		_apply_test_mode(cfg)


## Создать мир: карта мира по сиду + программная жизнь (M8).
func new_world() -> void:
	var cfg: Variant = _read_json(WORLD_CFG_PATH)
	if not (cfg is Dictionary):
		push_error("Не читается data/world.json")
		return
	var map_script: Script = load(WORLD_MAP_SCRIPT)
	world_map = map_script.new()
	world_map.generate(randi(), cfg)
	var sim_script: Script = load(WORLD_SIM_SCRIPT)
	world_sim = sim_script.new()
	world_sim.setup(world_map, cfg)
	coins = int(cfg.get("trade", {}).get("start_coins", 15))


## Тест-режим: стартовые ресурсы и руны из city.json -> "test_mode".
func _apply_test_mode(cfg: Dictionary) -> void:
	var test_cfg: Dictionary = cfg.get("test_mode", {})
	if test_cfg.is_empty():
		return
	var start_res: Dictionary = test_cfg.get("resources", {})
	for key in start_res:
		if city_sim.res.has(key):
			city_sim.res[key] = float(int(start_res[key]))
	var runes_each := int(test_cfg.get("runes_each", 0))
	if runes_each > 0 and magic != null:
		var rune_ids := {}
		for r in magic.cfg.get("recipes", []):
			rune_ids[String(r["a"])] = true
			rune_ids[String(r["b"])] = true
		for rune_id in rune_ids:
			add_item(rune_id, runes_each)


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func count_item(id: String) -> int:
	for stack in inventory:
		if stack["id"] == id:
			return int(stack["count"])
	return 0


## Убрать n единиц предмета; пустые стакы удаляются. Возвращает сколько убрано.
func remove_item(id: String, count: int) -> int:
	var left := count
	var i := 0
	while i < inventory.size() and left > 0:
		var stack: Dictionary = inventory[i]
		if String(stack["id"]) == id:
			var take := mini(left, int(stack["count"]))
			stack["count"] = int(stack["count"]) - take
			left -= take
			if int(stack["count"]) <= 0:
				inventory.remove_at(i)
				continue
		i += 1
	return count - left


## Заклинание изучено?
func has_spell(spell_id: String) -> bool:
	return spellbook.has(spell_id)


## Изучить заклинание (без дублей).
func learn_spell(spell_id: String) -> void:
	if not spellbook.has(spell_id):
		spellbook.append(spell_id)
		codex_seen("spells", spell_id)   # кодекс (M14-K)


## Добавляет предмет в рюкзак, при совпадении складывается в стак.
func add_item(id: String, count: int = 1) -> void:
	for stack in inventory:
		if stack["id"] == id:
			stack["count"] = int(stack["count"]) + count
			return
	inventory.append({"id": id, "count": count})
	if id.begins_with("rune_"):
		codex_seen("items", id)   # руны в кодекс (M14-K)


## Всего единиц добычи в рюкзаке.
func loot_total() -> int:
	var total := 0
	for stack in inventory:
		total += int(stack["count"])
	return total


## Гибель в данже: каждый стак теряет половину с округлением вверх.
## Возвращает число потерянных единиц.
func lose_half_loot() -> int:
	var lost_total := 0
	for stack in inventory:
		var lost := ceili(int(stack["count"]) / 2.0)
		stack["count"] = int(stack["count"]) - lost
		lost_total += lost
	inventory = inventory.filter(func(stack: Dictionary) -> bool: return int(stack["count"]) > 0)
	return lost_total


## --- данж: зачистки и восстановление (M5.1) -------------------------------

## Данж доступен в этот день города?
func dungeon_available(day: int) -> bool:
	return day >= dungeon_lock_day


## Данж полностью зачищен: восстанавливается lock_days дней, следующая версия сильнее.
func register_dungeon_clear(day: int, lock_days: int) -> void:
	dungeon_clears += 1
	dungeon_lock_day = day + lock_days


## --- комплекты героя (M5.1) ------------------------------------------------

## Надеть комплект из оружейки: +урон и +броня герою. true — надет.
func buy_hero_kit(city_cfg: Dictionary, sim) -> String:
	var kcfg: Dictionary = city_cfg.get("hero_kit", {})
	if int(kcfg.get("max", 3)) > 0 and hero_kits >= int(kcfg.get("max", 3)):
		return "armory_max"
	if sim == null or float(sim.res.get("metal", 0.0)) < float(kcfg.get("cost_metal", 3)):
		return "no_metal"
	sim.res["metal"] = float(sim.res["metal"]) - float(kcfg.get("cost_metal", 3))
	hero_kits += 1
	return ""


## Бонусы героя от комплектов: {damage, armor}.
func hero_kit_bonus(city_cfg: Dictionary) -> Dictionary:
	var kcfg: Dictionary = city_cfg.get("hero_kit", {})
	return {
		"damage": hero_kits * int(kcfg.get("damage", 2)),
		"armor": hero_kits * int(kcfg.get("armor", 1)),
	}


## --- экипировка, свитки и зелья (M14-B, issue #3 B.1–B.3) ------------------

## Определение предмета из data/items.json ({} — неизвестен).
func item_def(item_id: String) -> Dictionary:
	for item in items_cfg.get("items", []):
		if String(item["id"]) == item_id:
			return item
	return {}


## Паттерн оружия из data/weapons.json ({} — неизвестен).
func weapon_def(weapon_id: String) -> Dictionary:
	for w in weapons_cfg.get("weapons", []):
		if String(w["id"]) == weapon_id:
			return w
	return {}


## Цвет редкости из data/loot.json (белый — неизвестная).
func rarity_color(rarity_id: String) -> Color:
	for r in loot_cfg.get("rarities", []):
		if String(r["id"]) == rarity_id:
			return Color(String(r["color"]))
	return Color.WHITE


## Параметры атаки с надетым оружием ({} — без оружия, герой бьёт как мечом
## по параметрам dungeon.json -> hero). Урон предмета = паттерн × damage_mult.
func weapon_params() -> Dictionary:
	var item: Dictionary = item_def(String(equipment.get("weapon", "")))
	if item.is_empty():
		return {}
	var w: Dictionary = weapon_def(String(item.get("weapon", "")))
	if w.is_empty():
		return {}
	var mult := float(item.get("damage_mult", 1.0))
	return {
		"id": String(w["id"]),
		"pattern": String(w.get("pattern", "arc")),
		"damage": int(round(float(w.get("damage", 2)) * mult)),
		"attack_cooldown": float(w.get("attack_cooldown", 0.4)),
		"range": float(w.get("range", 30)),
		"arc": float(w.get("arc", 90)),
		"projectile_speed": float(w.get("projectile_speed", 0.0)),
		"mana_cost": int(w.get("mana_cost", 0)),
	}


## Суммарные бонусы надетых брони и аксессуара: {armor, hp, mana, ...}.
func equipment_bonuses() -> Dictionary:
	var out := {}
	for slot in ["armor", "accessory"]:
		var item: Dictionary = item_def(String(equipment.get(slot, "")))
		var bonuses: Dictionary = item.get("bonuses", {})
		for key in bonuses:
			out[key] = float(out.get(key, 0.0)) + float(bonuses[key])
	return out


## Надеть предмет из рюкзака (предыдущий из слота возвращается в рюкзак).
## "" — успех, иначе ключ локализации ошибки.
func equip_item(item_id: String) -> String:
	var item: Dictionary = item_def(item_id)
	if item.is_empty():
		return "eq.bad_item"
	var kind := String(item["kind"])
	if kind not in EQUIP_SLOTS:
		return "eq.not_equippable"
	if count_item(item_id) < 1:
		return "eq.not_owned"
	var prev := String(equipment.get(kind, ""))
	remove_item(item_id, 1)
	if prev != "":
		add_item(prev, 1)
	equipment[kind] = item_id
	return ""


## Снять предмет со слота в рюкзак. "" — успех.
func unequip_slot(slot: String) -> String:
	if slot not in EQUIP_SLOTS:
		return "eq.bad_item"
	var cur := String(equipment.get(slot, ""))
	if cur == "":
		return "eq.empty_slot"
	equipment[slot] = ""
	add_item(cur, 1)
	return ""


## Выпить зелье (герой передаётся сценой — эффекты идут в живой объект).
## "" — успех, иначе ключ локализации ошибки.
func use_potion(item_id: String, hero) -> String:
	var item: Dictionary = item_def(item_id)
	if item.is_empty() or String(item["kind"]) != "potion":
		return "eq.not_usable"
	if count_item(item_id) < 1:
		return "eq.not_owned"
	if hero == null:
		return "eq.only_dungeon"
	var fx: Dictionary = item.get("use", {})
	match String(fx.get("effect", "")):
		"heal":
			hero.heal(int(fx.get("amount", 8)))
		"mana":
			hero.add_mana(int(fx.get("amount", 5)))
		"temp_damage":
			hero.temp_damage_bonus(float(fx.get("duration", 10.0)), int(fx.get("amount", 2)))
		"temp_armor":
			hero.temp_armor_bonus(float(fx.get("duration", 10.0)), int(fx.get("amount", 2)))
		_:
			return "eq.not_usable"
	remove_item(item_id, 1)
	return ""


## Скрафтить предмет (T05: второй источник — мастерские города). Симуляция
## города даёт пул ресурсов; near_armory/near_workshop — герой у здания.
## "" — успех, иначе ключ локализации ошибки.
func craft_item(item_id: String, sim, near_armory: bool, near_workshop: bool) -> String:
	var item: Dictionary = item_def(item_id)
	var craft: Dictionary = item.get("craft", {})
	if craft.is_empty():
		return "eq.not_craftable"
	var where := String(craft.get("where", "armory"))
	if where == "armory" and not near_armory:
		return "eq.need_armory"
	if where == "workshop" and not near_workshop:
		return "eq.need_workshop"
	if sim == null:
		return "eq.need_armory"
	var cost: Dictionary = craft.get("cost", {})
	if not sim.can_afford(cost):
		return "eq.no_resources"
	for key in cost:
		sim.res[key] = float(sim.res.get(key, 0.0)) - float(cost[key])
	add_item(item_id, 1)
	return ""
