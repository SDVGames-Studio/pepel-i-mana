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

const RESOURCES := ["wood", "stone", "food", "crystal", "tools", "iron", "metal", "kits", "seeds"]

var map = null                  # city_map.gd, нетипизированно (см. грабли GDScript)
var cfg: Dictionary = {}
var res: Dictionary = {"wood": 0, "stone": 0, "food": 0, "crystal": 0, "seeds": 0}
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
var zones: Array = []           # зоны (M6): {id, type, cells, progress, crops: [{stage, t, fallow}]}
var _zone_id := 1
var _livestock_id := 1

var _next_id := 1
var _trait_map := {}            # id черты -> описание (из people["traits"])
var _spell_ready := {}          # id городского заклинания -> время готовности
var _event_rng := RandomNumberGenerator.new()
var _last_event_day := 0
var _last_daily_day := 0        # дневные броски M4: беженцы/рождения/болезни/истории
var _gate_state := {}           # id ворот -> открыты? (страж на ближней вышке)
var _next_raid_at := 0.0        # время следующей волны, сек
var _raid_gap_days := 1.2       # длительность текущего интервала между волнами
var _raid_warned := false       # предупреждение уже объявлено
# имитация жизни (M12): похороны и могилки у кладбища
var graves: Array = []                 # [{tile: Vector2i, name: String, ready: bool}]
var funeral_target := Vector2i(-1, -1) # тайл сбора процессии у кладбища
var funeral_pos := Vector2.ZERO        # где умершего взяли нести (для летописи сцены)
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
	zones = []
	_zone_id = 1
	_livestock_id = 1
	forest_anger = 0.0
	necro_dark = 0.0
	necro_army = 0
	necro_known = false
	necro_ghosts = []
	terrain_dirty = false
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
		# последний стартовый житель — всегда староста (просьба заказчика)
		var prof := String(profs[i % profs.size()])
		if i == residents_count - 1:
			prof = "elder"
		residents.append(_new_resident(String(names[i % names.size()]), prof, tile))
		_next_id += 1
	_assign_jobs()


## Новый житель с личностью: черты, настроение, навык с нуля.
func _new_resident(res_name: String, prof: String, tile: Vector2i) -> Dictionary:
	var traits := _random_traits()
	var r := {
		"id": _next_id, "name": res_name, "prof": prof,
		"bld": null, "site": null, "home": null,
		"state": "idle", "pos": map.tile_center_px(tile),
		"target": Vector2i(-1, -1), "path": PackedVector2Array(),
		"fatigue": 0.0,
		"traits": traits, "mood": _start_mood(traits),
		"skill": 0.0, "rank": 0, "age_days": 100.0,
		"ail": "", "ail_days": 0.0, "friend": -1, "work_bonus": 0.0,
		"prof_extra": [], "sub_prof": "", "atk_cd": 0.0, "partner": -1,
		"rel": {}, "mem": [], "goal": "", "goal_prev": "", "tavern_visited": false,
	}
	return r


## --- Жизнь v3 (M14-F, issue #3): отношения, память, цели --------------------

func _v3() -> Dictionary:
	return people.get("v3", {})


## Балл отношений a→b (и симметрично b→a хранится отдельно, меняются вместе).
func _rel_change(a: Dictionary, b: Dictionary, delta: float) -> void:
	var cap := 100.0
	var lo := -100.0
	for pair in [[a, b], [b, a]]:
		var rel: Dictionary = pair[0].get("rel", {})
		if (rel as Dictionary).is_empty() and delta > 0.0 and not (pair[0] as Dictionary).has("rel"):
			pair[0]["rel"] = {}
		rel = pair[0].get("rel", {})
		var key := str(int(pair[1]["id"]))
		rel[key] = clampf(float(rel.get(key, 0.0)) + delta, lo, cap)


func _rel_score(r: Dictionary, other_id: int) -> float:
	var rel: Dictionary = r.get("rel", {})
	return float(rel.get(str(other_id), 0.0))


## Лучший друг / заклятый враг по карте отношений (для панели и досуга).
func rel_best(r: Dictionary) -> Dictionary:
	var rel: Dictionary = r.get("rel", {})
	var best_id := -1
	var best_score := float(_v3().get("friend_threshold", 50.0))
	for k in rel:
		if float(rel[k]) >= best_score:
			best_score = float(rel[k])
			best_id = int(k)
	if best_id < 0:
		return {}
	var other := _resident_by_id(best_id)
	if other.is_empty():
		return {}
	return {"other": other, "score": best_score}


func rel_worst(r: Dictionary) -> Dictionary:
	var rel: Dictionary = r.get("rel", {})
	var worst_id := -1
	var worst_score := float(_v3().get("foe_threshold", -30.0))
	for k in rel:
		if float(rel[k]) <= worst_score:
			worst_score = float(rel[k])
			worst_id = int(k)
	if worst_id < 0:
		return {}
	var other := _resident_by_id(worst_id)
	if other.is_empty():
		return {}
	return {"other": other, "score": worst_score}


## Память (M14-F): последние N личных событий; вклад в настроение тает со
## временем, но не гаснет до нуля (негаснущий хвост, grief затухает медленно).
func _mem_push(r: Dictionary, key: String) -> void:
	var slots := int(_v3().get("memory_slots", 3))
	var mem: Array = r.get("mem", [])
	mem.append({"k": key, "age": 0.0})
	while mem.size() > slots:
		mem.pop_front()
	r["mem"] = mem


func _memory_mood(r: Dictionary) -> float:
	var v3 := _v3()
	var moods: Dictionary = v3.get("mood_per_event", {})
	var decay_days := maxf(1.0, float(v3.get("memory_decay_days", 10.0)))
	var min_factor := float(v3.get("memory_min_factor", 0.2))
	var total := 0.0
	for m in r.get("mem", []):
		var decay := maxf(min_factor, 1.0 - float(m["age"]) / decay_days)
		total += float(moods.get(String(m["k"]), 0.0)) * decay
	return total


## Ежедневный тик v3: память стареет; отношения от совместной работы;
## друг = лучший балл; новые личные цели.
func _roll_v3() -> void:
	var v3 := _v3()
	var adults: Array = _adults()
	# память стареет
	for r in adults:
		var mem: Array = r.get("mem", [])
		for m in mem:
			m["age"] = float(m["age"]) + 1.0
	# отношения: работа рядом сближает
	var near_tiles := float(v3.get("work_near_tiles", 3))
	var bonus := float(v3.get("work_near_bonus", 1.0))
	for i in adults.size():
		var a: Dictionary = adults[i]
		var bld_a = a.get("bld")
		if bld_a == null or not bool((bld_a as Dictionary).get("done", false)):
			continue
		for j in range(i + 1, adults.size()):
			var b: Dictionary = adults[j]
			var bld_b = b.get("bld")
			if bld_b == null or not bool((bld_b as Dictionary).get("done", false)):
				continue
			if Vector2(bld_a["tile"]).distance_to(Vector2(bld_b["tile"])) <= near_tiles:
				_rel_change(a, b, bonus)
	# друг = лучший балл отношений (используется вечерним досугом M12)
	var friend_at := float(v3.get("friend_threshold", 50.0))
	for r in adults:
		var rel: Dictionary = r.get("rel", {})
		var best_id := -1
		var best_score := friend_at
		for k in rel:
			if float(rel[k]) >= best_score:
				best_score = float(rel[k])
				best_id = int(k)
		r["friend"] = best_id
	# вечерняя попойка в таверне забыта до следующего вечера
	for r in residents:
		r["tavern_visited"] = false
	_roll_goals()


## Новая личная цель свободному взрослому; выполненная — награда и новая.
func _roll_goals() -> void:
	var v3 := _v3()
	var pool: Array = people.get("goals", [])
	if pool.is_empty():
		return
	for r in _adults():
		var goal := String(r.get("goal", ""))
		if goal == "":
			_assign_goal(r, pool)
			continue
		var done := false
		match goal:
			"become_master":
				done = int(r.get("rank", 0)) >= 5
			"feast_tavern":
				done = bool(r.get("tavern_visited", false))
			"store_food":
				var need := float(_adults().size()) * float(cfg.get("food_per_resident_day", 2.0)) \
						* float(v3.get("goal_food_days", 7))
				done = float(res["food"]) >= need
			"build_garden":
				pass   # завершается постройкой сада/статуи (см. _complete_site)
		if done:
			_complete_goal(r, pool)


func _assign_goal(r: Dictionary, pool: Array) -> void:
	for attempt in 6:
		var pick: Dictionary = pool[_event_rng.randi_range(0, pool.size() - 1)]
		var gid := String(pick["id"])
		if gid == String(r.get("goal_prev", "")) and attempt < 5:
			continue
		r["goal"] = gid
		return


## Цель достигнута: настроение, летопись, память — и новая цель.
func _complete_goal(r: Dictionary, pool: Array) -> void:
	var goal := String(r.get("goal", ""))
	if goal == "":
		return
	r["goal_prev"] = goal
	r["goal"] = ""
	r["mood"] = clampf(float(r["mood"]) + float(_v3().get("goal_mood", 6.0)), 0.0, 100.0)
	_mem_push(r, "goal")
	_chron("chron.goal_done", String(r["name"]), "goal." + goal)
	events.append({"type": "goal_done", "name": String(r["name"]), "goal": goal})
	_assign_goal(r, pool)


## Достигнуть цель «построить сад» у строителя (декор готов, M14-F).
func _goal_garden_built(worker_id: int) -> void:
	var r := _resident_by_id(worker_id)
	if not r.is_empty() and String(r.get("goal", "")) == "build_garden":
		_complete_goal(r, people.get("goals", []))


func _start_mood(traits: Array) -> float:
	var mood: float = float(people.get("mood_base", 50.0))
	for t_id in traits:
		var td: Dictionary = _trait_map.get(String(t_id), {})
		mood += float(td.get("mood", 0.0))
	return clampf(mood, 0.0, 100.0)


## 1-2 случайные черты по весам, без повторов.
func _random_traits() -> Array:
	var tmin := int(people.get("traits_per_resident_min", 1))
	var tmax := int(people.get("traits_per_resident_max", 2))
	var tdefs: Array = people.get("traits", [])
	var picked := {}
	var out: Array = []
	for i in _event_rng.randi_range(tmin, maxi(tmin, tmax)):
		var total := 0
		for td: Dictionary in tdefs:
			if not picked.has(String(td["id"])):
				total += int(td.get("weight", 1))
		var roll := _event_rng.randi_range(1, maxi(1, total))
		for td: Dictionary in tdefs:
			if picked.has(String(td["id"])):
				continue
			roll -= int(td.get("weight", 1))
			if roll <= 0:
				picked[String(td["id"])] = true
				out.append(String(td["id"]))
				break
	return out


func _read_json_file(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


# --- запросы для HUD и тестов -------------------------------------------

func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if int(res.get(key, 0)) < int(cost[key]):
			return false
	return true


func storage_cap() -> int:
	var extra := 0
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "storage":
			extra += int(cfg["storage_per_warehouse"])
	return int(cfg["storage_base"]) + extra


func pop_cap() -> int:
	var houses := 0
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "pop":
			houses += 1
	# обустроенные клетки жилой зоны — шалаши, каждый даёт место (M6)
	var tents := 0
	var per := int(cfg.get("zones", {}).get("types", {}).get("living", {}).get("pop", 1))
	for z in zones:
		if String(z["type"]) != "living":
			continue
		for i in (z["cells"] as Array).size():
			if _cell_filled(z, i) and building_at(z["cells"][i]).is_empty():
				tents += 1
	return base_pop + houses * int(cfg["pop_per_house"]) + tents * per


func is_night() -> bool:
	var t := fmod(time, float(cfg["day_length"]))
	return t >= float(cfg["day_length"]) * (1.0 - float(cfg["night_fraction"]))


func day_number() -> int:
	return day


## Быстрая перемотка на n дней (M8): герой в пути — город живёт (ежедневные
## броски, еда, угрозы, стройка). Шаг по четверти дня — устойчиво для боёв.
func advance_days(n: int) -> void:
	var was_paused := paused
	paused = false
	var step := float(cfg["day_length"]) / 4.0
	for i in n * 4:
		tick(step)
	paused = was_paused


## Событие в летопись из внешней симуляции (карта мира пишет свои истории, M8).
func chronicle_add(key: String, a: String = "", b: String = "") -> void:
	_chron(key, a, b)


## Благословение алтаря: есть готовый алтарь с работающим магом-учеником.
func has_blessing() -> bool:
	return altar_ready()


## Алтарь готов и на нём работает маг-ученик (крафт, зачарование, городские заклинания).
func altar_ready() -> bool:
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "altar" and int(b["worker"]) > 0:
			return true
	return false


## На алтаре зачарование «Мана» (больше запас и быстрее регенерация у героя).
func altar_enchanted() -> bool:
	for b in buildings:
		if b["done"] and String(b["type"]) == "altar" and String(b.get("enchant", "")) == "mana":
			return true
	return false


## Полоса загрязнения: clean / mild / heart / wild (для HUD и множителя).
func pollution_band() -> String:
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	if pollution >= float(pol_cfg.get("band_wild", 85.0)):
		return "wild"
	if pollution >= float(pol_cfg.get("band_heart", 60.0)):
		return "heart"
	if pollution >= float(pol_cfg.get("band_mild", 30.0)):
		return "mild"
	return "clean"


## Множитель производства от загрязнения («магическое сердце» — ответ №64),
## дикого резонанса, зачарования здания, планировки (склад рядом — M6)
## и дисциплин (M7: «Земледелие» — еде, «Тайное» — всем).
func production_mult(bld: Dictionary) -> float:
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	var mult := 1.0
	var band := pollution_band()
	if band == "heart":
		mult *= float(pol_cfg.get("prod_heart", 1.15))
	elif band == "mild":
		mult *= float(pol_cfg.get("prod_mild", 1.05))
	if resonance_left > 0.0:
		mult *= resonance_mult
	mult *= float(bld.get("ench_mult", 1.0))
	mult *= layout_mult(bld)
	mult *= research_mult("prod_all", 1.0)
	if not bld.is_empty() and bld.has("type") \
			and String(_def(bld).get("produce", {}).get("res", "")) == "food":
		mult *= research_mult("food_prod", 1.0)
	return mult


## Бонус планировки (M6): склад рядом со зданием ускоряет производство
## («склад рядом с фермами = +скорость», пункт плана M6).
func layout_mult(bld: Dictionary) -> float:
	if bld.is_empty() or not bld.has("type") or not _def(bld).has("produce"):
		return 1.0
	var lcfg: Dictionary = cfg.get("layout", {})
	if lcfg.is_empty():
		return 1.0
	var radius := float(lcfg.get("warehouse_radius", 4))
	for b in buildings:
		if bool(b["done"]) and _def(b).get("effect", "") == "storage" \
				and Vector2(b["tile"]).distance_to(Vector2(bld["tile"])) <= radius:
			return float(lcfg.get("warehouse_mult", 1.25))
	return 1.0


## Комфорт от готового декора (сад, статуя — ответ №18) с потолком.
func decor_mood() -> float:
	var total := 0.0
	for b in buildings:
		if bool(b["done"]) and _def(b).get("effect", "") == "decor":
			total += float(_def(b).get("mood", 0.0))
	return minf(total, float(cfg.get("decor_mood_max", 20.0)))


## Прибавить загрязнение (дикая магия в данже тоже — город в том же регионе).
func add_pollution(amount: float) -> void:
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	pollution = clampf(pollution + amount, 0.0, float(pol_cfg.get("max", 100.0)))


## Каст городского заклинания (M3). def — строка data/magic.json.
## Возвращает "" при успехе или ключ ошибки локализации ("magic." + ключ).
func cast_city_spell(def: Dictionary) -> String:
	if not altar_ready():
		return "no_altar"
	var spell_id := String(def["id"])
	if float(_spell_ready.get(spell_id, 0.0)) > time:
		return "cooldown"
	var cost := int(def.get("crystals_cost", 0))
	if int(res["crystal"]) < cost:
		return "no_crystals"
	res["crystal"] = float(res["crystal"]) - float(cost)
	_spell_ready[spell_id] = time + float(def.get("cooldown", 0.0))
	var params: Dictionary = def.get("params", {})
	match spell_id:
		"wild_resonance":
			resonance_left = float(params.get("duration", 120.0))
			resonance_mult = float(params.get("prod_mult", 1.5))
			add_pollution(float(def.get("pollution", 0.0)))
		"cleanse":
			pollution = maxf(0.0, pollution - float(params.get("amount", 25.0)))
		"forest_gift":
			_add_resource_capped("food", float(params.get("food", 15.0)))
			add_pollution(float(def.get("pollution", 0.0)))
		"meteor_shard":
			_add_resource_capped("stone", float(params.get("stone", 30.0)))
			add_pollution(float(def.get("pollution", 0.0)))
		"bless":
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(params.get("mood", 12.0)), 0.0, 100.0)
		"harvest_blessing":
			_add_resource_capped("food", float(params.get("food", 25.0)))
			add_pollution(float(def.get("pollution", 0.0)))
	return ""


## Добавить ресурс с ограничением хранилища, но БЕЗ уменьшения запаса:
## если его больше капа (тест-режим, излишки) — просто ничего не добавляем.
func _add_resource_capped(key: String, amount: float) -> void:
	var cap := float(storage_cap())
	if float(res[key]) >= cap:
		return
	res[key] = minf(cap, float(res[key]) + amount)


## Зачаровать готовое здание (ответ №60): руна из рюкзака + кристаллы из пула.
## def — строка "enchantments" из data/magic.json. Возвращает "" или ключ ошибки.
func enchant_building(bld: Dictionary, def: Dictionary, inventory: Array) -> String:
	if bld.is_empty() or not bool(bld["done"]):
		return "enchant_not_done"
	var target := String(def.get("target", "any"))
	if target != "any" and String(bld["type"]) != target:
		return "enchant_wrong"
	var cost := int(def.get("crystals", 1))
	if int(res["crystal"]) < cost:
		return "no_crystals"
	var rune := String(def["rune"])
	if _count_item(inventory, rune) < 1:
		return "no_rune"
	res["crystal"] = float(res["crystal"]) - float(cost)
	_take_item(inventory, rune, 1)
	bld["enchant"] = String(def["id"])
	bld["ench_mult"] = float(def.get("prod_mult", 1.0))
	return ""


## Руной «Мана» алтарь усиливает ману героя (параметры из city.json -> "hero_mana").
func hero_mana_params() -> Dictionary:
	var mana_cfg: Dictionary = cfg.get("hero_mana", {})
	var regen: float = float(mana_cfg.get("regen_period", 8.0))
	if altar_enchanted():
		regen = float(mana_cfg.get("altar_regen_period", 5.0))
	# дисциплина «Тайное» (M7): регенерация маны героя быстрее
	regen *= research_mult("mana_regen_mult", 1.0)
	return {"cap_extra": int(mana_cfg.get("altar_cap_extra", 4)) if altar_enchanted() else 0,
			"regen_period": regen}


## --- дисциплины прогрессии города (M7): 3 ветки исследований ----------------

## Изучить дисциплину (тир). Возвращает "" или ключ ошибки локализации.
func study_research(tier_id: String) -> String:
	if researched.has(tier_id):
		return "research_done"
	var tier := _research_tier(tier_id)
	if tier.is_empty():
		return "research_done"
	# тир доступен, только если предыдущий в ветке изучен
	for branch in research_cfg.get("branches", []):
		var prev := ""
		for t in branch.get("tiers", []):
			if String(t["id"]) == tier_id:
				if prev != "" and not researched.has(prev):
					return "research_locked"
				break
			prev = String(t["id"])
	for res_key in tier.get("cost", {}):
		if float(res.get(res_key, 0.0)) < float(tier["cost"][res_key]):
			return "research_no_res"
	for res_key in tier.get("cost", {}):
		res[res_key] = float(res[res_key]) - float(tier["cost"][res_key])
	researched.append(tier_id)
	return ""


func _research_tier(tier_id: String) -> Dictionary:
	for branch in research_cfg.get("branches", []):
		for t in branch.get("tiers", []):
			if String(t["id"]) == tier_id:
				return t
	return {}


## Сумма аддитивных эффектов дисциплин (tower_damage, tower_range).
func research_sum(key: String) -> float:
	var total := 0.0
	for tier_id in researched:
		total += float(_research_tier(String(tier_id)).get(key, 0.0))
	return total


## Произведение мультипликативных эффектов дисциплин (food_prod, prod_all...).
func research_mult(key: String, fallback: float) -> float:
	var mult := fallback
	for tier_id in researched:
		var v: float = float(_research_tier(String(tier_id)).get(key, 0.0))
		if v > 0.0:
			mult *= v
	return mult


func _count_item(inventory: Array, item_id: String) -> int:
	for stack in inventory:
		if String(stack["id"]) == item_id:
			return int(stack["count"])
	return 0


func _take_item(inventory: Array, item_id: String, count: int) -> void:
	var left := count
	var i := 0
	while i < inventory.size() and left > 0:
		var stack: Dictionary = inventory[i]
		if String(stack["id"]) == item_id:
			var take := mini(left, int(stack["count"]))
			stack["count"] = int(stack["count"]) - take
			left -= take
			if int(stack["count"]) <= 0:
				inventory.remove_at(i)
				continue
		i += 1

## Определение здания по типу.
func _def(b: Dictionary) -> Dictionary:
	for d in cfg["buildings"]:
		if String(d["id"]) == String(b["type"]):
			return d
	return {}


func building_at(tile: Vector2i) -> Dictionary:
	for b in buildings:
		if b["tile"] == tile:
			return b
	return {}


# --- стройка -------------------------------------------------------------

## Тайл годен под стройку: проходимая суша (или руда под шахту), нет здания, не аномалия.
func is_buildable_tile(tile: Vector2i, type_id := "") -> bool:
	if not map.in_bounds(tile) or tile == map.anomaly_tile:
		return false
	if not map.is_nature_walkable(tile):
		# шахту ставим прямо на рудную жилу (заказчик: место под шахту)
		if type_id == "mine" and map.grid[tile.y][tile.x] == map.TILE_ORE:
			pass
		else:
			return false
	return building_at(tile).is_empty()


