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
## Житель: {id, name, prof, bld, site, home, state, pos, target, path, fatigue,
##          traits, mood, skill, rank, age_days, ail, ail_days, friend, work_bonus}
## Здание: {id, type, tile, done, progress, worker, enchant, ench_mult, stun_left}

const RESOURCES := ["wood", "stone", "food", "crystal", "tools"]

var map = null                  # city_map.gd, нетипизированно (см. грабли GDScript)
var cfg: Dictionary = {}
var res: Dictionary = {"wood": 0, "stone": 0, "food": 0, "crystal": 0}
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

var _next_id := 1
var _trait_map := {}            # id черты -> описание (из people["traits"])
var _spell_ready := {}          # id городского заклинания -> время готовности
var _event_rng := RandomNumberGenerator.new()
var _last_event_day := 0
var _last_daily_day := 0        # дневные броски M4: беженцы/рождения/болезни/истории
var _gate_state := {}           # id ворот -> открыты? (страж на ближней вышке)

const PEOPLE_CFG_PATH := "res://data/residents.json"


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
	_last_daily_day = 0   # дневные броски (в т.ч. стройка) — с первого дня (заказчик)
	_event_rng.randomize()
	_next_id = 1
	var people_data: Variant = _read_json_file(PEOPLE_CFG_PATH)
	people = people_data if people_data is Dictionary else {}
	_trait_map = {}
	for td in people.get("traits", []):
		_trait_map[String(td["id"])] = td
	var levels: Dictionary = cfg["start"]["levels"]
	var start_res: Dictionary = levels.get(level, levels["normal"])
	for key in RESOURCES:
		res[key] = int(start_res.get(key, 0))
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
		"prof_extra": [], "sub_prof": "",
	}
	return r


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
	return base_pop + houses * int(cfg["pop_per_house"])


func is_night() -> bool:
	var t := fmod(time, float(cfg["day_length"]))
	return t >= float(cfg["day_length"]) * (1.0 - float(cfg["night_fraction"]))


func day_number() -> int:
	return day


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
## дикого резонанса и зачарования здания.
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
	return mult


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
	if altar_enchanted():
		return {
			"cap_extra": int(mana_cfg.get("altar_cap_extra", 4)),
			"regen_period": float(mana_cfg.get("altar_regen_period", 5.0)),
		}
	return {"cap_extra": 0, "regen_period": float(mana_cfg.get("regen_period", 8.0))}


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

## Тайл годен под стройку: проходимая суша, нет здания, не аномалия.
func is_buildable_tile(tile: Vector2i) -> bool:
	if not map.in_bounds(tile) or tile == map.anomaly_tile:
		return false
	if not map.is_nature_walkable(tile):
		return false
	return building_at(tile).is_empty()


## Заложить стройплощадку: ресурсы списываются сразу (ответ №16 — достраивают рабочие).
func place_building(type_id: String, tile: Vector2i) -> bool:
	var def := _def({"type": type_id})
	if def.is_empty() or not is_buildable_tile(tile) or not can_afford(def["cost"]):
		return false
	for key in def["cost"]:
		res[key] = int(res[key]) - int(def["cost"][key])
	buildings.append({
		"id": _next_id, "type": type_id, "tile": tile,
		"done": false, "progress": 0.0, "worker": -1,
		"enchant": "", "ench_mult": 1.0, "stun_left": 0.0,
	})
	_next_id += 1
	events.append({"type": "site", "bld": type_id})
	_assign_jobs()
	return true


