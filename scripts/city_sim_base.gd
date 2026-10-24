extends RefCounted
## Симуляция города (M2): общий пул ресурсов, стройка силами строителей,
## жители-статисты (6 профессий): работа, еда, сон. Чистая логика без сцены.
## Живёт в автозагрузке Game — город продолжает жить, пока герой в данже.
##
## M3 (магия): магическое загрязнение с полосами и дикими событиями,
## городские заклинания (резонанс/очищение/дары леса) с кулдаунами,
## зачарование зданий руной + кристаллом, стан зданий от диких вспышек.
##
## M4 (жители-личности): черты характера (data/residents.json), навык растёт
## от работы, настроение (потребности+черты+события), беженцы и рождения,
## болезни/раны и лекарь, смерть жителя → горе, летопись, события-истории.
##
## M5 (угрозы и оборона): нарастающая кривая угрозы (время+размер города),
## волны мутантов из аномалии и осады (ломают стены/ворота), вышки и стражи
## реально воюют, магическая буря портит здания, участие героя (hero_slash),
## провал осады — потеря зданий, но не игры.
##
## M6 (свободные зоны и физическая логистика): зоны мышью (поле/пастбище/жилая),
## жители сами обустраивают клетки зон; дороги ускоряют жителей и носильщиков;
## производство растёт кучей у здания, носильщик носит кучи на склад — общий
## пул стал физическим хранилищем; склад рядом со зданием = быстрее производство;
## декор (сад, статуя) повышает мораль; мастерская чинит повреждённые здания,
## а без повреждений перерабатывает дерево и камень в инструменты.
##
## Житель: {id, name, prof, bld, site, home, state, pos, target, path, fatigue,
##          traits, mood, skill, rank, age_days, ail, ail_days, friend, work_bonus}
## Здание: {id, type, tile, done, progress, worker, enchant, ench_mult, stun_left, hp,
##          pile: {ресурс: количество} — куча у здания (M6)}
## Зона: {id, type: "field"|"pasture"|"living", cells: [Vector2i], progress: [float]}
## Рейдер: {id, type, p(строка enemies.json), hp, max_hp, pos, target, path,
##          atk_cd, goal(тайл), mode(advance|break|fight|flee)}

const RESOURCES := ["wood", "stone", "food", "crystal", "tools", "iron", "metal", "kits", "seeds", "saplings", "gems"]

var map = null                  # city_map.gd, нетипизированно (см. грабли GDScript)
var cfg: Dictionary = {}
var res: Dictionary = {"wood": 0, "stone": 0, "food": 0, "crystal": 0, "seeds": 0, "saplings": 0, "gems": 0}
var residents: Array = []
var buildings: Array = []
var time := 0.0                 # игровое время, сек (x1)
var day := 1
var speed := 1
var paused := false
var pollution := 0.0            # магическое загрязнение 0..100
var resonance_left := 0.0       # остаток «Дикого резонанса», сек
var resonance_mult := 1.0       # множитель производства резонанса
var events: Array = []          # [{"type": "site"|"built"|"no_worker"|"wild_*"|"died"|...}] — читает сцена
var chronicle: Array = []       # летопись (M4): [{day, key, a, b}] — ключи локализации
var base_pop := 0               # жители на старте — база лимита
var conflicts := true           # ссоры и воровство включены (ответ №29, галочка в меню)
var people: Dictionary = {}     # data/residents.json — черты, настроение, истории
var autonomous := false         # автономная деревня (правки v1.12.0): с 10 жителей
                                # деревня живёт сама — строит без старосты, зовёт поселенцев
var _chop_progress := {}        # недоруб героем: тайл -> удары (правки v1.12.2, транзитно)

