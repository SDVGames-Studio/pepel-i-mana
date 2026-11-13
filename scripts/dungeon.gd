# Часть: сцена данжа — шипы, эффекты, туман войны, пути, интеракции (руны/сундуки/
# ловушки), выпадение лута, смерти, зачистка и выход.
# Корень extends-цепочки: сцена scenes/dungeon.tscn ссылается на этот файл.
extends "res://scripts/dungeon_build.gd"

## Тик зон шипов: урон по времени всем врагам внутри.
func _update_zones() -> void:
	var i := 0
	while i < _zones.size():
		var zone: Dictionary = _zones[i]
		if _zone_time >= float(zone["until"]):
			_zones.remove_at(i)
			continue
		zone["acc"] = float(zone["acc"]) + get_process_delta_time()
		while float(zone["acc"]) >= 1.0:
			zone["acc"] = float(zone["acc"]) - 1.0
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy.global_position.distance_to(zone["pos"]) <= float(zone["radius"]) + float(enemy.p["radius"]):
					enemy.take_damage(int(zone["dps"]), "nature")
		i += 1


func _add_fx(kind: String, col: Color, radius: float, duration: float,
		pos: Vector2, points: PackedVector2Array = PackedVector2Array()) -> void:
	var fx = SpellFxScript.new()
	fx.setup(kind, col, radius, duration, points)
	fx.position = pos
	add_child(fx)



func _update_fog() -> void:
	var t := _pos_to_tile(hero.position)
	var r := int(params["hero"]["vision_tiles"])
	var changed := false
	# v1.33: поле зрения СЕЙЧАС (для тумана войны — живой обзор против
	# «памяти»): полы в радиусе с прямой видимостью
	var vis: Dictionary = {}
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var p := Vector2i(t.x + dx, t.y + dy)
			if gen.is_floor(p) and _line_of_sight(t, p):
				vis[p] = true
				if not _visited.has(p):
					_visited[p] = true
					changed = true
	if changed or not _same_keys(vis, _visible_now):
		_visible_now = vis
		if _fog != null:
			_fog.visited = _visited
			_fog.visible_now = vis
			_fog.hero_pos = hero.position   # центр мягкого круга (v1.33.2)
			_fog.queue_redraw()
	if changed:
		hud.minimap.update_state(t, _visited)


func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
	return true


## v1.46: прямая видимость между точками (для ИИ врагов: свет и погоня).
func line_of_sight_px(from_px: Vector2, to_px: Vector2) -> bool:
	return _line_of_sight(_pos_to_tile(from_px), _pos_to_tile(to_px))


## A*-путь для врага по коридорам данжа (герой за стеной — обход).
func enemy_path(from_px: Vector2, to_px: Vector2) -> PackedVector2Array:
	if _dungeon_astar == null:
		return PackedVector2Array()
	var from_t := _pos_to_tile(from_px)
	var to_t := _pos_to_tile(to_px)
	if not _dungeon_astar.is_point_solid(from_t) \
			and not _dungeon_astar.is_point_solid(to_t):
		var pts: Array = _dungeon_astar.get_id_path(from_t, to_t)
		var out := PackedVector2Array()
		for t in pts:
			out.append(_tile_to_pos(t))
		return out
	return PackedVector2Array()


var _dungeon_astar = null   # ленивый A* данжа (v1.46)


func _ensure_dungeon_astar() -> void:
	if _dungeon_astar != null:
		return
	var g = load("res://scripts/map_astar.gd").new()
	var solids := {}
	for y in gen.h:
		for x in gen.w:
			if gen.grid[y][x] == DungeonGenScript.TILE_WALL:
				solids[Vector2i(x, y)] = true
	g.setup(gen.w, gen.h, float(ts), {}, {})
	g.rebuild(solids)
	_dungeon_astar = g


