extends Node2D
## Сцена данжа-прототипа (M1): генерация, герой, враги, лут, мана-голод, HUD.
## Приёмка этапа: вошёл -> подрался -> собрал лут -> вернулся; смерть не завершает игру.

const DungeonGenScript := preload("res://scripts/dungeon_gen.gd")
const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const ChestScript := preload("res://scripts/chest.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const ExitMarkerScript := preload("res://scripts/exit_marker.gd")
const DungeonViewScript := preload("res://scripts/dungeon_view.gd")
const HudScript := preload("res://scripts/hud.gd")
const SpellFxScript := preload("res://scripts/spell_fx.gd")
const CITY_CFG_PATH := "res://data/city.json"

var params: Dictionary = {}
var biome: Dictionary = {}        # активный биом (M5: руины или лес-мутант)
var enemies_data: Array = []
var loot_data: Dictionary = {}
# ссылки на скрипты других узлов — динамические, без типов движка (свойств у них нет)
var gen = null
var hero = null
var hud = null
var ts := 32

var _seed_value := 0
var _visited: Dictionary = {}
var _mana_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _loot_rng := RandomNumberGenerator.new()
var _zones: Array = []            # зоны «Терновых шипов»: {pos, radius, until, acc, dps}
var _zone_time := 0.0


func _ready() -> void:
	params = _read_json("res://data/dungeon.json")
	enemies_data = _read_json("res://data/enemies.json")
	loot_data = _read_json("res://data/loot.json")
	ts = int(params["tile_size"])
	_seed_value = int(Time.get_unix_time_from_system())
	_rng.seed = _seed_value
	_loot_rng.seed = _seed_value + 1
	biome = _pick_biome()

	gen = DungeonGenScript.new()
	gen.generate(_seed_value, params)

	_build_darkness()
	add_child(_make_view())
	_build_walls()
	_build_exit()
	_build_chests()
	_build_crystals()
	_build_hero()
	_build_enemies()

	hud = HudScript.new()
	hud.init(hero, gen, loot_data)
	add_child(hud)
	hud.minimap.setup(gen)
	# дикий регион: посещение леса-мутанта добавляет городу загрязнения (M5)
	var pol := float(biome.get("pollution_on_visit", 0.0))
	if pol > 0.0 and Game.city_sim != null:
		Game.city_sim.add_pollution(pol)


## Биом данжа по весам (M5): руины спокойнее, лес-мутант опаснее и жирнее.
func _pick_biome() -> Dictionary:
	var biomes: Dictionary = params.get("biomes", {})
	var weights: Dictionary = params.get("biome_weights", {})
	var total := 0
	for w: int in weights.values():
		total += w
	var roll := _rng.randi_range(1, maxi(1, total))
	for id in weights:
		roll -= int(weights[id])
		if roll <= 0 and biomes.has(id):
			return biomes[id]
	return biomes.get("ruins", params.get("biome", {}))


func _process(delta: float) -> void:
	if hero.dead:
		return
	_zone_time += delta
	_update_zones()
	_update_fog()
	_update_mana_hunger(delta)
	_update_hint()
	hud.refresh()
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	if Input.is_action_just_pressed("inventory"):
		hud.toggle_inventory()


func _unhandled_input(event: InputEvent) -> void:
	# слоты заклинаний 1–9 (спеллбук, порядок изучения; с M5 — 9 боевых школ-заклинаний)
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.physical_keycode:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
			KEY_4: idx = 3
			KEY_5: idx = 4
			KEY_6: idx = 5
			KEY_7: idx = 6
			KEY_8: idx = 7
			KEY_9: idx = 8
		if idx >= 0 and idx < Game.spellbook.size():
			_cast_spell(String(Game.spellbook[idx]))


func _tile_to_pos(tile: Vector2i) -> Vector2:
	return Vector2(tile) * float(ts) + Vector2(ts, ts) / 2.0


func _pos_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i((pos / float(ts)).floor())


## Тьма: весь данж гасится, видимость даёт только фонарь героя (hero.make_light).
func _build_darkness() -> void:
	var dark := CanvasModulate.new()
	dark.name = "Darkness"
	dark.color = Color(String(biome["ambient"]))
	add_child(dark)


func _make_view() -> Node2D:
	var view = DungeonViewScript.new()
	view.setup(gen, ts, biome)
	return view


## Стены: один StaticBody2D, горизонтальные цепочки стен слеплены в один прямоугольник.
## На каждый сегмент — LightOccluder2D: фонарь героя отбрасывает от стен настоящие тени.
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
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
			var occ := LightOccluder2D.new()
			var poly := OccluderPolygon2D.new()
			var hw := seg_w / 2.0
			var hh := float(ts) / 2.0
			poly.polygon = PackedVector2Array([
				Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh),
			])
			occ.occluder = poly
			occ.position = center
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
	_apply_mana_params()
	# боевые комплекты героя из оружейки: +урон, +броня (M5.1)
	var kit: Dictionary = Game.hero_kit_bonus(_read_json(CITY_CFG_PATH))
	hero.bonus_damage = int(kit["damage"])
	hero.bonus_armor = int(kit["armor"])
	hero.position = _tile_to_pos(gen.start_tile)
	hero.died.connect(_on_hero_died)
	add_child(hero)
	hero.set_camera_limits(Rect2(0, 0, gen.w * float(ts), gen.h * float(ts)))
	# радиус фонаря — отдельный параметр (меньше радиуса обзора-памяти миникарты)
	hero.make_light(float(params["hero"]["light_radius_tiles"]) * float(ts))