# --- M5: угрозы -----------------------------------------------------------
var raiders: Array = []         # мутанты текущей волны
var raid_active := false        # идёт атака/осада
var raid_siege := false         # текущая волна — осада (ломает здания)
var raid_count := 0             # всего волн с начала игры
var razed_this_raid := 0        # зданий снесено мутантами в этой волне
var storm_state := ""           # "" | "warn" | "active"
var storm_left := 0.0           # сек до конца бури / до начала (warn)
var hero_pos := Vector2.ZERO    # где герой в городе (сцена обновляет каждый кадр)
var hero_alive := false         # герой в городе и на ногах
var animals: Array = []         # дикие животные для охоты: {id, pos, target, path, idle}
var livestock: Array = []       # скот на пастбищах (M10): {id, kind, pasture, pos, target, path, idle, adult, age}
var caravans_out: Array = []    # отправленные караваны (M10): {res, amount, left, coins, dest}
var caravan_here := false       # пришёл торговый караван в город (M10, рынок)
var _last_caravan_day := -99
# торговые палатки (этап 2, аспект 4): бродячие торговцы-нейтралы у палаток
var wanderers: Array = []       # {id, pos, path, mode: come|trade|leave, tent(id здания), left}
var _wanderer_id := 1
var _last_wanderer_day := -99
var zones: Array = []           # зоны (M6): {id, type: "field"|"pasture", cells, progress, crops}
var _zone_id := 1
var _livestock_id := 1
var plaza := Vector2i(-1, -1)   # Главная площадь 2×2 (левый верхний угол): место
                                # сбора и планёрки; рядом строить нельзя, переносится
var day_plans: Array = []       # утренние планы старосты (правки v1.20): последние N дней
var thought_log: Array = []     # журнал мыслей жителей [{t, name, text}] — тултип и отладка
var _log_file: FileAccess = null    # файл отладочного лога user://city_debug.log
var _stuck_checked_day := 0     # день последней проверки застрявших (анти-фриз, v1.20)

const GOLEM_NAME := "Голем"     # староста-голем «Белый властелин» (правки v1.20):
                                # не житель, без цвета, управляет утром деревней

var _next_id := 1
var _trait_map := {}            # id черты -> описание (из people["traits"])
var _spell_ready := {}          # id городского заклинания -> время готовности
var _event_rng := RandomNumberGenerator.new()
var _last_event_day := 0
var _last_daily_day := 0        # дневные броски M4: беженцы/рождения/болезни/истории
var _gate_state := {}           # id ворот -> открыты? (страж на ближней вышке)
var _spot_cache := {}           # id здания -> {key, spot}: кэш входа (этап 2, аспект 2)
# --- кэши производительности (правки приёмки v1.21.4: FPS падал к 70-му дню) ---
var _json_cache := {}           # path -> разобранный JSON: res:// в сессии не меняется,
                                # а _weather_cfg/_laws_cfg/_religion_cfg зовутся из
                                # _mood_target на каждого жителя каждый кадр
var _def_cache := {}            # type_id -> конфиг здания (_def сканировал cfg на каждый вызов)
var _bld_w_cache := {}          # type_id -> ширина здания в клетках
var _bld_hp_cache := {}         # type_id -> запас прочности
var _bld_tiles := {}            # Vector2i -> здание: индекс клеток для building_at O(1)
var _bld_tiles_ver := -1        # версия индекса (перестраивается при _bld_ver)
var _bld_ver := 0               # версия списка зданий (растёт при любой мутации)
var _next_raid_at := 0.0        # время следующей волны, сек
var _raid_gap_days := 10.0      # длительность текущего интервала между волнами
var _raid_not_before := 0.0     # волна не раньше этого времени: зачистка данжа у города сдвигает атаки (2026-10-21)
var _raid_warned := false       # предупреждение уже объявлено
# имитация жизни (M12): похороны и могилки у кладбища
var graves: Array = []                 # [{tile: Vector2i, name: String, ready: bool,
                                       #   rite: "bury"|"burn", burn_left?: float}]