## Зрение героя: тайл виден, только если линия от героя не упирается в стену —
## карта не должна рисоваться там, где герой не был и не мог видеть (заказчик).
func _line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	return los_clear_grid(gen.grid, from, to, DungeonGenScript.TILE_WALL)


## Чистая математика LOS (для тестов v1.33): grid — массив строк тайлов,
## стеной считается tile == wall. Промежуточные клетки линии (без концов)
## не должны быть стеной.
static func los_clear_grid(grid: Array, from: Vector2i, to: Vector2i, wall: int) -> bool:
	var dx := to.x - from.x
	var dy := to.y - from.y
	var steps := maxi(absi(dx), absi(dy))
	if steps <= 1:
		return true
	var x := float(from.x)
	var y := float(from.y)
	for i in steps - 1:
		x += float(dx) / float(steps)
		y += float(dy) / float(steps)
		var t := Vector2i(int(round(x)), int(round(y)))
		if t.y < 0 or t.y >= grid.size() or t.x < 0 or t.x >= (grid[0] as Array).size():
			return false
		if grid[t.y][t.x] == wall:
			return false
	return true


## Мана-голод (упрощённо): мана утекает по таймеру, на нуле — здоровье.
func _update_mana_hunger(delta: float) -> void:
	_mana_acc += delta
	if _mana_acc < float(params["mana_drain_period"]):
		return
	_mana_acc = 0.0
	if not hero.drain_mana():
		hero.take_damage(1)


func _update_hint() -> void:
	if _near_ladder():
		hud.set_hint(Loc.t("dungeon.hint_exit"))
		return
	var rune = _nearest_rune()
	if rune != null:
		hud.set_hint(Loc.t("dungeon.hint_rune"))
		return
	var trap = _nearest_trap(float(ts) * 1.3)
	if trap != null:
		hud.set_hint(Loc.t("dungeon.hint_trap"))
		return
	var chest = _nearest_chest(float(ts) * 1.8)
	if chest != null:
		hud.set_hint(Loc.t("dungeon.hint_chest"))
		return
	hud.set_hint(Loc.t("dungeon.hint_spells"))


## Ближайший неактивированный рунный круг в радиусе взаимодействия.
func _nearest_rune():
	var best = null
	var best_d := float(ts) * 1.6
	for r in get_tree().get_nodes_in_group("dungeon_runes"):
		if r.used:
			continue
		var d: float = r.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = r
	return best


func _near_ladder() -> bool:
	var ladder := get_node_or_null("ExitLadder")
	if ladder == null:
		return false
	return hero.position.distance_to(ladder.position) < float(ts) * 1.6


func _nearest_chest(radius: float):
	var best = null
	var best_d := radius
	for chest in get_tree().get_nodes_in_group("chests"):
		if chest.open:
			continue
		var d: float = chest.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = chest
	return best


func _try_interact() -> void:
	if _near_ladder():
		_leave_dungeon()
		return
	var rune = _nearest_rune()
	if rune != null:
		_activate_rune(rune)
		return
	var trap = _nearest_trap(float(ts) * 1.3)
	if trap != null:
		trap.disarm()
		hud.toast(Loc.t("dungeon.trap_disarmed"))
		return
	var chest = _nearest_chest(float(ts) * 1.8)
	if chest != null:
		_open_chest(chest)


## Активация рунного круга: мана + боевой запал, вспышка и тост (одноразово).
func _activate_rune(rune) -> void:
	var res: Dictionary = rune.activate(hero, params.get("v2", {}).get("rune", {}))
	if res.is_empty():
		return
	SfxLib.play("rune")   # v1.65
	var col: Color = rune.color
	_add_fx("ring", col, 40.0, 0.8, rune.global_position)
	if int(res.get("mana", 0)) > 0:
		hud.toast(Loc.t("dungeon.rune_mana") % int(res["mana"]))
	if int(res.get("buff", 0)) > 0:
		hud.toast(Loc.t("dungeon.rune_buff") % [int(res["buff"]), int(res["seconds"])])


