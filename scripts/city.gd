extends Node2D
## Город (M2): карта, стройка мышью, жители-статисты, пул ресурсов,
## переключение город↔данж у аномалии, пауза и скорость x1/x2/x3.
## Симуляция живёт в Game и тикается сама — сцена только показывает и слушает ввод.

const DUNGEON_SCENE := "res://scenes/dungeon.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const CITY_CFG_PATH := "res://data/city.json"
const HERO_SCRIPT := "res://scripts/hero.gd"
const VIEW_SCRIPT := "res://scripts/city_view.gd"
const HUD_SCRIPT := "res://scripts/city_hud.gd"

var sim = null
var map = null
var cfg: Dictionary = {}
var hero = null
var view: Node2D = null
var hud: CanvasLayer = null

var build_mode := ""            # выбранный тип здания для стройки
var enchant_mode := ""          # выбранное зачарование (M3): клик по зданию применит
var _modulate: CanvasModulate
var _static_body: StaticBody2D
var _near_anomaly := false
var _near_armory: Dictionary = {}   # оружейка рядом с героем (E — комплект героя)


func _ready() -> void:
	if Game.city_sim == null:
		Game.new_city()
	sim = Game.city_sim
	sim.paused = false
	map = sim.map
	cfg = _read_json(CITY_CFG_PATH)
	view = load(VIEW_SCRIPT).new()
	view.setup(map, sim, cfg)
	view.city = self
	view.enchant_colors = _enchant_colors()
	add_child(view)
	_static_body = StaticBody2D.new()
	_rebuild_collision()
	add_child(_static_body)
	_spawn_hero()
	_modulate = CanvasModulate.new()
	_modulate.color = Color.WHITE
	add_child(_modulate)
	hud = load(HUD_SCRIPT).new()
	hud.init(sim, self, cfg)
	add_child(hud)
	hud.set_enchant_colors(_enchant_colors())
	hud.set_hint(_default_hint())
	hero.died.connect(_on_hero_down)
	_deposit_loot()


func _exit_tree() -> void:
	# ушли в данж/меню: мутантам некого преследовать
	if sim != null:
		sim.hero_alive = false


## Цвета зачарований для подсветки зданий и кнопок панели магии.
func _enchant_colors() -> Dictionary:
	var out := {}
	for e in Game.magic.enchantments():
		out[String(e["id"])] = Color(String(e["color"]))
	return out


func _spawn_hero() -> void:
	var dungeon_cfg: Dictionary = _read_json("res://data/dungeon.json")
	var hero_script: Script = load(HERO_SCRIPT)
	hero = hero_script.new()
	hero.city_mode = true
	hero.setup(dungeon_cfg["hero"], 0)
	var kit: Dictionary = Game.hero_kit_bonus(cfg)
	hero.bonus_damage = int(kit["damage"])
	hero.bonus_armor = int(kit["armor"])
	hero.position = map.tile_center_px(map.spawn_tile)
	add_child(hero)
	hero.set_camera_limits(Rect2(0, 0, map.w * map.ts, map.h * map.ts))


## Коллизии героя: вода, скалы и все готовые здания (открытые ворота проходимы).
func _rebuild_collision() -> void:
	for child in _static_body.get_children():
		child.queue_free()
	var blocked := {}
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] == map.TILE_WATER or map.grid[y][x] == map.TILE_ROCK:
				blocked[Vector2i(x, y)] = true
	for b in sim.buildings:
		if b["done"]:
			if _bld_effect(b) == "gate" and sim.is_gate_open(b):
				continue
			blocked[b["tile"]] = true
	for tile: Vector2i in blocked:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(map.ts, map.ts)
		shape.shape = rect
		shape.position = map.tile_center_px(tile)
		_static_body.add_child(shape)


## Эффект здания из конфига (для ворот и прочих особых зданий).
func _bld_effect(b: Dictionary) -> String:
	for d in cfg["buildings"]:
		if String(d["id"]) == String(b["type"]):
			return String(d.get("effect", ""))
	return ""


func _deposit_loot() -> void:
	if Game.loot_total() == 0:
		Game.last_run_death = false
		return
	var died := Game.last_run_death
	var added: Dictionary = sim.deposit_loot(Game.inventory)
	var parts := PackedStringArray()
	if died:
		parts.append(Loc.t("city.last_run_death") % _leftover_line())
	if not added.is_empty():
		var res_parts := PackedStringArray()
		for key in added:
			res_parts.append("%s ×%d" % [Loc.t("res." + key), int(added[key])])
		parts.append(Loc.t("city.deposited") % ", ".join(res_parts))
	if not died and Game.loot_total() > 0:
		parts.append(Loc.t("city.last_run_ok") % _leftover_line())
	if not parts.is_empty():
		hud.toast("   ".join(parts))
	Game.last_run_death = false