var funeral_target := Vector2i(-1, -1) # тайл сбора процессии у кладбища
var funeral_pos := Vector2.ZERO        # где умершего взяли нести (для летописи сцены)
# кладбище и останки (v1.23): первая могила основывает место; павшие с телом
# (кроме духов, призраков и элементалей) ждут носильщика
var cemetery_tile := Vector2i(-1, -1)  # место кладбища: здание или основанное первой могилой
var corpses: Array = []                # останки врагов: [{tile: Vector2i, kind, rot, claim?}]
var _raid_rng := RandomNumberGenerator.new()
var _bld_id := 1                # счётчик id рейдеров/снарядов (общий с зданиями не нужен)
var _storm_struck_at := 0.0     # время последнего удара бури по зданию
var researched: Array = []      # изученные дисциплины (M7): id тиров research.json
var research_cfg: Dictionary = {}  # data/research.json — 3 ветки прогрессии города

# --- M11: вишлист (духи леса, некромант, добыча скалы) ----------------------
var forest_anger := 0.0         # гнев леса: растёт от вырубки, спадает от посадки
var necro_dark := 0.0           # тьма кладбища 0..1 — растёт, пока некромант работает
var necro_army := 0             # тайная армия скелетов
var necro_known := false        # некромантия раскрыта городу
var necro_ghosts: Array = []    # ночные призывы у кладбища (для отрисовки): [px]
var terrain_dirty := false      # ландшафт менялся (спил/посадка/выработка) — перерисовать слой
var static_dirty := false       # земля менялась (зоны/дороги/плиты площади) — перевыпечь духовку (v1.22)
var _winter_announced := false  # «зима близко» уже объявлено в этом предзимье (v1.22)
var _raid_kind := "mutant"      # вид текущей волны: mutant | forest | undead
var _forest_warned := false     # предупреждение «лес гневается» уже было
var _forest_cooldown := 0.0     # время следующей атаки леса, сек
var _necro_chosen := false      # житель-некромант уже выбран для кладбища

const PEOPLE_CFG_PATH := "res://data/residents.json"
const RESEARCH_CFG_PATH := "res://data/research.json"


## Запуск новой игры: карта, стартовые ресурсы по уровню, жители с профессиями.
func setup(city_map, city_cfg: Dictionary, residents_count: int, level: String) -> void:
	map = city_map
	cfg = city_cfg
	residents = []
	buildings = []
	events = []
	# кэши производительности (v1.21.4): новая игра — чистые кэши
	_json_cache = {}
	_def_cache = {}
	_bld_w_cache = {}
	_bld_hp_cache = {}
	_bld_tiles = {}
	_bld_ver += 1
	_spot_cache = {}
	autonomous = false
	time = 0.0
	day = 1
	speed = 1
	paused = false
	pollution = 0.0
	resonance_left = 0.0
	resonance_mult = 1.0
	_spell_ready = {}
	_last_event_day = 0
	chronicle = []
	_gate_state = {}
	raiders = []
	raid_active = false
	raid_siege = false
	raid_count = 0
	razed_this_raid = 0
	storm_state = ""
	storm_left = 0.0
	hero_alive = false
	animals = []
	livestock = []
	caravans_out = []
	caravan_here = false
	_last_caravan_day = -99
	wanderers = []
	_wanderer_id = 1
	_last_wanderer_day = -99
	zones = []
	_zone_id = 1
	day_plans = []
	thought_log = []
	_stuck_checked_day = 0
	plaza = Vector2i(-1, -1)
	_livestock_id = 1
	forest_anger = 0.0
	necro_dark = 0.0
	necro_army = 0
	necro_known = false
	necro_ghosts = []
	cemetery_tile = Vector2i(-1, -1)
	corpses = []
	terrain_dirty = false
	static_dirty = false
	_raid_kind = "mutant"
	_forest_warned = false
	_forest_cooldown = 0.0
	_necro_chosen = false
	for i in int(cfg.get("hunting", {}).get("animals", 8)):
		animals.append(_new_animal())
	_next_raid_at = 0.0
	_raid_warned = false
	_storm_struck_at = 0.0
	_last_daily_day = 0   # дневные броски (в т.ч. стройка) — с первого дня (заказчик)
	_event_rng.randomize()
	_raid_rng.randomize()
	_next_id = 1
	var people_data: Variant = _read_json_file(PEOPLE_CFG_PATH)
	people = people_data if people_data is Dictionary else {}
	_trait_map = {}
	for td in people.get("traits", []):
		_trait_map[String(td["id"])] = td
	var rdata: Variant = _read_json_file(RESEARCH_CFG_PATH)
	research_cfg = rdata if rdata is Dictionary else {}
	researched = []
	var levels: Dictionary = cfg["start"]["levels"]
	var start_res: Dictionary = levels.get(level, levels["normal"])
	for key in RESOURCES:
		res[key] = int(start_res.get(key, 0))
	# стартовые семена (M10): поля сеются, урожай возвращает часть
	_add_resource_capped("seeds", float(cfg.get("farming", {}).get("start_seeds", 16)))
	var profs: Array = cfg["start"]["professions"]
	var names: Array = cfg["names"]
	base_pop = residents_count
	for i in residents_count:
		var offset := Vector2(-2 + (i % 5), i / 5)
		var tile: Vector2i = map.spawn_tile + Vector2i(offset)
		if not map.is_walkable(tile):
			tile = map.spawn_tile
		residents.append(_new_resident(String(names[i % names.size()]), String(profs[i % profs.size()]), tile))
		_next_id += 1
	# главная площадь 2×2 в центре появления и староста-голем при нём (правки
	# v1.20): голем — не житель, белый, размещает здания и ведёт утреннюю планёрку
	_ensure_plaza()
	_spawn_golem()
	_assign_jobs()


