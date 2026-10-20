extends Node2D
## Сцена карты мира (M8): туман войны, точки интереса, путешествие по дням.
## Выбрал точку — герой идёт N дней, мир и город тем временем живут
## (решение заказчика: время пути по дням, как в RimWorld).
## Логика мира — world_map.gd/world_sim.gd, сцена только показывает и слушает.

const WORLD_CFG_PATH := "res://data/world.json"
const CITY_SCENE := "res://scenes/city.tscn"
const DUNGEON_SCENE := "res://scenes/dungeon.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const VIEW_SCRIPT := "res://scripts/world_view.gd"
const HUD_SCRIPT := "res://scripts/world_hud.gd"

var map = null                  # world_map.gd
var sim = null                  # world_sim.gd
var cfg: Dictionary = {}
var view: Node2D = null
var hud: CanvasLayer = null
var camera: Camera2D = null

var hero_tile := Vector2i.ZERO  # тайл героя на карте мира
var hero_px := Vector2.ZERO
var selected: Dictionary = {}   # выбранный POI (панель справа)
var travel := {}                # {path, days, px_done, px_total, day_mark}
var _near_poi: Dictionary = {}  # POI у ног героя (действие E)
var fauna = null                # мирная фауна и хищники (M14-C, T01)
const FAUNA_CFG_PATH := "res://data/fauna.json"
const FAUNA_SCRIPT := "res://scripts/world_fauna.gd"


func _ready() -> void:
	cfg = _read_json(WORLD_CFG_PATH)
	if Game.world_map == null or Game.world_sim == null:
		Game.new_world()
	map = Game.world_map
	sim = Game.world_sim
	Game.world_active = true   # «Продолжить» из меню вернёт на карту мира
	Game.in_dungeon = false    # вышли из данжа на карту — автосейв снова работает
	if Game.city_sim != null:
		Game.city_sim.paused = false   # город живёт, пока герой на большой карте
	# мирная фауна (M14-C/T01): олени, кабаны, птицы, волки, рыба
	fauna = load(FAUNA_SCRIPT).new()
	fauna.setup(map, _read_json(FAUNA_CFG_PATH), randi())
	# вернулись из локации — герой там, где вошёл; иначе у города
	if Game.world_hero_tile.x >= 0 and map.in_bounds(Game.world_hero_tile):
		hero_tile = Game.world_hero_tile
	else:
		hero_tile = map.city_tile
	Game.world_hero_tile = Vector2i(-1, -1)
	hero_px = map.tile_center_px(hero_tile)
	_reveal(hero_tile)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map.w * map.ts
	camera.limit_bottom = map.h * map.ts
	camera.position = hero_px
	add_child(camera)
	camera.make_current()

	view = load(VIEW_SCRIPT).new()
	view.setup(map)
	add_child(view)

	hud = load(HUD_SCRIPT).new()
	hud.init(self)
	add_child(hud)
	hud.set_hint(Loc.t("world.hint"))


func _process(delta: float) -> void:
	_update_travel(delta)
	if fauna != null:
		fauna.update(delta, hero_px)
	camera.position = hero_px
	view.hero_px = hero_px
	view.hero_tile = hero_tile
	view.queue_redraw()
	hud.refresh()
	_update_near_poi()


## Открытие тайла (M14-C/T13): на исследованном земле радиус полный,
## в тумане — уменьшенный ((cfg -> fog_reveal_radius)). Заодно подкидывает
## фауну возле открытых тайлов.
func _reveal(tile: Vector2i) -> void:
	var full := int(cfg.get("reveal_radius", 5))
	var radius := full if map.is_explored(tile) else int(cfg.get("fog_reveal_radius", 2))
	map.reveal_around(tile, radius)
	if fauna != null:
		fauna.try_spawn_near(tile)


## Идём ли мы и на что наступили — рядом с каким POI герой стоит.
func _update_near_poi() -> void:
	# зверь рядом — подсказка охоты/рыбалки важнее POI (M14-C/T01)
	if fauna != null:
		var prey: Dictionary = fauna.interact_check(hero_px)
		if not prey.is_empty():
			hud.set_hint(Loc.t("world.hint_fish" if String(prey["behavior"]) == "fish" else "world.hint_hunt")
					% Loc.t("fauna." + String(prey["kind"])))
			return
	_near_poi = map.poi_at(hero_tile)
	if _near_poi.is_empty():
		# соседний тайл тоже считается (POI занимают один тайл)
		for n in [hero_tile + Vector2i(1, 0), hero_tile + Vector2i(-1, 0),
				hero_tile + Vector2i(0, 1), hero_tile + Vector2i(0, -1)]:
			var poi: Dictionary = map.poi_at(n)
			if not poi.is_empty():
				_near_poi = poi
				break
	if not _near_poi.is_empty():
		hud.set_hint(_poi_hint(_near_poi))


