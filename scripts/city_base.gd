# Часть: сцена города — переменные-режимы, _ready, крафт, герой, покадровый _process.
# Структура v1.62.0: бывший city.gd (1979 строк) разрезан на extends-цепочку
# Node2D (city_base -> city_events -> city_input -> city.gd) — это один класс,
# сцена scenes/city.tscn по-прежнему ссылается на city.gd. Поведение не меняется.
extends Node2D

## Город (M2): карта, стройка мышью, жители-статисты, пул ресурсов,
## переключение город↔данж у аномалии, пауза и скорость x1/x2/x3.
## Симуляция живёт в Game и тикается сама — сцена только показывает и слушает ввод.

const DUNGEON_SCENE := "res://scenes/dungeon.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const CITY_CFG_PATH := "res://data/city.json"
const HERO_SCRIPT := "res://scripts/hero.gd"
const VIEW_SCRIPT := "res://scripts/city_view.gd"
const HUD_SCRIPT := "res://scripts/city_hud.gd"
const SKY := preload("res://scripts/city_sky.gd")  # статические функции фаз

var sim = null
var map = null
var cfg: Dictionary = {}
var hero = null
var view: Node2D = null
var hud: CanvasLayer = null
var guest := false   # герой в поселении НПС («Мир v2», этап 3): смотрит и
                     # торгует, но не строит и не управляет чужим городом

var build_mode := ""            # выбранный тип здания для стройки
var enchant_mode := ""          # выбранное зачарование (M3): клик по зданию применит
var zone_mode := ""             # инструмент зоны (M6): "field" | "pasture"
var road_mode := false          # инструмент дороги (M6)
var plant_mode := false         # инструмент посадки леса (M11)
var move_mode := false          # инструмент переноса зданий (этап 2, аспект 5)
var plaza_mode := false         # перенос главной площади (правки v1.20)
var _move_bld: Dictionary = {}  # здание, снятое для переноса; {} — не выбрано
var _dragging := false          # ЛКМ зажата — выделение зоны или рисование дороги
var _drag_from := Vector2i(-1, -1)
var _drag_to := Vector2i(-1, -1)
var _road_warned := false       # тост «нет камня» не спамит при рисовании
var _modulate: CanvasModulate
var _static_body: StaticBody2D
var _terrain: Node2D = null     # статический слой ландшафта (перерисовка по dirty, M11)
var _water: Node2D = null       # живая вода «Природы 2.0» (v1.39.0)
var _near_anomaly := false
var _near_armory: Dictionary = {}   # оружейка рядом с героем (E — комплект героя)
var _equip_panel = null         # панель экипировки и крафта (M14-B, клавиша I)
var _gov_panel = null           # панель управления: законы/вера/дипломатия (M14-H, L)
var _quests_panel = null        # доска объявлений (M14-K, клавиша Q)
var _overview = null            # обзорная карта города (v1.51, клавиша N)
var _notices = null             # донесения-письма (v1.53, справа)
var _menu_layer: CanvasLayer = null  # меню-оверлей (v1.54: Esc больше НЕ
                                     # пересоздаёт сцену — город под паузой)
var _codex_panel = null         # кодекс и статистика (M14-K, клавиша K)
var _ambience = null            # светлячки и огоньки (M14-C, T21/T23)
var _weather_fx = null          # погода: дождь/снег/туман/буря (M14-J)
var _sky_shadows: Node2D = null # тени от солнца/луны (v1.27)
var _sky: Node2D = null         # небо: солнце/луна/звёзды, характер дня (v1.27)
var _near_temple := false       # храм рядом — E: молитва (M14-H)
var _hero_tree: Dictionary = {} # дерево у ног героя (E — рубить, правки v1.12.2)
var _hero_rock: Dictionary = {} # скала/руда рядом (E — добыть)
var _hero_crop: Dictionary = {} # спелая грядка рядом (E — собрать, этап 2, аспект 3)
var _hero_sow: Dictionary = {}  # пустая клетка поля рядом (E — посеять, 2026-10-21)
var _hero_till: Dictionary = {} # невспаханная клетка зоны рядом (E — вспахать)
var _hero_haul: Dictionary = {} # куча ресурса у здания рядом (E — на склад, 2026-10-21)
var _pick_zone_id := -1         # id поля, в котором меняем культуру
var _hero_site: Dictionary = {} # недострой рядом (E — помочь)
var _hero_repair_bld: Dictionary = {}   # повреждённое здание/руины рядом (E — ремонт, этап 2, аспект 5)
var _hero_work_cd := 0.0        # кулдаун удара героя по природе/стройке


