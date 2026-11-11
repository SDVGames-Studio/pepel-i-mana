# Часть: урон и руины, починка (бригада v1.50 / герой), миграция старых сейвов
# и бесплатный перенос зданий.
# Структура v1.62.0: вынесено из city_sim_build.gd — это один класс,
# поведение не меняется.
extends "res://scripts/city_sim_build.gd"

## Миграция старых сейвов (этап 2, аспект 2): здания без поля "w" — 1×1.
## Расширяем до 2×2 на месте, если есть место; иначе бесплатно переносим
## на ближайшее подходящее; в крайнем случае здание остаётся 1×1 (не теряем).
func migrate_legacy_buildings() -> void:
	var migrated := 0
	for b in buildings:
		if b.has("w"):
			continue
		var w := bld_w(b)   # размер из конфига (у здания поля ещё нет)
		if w <= 1:
			b["w"] = 1
			continue
		# до удачного расширения/переноса здание остаётся 1×1 — проверки места
		# не считают его собственный будущий прямоугольник занятостью
		if _try_expand_bld(b) or _try_relocate_bld(b):
			b["w"] = w
			migrated += 1
		else:
			b["w"] = 1   # совсем некуда — живёт в 1×1, игрок перенесёт сам
	_spots_dirty()
	if migrated > 0:
		events.append({"type": "bld_migrated", "n": migrated})


## Расширение 1×1 до 2×2 на месте: три соседние клетки свободны и пригодны.
func _try_expand_bld(b: Dictionary) -> bool:
	var t: Vector2i = Vector2i(b["tile"])
	for off: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var c: Vector2i = t + off
		if not map.in_bounds(c) or c == map.anomaly_tile:
			return false
		var type_id := String(b["type"])
		var ok_nature: bool = map.is_nature_walkable(c) \
				or (type_id == "mine" and int(map.grid[c.y][c.x]) in [map.TILE_ORE, map.TILE_DEADROCK])
		if not ok_nature or not building_at(c).is_empty():
			return false
		if map.bridges.has(c):
			return false
		for g in graves:
			if Vector2i(g["tile"]) == c:
				return false
	# дороги и зоны под новыми клетками уступают место — как при стройке
	for off2: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var c2: Vector2i = t + off2
		map.remove_road(c2)
		_drop_zone_cell(c2)
	return true


## Бесплатный перенос: ближайшее к старому месту годное 2×2 (правила места — те же).
func _try_relocate_bld(b: Dictionary) -> bool:
	var type_id := String(b["type"])
	var old := Vector2i(b["tile"])
	for radius in range(1, 13):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := old + Vector2i(dx, dy)
				if not is_buildable_rect(type_id, t) or placement_block(type_id, t) != "" \
						or not placement_gap_ok(type_id, t):
					continue
				var w := bld_w_of_type(type_id)
				for cy in w:
					for cx in w:
						var cell := t + Vector2i(cx, cy)
						map.remove_road(cell)
						_drop_zone_cell(cell)
				b["tile"] = t
				return true
	return false


## Урон зданию от мутантов и бури; на нуле прочности здание разрушается.
## Разрушение (этап 2, аспект 5, ответ №17 «ремонт, не снос»): готовое здание
## НЕ исчезает — остаётся руинами на карте (клетки проходимы как обломки,
## но место занято и строить нельзя), чинится за 40% стоимости.
## Стройплощадка сносится совсем. true — здание только что разрушено.
func _damage_building(b: Dictionary, amount: float) -> bool:
	b["hp"] = float(b.get("hp", float(_bld_max_hp(String(b["type"]))))) - amount
	if float(b["hp"]) > 0.0:
		return false
	# разрушено: рабочее место освобождается, стена перестаёт быть преградой
	# v1.21.4: входы и индекс клеток устаревают при любом исходе (снос площадки
	# раньше не сбрасывал кэши — индекс держал здание-призрак на клетках)
	_spots_dirty()
	if int(b["worker"]) > 0:
		for r in residents:
			if int(r["id"]) == int(b["worker"]):
				r["bld"] = null
				r["site"] = null
				r["sub_prof"] = ""
				break
		b["worker"] = -1
	# дом разрушен — живущие в нём остаются без дома (этап 2, аспект 5)
	for r in residents:
		var home: Variant = r.get("home", null)
		if home is Dictionary and not (home as Dictionary).is_empty() \
				and int((home as Dictionary).get("id", -1)) == int(b["id"]):
			r["home"] = null
	if _def(b).get("effect", "") in ["wall", "gate"]:
		map.set_solid(b["tile"], false)
	elif bool(b.get("done", false)):
		# руины не преграждают путь (обломки), но клетки остаются за зданием
		for cell in bld_cells(b):
			map.set_solid(cell, false)
	if not bool(b.get("done", false)):
		buildings.erase(b)   # стройплощадка — просто снос
		return true
	b["razed"] = true
	b["hp"] = 0.0
	b["enchant"] = ""   # руины не удерживают зачарование
	b["stun_left"] = 0.0
	# кладбище разрушено (мутантами, бурей) — тайная армия рассыпается (M11)
	if String(b["type"]) == "cemetery":
		_necro_purge()
	events.append({"type": "razed", "bld": String(b["type"])})
	_chron("chron.razed", String(b["type"]))
	return true