## Остаток рюкзака (руны, снаряжение) одной строкой.
func _leftover_line() -> String:
	var names := {}
	for item: Dictionary in _read_json("res://data/loot.json").get("items", []):
		names[String(item["id"])] = String(item["loc"])
	var parts := PackedStringArray()
	var shown := 0
	for stack in Game.inventory:
		if shown >= 3:
			parts.append("…")
			break
		parts.append("%s ×%d" % [Loc.t(names[String(stack["id"])]), int(stack["count"])])
		shown += 1
	return " ".join(parts)


func _process(_delta: float) -> void:
	# герой в городе: мутанты могут гнаться за ним (M5)
	if not hero.dead:
		sim.hero_pos = hero.global_position
		sim.hero_alive = true
	view.queue_redraw()
	hud.refresh()
	_update_daylight()
	_process_events()
	_update_hover()
	_near_anomaly = hero.position.distance_to(map.tile_center_px(map.anomaly_tile)) < map.ts * 1.7
	_near_armory = _armory_near_hero()
	if _near_anomaly:
		if Game.dungeon_available(sim.day_number()):
			hud.set_hint(Loc.t("city.enter_anomaly"))
		else:
			hud.set_hint(Loc.t("city.dungeon_locked_hint") % (Game.dungeon_lock_day - sim.day_number()))
	elif not _near_armory.is_empty():
		hud.set_hint(Loc.t("city.armory_hint") % int(cfg.get("hero_kit", {}).get("cost_metal", 3)))
	elif build_mode == "":
		hud.set_hint(_default_hint())


## Оружейка рядом с героем (M5.1): за металл герой надевает боевой комплект.
func _armory_near_hero() -> Dictionary:
	for b in sim.buildings:
		if bool(b["done"]) and String(b["type"]) == "armory" \
				and hero.position.distance_to(map.tile_center_px(b["tile"])) < map.ts * 1.7:
			return b
	return {}


## Название здания под курсором — тултип у мыши (просьба заказчика).
func _update_hover() -> void:
	if build_mode != "" or enchant_mode != "":
		hud.set_hover_info("", Vector2.ZERO)
		return
	var b: Dictionary = sim.building_at(map.tile_of_px(get_global_mouse_position()))
	if b.is_empty():
		hud.set_hover_info("", Vector2.ZERO)
		return
	hud.set_hover_info(_hover_text(b), get_viewport().get_mouse_position())


func _hover_text(b: Dictionary) -> String:
	var bld_name := _bld_name(String(b["type"]))
	if not bool(b["done"]):
		var work := 1.0
		for d in cfg["buildings"]:
			if String(d["id"]) == String(b["type"]):
				work = float(d["build_work"])
		var pct := int(clampf(float(b["progress"]) / work * 100.0, 0.0, 100.0))
		return Loc.t("city.hover_site") % [bld_name, pct]
	if float(b.get("stun_left", 0.0)) > 0.0:
		return Loc.t("city.hover_stun") % bld_name
	if _bld_effect(b) == "gate":
		return "%s • %s" % [bld_name, Loc.t("city.gate_open" if sim.is_gate_open(b) else "city.gate_closed")]
	if String(b.get("enchant", "")) != "":
		return "%s • %s" % [bld_name, Loc.t("ench." + String(b["enchant"]))]
	return bld_name


