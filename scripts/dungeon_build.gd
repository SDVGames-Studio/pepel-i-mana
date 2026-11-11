# Часть: сцена данжа — постройка уровня (стены/выход/сундуки/герой/враги/фауна/
# ловушки/босс), лут и заклинания героя. Один класс, поведение не меняется.
extends "res://scripts/dungeon_base.gd"

func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var tile_poly := OccluderPolygon2D.new()
	var hh := float(ts) / 2.0
	tile_poly.polygon = PackedVector2Array([
		Vector2(-hh, -hh), Vector2(hh, -hh), Vector2(hh, hh), Vector2(-hh, hh),
	])
	for y in gen.h:
		var x := 0
		while x < gen.w:
			if gen.grid[y][x] != DungeonGenScript.TILE_WALL:
				x += 1
				continue
			var x0 := x
			while x < gen.w and gen.grid[y][x] == DungeonGenScript.TILE_WALL:
				x += 1
			var seg_w := (x - x0) * float(ts)
			var center := Vector2((x0 + (x - x0) / 2.0) * float(ts), (y + 0.5) * float(ts))
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(seg_w, float(ts))
			shape.shape = rect
			shape.position = center
			body.add_child(shape)
			for tx in range(x0, x):
				var occ := LightOccluder2D.new()
				occ.occluder = tile_poly
				occ.position = Vector2((tx + 0.5) * float(ts), (y + 0.5) * float(ts))
				body.add_child(occ)


func _build_exit() -> void:
	var marker = ExitMarkerScript.new()
	marker.marker_color = Color(String(biome["exit_color"]))
	# на тайл в стороне от точки спавна, но всегда внутри стартовой комнаты
	marker.position = _tile_to_pos(gen.start_tile) + Vector2(float(ts), 0)
	marker.name = "ExitLadder"
	add_child(marker)


func _build_chests() -> void:
	for tile: Vector2i in gen.chest_spawns:
		var chest = ChestScript.new()
		chest.position = _tile_to_pos(tile)
		chest.add_to_group("chests")
		add_child(chest)


func _build_crystals() -> void:
	for tile: Vector2i in gen.crystal_spawns:
		_spawn_pickup("mana", "", _tile_to_pos(tile))


func _build_hero() -> void:
	hero = HeroScript.new()
	var hero_params: Dictionary = params["hero"]
	hero.setup(hero_params, int(hero_params["mana"]))
	# постоянные бонусы дерева навыков (M7) — до маны, она учитывает навык
	if Game.skills != null:
		hero.apply_skill_bonuses(Game.skills.bonuses())
	_apply_mana_params()
	# боевые комплекты героя из оружейки: +урон, +броня (M5.1)
	var kit: Dictionary = Game.hero_kit_bonus(_read_json(CITY_CFG_PATH))
	hero.bonus_damage = int(kit["damage"])
	hero.bonus_armor = int(kit["armor"])
	# благословение «Пепла» (M14-H): герой сильнее, пока божество избрано
	if Game.city_sim != null and Game.city_sim.god == "ash":
		hero.bonus_damage += int(Game.city_sim.god_def().get("value", 0))
	hero.position = _tile_to_pos(gen.start_tile)
	hero.died.connect(_on_hero_died)
	add_child(hero)
	# герой слою света — гасить дальние источники (FPS, v1.42.3)
	if _lights != null:
		_lights.hero = hero
	# экипировка (M14-B): бонусы брони/аксессуара и мана-кап до фонаря
	_apply_equipment()
	hero.projectile_solid_check = _solid_at
	hero.set_camera_limits(Rect2(0, 0, gen.w * float(ts), gen.h * float(ts)))
	# радиус фонаря — отдельный параметр (меньше радиуса обзора-памяти миникарты)
	hero.make_light(float(params["hero"]["light_radius_tiles"]) * float(ts))


## Применить надетую экипировку к живому герою (спавн и любое изменение в панели).
func _apply_equipment() -> void:
	if hero == null:
		return
	hero.set_equipment_bonuses(Game.equipment_bonuses())
	_apply_mana_params()
	hero.mana = mini(hero.mana, hero.mana_cap())


## Стена ли тайл под точкой — снаряды гаснут об стены данжа.
func _solid_at(pos: Vector2) -> bool:
	return gen.tile_at(_pos_to_tile(pos)) == DungeonGenScript.TILE_WALL