## Готовое и НЕ разрушенное здание — «действующее» (даёт эффект, работу,
## считается в лимитах). Руины и стройплощадки эффектов не дают (этап 2, аспект 5).
func _active(b: Dictionary) -> bool:
	return bool(b["done"]) and not bool(b.get("razed", false))


## Цена ремонта (доля стоимости постройки; frac_v < 0 — доля героя из
## конфига): каждый ресурс округляется вверх (минимум 1, если был в цене).
func repair_cost(type_id: String, frac_v := -1.0) -> Dictionary:
	var frac: float = float(cfg.get("repair", {}).get("cost_frac", 0.4)) \
			if frac_v < 0.0 else frac_v
	var out: Dictionary = {}
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			for key in d.get("cost", {}):
				out[key] = maxi(1, int(ceil(float(d["cost"][key]) * frac)))
			break
	return out


## Мгновенный ремонт за долю стоимости: чинит и повреждённое здание, и
## руины (поднимает, клетки снова преграждают путь). Доля героя — cost_frac
## (40%); город чинит сам — строитель за builder_frac, непрофильный житель
## за other_frac (v1.21.3). v1.50: free=true — «голыми руками» бригадой
## без ресурсов (ресурсы не списываются). "" — успех | "bad" | "full" | "no_res".
func repair_building(b: Dictionary, frac_v := -1.0, free := false) -> String:
	if b.is_empty() or not bool(b.get("done", false)):
		return "bad"
	var max_hp := float(_bld_max_hp(String(b["type"])))
	var was_razed := bool(b.get("razed", false))
	if not was_razed and float(b.get("hp", max_hp)) >= max_hp:
		return "full"   # чинить нечего
	var cost := repair_cost(String(b["type"]), frac_v)
	if not free:
		if not can_afford(cost):
			return "no_res"
		for key in cost:
			res[key] = int(res[key]) - int(cost[key])
	b["hp"] = max_hp
	if was_razed:
		b["razed"] = false
		if String(_def(b).get("effect", "")) == "gate":
			_gate_state.erase(str(int(b["id"])))   # состояние пересчитается на новом месте
			_update_gates()
		else:
			_set_bld_solid(b, true)   # стены (1×1) и капитальные — одинаково
			_step_off_bld(b)
		_spots_dirty()
	events.append({"type": "bld_repaired", "bld": String(b["type"]), "cost": cost,
			"razed": was_razed})
	_chron("chron.repaired", String(b["type"]))
	_assign_jobs()
	return ""


## Здание по id (v1.50: бригаде и поручению нужен обратный поиск).
func _building_by_id(bid: int) -> Dictionary:
	for b in buildings:
		if int(b["id"]) == bid:
			return b
	return {}