func _ready() -> void:
	# v1.41 («Мир v2», этап 3, №120): поселение НПС — та же сцена города,
	# но герой в гостях: живёт их симуляция, монеты — их кошелёк
	guest = Game.visiting_city_id >= 0 and Game.npc_cities != null \
			and Game.npc_cities.city_of(Game.visiting_city_id) != null
	if guest:
		sim = Game.npc_cities.city_of(Game.visiting_city_id)
	else:
		if Game.city_sim == null:
			Game.new_city()
		sim = Game.city_sim
	sim.paused = false
	get_tree().paused = false   # v1.30.1: после смерти в данже пауза не должна протекать в город
	Game.in_dungeon = false   # герой в городе — автосейв и «Сохранить» доступны
	if guest:
		# кошелёк города НПС уже подшит (npc_cities.attach_wallet) — не лезем
		# в монеты героя; world_active остаётся true: герой «на карте мира»
		# у поселения, «Продолжить» из меню вернёт к поселению
		pass
	else:
		# монеты общие с героем (M10): симуляция кладёт/берёт через колбэки
		sim.coins_sink = func(n: int) -> void: Game.coins += n
		sim.coins_source = func() -> int: return Game.coins
		Game.world_active = false   # вернулись в город — «Продолжить» откроет город
	map = sim.map
	cfg = _read_json(CITY_CFG_PATH)
	view = load(VIEW_SCRIPT).new()
	# статический ландшафт — отдельным слоем под динамикой (M9, 60 FPS)
	_terrain = load("res://scripts/city_terrain.gd").new()
	_terrain.setup(map, cfg, sim, "player" if Game.poi_id == 0 else "npc:%d" % Game.poi_id)
	add_child(_terrain)
	# живая вода «Природы 2.0» (v1.39.0): анимация/пена/рябь/камыши —
	# над запечённой землёй, под тенями и жителями
	_water = load("res://scripts/water_terrain.gd").new()
	_water.setup(_terrain, _terrain.colors)
	add_child(_water)
	# тени солнечного цикла (v1.27): под объектами, над ландшафтом
	_sky_shadows = SKY.new()
	_sky_shadows.mode = "shadows"
	_sky_shadows.setup(map, sim, cfg)
	add_child(_sky_shadows)
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
	# светлячки и болотные огоньки (M14-C/T21/T23): VFX ночи без просадки FPS
	_ambience = load("res://scripts/city_ambience.gd").new()
	_ambience.setup(map)
	add_child(_ambience)
	# погода (M14-J): дождь/снег/туман/пепельная буря поверх мира
	_weather_fx = load("res://scripts/city_weather.gd").new()
	add_child(_weather_fx)
	# небо (v1.27): солнце/луна/звёзды и свечение рассветов-закатов поверх
	_sky = SKY.new()
	_sky.mode = "sky"
	_sky.setup(map, sim, cfg)
	add_child(_sky)
	hud = load(HUD_SCRIPT).new()
	hud.init(sim, self, cfg, guest)
	add_child(hud)
	hud.set_enchant_colors(_enchant_colors())
	hud.set_hint(_default_hint())
	# соло-старт (правки v1.12.2): герой видит рядом NPC — это и есть единственный
	# житель, основатель-староста. Объясняем сразу, чтобы не гадать.
	if not guest and sim.residents.size() == 1:
		hud.toast(Loc.t("city.founder_hint"))
	if guest:
		hud.toast(Loc.t("city.guest_banner"))
	hero.died.connect(_on_hero_down)
	if not guest:
		_deposit_loot()   # лут из данжа выгружается только в своём городе
	# панель экипировки (M14-B, клавиша I): в городе ещё и крафт у мастеровых
	_equip_panel = load("res://scripts/equipment_panel.gd").new()
	_equip_panel.hero_cb = func(): return hero
	_equip_panel.toast_cb = func(msg: String) -> void: hud.toast(msg)
	_equip_panel.on_change = func() -> void:
		hero.set_equipment_bonuses(Game.equipment_bonuses())
	_equip_panel.craft_cb = _craft_item
	_equip_panel.cast_scroll_cb = _cast_scroll   # v1.49: свитки работают и в городе
	add_child(_equip_panel)
	# панель управления (M14-H, клавиша L): законы, вера, дипломатия
	_gov_panel = load("res://scripts/governance_panel.gd").new()
	add_child(_gov_panel)
	# доска объявлений (M14-K, клавиша Q)
	_quests_panel = load("res://scripts/quests_panel.gd").new()
	add_child(_quests_panel)
	# кодекс и статистика (M14-K, клавиша K)
	_codex_panel = load("res://scripts/codex_panel.gd").new()
	add_child(_codex_panel)
	# обзорная карта города (v1.51, клавиша N): вся локация с ресурсами
	_overview = load("res://scripts/city_overview.gd").new()
	_overview.setup(map, sim)
	_overview.hero_cb = func(): return hero
	add_child(_overview)
	# донесения-письма (v1.53): крупные события справа, читается/закрывается
	_notices = load("res://scripts/notice_feed.gd").new()
	add_child(_notices)
	# v1.55: ежедневное соперничество регионов — события уходят ПИСЬМАМИ
	if not guest and Game.npc_cities != null:
		sim.rivalry_cb = func() -> void:
			for ev in Game.npc_cities.rivalry_day(sim):
				_letter(String(ev["type"]), _region_text(ev))
			# v1.60: караваны и союзные походы — письма из той же серии
			for ev2 in Game.npc_cities.trade_day(sim):
				_letter(String(ev2["type"]), _region_text(ev2))