func _update_travel(delta: float) -> void:
	if travel.is_empty():
		return
	var path: Array = travel["path"]
	var step: float = float(cfg["hero_speed"]) * delta
	while step > 0.0 and path.size() > 1:
		var next: Vector2 = map.tile_center_px(path[1])
		var to_next: Vector2 = next - hero_px
		var dist := to_next.length()
		if dist <= step:
			hero_px = next
			step -= dist
			path.remove_at(1)
			hero_tile = path[0]
			_reveal(hero_tile)
			_scout_tracks()
		else:
			hero_px += to_next / dist * step
			step = 0.0
	travel["px_done"] = float(travel["px_done"]) + float(cfg["hero_speed"]) * delta
	# граница дня: мир живёт, пока герой идёт (дни пути — решение заказчика);
	# последний день засчитывается на финише — однодневный переход тоже тикает мир
	var day_now := int(floorf(float(travel["px_done"]) / maxf(1.0, float(travel["px_total"])) * float(travel["days"]) + 0.0001))
	while int(travel["day_mark"]) < day_now and int(travel["day_mark"]) < int(travel["days"]):
		travel["day_mark"] = int(travel["day_mark"]) + 1
		_advance_world_day()
	if path.size() <= 1:
		_finish_travel()


func _advance_world_day() -> void:
	var evs: Array = sim.advance_day()
	for ev: Dictionary in evs:
		hud.toast(_event_text(ev))
	_flush_chronicle()
	if Game.city_sim != null:
		Game.city_sim.advance_days(1)


## Охота/рыбалка (M14-C/T01): E у зверя — добыча через стандартный лут.
func _try_hunt() -> bool:
	if fauna == null:
		return false
	var result: Dictionary = fauna.interact(hero_px)
	if result.is_empty():
		return false
	var kind := String(result["kind"])
	var parts := PackedStringArray()
	for drop: Dictionary in result["drops"]:
		Game.add_item(String(drop["id"]), int(drop["count"]))
		parts.append("%s ×%d" % [Loc.t("item." + String(drop["id"])), int(drop["count"])])
	hud.toast(Loc.t("world.hunt_got") % [Loc.t("fauna." + kind), ", ".join(parts)])
	if Game.city_sim != null:
		Game.city_sim.chronicle_add("chron.hunt", Loc.t("fauna." + kind))
	return true


## Следы (M12): на каждом шаге герой затирает след под ногами и высматривает
## чужие следы — возле цепочки неоткрытого гнезда открывается путь к нему.
func _scout_tracks() -> void:
	var res: Dictionary = sim.track_scout(hero_tile)
	if bool(res["found"]):
		hud.toast(Loc.t("world.track_found"))
		view.queue_redraw()
	if bool(res["wiped"]):
		view.queue_redraw()


## Мировая летопись уходит в общую городскую (единый журнал M4).
## Аргументы — сырые id (kind, фракция): переводим здесь, у сцены есть Loc.
func _flush_chronicle() -> void:
	if Game.city_sim == null:
		sim.chronicle.clear()
		return
	var factions := ["traders", "bandits", "cult"]
	for e: Dictionary in sim.chronicle:
		var a := String(e["a"])
		var b := String(e["b"])
		if a != "":
			a = Loc.t("world.poi." + a)
		if b != "":
			b = Loc.t("world.faction." + b) if b in factions else Loc.t("world.poi." + b)
		Game.city_sim.chronicle_add(String(e["key"]), a, b)
	sim.chronicle.clear()


func _finish_travel() -> void:
	# дозасчитываем дни, которые не успели тикнуть из-за округления кадра:
	# каждый запланированный день пути прожит миром и городом
	while int(travel["day_mark"]) < int(travel["days"]):
		travel["day_mark"] = int(travel["day_mark"]) + 1
		_advance_world_day()
	travel = {}
	hero_tile = map.tile_of_px(hero_px)
	_reveal(hero_tile)
	var poi: Dictionary = map.poi_at(hero_tile)
	if poi.is_empty():
		return
	hud.toast(Loc.t("world.arrived") % Loc.t("world.poi." + String(poi["kind"])))
	match String(poi["kind"]):
		"caravan", "settlement":
			if sim.is_trade_poi(poi):
				hud.open_trade(poi)
		"obelisk":
			_touch_obelisk(poi)