## Главная площадь 2×2 у точки появления: место сбора и планёрки.
## Рядом (радиус plaza.radius клеток) строить нельзя; переносится игроком.
func _ensure_plaza() -> void:
	if plaza != Vector2i(-1, -1) and _plaza_ok(plaza):
		return
	plaza = map.spawn_tile + Vector2i(-1, -1)   # площадь накрывает точку появления
	if not _plaza_ok(plaza):
		plaza = map.nearest_walkable(map.spawn_tile) + Vector2i(-1, -1)
	if not _plaza_ok(plaza):
		plaza = map.spawn_tile


## Площадь 2×2 годна: в границах, без аномалии (вода/скалы допустимы — мостки).
func _plaza_ok(tile: Vector2i) -> bool:
	for dy in 2:
		for dx in 2:
			var c: Vector2i = tile + Vector2i(dx, dy)
			if not map.in_bounds(c) or c == map.anomaly_tile:
				return false
	return true


## Тайл в запретном радиусе площади (шебчево <= radius от прямоугольника 2×2).
func near_plaza(tile: Vector2i) -> bool:
	if plaza == Vector2i(-1, -1):
		return false
	var radius := int(cfg.get("plaza", {}).get("radius", 3))
	var dx := maxi(plaza.x - tile.x, tile.x - (plaza.x + 1))
	var dy := maxi(plaza.y - tile.y, tile.y - (plaza.y + 1))
	return maxi(dx, dy) <= radius


## Клетки площади 2×2.
func plaza_cells() -> Array:
	var out: Array = []
	if plaza == Vector2i(-1, -1):
		return out
	for dy in 2:
		for dx in 2:
			out.append(plaza + Vector2i(dx, dy))
	return out


## Клетки сбора: сама площадь + кольцо вокруг (жителям хватит места).
func plaza_gather_tiles() -> Array:
	var out := plaza_cells()
	for c in plaza_cells():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if map.in_bounds(n) and map.is_walkable(n) and not out.has(n):
				out.append(n)
	return out