## Ближайшая заряженная ловушка в радиусе (issue #2): разминированные пропускаем.
func _nearest_trap(radius: float):
	var best = null
	var best_d := radius
	for t in get_tree().get_nodes_in_group("traps"):
		if t.disarmed:
			continue
		var d: float = t.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func _open_chest(chest: Node) -> void:
	SfxLib.play("chest")   # v1.65
	chest.open = true
	chest.queue_redraw()
	var test_cfg: Dictionary = params.get("test_mode", {})
	var min_i := int(loot_data["chest_items_min"])
	var max_i := int(loot_data["chest_items_max"])
	if Game.test_mode and not test_cfg.is_empty():
		min_i = int(test_cfg.get("chest_items_min", min_i))
		max_i = int(test_cfg.get("chest_items_max", max_i))
	var count := _loot_rng.randi_range(min_i, max_i) + int(biome.get("loot_bonus", 0))
	for i in count:
		var item := _roll_item()
		Game.add_item(String(item["id"]))
		hud.toast(Loc.t("dungeon.got_item") % Loc.t(String(item["loc"])))
	# экипировка (M14-B/T04): шанс растёт с жирностью биома (loot_bonus = ярус-1)
	var drop_id := _roll_equipment(int(biome.get("loot_bonus", 0)) + 1)
	if drop_id != "":
		Game.add_item(drop_id)
		hud.toast(Loc.t("dungeon.got_item") % Loc.t(String(Game.item_def(drop_id)["loc"])))
	# тест-режим: гарантированная руна из сундука — для проверки крафта
	if Game.test_mode and int(test_cfg.get("rune_per_chest", 0)) > 0:
		for i in int(test_cfg["rune_per_chest"]):
			var rune_id := _random_rune_id()
			Game.add_item(rune_id)
			var rune_item := _item_by_id(rune_id)
			if not rune_item.is_empty():
				hud.toast(Loc.t("dungeon.got_item") % Loc.t(String(rune_item["loc"])))


## Случайная руна из рецептов (все 8 участвуют).
func _random_rune_id() -> String:
	var runes := {}
	for r in Game.magic.cfg.get("recipes", []):
		runes[String(r["a"])] = true
		runes[String(r["b"])] = true
	var keys: Array = runes.keys()
	return String(keys[_loot_rng.randi_range(0, keys.size() - 1)])


## Ролл предмета: сначала редкость по весам, затем случайный предмет этой редкости.
func _roll_item() -> Dictionary:
	var total := 0
	for rarity in loot_data["rarities"]:
		total += int(rarity["weight"])
	var roll := _loot_rng.randi_range(1, total)
	var chosen := ""
	for rarity in loot_data["rarities"]:
		roll -= int(rarity["weight"])
		if roll <= 0:
			chosen = String(rarity["id"])
			break
	var pool: Array = []
	for item in loot_data["items"]:
		if String(item["rarity"]) == chosen:
			pool.append(item)
	if pool.is_empty():
		return loot_data["items"][0]
	return pool[_loot_rng.randi_range(0, pool.size() - 1)]


## Ролл экипировки (M14-B/T04): вернуть id или "" (не выпал). tier — уровень
## локации (1..3): доступны предметы с tier не выше. Вес — редкости loot.json.
func _roll_equipment(tier: int) -> String:
	var drops: Dictionary = Game.items_cfg.get("drops", {})
	var chance := float(drops.get("chest_chance", 0.3)) \
			+ float(tier - 1) * float(drops.get("bonus_per_tier", 0.06))
	if _loot_rng.randf() >= chance:
		return ""
	var pool: Array = []
	for item in Game.items_cfg.get("items", []):
		if String(item.get("kind", "")) in ["weapon", "armor", "accessory"] \
				and int(item.get("tier", 1)) <= tier:
			pool.append(item)
	if pool.is_empty():
		return ""
	var total := 0
	for item: Dictionary in pool:
		total += _rarity_weight(String(item["rarity"]))
	var roll := _loot_rng.randi_range(1, maxi(1, total))
	for item: Dictionary in pool:
		roll -= _rarity_weight(String(item["rarity"]))
		if roll <= 0:
			return String(item["id"])
	return String(pool[0]["id"])