# --- ввод ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		# фауна ближе POI: охота/рыбалка (M14-C/T01)
		if _try_hunt():
			return
		if not _near_poi.is_empty():
			_use_poi(_near_poi)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click_map(map.tile_of_px(get_global_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				_cancel()


func _cancel() -> void:
	if not travel.is_empty():
		travel = {}
		hud.toast(Loc.t("world.travel_cancel"))
		return
	if hud.trade_visible():
		hud.close_trade()
		return
	if not selected.is_empty():
		selected = {}
		view.selected_tile = Vector2i(-1, -1)
		hud.close_poi_panel()
		return
	# Esc (фидбек заказчика 2026-10-20): как раньше — сразу в меню
	if Game.city_sim != null:
		Game.city_sim.paused = true
	Game.menu_hero_tile = hero_tile
	Game.menu_hero_hp = -1
	Game.menu_hero_mana = -1
	get_tree().change_scene_to_file(MENU_SCENE)


func _click_map(tile: Vector2i) -> void:
	if not travel.is_empty():
		return
	var poi: Dictionary = map.poi_at(tile)
	if not poi.is_empty() and bool(poi["discovered"]):
		_select_poi(poi)
		return
	if not map.in_bounds(tile):
		return
	if not map.is_walkable(tile):
		hud.toast(Loc.t("world.impassable"))
		return
	# туман (M14-C/T13): маршрут прокладывается и в неисследованное — так
	# карта и открывается; радиус открытия в тумане меньше (см. _reveal)
	start_travel_to(tile)


## Выбор точки интереса: панель с описанием и кнопками пути/входа.
func _select_poi(poi: Dictionary) -> void:
	selected = poi
	view.selected_tile = poi["tile"]
	hud.open_poi_panel(poi, map.travel_days(hero_tile, poi["tile"]))


## Собраться в путь (кнопка панели или клик по земле).
func start_travel_to(tile: Vector2i) -> void:
	if tile == hero_tile:
		hud.toast(Loc.t("world.already_here"))
		return
	var path: Array = map.tile_path(hero_tile, tile)
	if path.is_empty():
		hud.toast(Loc.t("world.no_path"))
		return
	var days: int = map.travel_days(hero_tile, tile)
	var px_total := 0.0
	for i in range(1, path.size()):
		px_total += map.tile_center_px(path[i - 1]).distance_to(map.tile_center_px(path[i]))
	travel = {"path": path, "days": days, "px_done": 0.0, "px_total": px_total, "day_mark": 0}
	selected = {}
	view.selected_tile = Vector2i(-1, -1)
	hud.close_poi_panel()
	hud.toast(Loc.t("world.travel_toast") % days)


## Действие E у точки интереса.
func _use_poi(poi: Dictionary) -> void:
	match String(poi["kind"]):
		"city":
			_enter_city()
		"obelisk":
			_touch_obelisk(poi)
		"caravan", "settlement":
			if sim.is_trade_poi(poi):
				hud.open_trade(poi)
			else:
				_enter_location(poi)   # павшее поселение — там лагерь бандитов
		"trade_camp":
			_enter_trade_camp(poi)
		"dungeon", "ruins", "camp", "dragon_castle":
			if sim.poi_enterable(poi):
				_enter_location(poi)
			else:
				hud.toast(Loc.t("world.cleared") % _reset_left(poi))


## Войти в лагерь торговцев «гуляй-город» (M10): телеги по кругу, костёр,
## торговцы — торговля с ценами каравана.
func _enter_trade_camp(poi: Dictionary) -> void:
	Game.world_hero_tile = poi["tile"]
	Game.poi_id = int(poi["id"])
	get_tree().change_scene_to_file("res://scenes/trade_camp.tscn")


func _reset_left(poi: Dictionary) -> int:
	var left: int = int(cfg.get("sim", {}).get("dungeon_reset_days", 10)) \
			- (sim.day - int(poi["cleared_day"]))
	return maxi(1, left)


## Войти в город: герой появляется у того края города, с которого пришёл
## (фидбек приёмки M8: точки старта симметричны). На 2 тайла внутрь рамки,
## чтобы сразу не сработал обратный переход.
func _enter_city() -> void:
	Game.world_hero_tile = Vector2i(-1, -1)
	var cmap = Game.city_sim.map
	var d: Vector2i = hero_tile - map.city_tile
	var dir := Vector2i(-1, 0)   # герой у самого города — западные ворота (арка)
	if d != Vector2i.ZERO:
		if absi(d.x) >= absi(d.y):
			dir = Vector2i(1 if d.x > 0 else -1, 0)
		else:
			dir = Vector2i(0, 1 if d.y > 0 else -1)
	var target := Vector2i(2, cmap.h / 2)
	if dir.x > 0:
		target = Vector2i(cmap.w - 3, cmap.h / 2)
	elif dir.y < 0:
		target = Vector2i(cmap.w / 2, 2)
	elif dir.y > 0:
		target = Vector2i(cmap.w / 2, cmap.h - 3)
	Game.city_return_tile = cmap.nearest_walkable(target)
	get_tree().change_scene_to_file(CITY_SCENE)


## Войти в локацию боевой точки: данж генерируется как сейчас (пункт плана M8).
## Лагеря бандитов и павшие поселения — биом «лагерь бандитов» (M10): там
## гуманоиды-бандиты (орки), а не живность.
func _enter_location(poi: Dictionary) -> void:
	Game.return_scene = "res://scenes/world.tscn"
	Game.world_hero_tile = poi["tile"]
	Game.poi_id = int(poi["id"])
	Game.forced_biome = String(poi["biome"])
	Game.dungeon_scale = 1.0
	Game.poi_coins = 0
	match String(poi["kind"]):
		"ruins":
			Game.dungeon_scale = 0.5
			Game.poi_coins = sim.coin_reward(poi)
		"camp":
			# строители гнезда укрепляют лагерь — масштаб растёт с уровнем (M12)
			Game.dungeon_scale = sim.location_scale(poi)
			Game.forced_biome = "bandit_camp"
			Game.poi_coins = sim.coin_reward(poi)
		"settlement":
			Game.dungeon_scale = sim.location_scale(poi)
			Game.forced_biome = "bandit_camp"
			Game.poi_coins = sim.coin_reward(poi)
		"dragon_castle":
			# логово древнего дракона (M13): гуща врагов и богатая сокровищница
			Game.dungeon_scale = 1.4
			Game.poi_coins = sim.coin_reward(poi)
	get_tree().change_scene_to_file(DUNGEON_SCENE)


## Обелиск: открывает далёкие места (ответ №24).
func _touch_obelisk(poi: Dictionary) -> void:
	for ev: Dictionary in sim.touch_obelisk(int(poi["id"])):
		hud.toast(Loc.t("world." + String(ev["type"])))


## Текст события мира для тоста.
func _event_text(ev: Dictionary) -> String:
	match String(ev["type"]):
		"siege_start":
			return Loc.t("world.siege_start") % [Loc.t("world.faction.bandits"), Loc.t("world.poi." + String(ev["b"]))]
		"siege_fell":
			return Loc.t("world.siege_fell") % Loc.t("world.poi." + String(ev["a"]))
		"siege_repelled":
			return Loc.t("world.siege_repelled") % Loc.t("world.poi." + String(ev["a"]))
		"resettle":
			return Loc.t("world.resettle") % [Loc.t("world.poi." + String(ev["a"])), Loc.t("world.faction." + String(ev["b"]))]
		"poi_reborn":
			return Loc.t("world.poi_reborn") % Loc.t("world.poi." + String(ev["a"]))
		"caravan_moved":
			return Loc.t("world.caravan_moved")
	return ""


func _poi_hint(poi: Dictionary) -> String:
	var kind := String(poi["kind"])
	match kind:
		"city":
			return Loc.t("world.hint_enter_city")
		"obelisk":
			return Loc.t("world.hint_obelisk") if not bool(poi["used"]) else Loc.t("world.obelisk_used")
		"caravan", "settlement":
			if String(poi["state"]) == "fallen":
				return Loc.t("world.hint_enter_loc")
			return Loc.t("world.hint_trade")
		"trade_camp":
			return Loc.t("world.hint_trade_camp")
		"dungeon", "ruins", "camp", "dragon_castle":
			if not sim.poi_enterable(poi):
				return Loc.t("world.cleared") % _reset_left(poi)
			if kind == "camp" and int(poi.get("nest_level", 0)) > 0:
				return "%s • %s" % [Loc.t("world.hint_enter_loc"),
						Loc.t("world.nest_level") % int(poi["nest_level"])]
			return Loc.t("world.hint_dragon_castle") if kind == "dragon_castle" \
					else Loc.t("world.hint_enter_loc")
	return Loc.t("world.hint")


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