## Мана героя (ответы №56 и №65): запас и регенерация; зачарованный алтарь
## в городе увеличивает запас, дисциплина «Тайное» ускоряет регенерацию (M7).
## v1.24: мудрость героя расширяет запас поверх этого (hero.mana_cap()).
func _apply_mana_params() -> void:
	var mp: Dictionary = {"cap_extra": 0, "regen_period": 8.0}
	if Game.city_sim != null:
		mp = Game.city_sim.hero_mana_params()
	hero.mana_max = int(params["hero"]["mana"]) + int(mp.get("cap_extra", 0)) + hero.skill_bonus("mana")
	hero.mana = mini(hero.mana, hero.mana_cap())
	hero.mana_regen_period = float(mp.get("regen_period", 8.0))


## Враги данжа: с каждой полной зачисткой сильнее (M5.1).
func _scaled_enemy(data: Dictionary) -> Dictionary:
	var growth: Dictionary = params.get("clear_growth", {})
	var n := int(Game.dungeon_clears)
	var out := data.duplicate()
	var eruption := 1.0
	# v1.45: выбросы эпицентра усиливают аномалии (данжи) — враги крепнут
	if Game.world_map != null and "epicenter" in Game.world_map:
		eruption = 1.0 + 0.15 * float(Game.world_map.epicenter.get("power", 0))
	out["hp"] = int(round(float(data["hp"]) * (1.0 + float(growth.get("hp_per_clear", 0.3)) * n) * eruption))
	out["damage"] = int(data["damage"]) + n * int(growth.get("damage_per_clear", 1)) 			+ int(round(eruption)) - 1
	return out


func _build_enemies() -> void:
	for i in gen.enemy_spawns.size():
		var enemy = EnemyScript.new()
		enemy.setup(_scaled_enemy(_pick_enemy_data()))
		enemy.position = _tile_to_pos(gen.enemy_spawns[i])
		enemy.hero = hero
		enemy.died.connect(_on_enemy_died)
		# стража гнезда патрулирует (M12): в лагере бандитов часть врагов
		# обходит точки рядом со своим постом, пока герой далеко
		if Game.forced_biome == "bandit_camp" and i % 2 == 0:
			enemy.patrol = _patrol_points(gen.enemy_spawns[i])
		add_child(enemy)


## Точки патруля: до 3 свободных тайлов в радиусе 3 от поста.
func _patrol_points(home: Vector2i) -> PackedVector2Array:
	var points := PackedVector2Array()
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
			Vector2i(3, 1), Vector2i(-3, -1), Vector2i(1, 3), Vector2i(-1, -3)]:
		var t: Vector2i = home + d
		if gen.is_floor(t):
			points.append(_tile_to_pos(t))
		if points.size() >= 3:
			break
	return points


## Мирная фауна данжей (замечание 2026-10-20: звери живут не только на карте
## мира). Состав по биому; птица почти везде, в лесу — олени и кабан.
func _build_fauna() -> void:
	var biome_id := _biome_id()
	var roster: Array = {
		"mutant_forest": ["deer", "deer", "boar", "bird"],
		"ruins": ["bird", "bird"],
		"crystal_caves": ["bird", "bird"],
		"ash_wastes": ["bird"],
		"cursed_hall": ["bird", "bird"],
		"demon_lair": ["bird"],
	}.get(biome_id, ["bird", "bird"])
	var fcfg: Dictionary = _read_json("res://data/fauna.json")
	var creature_script: Script = load("res://scripts/dungeon_creature.gd")
	var placed := 0
	var guard := 0
	while placed < roster.size() and guard < 300:
		guard += 1
		var tile := Vector2i(_rng.randi_range(1, gen.w - 2), _rng.randi_range(1, gen.h - 2))
		if not gen.is_floor(tile):
			continue
		if tile.distance_to(gen.start_tile) < 6:
			continue
		var kind: String = roster[placed]
		var def: Dictionary = {}
		for s in fcfg.get("species", []):
			if String(s["id"]) == kind:
				def = s
				break
		if def.is_empty():
			continue
		var creature = creature_script.new()
		creature.setup(kind, def, hero, gen, float(ts))
		creature.position = _tile_to_pos(tile)
		creature.slain.connect(_on_fauna_slain)
		creature.add_to_group("dungeon_fauna")
		add_child(creature)
		placed += 1


## Ключ текущего биома (forced от POI карты мира или поиск по словарю).
func _biome_id() -> String:
	var fb := String(Game.forced_biome)
	if params.get("biomes", {}).has(fb):
		return fb
	for key in params.get("biomes", {}):
		if params["biomes"][key] == biome:
			return String(key)
	return ""


