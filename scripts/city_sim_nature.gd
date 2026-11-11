# Часть: улей мутантов, удары героя в городе, магическая буря, звери и охота, духи леса.
# Структура v1.62.0: бывший city_sim_threat.gd разрезан на extends-цепочку
# war -> nature -> threat — это один класс, поведение не меняется.
extends "res://scripts/city_sim_war.gd"

## ==================== УЛЕЙ МУТАНТОВ (v1.44, «Новый мир v2») ==============

## Тик улья: постройка у аномалии, роли, рост от запаса, волны.
static var _hive_cfg_cache: Dictionary = {}


func _hive_cfg() -> Dictionary:
	# v1.44: конфиг улья живёт в balance.json (city.json — про город)
	if _hive_cfg_cache.is_empty():
		var parsed: Variant = _read_json_file("res://data/balance.json")
		if parsed is Dictionary and (parsed as Dictionary).has("hive"):
			_hive_cfg_cache = parsed["hive"]
	return _hive_cfg_cache


func _update_hive(dt: float, day_len: float) -> void:
	var hcfg: Dictionary = _hive_cfg()
	if hcfg.is_empty() or hcfg.get("enabled", true) == false:
		return
	# v1.44: в автотестах улей молчит (ломает сценарные тесты волн/заселения),
	# кроме собственных тестов улья (PEPEL_HIVE_ON)
	if OS.has_environment("PEPEL_TEST_MAPS") 			and not OS.has_environment("PEPEL_HIVE_ON"):
		return
	if not hive.is_empty() and not bool(hive.get("active", false)):
		# улей разорён — аномалия отстраивает новый через RESPAWN_DAYS
		if time >= float(hive.get("respawn_day", 0.0)) * day_len:
			hive = {}
		return
	if hive.is_empty():
		if float(day) < float(hcfg.get("start_day", HiveSim.START_DAY)):
			return
		# улей строится у аномалии: пятно в 3-6 тайлах, на проходимой земле
		for attempt in 40:
			var off := Vector2i(_raid_rng.randi_range(-6, 6), _raid_rng.randi_range(-6, 6))
			var t: Vector2i = map.anomaly_tile + off
			if map.is_walkable(t) and t.distance_to(map.anomaly_tile) >= 3:
				hive = {"active": true,
						"pos": map.tile_center_px(t), "tile": t,
						"hp": float(HiveSim.HP), "level": 1,
						"stock": 0, "gathered": 0, "waves": 0,
						"next_wave_day": float(day) + HiveSim.wave_days(1),
						"respawn_day": 0.0, "alert": 0.0}
				events.append({"type": "hive_built"})
				_chron("chron.hive_built")
				break
		return
	var level: int = int(hive["level"])
	var want: Array = HiveSim.roles_for(level)
	var have: Array = _hive_role_counts()
	# добор ролей (юниты живут в общем списке рейдеров — весь бой/урон/отрисовка)
	var roles := ["guard", "gatherer", "scout"]
	for ri in roles.size():
		while have[ri] < int(want[ri]):
			if _spawn_hive_unit(roles[ri]) == null:
				break
			have[ri] += 1
	# рост уровня от запаса
	var new_level: int = HiveSim.level_for(int(hive["stock"]))
	if new_level > level:
		hive["level"] = new_level
		events.append({"type": "hive_grew", "level": new_level})
	# волны: ресурс улья оплачивает набеги — чем удачнее сбор, тем сильнее
	if float(day) >= float(hive["next_wave_day"]) \
			and int(hive["stock"]) >= int(hcfg.get("wave_stock_min", 10)):
		var size := HiveSim.wave_size(int(hive["level"]), int(hive["stock"]), int(hive["waves"]))
		hive["waves"] = int(hive["waves"]) + 1
		hive["stock"] = int(hive["stock"]) - int(hive["stock"]) / 3
		hive["next_wave_day"] = float(day) + HiveSim.wave_days(int(hive["level"]))
		_spawn_hive_wave(size)


## Юниты улья тикаются ВСЕГДА (вне raid_active их гоняет отдельный цикл).
func _update_hive_units(dt: float, tcfg: Dictionary) -> void:
	if raid_active:
		return
	var i := 0
	while i < raiders.size():
		var r: Dictionary = raiders[i]
		if String(r.get("role", "")).is_empty():
			i += 1
			continue
		if _raider_update(r, dt, tcfg) == false or int(r["hp"]) <= 0:
			raiders.remove_at(i)
			continue
		i += 1



func _hive_role_counts() -> Array:
	var out := [0, 0, 0]
	for r in raiders:
		match String(r.get("role", "")):
			"guard":
				out[0] += 1
			"gatherer":
				out[1] += 1
			"scout":
				out[2] += 1
	return out