func _process_events() -> void:
	for ev in sim.events:
		var bld_name := _bld_name(String(ev.get("bld", "")))
		match String(ev["type"]):
			"site":
				hud.toast(Loc.t("city.site_started") % bld_name)
			"built":
				hud.toast(Loc.t("city.built_done") % bld_name)
				_rebuild_collision()
			"no_worker":
				hud.toast(Loc.t("city.no_free_worker") % bld_name)
			"wild_flash":
				hud.toast(Loc.t("magic.wild_flash") % bld_name)
			"wild_surge":
				hud.toast(Loc.t("magic.wild_surge"))
			"wild_gift":
				hud.toast(Loc.t("magic.wild_gift"))
			"refugee":
				hud.toast(Loc.t("city.refugee_came") % String(ev["name"]))
			"birth":
				hud.toast(Loc.t("city.birth_toast") % String(ev["name"]))
			"grown":
				hud.toast(Loc.t("city.grown_toast") % [String(ev["name"]), _prof_name(String(ev["prof"]))])
			"died":
				hud.toast(Loc.t("city.died_toast") % String(ev["name"]))
			"wounded":
				hud.toast(Loc.t("city.wounded_toast") % String(ev["name"]))
			"learned":
				hud.toast(Loc.t("city.learned_toast") % [String(ev["name"]), _prof_name(String(ev["prof"]))])
			"autobuild":
				hud.toast(Loc.t("city.autobuild_toast") % [String(ev["name"]), _bld_name(String(ev["bld"]))])
			"promoted":
				hud.toast(Loc.t("city.promoted_toast") % String(ev["name"]))
			"gate":
				hud.toast(Loc.t("city.gate_open" if bool(ev["open"]) else "city.gate_closed"))
				_rebuild_collision()
			"skill_up":
				hud.toast(Loc.t("city.skill_up_toast") % [String(ev["name"]), Loc.t("skill." + String(ev["rank"]))])
			"quarrel":
				hud.toast(Loc.t("story.quarrel_toast") % [String(ev["a"]), String(ev["b"])])
			"friendship":
				hud.toast(Loc.t("story.friendship_toast") % [String(ev["a"]), String(ev["b"])])
			"discovery":
				hud.toast(Loc.t("story.discovery_toast") % [String(ev["name"]), Loc.t("res." + String(ev["res"]))])
			"betrayal":
				hud.toast(Loc.t("story.betrayal_toast") % String(ev["name"]))
			"betrayal_caught":
				hud.toast(Loc.t("story.betrayal_caught_toast") % String(ev["name"]))
			"mutation_good":
				hud.toast(Loc.t("story.mutation_good_toast") % String(ev["name"]))
			"mutation_bad":
				hud.toast(Loc.t("story.mutation_bad_toast") % String(ev["name"]))
			# --- угрозы (M5) ---
			"raid_warn":
				hud.toast(Loc.t("city.raid_warn") % "%.1f" % float(ev["eta"]))
			"raid_start":
				hud.toast(Loc.t("city.raid_siege_toast" if bool(ev["siege"]) else "city.raid_toast") % int(ev["count"]))
			"raid_repelled":
				hud.toast(Loc.t("city.raid_repelled_toast") % int(ev["crystals"]))
			"raid_breached":
				hud.toast(Loc.t("city.raid_breached_toast") % int(ev["razed"]))
			"razed":
				hud.toast(Loc.t("city.razed_toast") % bld_name)
				_rebuild_collision()
			"storm_warn":
				hud.toast(Loc.t("city.storm_warn_toast"))
			"storm_start":
				hud.toast(Loc.t("city.storm_start_toast"))
			"storm_end":
				hud.toast(Loc.t("city.storm_end_toast"))
			"storm_strike":
				hud.toast(Loc.t("city.storm_strike_toast") % bld_name)
			"hero_hit":
				hero.take_damage(int(ev["dmg"]))
			"hunt":
				hud.toast(Loc.t("city.hunt_toast") % [String(ev["name"]), int(ev["food"])])
			"guard_trained":
				hud.toast(Loc.t("city.guard_trained_toast") % String(ev["name"]))
			"hunter_trained":
				hud.toast(Loc.t("city.hunter_trained_toast") % String(ev["name"]))
	sim.events.clear()


func _prof_name(prof_id: String) -> String:
	for p in cfg["professions"]:
		if String(p["id"]) == prof_id:
			return Loc.t(String(p["loc"]))
	return prof_id


func _bld_name(type_id: String) -> String:
	for b in cfg["buildings"]:
		if String(b["id"]) == type_id:
			return Loc.t(String(b["loc"]))
	return type_id