## Зверь убит: дроп по fauna.json в рюкзак героя.
func _on_fauna_slain(creature) -> void:
	var kind := String(creature.kind)
	var fcfg: Dictionary = _read_json("res://data/fauna.json")
	var def: Dictionary = {}
	for s in fcfg.get("species", []):
		if String(s["id"]) == kind:
			def = s
			break
	var parts := PackedStringArray()
	for d in def.get("drop", []):
		var n := _loot_rng.randi_range(int((d["count"] as Array)[0]), int((d["count"] as Array)[1]))
		if n > 0:
			Game.add_item(String(d["id"]), n)
			parts.append("%s ×%d" % [Loc.t("item." + String(d["id"])), n])
	hud.toast(Loc.t("world.hunt_got") % [Loc.t("fauna." + kind), ", ".join(parts)])


## Ловушки биома (M7): типы и числа — dungeon.json -> "traps".
func _build_traps() -> void:
	var trap_cfg: Dictionary = params.get("traps", {})
	for spawn: Dictionary in gen.trap_spawns:
		var kind := String(spawn["kind"])
		if not trap_cfg.has(kind):
			continue
		var trap = TrapScript.new()
		trap.setup(kind, trap_cfg[kind], gen, hero)
		trap.position = _tile_to_pos(spawn["tile"])
		trap.add_to_group("traps")
		add_child(trap)


## Босс биома (M7): один, в дальней комнате у выхода, гарантированный лут.
func _build_boss() -> void:
	var boss_id := String(biome.get("boss", ""))
	if boss_id == "":
		return
	var boss_data := _enemy_by_id(boss_id)
	if boss_data.is_empty():
		return
	var boss = EnemyScript.new()
	boss.setup(_scaled_enemy(boss_data))
	boss.position = _tile_to_pos(gen.exit_tile) + Vector2(float(ts), 0)
	boss.hero = hero
	boss.died.connect(_on_enemy_died)
	boss.died.connect(_on_boss_died)
	add_child(boss)
	# Кощей (v1.30, док 14): игла смерти в углу арены — пока цела, босс бессмертен
	if String(boss_data.get("perk", "")) == "koshchei":
		var nd := _enemy_by_id("death_needle")
		if not nd.is_empty():
			var needle = EnemyScript.new()
			needle.setup(nd)
			needle.position = boss.position + Vector2(-float(ts) * 4.0, float(ts) * 2.0)
			needle.hero = hero
			needle.died.connect(_on_enemy_died)
			add_child(needle)


func _enemy_by_id(enemy_id: String) -> Dictionary:
	for enemy in enemies_data:
		if String(enemy["id"]) == enemy_id:
			return enemy
	return {}


## Взвешенный случайный тип врага: свой набор у каждого биома (M5),
## общий — из data/dungeon.json -> "enemy_weights".
func _pick_enemy_data() -> Dictionary:
	var weights: Dictionary = biome.get("enemy_weights", params["enemy_weights"])
	var total := 0
	for w: int in weights.values():
		total += w
	var roll := _rng.randi_range(1, total)
	for enemy in enemies_data:
		roll -= int(weights.get(String(enemy["id"]), 0))
		if roll <= 0:
			return enemy
	return enemies_data[0]


func _spawn_pickup(kind: String, item_id: String, pos: Vector2) -> void:
	var pickup = PickupScript.new()
	# спрайт лута (M9): из dungeon.json -> sprites (мана) или loot.json -> items (предмет)
	var ref := ""
	if kind == "mana":
		ref = String(params.get("sprites", {}).get("mana", "k:116"))
	else:
		for it: Dictionary in loot_data.get("items", []):
			if String(it["id"]) == item_id:
				ref = String(it.get("sprite", ""))
				break
		# предметы экипировки живут в items.json (M14-B)
		if ref == "":
			for it: Dictionary in Game.items_cfg.get("items", []):
				if String(it["id"]) == item_id:
					ref = String(it.get("sprite", ""))
					break
	pickup.setup(kind, item_id, ref)
	pickup.position = pos
	pickup.collected.connect(_on_pickup_collected)
	add_child(pickup)


## --- Магия (M3): каст боевых заклинаний ---------------------------------

