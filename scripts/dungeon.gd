extends Node2D
## Сцена данжа-прототипа (M1): генерация, герой, враги, лут, мана-голод, HUD.
## Приёмка этапа: вошёл -> подрался -> собрал лут -> вернулся; смерть не завершает игру.

const DungeonGenScript := preload("res://scripts/dungeon_gen.gd")
const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const TrapScript := preload("res://scripts/trap.gd")
const ChestScript := preload("res://scripts/chest.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const ExitMarkerScript := preload("res://scripts/exit_marker.gd")
const DungeonViewScript := preload("res://scripts/dungeon_view.gd")
const HudScript := preload("res://scripts/hud.gd")
const SpellFxScript := preload("res://scripts/spell_fx.gd")
const CITY_CFG_PATH := "res://data/city.json"
const LOOT_CFG_PATH := "res://data/loot.json"

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
var _darkness: CanvasModulate = null    # общий свет данжа: светлеет по мере убийств
var _ambient_base := Color.WHITE        # исходная тьма биома
var _enemies_total := 0                 # монстров на входе в данж (для подсветки)
var _pause_layer: CanvasLayer = null   # пауза данжа (M9, Esc)
var _pause_overlay = null
var _equip_panel = null                # панель экипировки (M14-B, клавиша I)
var _fog = null                        # туман войны (v1.33, dungeon_fog.gd)
var _visible_now: Dictionary = {}      # полы в поле зрения героя сейчас


## Пауза данжа (M9): Esc — вуаль + «Продолжить / В меню».
## Сначала Esc закрывает открытые окна (фидбек заказчика): экипировка,
## инвентарь; и только затем — пауза.
func _toggle_pause() -> void:
	if get_tree().paused:
		return  # закрытие оверлея делает сам оверлей (ALWAYS)
	if _equip_panel != null and _equip_panel.is_open():
		_equip_panel.close()
		return
	if hud.inventory_visible():
		hud.toggle_inventory()
		return
	_pause_overlay.open()


func _build_pause() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 50
	add_child(_pause_layer)
	_pause_overlay = load("res://scripts/pause_overlay.gd").new()
	# данжи транзитны (M14-A): середина данжа не сохраняется — честно говорим
	_pause_overlay.allow_save = false
	_pause_overlay.hint = Loc.t("save.dungeon_hint")
	_pause_layer.add_child(_pause_overlay)


func _ready() -> void:
	Game.in_dungeon = true   # в данже автосейва нет (транзитность, M14-A)
	params = _read_json("res://data/dungeon.json")
	enemies_data = _read_json("res://data/enemies.json")
	loot_data = _read_json(LOOT_CFG_PATH)
	ts = int(params["tile_size"])
	_seed_value = int(Time.get_unix_time_from_system())
	_rng.seed = _seed_value
	_loot_rng.seed = _seed_value + 1
	# локация карты мира (M8): руины и лагеря меньше полноценного данжа
	if Game.dungeon_scale < 1.0:
		params = params.duplicate(true)
		for key in ["max_rooms", "enemy_count", "chest_count", "crystal_count"]:
			params[key] = maxi(1, int(round(float(params[key]) * Game.dungeon_scale)))
		params["traps"]["count"] = maxi(1, int(round(float(params["traps"]["count"]) * Game.dungeon_scale)))
	biome = _pick_biome()
	# кодекс (M14-K): биом открыт
	Game.codex_seen("biomes", _biome_id())

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
	_build_traps()
	_build_boss()
	_build_fauna()
	# туман войны (v1.33): поверх мира, до HUD — неисследованное чёрное,
	# изученное приглушено, видимое в свет герой — чистое
	_fog = load("res://scripts/dungeon_fog.gd").new()
	_fog.setup(gen, ts)
	add_child(_fog)
	# сколько монстров было на входе: по доле убитых данж светлеет (2026-10-21)
	_enemies_total = get_tree().get_nodes_in_group("enemies").size()

	hud = HudScript.new()
	hud.init(hero, gen, loot_data)
	# v1.33: HUD — CanvasLayer, рисуется выше тумана войны (z=40 в базовой
	# канве) автоматически, без z_index (у CanvasLayer его нет)
	add_child(hud)
	hud.minimap.setup(gen)
	_build_pause()
	# панель экипировки (M14-B, клавиша I): слоты, рюкзак, свитки/зелья
	_equip_panel = load("res://scripts/equipment_panel.gd").new()
	_equip_panel.hero_cb = func(): return hero
	_equip_panel.toast_cb = func(msg: String) -> void: hud.toast(msg)
	_equip_panel.on_change = _apply_equipment
	_equip_panel.cast_scroll_cb = _cast_scroll
	add_child(_equip_panel)
	# дикий регион: посещение леса-мутанта добавляет городу загрязнения (M5)
	var pol := float(biome.get("pollution_on_visit", 0.0))
	if pol > 0.0 and Game.city_sim != null:
		Game.city_sim.add_pollution(pol)


## Биом данжа по весам (M5): руины спокойнее, лес-мутант опаснее и жирнее.
## Точка интереса карты мира задаёт биом сама (M8); городская аномалия — как раньше.
func _pick_biome() -> Dictionary:
	var biomes: Dictionary = params.get("biomes", {})
	if Game.forced_biome != "" and biomes.has(Game.forced_biome):
		return biomes[Game.forced_biome]
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
	if Input.is_action_just_pressed("ui_cancel"):
		_toggle_pause()
	if get_tree().paused or hero.dead:
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
	# панель экипировки (M14-B): клавиша I
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_I:
		_equip_panel.toggle()
		get_viewport().set_input_as_handled()
		return
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
## Правка 2026-10-21: с каждым убитым монстром данж светлеет — к финалу видно всё.
func _build_darkness() -> void:
	var dark := CanvasModulate.new()
	dark.name = "Darkness"
	# v1.33.1 (заказчик: «до этого был приятный РЕАЛИСТИЧНЫЙ свет»):
	# база данжа снова ТЁМНАЯ «тусклая луна» (эфф. ~0.53) — атмосферу даёт
	# тёплый фонарь героя с настоящими тенями от стен. В отличие от v1.30.1,
	# когда на такой базе тёмные тайлы биома сливались в черноту (стены
	# rgb(29,23,22)), теперь материалы полов/стен яркие (v1.33: камень,
	# кирпич, земля, кристалл) — в свете фонаря они читаются во всех
	# красках, вне света — тёмные, но узнаваемые. Войд остаётся чёрным.
	_ambient_base = Color(String(biome["ambient"])).lerp(
			Color(0.62, 0.62, 0.70), 0.80)
	dark.color = _ambient_base
	_darkness = dark
	add_child(dark)


## Чистая математика подсветки (для тестов): доля убитых 0..1 лерпит исходную
## тьму биома к светлому цвету clear_light с силой power.
static func bright_ambient(base: Color, killed_frac: float, lcfg: Dictionary) -> Color:
	var target := Color(String(lcfg.get("color", "#7a7a8c")))
	var power := clampf(float(lcfg.get("power", 0.9)), 0.0, 1.0)
	return base.lerp(target, clampf(killed_frac, 0.0, 1.0) * power)


## Пересчитать общий свет: чем больше монстров убито, тем светлее данж.
func _apply_clear_light() -> void:
	if _darkness == null or _enemies_total <= 0:
		return
	var alive := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and int(e["hp"]) > 0:
			alive += 1
	var killed_frac := 1.0 - float(alive) / float(_enemies_total)
	_darkness.color = bright_ambient(_ambient_base, killed_frac,
			params.get("clear_light", {}))


## Ночное усиление нечисти (v1.30, док 14): ночь города и тьма данжа до
## зачистки. Чистая формула — enemy.night_mult (тесты).
func night_boost() -> float:
	var is_night := false
	var cs = Game.city_sim
	if cs != null and cs.cfg != null:
		var dl := maxf(0.1, float(cs.cfg.get("day_length", 120.0)))
		var nf := clampf(float(cs.cfg.get("night_fraction", 0.3)), 0.0, 0.9)
		is_night = fmod(maxf(float(cs.time), 0.0), dl) >= dl * (1.0 - nf)
	var dark_frac := 1.0
	if _enemies_total > 0:
		var alive := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and int(e["hp"]) > 0:
				alive += 1
		dark_frac = float(alive) / float(_enemies_total)
	return EnemyScript.night_mult(is_night, dark_frac)


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
	var trap = _nearest_trap(float(ts) * 1.3)
	if trap != null:
		hud.set_hint(Loc.t("dungeon.hint_trap"))
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
	var trap = _nearest_trap(float(ts) * 1.3)
	if trap != null:
		trap.disarm()
		hud.toast(Loc.t("dungeon.trap_disarmed"))
		return
	var chest = _nearest_chest(float(ts) * 1.8)
	if chest != null:
		_open_chest(chest)


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