## Заложить стройплощадку: ресурсы списываются сразу (ответ №16 — достраивают рабочие).
## Особые здания требуют места: шахта — руда, пирс — вода рядом, оружейная — кузня рядом.
func place_building(type_id: String, tile: Vector2i) -> bool:
	var def := _def({"type": type_id})
	if def.is_empty() or not is_buildable_tile(tile, type_id) or not can_afford(def["cost"]):
		return false
	if placement_block(type_id, tile) != "":
		return false
	for key in def["cost"]:
		res[key] = int(res[key]) - int(def["cost"][key])
	buildings.append({
		"id": _next_id, "type": type_id, "tile": tile,
		"done": false, "progress": 0.0, "worker": -1,
		"enchant": "", "ench_mult": 1.0, "stun_left": 0.0,
		"hp": float(_bld_max_hp(type_id)),
		"pile": {},
	})
	_next_id += 1
	# здание занимает тайл: дорога и клетка зоны под ним уступают место (M6)
	map.remove_road(tile)
	_drop_zone_cell(tile)
	events.append({"type": "site", "bld": type_id})
	_assign_jobs()
	return true


## Проложить дорогу (M6): трава без зданий и зон, камень за тайл. "" — успех.
func place_road(tile: Vector2i) -> String:
	if not map.in_bounds(tile) or not map.is_nature_walkable(tile) \
			or not building_at(tile).is_empty() or _tile_in_zone(tile):
		return "bad"
	if map.has_road(tile):
		return ""
	var rcfg: Dictionary = cfg.get("roads", {})
	var cost := int(rcfg.get("cost_stone", 1))
	if int(res["stone"]) < cost:
		return "no_stone"
	res["stone"] = int(res["stone"]) - cost
	map.set_road(tile, float(rcfg.get("astar_weight", 0.4)))
	return ""


## Клетка занята зоной?
func _tile_in_zone(tile: Vector2i) -> bool:
	for z in zones:
		if (z["cells"] as Array).has(tile):
			return true
	return false


## Дневной бросок: город сам прокладывает дороги по протоптанным тропам
## (жители ходят по кратчайшим путям — износ концентрируется на оптимальных
## маршрутах: работа → склад, дом → работа). Не в ущерб стройке: только
## сверх резерва камня, не больше auto_per_day за день, зоны и здания пропускает.
func _roll_auto_roads() -> void:
	var rcfg: Dictionary = cfg.get("roads", {})
	if rcfg.is_empty() or not elder_present():
		return
	if int(res["stone"]) < int(rcfg.get("auto_reserve_stone", 15)):
		return
	var threshold: float = float(rcfg.get("wear_threshold", 25.0))
	var cand: Array = []
	for t in map.wear:
		if float(map.wear[t]) >= threshold and not map.has_road(t):
			cand.append(t)
	cand.sort_custom(func(a, b) -> bool: return float(map.wear[a]) > float(map.wear[b]))
	var laid := 0
	var limit := int(rcfg.get("auto_per_day", 3))
	for t: Vector2i in cand:
		if laid >= limit:
			break
		if place_road(t) == "":
			laid += 1
		map.wear.erase(t)   # тропу обработали — снимаем износ
	if laid > 0:
		events.append({"type": "road_auto", "count": laid})
		_chron("chron.road_built", str(laid))


## Убрать тайл из его зоны (здание заняло клетку).
func _drop_zone_cell(tile: Vector2i) -> void:
	for z in zones:
		var idx: int = (z["cells"] as Array).find(tile)
		if idx >= 0:
			z["cells"].remove_at(idx)
			z["progress"].remove_at(idx)
			return


## Почему здание нельзя поставить здесь: ключ локализации или "" (для тоста сцены).
func placement_block(type_id: String, tile: Vector2i) -> String:
	var place := ""
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			place = String(d.get("place", ""))
			break
	match place:
		"ore":
			if map.in_bounds(tile) and map.grid[tile.y][tile.x] != map.TILE_ORE:
				return "city.placement_ore"
		"water":
			if not _water_near(tile):
				return "city.placement_water"
		"near_forge":
			if _nearest_building_type(tile, ["forge"], 2.0).is_empty():
				return "city.placement_forge"
		"forest":
			# лесопилка — только у леса: лесоруб добывает именно деревья (заказчик)
			if _nature_near(tile, [map.TILE_TREE], 2.0) == Vector2i(-1, -1):
				return "city.placement_forest"
		"rock":
			# каменоломня — только у скал (заказчик)
			if _nature_near(tile, [map.TILE_ROCK, map.TILE_ORE], 2.0) == Vector2i(-1, -1):
				return "city.placement_rock"
	return ""