## Перенос площади (инструмент игрока): "" — перенесена, иначе ключ ошибки.
func move_plaza(tile: Vector2i) -> String:
	if not _plaza_ok(tile):
		return "city.plaza_bad_spot"
	for c in plaza_cells():
		if not building_at(c).is_empty():
			return "city.plaza_bad_spot"
	for c in _plaza_new_cells(tile):
		if not building_at(c).is_empty():
			return "city.plaza_bad_spot"
	plaza = tile
	static_dirty = true   # плиты площади переехали — перевыпечь духовку (v1.22)
	_chron("chron.plaza_moved")
	return ""


func _plaza_new_cells(tile: Vector2i) -> Array:
	var out: Array = []
	for dy in 2:
		for dx in 2:
			out.append(tile + Vector2i(dx, dy))
	return out


## Голем-староста появляется у площади: белый, без черт, не ест, не болеет.
func _spawn_golem() -> void:
	for r in residents:
		if String(r["prof"]) == "elder":
			return   # староста уже есть (болеющий голем — всё же староста)
	var g := _new_resident(GOLEM_NAME, "elder", map.nearest_walkable(map.spawn_tile))
	g["traits"] = []
	g["mood"] = 100.0
	g["golem"] = true
	g["age_days"] = -1.0   # не стареет
	residents.append(g)
	_next_id += 1
	_chron("chron.golem_awakens", GOLEM_NAME)
	events.append({"type": "golem_awakens", "name": GOLEM_NAME})


## Врождённый пул статов (v1.24): каждый житель рождается разным — пул
## start_pool_min..start_pool очков раскидывается по пяти статам со случайными
## весами (одна статка не выше start_stat_cap). Мудрость — пятый стат:
## она противится зову тьмы и питает волшебные ремёсла.
func _roll_start_stats() -> Dictionary:
	var acfg: Dictionary = cfg.get("attributes", {})
	var pool := float(_event_rng.randi_range(int(acfg.get("start_pool_min", 20)),
			int(acfg.get("start_pool_max", 30))))
	var cap := float(acfg.get("start_stat_cap", 12))
	var weights := {}
	var total := 0.0
	for k in ["str", "agi", "end", "int", "wis"]:
		var w := 0.25 + _event_rng.randf() * _event_rng.randf()   # склонности перекошены
		weights[k] = w
		total += w
	var out := {}
	for k in weights:
		out[k] = minf(cap, roundf(pool * float(weights[k]) / total))
	return out


## Новый житель с личностью: черты, настроение, навык с нуля.
func _new_resident(res_name: String, prof: String, tile: Vector2i) -> Dictionary:	var traits := _random_traits()
	var r := {
		"id": _next_id, "name": res_name, "prof": prof,
		"bld": null, "site": null, "home": null,
		"state": "idle", "pos": map.tile_center_px(tile),
		"target": Vector2i(-1, -1), "path": PackedVector2Array(),
		"fatigue": 0.0,
		"traits": traits, "mood": _start_mood(traits),
		"skill": 0.0, "rank": 0, "age_days": 100.0,
		"ail": "", "ail_days": 0.0, "friend": -1, "work_bonus": 0.0,
		"stats": _roll_start_stats(),   # врождённый пул статов (v1.24)
		"skills": {},                 # прикладные навыки по деятельности (v1.23)
		"prof_extra": [], "sub_prof": "", "atk_cd": 0.0, "partner": -1,
		"rel": {}, "mem": [], "goal": "", "goal_prev": "", "tavern_visited": false,
		"parents": [],          # родители-жители (для детей, правки v1.20)
		"golem": false,         # староста-голем: белый, без цвета и быта
	}
	return r


## --- Жизнь v3 (M14-F, issue #3): отношения, память, цели --------------------

# --- M14-H: законы, вера -----------------------------------------------------
var active_laws: Array = []     # принятые советом законы (id из data/laws.json)
var god: String = ""            # избранное божество (data/religion.json)
var prayed_day: int = -1        # день последней молитвы (раз в день)
const LAWS_CFG_PATH := "res://data/laws.json"
const RELIGION_CFG_PATH := "res://data/religion.json"
# --- M14-J: погода и сезоны --------------------------------------------------
var weather: String = "clear"   # clear | rain | snow | fog | ash_storm
var froze_last_night := false   # зима без дров — город мёрз (для настроения)
const WEATHER_CFG_PATH := "res://data/weather.json"
const QUESTS_CFG_PATH := "res://data/quests.json"
const STORY_CFG_PATH := "res://data/story.json"