func _update_daylight() -> void:
	var day_len := float(cfg["day_length"])
	var nf := float(cfg["night_fraction"])
	var fade := 8.0
	var t := fmod(sim.time, day_len)
	var night_start := day_len * (1.0 - nf)
	var amount := 0.0
	if t >= night_start:
		amount = 1.0
	elif t >= night_start - fade:
		amount = (t - (night_start - fade)) / fade
	elif t <= fade:
		amount = 1.0 - t / fade
	var night_color := Color(0.45, 0.5, 0.72)
	_modulate.color = Color.WHITE.lerp(night_color, amount)
	# магическое загрязнение подкрашивает воздух (больше — фиолетовее)
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	var pol_t := clampf(sim.pollution / maxf(1.0, float(pol_cfg.get("max", 100.0))), 0.0, 1.0)
	_modulate.color = _modulate.color.lerp(Color(0.82, 0.68, 0.95), pol_t * 0.3)
	# магическая буря (M5): небо наливается грозой
	if sim.storm_state == "active":
		_modulate.color = _modulate.color.lerp(Color(0.6, 0.5, 0.85), 0.4)
	elif sim.storm_state == "warn":
		_modulate.color = _modulate.color.lerp(Color(0.7, 0.6, 0.9), 0.2)


## Герой пал в городе (M5): не умирает окончательно — жители оттаскивают к центру.
func _on_hero_down() -> void:
	if sim.raid_active:
		sim.hero_alive = false
	hud.toast(Loc.t("city.hero_down_toast"))
	hero.dead = false
	hero.hp = maxi(1, int(hero.p["hp"]) / 3)
	hero.position = map.tile_center_px(map.spawn_tile)
	hero.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _near_anomaly:
			if Game.dungeon_available(sim.day_number()):
				_enter_dungeon()
			else:
				hud.toast(Loc.t("city.dungeon_locked_toast") % (Game.dungeon_lock_day - sim.day_number()))
			return
		if not _near_armory.is_empty():
			_buy_hero_kit()
			return
	if event.is_action_pressed("inventory"):
		hud.toggle_residents()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P:
				toggle_pause()
			KEY_R:
				hud.toggle_magic()
			KEY_C:
				hud.toggle_chronicle()
			KEY_1:
				set_speed(1)
			KEY_2:
				set_speed(2)
			KEY_3:
				set_speed(3)
			KEY_4:
				set_speed(10)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and enchant_mode != "":
			_try_enchant()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and enchant_mode != "":
			set_enchant_mode("")
			return
		if event.button_index == MOUSE_BUTTON_LEFT and build_mode != "":
			_try_place()
		elif event.button_index == MOUSE_BUTTON_RIGHT and build_mode != "":
			set_build_mode("")
		elif event.button_index == MOUSE_BUTTON_LEFT:
			hero.city_attack(sim)   # ЛКМ без режима — удар героя в городе (M5)
	elif event.is_action_pressed("ui_cancel"):
		if build_mode != "":
			set_build_mode("")
		elif enchant_mode != "":
			set_enchant_mode("")
		elif hud.magic_visible():
			hud.toggle_magic()
		elif hud.residents_visible():
			hud.toggle_residents()
		elif hud.chronicle_visible():
			hud.toggle_chronicle()
		else:
			sim.paused = true
			get_tree().change_scene_to_file(MENU_SCENE)


func _try_place() -> void:
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not sim.is_buildable_tile(tile, build_mode):
		hud.toast(Loc.t("city.cant_build_here"))
		return
	var cost: Dictionary = {}
	for b in cfg["buildings"]:
		if String(b["id"]) == build_mode:
			cost = b["cost"]
	if not sim.can_afford(cost):
		hud.toast(Loc.t("city.need_resources"))
		return
	var block: String = sim.placement_block(build_mode, tile)
	if block != "":
		hud.toast(Loc.t(block))
		return
	sim.place_building(build_mode, tile)


func set_build_mode(type_id: String) -> void:
	build_mode = type_id
	view.build_mode = type_id
	if type_id == "":
		hud.set_hint(_default_hint())
		return
	for b in cfg["buildings"]:
		if String(b["id"]) == type_id:
			hud.set_hint(Loc.t("city.build_hint") % _bld_hint(b))