## Крафт предмета (M14-B/T05): оружейка куёт оружие и броню, мастерская —
## аксессуары, свитки и зелья. "" — успех, иначе ключ локализации.
func _craft_item(item_id: String) -> String:
	var item: Dictionary = Game.item_def(item_id)
	var where := String(item.get("craft", {}).get("where", "armory"))
	var near_armory := _near_building_kind("armory")
	var near_workshop := _near_building_kind("workshop")
	return Game.craft_item(item_id, sim, where == "armory" and near_armory,
			where == "workshop" and near_workshop)


## Готовое здание типа type_id в двух тайлах от героя (до прямоугольника 2×2)?
func _near_building_kind(type_id: String) -> bool:
	for b in sim.buildings:
		if sim._active(b) and String(b["type"]) == type_id \
				and sim.bld_dist_px(hero.position, b) < map.ts * 2.2:
			return true
	return false


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
	# вернулись из мира (M8): герой появляется у края, откуда выходил
	if Game.city_return_tile.x >= 0 and map.in_bounds(Game.city_return_tile):
		hero.position = map.tile_center_px(Game.city_return_tile)
	# HP из сейва (M14-A): город лечит только до начала игры, сейв честнее
	if Game.hero_saved_hp >= 0:
		hero.hp = mini(Game.hero_saved_hp, hero.hp_max())
		Game.hero_saved_hp = -1
	# экипировка (M14-B): бонусы брони/аксессуара применяются при спавне
	hero.set_equipment_bonuses(Game.equipment_bonuses())
	_apply_resource_hero_bonuses()   # v1.57: кристалл лича / кровь вампира
	add_child(hero)
	hero.set_camera_limits(Rect2(0, 0, map.w * map.ts, map.h * map.ts))