## Каст по слоту спеллбука: мана, кулдаун, эффект, цвет школы.
## free_cast — свиток (M14-B): ману не тратим, кулдаун общий с заклинанием.
func _cast_spell(spell_id: String, free_cast := false) -> void:
	if hero.dead:
		return
	var def: Dictionary = Game.magic.spell(spell_id)
	if def.is_empty() or String(def["where"]) != "dungeon":
		return
	if hero.spell_cd_left(spell_id) > 0.0:
		return
	var cost := 0 if free_cast else int(def.get("mana_cost", 0))
	if hero.mana < cost:
		hud.toast(Loc.t("magic.no_mana"))
		return
	hero.mana -= cost
	# магия качает стату (v1.24): заклинания — интеллект, трата маны — мудрость
	var ha2: Dictionary = hero.attrs_cfg()
	Game.hero_train("int", float(ha2.get("train_cast_int", 0.15)))
	if cost > 0:
		Game.hero_train("wis", float(ha2.get("train_cast_wis", 0.05)) \
				+ float(ha2.get("train_mana_wis", 0.04)) * float(cost))
	# ветка мага (M7): кулдауны заклинаний короче
	hero.set_spell_cd(spell_id, float(def.get("cooldown", 3.0)) * hero.skill_mult("spell_cd_mult", 1.0))
	# интеллект усиливает урон и лечение заклинания (v1.24)
	var params2: Dictionary = def.get("params", {}).duplicate(true)
	params2["damage"] = int(round(float(params2.get("damage", 0)) * hero.spell_mult()))
	params2["heal"] = int(round(float(params2.get("heal", 0)) * hero.spell_mult()))
	var school := String(def["school"])
	var col: Color = Game.magic.school_color(school)
	match spell_id:
		"fire_flash":
			_spell_flash(params2, col)
		"chain_bolt":
			_spell_bolt(params2, col)
		"heal":
			_spell_heal(params2, col)
		"shield":
			_spell_shield(params2, col)
		"roots":
			_spell_roots(params2, col)
		"thorns":
			_spell_thorns(params2, col)
		"corrupt_blast":
			_spell_flash(params2, col)
		"plague":
			_spell_thorns(params2, col)
		"drain_life":
			_spell_drain(params2, col)
		"overcharge":
			_spell_overcharge(params2, col)
		"light_beacon":
			_spell_beacon(params2, col)
		"stone_skin":
			_spell_stone_skin(params2, col)
		"soul_burn":
			_spell_soul_burn(params2, col)
		"void_rift":
			_spell_flash(params2, col)
	# дикая магия загрязняет регион (даже из данжа — город рядом)
	if float(def.get("pollution", 0.0)) > 0.0 and Game.city_sim != null:
		Game.city_sim.add_pollution(float(def["pollution"]))


## Свиток (M14-B, B.3): разовое применение заклинания в бою, без затрат маны.
## Вызывается панелью экипировки; свиток расходуется до каста.
func _cast_scroll(item_id: String) -> String:
	var item: Dictionary = Game.item_def(item_id)
	var spell_id := String(item.get("spell_id", ""))
	if spell_id == "" or Game.magic.spell(spell_id).is_empty():
		return "eq.not_usable"
	if Game.count_item(item_id) < 1:
		return "eq.not_owned"
	if hero.dead:
		return "eq.not_usable"
	if hero.spell_cd_left(spell_id) > 0.0:
		return "magic.cooldown"
	Game.remove_item(item_id, 1)
	_cast_spell(spell_id, true)
	return ""


## Точка каста: курсор, не дальше range_px от героя.
func _cast_point(range_px: float) -> Vector2:
	var to: Vector2 = get_global_mouse_position() - hero.global_position
	if to.length() <= range_px:
		return hero.global_position + to
	return hero.global_position + to.normalized() * range_px


func _spell_flash(p2: Dictionary, col: Color) -> void:
	var pos := _cast_point(float(p2.get("range", 200.0)))
	var radius: float = float(p2.get("radius", 46.0)) * hero.skill_mult("radius_mult", 1.0)
	_add_fx("burst", col, radius, 0.4, pos)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(pos) <= radius + float(enemy.p["radius"]):
			enemy.take_damage(int(p2.get("damage", 4)), "wild")


func _spell_bolt(p2: Dictionary, col: Color) -> void:
	var in_range: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var d: float = enemy.global_position.distance_to(hero.global_position)
		if d <= float(p2.get("radius", 170.0)):
			in_range.append([d, enemy])
	in_range.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	var points := PackedVector2Array([Vector2.ZERO])
	var hits := 0
	for entry in in_range:
		if hits >= int(p2.get("targets", 3)):
			break
		var enemy = entry[1]
		enemy.take_damage(int(p2.get("damage", 2)), "wild")
		points.append(enemy.global_position - hero.global_position)
		hits += 1
	if hits > 0:
		_add_fx("bolt", col, 0.0, 0.35, hero.global_position, points)


