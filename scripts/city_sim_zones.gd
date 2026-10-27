# Часть: носильщик и кучи, зоны (поля ферм/пастбища), рост культур.
# Правки структуры v1.20.2: огромный city_sim.gd разбит на extends-цепочку
# частей; это один класс, разложенный по файлам — поведение не меняется.
extends "res://scripts/city_sim_gather.gd"

# --- носильщик и физический склад (M6, ответ №20) ---------------------------

## Носильщик: берёт готовую кучу у здания (>= chunk), несёт на склад —
## общий пул теперь физическое хранилище.
func _porter_work(r: Dictionary, dt: float) -> void:
	if float(r.get("carry", 0.0)) > 0.0:
		# склад — физическое хранилище; пока склада нет, носит к городскому амбару
		var barn := _nearest_done_of_type(r["pos"], "warehouse")
		var goal_tile: Vector2i = bld_spot(barn) if not barn.is_empty() else map.spawn_tile
		if _arrived(r, goal_tile):
			var key := String(r["carry_res"])
			# накопление без лимита (заказчик, 2026-10-25)
			var drop: float = float(r["carry"])
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
	if at_bld(r, target):   # подходит к входу здания (2×2 — тайл сплошной)
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


## Разбор готовых куч руками раз в день, когда носильщика в городе нет
## (v1.21, соло-экономика): доски с лесопилки и камень с каменоломни
## раньше гнили в кучах — самострой не мог платить за дома. Есть житель-
## носильщик — физическая логистика работает как прежде.
func _pull_idle_piles() -> void:
	for r in residents:
		if String(r["prof"]) == "porter":
			return
	var moved := 0
	for b in buildings:
		if not bool(b.get("done", false)) or not b.has("pile"):
			continue
		var pile: Dictionary = b["pile"]
		if pile.is_empty():
			continue
		for k in pile.keys():
			_add_resource_capped(String(k), float(pile[k]))
			moved += 1
		b["pile"] = {}
	if moved > 0:
		events.append({"type": "piles_hauled_hands", "n": moved})


# --- зоны (M6): поле, пастбище, жилая ----------------------------------------

## Разбить зону из клеток (сцена выделяет мышью). Возвращает число годных клеток.
func add_zone(type_id: String, cells: Array, crop := "turnip") -> int:
	var types: Dictionary = cfg.get("zones", {}).get("types", {})
	if not types.has(type_id):
		return 0
	var zone := {"id": _zone_id, "type": type_id, "cells": [], "progress": []}
	if type_id == "field":
		zone["crop"] = field_crop_id(crop)   # грядка засеивается целиком одной культурой
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
	static_dirty = true   # новая зона на земле — перевыпечь духовку (v1.22)
	return added


## Ид культуры поля из конфига (неизвестный — репа, фолбэк).
func field_crop_id(crop: String) -> String:
	var crops: Dictionary = cfg.get("farming", {}).get("crops", {})
	return crop if crops.has(crop) else ("turnip" if crops.has("turnip") else "")


## Определение культуры: темп созревания и еда за клетку (из data/city.json).
func crop_def(crop: String) -> Dictionary:
	var fcfg: Dictionary = cfg.get("farming", {})
	var cdef: Dictionary = fcfg.get("crops", {}).get(crop, {})
	if cdef.is_empty():
		return {"stage_days": float(fcfg.get("stage_days", 0.5)),
				"harvest": float(fcfg.get("harvest_food", 6.0)), "sprite": 0}
	return cdef


## Сезонная культура (v1.22): растёт только в свои сезоны (у репы и тыквы
## поля "seasons" нет — расти могут всегда). Зимой пшеница спит.
func crop_in_season(crop: String) -> bool:
	var seasons: Array = crop_def(crop).get("seasons", [])
	if seasons.is_empty():
		return true
	return season() in seasons


## Сменить культуру поля (DF-стиль): всё поле пересеивается заново.
## Возвращает true, если зона — поле и культура применена.
func set_field_crop(zone: Dictionary, crop: String) -> bool:
	if zone.is_empty() or String(zone["type"]) != "field":
		return false
	zone["crop"] = field_crop_id(crop)
	zone["crops"] = []   # старые посевы убраны — перезасеется само за семена
	events.append({"type": "crop_changed", "crop": String(zone["crop"])})
	return true