## Коллизии героя: вода, скалы и все готовые здания. Ворота — дверь:
## герой и жители проходят всегда, запираются ворота только для мутантов
## (v1.26, правка приёмки); руины — обломки, герой проходит сквозь них.
func _rebuild_collision() -> void:
	for child in _static_body.get_children():
		child.queue_free()
	var blocked := {}
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			# v1.29.1 (правки приёмки): всё непроходимое для жителей — то же
			# для героя (вода, скала, РУДНАЯ ЖИЛА, выработанная порода);
			# раньше руда в список не попадала — малые жилы проходились
			# насквозь (замечание заказчика). Мост (M14-I) стоит на воде
			# и не блокирует проход.
			if not map.is_nature_walkable(t) and not map.bridges.has(t):
				blocked[t] = true
	for b in sim.buildings:
		if sim._active(b):
			if _bld_effect(b) == "gate":
				continue   # ворота проходимы для героя всегда (v1.26)
			if _bld_effect(b) == "bridge":
				continue
			# здание 2×2: сплошной весь прямоугольник (этап 2, аспект 2)
			for cell in sim.bld_cells(b):
				blocked[cell] = true
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


var _hud_refresh_accum := 0.0     # троттлинг HUD (v1.21): панели не чаще 4 раз/сек
var _terrain_redraw_accum := 0.0  # ландшафт перерисовывается не чаще 2 раз/сек
var _hero_last_land := Vector2(-99999, -99999)  # последняя точка героя на суше (вода непроходима)
var _baked_grid_ver := -1   # версия сетки, на которую запечена земля (v1.28.1)