func _spell_heal(p2: Dictionary, col: Color) -> void:
	hero.heal(int(p2.get("heal", 5)))
	_add_fx("ring", col, 26.0, 0.6, hero.global_position)


func _spell_shield(p2: Dictionary, col: Color) -> void:
	hero.cast_shield(float(p2.get("duration", 5.0)))
	_add_fx("ring", col, 40.0, 0.8, hero.global_position)


func _spell_roots(p2: Dictionary, col: Color) -> void:
	var pos := _cast_point(float(p2.get("range", 200.0)))
	var radius: float = float(p2.get("radius", 58.0)) * hero.skill_mult("radius_mult", 1.0)
	_add_fx("burst", col, radius, 0.6, pos)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(pos) <= radius + float(enemy.p["radius"]):
			enemy.stun_for(float(p2.get("stun", 3.0)))


func _spell_thorns(p2: Dictionary, col: Color) -> void:
	var pos := _cast_point(float(p2.get("range", 200.0)))
	var radius: float = float(p2.get("radius", 58.0)) * hero.skill_mult("radius_mult", 1.0)
	var duration := float(p2.get("duration", 4.0))
	_zones.append({
		"pos": pos, "radius": radius, "until": _zone_time + duration,
		"acc": 0.0, "dps": int(p2.get("dps", 1)),
	})
	_add_fx("zone", col, radius, duration, pos)


## Вытягивание жизни (запретная школа, M5): бьёт ближайших и лечит героя.
func _spell_drain(p2: Dictionary, col: Color) -> void:
	var in_range: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var d: float = enemy.global_position.distance_to(hero.global_position)
		if d <= float(p2.get("radius", 180.0)):
			in_range.append([d, enemy])
	in_range.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	var points := PackedVector2Array([Vector2.ZERO])
	var hits := 0
	for entry in in_range:
		if hits >= int(p2.get("targets", 2)):
			break
		var enemy = entry[1]
		enemy.take_damage(int(p2.get("damage", 3)), "forbidden")
		points.append(enemy.global_position - hero.global_position)
		hits += 1
	if hits > 0:
		hero.heal(int(p2.get("heal_per_target", 2)) * hits)
		_add_fx("bolt", col, 0.0, 0.35, hero.global_position, points)


## Перегрузка (дикая школа, M7): герой временно бьёт сильнее.
func _spell_overcharge(p2: Dictionary, col: Color) -> void:
	hero.temp_damage_bonus(float(p2.get("duration", 8.0)), int(p2.get("damage_bonus", 2)))
	_add_fx("ring", col, 34.0, 0.7, hero.global_position)


## Маяк света (M7): замедляет всех врагов вокруг героя.
func _spell_beacon(p2: Dictionary, col: Color) -> void:
	var radius: float = float(p2.get("radius", 140.0)) * hero.skill_mult("radius_mult", 1.0)
	_add_fx("ring", col, radius, 0.8, hero.global_position)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(hero.global_position) <= radius:
			enemy.slow_for(float(p2.get("duration", 5.0)), float(p2.get("slow_mult", 0.5)))


## Каменная кожа (M7): герой временно получает броню.
func _spell_stone_skin(p2: Dictionary, col: Color) -> void:
	hero.temp_armor_bonus(float(p2.get("duration", 10.0)), int(p2.get("armor", 1)))
	_add_fx("ring", col, 30.0, 0.7, hero.global_position)


## Выжигание души (запретная школа, M7): взрыв по кругу, за каждую цель — мана.
func _spell_soul_burn(p2: Dictionary, col: Color) -> void:
	var pos := _cast_point(float(p2.get("range", 200.0)))
	var radius: float = float(p2.get("radius", 60.0)) * hero.skill_mult("radius_mult", 1.0)
	_add_fx("burst", col, radius, 0.5, pos)
	var hits := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(pos) <= radius + float(enemy.p["radius"]):
			enemy.take_damage(int(p2.get("damage", 5)), "forbidden")
			hits += 1
	if hits > 0:
		hero.add_mana(int(p2.get("mana_per_target", 1)) * hits)
		hud.toast(Loc.t("dungeon.mana_back") % (int(p2.get("mana_per_target", 1)) * hits))