func _rarity_weight(rarity_id: String) -> int:
	for rarity in loot_data.get("rarities", []):
		if String(rarity["id"]) == rarity_id:
			return int(rarity["weight"])
	return 1


func _on_pickup_collected(pickup) -> void:
	SfxLib.play("pickup")   # v1.65
	if pickup.kind == "mana":
		hero.add_mana(int(params["crystal_mana"]))
		hud.toast(Loc.t("dungeon.got_mana") % int(params["crystal_mana"]))
	else:
		Game.add_item(String(pickup.item_id))
		var item := _item_by_id(String(pickup.item_id))
		hud.toast(Loc.t("dungeon.got_item") % Loc.t(String(item["loc"])))


func _on_enemy_died(enemy) -> void:
	var drop_chance := float(loot_data["enemy_drop_chance"])
	var test_cfg: Dictionary = params.get("test_mode", {})
	if Game.test_mode and not test_cfg.is_empty():
		drop_chance = float(test_cfg.get("enemy_drop_chance", drop_chance))
	if _loot_rng.randf() < drop_chance:
		_spawn_pickup("item", String(_roll_item()["id"]), enemy.position)
	if _loot_rng.randf() < float(enemy.p["mana_chance"]):
		_spawn_pickup("mana", "", enemy.position + Vector2(12, 6))
	# XP за врага -> уровни героя -> выбор навыка (M7)
	if Game.skills != null and int(enemy.p.get("xp", 0)) > 0:
		var ups: int = Game.skills.add_xp(int(enemy.p["xp"]))
		if ups > 0:
			hud.toast(Loc.t("hud.level_up") % Game.skills.level)
			hud.open_skill_choice()
	# победы качают стату героя (v1.24): бой — сила и ловкость
	var ha: Dictionary = hero.attrs_cfg() if hero != null else {}
	if not ha.is_empty():
		Game.hero_train("str", float(ha.get("train_kill_str", 0.25)))
		Game.hero_train("agi", float(ha.get("train_kill_agi", 0.15)))
	_apply_clear_light()
	_check_dungeon_cleared()


## Босс повержен (M7): гарантированный жирный лут — трофей, кристалл эха, руна.
## M14-B: плюс гарантированный предмет экипировки по ярусу биома (T04).
func _on_boss_died(enemy) -> void:
	Game.stat("bosses")   # статистика (M14-K)
	for item_id: String in loot_data.get("boss_guaranteed", []):
		_spawn_pickup("item", item_id, enemy.position + Vector2(_loot_rng.randf_range(-14, 14), _loot_rng.randf_range(-10, 10)))
	_spawn_pickup("item", _random_rune_id(), enemy.position + Vector2(0, 16))
	# башня лича (M14-D): гарантированная вторая руна босса
	if _biome_id() == "lich_tower":
		_spawn_pickup("item", _random_rune_id(), enemy.position + Vector2(0, 32))
	var boss_drop := _roll_equipment_boss(int(biome.get("loot_bonus", 0)) + 1)
	if boss_drop != "":
		_spawn_pickup("item", boss_drop, enemy.position + Vector2(0, -18))
	hud.toast(Loc.t("dungeon.boss_down"))