func _process(delta: float) -> void:
	# v1.54: меню-оверлей закрыли изнутри меню — снимаем слой и паузу
	if _menu_layer != null and not Game.menu_overlay:
		_menu_layer.queue_free()
		_menu_layer = null
		sim.paused = false
	# герой в городе: мутанты могут гнаться за ним (M5)
	if not hero.dead:
		sim.hero_pos = hero.global_position
		sim.hero_alive = true
	# меч героя и ландшафт меняются — перерисовываем точечно
	hero.queue_redraw()
	# болотная зона города (M14-I): тайлы у воды вязнут — герой медленнее.
	# v1.29.2: ВОДА непроходима для всех целиком (брод отменён) — героя не
	# пускаем ни в реку, ни в болото, ни в озеро; мост разрешает.
	hero.city_speed_mult = _hero_ground_mult(hero.position)
	var hero_tile: Vector2i = map.tile_of_px(hero.position)
	if _hero_in_water(hero_tile):
		hero.position = _hero_last_land
		hero.velocity = Vector2.ZERO
	else:
		_hero_last_land = hero.position
	# правки v1.21 (фризы/FPS): полная перерисовка ландшафта — событие редкое,
	# но раньше рубка каждого дерева роняла кадр; теперь не чаще 2 раз/сек.
	# v1.22: в духовке также зоны/дороги/плиты площади — sim.static_dirty
	# (клетка зоны обустроена, дорога построена, площадь перенесена)
	if sim.terrain_dirty or sim.static_dirty:
		_terrain_redraw_accum += delta
		if _terrain_redraw_accum >= 0.5:
			_terrain_redraw_accum = 0.0
			var trees_changed: bool = sim.terrain_dirty
			var grid_ver: int = int(sim.map.grid_ver)
			# v1.28.1: земля перевыпекается ТОЛЬКО при смене маски скал
			# (grid_ver); деревья/саженцы в землю не запечены с M12.
			# Спил/рост деревьев — только кэши видов (view/тени).
			_terrain.rebake(grid_ver != _baked_grid_ver, grid_ver, sim.map.edited)
			sim.map.edited.clear()
			_baked_grid_ver = grid_ver
			sim.terrain_dirty = false
			sim.static_dirty = false
			if trees_changed:
				view.mark_trees_dirty()   # деревья ушли в сортированный слой (M12)
				_sky_shadows.rebuild()    # кэш теней тоже устарел (v1.27)
	else:
		_terrain_redraw_accum = 0.0
	view.queue_redraw()
	# HUD (v1.21): refresh каждый кадр перелопачивал тексты лейблов и ронял
	# FPS — обновляем панели 4 раза в секунду, подсказка у курсора — как раньше
	_hud_refresh_accum += delta
	if _hud_refresh_accum >= 0.25:
		_hud_refresh_accum = 0.0
		hud.refresh()
	_update_daylight()
	if _weather_fx != null:
		_weather_fx.weather = sim.weather
		_weather_fx.season = sim.season()
		_weather_fx.night = _night_amount()
		_weather_fx.map_span = Vector2(sim.map.w * sim.map.ts, sim.map.h * sim.map.ts)
	_process_events()
	_update_hover()
	# герой не проваливается за край: позиция зажата в границах карты,
	# а шаг на крайнюю рамку (1 тайл) переносит на карту мира (M8, фидбек)
	var half: float = map.ts * 0.5
	hero.position = Vector2(
			clampf(hero.position.x, half, map.w * map.ts - half),
			clampf(hero.position.y, half, map.h * map.ts - half))
	var border: Vector2i = map.border_dir(map.tile_of_px(hero.position))
	if border != Vector2i.ZERO:
		_exit_to_world(border)
		return
	_near_anomaly = not guest \
			and hero.position.distance_to(map.tile_center_px(map.anomaly_tile)) < map.ts * 1.7
	_near_armory = {} if guest else _armory_near_hero()
	_near_temple = not guest and _near_building_kind("temple")
	# ручной труд героя (правки v1.12.2): что можно потрогать по E
	# (в чужом поселении герой не работает — «Мир v2», этап 3)
	_hero_work_cd = maxf(0.0, _hero_work_cd - delta)
	_hero_site = {} if guest else sim.hero_site_near(hero.position)
	_hero_tree = {} if guest else sim.hero_tree_near(hero.position)
	_hero_rock = {} if guest else sim.hero_rock_near(hero.position)
	_hero_crop = {} if guest else sim.hero_harvest_near(hero.position)
	_hero_sow = {} if guest else sim.hero_sow_near(hero.position)
	_hero_till = {} if guest else sim.hero_till_near(hero.position)
	_hero_haul = {} if guest else sim.hero_haul_near(hero.position)
	_hero_repair_bld = {} if guest else sim.hero_repair_near(hero.position)
	if _near_map_border():
		hud.set_hint(Loc.t("city.exit_world"))
	elif _near_anomaly:
		if Game.dungeon_available(sim.day_number()):
			hud.set_hint(Loc.t("city.enter_anomaly"))
		else:
			hud.set_hint(Loc.t("city.dungeon_locked_hint") % (Game.dungeon_lock_day - sim.day_number()))
	elif not _near_armory.is_empty():
		hud.set_hint(Loc.t("city.armory_hint") % int(cfg.get("hero_kit", {}).get("cost_metal", 3)))
	elif _near_temple:
		hud.set_hint(Loc.t("city.temple_hint"))
	elif not _hero_site.is_empty():
		var site_work: float = maxf(1.0, float(sim._def(_hero_site)["build_work"]))
		hud.set_hint(Loc.t("city.hint_build") % int(100.0 * clampf(float(_hero_site["progress"]) / site_work, 0.0, 1.0)))
	elif not _hero_repair_bld.is_empty():
		hud.set_hint(Loc.t("city.repair_hint") % [_bld_name(String(_hero_repair_bld["type"])),
				_cost_str(sim.repair_cost(String(_hero_repair_bld["type"])))])
	elif not _hero_haul.is_empty():
		hud.set_hint(Loc.t("city.hint_haul") % _bld_name(String(_hero_haul["type"])))
	elif not _hero_tree.is_empty():
		hud.set_hint(Loc.t("city.hint_chop") % [int(_hero_tree["hits"]), int(_hero_tree["need"])])
	elif not _hero_rock.is_empty():
		hud.set_hint(Loc.t("city.hint_mine_ore" if String(_hero_rock["kind"]) == "ore" else "city.hint_mine"))
	elif not _hero_crop.is_empty():
		hud.set_hint(Loc.t("city.hint_harvest"))
	elif not _hero_sow.is_empty():
		hud.set_hint(Loc.t("city.hint_sow"))
	elif not _hero_till.is_empty():
		hud.set_hint(Loc.t("city.hint_till"))
	elif build_mode == "":
		hud.set_hint(_default_hint())