func _complete_site(site: Dictionary) -> void:
	site["done"] = true
	site["progress"] = 0.0
	site["worker"] = -1
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
		pollution = maxf(0.0, pollution - float(pol_cfg.get("decay_per_day", 2.0)) * dt / day_len)
	for b in buildings:
		if float(b.get("stun_left", 0.0)) > 0.0:
			b["stun_left"] = maxf(0.0, float(b["stun_left"]) - dt)
	_update_gates()
	_update_wild_events(pol_cfg, day_len)
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
	# голод: без дела — стоит; занятый работает вполсилы (иначе город умирает навсегда)
	if float(res["food"]) <= 0.0 and r["site"] == null and r["bld"] == null:
		r["state"] = "hungry"
		r["path"] = PackedVector2Array()
		return
	# ребёнок: растёт, не работает; повзрослел — получает профессию и черты
	if String(r["prof"]) == "":
		r["age_days"] = float(r.get("age_days", 0.0)) + dt / day_len
		var bcfg: Dictionary = people.get("births", {})
		if float(r["age_days"]) >= float(bcfg.get("child_days", 8.0)):
			_grow_up(r)
			return
		r["state"] = "child"
		r["path"] = PackedVector2Array()
		return
	# болен или ранен: идёт домой и лежит
	if String(r.get("ail", "")) != "":
		_lie_ill(r, dt)
		return
	var night := is_night()
	# ночь: все, кроме стража на вышке, спят
	if night and String(r["prof"]) != "guard":
		_sleep(r, dt)
		return
	# сильная усталость: отдых в любое время
	if float(r["fatigue"]) >= float(cfg["tired_at"]):
		r["state"] = "rest"
		r["fatigue"] = maxf(0.0, float(r["fatigue"]) - _restore_rate(r, false) * dt / day_len)
		r["path"] = PackedVector2Array()
		return
	if r["site"] != null:
		_do_build(r, r["site"], dt)
		return
	if r["bld"] != null:
		# производственное здание; без выработки (вышка стража) — просто пост
		if _def(r["bld"]).has("produce"):
			_do_work(r, r["bld"], dt)
		else:
			r["state"] = "idle"
		return
	if String(r["prof"]) == "elder":
		_manage_walk(r, dt)
		return
	# страж ночью идёт на вышку
	if night and String(r["prof"]) == "guard":
		var tower := _assigned_done(r, "guard")
		if not tower.is_empty():
			if _arrived(r, tower["tile"]):
				r["state"] = "guard"
				r["fatigue"] += dt / day_len
			else:
				_move_towards(r, tower["tile"], dt)
			return
	r["state"] = "idle"


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
		var amount: float = float(prod["per_day"]) * dt / float(cfg["day_length"]) * boost * production_mult(bld) * work_mult(r)
		var key2 := String(prod["res"])
		res[key2] = minf(float(storage_cap()), float(res[key2]) + amount)
	else:
		_move_towards(r, bld["tile"], dt)


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
	var step: float = float(cfg["resident_speed"]) * dt
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


# --- ворота в стене ---------------------------------------------------------

## Ворота открыты, если рядом (≤3 тайлов) стоит вышка со стражем (заказчик).
func _gate_open(gate: Dictionary) -> bool:
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
	if _friend_alive(r):
		target += float(people.get("friend_mood", 6.0))
	if tavern_active():
		var tcfg: Dictionary = cfg.get("tavern", {})
		target += float(tcfg.get("mood", 12.0))
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
	residents.erase(r)
	_assign_jobs()


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
func _food_reserve_ok() -> bool:
	return float(res["food"]) >= float(residents.size()) * float(cfg["food_per_resident_day"])


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
	# кризис: еды меньше чем на день — ферма вне очереди
	var critical_food: float = float(residents.size()) * float(cfg["food_per_resident_day"])
	if float(res["food"]) < critical_food and not _autobuild_site_exists("farm") and not _idle_farm_exists():
		var tile := _find_autobuild_tile("farm")
		if not tile == Vector2i(-1, -1) and place_building("farm", tile):
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


## Тайл под самострой: районы (заказчик) — жилые здания к западу от центра,
## производственные к востоку. Своё место в районе занято — общий поиск.
func _find_autobuild_tile(type_id: String) -> Vector2i:
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
func _roll_births() -> void:
	var bcfg: Dictionary = people.get("births", {})
	if bcfg.is_empty() or residents.size() >= pop_cap():
		return
	if not _food_reserve_ok() or _avg_mood() < float(bcfg.get("mood_gate", 60.0)):
		return
	if _event_rng.randf() >= float(bcfg.get("chance_per_day", 0.25)):
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