## Мана героя (ответы №56 и №65): запас и регенерация; зачарованный алтарь
## в городе увеличивает запас и ускоряет регенерацию.
func _apply_mana_params() -> void:
	var mana_cfg: Dictionary = _read_json(CITY_CFG_PATH).get("hero_mana", {})
	var regen := float(mana_cfg.get("regen_period", 8.0))
	var cap_extra := 0
	if Game.city_sim != null and Game.city_sim.altar_enchanted():
		cap_extra = int(mana_cfg.get("altar_cap_extra", 4))
		regen = float(mana_cfg.get("altar_regen_period", 5.0))
	hero.mana_max = int(params["hero"]["mana"]) + cap_extra
	hero.mana = hero.mana_max
	hero.mana_regen_period = regen


## Враги данжа: с каждой полной зачисткой сильнее (M5.1).
func _scaled_enemy(data: Dictionary) -> Dictionary:
	var growth: Dictionary = params.get("clear_growth", {})
	var n := int(Game.dungeon_clears)
	var out := data.duplicate()
	out["hp"] = int(round(float(data["hp"]) * (1.0 + float(growth.get("hp_per_clear", 0.3)) * n)))
	out["damage"] = int(data["damage"]) + n * int(growth.get("damage_per_clear", 1))
	return out


func _build_enemies() -> void:
	for i in gen.enemy_spawns.size():
		var enemy = EnemyScript.new()
		enemy.setup(_scaled_enemy(_pick_enemy_data()))
		enemy.position = _tile_to_pos(gen.enemy_spawns[i])
		enemy.hero = hero
		enemy.died.connect(_on_enemy_died)
		add_child(enemy)


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
	pickup.setup(kind, item_id)
	pickup.position = pos
	pickup.collected.connect(_on_pickup_collected)
	add_child(pickup)


## --- Магия (M3): каст боевых заклинаний ---------------------------------

## Каст по слоту спеллбука: мана, кулдаун, эффект, цвет школы.
func _cast_spell(spell_id: String) -> void:
	if hero.dead:
		return
	var def: Dictionary = Game.magic.spell(spell_id)
	if def.is_empty() or String(def["where"]) != "dungeon":
		return
	if hero.spell_cd_left(spell_id) > 0.0:
		return
	var cost := int(def.get("mana_cost", 0))
	if hero.mana < cost:
		hud.toast(Loc.t("magic.no_mana"))
		return
	hero.mana -= cost
	hero.set_spell_cd(spell_id, float(def.get("cooldown", 3.0)))
	var params2: Dictionary = def.get("params", {})
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
	# дикая магия загрязняет регион (даже из данжа — город рядом)
	if float(def.get("pollution", 0.0)) > 0.0 and Game.city_sim != null:
		Game.city_sim.add_pollution(float(def["pollution"]))


## Точка каста: курсор, не дальше range_px от героя.
func _cast_point(range_px: float) -> Vector2:
	var to: Vector2 = get_global_mouse_position() - hero.global_position
	if to.length() <= range_px:
		return hero.global_position + to
	return hero.global_position + to.normalized() * range_px


func _spell_flash(p2: Dictionary, col: Color) -> void:
	var pos := _cast_point(float(p2.get("range", 200.0)))
	_add_fx("burst", col, float(p2.get("radius", 46.0)), 0.4, pos)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(pos) <= float(p2.get("radius", 46.0)) + float(enemy.p["radius"]):
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
	_add_fx("burst", col, float(p2.get("radius", 58.0)), 0.6, pos)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(pos) <= float(p2.get("radius", 58.0)) + float(enemy.p["radius"]):
			enemy.stun_for(float(p2.get("stun", 3.0)))


func _spell_thorns(p2: Dictionary, col: Color) -> void:
	var pos := _cast_point(float(p2.get("range", 200.0)))
	var radius := float(p2.get("radius", 58.0))
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
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var p := Vector2i(t.x + dx, t.y + dy)
			if gen.is_floor(p) and not _visited.has(p):
				_visited[p] = true
				changed = true
	if changed:
		hud.minimap.update_state(t, _visited)


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
	var chest = _nearest_chest(float(ts) * 1.8)
	if chest != null:
		hud.set_hint(Loc.t("dungeon.hint_chest"))
		return
	hud.set_hint(Loc.t("dungeon.hint_spells"))


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
	var chest = _nearest_chest(float(ts) * 1.8)
	if chest != null:
		_open_chest(chest)


func _open_chest(chest: Node) -> void:
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


func _on_pickup_collected(pickup) -> void:
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
	_check_dungeon_cleared()


## Все враги мертвы — данж зачищен: 10 дней не работает, следующая версия сильнее (M5.1).
func _check_dungeon_cleared() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and int(e["hp"]) > 0:
			return
	var growth: Dictionary = params.get("clear_growth", {})
	var day := 0
	if Game.city_sim != null:
		day = int(Game.city_sim.day)
	Game.register_dungeon_clear(day, int(growth.get("lock_days", 10)))
	hud.toast(Loc.t("dungeon.cleared_toast") % int(growth.get("lock_days", 10)))


## Смерть героя: потеря половины лута и выброс в город, игра продолжается.
func _on_hero_died() -> void:
	Game.last_run_death = true
	Game.lose_half_loot()
	get_tree().change_scene_to_file("res://scenes/city.tscn")


func _leave_dungeon() -> void:
	Game.last_run_death = false
	get_tree().change_scene_to_file("res://scenes/city.tscn")


func _item_by_id(item_id: String) -> Dictionary:
	for item in loot_data.get("items", []):
		if item["id"] == item_id:
			return item
	return {}


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
