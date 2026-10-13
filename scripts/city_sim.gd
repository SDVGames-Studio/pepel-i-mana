extends RefCounted
## Симуляция города (M2): общий пул ресурсов, стройка силами строителей,
## жители-статисты (6 профессий): работа, еда, сон. Чистая логика без сцены.
## Живёт в автозагрузке Game — город продолжает жить, пока герой в данже.
##
## M3 (магия): магическое загрязнение с полосами и дикими событиями,
## городские заклинания (резонанс/очищение/дары леса) с кулдаунами,
## зачарование зданий руной + кристаллом, стан зданий от диких вспышек.
##
## Житель: {id, name, prof, bld, site, home, state, pos, target, path, fatigue}
## Здание: {id, type, tile, done, progress, worker, enchant, ench_mult, stun_left}

const RESOURCES := ["wood", "stone", "food", "crystal"]

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
var events: Array = []          # [{"type": "site"|"built"|"no_worker"|"wild_*", ...}] — читает сцена
var base_pop := 0               # жители на старте — база лимита

var _next_id := 1
var _spell_ready := {}          # id городского заклинания -> время готовности
var _event_rng := RandomNumberGenerator.new()
var _last_event_day := 0


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
	_event_rng.randomize()
	_next_id = 1
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
		residents.append({
			"id": _next_id, "name": String(names[i % names.size()]),
			"prof": String(profs[i % profs.size()]),
			"bld": null, "site": null, "home": null,
			"state": "idle", "pos": map.tile_center_px(tile),
			"target": Vector2i(-1, -1), "path": PackedVector2Array(),
			"fatigue": 0.0,
		})
		_next_id += 1
	_assign_jobs()


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
	events.append({"type": "built", "bld": String(site["type"])})
	_assign_jobs()


# --- жители --------------------------------------------------------------

## Раздача работы: производственные здания и стройплощадки — свободным жителям.
func _assign_jobs() -> void:
	var taken := {}   # id жителя -> занят
	for r in residents:
		if r["bld"] != null or r["site"] != null:
			taken[int(r["id"])] = true
	for b in buildings:
		var def := _def(b)
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
	for b in buildings:
		if not b["done"] or not def_has_worker(b):
			continue
		if int(b["worker"]) > 0 and taken.has(int(b["worker"])):
			continue
		var worker := _free_resident(String(_def(b)["worker"]), taken)
		if worker.is_empty():
			events.append({"type": "no_worker", "bld": String(b["type"])})
			continue
		b["worker"] = int(worker["id"])
		worker["bld"] = b
		worker["site"] = null
		taken[int(worker["id"])] = true


func def_has_worker(b: Dictionary) -> bool:
	return _def(b).has("worker")


## Свободный житель профессии prof (ничем не занят и не закреплён).
func _free_resident(prof: String, taken: Dictionary) -> Dictionary:
	for r in residents:
		if taken.has(int(r["id"])):
			continue
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
	# еда: все жители едят непрерывно; пусто — город голодает
	var eat: float = float(cfg["food_per_resident_day"]) * dt / day_len * residents.size()
	res["food"] = maxf(0.0, float(res["food"]) - eat)
	# магия (M3): резонанс, спад загрязнения, стан зданий, дикие события
	if resonance_left > 0.0:
		resonance_left = maxf(0.0, resonance_left - dt)
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	if not pol_cfg.is_empty() and pollution > 0.0:
		pollution = maxf(0.0, pollution - float(pol_cfg.get("decay_per_day", 2.0)) * dt / day_len)
	for b in buildings:
		if float(b.get("stun_left", 0.0)) > 0.0:
			b["stun_left"] = maxf(0.0, float(b["stun_left"]) - dt)
	_update_wild_events(pol_cfg, day_len)
	for r in residents:
		_update_resident(r, dt)


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
	# голод: работы нет, стоит
	if float(res["food"]) <= 0.0:
		r["state"] = "hungry"
		r["path"] = PackedVector2Array()
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
		return
	if _arrived(r, site["tile"]):
		r["state"] = "build"
		site["progress"] = float(site["progress"]) + dt
		r["fatigue"] += dt / float(cfg["day_length"])
		if float(site["progress"]) >= float(_def(site)["build_work"]):
			r["site"] = null
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
		var prod: Dictionary = _def(bld)["produce"]
		var boost: float = float(cfg["altar_boost"]) if has_blessing() else 1.0
		var amount: float = float(prod["per_day"]) * dt / float(cfg["day_length"]) * boost * production_mult(bld)
		var key := String(prod["res"])
		res[key] = minf(float(storage_cap()), float(res[key]) + amount)
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