## Юнит улья: как рейдер, но с ролью и вне расписания волн угрозы.
func _spawn_hive_unit(role: String):
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var def := _pick_raider_def(cfg.get("threat", {}))
	if def.is_empty():
		return null
	var pos: Vector2 = hive["pos"]
	for attempt in 20:
		var off := Vector2i(_raid_rng.randi_range(-2, 2), _raid_rng.randi_range(-2, 2))
		var t: Vector2i = (hive["tile"] as Vector2i) + off
		if map.is_walkable(t):
			pos = map.tile_center_px(t)
			break
	var unit := {
		"id": _next_id, "type": String(def["id"]), "p": def,
		"hp": int(def["hp"]), "max_hp": int(def["hp"]),
		"pos": pos, "target": Vector2i(-1, -1), "path": PackedVector2Array(),
		"atk_cd": 0.0, "mode": "hive", "role": role,
		"carry": 0, "res_tile": Vector2i(-1, -1), "hive": true,
	}
	_next_id += 1
	raiders.append(unit)
	return unit


## Волна ИЗ улья (не из расписания угроз): сильнее с уровнем и успехом.
func _spawn_hive_wave(size: int) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	raid_active = true
	raid_siege = false
	_raid_kind = "mutant"
	raid_count += 1
	razed_this_raid = 0
	var hp_mult := 1.0 + float(int(hive["level"]) - 1) * 0.25
	for i in size:
		var def := _pick_raider_def(tcfg)
		if def.is_empty():
			break
		var hp := int(round(float(def["hp"]) * hp_mult))
		raiders.append({
			"id": _next_id, "type": String(def["id"]), "p": def,
			"hp": hp, "max_hp": hp,
			"pos": (hive["pos"] as Vector2)
					+ Vector2(_raid_rng.randf_range(-24, 24), _raid_rng.randf_range(-24, 24)),
			"target": Vector2i(-1, -1), "path": PackedVector2Array(),
			"atk_cd": 0.0, "mode": "advance",
		})
		_next_id += 1
	events.append({"type": "hive_wave", "count": size, "level": int(hive["level"])})
	_chron("chron.hive_wave", str(size))
	_update_gates()


## Добытчик: к ресурсу (дерево/скала в радиусе улья) — собирает — в улей.
func _hive_gatherer_update(r: Dictionary, dt: float) -> bool:
	var level: int = int(hive.get("level", 1))
	var radius := HiveSim.radius_for(level) * float(map.ts)
	var home: Vector2 = hive["pos"]
	var speed: float = float(r["p"]["speed"]) * dt
	if not _hive_resource_ok(Vector2i(r.get("res_tile", Vector2i(-1, -1)))):
		r["res_tile"] = _hive_find_resource(home, radius)
		return true
	var rt: Vector2i = Vector2i(r["res_tile"])
	var full: bool = int(r.get("carry", 0)) >= HiveSim.GATHER_PER_TRIP
	var goal: Vector2 = home if full else map.tile_center_px(rt)
	var to: Vector2 = goal - (r["pos"] as Vector2)
	if to.length() <= float(map.ts) * 0.8:
		if full:
			hive["stock"] = int(hive["stock"]) + int(r["carry"])
			hive["gathered"] = int(hive["gathered"]) + int(r["carry"])
			r["carry"] = 0
		else:
			r["carry"] = HiveSim.GATHER_PER_TRIP
			_hive_consume_resource(rt)
		return true
	# v1.49: путь к цели перекрыт (пруд/гряда добора природы) — добытчик
	# бросает эту цель и ищет другую, а не удаляется из рейдеров каждый тик
	if not _raider_move_to(r, map.tile_of_px(goal), speed):
		r["res_tile"] = Vector2i(-1, -1)
		r["path"] = PackedVector2Array()
	return true


## Скаут: свежие СЛЕДЫ героя в радиусе — идёт по ним (тревога улья);
## иначе круговой дозор, расширяющий известную территорию.
func _hive_scout_update(r: Dictionary, dt: float) -> bool:
	var level: int = int(hive.get("level", 1))
	var radius := HiveSim.radius_for(level) * float(map.ts)
	var home: Vector2 = hive["pos"]
	var trail: Vector2 = HiveSim.track_near(hero_tracks, home, radius * 1.3, float(time))
	if trail != Vector2.INF:
		hive["alert"] = 3.0
		if not _raider_move_to(r, map.tile_of_px(trail), float(r["p"]["speed"]) * dt):
			r["path"] = PackedVector2Array()   # путь перекрыт — стоит, не гибнет
		return true
	var ang: float = float(int(r["id"]) % 7) * 0.9 + float(time) * 0.15
	var goal := home + Vector2(cos(ang), sin(ang)) * radius * 0.8
	var gt: Vector2i = map.tile_of_px(goal)
	if not map.is_walkable(gt):
		return true
	if not _raider_move_to(r, gt, float(r["p"]["speed"]) * dt):
		r["path"] = PackedVector2Array()
	return true


