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
var _modulate: CanvasModulate
var _static_body: StaticBody2D
var _near_anomaly := false


func _ready() -> void:
	if Game.city_sim == null:
		Game.new_city()
	sim = Game.city_sim
	sim.paused = false
	map = sim.map
	cfg = _read_json(CITY_CFG_PATH)
	view = load(VIEW_SCRIPT).new()
	view.setup(map, sim, cfg)
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
	hud.set_hint(_default_hint())
	_deposit_loot()


func _spawn_hero() -> void:
	var dungeon_cfg: Dictionary = _read_json("res://data/dungeon.json")
	var hero_script: Script = load(HERO_SCRIPT)
	hero = hero_script.new()
	hero.city_mode = true
	hero.setup(dungeon_cfg["hero"], 0)
	hero.position = map.tile_center_px(map.spawn_tile)
	add_child(hero)
	hero.set_camera_limits(Rect2(0, 0, map.w * map.ts, map.h * map.ts))


## Коллизии героя: вода, скалы и все готовые здания.
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
			blocked[b["tile"]] = true
	for tile: Vector2i in blocked:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(map.ts, map.ts)
		shape.shape = rect
		shape.position = map.tile_center_px(tile)
		_static_body.add_child(shape)


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
	view.queue_redraw()
	hud.refresh()
	_update_daylight()
	_process_events()
	_near_anomaly = hero.position.distance_to(map.tile_center_px(map.anomaly_tile)) < map.ts * 1.7
	if _near_anomaly:
		hud.set_hint(Loc.t("city.enter_anomaly"))
	elif build_mode == "":
		hud.set_hint(_default_hint())


func _process_events() -> void:
	for ev in sim.events:
		var bld_name := _bld_name(String(ev["bld"]))
		match String(ev["type"]):
			"site":
				hud.toast(Loc.t("city.site_started") % bld_name)
			"built":
				hud.toast(Loc.t("city.built_done") % bld_name)
				_rebuild_collision()
			"no_worker":
				hud.toast(Loc.t("city.no_free_worker") % bld_name)
	sim.events.clear()


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _near_anomaly:
		_enter_dungeon()
		return
	if event.is_action_pressed("inventory"):
		hud.toggle_residents()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P:
				toggle_pause()
			KEY_1:
				set_speed(1)
			KEY_2:
				set_speed(2)
			KEY_3:
				set_speed(3)
	if event is InputEventMouseButton and event.pressed and build_mode != "":
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			set_build_mode("")
	elif event.is_action_pressed("ui_cancel"):
		if build_mode != "":
			set_build_mode("")
		elif hud.residents_visible():
			hud.toggle_residents()
		else:
			sim.paused = true
			get_tree().change_scene_to_file(MENU_SCENE)


func _try_place() -> void:
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not sim.is_buildable_tile(tile):
		hud.toast(Loc.t("city.cant_build_here"))
		return
	var cost: Dictionary = {}
	for b in cfg["buildings"]:
		if String(b["id"]) == build_mode:
			cost = b["cost"]
	if not sim.can_afford(cost):
		hud.toast(Loc.t("city.need_resources"))
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
	return "%s (%s; %s)" % [Loc.t(String(b["loc"])), ", ".join(parts), desc]


func toggle_pause() -> void:
	sim.paused = not sim.paused
	if sim.paused:
		hud.toast(Loc.t("city.paused"))


## Скорость города: x1/x2/x3 (пункт плана M2). Пауза снимается.
func set_speed(value: int) -> void:
	sim.speed = value
	sim.paused = false


func _enter_dungeon() -> void:
	sim.speed = 1
	sim.paused = false
	get_tree().change_scene_to_file(DUNGEON_SCENE)


func _default_hint() -> String:
	return "%s   ·   %s" % [Loc.t("city.enter_anomaly"), Loc.t("city.back_hint")]


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