## Зона по id ({} — нет).
func zone_by_id(id: int) -> Dictionary:
	for z in zones:
		if int(z["id"]) == id:
			return z
	return {}


## Дикий зверь по id ({} — нет).
func _animal_by_id(animal_id: int) -> Dictionary:
	for a in animals:
		if int(a["id"]) == animal_id:
			return a
	return {}


## Готовое здание с кучей в шаге-двух от героя ({} — нет): героем по E куча
## уносится на склад в общий пул, как носильщик (2026-10-21: «не могу собирать
## с фермы еду» — в соло носильщика нет, еда застревала у фермы).
func hero_haul_near(px: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1.8 * float(map.ts) + float(map.ts) * 0.5
	for b in buildings:
		if not bool(b["done"]) or not (b as Dictionary).has("pile"):
			continue
		if _pile_total(b) < 0.5:
			continue
		var d: float = bld_dist_px(px, b)
		if d <= best_d:
			best_d = d
			best = b
	return best


## Унести кучу здания в общий пул (весь ворох разом). "" — кучи рядом нет,
## "haul" — принесено (детали — в событии hero_haul).
func hero_haul(px: Vector2) -> String:
	var b: Dictionary = hero_haul_near(px)
	if b.is_empty():
		return ""
	var pile: Dictionary = b["pile"]
	var total := 0.0
	var key := ""
	var best := 0.0
	for k in pile:
		var n := float(pile[k])
		_add_resource_capped(String(k), n)
		total += n
		if n > best:
			best = n
			key = String(k)
	b.erase("pile")
	events.append({"type": "hero_haul", "res": key, "n": int(round(total))})
	return "haul"


## Зона-поле, в которую попадает тайл ({} — нет).
func field_at(t: Vector2i) -> Dictionary:
	for z in zones:
		if String(z["type"]) != "field":
			continue
		for i in (z["cells"] as Array).size():
			if Vector2i(z["cells"][i]) == t and bool(_cell_filled(z, i)) \
					and building_at(t).is_empty():
				return z
	return {}


## Любая зона, в которую попадает тайл ({} — нет) — для подписи при наведении.
func zone_at(t: Vector2i) -> Dictionary:
	for z in zones:
		if (z["cells"] as Array).has(t):
			return z
	return {}


## Статистика поля для подписи: {filled, total, sown, ripe}.
func field_stats(z: Dictionary) -> Dictionary:
	var fill_work: float = float(cfg.get("zones", {}).get("fill_work", 4.0))
	var filled := 0
	var sown := 0
	var ripe := 0
	var crops: Array = z.get("crops", [])
	for i in (z["cells"] as Array).size():
		if float((z["progress"] as Array)[i]) >= fill_work \
				and building_at(z["cells"][i]).is_empty():
			filled += 1
			if crops.size() > i:
				if not (crops[i] is Dictionary):
					crops[i] = {}
				var c: Dictionary = crops[i]
				if not c.is_empty():
					sown += 1
					if bool(c.get("ripe", false)):
						ripe += 1
	return {"filled": filled, "total": (z["cells"] as Array).size(),
			"sown": sown, "ripe": ripe}


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


# --- зоны: только Поле и Пастбище (правки v1.20: слои и кварталы убраны) -----


## Усиление храма: благословение сильнее при служке (зоны-кварталы убраны, v1.20).
func _temple_work_mult() -> float:
	return 1.0


## Благословение храма (M14-H).
func blessing_boost() -> float:
	if not has_blessing():
		return 1.0
	return float(cfg.get("altar_boost", 1.0))


## Усиление алтаря (реген маны героя) — базовое (магзоны убраны, v1.20).
func _altar_work_mult() -> float:
	return 1.0


## Порча городской магии — базовая (магзоны убраны, v1.20).
func _magic_pollution_mult() -> float:
	return 1.0


## Свободный житель обустраивает ближайшую незаполненную клетку зоны;
## спелые грядки полей собирает (этап 2, аспект 3). False — зон нет.
## Правка v1.21 (голем-староста «менял цель очень быстро»): начатая клетка
## доводится до конца — спелые грядки и новые «ближние» цели её не перебивают.
func _zone_fill_work(r: Dictionary, dt: float) -> bool:
	var sticky: Dictionary = _zone_fill_sticky(r)
	if not sticky.is_empty():
		_zone_fill_do(r, sticky, dt)
		return true
	var ripe := _nearest_ripe_field_cell(r)
	if not ripe.is_empty():
		var rt: Vector2i = ripe["tile"]
		if _arrived(r, rt):
			_harvest_cell(ripe["zone"], int(ripe["idx"]))
			r["state"] = "harvest"
			r["fatigue"] += dt / float(cfg["day_length"])
		else:
			_move_towards(r, rt, dt)
		return true
	if zones.is_empty():
		return false
	var target := _nearest_zone_cell(r)
	if target.is_empty():
		return false
	r["_fill_zone"] = int((target["zone"] as Dictionary)["id"])
	r["_fill_idx"] = int(target["idx"])
	_zone_fill_do(r, target, dt)
	return true


## Липкая цель обустройства: начатая клетка, пока она не заполнена.
func _zone_fill_sticky(r: Dictionary) -> Dictionary:
	var sticky_z: Dictionary = zone_by_id(int(r.get("_fill_zone", -1)))
	if sticky_z.is_empty():
		return {}
	var si := int(r.get("_fill_idx", -1))
	if si < 0 or si >= (sticky_z["cells"] as Array).size():
		return {}
	if _cell_filled(sticky_z, si) or not building_at(sticky_z["cells"][si]).is_empty():
		return {}
	return {"zone": sticky_z, "idx": si, "tile": sticky_z["cells"][si]}


## Шаг обустройства клетки зоны (дойти → копить прогресс → закрыть клетку).
## v1.23: обустройство полей — крестьянское дело, растит «фермера».
func _zone_fill_do(r: Dictionary, target: Dictionary, dt: float) -> void:
	var tile: Vector2i = target["tile"]
	if _arrived(r, tile):
		r["state"] = "fill"
		var z: Dictionary = target["zone"]
		var i: int = int(target["idx"])
		z["progress"][i] = float(z["progress"][i]) + dt * work_mult(r)
		r["fatigue"] += dt / float(cfg["day_length"]) * _fatigue_cost(r)
		var kind := "farmer" if String(z["type"]) == "field" else "porter"
		_grow_skill(r, dt, kind)
		if _cell_filled(z, i):
			r["_fill_zone"] = -1
			r["_fill_idx"] = -1
			events.append({"type": "zone_cell", "zone": String(z["type"])})
			static_dirty = true   # клетка обустроена — заливка плотнее (v1.22)
			_zone_check_done(z, r)
	else:
		_move_towards(r, tile, dt)


## Ближайшая незаполненная клетка зоны: {zone, idx, tile} или {}.
func _nearest_zone_cell(r: Dictionary) -> Dictionary:
	# липкая цель (правки v1.20.1): начатую клетку доводим до конца —
	# даже если рядом появилась «поближе», мечтаться между клетками нельзя
	var sticky_z: Dictionary = zone_by_id(int(r.get("_fill_zone", -1)))
	if not sticky_z.is_empty():
		var si := int(r.get("_fill_idx", -1))
		if si >= 0 and si < (sticky_z["cells"] as Array).size() \
				and not _cell_filled(sticky_z, si) \
				and building_at(sticky_z["cells"][si]).is_empty():
			return {"zone": sticky_z, "idx": si, "tile": sticky_z["cells"][si]}
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
	if not best.is_empty():
		r["_fill_zone"] = int((best["zone"] as Dictionary)["id"])
		r["_fill_idx"] = int(best["idx"])
	else:
		r["_fill_zone"] = -1
		r["_fill_idx"] = -1
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
	if not who.is_empty():
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
		# посевы по клеткам (M10); культура поля — этап 2, аспект 3:
		# вся грядка одной культурой, темп и урожай — из data/city.json
		if not (z as Dictionary).has("crops"):
			z["crops"] = []
		var cdef: Dictionary = crop_def(String(z.get("crop", "turnip")))
		var crop_stage_days := maxf(0.1, float(cdef.get("stage_days", fcfg.get("stage_days", 0.5))))
		var crop_harvest := float(cdef.get("harvest", fcfg.get("harvest_food", 6.0)))
		var crops: Array = z["crops"]
		var crop_id := String(z.get("crop", "turnip"))
		var in_season := crop_in_season(crop_id)
		for i in (z["cells"] as Array).size():
			if not _cell_filled(z, i) or not building_at(z["cells"][i]).is_empty():
				continue
			while crops.size() <= i:
				crops.append({})
			# v1.28: старые сейвы могли оставить null-дыры в посевах — чиним
			if not (crops[i] is Dictionary):
				crops[i] = {}
			var crop: Dictionary = crops[i]
			if crop.is_empty():
				# пусто: сеем, если есть семя (v1.22: сезонная культура вне
				# своего сезона не сеется — семена не переводятся)
				if in_season and float(res.get("seeds", 0.0)) >= float(fcfg.get("seed_sow", 1)):
					res["seeds"] = float(res["seeds"]) - float(fcfg.get("seed_sow", 1))
					crops[i] = {"stage": 0, "t": 0.0, "ripe": false}
			elif not bool(crop.get("ripe", false)):
				# рост В ДНЯХ (правки v1.20.1: раньше t копил секунды и сравнивался
				# с днями — культура «зрела» за секунды, роста не видно).
				# v1.22: сезонная культура зимой СПИТ — не гибнет, просто ждёт
				# весны (посев стоит, рост продолжится в тёплый сезон)
				if in_season:
					crop["t"] = float(crop.get("t", 0.0)) + dt / maxf(1.0, day_len)
					if float(crop["t"]) >= crop_stage_days:
						crop["t"] = 0.0
						crop["stage"] = int(crop.get("stage", 0)) + 1
						if int(crop["stage"]) >= stages:
							crop["ripe"] = true
				# спелая грядка ЖДЁТ сборщика (этап 2, аспект 3): фермер обходит
			# поле и собирает, герой — по E. Автосбора больше нет.


## Сбор спелой клетки поля (фермер и герой): еда в общий пул, семя
## возвращается (с бонусным шансом), клетка пересеивается той же культурой
## за обычное семя; без семян клетка пустует.
func _harvest_cell(zone: Dictionary, idx: int) -> void:
	var cdef: Dictionary = crop_def(String(zone.get("crop", "turnip")))
	var fcfg: Dictionary = cfg.get("farming", {})
	_add_resource_capped("food", float(cdef.get("harvest", fcfg.get("harvest_food", 6.0))) * crop_mult())
	_add_resource_capped("seeds", float(fcfg.get("seed_return", 1)))
	if _event_rng.randf() < float(fcfg.get("seed_bonus_chance", 0.15)):
		_add_resource_capped("seeds", 1.0)
	var crops: Array = zone["crops"]
	if float(res.get("seeds", 0.0)) >= float(fcfg.get("seed_sow", 1)):
		res["seeds"] = float(res["seeds"]) - float(fcfg.get("seed_sow", 1))
		crops[idx] = {"stage": 0, "t": 0.0, "ripe": false}
	else:
		crops[idx] = {}


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
	var products: Dictionary = lcfg.get("products", {})
	var no_breed: Array = lcfg.get("no_breed", ["pig"])
	var total_food := 0.0
	for z in zones:
		if String(z["type"]) != "pasture":
			continue
		var cap := pasture_capacity(z)
		if cap <= 0:
			continue
		var pid := int(z["id"])
		var count := _livestock_in(pid)
		# ловля: житель отправляется за диким зверем и тащит его на пастбище
		# (этап 2: не телепорт, а работа жителя; один носильщик за раз)
		if count < cap and not animals.is_empty() and tame_task.is_empty() \
				and _event_rng.randf() < float(lcfg.get("tame_chance", 0.5)):
			var carrier: Dictionary = _free_tamer()
			if not carrier.is_empty():
				var wild: Dictionary = animals[_event_rng.randi_range(0, animals.size() - 1)]
				tame_task = {"animal": int(wild["id"]), "pasture": pid,
						"carrier": int(carrier["id"]), "phase": "to_animal"}
				events.append({"type": "tame_sent", "name": String(carrier["name"])})
		# приплод: пара взрослых ОДНОГО вида; свиньи не размножаются (заказчик)
		var by_kind := {}
		for a in livestock:
			if int(a["pasture"]) != pid or not bool(a["adult"]):
				continue
			var k := String(a["kind"])
			by_kind[k] = int(by_kind.get(k, 0)) + 1
		for k in by_kind:
			if k in no_breed or int(by_kind[k]) < 2 or count >= cap:
				continue
			if _event_rng.randf() < float(lcfg.get("breed_chance", 0.25)):
				var baby: String = "chick" if k == "chicken" else k
				livestock.append({"id": _livestock_id, "kind": baby, "pasture": pid,
						"pos": map.tile_center_px(z["cells"][0]), "target": Vector2i.ZERO,
						"path": PackedVector2Array(), "idle": 0.0, "adult": false, "age": 0.0})
				_livestock_id += 1
				count += 1
				events.append({"type": "livestock_born", "kind": baby})
				_chron("chron.livestock_born", baby)
			break   # один приплод в день на пастбище
		# свиньи: не размножаются, лишние (сверх одной) идут на мясо
		var pigs := 0
		var oldest := {}
		for a in livestock:
			if int(a["pasture"]) != pid or String(a["kind"]) != "pig":
				continue
			pigs += 1
			if oldest.is_empty() or int(a["id"]) < int(oldest["id"]):
				oldest = a
		if pigs > int(lcfg.get("pig_excess", 1)):
			livestock.erase(oldest)
			var meat := float(lcfg.get("pig_meat", 10.0))
			_add_resource_capped("food", meat)
			events.append({"type": "pig_slaughtered", "food": int(meat)})
			_chron("chron.pig_meat")
		# продукция по видам: корова — молоко, птица — яйца, овца — руно в еду;
		# свинья еды не даёт (её продукт — мясо при убое)
		for k in by_kind:
			total_food += float(by_kind[k]) * float(products.get(k, lcfg.get("food_per_adult", 1.2)))
	if total_food >= 1.0:
		_add_resource_capped("food", total_food)
		events.append({"type": "livestock_food", "food": int(total_food)})


## Свободный житель для ловли зверя: без работы, не староста/страж/носильщик.
func _free_tamer() -> Dictionary:
	for r in residents:
		if String(r["prof"]) in ["", "elder", "guard", "porter", "hunter"] or String(r.get("ail", "")) != "":
			continue
		if r["bld"] != null or r["site"] != null or int(r.get("funeral", 0)) > 0:
			continue
		return r
	return {}




func _tame_work(r: Dictionary, dt: float) -> bool:
	if tame_task.is_empty() or int(tame_task["carrier"]) != int(r["id"]):
		return false
	var wild := _animal_by_id(int(tame_task["animal"]))
	var pasture := _pasture_by_id(int(tame_task["pasture"]))
	if wild.is_empty() or pasture.is_empty() or (pasture["cells"] as Array).is_empty():
		tame_task = {}
		return false
	if (pasture["cells"] as Array).size() <= _livestock_in(int(pasture["id"])):
		tame_task = {}   # пастбище забито — зверь остался на воле
		return false
	if String(tame_task["phase"]) == "to_animal":
		var at: Vector2i = map.nearest_walkable(map.tile_of_px(wild["pos"]))
		if _arrived(r, at):
			animals.erase(wild)
			tame_task["phase"] = "to_pasture"
			return true
		_move_towards(r, at, dt)
		return true
	var goal: Vector2i = map.nearest_walkable(Vector2i(pasture["cells"][0]))
	if _arrived(r, goal):
		var wild_kind := String(wild.get("kind", "deer"))
		var kind: String = {"boar": "pig", "bird": "chicken", "turkey": "chicken", "deer": "sheep"}.get(wild_kind, "cow")
		livestock.append({"id": _livestock_id, "kind": kind, "pasture": int(pasture["id"]),
				"pos": map.tile_center_px(Vector2i(pasture["cells"][0])), "target": Vector2i.ZERO,
				"path": PackedVector2Array(), "idle": 0.0, "adult": true, "age": 99.0})
		_livestock_id += 1
		events.append({"type": "livestock_tame", "kind": kind})
		_chron("chron.livestock_tame", kind)
		tame_task = {}
		return false
	_move_towards(r, goal, dt)
	return true


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