## Страж: держится у улья (герой рядом — дефолтная ветка боя ниже).
func _hive_guard_update(r: Dictionary, dt: float, tcfg: Dictionary) -> bool:
	var home: Vector2 = hive["pos"]
	var guard_r := float(map.ts) * 5.0
	if (r["pos"] as Vector2).distance_to(home) > guard_r:
		if not _raider_move_to(r, map.tile_of_px(home), float(r["p"]["speed"]) * dt):
			r["path"] = PackedVector2Array()   # отрезан — ждёт, не исчезает
	return true


## Ресурс улья: дерево/скала/руда в радиусе (линейный скан окна).
func _hive_find_resource(home: Vector2, radius_px: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := radius_px
	var home_t: Vector2i = map.tile_of_px(home)
	var r_t := int(radius_px / float(map.ts))
	for y in range(maxi(1, home_t.y - r_t), mini(map.h - 1, home_t.y + r_t)):
		for x in range(maxi(1, home_t.x - r_t), mini(map.w - 1, home_t.x + r_t)):
			var t := Vector2i(x, y)
			var dd := float(t.distance_squared_to(home_t))
			if dd > r_t * r_t:
				continue
			var g: int = map.grid[t.y][t.x]
			if g != map.TILE_TREE and g != map.TILE_ROCK and g != map.TILE_ORE:
				continue
			if dd < best_d:
				best_d = dd
				best = t
	return best


func _hive_resource_ok(t: Vector2i) -> bool:
	if not map.in_bounds(t):
		return false
	var g: int = map.grid[t.y][t.x]
	return g == map.TILE_TREE or g == map.TILE_ROCK or g == map.TILE_ORE


## Добыча улья истощает тайл: дерево срубается, скала крошится.
func _hive_consume_resource(t: Vector2i) -> void:
	if map.grid[t.y][t.x] == map.TILE_TREE:
		map.grid[t.y][t.x] = map.TILE_GRASS
		map.tree_size.erase(t)
		map.stumps[t] = true
	else:
		map.rock_hp[t] = float(map.rock_hp.get(t, 60.0)) - 30.0
		if float(map.rock_hp[t]) <= 0.0:
			map.grid[t.y][t.x] = map.TILE_GRASS
			map.rock_hp.erase(t)
	map.note_edit(t)
	terrain_dirty = true


## Улей бьют (удар героя по позиции улья в дуге).
func _hive_take_damage(dmg: int) -> void:
	hive["hp"] = float(hive["hp"]) - float(dmg)
	if float(hive["hp"]) > 0.0:
		return
	var level: int = int(hive["level"])
	var loot: Dictionary = HiveSim.loot_for(level)
	for key in loot:
		res[key] = float(res.get(key, 0.0)) + float(loot[key])
	events.append({"type": "hive_destroyed", "level": level})
	_chron("chron.hive_destroyed", str(level))
	# юниты без дома бросают роли и разбегаются (остаются как волна)
	for r in raiders:
		if not String(r.get("role", "")).is_empty():
			r.erase("role")
			r["mode"] = "advance"
	hive = {"active": false, "respawn_day": float(day) + float(HiveSim.RESPAWN_DAYS),
			"pos": hive.get("pos", Vector2.ZERO), "tile": hive.get("tile", map.anomaly_tile)}


## Удар героя в городе (участие в обороне): дуга в сторону курсора. Возвращает, скольких задел.
func hero_slash(origin_px: Vector2, facing: Vector2, range_px: float, arc_deg: float, dmg: int) -> int:
	var hits := 0
	var hero_tile: Vector2i = map.tile_of_px(origin_px)
	# v1.44: улей — тоже цель удара (разорение с наградой)
	if not hive.is_empty() and bool(hive.get("active", false)):
		var to_hive: Vector2 = (hive["pos"] as Vector2) - origin_px
		if to_hive.length() <= range_px + float(map.ts) * 0.6 \
				and absf(facing.angle_to(to_hive)) <= deg_to_rad(arc_deg) / 2.0:
			_hive_take_damage(dmg)
			hits += 1
	for r in raiders.duplicate():
		var to: Vector2 = (r["pos"] as Vector2) - origin_px
		if to.length() > range_px + float(r["p"]["radius"]):
			continue
		if absf(facing.angle_to(to)) > deg_to_rad(arc_deg) / 2.0:
			continue
		_hit_raider(r, dmg, hero_tile, "hero")
		hits += 1
	if raid_active and _wave_raiders_left() == 0:
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
	_hit_raider(target, dmg, map.tile_of_px(origin_px), "hero")
	if raid_active and _wave_raiders_left() == 0:
		_raid_end(true)
	return 1


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
		if _active(b) and String(b.get("enchant", "")) != "ward":
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


## Виды диких животных города (v1.50: +заяц и лиса — живности разнообразнее):
## мирные чаще, волк и лиса — реже.
func _roll_animal_kind() -> String:
	var roll := _event_rng.randf()
	if roll < 0.30:
		return "deer"
	if roll < 0.50:
		return "boar"
	if roll < 0.65:
		return "bird"
	if roll < 0.78:
		return "hare"
	if roll < 0.88:
		return "fox"
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


# --- M11: духи леса ---------------------------------------------------------

## Лес живёт (правки v1.21): саженец 5 дней растёт до малого дерева (гнев −),
## малое +5 дней — до среднего, среднее +10 дней — до большого (любое дерево
## на карте растёт); гнев спадает медленно; переполнение — духи, потом Древень.
func _update_forest(dt: float, day_len: float) -> void:
	var fcfg: Dictionary = cfg.get("forest", {})
	if fcfg.is_empty():
		return
	# посаженное растёт до малого дерева
	if not map.saplings.is_empty():
		for tile: Vector2i in map.saplings.keys():
			var s: Dictionary = map.saplings[tile]
			s["t"] = float(s.get("t", 0.0)) + dt
			if float(s["t"]) < float(s.get("grow_days", fcfg.get("grow_days", 5.0))) * day_len:
				continue
			map.saplings.erase(tile)
			if map.grid[tile.y][tile.x] == map.TILE_GRASS and building_at(tile).is_empty():
				map.grid[tile.y][tile.x] = map.TILE_TREE
				map.tree_size[tile] = map.TREE_SMALL   # роста в этом тике не будет
				forest_anger = maxf(0.0, forest_anger - float(fcfg.get("calm_per_tree", 2.0)))
				events.append({"type": "tree_grown"})
				_chron("chron.tree_grown")
			terrain_dirty = true
	# растут и дикие деревья: малое → среднее (5 дней), среднее → большое (10).
	# Первый тик жизни нового дерева не считается (оно выросло из саженца
	# посреди тика — полный dt роста был бы двойным учётом, v1.21)
	for tile: Vector2i in map.tree_size.keys():
		if int(map.tree_size[tile]) >= map.TREE_LARGE:
			continue
		if not map.in_bounds(tile) or map.grid[tile.y][tile.x] != map.TILE_TREE:
			map.tree_growth.erase(tile)
			continue
		if not map.tree_growth.has(tile):
			map.tree_growth[tile] = 0.0
			continue
		var t_days: float = float(map.tree_growth.get(tile, 0.0)) + dt / day_len
		var size := int(map.tree_size[tile])
		var need := float(fcfg.get("grow_days_medium", 5.0)) if size == map.TREE_SMALL \
				else float(fcfg.get("grow_days_large", 10.0))
		if t_days >= need:
			map.tree_size[tile] = size + 1
			t_days = 0.0
			terrain_dirty = true
		map.tree_growth[tile] = t_days
	# гнев леса медленно уходит сам
	forest_anger = maxf(0.0, forest_anger - float(fcfg.get("calm_per_day", 0.35)) * dt / day_len)
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
## ломает лесопилку, а если и её нет — растворяется. v1.26: жертва за стеной —
## дух ломает преграду, а не толчётся у неё до рассвета.
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
		if _raider_move_to(r, map.tile_of_px(vic["pos"]), float(p["speed"]) * dt):
			return true
		return _raider_break_obstacle(r, dt, p, _nearest_building_of(r, ["wall", "gate"]))
	# жертвы нет: мстим лесопилке или растворяемся
	r["ttl"] = float(r.get("ttl", 30.0)) - dt
	if float(r["ttl"]) <= 0.0:
		return false
	var mill := _nearest_building_of(r, ["sawmill"])
	if mill.is_empty():
		return true
	var reach := float(p["attack_range"]) + float(map.ts) * 0.5
	if bld_dist_px(r["pos"], mill) <= reach:
		if float(r["atk_cd"]) <= 0.0:
			r["atk_cd"] = float(p["attack_cooldown"])
			_damage_building(mill, float(p["damage"]))
		return true
	var goal := _walkable_next_to_rect(mill)
	if goal == Vector2i(-1, -1):
		return true
	_raider_move_to(r, goal, float(p["speed"]) * dt)
	return true