# --- M14-K: доска объявлений -------------------------------------------------
var quests: Array = []          # активные заказы {kind, customer, item/type, need, progress, reward, days}
var _quest_id := 1

# --- M14-L: сюжетная рамка ----------------------------------------------------
var story_chapter := 0          # пройденные главы (индекс в story.json)
var story_side := ""            # финал: "mana" | "ash" ("" — не выбран)
var story_flags := {}           # флаги из других сцен (данжи, тьма)

func _v3() -> Dictionary:
	return people.get("v3", {})



# --- перенесённые из середины файла объявления (единое место переменных) ---
## Работа ловчего: дойти до зверя, поймать, дотащить до пастбища (этап 2).
var tame_task := {}   # {animal, pasture, carrier, phase: "to_animal"|"to_pasture"}

## Монеты общие с героем (Game) — симуляция без сцены копит через колбэк.
var coins_sink: Callable = Callable()   # сцена ставит: func(n): Game.coins += n
var coins_source: Callable = Callable() # сцена ставит: func(): return Game.coins

## Радиус крепостного кольца стен от центра города.
const WALL_RING := 6

## Параметры мутантов (data/enemies.json) — грузятся лениво.
var _enemies_cfg: Array = []    # data/enemies.json — параметры мутантов


# --- заглушки для парсера (структура v1.20.2) -----------------------------
# GDScript статически ищет self-вызовы вверх по цепочке наследования, а часть
# функций определена НИЖЕ по цепочке. Заглушки повторяют сигнатуру — парсер
# доволен; в рантайме виртуальная диспетчеризация зовёт настоящие тела
# (эти варианты никогда не выполняются). Сигнатуры держите в синхроне.
func _active(b: Dictionary) -> bool:
	return false

func _add_resource_capped(key: String, amount: float) -> void:
	pass

func _adults() -> Array:
	return []

func _altar_work_mult() -> float:
	return 0.0

func _assign_jobs() -> void:
	pass

func _chron(key: String, a: String = "", b: String = "") -> void:
	pass

func _count_item(inventory: Array, item_id: String) -> int:
	return 0

func _def(b: Dictionary) -> Dictionary:
	return {}

func _deplete_rock(r: Dictionary, bld: Dictionary, portion: float) -> void:
	pass

func _edge_tile() -> Vector2i:
	return Vector2i(-1, -1)

func _ensure_elder() -> void:
	pass

func _farm_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	pass

func _grow_skill(r: Dictionary, dt: float, kind := "") -> void:
	pass

func _grow_combat(r: Dictionary, dt: float) -> void:
	pass

func _guard_spar(r: Dictionary, dt: float) -> bool:
	return false

func _fatigue_cost(r: Dictionary) -> float:
	return 1.0

func _stat(r: Dictionary, key: String) -> float:
	return 0.0

func _try_haul_log(r: Dictionary, dt: float) -> bool:
	return false

func _log_haul_work(r: Dictionary, dt: float) -> bool:
	return false

func _necro_night_walk(r: Dictionary, dt: float) -> bool:
	return false

func _log_carry_slow(r: Dictionary, size: int) -> float:
	return 1.0

func _gather_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	pass

func _gather_target(r: Dictionary, bld: Dictionary) -> Vector2i:
	return Vector2i(-1, -1)

func _planks_for(size: int) -> float:
	return 0.0

func _hero_chop_hits(size: int) -> int:
	return 1

func _grow_up(r: Dictionary) -> void:
	pass

func _has_trait_flag(r: Dictionary, flag: String) -> bool:
	return false