## Есть ли рядом (в радиусе, тайлах) тайл природы одного из видов. Возвращает его.
func _nature_near(tile: Vector2i, kinds: Array, radius: float) -> Vector2i:
	var r := int(ceilf(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := tile + Vector2i(dx, dy)
			if map.in_bounds(t) and Vector2(t).distance_to(Vector2(tile)) <= radius \
					and map.grid[t.y][t.x] in kinds:
				return t
	return Vector2i(-1, -1)


func _water_near(tile: Vector2i) -> bool:
	for n in [tile + Vector2i(1, 0), tile + Vector2i(-1, 0), tile + Vector2i(0, 1), tile + Vector2i(0, -1)]:
		if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER:
			return true
	return false


## Ближайшее готовое здание одного из типов в радиусе (тайлах), {} — нет.
func _nearest_building_type(tile: Vector2i, types: Array, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for b in buildings:
		if not bool(b["done"]) or not (String(b["type"]) in types):
			continue
		var d: float = Vector2(b["tile"]).distance_to(Vector2(tile))
		if d <= best_d:
			best_d = d
			best = b
	return best


## Запас прочности здания (M5): стены/ворота крепче, остальное — базовое.
## Дисциплина «Оборона» (M7) умножает прочность стен и ворот.
func _bld_max_hp(type_id: String) -> int:
	var hp_cfg: Dictionary = cfg.get("threat", {}).get("bld_hp", {})
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			var hp := int(hp_cfg.get(String(d.get("effect", "default")), hp_cfg.get("default", 20)))
			if String(d.get("effect", "")) in ["wall", "gate"]:
				hp = int(round(float(hp) * research_mult("wall_hp_mult", 1.0)))
			return hp
	return int(hp_cfg.get("default", 20))


## Урон зданию от мутантов и бури; на нуле прочности здание разрушается.
func _damage_building(b: Dictionary, amount: float) -> void:
	b["hp"] = float(b.get("hp", float(_bld_max_hp(String(b["type"]))))) - amount
	if float(b["hp"]) > 0.0:
		return
	# разрушено: рабочее место освобождается, стена перестаёт быть преградой
	if int(b["worker"]) > 0:
		for r in residents:
			if int(r["id"]) == int(b["worker"]):
				r["bld"] = null
				r["site"] = null
				r["sub_prof"] = ""
				break
		b["worker"] = -1
	if _def(b).get("effect", "") in ["wall", "gate"]:
		map.set_solid(b["tile"], false)
	buildings.erase(b)
	# кладбище разрушено (мутантами, бурей) — тайная армия рассыпается (M11)
	if String(b["type"]) == "cemetery":
		_necro_purge()
	events.append({"type": "razed", "bld": String(b["type"])})
	_chron("chron.razed", String(b["type"]))


## Цель достигнута (стройка готова): декор закрывает цель «построить сад».
func _complete_site(site: Dictionary) -> void:
	var worker_id := int(site.get("worker", -1))
	site["done"] = true
	site["progress"] = 0.0
	site["worker"] = -1
	if _def(site).get("mood", 0) != 0 or String(_def(site).get("effect", "")) == "decor":
		_goal_garden_built(worker_id)   # личная цель v3: «построить сад»
	if _def(site).get("effect", "") == "wall":
		map.set_solid(site["tile"], true)
		_step_off_solid(site["tile"])
	if _def(site).get("effect", "") == "gate":
		_update_gates()   # ворота при достройке сразу закрываются/открываются
	events.append({"type": "built", "bld": String(site["type"])})
	_assign_jobs()


## Житель стоял на тайле, где достроили стену, — шагает на свободный соседний,
## иначе тайл становится сплошным и человек остаётся замурован навсегда.
func _step_off_solid(tile: Vector2i) -> void:
	for r in residents:
		if map.tile_of_px(r["pos"]) != tile:
			continue
		var free := _nearest_walkable(tile)
		if not free == Vector2i(-1, -1):
			r["pos"] = map.tile_center_px(free)
		r["target"] = Vector2i(-1, -1)
		r["path"] = PackedVector2Array()


func _nearest_walkable(tile: Vector2i) -> Vector2i:
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n: Vector2i = tile + Vector2i(dx, dy)
				if map.is_walkable(n):
					return n
	return Vector2i(-1, -1)


# --- жители --------------------------------------------------------------

## Раздача работы: производственные здания и стройплощадки — свободным жителям.
## M4-подмена: если по профессии никого нет, свободный житель замещает (и учится),
## а держатель подмены возвращается на свою профессию, когда она понадобилась.
func _assign_jobs() -> void:
	var taken := {}   # id жителя -> занят
	for r in residents:
		if r["bld"] != null or r["site"] != null:
			taken[int(r["id"])] = true
	# 1. стройки — свободным строителям
	for b in buildings:
		if b["done"]:
			continue   # готовое производственное здание закрепляется ниже
		if int(b["worker"]) > 0 and taken.has(int(b["worker"])):
			continue
		var worker := _free_resident("builder", taken)
		if worker.is_empty():
			continue
		b["worker"] = int(worker["id"])
		worker["site"] = b
		worker["bld"] = null
		taken[int(worker["id"])] = true
	# 2. готовые здания — по основной профессии
	for b in buildings:
		if not b["done"] or not def_has_worker(b):
			continue
		if int(b["worker"]) > 0 and taken.has(int(b["worker"])):
			continue
		var worker := _free_resident(String(_def(b)["worker"]), taken)
		if worker.is_empty():
			continue   # попробуют замещающие ниже
		b["worker"] = int(worker["id"])
		worker["bld"] = b
		worker["site"] = null
		taken[int(worker["id"])] = true
	# 3. держатели подмен возвращаются на основную профессию, если она нужна
	_substitutes_to_primary(taken)
	# 4. подмена строек и зданий свободными жителями (с обучением)
	for b in buildings:
		if not bool(b["done"]) and (int(b["worker"]) <= 0 or not taken.has(int(b["worker"]))):
			_substitute_into("builder", taken, b, true)
	for b in buildings:
		if not b["done"] or not def_has_worker(b):
			continue
		if int(b["worker"]) > 0 and taken.has(int(b["worker"])):
			continue
		_substitute_into(String(_def(b)["worker"]), taken, b, false)
	# 5. всё ещё некому — сообщаем игроку
	for b in buildings:
		if not b["done"] or not def_has_worker(b):
			continue
		if int(b["worker"]) <= 0:
			events.append({"type": "no_worker", "bld": String(b["type"])})


## Держатель подмены возвращается на свою профессию, если по ней свободна работа.
func _substitutes_to_primary(taken: Dictionary) -> void:
	for r in residents:
		if String(r.get("sub_prof", "")) == "":
			continue
		var want := String(r["prof"])
		var target: Dictionary = {}
		if want == "builder":
			for b in buildings:
				if not bool(b["done"]) and int(b["worker"]) <= 0:
					target = b
					break
		if target.is_empty():
			for b in buildings:
				if not b["done"] or not def_has_worker(b):
					continue
				if String(_def(b)["worker"]) != want or int(b["worker"]) > 0:
					continue
				target = b
				break
		if target.is_empty():
			continue
		if r["bld"] != null:
			(r["bld"] as Dictionary)["worker"] = -1
		if r["site"] != null:
			(r["site"] as Dictionary)["worker"] = -1
		target["worker"] = int(r["id"])
		var is_site := not bool(target["done"])
		if is_site:
			r["site"] = target
			r["bld"] = null
		else:
			r["bld"] = target
			r["site"] = null
		r["sub_prof"] = ""
		taken[int(r["id"])] = true


## Свободный житель замещает нехватку профессии need: предпочитает выучившего,
## иначе учится сам (профессия попадает в prof_extra — ответ на просьбу заказчика).
func _substitute_into(need: String, taken: Dictionary, bld: Dictionary, is_site: bool) -> void:
	var learned_cand: Dictionary = {}
	var any_cand: Dictionary = {}
	for r in residents:
		if taken.has(int(r["id"])) or String(r["prof"]) == need:
			continue
		if String(r["prof"]) == "" or String(r.get("ail", "")) != "":
			continue
		if String(r["prof"]) == "elder":
			continue   # староста управляет, а не замещает
		if r["bld"] != null or r["site"] != null:
			continue
		if (r.get("prof_extra", []) as Array).has(need):
			learned_cand = r
			break
		if any_cand.is_empty():
			any_cand = r
	var cand: Dictionary = learned_cand if not learned_cand.is_empty() else any_cand
	if cand.is_empty():
		return
	var extras: Array = cand.get("prof_extra", [])
	var learned := not extras.has(need)
	if learned:
		extras.append(need)
		_chron("chron.learned", String(cand["name"]), need)
		events.append({"type": "learned", "name": String(cand["name"]), "prof": need})
	cand["sub_prof"] = need
	cand["site"] = bld if is_site else null
	cand["bld"] = null if is_site else bld
	bld["worker"] = int(cand["id"])
	taken[int(cand["id"])] = true


func def_has_worker(b: Dictionary) -> bool:
	return _def(b).has("worker")


## Свободный житель профессии prof (ничем не занят, здоров и не закреплён).
func _free_resident(prof: String, taken: Dictionary) -> Dictionary:
	for r in residents:
		if taken.has(int(r["id"])):
			continue
		if String(r.get("ail", "")) != "":
			continue   # больной работу не получает
		if String(r["prof"]) == prof and r["bld"] == null and r["site"] == null:
			return r
	return {}


# --- главный тик ---------------------------------------------------------

func tick(dt_raw: float) -> void:
	if paused or map == null:
		return
	var dt := dt_raw * speed
	var day_len := float(cfg["day_length"])
	time += dt
	day = int(time / day_len) + 1
	# еда: все жители едят непрерывно (обжора ×2, ребёнок ×0.5); пусто — город голодает
	var eaters := 0.0
	for r in residents:
		var portion := _trait_prod(r, "food_mult")
		if String(r["prof"]) == "":
			portion *= float(people.get("child_food", 0.5))
		eaters += portion
	var eat: float = float(cfg["food_per_resident_day"]) * dt / day_len * eaters
	res["food"] = maxf(0.0, float(res["food"]) - eat)
	_tavern_beer(dt, day_len)
	# инструменты изнашиваются у работающих (мастерская обновляет запас)
	var workers := 0
	for r in residents:
		if String(r["state"]) == "work" or String(r["state"]) == "build":
			workers += 1
	if workers > 0 and float(res.get("tools", 0.0)) > 0.0:
		res["tools"] = maxf(0.0, float(res["tools"]) - float(cfg.get("tools_wear_per_day", 0.1)) * workers * dt / day_len)
	# магия (M3): резонанс, спад загрязнения, стан зданий, дикие события
	if resonance_left > 0.0:
		resonance_left = maxf(0.0, resonance_left - dt)
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	if not pol_cfg.is_empty() and pollution > 0.0:
		pollution = maxf(0.0, pollution - float(pol_cfg.get("decay_per_day", 2.0))
				* research_mult("pollution_decay_mult", 1.0) * dt / day_len)
	for b in buildings:
		if float(b.get("stun_left", 0.0)) > 0.0:
			b["stun_left"] = maxf(0.0, float(b["stun_left"]) - dt)
	_update_gates()
	_update_wild_events(pol_cfg, day_len)
	_update_storm(dt, day_len)
	_update_threat(dt, day_len)
	_update_animals(dt)
	_update_livestock(dt)
	_update_zones(dt, day_len)
	_update_forest(dt, day_len)
	for r in residents:
		_update_resident(r, dt)
	# люди (M4): раз в игровой день — преемник старосты, болезни, беженцы, рождения, стройка, истории
	if day > _last_daily_day:
		_last_daily_day = day
		_ensure_elder()
		_roll_ailments()
		_roll_refugees()
		_roll_births()
		_roll_autobuild()
		_roll_stories()
		_roll_couples()
		_roll_festival()
		_roll_guards()
		_roll_hunter()
		_roll_porter()
		_roll_auto_roads()
		_roll_animals()
		_roll_storm()
		_roll_livestock()
		_roll_market()
		_tick_caravans()
		_tick_orchards()
		_roll_necro()
		_roll_v3()   # жизнь v3 (M14-F): память, отношения, личные цели
	_update_gates()   # достроенные за тик вышки/ворота сразу меняют проходимость


## Дикие события (ответ №61): при переборе загрязнения (>= band_wild) раз в день
## с шансом event_chance_per_day: вспышка (стан здания), прилив маны (+загрязнение,
## усталость), сгущение маны (+кристалл). Защищает только зачарование «Оберег».
func _update_wild_events(pol_cfg: Dictionary, day_len: float) -> void:
	if pol_cfg.is_empty() or pollution < float(pol_cfg.get("band_wild", 85.0)):
		return
	if day == _last_event_day:
		return
	_last_event_day = day
	if _event_rng.randf() > float(pol_cfg.get("event_chance_per_day", 0.5)):
		return
	var kind := _weighted_pick(pol_cfg.get("event_weights", {"flash": 5, "surge": 3, "gift": 2}))
	match kind:
		"flash":
			var target := _wild_flash_target()
			if target.is_empty():
				_wild_surge(pol_cfg)
				return
			target["stun_left"] = float(pol_cfg.get("flash_stun_days", 1.0)) * day_len
			events.append({"type": "wild_flash", "bld": String(target["type"])})
		"surge":
			_wild_surge(pol_cfg)
		"gift":
			_add_resource_capped("crystal", float(pol_cfg.get("gift_crystals", 1)))
			events.append({"type": "wild_gift"})


func _wild_surge(pol_cfg: Dictionary) -> void:
	pollution = minf(float(pol_cfg.get("max", 100.0)), pollution + float(pol_cfg.get("surge_pollution", 5.0)))
	for r in residents:
		r["fatigue"] = float(r["fatigue"]) + float(pol_cfg.get("surge_fatigue", 0.2))
	events.append({"type": "wild_surge"})
	# дикая мана калечит (M4): случайный взрослый получает рану
	var acfg: Dictionary = people.get("ailments", {})
	var wounded_n := int(acfg.get("wounded_on_surge", 1))
	var adults := _adults()
	for i in wounded_n:
		if adults.is_empty():
			break
		var r: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
		_make_ail(r, "wounded", "chron.wounded")
		events.append({"type": "wounded", "name": String(r["name"])})


## Случайное готовое здание без «Оберега» (для дикой вспышки).
func _wild_flash_target() -> Dictionary:
	var candidates: Array = []
	for b in buildings:
		if bool(b["done"]) and String(b.get("enchant", "")) != "ward":
			candidates.append(b)
	if candidates.is_empty():
		return {}
	return candidates[_event_rng.randi_range(0, candidates.size() - 1)]


func _weighted_pick(weights: Dictionary) -> String:
	var total := 0
	for w: int in weights.values():
		total += w
	var roll := _event_rng.randi_range(1, maxi(1, total))
	for key in weights:
		roll -= int(weights[key])
		if roll <= 0:
			return String(key)
	return ""


func _update_resident(r: Dictionary, dt: float) -> void:
	var day_len := float(cfg["day_length"])
	_update_mood(r, dt, day_len)
	r["chat_cd_left"] = maxf(0.0, float(r.get("chat_cd_left", 0.0)) - dt)
	# голод: без дела — идёт в очередь к складу; занятый работает вполсилы (иначе город умирает навсегда)
	if float(res["food"]) <= 0.0 and r["site"] == null and r["bld"] == null:
		_hungry_queue(r, dt)
		return
	# ребёнок: растёт, не работает; играет у колодца (M12); повзрослел — профессия и черты
	if String(r["prof"]) == "":
		_child_update(r, dt, day_len)
		return
	# болен или ранен: идёт домой и лежит
	if String(r.get("ail", "")) != "":
		_lie_ill(r, dt)
		return
	var night := is_night()
	var tcfg: Dictionary = cfg.get("threat", {})
	# угроза (M5+): трус прячется сразу с предупреждения, бойцы снаряжаются в оружейке
	if raid_active or _raid_warned:
		if _has_trait_flag(r, "flees"):
			_flee_home(r, dt)
			return
		if String(r["prof"]) == "guard":
			_defender_update(r, dt, float(tcfg.get("guard_damage", 2)), float(tcfg.get("guard_cd", 1.0)))
			return
		if _raid_warned and not raid_active:
			_gather_fire(r, dt)   # сбор у костра: город ждёт волну вместе (M12)
			return
	if raid_active:
		# ополчение: бьются все свободные взрослые и храбрые работники (заказчик)
		var free := r["site"] == null and r["bld"] == null
		if (free or _has_trait_flag(r, "fearless")) \
				and String(r["prof"]) != "" and String(r["prof"]) != "elder":
			_defender_update(r, dt, float(tcfg.get("militia_damage", 1)), float(tcfg.get("militia_cd", 1.5)))
			return
	# похороны (M12): носильщики процессии идут к кладбищу
	if int(r.get("funeral", 0)) > 0:
		_funeral_update(r, dt)
		return
	# ночь: спят все, кроме стража ночной смены (дежурство день/ночь — заказчик)
	var guard_on_duty := String(r["prof"]) == "guard" \
			and ((night and String(r.get("shift", "day")) == "night") \
				or (not night and String(r.get("shift", "day")) == "day"))
	if night and not guard_on_duty:
		_sleep(r, dt)
		return
	# сильная усталость: отдых в любое время
	if float(r["fatigue"]) >= float(cfg["tired_at"]):
		r["state"] = "rest"
		r["fatigue"] = maxf(0.0, float(r["fatigue"]) - _restore_rate(r, false) * dt / day_len)
		r["path"] = PackedVector2Array()
		return
	# вечер (M12, имитация жизни): работа кончилась — таверна, костёр, визиты к друзьям
	if not raid_active and not _raid_warned and _is_evening() \
			and r["site"] == null and String(r["prof"]) != "elder":
		_leisure(r, dt)
		return
	if r["site"] != null:
		_do_build(r, r["site"], dt)
		return
	if r["bld"] != null:
		var bld_type := String(r["bld"]["type"])
		if _def(r["bld"]).has("produce"):
			# добытчики работают у источника: лесоруб — у дерева, каменотёс — у скалы (заказчик)
			if bld_type == "workshop":
				_workshop_work(r, r["bld"], dt)   # сперва ремонт повреждённых, потом переработка (M6)
			elif bld_type == "sawmill" or bld_type == "quarry":
				_gather_work(r, r["bld"], dt)
			else:
				_do_work(r, r["bld"], dt)
		elif guard_on_duty:
			_guard_post(r, dt)   # на смене — стоит на посту (вышка рядом открывает ворота)
		elif String(r["prof"]) == "guard" and _help_build(r, dt):
			pass                 # вне смены страж помогает городу строить (заказчик)
		elif String(r["prof"]) == "guard" and _guard_patrol(r, dt):
			pass                 # строек нет — страж обходит ворота (M12)
		else:
			r["state"] = "idle"
		return
	if String(r["prof"]) == "hunter":
		_hunt(r, dt)
		return
	if String(r["prof"]) == "porter":
		_porter_work(r, dt)   # носит кучи со зданий на склад (M6)
		return
	if String(r["prof"]) == "elder":
		_manage_walk(r, dt)
		return
	if guard_on_duty:
		_guard_post(r, dt)
		return
	if _zone_fill_work(r, dt):
		return   # свободный житель обустраивает зоны (M6: город заполняет их сам)
	if _help_build(r, dt):
		return   # свободный житель в мирное время тоже помогает строить (заказчик)
	r["state"] = "idle"


## Страж на посту: стоит у закреплённой вышки.
func _guard_post(r: Dictionary, dt: float) -> void:
	var tower := _assigned_done(r, "guard")
	if not tower.is_empty():
		if _arrived(r, tower["tile"]):
			r["state"] = "guard"
			r["fatigue"] += dt / float(cfg["day_length"])
		else:
			_move_towards(r, tower["tile"], dt)
	else:
		r["state"] = "idle"


## Страж вне смены помогает городу: строит ближайшую площадку. False — помогать нечем.
func _help_build(r: Dictionary, dt: float) -> bool:
	if raid_active or _raid_warned:
		return false   # при угрозе все силы — обороне
	var site: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if bool(b["done"]):
			continue
		var d: float = map.tile_center_px(b["tile"]).distance_to(r["pos"])
		if d < best_d:
			best_d = d
			site = b
	if site.is_empty():
		return false
	_do_build(r, site, dt)
	return true


# --- имитация жизни v1 (M12) -------------------------------------------------

## Вечер: доля дня от конца работы до ночи — город живёт (таверна, костёр).
func _is_evening() -> bool:
	var day_len := float(cfg["day_length"])
	var life: Dictionary = cfg.get("life", {})
	var evening: float = float(life.get("evening_len", 0.14))
	var nf := float(cfg["night_fraction"])
	var t := fmod(time, day_len) / day_len
	return t >= maxf(0.0, 1.0 - nf - evening) and t < 1.0 - nf


## Точка городского костра (M12): у колодца, если он есть, иначе в центре.
func fire_tile() -> Vector2i:
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == "well":
			return Vector2i(b["tile"]) + Vector2i(1, 0)
	return map.spawn_tile


## Вечерний досуг: таверна (если стоит), визит к другу, костёр в центре.
func _leisure(r: Dictionary, dt: float) -> void:
	var lcfg: Dictionary = cfg.get("life", {})
	# разговор: стоит, пока звучит реплика
	if float(r.get("chat_left", 0.0)) > 0.0:
		r["chat_left"] = float(r["chat_left"]) - dt
		if float(r["chat_left"]) <= 0.0:
			r["chat_key"] = ""
			r["chat_left"] = 0.0
			r["state"] = "leisure"
		else:
			r["state"] = "chat"
			r["path"] = PackedVector2Array()
		return
	var plan: Dictionary = r.get("leisure", {})
	if plan.is_empty() or (plan.has("tile") and not map.in_bounds(Vector2i(plan["tile"]))):
		plan = _pick_leisure(r)
		r["leisure"] = plan
	var target: Vector2i = Vector2i(plan.get("tile", map.spawn_tile))
	if not _arrived(r, target):
		_move_towards(r, target, dt)
		if String(r["state"]) != "going":
			r["state"] = "leisure"   # не добрался (замурован) — гуляет где стоит
	if _arrived(r, target):
		r["state"] = "leisure"
		r["path"] = PackedVector2Array()
		# личная цель «пировать в таверне» (M14-F): вечер в таверне засчитан
		if bool(plan.get("tavern", false)):
			r["tavern_visited"] = true
		_try_chat(r)


## Выбор вечернего занятия: в День основания — весь город гуляет (M13),
## иначе таверна 50%, любимый 60% / друг 40%, костёр — остальное.
func _pick_leisure(r: Dictionary) -> Dictionary:
	var tavern := _nearest_done_of_type(r["pos"], "tavern")
	var plan: Dictionary
	if _festival_today():
		if not tavern.is_empty() and randf() < 0.7:
			plan = {"tile": map.nearest_walkable(Vector2i(tavern["tile"]) + Vector2i(1, 0)), "tavern": true}
		else:
			plan = {"tile": map.nearest_walkable(fire_tile())}
	else:
		var partner := _partner_of(r)
		if not partner.is_empty() and randf() < 0.6:
			plan = {"tile": map.nearest_walkable(map.tile_of_px(partner["pos"]))}
		elif not tavern.is_empty() and randf() < 0.5:
			plan = {"tile": map.nearest_walkable(Vector2i(tavern["tile"]) + Vector2i(1, 0)), "tavern": true}
		else:
			var friend := _friend_of(r)
			if not friend.is_empty() and randf() < 0.4:
				plan = {"tile": map.nearest_walkable(map.tile_of_px(friend["pos"]))}
			else:
				plan = {"tile": map.nearest_walkable(fire_tile())}
	# ссорящиеся (M14-F) избегают друг друга вечером: цель рядом с врагом — к костру
	var foe: Dictionary = rel_worst(r)
	if not foe.is_empty():
		var foe_tile: Vector2i = map.tile_of_px(foe["other"]["pos"])
		if Vector2i(plan["tile"]).distance_to(foe_tile) <= 2:
			plan = {"tile": map.nearest_walkable(fire_tile())}
	return plan


func _friend_of(r: Dictionary) -> Dictionary:
	var fid := int(r.get("friend", -1))
	if fid < 0:
		return {}
	for other in residents:
		if int(other["id"]) == fid and String(other.get("ail", "")) == "":
			return other
	return {}


func _partner_of(r: Dictionary) -> Dictionary:
	var pid := int(r.get("partner", -1))
	if pid < 0:
		return {}
	for other in residents:
		if int(other["id"]) == pid and String(other.get("ail", "")) == "":
			return other
	return {}


## День основания (M13): каждые N дней весь город гуляет у таверны и костра.
func _festival_today() -> bool:
	var every := int(cfg.get("life", {}).get("festival_every_days", 0))
	return every > 0 and day_number() % every == 0 and not is_night()


## Разговор (M12): два праздных жителя рядом обмениваются репликой-облачком.
## В День основания — праздничные реплики, пары говорят о своём (M13).
func _try_chat(r: Dictionary) -> void:
	var lcfg: Dictionary = cfg.get("life", {})
	if float(r.get("chat_cd_left", 0.0)) > 0.0:
		return
	for other in residents:
		if other == r or String(other["prof"]) == "":
			continue
		var st := String(other.get("state", ""))
		if st != "leisure" and st != "chat":
			continue
		if float(other.get("chat_left", 0.0)) > 0.0 or float(other.get("chat_cd_left", 0.0)) > 0.0:
			continue
		if Vector2(other["pos"]).distance_to(Vector2(r["pos"])) > float(map.ts) * 1.5:
			continue
		var base := "chat"
		var lines := maxi(1, int(lcfg.get("chat_lines", 8)))
		if _festival_today():
			base = "fest"
			lines = maxi(1, int(lcfg.get("festival_lines", 4)))
		elif int(other.get("partner", -1)) == int(r["id"]):
			base = "love"
			lines = maxi(1, int(lcfg.get("love_lines", 4)))
		elif _rel_score(r, int(other["id"])) <= float(_v3().get("foe_threshold", -30.0)):
			# ссорящиеся (M14-F): обмениваются колкостями
			base = "spite"
			lines = maxi(1, int(_v3().get("spite_lines", 4)))
		var key := "%s.%d" % [base, randi() % lines]
		r["chat_key"] = key
		other["chat_key"] = key
		r["chat_left"] = float(lcfg.get("chat_seconds", 4.0))
		other["chat_left"] = float(lcfg.get("chat_seconds", 4.0))
		r["chat_cd_left"] = float(lcfg.get("chat_cd", 25.0))
		other["chat_cd_left"] = float(lcfg.get("chat_cd", 25.0))
		return


## Голодный (M12): идёт в очередь к складу (или к центру, если склада нет).
## state остаётся "hungry" и в пути — панель жителей объясняет простой.
func _hungry_queue(r: Dictionary, dt: float) -> void:
	var barn := _nearest_done_of_type(r["pos"], "warehouse")
	var goal: Vector2i = Vector2i(barn["tile"]) if not barn.is_empty() else map.spawn_tile
	if _arrived(r, goal):
		r["state"] = "hungry"
		r["path"] = PackedVector2Array()
		return
	_move_towards(r, map.nearest_walkable(goal), dt)
	r["state"] = "hungry"   # _move_towards ставит "going" — голод важнее


## Ребёнок (M12): растёт и играет у костра — бегает между соседними тайлами.
func _child_update(r: Dictionary, dt: float, day_len: float) -> void:
	r["age_days"] = float(r.get("age_days", 0.0)) + dt / day_len
	var bcfg: Dictionary = people.get("births", {})
	if float(r["age_days"]) >= float(bcfg.get("child_days", 8.0)):
		_grow_up(r)
		return
	var base := fire_tile()
	var target: Vector2i = Vector2i(r.get("play_tile", base))
	if not _arrived(r, target):
		_move_towards(r, target, dt)
		if String(r["state"]) != "going":
			r["state"] = "child"
		return
	r["state"] = "child"
	r["path"] = PackedVector2Array()
	r["play_left"] = float(r.get("play_left", 0.0)) - dt
	if float(r["play_left"]) <= 0.0:
		r["play_left"] = 2.0 + randf() * 3.0
		var off := Vector2i(randi_range(-2, 2), randi_range(-2, 2))
		r["play_tile"] = map.nearest_walkable(base + off)


## Тревога (M12): свободные жители собираются у костра, пока звучит предупреждение.
func _gather_fire(r: Dictionary, dt: float) -> void:
	var ring := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	var target: Vector2i = map.nearest_walkable(fire_tile() + ring[int(r["id"]) % ring.size()])
	r["state"] = "gather"
	if _arrived(r, target):
		r["path"] = PackedVector2Array()
		return
	_move_towards(r, target, dt)


## Похороны (M12): носильщик дошёл до кладбища — стоит прощание, могилка готова.
func _funeral_update(r: Dictionary, dt: float) -> void:
	if not _arrived(r, funeral_target):
		_move_towards(r, funeral_target, dt)
		if String(r["state"]) != "going":
			r["funeral"] = 0   # не добрался — вернулся к делам
		return
	r["state"] = "funeral"
	r["path"] = PackedVector2Array()
	r["funeral_wait"] = float(r.get("funeral_wait", 0.0)) + dt
	if float(r["funeral_wait"]) >= 2.0:
		r["funeral"] = 0
		r["funeral_wait"] = 0.0
		for g in graves:
			g["ready"] = true


## Запуск похорон: свободные жители несут умершего к кладбищу, готовится могилка.
func _start_funeral(dead: Dictionary, dead_pos: Vector2) -> void:
	var cemetery: Dictionary = {}
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == "cemetery":
			cemetery = b
			break
	if cemetery.is_empty():
		return
	var grave := _next_grave_tile(Vector2i(cemetery["tile"]))
	if grave == Vector2i(-1, -1):
		return
	funeral_target = map.nearest_walkable(Vector2i(cemetery["tile"]))
	funeral_pos = dead_pos
	graves.append({"tile": grave, "name": String(dead["name"]), "ready": false})
	var bearers := 0
	for other in residents:
		if other == dead or String(other["prof"]) == "" or String(other.get("ail", "")) != "":
			continue
		if other["site"] != null or other["bld"] != null or int(other.get("funeral", 0)) > 0:
			continue
		other["funeral"] = 1
		other["funeral_wait"] = 0.0
		bearers += 1
		if bearers >= 2:
			break


## Место под могилку: свободный травяной тайл по спирали вокруг кладбища.
func _next_grave_tile(center: Vector2i) -> Vector2i:
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := center + Vector2i(dx, dy)
				if not map.in_bounds(t) or not map.is_nature_walkable(t):
					continue
				if not building_at(t).is_empty():
					continue
				var taken := false
				for g in graves:
					if Vector2i(g["tile"]) == t:
						taken = true
						break
				if not taken:
					return t
	return Vector2i(-1, -1)


## Патруль стража вне смены (M12): обходит ворота по кругу. False — ворот нет.
func _guard_patrol(r: Dictionary, dt: float) -> bool:
	var gates: Array = []
	for b in buildings:
		if bool(b["done"]) and String(_def(b).get("effect", "")) == "gate":
			gates.append(Vector2i(b["tile"]))
	if gates.is_empty():
		return false
	var i := int(r.get("patrol_i", 0)) % gates.size()
	var target: Vector2i = map.nearest_walkable(gates[i])
	if _arrived(r, target):
		r["patrol_i"] = i + 1
		r["state"] = "patrol"
		r["path"] = PackedVector2Array()
		return true
	_move_towards(r, target, dt)
	if String(r["state"]) != "going":
		r["patrol_i"] = i + 1
		r["state"] = "patrol"
	return true


func _sleep(r: Dictionary, dt: float) -> void:
	if r["home"] == null:
		r["home"] = _free_home(r)
	var home: Dictionary = r["home"]
	if not home.is_empty():
		if not _arrived(r, home["tile"]):
			_move_towards(r, home["tile"], dt)
			return
	r["state"] = "sleep"
	r["fatigue"] = maxf(0.0, float(r["fatigue"]) - _restore_rate(r, true) * dt / float(cfg["day_length"]))


## Свободный готовый дом (до pop_per_house спящих).
func _free_home(r: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	var counts := {}
	for other in residents:
		if other["home"] != null and not other["home"].is_empty():
			var hb: Dictionary = other["home"]
			counts[int(hb["id"])] = int(counts.get(int(hb["id"]), 0)) + 1
	for b in buildings:
		if not b["done"] or _def(b).get("effect", "") != "pop":
			continue
		if int(counts.get(int(b["id"]), 0)) >= int(cfg["pop_per_house"]):
			continue
		var dist: float = map.tile_center_px(b["tile"]).distance_to(r["pos"])
		if dist < best_dist:
			best_dist = dist
			best = b
	return best


## Скорость восстановления усталости (в единицах усталости за игровой день).
## Дом ускоряет сон, колодец ускоряет любой отдых.
func _restore_rate(r: Dictionary, sleeping: bool) -> float:
	var base: float = float(cfg["sleep_restore_home"] if sleeping and r["home"] != null and not r["home"].is_empty() else cfg["sleep_restore_no_home"])
	if not sleeping:
		base *= float(cfg["rest_fraction"])
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "sleep":
			base *= 1.0 + float(cfg["well_bonus"])
			break
	return base


## Боец (страж или ополченец) при угрозе: без комплекта идёт в оружейку
## (страж перед осадой снаряжается и ждёт — заказчик), с комплектом бьёт сильнее.
func _defender_update(r: Dictionary, dt: float, dmg: float, cd: float) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	var armory := _done_building_of_type("armory")
	# снаряжение: в хранилище есть комплекты, боец ещё без него
	if not bool(r.get("kit", false)) and float(res.get("kits", 0.0)) > 0.0 and not armory.is_empty():
		if _arrived(r, armory["tile"]):
			res["kits"] = maxf(0.0, float(res["kits"]) - 1.0)
			r["kit"] = true
		else:
			_move_towards(r, armory["tile"], dt)
			return
	var mult := float(tcfg.get("kit_damage_mult", 2.0)) if bool(r.get("kit", false)) else 1.0
	var target := _nearest_raider(r["pos"], float(map.ts) * 10.0)
	if target.is_empty():
		# волна ещё в пути: страж ждёт на вышке, ополчение — в центре города
		if String(r["prof"]) == "guard":
			var tower := _assigned_done(r, "guard")
			if not tower.is_empty():
				if _arrived(r, tower["tile"]):
					r["state"] = "guard"
				else:
					_move_towards(r, tower["tile"], dt)
				return
		if not _arrived(r, map.spawn_tile + Vector2i(1, 0)):
			_move_towards(r, map.spawn_tile + Vector2i(1, 0), dt)
		else:
			r["state"] = "guard"
		return
	var dist: float = (target["pos"] as Vector2).distance_to(r["pos"])
	if dist <= float(map.ts) * 1.5:
		r["atk_cd"] = maxf(0.0, float(r.get("atk_cd", 0.0)) - dt)
		if float(r["atk_cd"]) <= 0.0:
			r["atk_cd"] = cd
			_hit_raider(target, int(round(dmg * mult)))
		r["state"] = "guard"
	else:
		_move_towards(r, map.tile_of_px(target["pos"]), dt)


func _done_building_of_type(type_id: String) -> Dictionary:
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == type_id:
			return b
	return {}


## Трус прячется дома, пока в городе мутанты.
func _flee_home(r: Dictionary, dt: float) -> void:
	if r["home"] == null:
		r["home"] = _free_home(r)
	var home: Dictionary = r["home"]
	if not home.is_empty() and not _arrived(r, home["tile"]):
		_move_towards(r, home["tile"], dt)
		return
	r["state"] = "hide"


func _do_build(r: Dictionary, site: Dictionary, dt: float) -> void:
	if site["done"]:
		r["site"] = null
		r["sub_prof"] = ""
		return
	if _arrived(r, site["tile"]):
		r["state"] = "build"
		site["progress"] = float(site["progress"]) + dt * work_mult(r)
		r["fatigue"] += dt / float(cfg["day_length"])
		_grow_skill(r, dt)
		if float(site["progress"]) >= float(_def(site)["build_work"]):
			r["site"] = null
			r["sub_prof"] = ""
			_complete_site(site)
	else:
		_move_towards(r, site["tile"], dt)


func _do_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		# дикая вспышка: здание молчит, работник стоит
		r["state"] = "idle"
		return
	if _arrived(r, bld["tile"]):
		_produce_tick(r, bld, dt)
	else:
		_move_towards(r, bld["tile"], dt)


## Добытчик (лесоруб/каменотёс) работает у источника: ходит к дереву или скале
## рядом со зданием и добывает именно там (заказчик). Источника нет — работает у здания.
## M11: лесоруб РУБИТ дерево — за chop_days оно падает (пень + гнев леса).
func _gather_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		r["state"] = "idle"
		return
	var res_tile: Vector2i = _gather_target(r, bld)
	if res_tile == Vector2i(-1, -1):
		_produce_tick(r, bld, dt)
		return
	if map.tile_of_px(r["pos"]) != res_tile:
		_move_towards(r, res_tile, dt)
		return
	if String(bld["type"]) == "sawmill":
		_chop_tree(r, dt)
	_produce_tick(r, bld, dt)


## Рубка (M11): накопив chop_days на тайле дерева, лесоруб валит его.
func _chop_tree(r: Dictionary, dt: float) -> void:
	var tile: Vector2i = map.tile_of_px(r["pos"])
	if map.grid[tile.y][tile.x] != map.TILE_TREE:
		r["chop_t"] = 0.0
		return
	var fcfg: Dictionary = cfg.get("forest", {})
	r["chop_t"] = float(r.get("chop_t", 0.0)) + dt
	var need := float(fcfg.get("chop_days", 0.5)) * float(cfg["day_length"])
	if float(r["chop_t"]) < need:
		return
	r["chop_t"] = 0.0
	map.grid[tile.y][tile.x] = map.TILE_GRASS
	map.stumps[tile] = true
	terrain_dirty = true
	forest_anger = clampf(forest_anger + float(fcfg.get("anger_per_tree", 2.5)), 0.0, 100.0)
	events.append({"type": "tree_felled"})
	_chron("chron.tree_felled")
	r["gath_tile"] = Vector2i(-1, -1)


## Тайл, у которого добытчик работает: ближайший к зданию подходящий тайл природы
## (для дерева — само дерево, для скалы — проходимый сосед). Кэшируется на жителе.
func _gather_target(r: Dictionary, bld: Dictionary) -> Vector2i:
	var kinds: Array = [map.TILE_TREE] if String(bld["type"]) == "sawmill" else [map.TILE_ROCK, map.TILE_ORE]
	var cached: Vector2i = r.get("gath_tile", Vector2i(-1, -1))
	if cached != Vector2i(-1, -1) and map.in_bounds(cached) and map.is_walkable(cached) \
			and cached != (bld["tile"] as Vector2i) \
			and not (String(bld["type"]) == "sawmill" and map.grid[cached.y][cached.x] != map.TILE_TREE):
		return cached
	var radius := int(cfg.get("gather_range", 6))
	var best_kind := Vector2i(-1, -1)
	var kind_d := INF
	var best_near := Vector2i(-1, -1)
	var near_d := INF
	var bc: Vector2i = bld["tile"]
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t: Vector2i = bc + Vector2i(dx, dy)
			if not map.in_bounds(t) or not map.is_walkable(t) or t == bc:
				continue
			var d: float = Vector2(t).distance_to(Vector2(bc))
			if map.grid[t.y][t.x] in kinds:
				# источник проходим (дерево) — стоим прямо на нём
				if d < kind_d:
					kind_d = d
					best_kind = t
			else:
				# непроходимый источник (скала, руда) — стоим на соседнем тайле
				for n in [t + Vector2i(1, 0), t + Vector2i(-1, 0), t + Vector2i(0, 1), t + Vector2i(0, -1)]:
					if map.in_bounds(n) and map.grid[n.y][n.x] in kinds:
						if d < near_d:
							near_d = d
							best_near = t
						break
	var best := best_kind if best_kind != Vector2i(-1, -1) else best_near
	r["gath_tile"] = best
	return best


## Мастерская (M6, перепрофилирование): сперва чинит повреждённые здания,
## когда чинить нечего — перерабатывает дерево и камень в инструменты.
func _workshop_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		r["state"] = "idle"
		return
	var broken := _damaged_building(bld)
	if broken.is_empty():
		_produce_tick(r, bld, dt)   # переработка излишков в инструменты
		return
	if _arrived(r, broken["tile"]):
		r["state"] = "repair"
		var rate: float = float(cfg.get("repair", {}).get("per_day", 15.0)) * work_mult(r)
		var max_hp := float(_bld_max_hp(String(broken["type"])))
		broken["hp"] = minf(float(broken.get("hp", max_hp)) + rate * dt / float(cfg["day_length"]), max_hp)
		r["fatigue"] += dt / float(cfg["day_length"])
		_grow_skill(r, dt)
	else:
		_move_towards(r, broken["tile"], dt)


## Повреждённое готовое здание ближе прочих (для мастерской).
func _damaged_building(near: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if not bool(b["done"]):
			continue
		var max_hp := float(_bld_max_hp(String(b["type"])))
		if float(b.get("hp", max_hp)) >= max_hp:
			continue
		var d: float = map.tile_center_px(b["tile"]).distance_to(map.tile_center_px(near["tile"]))
		if d < best_d:
			best_d = d
			best = b
	return best



## Само производство: расход материалов, множители, добавка в КУЧУ у здания.
## Общее для работников у здания и добытчиков у источника. В общий пул ресурс
## попадает только с носильщиком (M6: физическая логистика, ответ №20).
func _produce_tick(r: Dictionary, bld: Dictionary, dt: float) -> void:
	r["state"] = "work"
	r["fatigue"] += dt / float(cfg["day_length"])
	_grow_skill(r, dt)
	var prod: Dictionary = _def(bld)["produce"]
	# расход материалов (мастерская: дерево + камень -> инструменты)
	var portion: float = dt / float(cfg["day_length"])
	var inputs: Dictionary = prod.get("inputs", {})
	for key in inputs:
		if float(res.get(String(key), 0.0)) < float(inputs[key]) * portion:
			r["state"] = "idle"   # материалы кончились — стоит
			return
	for key in inputs:
		res[String(key)] = maxf(0.0, float(res[key]) - float(inputs[key]) * portion)
	var boost: float = float(cfg["altar_boost"]) if has_blessing() else 1.0
	var amount: float = float(prod["per_day"]) * portion * boost * production_mult(bld) * work_mult(r)
	_add_pile(bld, String(prod["res"]), amount)
	# шахта даёт и камень вместе с рудой (заказчик)
	if prod.has("res2"):
		var amount2: float = float(prod["per_day2"]) * portion * boost * production_mult(bld) * work_mult(r)
		_add_pile(bld, String(prod["res2"]), amount2)
	# каменотёс вырабатывает тайл гряды (M11): на месте истощённой скалы
	# вскрывается рудная жила или попадается кристалл — полезные материалы
	if String(bld["type"]) == "quarry":
		_deplete_rock(r, bld, portion)


## Куча у здания (M6): производство копится здесь, пока её не унесёт носильщик.
func _add_pile(bld: Dictionary, key: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var pile: Dictionary = bld.get("pile", {})
	var total := 0.0
	for k in pile:
		total += float(pile[k])
	var left: float = maxf(0.0, float(cfg.get("piles", {}).get("max", 20.0)) - total)
	if left <= 0.0:
		return
	pile[key] = float(pile.get(key, 0.0)) + minf(amount, left)
	bld["pile"] = pile


## Всего ресурса key в кучах по всем зданиям (для запаса еды город учитывает и кучи).
func _piled_total_of(key: String) -> float:
	var total := 0.0
	for b in buildings:
		if not bool(b["done"]) or not (b as Dictionary).has("pile"):
			continue
		total += float((b["pile"] as Dictionary).get(key, 0.0))
	return total


func _pile_total(b: Dictionary) -> float:
	var total := 0.0
	for k in b.get("pile", {}):
		total += float(b["pile"][k])
	return total


## Закреплённое готовое здание с работником r (для вышки стража).
func _assigned_done(r: Dictionary, worker_prof: String) -> Dictionary:
	for b in buildings:
		if b["done"] and int(b["worker"]) == int(r["id"]) and String(_def(b).get("worker", "")) == worker_prof:
			return b
	return {}


func _arrived(r: Dictionary, tile: Vector2i) -> bool:
	return map.tile_of_px(r["pos"]) == tile


func _move_towards(r: Dictionary, tile: Vector2i, dt: float) -> void:
	r["state"] = "going"
	if r["target"] != tile:
		r["target"] = tile
		r["path"] = map.path_px(r["pos"], tile)
	var path: PackedVector2Array = r["path"]
	if path.is_empty():
		# страховка: замурован на сплошном тайле (стену достроили под ногами)
		var here: Vector2i = map.tile_of_px(r["pos"])
		if not map.is_walkable(here):
			var free := _nearest_walkable(here)
			if not free == Vector2i(-1, -1):
				r["pos"] = map.tile_center_px(free)
				r["target"] = Vector2i(-1, -1)
				return
		r["state"] = "idle"
		return
	var pos: Vector2 = r["pos"]
	var step: float = float(cfg["resident_speed"]) * dt
	# дорога под ногами ускоряет; носильщику — сильнее всех (M6)
	if map.has_road(map.tile_of_px(pos)):
		var rcfg: Dictionary = cfg.get("roads", {})
		step *= float(rcfg.get("porter_mult", 1.8)) if String(r["prof"]) == "porter" \
				else float(rcfg.get("mult", 1.4))
	var step_total := step
	while step > 0.0 and not path.is_empty():
		var to_next: Vector2 = path[0] - pos
		var dist := to_next.length()
		if dist <= step:
			pos = path[0]
			step -= dist
			path.remove_at(0)
		else:
			pos += to_next / dist * step
			step = 0.0
		if absf(to_next.x) >= absf(to_next.y) and absf(to_next.x) > 0.5:
			r["dir"] = "left" if to_next.x < 0.0 else "right"
		elif absf(to_next.y) > 0.5:
			r["dir"] = "back" if to_next.y < 0.0 else "front"
	r["pos"] = pos
	r["path"] = path
	# протоптанная тропа (M6): сколько прошёл — столько износа оставил
	var moved := step_total - step
	r["moving"] = moved > 0.05
	if moved > 0.0:
		map.add_wear(map.tile_of_px(pos), moved / float(map.ts) * float(cfg.get("roads", {}).get("wear_per_tile", 1.0)))


# --- носильщик и физический склад (M6, ответ №20) ---------------------------

## Носильщик: берёт готовую кучу у здания (>= chunk), несёт на склад —
## общий пул теперь физическое хранилище.
func _porter_work(r: Dictionary, dt: float) -> void:
	if float(r.get("carry", 0.0)) > 0.0:
		# склад — физическое хранилище; пока склада нет, носит к городскому амбару
		var barn := _nearest_done_of_type(r["pos"], "warehouse")
		var goal_tile: Vector2i = barn["tile"] if not barn.is_empty() else map.spawn_tile
		if _arrived(r, goal_tile):
			var key := String(r["carry_res"])
			var free: float = float(storage_cap()) - float(res.get(key, 0.0))
			var drop: float = minf(float(r["carry"]), maxf(0.0, free))
			if drop > 0.0:
				res[key] = float(res.get(key, 0.0)) + drop
				r["carry"] = float(r["carry"]) - drop
				r["state"] = "porter"
			if float(r["carry"]) <= 0.001:
				r["carry"] = 0.0
				r["carry_res"] = ""
			else:
				r["state"] = "idle"   # хранилище полно — ждёт с грузом
		else:
			_move_towards(r, goal_tile, dt)
		return
	var target := _biggest_ready_pile(r)
	if target.is_empty():
		r["state"] = "idle"
		return
	if _arrived(r, target["tile"]):
		var pile: Dictionary = target.get("pile", {})
		var key := ""
		var best := 0.0
		for k in pile:
			if float(pile[k]) > best:
				best = float(pile[k])
				key = String(k)
		if key == "":
			r["state"] = "idle"
			return
		var take: float = minf(float(cfg.get("piles", {}).get("carry", 10.0)), float(pile[key]))
		pile[key] = float(pile[key]) - take
		if float(pile[key]) <= 0.0001:
			pile.erase(key)
		target["pile"] = pile
		r["carry"] = take
		r["carry_res"] = key
		r["state"] = "porter"
	else:
		_move_towards(r, target["tile"], dt)


## Готовое здание с самой большой кучей (>= chunk); при равенстве — ближайшее.
func _biggest_ready_pile(from: Dictionary) -> Dictionary:
	var chunk: float = float(cfg.get("piles", {}).get("chunk", 8.0))
	var best: Dictionary = {}
	var best_amt := -1.0
	var best_d := INF
	for b in buildings:
		if not bool(b["done"]):
			continue
		var amt := _pile_total(b)
		if amt < chunk:
			continue
		var d: float = map.tile_center_px(b["tile"]).distance_to(from["pos"])
		if amt > best_amt + 0.0001 or (absf(amt - best_amt) <= 0.0001 and d < best_d):
			best_amt = amt
			best_d = d
			best = b
	return best


## Ближайшее готовое здание заданного типа (для носильщика — склад).
func _nearest_done_of_type(from_px: Vector2, type_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if not bool(b["done"]) or String(b["type"]) != type_id:
			continue
		var d: float = map.tile_center_px(b["tile"]).distance_to(from_px)
		if d < best_d:
			best_d = d
			best = b
	return best


## Дневной бросок: есть готовые кучи и некому носить — город обучает носильщика.
func _roll_porter() -> void:
	var chunk: float = float(cfg.get("piles", {}).get("chunk", 8.0))
	var need := false
	for b in buildings:
		if bool(b["done"]) and _pile_total(b) >= chunk:
			need = true
			break
	if not need:
		return
	for r in residents:
		if String(r["prof"]) == "porter" and String(r.get("ail", "")) == "":
			return
	for r in residents:
		if String(r["prof"]) in ["", "elder", "guard", "hunter", "porter"] or String(r.get("ail", "")) != "":
			continue
		if r["bld"] != null or r["site"] != null:
			continue
		r["prof"] = "porter"
		r["bld"] = null
		r["site"] = null
		r["sub_prof"] = ""
		_chron("chron.porter_trained", String(r["name"]))
		events.append({"type": "porter_trained", "name": String(r["name"])})
		_assign_jobs()
		return


# --- зоны (M6): поле, пастбище, жилая ----------------------------------------

## Разбить зону из клеток (сцена выделяет мышью). Возвращает число годных клеток.
func add_zone(type_id: String, cells: Array) -> int:
	var types: Dictionary = cfg.get("zones", {}).get("types", {})
	if not types.has(type_id):
		return 0
	var zone := {"id": _zone_id, "type": type_id, "cells": [], "progress": []}
	var added := 0
	for c in cells:
		if _zone_cell_ok(c):
			zone["cells"].append(c)
			zone["progress"].append(0.0)
			added += 1
	if added == 0:
		return 0
	_zone_id += 1
	zones.append(zone)
	return added


## Клетка годна под зону: трава без зданий и без чужих зон.
func _zone_cell_ok(t: Vector2i) -> bool:
	if not map.in_bounds(t) or t == map.anomaly_tile:
		return false
	if map.grid[t.y][t.x] != map.TILE_GRASS:
		return false
	if not building_at(t).is_empty():
		return false
	for z in zones:
		if (z["cells"] as Array).has(t):
			return false
	return true


func _cell_filled(z: Dictionary, i: int) -> bool:
	return float(z["progress"][i]) >= float(cfg.get("zones", {}).get("fill_work", 4.0))


## Свободный житель обустраивает ближайшую незаполненную клетку зоны. False — зон нет.
func _zone_fill_work(r: Dictionary, dt: float) -> bool:
	if zones.is_empty():
		return false
	var target := _nearest_zone_cell(r)
	if target.is_empty():
		return false
	var tile: Vector2i = target["tile"]
	if _arrived(r, tile):
		r["state"] = "fill"
		var z: Dictionary = target["zone"]
		var i: int = int(target["idx"])
		z["progress"][i] = float(z["progress"][i]) + dt * work_mult(r)
		r["fatigue"] += dt / float(cfg["day_length"])
		_grow_skill(r, dt)
		if _cell_filled(z, i):
			events.append({"type": "zone_cell", "zone": String(z["type"])})
			_zone_check_done(z, r)
	else:
		_move_towards(r, tile, dt)
	return true


## Ближайшая незаполненная клетка зоны: {zone, idx, tile} или {}.
func _nearest_zone_cell(r: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for z in zones:
		for i in (z["cells"] as Array).size():
			if _cell_filled(z, i) or not building_at(z["cells"][i]).is_empty():
				continue
			var d: float = map.tile_center_px(z["cells"][i]).distance_to(r["pos"])
			if d < best_d:
				best_d = d
				best = {"zone": z, "idx": i, "tile": z["cells"][i]}
	return best


## Зона заполнена целиком — событие и летопись (один раз).
func _zone_check_done(z: Dictionary, who: Dictionary) -> void:
	if bool(z.get("done_announced", false)):
		return
	for i in (z["progress"] as Array).size():
		if not _cell_filled(z, i):
			return
	z["done_announced"] = true
	events.append({"type": "zone_done", "zone": String(z["type"])})
	_chron("chron.zone_done", String(who["name"]), String(z["type"]))


## Поля (M10): обустроенная клетка сеется (1 семя), культура растёт стадиями
## (спрайты plants/), спелый урожай даёт еду и возвращает семя. Без семян
## клетка пустует (fallow). Пастбище даёт еду понемногу, как раньше.
func _update_zones(dt: float, day_len: float) -> void:
	var zcfg: Dictionary = cfg.get("zones", {})
	if zcfg.is_empty():
		return
	var fcfg: Dictionary = cfg.get("farming", {})
	var stage_days: float = float(fcfg.get("stage_days", 0.5))
	var stages: int = int(fcfg.get("stages", 4))
	var harvest_food: float = float(fcfg.get("harvest_food", 6.0))
	var seed_return: int = int(fcfg.get("seed_return", 1))
	var seed_bonus: float = float(fcfg.get("seed_bonus_chance", 0.15))
	for z in zones:
		var t := String(z["type"])
		if t == "pasture":
			var rate: float = float(zcfg.get("types", {}).get(t, {}).get("food", 0.0))
			var filled := 0
			for i in (z["cells"] as Array).size():
				if _cell_filled(z, i) and building_at(z["cells"][i]).is_empty():
					filled += 1
			if filled > 0 and rate > 0.0:
				_add_resource_capped("food", rate * float(filled) * dt / day_len)
			continue
		if t != "field":
			continue
		# посевы по клеткам (M10)
		if not (z as Dictionary).has("crops"):
			z["crops"] = []
		var crops: Array = z["crops"]
		for i in (z["cells"] as Array).size():
			if not _cell_filled(z, i) or not building_at(z["cells"][i]).is_empty():
				continue
			while crops.size() <= i:
				crops.append({})
			var crop: Dictionary = crops[i]
			if crop.is_empty():
				# пусто: сеем, если есть семя
				if float(res.get("seeds", 0.0)) >= float(fcfg.get("seed_sow", 1)):
					res["seeds"] = float(res["seeds"]) - float(fcfg.get("seed_sow", 1))
					crops[i] = {"stage": 0, "t": 0.0, "ripe": false}
			elif not bool(crop.get("ripe", false)):
				crop["t"] = float(crop.get("t", 0.0)) + dt
				if crop["t"] >= stage_days:
					crop["t"] = 0.0
					crop["stage"] = int(crop.get("stage", 0)) + 1
					if int(crop["stage"]) >= stages:
						crop["ripe"] = true
			else:
				# спелое: сбор (сами жители «снимают» — упрощённо автосбор)
				_add_resource_capped("food", harvest_food)
				_add_resource_capped("seeds", float(seed_return))
				if _event_rng.randf() < seed_bonus:
					_add_resource_capped("seeds", 1.0)
				crops[i] = {}


## Пастбище: ёмкость по обустроенным клеткам. Разведение — логистическое:
## только до ёмкости и только при паре взрослых (в меру, не геометрия).
func pasture_capacity(z: Dictionary) -> int:
	var lcfg: Dictionary = cfg.get("livestock", {})
	var per: float = float(lcfg.get("cells_per_animal", 4))
	var filled := 0
	for i in (z["cells"] as Array).size():
		if _cell_filled(z, i) and building_at(z["cells"][i]).is_empty():
			filled += 1
	return int(floorf(float(filled) / maxf(1.0, per)))


func _livestock_in(pasture_id: int) -> int:
	var n := 0
	for a in livestock:
		if int(a["pasture"]) == pasture_id:
			n += 1
	return n


func _livestock_adults(pasture_id: int) -> int:
	var n := 0
	for a in livestock:
		if int(a["pasture"]) == pasture_id and bool(a["adult"]):
			n += 1
	return n


## Ежедневный тик скота: приручение диких, приплод, молоко/яйца в пул.
func _roll_livestock() -> void:
	var lcfg: Dictionary = cfg.get("livestock", {})
	if lcfg.is_empty():
		return
	var kinds: Array = lcfg.get("kinds", {"sheep": 3, "chicken": 3, "cow": 2, "pig": 2}).keys()
	var total_food := 0.0
	var events_today := 0
	for z in zones:
		if String(z["type"]) != "pasture":
			continue
		var cap := pasture_capacity(z)
		if cap <= 0:
			continue
		var count := _livestock_in(int(z["id"]))
		# приручение: дикий зверь со двора — в загон (шанс в день)
		if count < cap and not animals.is_empty() \
				and _event_rng.randf() < float(lcfg.get("tame_chance", 0.5)):
			var wild: Dictionary = animals[_event_rng.randi_range(0, animals.size() - 1)]
			animals.erase(wild)
			var kind: String = kinds[_event_rng.randi_range(0, kinds.size() - 1)]
			livestock.append({"id": _livestock_id, "kind": kind, "pasture": int(z["id"]),
					"pos": map.tile_center_px(z["cells"][0]), "target": Vector2i.ZERO,
					"path": PackedVector2Array(), "idle": 0.0, "adult": true, "age": 99.0})
			_livestock_id += 1
			count += 1
			events.append({"type": "livestock_tame", "kind": kind})
			_chron("chron.livestock_tame", kind)
		# приплод: пара взрослых и есть место (в меру — шанс в день)
		if count < cap and _livestock_adults(int(z["id"])) >= 2 \
				and _event_rng.randf() < float(lcfg.get("breed_chance", 0.25)):
			var kind2 := "chick"
			if not livestock.is_empty():
				kind2 = String(livestock[_event_rng.randi_range(0, livestock.size() - 1)]["kind"])
			livestock.append({"id": _livestock_id, "kind": kind2, "pasture": int(z["id"]),
					"pos": map.tile_center_px(z["cells"][0]), "target": Vector2i.ZERO,
					"path": PackedVector2Array(), "idle": 0.0, "adult": false, "age": 0.0})
			_livestock_id += 1
			events.append({"type": "livestock_born", "kind": kind2})
			_chron("chron.livestock_born", kind2)
		# продукция: взрослые дают еду (молоко/яйца) — в пул раз в день
		total_food += float(_livestock_adults(int(z["id"]))) * float(lcfg.get("food_per_adult", 1.2))
	if total_food >= 1.0:
		_add_resource_capped("food", total_food)
		events.append({"type": "livestock_food", "food": int(total_food)})


## Скот бродит по клеткам своего пастбища, детёныши растут.
func _update_livestock(dt: float) -> void:
	var mature_days: float = float(cfg.get("livestock", {}).get("mature_days", 3.0))
	for a in livestock:
		if not bool(a["adult"]):
			a["age"] = float(a.get("age", 0.0)) + dt / maxf(0.01, float(cfg["day_length"]))
			if float(a["age"]) >= mature_days:
				a["adult"] = true
		a["idle"] = float(a["idle"]) - dt
		if float(a["idle"]) > 0.0:
			continue
		a["idle"] = _event_rng.randf_range(2.0, 7.0)
		var pasture := _pasture_by_id(int(a["pasture"]))
		if pasture.is_empty():
			continue
		var cells: Array = pasture["cells"]
		var goal: Vector2i = cells[_event_rng.randi_range(0, cells.size() - 1)]
		a["path"] = map.path_px(a["pos"], map.nearest_walkable(goal))
	var step_speed: float = float(cfg.get("livestock", {}).get("speed", 24.0))
	for a2 in livestock:
		var path: PackedVector2Array = a2["path"]
		if path.is_empty():
			continue
		var pos: Vector2 = a2["pos"]
		var step := step_speed * dt
		while step > 0.0 and not path.is_empty():
			var to_next: Vector2 = path[0] - pos
			var dist := to_next.length()
			if dist <= step:
				pos = path[0]
				step -= dist
				path.remove_at(0)
			else:
				pos += to_next / dist * step
				step = 0.0
		if pos.distance_to(a2["pos"]) > 0.01:
			a2["dir"] = Assets_dir_of(pos - a2["pos"])
		a2["pos"] = pos
		a2["path"] = path
		a2["moving"] = not path.is_empty()


func _pasture_by_id(pasture_id: int) -> Dictionary:
	for z in zones:
		if String(z["type"]) == "pasture" and int(z["id"]) == pasture_id:
			return z
	return {}


## Направление из вектора (обёртка, чтобы не тянуть Assets в симуляцию).
func Assets_dir_of(v: Vector2) -> String:
	if absf(v.x) >= absf(v.y):
		return "left" if v.x < 0.0 else "right"
	return "back" if v.y < 0.0 else "front"


# --- рынок и караваны мэра (M10) ---------------------------------------------

## Рынок работает: построен и за ним закреплен торговец.
func market_ready() -> bool:
	for b in buildings:
		if String(b["type"]) == "market" and bool(b["done"]) and int(b["worker"]) > 0:
			return true
	return false


## Ежедневный бросок: раз в N дней караван приходит в город (рынок активен).
func _roll_market() -> void:
	var mcfg: Dictionary = cfg.get("market", {})
	if mcfg.is_empty() or not market_ready():
		caravan_here = false
		return
	if caravan_here:
		caravan_here = false   # простоял день и уехал
		events.append({"type": "caravan_left"})
		return
	if day - _last_caravan_day < int(mcfg.get("caravan_days", 4)):
		return
	caravan_here = true
	_last_caravan_day = day
	events.append({"type": "caravan_arrived"})


## Отправить свой караван с товаром (организует мэр). deal — из city.json
## "market.deals". Возвращает "" или ключ ошибки без префикса.
func send_caravan(deal: Dictionary) -> String:
	var mcfg: Dictionary = cfg.get("market", {})
	if not market_ready():
		return "no_market"
	if caravans_out.size() >= int(mcfg.get("max_out", 2)):
		return "caravan_busy"
	var amount := float(deal["amount"])
	if float(res.get(String(deal["res"]), 0.0)) < amount:
		return "no_res"
	res[String(deal["res"])] = float(res[String(deal["res"])]) - amount
	caravans_out.append({"res": String(deal["res"]), "amount": amount,
			"left": int(deal["days"]), "coins": int(deal["coins"]),
			"dest": String(deal.get("dest", "traders"))})
	events.append({"type": "caravan_sent", "res": String(deal["res"]), "amount": int(amount)})
	_chron("chron.caravan_sent", Loc_res(String(deal["res"])), str(int(amount)))
	return ""


func Loc_res(key: String) -> String:
	return key


## Дневной тик отправленных караванов: доход в монеты или разграбление.
func _tick_caravans() -> void:
	var mcfg: Dictionary = cfg.get("market", {})
	var still: Array = []
	for c: Dictionary in caravans_out:
		c["left"] = int(c["left"]) - 1
		if int(c["left"]) > 0:
			still.append(c)
			continue
		if _event_rng.randf() < float(mcfg.get("loss_chance", 0.15)):
			events.append({"type": "caravan_lost", "res": String(c["res"])})
			_chron("chron.caravan_lost", Loc_res(String(c["res"])), str(int(float(c["amount"]))))
		else:
			Game_coins_add(int(c["coins"]))
			events.append({"type": "caravan_returned", "coins": int(c["coins"])})
			_chron("chron.caravan_returned", str(int(c["coins"])))
	caravans_out = still


## Монеты общие с героем (Game) — симуляция без сцены копит через колбэк.
var coins_sink: Callable = Callable()   # сцена ставит: func(n): Game.coins += n
var coins_source: Callable = Callable() # сцена ставит: func(): return Game.coins


func Game_coins_add(n: int) -> void:
	if coins_sink.is_valid():
		coins_sink.call(n)


## Цена каравана на базаре (за единицу) — из city.json -> market.caravan_buy.
func caravan_price(key: String) -> float:
	return float(cfg.get("market", {}).get("caravan_buy", {}).get(key, 3))


## Купить у пришедшего каравана (в пул города). "" или ключ ошибки.
func market_buy(key: String, count: int) -> String:
	if not caravan_here:
		return "no_caravan"
	var price := caravan_price(key)
	var cost := int(ceilf(price * float(count)))
	if coins_source.is_valid() and int(coins_source.call()) < cost:
		return "no_coins"
	var free := float(storage_cap()) - float(res.get(key, 0.0))
	var add := minf(float(count), maxf(0.0, free))
	if add <= 0.0:
		return "storage_full"
	res[key] = float(res.get(key, 0.0)) + add
	Game_coins_add(-int(ceilf(price * add)))
	return ""


## Продать каравану из пула. "" или ключ ошибки.
func market_sell(key: String, count: int) -> String:
	if not caravan_here:
		return "no_caravan"
	var have := float(res.get(key, 0.0))
	var take := minf(float(count), have)
	if take <= 0.0:
		return "no_res"
	var price := caravan_price(key) * float(cfg.get("market", {}).get("caravan_sell_mult", 0.5))
	res[key] = have - take
	Game_coins_add(int(floorf(price * take)))
	return ""


# --- яблоневые сады (M10) -----------------------------------------------------

## Сад растёт: у готового сада зреют яблоки (stage), потом урожай в пул.
func _tick_orchards() -> void:
	var ocfg: Dictionary = cfg.get("orchard", {})
	if ocfg.is_empty():
		return
	for b in buildings:
		if String(b["type"]) != "orchard" or not bool(b["done"]):
			continue
		b["apple_stage"] = int(b.get("apple_stage", 0))
		if int(b["apple_stage"]) < int(ocfg.get("stages", 3)):
			b["apple_stage"] = int(b["apple_stage"]) + 1
		elif _event_rng.randf() < float(ocfg.get("harvest_chance", 0.7)):
			_add_resource_capped("food", float(ocfg.get("food", 14.0)))
			b["apple_stage"] = 0
			events.append({"type": "orchard_harvest", "food": int(float(ocfg.get("food", 14.0)))})


# --- ворота в стене ---------------------------------------------------------

## Ворота открыты, если рядом (≤3 тайлов) стоит вышка со стражем (заказчик).
## При надвигающейся или идущей атаке ворота ЗАКРЫТЫ всегда (M5).
func _gate_open(gate: Dictionary) -> bool:
	if raid_active or _raid_warned:
		return false
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "guard" and int(b["worker"]) > 0:
			if Vector2(b["tile"]).distance_to(Vector2(gate["tile"])) <= 3.0:
				return true
	return false


func is_gate_open(gate: Dictionary) -> bool:
	if not bool(gate["done"]):
		return false
	return bool(_gate_state.get(str(gate["id"]), false))


## При смене состояния — тайл ворот становится проходимым или стеной.
func _update_gates() -> void:
	for b in buildings:
		if not bool(b["done"]) or _def(b).get("effect", "") != "gate":
			continue
		var open := _gate_open(b)
		var key := str(b["id"])
		if not _gate_state.has(key) or bool(_gate_state[key]) != open:
			_gate_state[key] = open
			map.set_solid(b["tile"], not open)
			events.append({"type": "gate", "open": open})


# --- жители-личности (M4) -------------------------------------------------

func _trait_sum(r: Dictionary, key: String, base: float) -> float:
	var total := base
	for t_id in r.get("traits", []):
		var td: Dictionary = _trait_map.get(String(t_id), {})
		total += float(td.get(key, 0.0))
	return total


func _trait_prod(r: Dictionary, key: String) -> float:
	var mult := 1.0
	for t_id in r.get("traits", []):
		var td: Dictionary = _trait_map.get(String(t_id), {})
		mult *= float(td.get(key, 1.0))
	return mult


func _has_trait_flag(r: Dictionary, flag: String) -> bool:
	for t_id in r.get("traits", []):
		var td: Dictionary = _trait_map.get(String(t_id), {})
		if bool(td.get(flag, false)):
			return true
	return false


func _adults() -> Array:
	var out: Array = []
	for r in residents:
		if String(r["prof"]) != "":
			out.append(r)
	return out


func _avg_mood() -> float:
	if residents.is_empty():
		return float(people.get("mood_base", 50.0))
	var total := 0.0
	for r in residents:
		total += float(r["mood"])
	return total / residents.size()


func _friend_alive(r: Dictionary) -> bool:
	var fid := int(r.get("friend", -1))
	if fid < 0:
		return false
	for other in residents:
		if int(other["id"]) == fid:
			return true
	return false


func _friend_working(r: Dictionary) -> bool:
	var fid := int(r.get("friend", -1))
	if fid < 0:
		return false
	for other in residents:
		if int(other["id"]) == fid:
			return String(other["state"]) == "work" or String(other["state"]) == "build"
	return false


## Итоговый множитель работы: настроение + черты + навык + друг + мутация.
## Пустой амбар режет работу до «голодных» 40% — но работа не встаёт совсем.
func work_mult(r: Dictionary) -> float:
	var mult := 1.0
	var mood := float(r.get("mood", 50.0))
	if mood >= float(people.get("mood_good", 70.0)):
		mult *= float(people.get("work_mood_good", 1.1))
	elif mood <= float(people.get("mood_bad", 30.0)):
		mult *= float(people.get("work_mood_bad", 0.7))
	mult *= _trait_prod(r, "work_mult")
	mult *= 1.0 + float(people.get("skill_prod", 0.08)) * float(r.get("skill", 0.0))
	if _friend_working(r):
		mult *= float(people.get("friend_work", 1.1))
	mult *= 1.0 + float(r.get("work_bonus", 0.0))
	# подмена: работа не по основной профессии вдвое хуже (просьба заказчика)
	if String(r.get("sub_prof", "")) != "":
		mult *= float(people.get("sub_work", 0.5))
	# инструменты из мастерской ускоряют всех, пока есть в хранилище
	if float(res.get("tools", 0.0)) > 0.0:
		mult *= float(cfg.get("tools_boost", 1.15))
	# атака мутантов: работы вполсилы, только храбрые не боятся (M5)
	if raid_active and not _has_trait_flag(r, "fearless"):
		mult *= float(cfg.get("threat", {}).get("fear_work", 0.75))
	if float(res["food"]) <= 0.0:
		mult *= float(people.get("starving_work", 0.6))
	return clampf(mult, 0.2, 3.0)


## Настроение плывёт к целевому: черты + загрязнение + потребности + события.
func _mood_target(r: Dictionary) -> float:
	var target: float = float(people.get("mood_base", 50.0))
	target += _trait_sum(r, "mood", 0.0)
	target += _trait_sum(r, "pollution_mood", 0.0) * pollution
	if float(res["food"]) <= 0.0:
		target -= 35.0
	if float(r["fatigue"]) >= float(cfg["tired_at"]):
		target -= 10.0
	if String(r.get("ail", "")) != "":
		target -= 25.0
	var home: Dictionary = r["home"] if r["home"] != null else {}
	if not home.is_empty():
		target += 8.0
	else:
		target -= 8.0
	# декор и комфорт (сад, статуя — ответ №18): уют поднимает мораль всему городу
	target += decor_mood()
	if _friend_alive(r):
		target += float(people.get("friend_mood", 6.0))
	if tavern_active():
		var tcfg: Dictionary = cfg.get("tavern", {})
		target += float(tcfg.get("mood", 12.0))
	# память v3 (M14-F): свежие события качают настроение, старые тлеют в хвосте
	target += _memory_mood(r)
	return clampf(target, 0.0, 100.0)


func _update_mood(r: Dictionary, dt: float, day_len: float) -> void:
	var target := _mood_target(r)
	var rate: float = float(people.get("mood_rate", 1.5))
	r["mood"] = clampf(float(r["mood"]) + (target - float(r["mood"])) * rate * dt / day_len, 0.0, 100.0)


## Навык растёт, пока житель работает; вехи — «опытный» и «мастер».
func _grow_skill(r: Dictionary, dt: float) -> void:
	var rate: float = float(people.get("skill_rate", 0.5)) * _trait_prod(r, "skill_rate")
	var skill_max: float = float(people.get("skill_max", 5.0))
	var before := float(r["skill"])
	r["skill"] = minf(skill_max, before + rate * dt / float(cfg["day_length"]))
	var expert_at: float = float(people.get("skill_expert_at", 3.0))
	var rank := int(r.get("rank", 0))
	if rank < 3 and float(r["skill"]) >= expert_at:
		r["rank"] = 3
		_chron("chron.skill_expert", String(r["name"]), String(r["prof"]))
		events.append({"type": "skill_up", "name": String(r["name"]), "rank": "expert"})
	elif rank < 5 and float(r["skill"]) >= skill_max - 0.001:
		r["rank"] = 5
		_chron("chron.skill_master", String(r["name"]), String(r["prof"]))
		events.append({"type": "skill_up", "name": String(r["name"]), "rank": "master"})


func _make_ail(r: Dictionary, kind: String, chron_key: String) -> void:
	r["ail"] = kind
	r["ail_days"] = 0.0
	_chron(chron_key, String(r["name"]))
	# болеющий не держит рабочее место: здоровый замещающий подхватит (анти-стопор)
	if r["bld"] != null:
		(r["bld"] as Dictionary)["worker"] = -1
	if r["site"] != null:
		(r["site"] as Dictionary)["worker"] = -1
	r["bld"] = null
	r["site"] = null
	r["sub_prof"] = ""
	_assign_jobs()


## Больной/раненый идёт домой и лежит.
func _lie_ill(r: Dictionary, dt: float) -> void:
	if r["home"] == null:
		r["home"] = _free_home(r)
	var home: Dictionary = r["home"]
	if not home.is_empty() and not _arrived(r, home["tile"]):
		_move_towards(r, home["tile"], dt)
		return
	r["state"] = String(r["ail"])


## Смерть жителя: летопись, тост, горе всем (храбрый/трусливый меняют силу).
func _kill(r: Dictionary, chron_key: String) -> void:
	_chron(chron_key, String(r["name"]))
	events.append({"type": "died", "name": String(r["name"])})
	_start_funeral(r, Vector2(r["pos"]))   # процессия к кладбищу, могилка (M12)
	var grief: float = float(people.get("grief_mood", 20.0))
	for other in residents:
		if other == r:
			continue
		var gm := _trait_prod(other, "grief_mult")
		other["mood"] = clampf(float(other["mood"]) - grief * gm, 0.0, 100.0)
	if r["bld"] != null:
		(r["bld"] as Dictionary)["worker"] = -1
	if r["site"] != null:
		(r["site"] as Dictionary)["worker"] = -1
	if bool(r.get("kit", false)):
		res["kits"] = float(res.get("kits", 0.0)) + 1.0   # комплект вернулся в хранилище
	# овдовевший партнёр (M13): сброс пары и дополнительное горе
	var pid := int(r.get("partner", -1))
	if pid >= 0:
		var widow := _resident_by_id(pid)
		if not widow.is_empty():
			widow["partner"] = -1
			widow["mood"] = clampf(float(widow["mood"])
					- float(people.get("couples", {}).get("widow_grief", 10.0)), 0.0, 100.0)
			_chron("chron.widow", String(widow["name"]), String(r["name"]))
			_mem_push(widow, "widow")   # память v3: горе тает медленно
			events.append({"type": "widow", "a": String(widow["name"]), "b": String(r["name"])})
	residents.erase(r)
	_assign_jobs()


func _resident_by_id(res_id: int) -> Dictionary:
	for r in residents:
		if int(r["id"]) == res_id:
			return r
	return {}


func _healer_ready() -> bool:
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "heal" and int(b["worker"]) > 0:
			return true
	return false


func _manned_towers() -> int:
	var count := 0
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "guard" and int(b["worker"]) > 0:
			count += 1
	return count


## Запас еды хотя бы на день впереди — иначе город не тянется и приток стоит.
## Кучи еды у ферм тоже считаются (M6: они скоро попадут на склад).
func _food_reserve_ok() -> bool:
	var have: float = float(res["food"]) + _piled_total_of("food")
	return have >= float(residents.size()) * float(cfg["food_per_resident_day"])


## Почему не растёт город (беженцы и рождения): "" — всё ок, иначе ключ локализации.
func growth_block() -> String:
	if residents.size() >= pop_cap():
		return "city.growth_cap"
	if not _food_reserve_ok():
		return "city.growth_food"
	var min_gate: float = minf(
			float(people.get("refugees", {}).get("mood_gate", 45.0)),
			float(people.get("births", {}).get("mood_gate", 60.0)))
	if _avg_mood() < min_gate:
		return "city.growth_mood"
	return ""


# --- таверна (излишки еды -> пиво -> настроение) ---------------------------

## Хватает ли еды сверх дневного запаса: только тогда таверна варит пиво.
func _tavern_surplus() -> bool:
	var reserve: float = float(residents.size()) * float(cfg["food_per_resident_day"])
	return float(res["food"]) > reserve + 1.0


func tavern_active() -> bool:
	var tcfg: Dictionary = cfg.get("tavern", {})
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "tavern" and int(b["worker"]) > 0:
			return _tavern_surplus()
	return false


## Работающая таверна пьёт только ИЗЛИШКИ еды сверх дневного запаса (просьба заказчика).
func _tavern_beer(dt: float, day_len: float) -> void:
	var tcfg: Dictionary = cfg.get("tavern", {})
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "tavern" and int(b["worker"]) > 0:
			var sip: float = float(tcfg.get("food_per_day", 8.0)) * dt / day_len
			if _tavern_surplus():
				res["food"] = maxf(0.0, float(res["food"]) - sip)


# --- староста/мэр ----------------------------------------------------------

## Староста на ногах (не болеет) — город может строить сам.
func elder_present() -> bool:
	for r in residents:
		if String(r["prof"]) == "elder" and String(r.get("ail", "")) == "":
			return true
	return false


## Староста не сидит: обходит здания и следит за порядком.
func _manage_walk(r: Dictionary, dt: float) -> void:
	if r["target"] == Vector2i(-1, -1) or _arrived(r, r["target"]):
		var t := _manage_target(r)
		if not t == Vector2i(-1, -1):
			r["target"] = t
	_move_towards(r, r["target"], dt)
	r["state"] = "manage"


func _manage_target(r: Dictionary) -> Vector2i:
	for attempt in 20:
		if buildings.is_empty():
			break
		var b: Dictionary = buildings[_event_rng.randi_range(0, buildings.size() - 1)]
		var tile: Vector2i = (b["tile"] as Vector2i) + Vector2i(_event_rng.randi_range(-2, 2), _event_rng.randi_range(-2, 2))
		if map.is_walkable(tile):
			return tile
	var near: Vector2i = map.spawn_tile + Vector2i(_event_rng.randi_range(-4, 4), _event_rng.randi_range(-4, 4))
	return near if map.is_walkable(near) else map.spawn_tile


## Ежедневный самострой (просьба заказчика): город строится СРАЗУ по плану —
## весь нужный набор строений, без ожидания кризисов. Кризисы (голод, теснота)
## идут вне очереди. Когда план выполнен и все здания достроены — обустройство
## защиты: крепостное кольцо стен с воротами. Игрок строит что хочет поверх.
func _roll_autobuild() -> void:
	if not elder_present():
		return
	# кризис: еды меньше чем на день — ферма вне очереди (кучи у ферм тоже еда — M6)
	var critical_food: float = float(residents.size()) * float(cfg["food_per_resident_day"])
	if float(res["food"]) + _piled_total_of("food") < critical_food \
			and not _autobuild_site_exists("farm") and not _idle_farm_exists():
		var tile := _find_autobuild_tile("farm")
		if not tile == Vector2i(-1, -1) and place_building("farm", tile):
			_announce_autobuild("farm", true)
			return
	# еда идёт в минус: производство меньше расхода — нужна ещё ферма, пока не выправится (заказчик)
	if _food_deficit() and not _autobuild_site_exists("farm") and not _idle_farm_exists():
		var tile_d := _find_autobuild_tile("farm")
		if not tile_d == Vector2i(-1, -1) and place_building("farm", tile_d):
			_announce_autobuild("farm", true)
			return
	# кризис: мест нет совсем — дом вне очереди
	if residents.size() >= pop_cap() and not _autobuild_site_exists("house"):
		var tile_h := _find_autobuild_tile("house")
		if not tile_h == Vector2i(-1, -1) and place_building("house", tile_h):
			_announce_autobuild("house", true)
			return
	# план города: сразу строим всё нужное по порядку, до двух зданий в день
	var built := 0
	for i in 2:
		var need := _next_plan_need()
		if need == "":
			break
		var tile_p := _find_autobuild_tile(need)
		if tile_p == Vector2i(-1, -1):
			break
		if not place_building(need, tile_p):
			continue   # не по карману — попробуем следующее нужное
		_announce_autobuild(need, true)
		built += 1
	if built > 0:
		return
	# обустройство защиты: кольцо стен — только когда ВСЕ здания достроены,
	# еды хватает и есть запас дерева на важные постройки
	if _any_unfinished_building() or not _food_reserve_ok():
		return
	if float(res["wood"]) < 12:
		return
	# кольцо ещё не замкнуто — два звена в день
	if not _next_wall_tile() == Vector2i(-1, -1):
		var walls := 0
		for i in 2:
			var wtile := _next_wall_tile()
			if wtile == Vector2i(-1, -1):
				break
			if not place_building("wall", wtile):
				break
			walls += 1
		if walls > 0:
			_announce_autobuild("wall", false)
		return
	# кольцо готово: строим ворота в проёмах (заказчик)
	for off in _gate_offsets():
		var gt: Vector2i = map.spawn_tile + (off as Vector2i)
		if building_at(gt).is_empty():
			if not is_buildable_tile(gt):
				continue   # на воде/камне ворот не будет — природная преграда
			if place_building("gate", gt):
				_announce_autobuild("gate", true)
			return
	# у каждых ворот — вышка: страж на ней открывает ворота
	for off in _gate_offsets():
		var gt2: Vector2i = map.spawn_tile + (off as Vector2i)
		var gate_b: Dictionary = building_at(gt2)
		if gate_b.is_empty() or not bool(gate_b["done"]):
			continue   # проём без ворот или ворота ещё строятся
		if not _manned_tower_near(gt2):
			var tt := _tower_tile_near(gt2)
			if tt == Vector2i(-1, -1):
				continue
			if place_building("tower", tt):
				_announce_autobuild("tower", true)
			return


## Четыре проёма кольца: север, юг, запад, восток.
func _gate_offsets() -> Array:
	return [Vector2i(0, -WALL_RING), Vector2i(0, WALL_RING), Vector2i(-WALL_RING, 0), Vector2i(WALL_RING, 0)]


func _manned_tower_near(tile: Vector2i) -> bool:
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "guard" and int(b["worker"]) > 0:
			if Vector2(b["tile"]).distance_to(Vector2(tile)) <= 3.0:
				return true
	return false


## Тайл под вышку у ворот — внутри кольца, ближе к центру города.
func _tower_tile_near(gate_tile: Vector2i) -> Vector2i:
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := gate_tile + Vector2i(dx, dy)
				if is_buildable_tile(tile) \
						and Vector2(tile).distance_to(Vector2(map.spawn_tile)) < Vector2(gate_tile).distance_to(Vector2(map.spawn_tile)):
					return tile
	return Vector2i(-1, -1)


## Первое строение из плана города, которого ещё нет в нужном количестве.
func _next_plan_need() -> String:
	var plan: Array = cfg.get("autobuild_plan", [])
	var counts := {}
	for b in buildings:
		counts[String(b["type"])] = int(counts.get(String(b["type"]), 0)) + 1
	for type_id in plan:
		var t := String(type_id)
		if int(counts.get(t, 0)) < _plan_count(plan, t):
			return t
	return ""


func _plan_count(plan: Array, type_id: String) -> int:
	var n := 0
	for t in plan:
		if String(t) == type_id:
			n += 1
	return n


## Есть ли хоть одно недостроенное здание — стены начинаются в полностью
## застроенном городе, а не вперемешку с домами и фермами.
func _any_unfinished_building() -> bool:
	for b in buildings:
		if not bool(b["done"]):
			return true
	return false


## Радиус крепостного кольца стен от центра города.
const WALL_RING := 6


## Следующий тайл кольца стен (обход по часовой). Ворота — 4 середины сторон.
func _next_wall_tile() -> Vector2i:
	var c: Vector2i = map.spawn_tile
	var ring := 2 * WALL_RING
	for i in range(0, 4 * ring):
		var side := i / ring
		var step := i % ring
		var off: Vector2i
		match side:
			0: off = Vector2i(-WALL_RING + step, -WALL_RING)
			1: off = Vector2i(WALL_RING, -WALL_RING + step)
			2: off = Vector2i(WALL_RING - step, WALL_RING)
			3: off = Vector2i(-WALL_RING, WALL_RING - step)
		if off.x == 0 or off.y == 0:
			continue   # ворота на север, юг, запад и восток
		var tile := c + off
		if is_buildable_tile(tile):
			return tile
	return Vector2i(-1, -1)


## Еда идёт в минус: суммарное производство ферм меньше дневного расхода города.
func _food_deficit() -> bool:
	var production := 0.0
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == "farm":
			production += float(_def(b)["produce"]["per_day"]) * float(b.get("ench_mult", 1.0))
	return production < float(residents.size()) * float(cfg["food_per_resident_day"])


## Готовая ферма без работника: строить новую бессмысленно — сперва некому работать.
func _idle_farm_exists() -> bool:
	for b in buildings:
		if b["done"] and String(b["type"]) == "farm" and int(b["worker"]) <= 0:
			return true
	return false


func _autobuild_site_exists(type_id: String) -> bool:
	for b in buildings:
		if not bool(b["done"]) and String(b["type"]) == type_id:
			return true
	return false


## Тайл под самострой: добытчики — у своего ресурса (заказчик), остальные —
## по районам (жилые к западу, производственные к востоку). Своё место занято — общий поиск.
func _find_autobuild_tile(type_id: String) -> Vector2i:
	var place := ""
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			place = String(d.get("place", ""))
			break
	if place == "ore":
		var ore_t := _find_gather_tile(type_id, [map.TILE_ORE], true)
		if not ore_t == Vector2i(-1, -1):
			return ore_t
	if place == "forest":
		var forest_t := _find_gather_tile(type_id, [map.TILE_TREE], false)
		if not forest_t == Vector2i(-1, -1):
			return forest_t
	if place == "rock":
		var rock_t := _find_gather_tile(type_id, [map.TILE_ROCK, map.TILE_ORE], false)
		if not rock_t == Vector2i(-1, -1):
			return rock_t
	var district := "work"
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			district = String(d.get("district", "work"))
			break
	var center: Vector2i = map.spawn_tile
	if district == "living":
		center += Vector2i(-4, 0)
	else:
		center += Vector2i(4, 0)
	var tile := _ring_buildable(center, 4)
	if not tile == Vector2i(-1, -1):
		return tile
	return _ring_buildable(map.spawn_tile, 8)


## Ближайший к центру города тайл рядом с ресурсом, куда можно поставить здание.
## on_resource — здание ставится прямо на тайл (шахта на руде).
func _find_gather_tile(type_id: String, kinds: Array, on_resource: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if on_resource:
				if not (map.grid[y][x] in kinds) or not is_buildable_tile(t, type_id):
					continue
			else:
				if not is_buildable_tile(t, type_id) or placement_block(type_id, t) != "":
					continue
			var d: float = Vector2(t).distance_to(Vector2(map.spawn_tile))
			if d < best_d:
				best_d = d
				best = t
	return best


func _ring_buildable(center: Vector2i, max_radius: int) -> Vector2i:
	for radius in range(1, max_radius + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := center + Vector2i(dx, dy)
				if is_buildable_tile(tile):
					return tile
	return Vector2i(-1, -1)


func _announce_autobuild(type_id: String, toast: bool) -> void:
	var manager := ""
	for r in residents:
		if String(r["prof"]) == "elder":
			manager = String(r["name"])
			break
	_chron("chron.autobuild", manager, type_id)
	if toast:
		events.append({"type": "autobuild", "name": manager, "bld": type_id})


## Староста погиб — город не остаётся без управления: старостой становится
## самый опытный взрослый (просьба заказчика: город должен расти сам).
func _ensure_elder() -> void:
	for r in residents:
		if String(r["prof"]) == "elder":
			return
	var best: Dictionary = {}
	for r in _adults():
		if best.is_empty() or float(r.get("skill", 0.0)) > float(best.get("skill", 0.0)):
			best = r
	if best.is_empty():
		return
	if best["bld"] != null:
		(best["bld"] as Dictionary)["worker"] = -1
	if best["site"] != null:
		(best["site"] as Dictionary)["worker"] = -1
	best["bld"] = null
	best["site"] = null
	best["sub_prof"] = ""
	best["prof"] = "elder"
	_chron("chron.promoted", String(best["name"]))
	events.append({"type": "promoted", "name": String(best["name"])})
	_assign_jobs()


## Дневной бросок: болезни и выздоровления (лекарь лечит, запущенная болезнь убивает).
func _roll_ailments() -> void:
	var acfg: Dictionary = people.get("ailments", {})
	for r in residents.duplicate():
		if String(r["prof"]) == "":
			continue
		var ail := String(r.get("ail", ""))
		if ail == "":
			var chance: float = float(acfg.get("sick_chance", 0.02)) \
					+ float(acfg.get("pollution_sick_extra", 0.1)) * pollution / 100.0
			# черта «болезненный» (M7): хвори цепляются вдвое чаще
			if _has_trait_flag(r, "frail"):
				chance *= float(acfg.get("frail_mult", 2.0))
			if _event_rng.randf() < chance:
				_make_ail(r, "sick", "chron.sick")
			continue
		r["ail_days"] = float(r.get("ail_days", 0.0)) + 1.0
		var recov: float = float(acfg.get("recover_chance", 0.25))
		if _healer_ready():
			recov = float(acfg.get("healer_recover_chance", 0.7))
		if _event_rng.randf() < recov:
			r["ail"] = ""
			_assign_jobs()   # выздоровел — вернулся в раздачу работы
			continue
		var risk: float = float(acfg.get("death_chance", 0.04))
		var overdue: float = float(r["ail_days"]) - float(acfg.get("death_risk_after_days", 3.0))
		if overdue > 0.0:
			risk += float(acfg.get("death_risk_growth", 0.05)) * overdue
		if _event_rng.randf() < risk:
			_kill(r, "chron.died_sick")


## Дневной бросок: беженцы идут сами (ответ №27) — шанс выше при вышках со стражей.
func _roll_refugees() -> void:
	var rcfg: Dictionary = people.get("refugees", {})
	if rcfg.is_empty() or residents.size() >= pop_cap():
		return
	if not _food_reserve_ok() or _avg_mood() < float(rcfg.get("mood_gate", 45.0)):
		return
	var chance: float = float(rcfg.get("chance_per_day", 0.35)) \
			+ minf(float(rcfg.get("tower_bonus", 0.1)) * _manned_towers(), float(rcfg.get("tower_bonus_max", 0.4)))
	if _event_rng.randf() >= chance:
		return
	var wave := _event_rng.randi_range(1, maxi(1, int(rcfg.get("wave_max", 2))))
	for i in wave:
		if residents.size() >= pop_cap():
			break
		var profs: Array = cfg["start"]["professions"]
		var prof := String(profs[_event_rng.randi_range(0, profs.size() - 1)])
		var names: Array = cfg["names"]
		var r := _new_resident(String(names[_event_rng.randi_range(0, names.size() - 1)]), prof, _edge_tile())
		residents.append(r)
		_next_id += 1
		_chron("chron.refugee", String(r["name"]), prof)
		events.append({"type": "refugee", "name": String(r["name"]), "prof": prof})
	_assign_jobs()


func _edge_tile() -> Vector2i:
	for attempt in 100:
		var side := _event_rng.randi_range(0, 3)
		var tile := Vector2i.ZERO
		match side:
			0: tile = Vector2i(_event_rng.randi_range(0, map.w - 1), 0)
			1: tile = Vector2i(_event_rng.randi_range(0, map.w - 1), map.h - 1)
			2: tile = Vector2i(0, _event_rng.randi_range(0, map.h - 1))
			3: tile = Vector2i(map.w - 1, _event_rng.randi_range(0, map.h - 1))
		if map.is_walkable(tile) and building_at(tile).is_empty():
			return tile
	return map.spawn_tile


## Дневной бросок: рождение ребёнка у случайного взрослого, когда всем хорошо.
## Пары повышают шанс рождения (couple_boost, M13).
func _roll_births() -> void:
	var bcfg: Dictionary = people.get("births", {})
	if bcfg.is_empty() or residents.size() >= pop_cap():
		return
	if not _food_reserve_ok() or _avg_mood() < float(bcfg.get("mood_gate", 60.0)):
		return
	var chance := float(bcfg.get("chance_per_day", 0.25))
	if _couples_count() > 0:
		chance *= float(bcfg.get("couple_boost", 1.5))
	if _event_rng.randf() >= chance:
		return
	var adults := _adults()
	if adults.is_empty():
		return
	var parent: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	var names: Array = cfg["names"]
	var child := _new_resident(String(names[_event_rng.randi_range(0, names.size() - 1)]), "", map.tile_of_px(parent["pos"]))
	child["age_days"] = 0.0
	child["traits"] = []
	child["mood"] = float(people.get("mood_base", 50.0))
	residents.append(child)
	_next_id += 1
	_chron("chron.birth", String(child["name"]))
	events.append({"type": "birth", "name": String(child["name"])})


## Число пар (M13): свадьбы друзей, поддержка и дети.
func _couples_count() -> int:
	var n := 0
	for r in residents:
		if int(r.get("partner", -1)) >= 0:
			n += 1
	return n / 2


## Пары (M13): друзья с хорошим настроением со временем женятся;
## живые пары каждый день поддерживают друг друга настроением.
func _roll_couples() -> void:
	var ccfg: Dictionary = people.get("couples", {})
	if ccfg.is_empty():
		return
	var gate := float(ccfg.get("mood_gate", 62.0))
	for r in residents:
		if int(r.get("partner", -1)) >= 0 or String(r["prof"]) == "":
			continue
		var other := _friend_of(r)
		if other.is_empty() or int(other.get("partner", -1)) >= 0:
			continue
		if float(r["mood"]) < gate or float(other["mood"]) < gate:
			continue
		if _event_rng.randf() >= float(ccfg.get("chance_per_day", 0.25)):
			continue
		r["partner"] = int(other["id"])
		other["partner"] = int(r["id"])
		var boost := float(people.get("wedding_mood", 12.0))
		r["mood"] = clampf(float(r["mood"]) + boost, 0.0, 100.0)
		other["mood"] = clampf(float(other["mood"]) + boost, 0.0, 100.0)
		_rel_change(r, other, float(_v3().get("wedding_rel_bonus", 40.0)))   # v3
		_mem_push(r, "wedding")
		_mem_push(other, "wedding")
		_chron("chron.wedding", String(r["name"]), String(other["name"]))
		events.append({"type": "wedding", "a": String(r["name"]), "b": String(other["name"])})
	var pm := float(ccfg.get("pair_mood", 4.0))
	for r in residents:
		var pid := int(r.get("partner", -1))
		if pid < 0:
			continue
		if not _resident_by_id(pid).is_empty():
			r["mood"] = clampf(float(r["mood"]) + pm, 0.0, 100.0)


## День основания (M13): раз в N дней город гуляет всем городом —
## вечером все у таверны и костра, еда расходуется, настроение поднимается.
func _roll_festival() -> void:
	var lcfg: Dictionary = cfg.get("life", {})
	var every := int(lcfg.get("festival_every_days", 0))
	if every <= 0 or day_number() % every != 0:
		return
	var cost := float(lcfg.get("festival_food", 12.0))
	if float(res["food"]) + _piled_total_of("food") < cost:
		_chron("chron.found_skip")
		events.append({"type": "found_skip"})
		return
	res["food"] = maxf(0.0, float(res["food"]) - cost)
	var dm := float(lcfg.get("festival_mood", 8.0))
	for r in residents:
		if String(r["prof"]) != "":
			r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	# друзья дарят подарки (M14-F): отношения крепнут, память хранит праздник
	var friends_at := float(_v3().get("friend_threshold", 50.0))
	var gift_bonus := float(_v3().get("gift_rel_bonus", 6.0))
	var gifted: Array = []
	for r in _adults():
		var rel: Dictionary = r.get("rel", {})
		for k in rel:
			var other := _resident_by_id(int(k))
			if other.is_empty() or gifted.has(other) or gifted.has(r):
				continue
			if float(rel[k]) >= friends_at and _rel_score(other, int(r["id"])) >= friends_at:
				_rel_change(r, other, gift_bonus)
				_mem_push(r, "gift")
				_mem_push(other, "gift")
				gifted.append(r)
				gifted.append(other)
				_chron("chron.fest_gift", String(r["name"]), String(other["name"]))
				events.append({"type": "fest_gift", "a": String(r["name"]), "b": String(other["name"])})
				break
	_chron("chron.found_day")
	events.append({"type": "found_day"})


## Ребёнок повзрослел: получает профессию (реже всех) и черты характера.
func _grow_up(r: Dictionary) -> void:
	var pool: Array = []
	if not elder_present():
		pool.append("elder")   # город без старосты вырастит нового из повзрослевшего
	for prof in cfg["start"]["professions"]:
		pool.append(String(prof))
	var counts := {}
	for other in residents:
		if String(other["prof"]) != "":
			counts[String(other["prof"])] = int(counts.get(String(other["prof"]), 0)) + 1
	var best := ""
	var best_count := 999999
	for prof in pool:
		var c := int(counts.get(String(prof), 0))
		if c < best_count:
			best_count = c
			best = String(prof)
	r["prof"] = best
	r["traits"] = _random_traits()
	r["age_days"] = 100.0
	_chron("chron.grown", String(r["name"]), best)
	events.append({"type": "grown", "name": String(r["name"]), "prof": best})
	_assign_jobs()


## Дневной бросок: события-истории про конкретных жителей (пункт плана M4).
func _roll_stories() -> void:
	var scfg: Dictionary = people.get("stories", {})
	if scfg.is_empty():
		return
	if _event_rng.randf() >= float(scfg.get("chance_per_day", 0.5)):
		return
	match _weighted_pick(scfg.get("weights", {})):
		"quarrel":
			_story_quarrel(scfg)
		"friendship":
			_story_friendship(scfg)
		"discovery":
			_story_discovery(scfg)
		"betrayal":
			_story_betrayal(scfg)
		"mutation":
			_story_mutation(scfg)
		"festival":
			_story_festival(scfg)
		"prodigy":
			_story_prodigy(scfg)
		"brave_deed":
			_story_brave_deed(scfg)
		"meteor":
			_story_meteor(scfg)
		"herbs":
			_story_herbs(scfg)
		"night_terror":
			_story_night_terror(scfg)
		"wedding":
			_story_wedding(scfg)
		"artifact":
			_story_artifact(scfg)
		"good_harvest":
			_story_good_harvest(scfg)
		"stranger":
			_story_stranger(scfg)


## Ссора (ответ №29, отключается галочкой): ворчун портит настроение ещё кому-то.
func _story_quarrel(scfg: Dictionary) -> void:
	if not conflicts or residents.size() < 2:
		return
	var instigators: Array = []
	for r in _adults():
		if _has_trait_flag(r, "instigator"):
			instigators.append(r)
	if instigators.is_empty():
		return
	var a: Dictionary = instigators[_event_rng.randi_range(0, instigators.size() - 1)]
	var others: Array = []
	for r in _adults():
		if r != a:
			others.append(r)
	if others.is_empty():
		return
	var b: Dictionary = others[_event_rng.randi_range(0, others.size() - 1)]
	var dm: float = float(scfg.get("quarrel_mood", -15.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_rel_change(a, b, float(_v3().get("quarrel_rel_hit", -18.0)))   # отношения v3
	_mem_push(a, "quarrel")
	_mem_push(b, "quarrel")
	_chron("chron.quarrel", String(a["name"]), String(b["name"]))
	events.append({"type": "quarrel", "a": String(a["name"]), "b": String(b["name"])})


## Дружба (ответ №34): пара работает вместе эффективнее и бодрее духом.
func _story_friendship(scfg: Dictionary) -> void:
	var cands: Array = []
	for r in _adults():
		if int(r.get("friend", -1)) < 0 and float(r["mood"]) >= 50.0:
			cands.append(r)
	if cands.size() < 2:
		return
	var a: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	var b: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	if a == b:
		return
	a["friend"] = int(b["id"])
	b["friend"] = int(a["id"])
	var dm: float = float(scfg.get("friendship_mood", 10.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_chron("chron.friendship", String(a["name"]), String(b["name"]))
	events.append({"type": "friendship", "a": String(a["name"]), "b": String(b["name"])})


## Находка (навык пригодился): излишек ресурса в общий пул.
func _story_discovery(scfg: Dictionary) -> void:
	var skilled: Array = []
	var expert_at: float = float(people.get("skill_expert_at", 3.0))
	for r in _adults():
		if float(r.get("skill", 0.0)) >= expert_at:
			skilled.append(r)
	if skilled.is_empty():
		return
	var r: Dictionary = skilled[_event_rng.randi_range(0, skilled.size() - 1)]
	var roll := _event_rng.randf()
	var key := "food"
	var amount: float = float(scfg.get("discovery_food", 12))
	if roll > 0.8:
		key = "crystal"
		amount = float(scfg.get("discovery_crystal", 1))
	elif roll > 0.4:
		key = "stone"
		amount = float(scfg.get("discovery_stone", 6))
	_add_resource_capped(key, amount)
	_chron("chron.discovery", String(r["name"]), key)
	events.append({"type": "discovery", "name": String(r["name"]), "res": key})


## Предательство (жадный в унынии крадёт еду; страж в городе — пойман).
func _story_betrayal(scfg: Dictionary) -> void:
	if not conflicts:
		return
	var thieves: Array = []
	for r in _adults():
		if _has_trait_flag(r, "can_steal") and float(r["mood"]) < 40.0:
			thieves.append(r)
	if thieves.is_empty():
		return
	var r: Dictionary = thieves[_event_rng.randi_range(0, thieves.size() - 1)]
	var guard_near := false
	for other in residents:
		if String(other["prof"]) == "guard":
			guard_near = true
			break
	if guard_near:
		r["mood"] = clampf(float(r["mood"]) - 15.0, 0.0, 100.0)
		_chron("chron.betrayal_caught", String(r["name"]))
		events.append({"type": "betrayal_caught", "name": String(r["name"])})
		return
	var amount: float = minf(float(scfg.get("betrayal_food", 10)), float(res["food"]))
	res["food"] = maxf(0.0, float(res["food"]) - amount)
	var dm: float = float(scfg.get("betrayal_mood", -5.0))
	for other in residents:
		other["mood"] = clampf(float(other["mood"]) + dm, 0.0, 100.0)
	_chron("chron.betrayal", String(r["name"]))
	events.append({"type": "betrayal", "name": String(r["name"])})


## Мутация (ответ №35): дикая магия меняет жителя — кому улучшение, кому болезнь.
func _story_mutation(scfg: Dictionary) -> void:
	if pollution < float(scfg.get("mutation_pollution", 30.0)):
		return
	var adults := _adults()
	if adults.is_empty():
		return
	var r: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	if _event_rng.randf() < 0.5:
		r["work_bonus"] = float(r.get("work_bonus", 0.0)) + float(scfg.get("mutation_work_bonus", 0.1))
		_chron("chron.mutation_good", String(r["name"]))
		events.append({"type": "mutation_good", "name": String(r["name"])})
	else:
		_make_ail(r, "sick", "chron.mutation_bad")
		events.append({"type": "mutation_bad", "name": String(r["name"])})


## --- события-истории M7 (до 15) ---------------------------------------------

## Праздник в таверне: городу есть чем поживиться — все гуляют.
func _story_festival(scfg: Dictionary) -> void:
	if not tavern_active() or float(res["food"]) < float(scfg.get("festival_food", 15)):
		return
	res["food"] = maxf(0.0, float(res["food"]) - float(scfg.get("festival_food", 15)))
	var dm: float = float(scfg.get("festival_mood", 10.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.festival")
	events.append({"type": "festival"})


## Одарённый ученик: умелый житель обучает товарища — навык растёт скачком.
func _story_prodigy(scfg: Dictionary) -> void:
	var expert_at: float = float(people.get("skill_expert_at", 3.0))
	var teacher: Dictionary = {}
	var student: Dictionary = {}
	for r in _adults():
		if float(r.get("skill", 0.0)) >= expert_at:
			teacher = r
			break
	for r in _adults():
		if not r.is_empty() and r != teacher and float(r.get("skill", 0.0)) < float(people.get("skill_max", 5.0)):
			student = r
			break
	if teacher.is_empty() or student.is_empty():
		return
	student["skill"] = minf(float(people.get("skill_max", 5.0)),
			float(student["skill"]) + float(scfg.get("prodigy_skill", 1.0)))
	_chron("chron.prodigy", String(teacher["name"]), String(student["name"]))
	events.append({"type": "prodigy", "a": String(teacher["name"]), "b": String(student["name"])})


## Храбрый поступок: храбрец спасает жителя — город гордится.
func _story_brave_deed(scfg: Dictionary) -> void:
	var heroes: Array = []
	for r in _adults():
		if _has_trait_flag(r, "fearless"):
			heroes.append(r)
	if heroes.is_empty():
		return
	var hero_r: Dictionary = heroes[_event_rng.randi_range(0, heroes.size() - 1)]
	var dm: float = float(scfg.get("brave_deed_mood", 8.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.brave_deed", String(hero_r["name"]))
	events.append({"type": "brave_deed", "name": String(hero_r["name"])})


## Метеорит: упал камень с неба — добыча даром, но воздух дурит.
func _story_meteor(scfg: Dictionary) -> void:
	_add_resource_capped("stone", float(scfg.get("meteor_stone", 20)))
	add_pollution(float(scfg.get("meteor_pollution", 8.0)))
	_chron("chron.meteor")
	events.append({"type": "meteor"})


## Целебные травы: лекарь находит сбор — все больные выздоравливают разом.
func _story_herbs(scfg: Dictionary) -> void:
	if not _healer_ready():
		return
	var healed := 0
	for r in residents:
		if String(r.get("ail", "")) != "":
			r["ail"] = ""
			healed += 1
	if healed == 0:
		return
	_assign_jobs()
	_chron("chron.herbs", str(healed))
	events.append({"type": "herbs", "n": healed})


## Кошмары: наэлектризованный воздух не даёт спать — настроение чуть проседает.
func _story_night_terror(scfg: Dictionary) -> void:
	if pollution < float(scfg.get("terror_pollution", 20.0)):
		return
	var dm: float = float(scfg.get("terror_mood", -6.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.night_terror")
	events.append({"type": "night_terror"})


## Свадьба: двое свободных жителей соединяются — им и городу веселей.
func _story_wedding(scfg: Dictionary) -> void:
	var cands: Array = []
	for r in _adults():
		if int(r.get("friend", -1)) < 0:
			cands.append(r)
	if cands.size() < 2:
		return
	var a: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	var b: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	if a == b:
		return
	a["friend"] = int(b["id"])
	b["friend"] = int(a["id"])
	var dm: float = float(scfg.get("wedding_mood", 12.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_chron("chron.wedding", String(a["name"]), String(b["name"]))
	events.append({"type": "wedding", "a": String(a["name"]), "b": String(b["name"])})


## Артефакт: житель выкапывает странную вещь — кристалл в пул, мастерство в голову.
func _story_artifact(scfg: Dictionary) -> void:
	var adults := _adults()
	if adults.is_empty():
		return
	var r: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	_add_resource_capped("crystal", float(scfg.get("artifact_crystal", 1)))
	r["skill"] = minf(float(people.get("skill_max", 5.0)),
			float(r["skill"]) + float(scfg.get("artifact_skill", 0.5)))
	_chron("chron.artifact", String(r["name"]))
	events.append({"type": "artifact", "name": String(r["name"])})


## Урожайный год: погода и руки сошлись — лишняя еда в амбар.
func _story_good_harvest(scfg: Dictionary) -> void:
	if _assigned_done_of_farm().is_empty():
		return
	_add_resource_capped("food", float(scfg.get("harvest_food", 18)))
	_chron("chron.good_harvest")
	events.append({"type": "good_harvest"})


## Странник: изгнанник делится припасами и слухами о данже.
func _story_stranger(scfg: Dictionary) -> void:
	_add_resource_capped("food", float(scfg.get("stranger_food", 10)))
	_add_resource_capped("crystal", float(scfg.get("stranger_crystal", 1)))
	_chron("chron.stranger")
	events.append({"type": "stranger"})


## Готовая ферма с работающим фермером — условие «Урожайного года».
func _assigned_done_of_farm() -> Dictionary:
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == "farm" and int(b["worker"]) > 0:
			return b
	return {}


## Летопись: хранит ключи локализации, текст собирает HUD.
func _chron(key: String, a: String = "", b: String = "") -> void:
	chronicle.append({"day": day, "key": key, "a": a, "b": b})
	if chronicle.size() > 200:
		chronicle.pop_front()


# --- добыча из данжа -----------------------------------------------------

## Рюкзак героя в пул города (пункт плана M2). Замапленные предметы уходят из
## рюкзака, остальное (руны, снаряжение) в нём остаётся. Возвращает добавленное.
func deposit_loot(inventory: Array) -> Dictionary:
	var pool_map: Dictionary = cfg["loot_to_pool"]
	var added := {}
	var i := 0
	while i < inventory.size():
		var stack: Dictionary = inventory[i]
		var item_id := String(stack["id"])
		if not pool_map.has(item_id):
			i += 1
			continue
		var key := String(pool_map[item_id])
		var want := int(stack["count"])
		var free: float = float(storage_cap()) - float(res[key])
		var got := mini(want, int(maxf(0.0, free)))
		if got > 0:
			res[key] = float(res[key]) + got
			added[key] = int(added.get(key, 0)) + got
		if got >= want:
			inventory.remove_at(i)
		else:
			stack["count"] = want - got
			i += 1
	return added


# --- угрозы и оборона (M5) --------------------------------------------------

var _enemies_cfg: Array = []    # data/enemies.json — параметры мутантов


## Сила угрозы: растёт со временем и размером города (ТЗ 4.3, решение №12).
func threat_value() -> float:
	var tcfg: Dictionary = cfg.get("threat", {})
	var city_value := 0
	for b in buildings:
		if bool(b["done"]):
			city_value += 1
	city_value += residents.size()
	return maxf(0.0, float(day - int(tcfg.get("start_day", 3.0)))) * float(tcfg.get("day_growth", 0.35)) \
			+ float(city_value) * float(tcfg.get("city_growth", 0.08))


## Стадия угрозы для HUD: calm / unease / danger / siege.
func threat_stage() -> String:
	var tcfg: Dictionary = cfg.get("threat", {})
	var v := threat_value()
	if v >= float(tcfg.get("siege_from_threat", 8.0)):
		return "siege"
	if v >= 3.0:
		return "danger"
	if v >= float(tcfg.get("min_threat", 1.0)):
		return "unease"
	return "calm"


## Сколько дней до следующей волны (для индикатора HUD).
func raid_eta_days() -> float:
	if raid_active:
		return 0.0
	return maxf(0.0, (_next_raid_at - time) / float(cfg["day_length"]))


func _schedule_next_raid() -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	# каждая прошедшая волна сильнее, а следующая приходит на 2 дня позже (заказчик)
	var gap: float = float(tcfg.get("base_gap_days", 1.2)) \
			+ float(tcfg.get("wave_growth_gap_days", 2.0)) * float(raid_count) \
			- float(tcfg.get("gap_shrink", 0.04)) * threat_value()
	_raid_gap_days = maxf(gap, float(tcfg.get("gap_min_days", 0.6)))
	# первая волна — не раньше start_day, как бы ни разросся город (заказчик: на 4-й день пришла)
	_next_raid_at = maxf(time + _raid_gap_days * float(cfg["day_length"]),
			float(tcfg.get("start_day", 10.0)) * float(cfg["day_length"]) + 1.0)
	_raid_warned = false


## Планировщик волн: предупреждение за warn_fraction интервала, затем атака.
func _update_threat(dt: float, day_len: float) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	if tcfg.is_empty():
		return
	if raid_active:
		_update_raid(dt, day_len)
		return
	if _next_raid_at <= 0.0:
		_schedule_next_raid()
		return
	var warn_at: float = _next_raid_at - float(tcfg.get("warn_fraction", 0.3)) * _raid_gap_days * day_len
	if not _raid_warned and time >= warn_at:
		_raid_warned = true
		events.append({"type": "raid_warn", "eta": raid_eta_days()})
		return
	if time >= _next_raid_at:
		if float(day) < float(tcfg.get("start_day", 10.0)) \
				or threat_value() < float(tcfg.get("min_threat", 1.0)):
			_next_raid_at = time + 0.5 * day_len   # город ещё мал или рано — мутанты не идут
			return
		var siege := threat_value() >= float(tcfg.get("siege_from_threat", 8.0)) \
				and _raid_rng.randf() < float(tcfg.get("siege_chance", 0.35))
		var size := int(float(tcfg.get("raid_size_base", 2)) + threat_value() * float(tcfg.get("raid_size_threat", 0.3)))
		size = clampi(size, 1, int(tcfg.get("raid_size_max", 10)))
		if siege:
			size += int(tcfg.get("siege_size_bonus", 4))
		_spawn_raid(size, siege)


## Волна мутантов из аномалии: size тварей, siege — осада покрупнее.
func _spawn_raid(size: int, siege: bool) -> void:
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var tcfg: Dictionary = cfg.get("threat", {})
	raid_active = true
	raid_siege = siege
	_raid_kind = "mutant"
	raid_count += 1
	razed_this_raid = 0
	# каждая следующая волна сильнее (заказчик): больше размер и прочность тварей
	var wave_no := raid_count - 1
	size = clampi(size + wave_no * int(tcfg.get("wave_growth_size", 1)), 1,
			int(tcfg.get("raid_size_max", 10)) + wave_no)
	var hp_mult := 1.0 + threat_value() * float(tcfg.get("hp_per_threat", 0.04)) \
			+ float(wave_no) * float(tcfg.get("wave_growth_hp", 0.15))
	for i in size:
		var def := _pick_raider_def(tcfg)
		if def.is_empty():
			break
		var hp := int(round(float(def["hp"]) * hp_mult))
		raiders.append({
			"id": _next_id, "type": String(def["id"]), "p": def,
			"hp": hp, "max_hp": hp,
			"pos": _spawn_tile_near_anomaly(),
			"target": Vector2i(-1, -1), "path": PackedVector2Array(),
			"atk_cd": 0.0, "mode": "advance",
		})
		_next_id += 1
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + float(tcfg.get("raid_mood", -15.0)), 0.0, 100.0)
	events.append({"type": "raid_start", "siege": siege, "count": raiders.size()})
	_chron("chron.raid_siege" if siege else "chron.raid", str(raiders.size()))
	_update_gates()   # ворота захлопываются


func _pick_raider_def(tcfg: Dictionary) -> Dictionary:
	var weights: Dictionary = tcfg.get("enemy_weights", {})
	var total := 0
	for w: int in weights.values():
		total += w
	var roll := _raid_rng.randi_range(1, maxi(1, total))
	for def: Dictionary in _enemies_cfg:
		roll -= int(weights.get(String(def["id"]), 0))
		if roll <= 0:
			return def
	return _enemies_cfg[0] if not _enemies_cfg.is_empty() else {}


func _spawn_tile_near_anomaly() -> Vector2:
	for attempt in 40:
		var off := Vector2i(_raid_rng.randi_range(-3, 3), _raid_rng.randi_range(-3, 3))
		var tile: Vector2i = map.anomaly_tile + off
		if map.is_walkable(tile):
			return map.tile_center_px(tile)
	return map.tile_center_px(map.anomaly_tile)


## Тик волны: движение мутантов, атаки по герою и зданиям, огонь вышек.
func _update_raid(dt: float, _day_len: float) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	_shoot_towers(dt, tcfg)
	var i := 0
	while i < raiders.size():
		var r: Dictionary = raiders[i]
		if not _raider_update(r, dt, tcfg):
			raiders.remove_at(i)
			continue
		i += 1
	if raiders.is_empty():
		_raid_end(true)
		return
	if razed_this_raid >= int(tcfg.get("defeat_razes", 3)):
		_raid_end(false)


## Вышка со стражем бьёт ближайшего мутанта в радиусе (страж реально воюет).
func _shoot_towers(dt: float, tcfg: Dictionary) -> void:
	# дисциплина «Оборона» (M7): дальность и урон вышек растут
	var range_px := (float(tcfg.get("tower_range", 4.5)) + research_sum("tower_range")) * float(map.ts)
	for b in buildings:
		if not bool(b["done"]) or _def(b).get("effect", "") != "guard" or int(b["worker"]) <= 0:
			continue
		if float(b.get("stun_left", 0.0)) > 0.0:
			continue
		b["cd"] = float(b.get("cd", 0.0)) - dt
		if float(b["cd"]) > 0.0:
			continue
		var target: Dictionary = _nearest_raider(map.tile_center_px(b["tile"]), range_px)
		if target.is_empty():
			continue
		b["cd"] = float(tcfg.get("tower_cd", 1.2))
		# комплект стража усиливает и выстрелы его вышки
		var mult := 1.0
		var worker := _resident_by_id(int(b["worker"]))
		if not worker.is_empty() and bool(worker.get("kit", false)):
			mult = float(tcfg.get("kit_damage_mult", 2.0))
		_hit_raider(target, int(round((float(tcfg.get("tower_damage", 2)) + research_sum("tower_damage")) * mult)))


func _nearest_raider(from_px: Vector2, radius_px: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius_px
	for r in raiders:
		var d: float = (r["pos"] as Vector2).distance_to(from_px)
		if d < best_d:
			best_d = d
			best = r
	return best


## ИИ мутанта: герой рядом — дерётся с героем; здание в досягаемости — ломает;
## путь к центру открыт — идёт; заперт стеной — идёт к ближайшей стене/воротам.
## M11: духи леса в режиме «hunt» гонятся за своей жертвой (лесорубом/каменотёсом).
## Возвращает false, если мутант погиб или волне нечего делать (убрать из списка).
func _raider_update(r: Dictionary, dt: float, tcfg: Dictionary) -> bool:
	if int(r["hp"]) <= 0:
		return false
	r["atk_cd"] = maxf(0.0, float(r["atk_cd"]) - dt)
	var p: Dictionary = r["p"]
	if String(r.get("mode", "")) == "hunt":
		return _spirit_update(r, dt)
	# герой в городе и рядом — мутант отвлекается на чемпиона (путь как у жителей:
	# напрямую он резал бы углы сквозь скалы — заказчик видел проходы насквозь)
	if hero_alive:
		var to_hero: Vector2 = hero_pos - (r["pos"] as Vector2)
		if to_hero.length() <= float(p["aggro"]):
			if to_hero.length() <= float(p["attack_range"]) + 12.0:
				if float(r["atk_cd"]) <= 0.0:
					r["atk_cd"] = float(p["attack_cooldown"])
					events.append({"type": "hero_hit", "dmg": int(p["damage"])})
			else:
				_raider_move_to(r, map.tile_of_px(hero_pos), float(p["speed"]) * dt)
			return true
	var reach := float(p["attack_range"]) + float(map.ts) * 0.5
	# здание в пределах досягаемости — крушим (иначе осцилляция «центр ↔ стена»:
	# обходной путь всегда существует, и мутант ни разу не ударит)
	var near := _nearest_building_of(r, [])
	if not near.is_empty() and (r["pos"] as Vector2).distance_to(map.tile_center_px(near["tile"])) <= reach:
		if float(r["atk_cd"]) <= 0.0:
			r["atk_cd"] = float(p["attack_cooldown"])
			var mult := float(tcfg.get("brute_bld_mult", 3.0)) if String(r["type"]) == "brute" else 1.0
			_damage_building(near, float(p["damage"]) * mult)
			if not buildings.has(near):
				razed_this_raid += 1
		return true
	# путь к центру открыт — идём
	var path: PackedVector2Array = map.path_px(r["pos"], map.spawn_tile)
	if path.size() > 1:
		_raider_move_to(r, map.spawn_tile, float(p["speed"]) * dt)
		return true
	# заперты в кольце: идём ломать ближайшую стену или ворота
	var b := _nearest_building_of(r, ["wall", "gate"])
	if b.is_empty():
		b = near
	if b.is_empty():
		return false   # город пуст — волне нечего делать
	var goal := _walkable_next_to(b["tile"])
	if goal == Vector2i(-1, -1):
		return true
	_raider_move_to(r, goal, float(p["speed"]) * dt)
	return true


## Движение мутанта по кэшированному пути (как у жителей): без кэша путь
## перестраивается каждый тик и мутант дёргается на границе тайла на месте.
func _raider_move_to(r: Dictionary, tile: Vector2i, step: float) -> void:
	if r["target"] != tile:
		r["target"] = tile
		r["path"] = map.path_px(r["pos"], tile)
	var path: PackedVector2Array = r["path"]
	if path.is_empty():
		return
	var pos: Vector2 = r["pos"]
	while step > 0.0 and not path.is_empty():
		var to_next: Vector2 = path[0] - pos
		var dist := to_next.length()
		if dist <= step:
			pos = path[0]
			step -= dist
			path.remove_at(0)
		else:
			pos += to_next / dist * step
			step = 0.0
	r["pos"] = pos
	r["path"] = path


## Ближайшее к мутанту готовое здание с эффектом из wanted (пустой — любое).
func _nearest_building_of(r: Dictionary, wanted: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if not bool(b["done"]):
			continue
		if not wanted.is_empty() and not (_def(b).get("effect", "") in wanted):
			continue
		var d: float = map.tile_center_px(b["tile"]).distance_to(r["pos"])
		if d < best_d:
			best_d = d
			best = b
	return best


func _walkable_next_to(tile: Vector2i) -> Vector2i:
	for n in [tile + Vector2i(1, 0), tile + Vector2i(-1, 0), tile + Vector2i(0, 1), tile + Vector2i(0, -1)]:
		if map.is_walkable(n):
			return n
	return Vector2i(-1, -1)


## Урон мутанту (вышка, страж, герой). Слабость к школе не учитывается — урон физический.
func _hit_raider(r: Dictionary, dmg: int) -> void:
	r["hp"] = int(r["hp"]) - dmg
	if int(r["hp"]) <= 0:
		raiders.erase(r)


## Удар героя в городе (участие в обороне): дуга в сторону курсора. Возвращает, скольких задел.
func hero_slash(origin_px: Vector2, facing: Vector2, range_px: float, arc_deg: float, dmg: int) -> int:
	var hits := 0
	for r in raiders.duplicate():
		var to: Vector2 = (r["pos"] as Vector2) - origin_px
		if to.length() > range_px + float(r["p"]["radius"]):
			continue
		if absf(facing.angle_to(to)) > deg_to_rad(arc_deg) / 2.0:
			continue
		_hit_raider(r, dmg)
		hits += 1
	if raid_active and raiders.is_empty():
		_raid_end(true)
	return hits


## Выстрел героя (M14-B, лук/посох в городе): ближайший рейдер в узком конусе.
func hero_shoot(origin_px: Vector2, facing: Vector2, range_px: float, dmg: int) -> int:
	var target: Dictionary = _nearest_raider(origin_px, range_px)
	if target.is_empty():
		return 0
	var to: Vector2 = (target["pos"] as Vector2) - origin_px
	if absf(facing.angle_to(to)) > 0.3:
		return 0
	_hit_raider(target, dmg)
	if raid_active and raiders.is_empty():
		_raid_end(true)
	return 1


## Конец волны: true — отбита (награда), false — осада удалась (город понёс потери).
## M11: награда и переналадка мутантских волн — только для волн мутантов;
## лес и неспокойные духи не трогают расписание угроз.
func _raid_end(defended: bool) -> void:
	var kind := _raid_kind
	raid_active = false
	raiders.clear()
	var tcfg: Dictionary = cfg.get("threat", {})
	if kind == "mutant":
		if defended:
			var reward := int(tcfg.get("reward_crystals", 2))
			_add_resource_capped("crystal", reward)
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(tcfg.get("repelled_mood", 8.0)), 0.0, 100.0)
			events.append({"type": "raid_repelled", "crystals": reward})
			_chron("chron.repelled")
		else:
			events.append({"type": "raid_breached", "razed": razed_this_raid})
			_chron("chron.breach")
		razed_this_raid = 0
		_schedule_next_raid()
		_update_gates()   # ворота снова по правилу стража
		return
	# лес (M11): духи ушли или перебиты — лес немного успокаивается
	var fcfg: Dictionary = cfg.get("forest", {})
	if defended:
		forest_anger = maxf(0.0, forest_anger - float(fcfg.get("anger_per_tree", 2.5)) * 4.0)
		if kind == "forest":
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + 6.0, 0.0, 100.0)
			events.append({"type": "forest_repelled"})
			_chron("chron.forest_repelled")
		elif kind == "undead":
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(tcfg.get("repelled_mood", 8.0)), 0.0, 100.0)
			events.append({"type": "raid_repelled", "crystals": 0})
			_chron("chron.repelled")
	else:
		# духам всё же надоели рабочие / мёртвые разграбили город
		if kind == "forest":
			forest_anger = maxf(0.0, forest_anger - float(fcfg.get("anger_per_tree", 2.5)) * 6.0)
	razed_this_raid = 0
	_update_gates()


## --- магическая буря (M5) ---------------------------------------------------

## Дневной бросок: буря редка сама по себе и частит с загрязнением.
func _roll_storm() -> void:
	if storm_state != "" or residents.is_empty():
		return
	var scfg: Dictionary = cfg.get("storm", {})
	if scfg.is_empty():
		return
	var chance: float = float(scfg.get("base_chance", 0.02)) \
			+ float(scfg.get("pollution_chance", 0.25)) * pollution / 100.0
	if _event_rng.randf() >= chance:
		return
	storm_state = "warn"
	storm_left = float(scfg.get("warn_days", 0.3)) * float(cfg["day_length"])
	events.append({"type": "storm_warn"})
	_chron("chron.storm_warn")


func _update_storm(dt: float, day_len: float) -> void:
	if storm_state == "":
		return
	var scfg: Dictionary = cfg.get("storm", {})
	storm_left = maxf(0.0, storm_left - dt)
	if storm_state == "warn":
		if storm_left <= 0.0:
			storm_state = "active"
			storm_left = float(scfg.get("duration_days", 0.6)) * day_len
			_storm_struck_at = time
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(scfg.get("mood_hit", -10.0)), 0.0, 100.0)
			events.append({"type": "storm_start"})
			_chron("chron.storm")
		return
	# активная буря: портит воздух и бьёт по зданиям («Оберег» защищает)
	add_pollution(float(scfg.get("pollution_per_day", 10.0)) * dt / day_len)
	if time - _storm_struck_at >= float(scfg.get("strike_period_days", 0.12)) * day_len:
		_storm_struck_at = time
		var target := _storm_strike_target()
		if not target.is_empty():
			_damage_building(target, float(scfg.get("strike_damage", 12)))
			if buildings.has(target):
				events.append({"type": "storm_strike", "bld": String(target["type"])})
	if storm_left <= 0.0:
		storm_state = ""
		events.append({"type": "storm_end"})
		_chron("chron.storm_end")


## Случайное готовое здание без «Оберега» — цель удара бури.
func _storm_strike_target() -> Dictionary:
	var candidates: Array = []
	for b in buildings:
		if bool(b["done"]) and String(b.get("enchant", "")) != "ward":
			candidates.append(b)
	if candidates.is_empty():
		return {}
	return candidates[_event_rng.randi_range(0, candidates.size() - 1)]


# --- охота, животные, стражи (M5.1) ------------------------------------------

## Дикое животное (M5.1 → M14-C правка): виды из data/fauna.json — олени,
## кабаны, птицы и волки («не мирные»: охотятся на прочих зверей).
func _new_animal() -> Dictionary:
	_next_id += 1
	return {"id": _next_id, "kind": _roll_animal_kind(), "pos": _random_walkable_px(),
			"target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "idle": _event_rng.randf_range(0.0, 4.0)}


## Виды диких животных города: мирные чаще, волк — реже.
func _roll_animal_kind() -> String:
	var roll := _event_rng.randf()
	if roll < 0.38:
		return "deer"
	if roll < 0.60:
		return "boar"
	if roll < 0.80:
		return "bird"
	return "wolf"


func _random_walkable_px() -> Vector2:
	for attempt in 60:
		var tile := Vector2i(_event_rng.randi_range(1, map.w - 2), _event_rng.randi_range(1, map.h - 2))
		if map.is_walkable(tile) and building_at(tile).is_empty():
			return map.tile_center_px(tile)
	return map.tile_center_px(map.spawn_tile)


## Животные бродят по карте (чистая симуляция — без графики, для оптимизации).
func _update_animals(dt: float) -> void:
	# волки («не мирные», замечание 2026-10-20): гонятся за ближайшим мирным
	# зверем; догнали — добыча исчезает
	var eaten: Array = []
	for a in animals:
		if String(a.get("kind", "deer")) != "wolf":
			continue
		var prey := _nearest_prey_animal(a)
		if prey.is_empty():
			continue
		var to_prey: Vector2 = (prey["pos"] as Vector2) - (a["pos"] as Vector2)
		if to_prey.length() > 10.0:
			a["pos"] = (a["pos"] as Vector2) + to_prey.normalized() * 48.0 * dt
			a["path"] = PackedVector2Array()
			a["idle"] = 0.5
		else:
			eaten.append(prey)
	for prey in eaten:
		if animals.has(prey):
			animals.erase(prey)
	for a in animals:
		a["idle"] = float(a["idle"]) - dt
		if float(a["idle"]) > 0.0:
			continue
		a["idle"] = _event_rng.randf_range(2.0, 6.0)
		var here: Vector2i = map.tile_of_px(a["pos"])
		var goal: Vector2i = here + Vector2i(_event_rng.randi_range(-3, 3), _event_rng.randi_range(-3, 3))
		if map.is_walkable(goal):
			a["target"] = goal
			a["path"] = map.path_px(a["pos"], goal)
	var path: PackedVector2Array = PackedVector2Array()
	for a in animals:
		path = a["path"]
		if (path as PackedVector2Array).is_empty():
			continue
		var pos: Vector2 = a["pos"]
		var step: float = 30.0 * dt
		while step > 0.0 and not (path as PackedVector2Array).is_empty():
			var to_next: Vector2 = path[0] - pos
			var dist := to_next.length()
			if dist <= step:
				pos = path[0]
				step -= dist
				path.remove_at(0)
			else:
				pos += to_next / dist * step
				step = 0.0
		a["pos"] = pos
		a["path"] = path


## Ближайший к хищнику мирный зверь в радиусе погони.
func _nearest_prey_animal(wolf: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 140.0
	for a in animals:
		if a == wolf or String(a.get("kind", "deer")) == "wolf":
			continue
		var d: float = (a["pos"] as Vector2).distance_to(wolf["pos"])
		if d < best_d:
			best_d = d
			best = a
	return best


## Охота героя в городе (замечание 2026-10-20): удар ЛКМ снимает зверя в
## дуге; дроп — по data/fauna.json, стандартные предметы. {} — промах.
func hero_hit_animal(origin_px: Vector2, facing: Vector2, range_px: float, arc_deg: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := range_px + 8.0
	for a in animals:
		var to: Vector2 = (a["pos"] as Vector2) - origin_px
		var d := to.length()
		if d > best_d:
			continue
		if absf(facing.angle_to(to)) > deg_to_rad(arc_deg) / 2.0:
			continue
		best_d = d
		best = a
	if best.is_empty():
		return {}
	var kind := String(best.get("kind", "deer"))
	var drops: Array = []
	var fcfg: Variant = _read_json_file("res://data/fauna.json")
	if fcfg is Dictionary:
		for s in fcfg.get("species", []):
			if String(s["id"]) != kind:
				continue
			for d in s.get("drop", []):
				var n := _event_rng.randi_range(int((d["count"] as Array)[0]), int((d["count"] as Array)[1]))
				if n > 0:
					drops.append({"id": String(d["id"]), "count": n})
	animals.erase(best)
	return {"kind": kind, "drops": drops}


func _nearest_animal(from_px: Vector2, radius_px: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius_px
	for a in animals:
		var d: float = (a["pos"] as Vector2).distance_to(from_px)
		if d < best_d:
			best_d = d
			best = a
	return best


## Охотник: догоняет зверя, разделывает (hunt_time), еда в пул.
func _hunt(r: Dictionary, dt: float) -> void:
	var hcfg: Dictionary = cfg.get("hunting", {})
	var prey := _nearest_animal(r["pos"], float(hcfg.get("roam_range", 15)) * float(map.ts))
	if prey.is_empty():
		r["state"] = "idle"
		return
	if (prey["pos"] as Vector2).distance_to(r["pos"]) <= float(map.ts) * 1.3:
		r["state"] = "hunt"
		r["hunt_t"] = float(r.get("hunt_t", 0.0)) + dt
		if float(r["hunt_t"]) >= float(hcfg.get("hunt_time", 2.0)):
			r["hunt_t"] = 0.0
			animals.erase(prey)
			var food: float = float(hcfg.get("hunt_food", 6.0))
			_add_resource_capped("food", food)
			_chron("chron.hunt", String(r["name"]), str(int(food)))
			events.append({"type": "hunt", "name": String(r["name"]), "food": int(food)})
	else:
		r["hunt_t"] = 0.0
		_move_towards(r, map.tile_of_px(prey["pos"]), dt)


## Дневной бросок: зверьё восстанавливается.
func _roll_animals() -> void:
	var hcfg: Dictionary = cfg.get("hunting", {})
	if hcfg.is_empty():
		return
	if animals.size() >= int(hcfg.get("animals", 8)):
		return
	if _event_rng.randf() < float(hcfg.get("respawn_chance", 0.35)):
		animals.append(_new_animal())


## Дневной бросок: город держит стражей — двое на постоянке (день и ночь),
## больше при росте населения; берут свободных взрослых, если есть еда (заказчик).
func _roll_guards() -> void:
	var gcfg: Dictionary = cfg.get("guards", {})
	if gcfg.is_empty():
		return
	var desired: int = int(gcfg.get("base", 2)) + residents.size() / maxi(1, int(gcfg.get("per_pop", 8)))
	var have := 0
	for r in residents:
		if String(r["prof"]) == "guard":
			have += 1
	if have >= desired or not _food_reserve_ok():
		return
	for r in residents:
		if have >= desired:
			break
		if String(r["prof"]) in ["", "elder", "guard", "hunter", "porter"] or String(r.get("ail", "")) != "":
			continue
		if r["bld"] != null or r["site"] != null:
			continue
		r["prof"] = "guard"
		r["bld"] = null
		r["site"] = null
		r["sub_prof"] = ""
		have += 1
		_chron("chron.guard_trained", String(r["name"]))
		events.append({"type": "guard_trained", "name": String(r["name"])})
	_assign_shifts()
	_assign_jobs()


## Смены стражей: первый — дневной, второй — ночной, дальше чередуются.
func _assign_shifts() -> void:
	var i := 0
	for r in residents:
		if String(r["prof"]) == "guard":
			r["shift"] = "day" if i % 2 == 0 else "night"
			i += 1


## Дневной бросок: зверь водится, а охотника нет — свободный взрослый становится
## охотником (заказчик: никто не охотится, потому что профессию никто не давал).
func _roll_hunter() -> void:
	if animals.is_empty() or not _food_reserve_ok():
		return
	for r in residents:
		if String(r["prof"]) == "hunter" and String(r.get("ail", "")) == "":
			return   # охотник уже есть и на ногах
	for r in residents:
		if String(r["prof"]) in ["", "elder", "guard", "hunter", "porter"] or String(r.get("ail", "")) != "":
			continue
		if r["bld"] != null or r["site"] != null:
			continue
		r["prof"] = "hunter"
		r["bld"] = null
		r["site"] = null
		r["sub_prof"] = ""
		_chron("chron.hunter_trained", String(r["name"]))
		events.append({"type": "hunter_trained", "name": String(r["name"])})
		_assign_jobs()
		return


# --- M11: духи леса ---------------------------------------------------------

## Лес живёт: саженцы растут в деревья, гнев спадает; переполнение гнева —
## духи нападают на рубящих, при долгом злодействе — Древень с армией леса.
func _update_forest(dt: float, day_len: float) -> void:
	var fcfg: Dictionary = cfg.get("forest", {})
	if fcfg.is_empty():
		return
	# посаженное растёт
	if not map.saplings.is_empty():
		for tile: Vector2i in map.saplings.keys():
			var s: Dictionary = map.saplings[tile]
			s["t"] = float(s.get("t", 0.0)) + dt
			if float(s["t"]) < float(s.get("grow_days", fcfg.get("grow_days", 1.2))) * day_len:
				continue
			map.saplings.erase(tile)
			if map.grid[tile.y][tile.x] == map.TILE_GRASS and building_at(tile).is_empty():
				map.grid[tile.y][tile.x] = map.TILE_TREE
				forest_anger = maxf(0.0, forest_anger - float(fcfg.get("calm_per_tree", 3.0)))
				events.append({"type": "tree_grown"})
				_chron("chron.tree_grown")
			terrain_dirty = true
	# гнев леса медленно уходит сам
	forest_anger = maxf(0.0, forest_anger - float(fcfg.get("calm_per_day", 0.6)) * dt / day_len)
	if raid_active:
		return
	if forest_anger >= float(fcfg.get("warn_anger", 8.0)) and not _forest_warned:
		_forest_warned = true
		events.append({"type": "forest_warn"})
		_chron("chron.forest_warn")
	if forest_anger < float(fcfg.get("spirit_anger", 14.0)) or time < _forest_cooldown:
		return
	_spawn_forest_wave(forest_anger >= float(fcfg.get("boss_anger", 26.0)))
	_forest_cooldown = time + float(fcfg.get("cooldown_days", 1.5)) * day_len


## Волна леса: духи охотятся на рубящих; с Древенем — покрупнее.
func _spawn_forest_wave(boss: bool) -> void:
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var def_spirit: Dictionary = {}
	var def_boss: Dictionary = {}
	for d: Dictionary in _enemies_cfg:
		if String(d["id"]) == "forest_spirit":
			def_spirit = d
		elif String(d["id"]) == "forest_boss":
			def_boss = d
	if def_spirit.is_empty():
		return
	var fcfg: Dictionary = cfg.get("forest", {})
	raid_active = true
	raid_siege = false
	_raid_kind = "forest"
	# жертвы — те, кто рубит лес и ломает камень
	var victims: Array = []
	for r in residents:
		if String(r["prof"]) in ["lumberjack", "miner", "hunter"] and r["bld"] != null:
			victims.append(r)
	if victims.is_empty():
		for r in residents:
			if String(r["prof"]) != "" and r["bld"] != null:
				victims.append(r)
	var count := int(fcfg.get("boss_spirits", 5)) if boss else int(fcfg.get("spirit_count", 3))
	for i in count:
		var vic: Dictionary = victims[_event_rng.randi_range(0, maxi(0, victims.size() - 1))] if not victims.is_empty() else {}
		raiders.append({
			"id": _next_id, "type": "forest_spirit", "p": def_spirit,
			"hp": int(def_spirit["hp"]), "max_hp": int(def_spirit["hp"]),
			"pos": _spirit_spawn_px(vic), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "atk_cd": 0.0, "mode": "hunt",
			"victim_id": int(vic["id"]) if not vic.is_empty() else -1,
			"ttl": float(cfg["day_length"]) * 0.5,
		})
		_next_id += 1
	if boss and not def_boss.is_empty():
		var vic2: Dictionary = victims[0] if not victims.is_empty() else {}
		raiders.append({
			"id": _next_id, "type": "forest_boss", "p": def_boss,
			"hp": int(def_boss["hp"]), "max_hp": int(def_boss["hp"]),
			"pos": _spirit_spawn_px(vic2), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "atk_cd": 0.0, "mode": "hunt",
			"victim_id": int(vic2["id"]) if not vic2.is_empty() else -1,
			"ttl": float(cfg["day_length"]) * 0.75,
		})
		_next_id += 1
	var mood_hit := float(fcfg.get("boss_mood", -12.0)) if boss else float(fcfg.get("spirit_mood", -6.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + mood_hit, 0.0, 100.0)
	events.append({"type": "forest_boss_attack" if boss else "spirit_attack", "count": raiders.size()})
	_chron("chron.forest_boss" if boss else "chron.spirit_attack", str(raiders.size()))
	_update_gates()


## Дух является из леса: тайл рядом с жертвой, иначе — у любого дерева.
func _spirit_spawn_px(victim: Dictionary) -> Vector2:
	var anchor: Vector2i = map.tile_of_px(victim["pos"]) if not victim.is_empty() else map.spawn_tile
	for attempt in 40:
		var off := Vector2i(_event_rng.randi_range(-4, 4), _event_rng.randi_range(-4, 4))
		var tile := anchor + off
		if map.is_walkable(tile):
			return map.tile_center_px(tile)
	return map.tile_center_px(anchor)


## Охота духа (M11): догоняет свою жертву, ранит и пугает; без жертвы —
## ломает лесопилку, а если и её нет — растворяется.
func _spirit_update(r: Dictionary, dt: float) -> bool:
	var p: Dictionary = r["p"]
	var vic := _resident_by_id(int(r.get("victim_id", -1)))
	if not vic.is_empty():
		var to: Vector2 = (vic["pos"] as Vector2) - (r["pos"] as Vector2)
		if to.length() <= float(p["attack_range"]) + 10.0:
			if float(r["atk_cd"]) <= 0.0:
				r["atk_cd"] = float(p["attack_cooldown"])
				if _event_rng.randf() < 0.5:
					_make_ail(vic, "wounded", "chron.spirit_hit")
					events.append({"type": "spirit_hit", "name": String(vic["name"])})
				else:
					vic["mood"] = clampf(float(vic["mood"]) - 12.0, 0.0, 100.0)
			return true
		_raider_move_to(r, map.tile_of_px(vic["pos"]), float(p["speed"]) * dt)
		return true
	# жертвы нет: мстим лесопилке или растворяемся
	r["ttl"] = float(r.get("ttl", 30.0)) - dt
	if float(r["ttl"]) <= 0.0:
		return false
	var mill := _nearest_building_of(r, ["sawmill"])
	if mill.is_empty():
		return true
	var reach := float(p["attack_range"]) + float(map.ts) * 0.5
	if (r["pos"] as Vector2).distance_to(map.tile_center_px(mill["tile"])) <= reach:
		if float(r["atk_cd"]) <= 0.0:
			r["atk_cd"] = float(p["attack_cooldown"])
			_damage_building(mill, float(p["damage"]))
		return true
	var goal := _walkable_next_to(mill["tile"])
	if goal == Vector2i(-1, -1):
		return true
	_raider_move_to(r, goal, float(p["speed"]) * dt)
	return true


# --- M11: посадка леса -------------------------------------------------------

## Годен ли тайл под саженец.
func can_plant_at(tile: Vector2i) -> bool:
	if not map.in_bounds(tile) or map.grid[tile.y][tile.x] != map.TILE_GRASS:
		return false
	if map.stumps.has(tile) or map.saplings.has(tile):
		return false
	if not building_at(tile).is_empty() or _tile_in_zone(tile):
		return false
	return true


## Посадить саженец (семя из пула). "" — успех, иначе ключ ошибки.
func plant_sapling(tile: Vector2i) -> String:
	var fcfg: Dictionary = cfg.get("forest", {})
	if not can_plant_at(tile):
		return "bad"
	var cost := int(fcfg.get("seed_cost", 1))
	if float(res.get("seeds", 0.0)) < float(cost):
		return "no_seeds"
	res["seeds"] = float(res["seeds"]) - float(cost)
	map.saplings[tile] = {"t": 0.0, "grow_days": float(fcfg.get("grow_days", 1.2))}
	terrain_dirty = true
	events.append({"type": "sapling_planted"})
	_chron("chron.sapling_planted")
	return ""


# --- M11: добыча скалы -------------------------------------------------------

## Тайл гряды рядом с добытчиком (свой тайл непроходим — берём соседний).
func _rock_tile_near(px: Vector2) -> Vector2i:
	var base: Vector2i = map.tile_of_px(px)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var t: Vector2i = base + d
		if map.in_bounds(t) and map.rock_hp.has(t):
			return t
	return Vector2i(-1, -1)


## Каменотёс вырабатывает тайл гряды: истощённая скала вскрывает рудную жилу,
## изредка попадается кристалл, иначе тайл осыпается в траву (камень — в кучу).
func _deplete_rock(r: Dictionary, bld: Dictionary, portion: float) -> void:
	var mcfg: Dictionary = cfg.get("mountain", {})
	if mcfg.is_empty():
		return
	var tile := _rock_tile_near(r["pos"])
	if tile == Vector2i(-1, -1):
		return
	var hp: float = float(map.rock_hp.get(tile, float(mcfg.get("hp", 80.0))))
	hp -= float(mcfg.get("rate", 55.0)) * portion * work_mult(r)
	var kind := int(map.grid[tile.y][tile.x])
	if hp > 0.0:
		map.rock_hp[tile] = hp
		return
	var roll := _event_rng.randf()
	map.rock_hp.erase(tile)
	if kind == map.TILE_ROCK and roll < float(mcfg.get("ore_reveal", 0.35)):
		map.grid[tile.y][tile.x] = map.TILE_ORE
		map.rock_hp[tile] = float(mcfg.get("hp", 80.0)) * 1.3
		events.append({"type": "ore_revealed"})
		_chron("chron.ore_revealed")
	elif roll < float(mcfg.get("ore_reveal", 0.35)) + float(mcfg.get("crystal_chance", 0.06)):
		_add_pile(bld, "crystal", 1.0)
		events.append({"type": "gem_found"})
		_chron("chron.gem_found")
	else:
		_add_pile(bld, "stone", float(mcfg.get("bonus_stone", 6)))
		map.grid[tile.y][tile.x] = map.TILE_GRASS
		events.append({"type": "rock_gone"})
		_chron("chron.rock_gone")
	terrain_dirty = true


# --- M11: некромант и кладбище ----------------------------------------------

## Готовое кладбище ({} — нет).
func _cemetery() -> Dictionary:
	return _done_building_of_type("cemetery")


## Ночной ритуал (дневной бросок): тьма растёт, скелеты собираются тайно,
## при достаточной армии — восстание.
func _roll_necro() -> void:
	var ncfg: Dictionary = cfg.get("necro", {})
	var cem := _cemetery()
	if ncfg.is_empty() or cem.is_empty():
		return
	# однажды кто-то из жителей «слышит зов» и начинает тайные ритуалы
	if not _necro_chosen:
		var cands := _adults()
		if not cands.is_empty():
			var who: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
			who["secret"] = "necromancer"
			_necro_chosen = true
			_chron("chron.necro_chosen", String(who["name"]))
	# кладбище темнеет со временем
	necro_dark = clampf(necro_dark + float(ncfg.get("dark_per_night", 0.06)), 0.0, 1.0)
	if not necro_known and necro_dark >= float(ncfg.get("reveal_dark", 0.45)):
		necro_known = true
		events.append({"type": "necro_revealed"})
		_chron("chron.necro_revealed")
	# ночные призывы: у кладбища видят огни и тени
	if _necro_chosen and _event_rng.randf() < float(ncfg.get("summon_chance", 0.6)):
		necro_army += _event_rng.randi_range(1, 2)
		necro_ghosts.clear()
		var c: Vector2i = cem["tile"]
		for i in mini(3, necro_army):
			var t := _walkable_next_to(c + Vector2i(_event_rng.randi_range(-1, 1), _event_rng.randi_range(-1, 1)))
			if t != Vector2i(-1, -1):
				necro_ghosts.append(map.tile_center_px(t))
		if necro_known:
			events.append({"type": "necro_summon"})
		_chron("chron.necro_whisper")
	# тайная армия созрела — восстание
	if necro_army >= int(ncfg.get("rise_at", 8)):
		_spawn_undead_wave()


## Восстание (M11): мертвецы выходят из кладбища, армия тает вдвое.
func _spawn_undead_wave() -> void:
	var ncfg: Dictionary = cfg.get("necro", {})
	var cem := _cemetery()
	if cem.is_empty():
		return
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var skel: Dictionary = {}
	for d: Dictionary in _enemies_cfg:
		if String(d["id"]) == "skeleton":
			skel = d
			break
	if skel.is_empty():
		return
	raid_active = true
	raid_siege = true
	_raid_kind = "undead"
	var size := mini(necro_army, int(ncfg.get("wave_max", 8)))
	necro_army = int(necro_army / 2)
	var hp_mult := 1.0 + threat_value() * float(cfg.get("threat", {}).get("hp_per_threat", 0.04))
	var anchor: Vector2i = cem["tile"]
	for i in size:
		var hp := int(round(float(skel["hp"]) * hp_mult))
		var t := _walkable_next_to(anchor)
		raiders.append({
			"id": _next_id, "type": "skeleton", "p": skel,
			"hp": hp, "max_hp": hp,
			"pos": map.tile_center_px(t if t != Vector2i(-1, -1) else anchor),
			"target": Vector2i(-1, -1), "path": PackedVector2Array(),
			"atk_cd": 0.0, "mode": "advance",
		})
		_next_id += 1
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + float(ncfg.get("mood_hit", -8.0)), 0.0, 100.0)
	events.append({"type": "undead_rising", "count": size})
	_chron("chron.undead_rising", str(size))
	_update_gates()


## Кладбище разрушено — тайная армия рассыпается, некромант раскрыт.
func _necro_purge() -> void:
	necro_army = 0
	necro_dark = 0.0
	necro_ghosts = []
	for r in residents:
		if String(r.get("secret", "")) == "necromancer":
			r["secret"] = ""
			r["mood"] = clampf(float(r["mood"]) - 15.0, 0.0, 100.0)
	_necro_chosen = false
	events.append({"type": "necro_purged"})
	_chron("chron.necro_purged")


## Удар героя по кладбищу (M11): единственное здание, которое герой рушит сам.
## Возвращает "" | "necro_hit" | "necro_purged".
func hero_hit_building(origin_px: Vector2, facing: Vector2, range_px: float, arc_deg: float, dmg: int) -> String:
	for b in buildings:
		if String(b["type"]) != "cemetery" or not bool(b["done"]):
			continue
		var to: Vector2 = map.tile_center_px(b["tile"]) - origin_px
		if to.length() > range_px + float(map.ts) * 0.6:
			continue
		if absf(facing.angle_to(to)) > deg_to_rad(arc_deg) / 2.0:
			continue
		_damage_building(b, float(dmg))
		return "necro_purged" if not buildings.has(b) else "necro_hit"
	return ""