## Подсказка выбранного здания: имя (цена — эффект).
func _bld_hint(b: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in b["cost"]:
		parts.append("%d %s" % [int(b["cost"][key]), Loc.t("res." + key)])
	var desc := Loc.t(String(b["desc"]))
	if b.has("produce"):
		desc = desc % int(b["produce"]["per_day"])
	elif String(b.get("effect", "")) == "storage":
		desc = desc % int(cfg["storage_per_warehouse"])
	elif String(b.get("effect", "")) == "tavern":
		var tcfg: Dictionary = cfg.get("tavern", {})
		desc = desc % int(float(tcfg.get("food_per_day", 8.0)))
	return "%s (%s; %s)" % [Loc.t(String(b["loc"])), ", ".join(parts), desc]


func toggle_pause() -> void:
	sim.paused = not sim.paused
	if sim.paused:
		hud.toast(Loc.t("city.paused"))


## --- Магия (M3): крафт, городские заклинания, зачарование ----------------

## Крафт из панели магии: пара рун по таблице рецептов, только у работающего алтаря.
func craft_spell(rune_a: String, rune_b: String) -> void:
	if rune_a == "" or rune_b == "":
		hud.toast(Loc.t("magic.craft_need_two"))
		return
	if not sim.altar_ready():
		hud.toast(Loc.t("magic.no_altar"))
		return
	var spell_id: String = Game.magic.recipe_result(rune_a, rune_b)
	if spell_id == "":
		hud.toast(Loc.t("magic.craft_none"))
		return
	if Game.has_spell(spell_id):
		hud.toast(Loc.t("magic.craft_known"))
		return
	if Game.count_item(rune_a) < 1 or Game.count_item(rune_b) < 1:
		hud.toast(Loc.t("magic.craft_need_two"))
		return
	Game.remove_item(rune_a, 1)
	Game.remove_item(rune_b, 1)
	Game.learn_spell(spell_id)
	hud.toast(Loc.t("magic.craft_done") % Loc.t("spell." + spell_id))


## Городское заклинание из панели магии (расход — кристаллы из пула).
func cast_city_spell(spell_id: String) -> void:
	var def: Dictionary = Game.magic.spell(spell_id)
	if def.is_empty():
		return
	var err: String = sim.cast_city_spell(def)
	if err == "":
		hud.toast(Loc.t("magic.cast_done") % Loc.t(String(def["loc"])))
	else:
		hud.toast(Loc.t("magic." + err))


## Выбор зачарования в панели; повторное нажатие / ПКМ / Esc отменяет.
func set_enchant_mode(ench_id: String) -> void:
	enchant_mode = "" if enchant_mode == ench_id else ench_id
	view.enchant_mode = enchant_mode
	if enchant_mode == "":
		hud.set_enchant_hint("")
		return
	var def: Dictionary = Game.magic.enchantment(ench_id)
	var target_name := Loc.t("city.any_bld") if String(def.get("target", "any")) == "any" \
			else _bld_name(String(def["target"]))
	hud.set_enchant_hint(Loc.t("magic.enchant_pick") % target_name)


func _try_enchant() -> void:
	var ench_id := enchant_mode
	set_enchant_mode("")
	var bld: Dictionary = sim.building_at(map.tile_of_px(get_global_mouse_position()))
	if bld.is_empty():
		hud.toast(Loc.t("magic.enchant_wrong"))
		return
	var err: String = sim.enchant_building(bld, Game.magic.enchantment(ench_id), Game.inventory)
	if err == "":
		hud.toast(Loc.t("magic.enchant_done") % _bld_name(String(bld["type"])))
	else:
		hud.toast(Loc.t("magic." + err))


## Скорость города: x1/x2/x3 (пункт плана M2). Пауза снимается.
func set_speed(value: int) -> void:
	sim.speed = value
	sim.paused = false


## Комплект героя из оружейки: металл из пула, бонусы урона/брони (M5.1).
func _buy_hero_kit() -> void:
	var err: String = Game.buy_hero_kit(cfg, sim)
	if err == "":
		var kit: Dictionary = Game.hero_kit_bonus(cfg)
		hero.bonus_damage = int(kit["damage"])
		hero.bonus_armor = int(kit["armor"])
		hud.toast(Loc.t("city.armory_bought_toast") % Game.hero_kits)
	elif err == "armory_max":
		hud.toast(Loc.t("city.armory_max_toast"))
	else:
		hud.toast(Loc.t("city.armory_no_metal_toast"))


func _enter_dungeon() -> void:
	sim.speed = 1
	sim.paused = false
	get_tree().change_scene_to_file(DUNGEON_SCENE)


func _default_hint() -> String:
	return "%s   ·   %s" % [Loc.t("city.enter_anomaly"), Loc.t("city.back_hint")]


## Подсветка зданий под курсором в режиме зачарования — рисует view.
func enchant_target_valid(tile: Vector2i) -> bool:
	var def: Dictionary = Game.magic.enchantment(enchant_mode)
	var bld: Dictionary = sim.building_at(tile)
	if def.is_empty() or bld.is_empty() or not bool(bld["done"]):
		return false
	var target := String(def.get("target", "any"))
	return target == "any" or String(bld["type"]) == target


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