## Вода в 2 тайлах — «влажная низина» города (болотная зона, M14-I).
func _near_water(pos: Vector2) -> bool:
	var t: Vector2i = map.tile_of_px(pos)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var n := t + Vector2i(dx, dy)
			if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER:
				return true
	return false


## Скорость героя по грунту: мост — как по земле, брод-мелководье — 0.55
## (переход вброд), у воды — влажная низина (v1.31).
func _hero_ground_mult(pos: Vector2) -> float:
	var t: Vector2i = map.tile_of_px(pos)
	if map.bridges.has(t):
		return 1.0
	if map.fords.has(t):
		return 0.55
	return 0.7 if _near_water(pos) else 1.0


## Герой в запрещённой воде? Проходы: мост и брод-мелководье (v1.31).
func _hero_in_water(t: Vector2i) -> bool:
	if not map.in_bounds(t) or map.grid[t.y][t.x] != map.TILE_WATER:
		return false
	return not map.bridges.has(t) and not map.fords.has(t)


## Оружейка рядом с героем (M5.1): за металл герой надевает боевой комплект.
func _armory_near_hero() -> Dictionary:
	for b in sim.buildings:
		if sim._active(b) and String(b["type"]) == "armory" \
				and sim.bld_dist_px(hero.position, b) < map.ts * 1.7:
			return b
	return {}


## Название здания под курсором — тултип у мыши (просьба заказчика).

# --- заглушки для парсера (структура v1.62.0) ------------------------------
# Цепочка частей одного класса: часть выше зовёт функции, живущие ниже —
# парсеру нужны сигнатуры (как в city_sim_base.gd). Реальные тела — в частях
# ниже; в рантайме виртуальная диспетчеризация зовёт их. Сигнатуры в синхроне.
func _add_fx(kind: String, col: Color, radius: float, dur: float, pos: Vector2) -> void:
	pass

func _read_json(path: String) -> Dictionary:
	return {}

func _default_hint() -> String:
	return ""

func set_speed(value: int) -> void:
	pass

func set_enchant_mode(ench_id: String) -> void:
	pass

func _region_text(ev: Dictionary) -> String:
	return ""

func _letter(ev_type: String, msg: String) -> void:
	pass

func _cost_str(cost: Dictionary) -> String:
	return ""

func _bld_name(type_id: String) -> String:
	return ""

func _on_hero_down() -> void:
	pass

func _apply_resource_hero_bonuses() -> void:
	pass

func _update_daylight() -> void:
	pass

func _night_amount() -> float:
	return 0.0

func _update_hover() -> void:
	pass

func _process_events() -> void:
	pass

func _hero_act() -> bool:
	return false

func _buy_hero_kit() -> void:
	pass

func _enter_dungeon() -> void:
	pass

func _exit_to_world(dir: Vector2i) -> void:
	pass

func _near_map_border() -> bool:
	return false

func _try_enchant() -> void:
	pass

## Свитки героя: ссылка на метод уходит колбэком в панель экипировки (v1.49).
func _cast_scroll(item_id: String) -> String:
	return ""

# --- заглушки для парсера (v1.66) -------------------------------------------
# Звено ввода (city_input) зовёт методы корня city.gd — реальные тела ниже
# по цепочке. Сигнатуры держите в синхроне.
func cast_combat_spell(_spell_id: String) -> void:
	pass