## Дневной бросок (v1.21.3 → v1.50 «Живая земля»): город чинит сам БРИГАДОЙ.
## Самое битое здание (сперва руины, затем минимум прочности) чинит бригада
## до brigade_size свободных горожан (сперва строители): собирается и
## работает ЦЕЛЫЙ день — need = day_length × доля бодрствования × day_frac.
## Ресурсы — из пула (доля стоимости builder_frac/other_frac); ресурсов НЕТ —
## «голыми руками» в no_res_mult раз дольше; брёвна из пула (срубленные
## деревья) ускоряют (расход logs_per_job wood при старте, ×log_speedup).
## Незаконченная работа продолжается и на следующий день.
func _roll_city_repair() -> void:
	var rcfg: Dictionary = cfg.get("repair", {})
	# вчерашняя бригада: если цель ещё битая — работает и сегодня
	if not brigade_job.is_empty():
		var prev: Dictionary = _building_by_id(int(brigade_job["bld"]))
		var prev_hp := float(_bld_max_hp(String(prev["type"]))) if not prev.is_empty() else 0.0
		if not prev.is_empty() and bool(prev.get("done", false)) \
				and (bool(prev.get("razed", false)) or float(prev.get("hp", prev_hp)) < prev_hp):
			return
		brigade_job = {}
	# цель: самое битое (сперва руины, затем минимум прочности)
	var worst: Dictionary = {}
	var worst_rank := 0.0
	for b in buildings:
		if not bool(b.get("done", false)):
			continue
		var max_hp := float(_bld_max_hp(String(b["type"])))
		var hp := float(b.get("hp", max_hp))
		if not bool(b.get("razed", false)) and hp >= max_hp:
			continue   # целое
		var rank := 0.0 if bool(b.get("razed", false)) else 1.0 + hp / maxf(1.0, max_hp)
		if worst.is_empty() or rank < worst_rank:
			worst = b
			worst_rank = rank
	if worst.is_empty():
		return
	# бригада: сперва СВОБОДНЫЕ строители, затем свободные непрофильные;
	# если город разорён и все при деле — работающий строитель уходит
	# с поста на починку руин (v1.52.2: раньше при занятых жителях бригада
	# не собиралась вовсе — «жители не чинят здания»)
	var members: Array = []
	var frac := float(rcfg.get("builder_frac", 0.5))
	for r in residents:
		if members.size() >= int(rcfg.get("brigade_size", 3)):
			break
		if String(r["prof"]) == "builder" and r["site"] == null and r["bld"] == null \
				and String(r.get("ail", "")) == "" and int(r.get("repair_bld", 0)) <= 0:
			members.append(r)
	if members.is_empty():
		frac = float(rcfg.get("other_frac", 0.7))
		for r in residents:
			if members.size() >= int(rcfg.get("brigade_size", 3)):
				break
			var prof := String(r["prof"])
			if prof != "" and prof != "elder" and prof != "builder" \
					and r["site"] == null and r["bld"] == null \
					and String(r.get("ail", "")) == "" and int(r.get("repair_bld", 0)) <= 0:
				members.append(r)
	if members.is_empty():
		# все при деле: руины важнее смены — строитель срывается с работы;
		# v1.59: строителей может не быть вовсе (город выгорел) — тогда с
		# поста срывается любой здоровый не-староста, иначе руины вечны
		for r in residents:
			if not members.is_empty():
				break
			if String(r.get("ail", "")) == "" and int(r.get("repair_bld", 0)) <= 0 \
					and not _is_golem(r) and String(r["prof"]) != "elder":
				r["site"] = null
				r["bld"] = null
				members.append(r)
	if members.is_empty():
		return
	# сроки: ЦЕЛЫЙ рабочий день (без ночи); модификаторы — ресурсы и брёвна
	var awake := maxf(0.3, 1.0 - float(cfg.get("night_fraction", 0.22)))
	# бригадный день: полная бригада (total).finishes за день; каждый тик dt
	var need := float(cfg["day_length"]) * awake * float(rcfg.get("day_frac", 1.0)) 			* maxf(1.0, float(members.size()))
	var has_res := can_afford(repair_cost(String(worst["type"]), frac))
	var use_logs := false
	if has_res:
		var logs_need := int(rcfg.get("logs_per_job", 4))
		if int(res.get("wood", 0)) >= logs_need and float(rcfg.get("log_speedup", 0.5)) < 1.0:
			use_logs = true
			res["wood"] = int(res["wood"]) - logs_need   # брёвна заготовлены
			need *= float(rcfg.get("log_speedup", 0.5))
	else:
		need *= float(rcfg.get("no_res_mult", 3.5))   # «голыми руками»
	brigade_job = {"bld": int(worst["id"]), "work": 0.0, "need": need,
			"frac": frac, "total": members.size(), "logs": use_logs}
	for r in members:
		r["repair_bld"] = int(worst["id"])
		r["repair_frac"] = frac


## Поручение города (v1.21.3 → v1.50): житель бригады идёт с инструментом
## к битому зданию и работает ЦЕЛЫЙ день: каждый пришедший добавляет
## dt/total (полная бригада укладывается в need). Как работа наберётся —
## здание чинится (ресурсы списывает repair_building; без ресурсов —
## «голыми руками», бесплатно). False — жителю поручения нет.
func _repair_errand(r: Dictionary, dt: float) -> bool:
	var bid := int(r.get("repair_bld", 0))
	if bid <= 0:
		return false
	var b: Dictionary = _building_by_id(bid)
	var max_hp := float(_bld_max_hp(String(b["type"]))) if not b.is_empty() else 0.0
	if brigade_job.is_empty() or int(brigade_job["bld"]) != bid or b.is_empty() \
			or not bool(b.get("done", false)) \
			or (not bool(b.get("razed", false)) and float(b.get("hp", max_hp)) >= max_hp):
		# исчезло или уже починили (герой/мастерская) — работу закрываем
		r["repair_bld"] = 0
		if not brigade_job.is_empty() and int(brigade_job["bld"]) == bid:
			brigade_job = {}
			for other in residents:
				if int(other.get("repair_bld", 0)) == bid:
					other["repair_bld"] = 0
		return false
	if not at_bld(r, b):
		r["state"] = "repair"
		_move_towards(r, bld_spot(b), dt)
		return true
	# работа у здания (v1.52.2: раньше dt делился на total — ПОЛНАЯ бригада
	# работала не быстрее одиночки, а без ресурсов ×3.5 не влезала в светлые
	# часы вовсе). Теперь: каждый пришедший вносит dt; need — бригадный день.
	r["state"] = "repair"
	brigade_job["work"] = float(brigade_job["work"]) + dt
	if float(brigade_job["work"]) < float(brigade_job["need"]):
		return true
	# день работы вышел — здание поднято
	var frac := float(brigade_job["frac"])
	var free := not can_afford(repair_cost(String(b["type"]), frac))
	repair_building(b, frac, free)
	if free:
		events.append({"type": "city_repaired_bare", "bld": String(b["type"]),
				"mult": float(cfg.get("repair", {}).get("no_res_mult", 3.5))})
	else:
		events.append({"type": "city_repaired", "bld": String(b["type"]),
				"name": String(r["name"]), "frac": frac})
	_chron("chron.city_repaired", String(r["name"]), String(b["type"]))
	brigade_job = {}
	for other in residents:
		if int(other.get("repair_bld", 0)) == bid:
			other["repair_bld"] = 0
	return true