func _hit_raider(r: Dictionary, dmg: int) -> void:
	pass

func _hunt(r: Dictionary, dt: float) -> void:
	pass

func _is_golem(r: Dictionary) -> bool:
	return false

func _lie_ill(r: Dictionary, dt: float) -> void:
	pass

func _magic_pollution_mult() -> float:
	return 0.0

func _make_ail(r: Dictionary, kind: String, chron_key: String) -> void:
	pass

func _manage_walk(r: Dictionary, dt: float) -> void:
	pass

func _nearest_done_of_type(from_px: Vector2, type_id: String) -> Dictionary:
	return {}

func _nearest_raider(from_px: Vector2, radius_px: float) -> Dictionary:
	return {}

func _nearest_ripe_field_cell(r: Dictionary, farm_id: int = -1) -> Dictionary:
	return {}

func _necro_purge() -> void:
	pass

func _new_animal() -> Dictionary:
	return {}

func _porter_work(r: Dictionary, dt: float) -> void:
	pass

func _pull_idle_piles() -> void:
	pass

func _random_traits() -> Array:
	return []

func _read_json_file(path: String) -> Variant:
	return null

func _resident_by_id(res_id: int) -> Dictionary:
	return {}

func _roll_ailments() -> void:
	pass

func _roll_animals() -> void:
	pass

func _roll_autobuild() -> void:
	pass

func _roll_city_repair() -> void:
	pass

func _repair_errand(r: Dictionary, dt: float) -> bool:
	return false

func _move_towards(r: Dictionary, tile: Vector2i, dt: float) -> void:
	pass

func _roll_births() -> void:
	pass

func _roll_couples() -> void:
	pass

func _roll_festival() -> void:
	pass

func _roll_guards() -> void:
	pass

func _roll_hunter() -> void:
	pass

func _roll_livestock() -> void:
	pass

func _roll_market() -> void:
	pass

func _roll_necro() -> void:
	pass

func _roll_porter() -> void:
	pass

func _roll_refugees() -> void:
	pass

func _roll_stories() -> void:
	pass

func _roll_storm() -> void:
	pass

func _roll_wanderer() -> void:
	pass

func _start_mood(traits: Array) -> float:
	return 0.0

func _take_item(inventory: Array, item_id: String, count: int) -> void:
	pass

func _tame_work(r: Dictionary, dt: float) -> bool:
	return false

func _tavern_beer(dt: float, day_len: float) -> void:
	pass

func _tent_tend(r: Dictionary, b: Dictionary, dt: float) -> void:
	pass

func _tent_visit(r: Dictionary, dt: float) -> bool:
	return false

func _tick_caravans() -> void:
	pass

func _tick_orchards() -> void:
	pass

func _tick_tents() -> void:
	pass

func _trait_prod(r: Dictionary, key: String) -> float:
	return 0.0

func _update_animals(dt: float) -> void:
	pass

func _update_forest(dt: float, day_len: float) -> void:
	pass

func _update_gates() -> void:
	pass

func _update_livestock(dt: float) -> void:
	pass

func _update_mood(r: Dictionary, dt: float, day_len: float) -> void:
	pass

func _update_storm(dt: float, day_len: float) -> void:
	pass

func _update_threat(dt: float, day_len: float) -> void:
	pass

func _update_wanderers(dt: float) -> void:
	pass

func _update_zones(dt: float, day_len: float) -> void:
	pass

func _watchdog_stuck() -> void:
	pass

func _zone_fill_work(r: Dictionary, dt: float) -> bool:
	return false

func blessing_boost() -> float:
	return 0.0

func building_at(tile: Vector2i) -> Dictionary:
	return {}

func elder_present() -> bool:
	return false

func morning_plan() -> Dictionary:
	return {}

func research_mult(key: String, fallback: float) -> float:
	return 0.0

func tick(dt_raw: float) -> void:
	pass

func work_mult(r: Dictionary) -> float:
	return 0.0

func working_tents() -> Array:
	return []