## Гарантированный предмет экипировки с босса (мимо шанса сундука).
func _roll_equipment_boss(tier: int) -> String:
	var count := int(Game.items_cfg.get("drops", {}).get("boss_guaranteed", 1))
	if count <= 0:
		return ""
	var pool: Array = []
	for item in Game.items_cfg.get("items", []):
		if String(item.get("kind", "")) in ["weapon", "armor", "accessory"] \
				and int(item.get("tier", 1)) <= tier:
			pool.append(item)
	if pool.is_empty():
		return ""
	return String(pool[_loot_rng.randi_range(0, pool.size() - 1)]["id"])


## Все враги мертвы — данж зачищен: 20 дней не работает (перезарядка данжа
## у города, 2026-10-21), следующая версия сильнее, атаки мутантов на город
## сдвигаются на время перезарядки.
func _check_dungeon_cleared() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and int(e["hp"]) > 0:
			return
	var growth: Dictionary = params.get("clear_growth", {})
	var day := 0
	if Game.city_sim != null:
		day = int(Game.city_sim.day)
	Game.register_dungeon_clear(day, int(growth.get("lock_days", 20)))
	hud.toast(Loc.t("dungeon.cleared_toast") % int(growth.get("lock_days", 20)))
	# зачищен именно данж у города (не точка карты мира): атаки сдвигаются
	if Game.poi_id == 0 and Game.city_sim != null \
			and Game.city_sim.has_method("delay_raids_after_dungeon_clear"):
		Game.city_sim.delay_raids_after_dungeon_clear()
	# v1.56/1.57: УНИКАЛЬНЫЕ ЛОГОВА — богатства в пул города
	if Game.forced_biome == "dragon_lair" and Game.city_sim != null:
		var dragon_loot := {"dragon_bone": 2, "dragon_hide": 2, "gold": 30}
		for key in dragon_loot:
			Game.city_sim._add_resource_capped(String(key), float(dragon_loot[key]))
		hud.toast(Loc.t("event.dragon_loot"))
		Game.city_sim.chronicle_add("chron.dragon_lair")
	if Game.forced_biome == "lich_tower" and Game.city_sim != null:
		Game.city_sim._add_resource_capped("lich_crystal", 1.0)
		hud.toast(Loc.t("event.lich_loot"))
		Game.city_sim.chronicle_add("chron.lich_lair")
	if Game.forced_biome == "vampire_keep" and Game.city_sim != null:
		Game.city_sim._add_resource_capped("vampire_blood", 1.0)
		hud.toast(Loc.t("event.vampire_loot"))
		Game.city_sim.chronicle_add("chron.vampire_lair")
	# карта мира (M8): монеты за лагерь/руины и отметка точки интереса
	if Game.poi_coins > 0:
		Game.coins += Game.poi_coins
		hud.toast(Loc.t("world.coins_got") % Game.poi_coins)
		Game.poi_coins = 0
	if Game.world_sim != null and Game.poi_id > 0:
		for ev: Dictionary in Game.world_sim.mark_cleared(Game.poi_id):
			hud.toast(Loc.t("world." + String(ev["type"])))
		Game.poi_id = 0


## Смерть героя: потеря половины лута и выброс, игра продолжается.
## Из локации карты мира возвращаемся на карту мира (M8).
func _on_hero_died() -> void:
	Game.last_run_death = true
	Game.lose_half_loot()
	_clear_location_context()
	get_tree().change_scene_to_file(_return_scene())


func _leave_dungeon() -> void:
	Game.last_run_death = false
	_clear_location_context()
	get_tree().change_scene_to_file(_return_scene())


## Куда возвращать героя: из локации карты мира — на карту мира, иначе в город.
func _return_scene() -> String:
	return Game.return_scene if Game.return_scene != "" else "res://scenes/city.tscn"


## Контекст локации карты мира одноразовый — гасим при любом выходе.
func _clear_location_context() -> void:
	Game.return_scene = ""
	Game.forced_biome = ""
	Game.dungeon_scale = 1.0


func _item_by_id(item_id: String) -> Dictionary:
	for item in loot_data.get("items", []):
		if item["id"] == item_id:
			return item
	return {}


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