## Ближайшее к герою готовое здание, которое можно чинить (повреждено или руины).
func hero_repair_near(px: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1.6 * float(map.ts) + float(map.ts) * 0.5   # как у стройплощадки
	for b in buildings:
		if not bool(b["done"]):
			continue
		var max_hp := float(_bld_max_hp(String(b["type"])))
		if not bool(b.get("razed", false)) and float(b.get("hp", max_hp)) >= max_hp:
			continue
		var d: float = bld_dist_px(px, b)
		if d <= best_d:
			best_d = d
			best = b
	return best


## E у повреждённого здания или руин: мгновенный ремонт за 40% стоимости.
## "" — рядом нечего чинить, иначе результат repair_building.
func hero_repair(px: Vector2) -> String:
	var b := hero_repair_near(px)
	if b.is_empty():
		return ""
	return repair_building(b)


## Годно ли новое место для переноса здания (правила — как при стройке;
## собственные клетки не мешают: здание их освободит) (этап 2, аспект 5).
func move_spot_ok(b: Dictionary, tile: Vector2i) -> bool:
	if b.is_empty() or not bool(b["done"]) or bool(b.get("razed", false)):
		return false
	if tile == Vector2i(b["tile"]):
		return true
	var type_id := String(b["type"])
	var w := bld_w(b)
	for dy in w:
		for dx in w:
			var cell := tile + Vector2i(dx, dy)
			if not map.in_bounds(cell) or cell == map.anomaly_tile:
				return false
			var ok_nature: bool = map.is_nature_walkable(cell) \
					or (type_id == "mine" and int(map.grid[cell.y][cell.x]) in [map.TILE_ORE, map.TILE_DEADROCK])
			if not ok_nature:
				return false
			var other := building_at(cell)
			if not other.is_empty() and int(other["id"]) != int(b["id"]):
				return false
			if map.bridges.has(cell):
				return false
			for g in graves:
				if Vector2i(g["tile"]) == cell:
					return false
	if placement_block(type_id, tile, true) != "":
		return false
	return placement_gap_ok(type_id, tile, int(b["id"]))


## Бесплатный перенос готового здания (этап 2, аспект 5): правила места те же,
## что при стройке; ресурсы не тратятся. "" — успех | "bad_bld" | "bad_spot".
func move_building(b: Dictionary, tile: Vector2i) -> String:
	if b.is_empty() or not bool(b["done"]) or bool(b.get("razed", false)):
		return "bad_bld"
	if tile == Vector2i(b["tile"]):
		return ""   # перенос на своё место — ничего не делаем
	if not move_spot_ok(b, tile):
		return "bad_spot"
	var effect := String(_def(b).get("effect", ""))
	var gate := effect == "gate"
	# старое место освобождается
	if gate:
		map.set_solid(Vector2i(b["tile"]), false)
		_gate_state.erase(str(int(b["id"])))   # применится к новому месту
	else:
		_set_bld_solid(b, false)
	# новое место: дороги и клетки зон уступают, клетки становятся сплошными
	var w := bld_w(b)
	for dy in w:
		for dx in w:
			var cell := tile + Vector2i(dx, dy)
			map.remove_road(cell)
			_drop_zone_cell(cell)
	b["tile"] = tile
	if gate:
		_update_gates()
	else:
		_set_bld_solid(b, true)
		_step_off_bld(b)
	_spots_dirty()
	events.append({"type": "bld_moved", "bld": String(b["type"])})
	_chron("chron.moved", String(b["type"]))
	return ""
