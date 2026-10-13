extends RefCounted
## Симуляция города (M2): общий пул ресурсов, стройка силами строителей,
## жители-статисты (6 профессий): работа, еда, сон. Чистая логика без сцены.
## Живёт в автозагрузке Game — город продолжает жить, пока герой в данже.
##
## Житель: {id, name, prof, bld, site, home, state, pos, target, path, fatigue}
## Здание: {id, type, tile, done, progress, worker}

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
var events: Array = []          # [{"type": "site"|"built"|"no_worker", "bld": id}] — читает сцена
var base_pop := 0               # жители на старте — база лимита

var _next_id := 1


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
		if b["done"] and _def(b)["effect"] == "storage":
			extra += int(cfg["storage_per_warehouse"])
	return int(cfg["storage_base"]) + extra


func pop_cap() -> int:
	var houses := 0
	for b in buildings:
		if b["done"] and _def(b)["effect"] == "pop":
			houses += 1
	return base_pop + houses * int(cfg["pop_per_house"])


func is_night() -> bool:
	var t := fmod(time, float(cfg["day_length"]))
	return t >= float(cfg["day_length"]) * (1.0 - float(cfg["night_fraction"]))


func day_number() -> int:
	return day


## Благословение алтаря: есть готовый алтарь с работающим магом-учеником.
func has_blessing() -> bool:
	for b in buildings:
		if b["done"] and _def(b)["effect"] == "altar" and int(b["worker"]) > 0:
			return true
	return false


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
	})
	_next_id += 1
	events.append({"type": "site", "bld": type_id})
	_assign_jobs()
	return true


func _complete_site(site: Dictionary) -> void:
	site["done"] = true
	site["progress"] = 0.0
	site["worker"] = -1
	if _def(site)["effect"] == "wall":
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
	for r in residents:
		_update_resident(r, dt)


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
		if not b["done"] or _def(b)["effect"] != "pop":
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
		if b["done"] and _def(b)["effect"] == "sleep":
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
	if _arrived(r, bld["tile"]):
		r["state"] = "work"
		r["fatigue"] += dt / float(cfg["day_length"])
		var prod: Dictionary = _def(bld)["produce"]
		var boost: float = float(cfg["altar_boost"]) if has_blessing() else 1.0
		var amount: float = float(prod["per_day"]) * dt / float(cfg["day_length"]) * boost
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
