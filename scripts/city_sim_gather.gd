# Часть: добыча у источников (правки v1.21) — лесопилка, каменоломня, шахта.
# Лесоруб ВАЛИТ дерево (малое/среднее/большое), готовит бревно, тащит на
# лесопилку и пилит доски; шахтёр добывает сырой камень у гряды и несёт на
# каменоломню — переработка даёт стройкамень и с шансом железо/самоцветы/
# кристалл; выработанная гряда остаётся пустой породой, туда ставится шахта.
extends "res://scripts/city_sim_tick.gd"


## Единый вход добытчиков (из _update_resident): маршрутизация по типу здания.
func _gather_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		r["state"] = "idle"
		return
	match String(bld["type"]):
		"sawmill":
			_sawmill_work(r, bld, dt)
		"quarry":
			_quarry_work(r, bld, dt)
		"mine":
			_mine_work(r, bld, dt)
		_:
			r["state"] = "idle"


# --- лесопилка ---------------------------------------------------------------

## Цикл лесоруба: посадка саженцев → дерево → рубка → подготовка бревна →
## переноска на лесопилку (большое тащить тяжелее) → распилка в доски.
## v1.23: сперва распиливается ворох брёвен, принесённый прохожими;
## поваленные брёвна лесоруб собирает по всей карте — лесопилка не держит
## радиуса поиска деревьев. Деревьев нет — лесоруб стоит у лесопилки.
func _sawmill_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	var day_len := float(cfg["day_length"])
	# саженцы из пула — лес подрастёт (посадка лес успокаивает, v1.21)
	if _sawmill_plant(r, bld, dt):
		return
	# несём бревно: дотащить до лесопилки и распилить
	if int(r.get("log_size", 0)) > 0:
		if not at_bld(r, bld):
			r["state"] = "porter"
			_move_towards(r, bld_spot(bld), dt)
			return
		var fcfg: Dictionary = cfg.get("forest", {})
		var need_saw: float = float(fcfg.get("saw_days", 0.1)) * day_len
		r["saw_t"] = float(r.get("saw_t", 0.0)) + dt * work_mult(r)
		r["fatigue"] += dt / day_len * _fatigue_cost(r)
		_grow_skill(r, dt)
		if float(r["saw_t"]) < need_saw:
			r["state"] = "saw"
			return
		var size := int(r["log_size"])
		var planks: float = _planks_for(size) * blessing_boost() * production_mult(bld)
		_add_resource_capped("wood", planks)   # v1.25: сразу в общий пул — без кучи
		forest_anger = clampf(forest_anger + float(fcfg.get("anger_per_sawing", 0.5)), 0.0, 100.0)
		events.append({"type": "tree_sawed", "planks": int(planks)})
		_chron("chron.tree_sawed", str(int(planks)))
		r["log_size"] = 0
		r["saw_t"] = 0.0
		r["carry_slow"] = 1.0
		return
	# ворох брёвен у лесопилки (принесли прохожие, v1.23) — пилим на месте
	if not (bld.get("pending_logs", []) as Array).is_empty():
		if not at_bld(r, bld):
			r["state"] = "porter"
			_move_towards(r, bld_spot(bld), dt)
			return
		var fcfg2: Dictionary = cfg.get("forest", {})
		var need_saw2: float = float(fcfg2.get("saw_days", 0.1)) * day_len
		r["saw_t"] = float(r.get("saw_t", 0.0)) + dt * work_mult(r)
		r["fatigue"] += dt / day_len * _fatigue_cost(r)
		_grow_skill(r, dt)
		if float(r["saw_t"]) < need_saw2:
			r["state"] = "saw"
			return
		var sizes: Array = bld["pending_logs"]
		var psize := int(sizes.pop_front())
		var planks2: float = _planks_for(psize) * blessing_boost() * production_mult(bld)
		_add_resource_capped("wood", planks2)
		forest_anger = clampf(forest_anger + float(fcfg2.get("anger_per_sawing", 0.5)), 0.0, 100.0)
		events.append({"type": "tree_sawed", "planks": int(planks2)})
		_chron("chron.tree_sawed", str(int(planks2)))
		r["saw_t"] = 0.0
		return
	# готовим поваленное бревно к переноске (закрепляем, обрубаем сучья)
	if float(r.get("prep_left", 0.0)) > 0.0:
		r["prep_left"] = maxf(0.0, float(r["prep_left"]) - dt * work_mult(r))
		r["state"] = "prep"
		r["fatigue"] += dt / day_len * _fatigue_cost(r)
		_grow_skill(r, dt)
		if float(r["prep_left"]) <= 0.0:
			r["log_size"] = int(r.get("fell_size", map.TREE_SMALL))
			r["carry_slow"] = _log_carry_slow(r, int(r["log_size"]))
		return
	# бревно на земле (валка героя, v1.21.2) — подбираем: рубить не надо
	var log_t := _log_target(r, bld)
	if log_t != Vector2i(-1, -1):
		if map.tile_of_px(r["pos"]) != log_t:
			_move_towards(r, log_t, dt)
			return
		var lsize: int = int((map.logs[log_t] as Dictionary).get("size", map.TREE_SMALL))
		map.logs.erase(log_t)
		r["log_size"] = lsize
		r["fell_size"] = lsize
		r["carry_slow"] = _log_carry_slow(r, lsize)
		r["gath_tile"] = Vector2i(-1, -1)
		return
	# ищем дерево в радиусе сбора от лесопилки
	var res_tile: Vector2i = _gather_target(r, bld)
	if res_tile == Vector2i(-1, -1):
		r["state"] = "idle"
		return
	if map.tile_of_px(r["pos"]) != res_tile:
		_move_towards(r, res_tile, dt)
		return
	_chop_tree(r, dt)


## Ноша бревна размера size (v1.23): большое тяжелее, сильный тащит бодрее.
func _log_carry_slow(r: Dictionary, size: int) -> float:
	var slow := _carry_mult(size) * (1.0 - float(cfg.get("attributes", {}).get("str_carry", 0.05)) * _stat(r, "str"))
	return clampf(slow, 0.3, 1.0)


## Досок с дерева размера size (1/2/3 — малое/среднее/большое).
func _planks_for(size: int) -> float:
	var table: Dictionary = cfg.get("forest", {}).get("planks_per_tree", {})
	var key := "small" if size == map.TREE_SMALL else ("medium" if size == map.TREE_MEDIUM else "large")
	return float(table.get(key, 10.0))


## Замедление переноски бревна размера size (большое тащить труднее).
func _carry_mult(size: int) -> float:
	var table: Dictionary = cfg.get("forest", {}).get("carry_mult", {})
	var key := "small" if size == map.TREE_SMALL else ("medium" if size == map.TREE_MEDIUM else "large")
	return float(table.get(key, 1.0))


## Посадка саженцев у лесопилки: житель носит саженцы из пула (выпадают из
## срубленных деревьев) и сажает лес вокруг — будущие доски и минус гнев.
func _sawmill_plant(r: Dictionary, bld: Dictionary, dt: float) -> bool:
	var fcfg: Dictionary = cfg.get("forest", {})
	var per_day := int(fcfg.get("plant_per_day", 2))
	if int(r.get("plant_day", 0)) != day:
		r["plant_day"] = day
		r["plant_n"] = 0
	if int(r.get("plant_n", 0)) >= per_day or float(res.get("saplings", 0.0)) < 1.0:
		return false
	var tile: Vector2i = r.get("plant_tile", Vector2i(-1, -1))
	if tile == Vector2i(-1, -1):
		tile = _plant_tile_near(bld)
		if tile == Vector2i(-1, -1):
			return false   # места нет — просто работаем
		r["plant_tile"] = tile
	if not _arrived(r, tile):
		_move_towards(r, tile, dt)
		return true
	res["saplings"] = float(res["saplings"]) - 1.0
	map.saplings[tile] = {"t": 0.0, "grow_days": float(fcfg.get("grow_days", 5.0))}
	terrain_dirty = true
	r["plant_n"] = int(r.get("plant_n", 0)) + 1
	r["plant_tile"] = Vector2i(-1, -1)
	r["state"] = "fill"
	_chron("chron.sapling_planted", String(r["name"]))
	events.append({"type": "sapling_planted", "name": String(r["name"])})
	return false


## Свободная трава у здания под саженец: без зданий, пней, саженцев, зон
## и запретного радиуса площади.
func _plant_tile_near(bld: Dictionary) -> Vector2i:
	var fcfg: Dictionary = cfg.get("forest", {})
	var radius := int(fcfg.get("plant_radius", 5))
	var bc: Vector2i = bld["tile"]
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t: Vector2i = bc + Vector2i(dx, dy)
			if not map.in_bounds(t) or map.grid[t.y][t.x] != map.TILE_GRASS:
				continue
			if map.saplings.has(t) or map.stumps.has(t) or map.logs.has(t) or not map.is_walkable(t):
				continue
			if near_plaza(t) or not building_at(t).is_empty() or _tile_in_fill_zone(t):
				continue
			var d: float = Vector2(t).distance_to(Vector2(bc))
			if d < best_d:
				best_d = d
				best = t
	return best


## Срубленное дерево с шансом роняет саженцы в общий пул (кто бы ни рубил).
func _drop_saplings() -> void:
	var fcfg: Dictionary = cfg.get("forest", {})
	if _event_rng.randf() >= float(fcfg.get("sapling_drop_chance", 0.5)):
		return
	var n := _event_rng.randi_range(int(fcfg.get("sapling_drop_min", 1)), int(fcfg.get("sapling_drop_max", 2)))
	_add_resource_capped("saplings", float(n))
	events.append({"type": "saplings_dropped", "n": n})


## Рубка: копим chop_days ПО РАЗМЕРУ дерева, валим — пень, гнев леса +1,
## саженцы в пул; дальше житель готовит бревно к переноске.
func _chop_tree(r: Dictionary, dt: float) -> void:
	var tile: Vector2i = map.tile_of_px(r["pos"])
	if map.grid[tile.y][tile.x] != map.TILE_TREE:
		r["chop_t"] = 0.0
		return
	var fcfg: Dictionary = cfg.get("forest", {})
	var size: int = map.tree_kind(tile)
	var need := _chop_days_for(size) * float(cfg["day_length"])
	r["chop_t"] = float(r.get("chop_t", 0.0)) + dt * work_mult(r)
	r["state"] = "chop"
	r["fatigue"] += dt / float(cfg["day_length"]) * _fatigue_cost(r)
	_grow_skill(r, dt)
	if float(r["chop_t"]) < need:
		return
	r["chop_t"] = 0.0
	map.grid[tile.y][tile.x] = map.TILE_GRASS
	map.stumps[tile] = true
	map.tree_size.erase(tile)
	map.tree_growth.erase(tile)
	terrain_dirty = true
	forest_anger = clampf(forest_anger + float(fcfg.get("anger_per_tree", 1.0)), 0.0, 100.0)
	_drop_saplings()   # из поваленного дерева выпадают саженцы
	events.append({"type": "tree_felled"})
	_chron("chron.tree_felled")
	r["fell_size"] = size
	r["prep_left"] = float(fcfg.get("prep_days", 0.1)) * float(cfg["day_length"])
	r["gath_tile"] = Vector2i(-1, -1)


## Сколько дней валить дерево размера size.
func _chop_days_for(size: int) -> float:
	var table: Dictionary = cfg.get("forest", {}).get("chop_days", {})
	var key := "small" if size == map.TREE_SMALL else ("medium" if size == map.TREE_MEDIUM else "large")
	return float(table.get(key, 0.75))


## Тайл дерева, у которого работает лесоруб: ближайший к лесопилке в радиусе
## сбора. Кэшируется на жителе (липкая цель).
func _gather_target(r: Dictionary, bld: Dictionary) -> Vector2i:
	var cached: Vector2i = r.get("gath_tile", Vector2i(-1, -1))
	if cached != Vector2i(-1, -1) and map.in_bounds(cached) and map.is_walkable(cached) \
			and cached != (bld["tile"] as Vector2i) \
			and map.grid[cached.y][cached.x] == map.TILE_TREE:
		return cached
	var radius := int(cfg.get("gather_range", 6))
	var best := Vector2i(-1, -1)
	var best_d := INF
	var bc: Vector2i = bld["tile"]
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t: Vector2i = bc + Vector2i(dx, dy)
			if not map.in_bounds(t) or t == bc:
				continue
			if map.grid[t.y][t.x] != map.TILE_TREE:
				continue
			var d: float = Vector2(t).distance_to(Vector2(bc))
			if d < best_d:
				best_d = d
				best = t
	r["gath_tile"] = best
	return best


## Бревно на земле (v1.23: лесопилка больше не держит радиуса поиска —
## лесоруб идёт за любым поваленным деревьем на карте). Ближайшее к лесорубу,
## не разобранное другим носильщиком.
func _log_target(r: Dictionary, bld: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for t: Vector2i in map.logs.keys():
		var claim := int((map.logs[t] as Dictionary).get("claim", -1))
		if claim >= 0 and claim != int(r["id"]):
			var stale := time - float((map.logs[t] as Dictionary).get("claim_t", 0.0)) \
					> float(cfg.get("logs", {}).get("claim_stale", 60.0))
			if not stale:
				continue   # бревно уже несёт прохожий
		var d: float = Vector2(t).distance_to(Vector2(r["pos"]))
		if d < best_d:
			best_d = d
			best = t
	return best


# --- вывоз поваленных деревьев прохожими (v1.23) -------------------------------

## Прохожий рядом с бревном: свободные руки — подберёт и отнесёт на лесопилку,
## даже если рубил не он и бревно далеко от лесопилки (просьба заказчика).
func _try_haul_log(r: Dictionary, dt: float) -> bool:
	var lcfg: Dictionary = cfg.get("logs", {})
	if lcfg.is_empty() or map.logs.is_empty():
		return false
	if float(r.get("log_haul_cd", 0.0)) > time:
		return false
	# руки заняты — не отвлекаем
	if int(r.get("log_size", 0)) > 0 or float(r.get("carry", 0.0)) > 0.0 \
			or float(r.get("raw", 0.0)) > 0.0 or float(r.get("carry_iron", 0.0)) > 0.0 \
			or float(r.get("carry_stone", 0.0)) > 0.0 \
			or not (r.get("corpse_task", {}) as Dictionary).is_empty():
		return false
	var st := String(r["state"])
	if not (st in ["idle", "going", "leisure", "chat"]):
		return false
	# лесопилки нет — бревну пока некуда идти
	if _nearest_done_of_type(r["pos"], "sawmill").is_empty():
		return false
	r["log_haul_cd"] = time + float(lcfg.get("check_every", 2.0))
	var radius := float(lcfg.get("passer_radius", 3)) * float(map.ts)
	var best := Vector2i(-1, -1)
	var best_d := INF
	for t: Vector2i in map.logs.keys():
		var claim := int((map.logs[t] as Dictionary).get("claim", -1))
		if claim >= 0 and claim != int(r["id"]) \
				and time - float((map.logs[t] as Dictionary).get("claim_t", 0.0)) \
				< float(lcfg.get("claim_stale", 60.0)):
			continue
		var d: float = map.tile_center_px(t).distance_to(r["pos"])
		if d <= radius and d < best_d:
			best_d = d
			best = t
	if best == Vector2i(-1, -1):
		return false
	map.logs[best]["claim"] = int(r["id"])
	map.logs[best]["claim_t"] = time
	r["haul_log_tile"] = best
	r["haul_log"] = true
	return _log_haul_work(r, dt)


## Ноша бревна прохожим: дойти → поднять → дотащить до лесопилки и сдать
## в ворох (лесоруб распилит на месте).
func _log_haul_work(r: Dictionary, dt: float) -> bool:
	if r.has("haul_log_tile"):
		var tile: Vector2i = r["haul_log_tile"]
		var ld: Dictionary = map.logs.get(tile, {})
		if ld.is_empty() or not map.is_walkable(tile):
			r.erase("haul_log_tile")   # бревно забрали / замуровали
			r["haul_log"] = false
			return false
		if not _arrived(r, tile):
			_move_towards(r, tile, dt)
			return true
		var size := int(ld.get("size", 1))
		map.logs.erase(tile)
		r["log_size"] = size
		r["fell_size"] = size
		r["carry_slow"] = _log_carry_slow(r, size)
		r.erase("haul_log_tile")
		_grow_skill(r, dt, "porter")
		return true
	# несём на ближайшую лесопилку
	var mill := _nearest_done_of_type(r["pos"], "sawmill")
	if mill.is_empty():
		_drop_carried_log(r)   # лесопилку снесли — бревно обратно на землю
		return false
	if not at_bld(r, mill):
		r["state"] = "porter"
		_move_towards(r, bld_spot(mill), dt)
		return true
	if not mill.has("pending_logs"):
		mill["pending_logs"] = []
	if int(r.get("log_size", 0)) > 0:
		(mill["pending_logs"] as Array).append(int(r["log_size"]))
		events.append({"type": "log_hauled", "name": String(r["name"]),
				"size": int(r["log_size"])})
	r["log_size"] = 0
	r["carry_slow"] = 1.0
	r["haul_log"] = false
	r["log_haul_cd"] = time + 20.0   # передышка после ходки
	return false


## Бросить несомое бревно на землю (лесопилка пропала).
func _drop_carried_log(r: Dictionary) -> void:
	var size := int(r.get("log_size", 0))
	if size <= 0:
		r["haul_log"] = false
		return
	var drop: Vector2i = map.nearest_walkable(map.tile_of_px(r["pos"]))
	if drop != Vector2i(-1, -1) and not map.logs.has(drop):
		map.logs[drop] = {"size": size}
	r["log_size"] = 0
	r["carry_slow"] = 1.0
	r["haul_log"] = false


# --- каменоломня ---------------------------------------------------------------

## Цикл шахтёра у каменоломни: добыть сырой камень у гряды (тайл истощается),
## унести на каменоломню, переработать в стройкамень; переработка с шансом
## даёт железо, самоцветы и куски мано-кристалла.
func _quarry_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	var day_len := float(cfg["day_length"])
	var mcfg: Dictionary = cfg.get("mountain", {})
	var cap: float = float(mcfg.get("carry_raw", 8.0))
	# гряда в радиусе сбора (липкая цель)
	var pair: Dictionary = _rock_target(r, bld)
	# несём сырой камень на каменоломню — когда руки полны или гряда кончилась
	if float(r.get("raw", 0.0)) > 0.0 and (pair.is_empty() or float(r["raw"]) >= cap):
		if not at_bld(r, bld):
			r["state"] = "porter"
			_move_towards(r, bld_spot(bld), dt)
			return
		var raw := float(r["raw"])
		_add_resource_capped("stone", raw * blessing_boost() * production_mult(bld))
		_roll_quarry_bonus(bld)
		events.append({"type": "quarry_processed", "stone": int(raw)})
		r["raw"] = 0.0
		r["carry_slow"] = 1.0
		return
	if pair.is_empty():
		r["state"] = "idle"
		return
	var stand: Vector2i = pair["stand"]
	var tile: Vector2i = pair["rock"]
	if map.tile_of_px(r["pos"]) != stand:
		_move_towards(r, stand, dt)
		return
	# добываем: тайл теряет прочность, сырой камень — в руки
	var max_hp := _rock_max_hp(tile)
	var hp := float(map.rock_hp.get(tile, max_hp))
	var drained: float = minf(hp, float(mcfg.get("rate", 55.0)) * dt / day_len * work_mult(r))
	hp -= drained
	r["raw"] = minf(cap, float(r.get("raw", 0.0))
			+ drained / maxf(1.0, max_hp) * float(mcfg.get("raw_per_tile", 10.0)))
	r["state"] = "work"
	r["fatigue"] += dt / day_len * _fatigue_cost(r)
	_grow_skill(r, dt)
	if float(r["raw"]) >= cap:
		r["carry_slow"] = float(mcfg.get("carry_slow", 0.8))
		r["gath_tile"] = Vector2i(-1, -1)
		r["gath_res"] = Vector2i(-1, -1)
		return
	if hp > 0.0:
		map.rock_hp[tile] = hp
		return
	# тайл выработан: жила или пустая порода (скала больше не исчезает, v1.21)
	_exhaust_rock_tile(tile, r)


## Переработка сырого камня: с небольшим шансом железо, самоцветы, кристалл.
func _roll_quarry_bonus(bld: Dictionary) -> void:
	var mcfg: Dictionary = cfg.get("mountain", {})
	var roll := _event_rng.randf()
	if roll < float(mcfg.get("by_iron", 0.35)):
		_add_resource_capped("iron", 1.0)
		events.append({"type": "quarry_bonus", "res": "iron"})
	elif roll < float(mcfg.get("by_iron", 0.35)) + float(mcfg.get("by_gems", 0.12)):
		_add_resource_capped("gems", 1.0)
		events.append({"type": "quarry_bonus", "res": "gems"})
		_chron("chron.gems_found")
	elif roll < float(mcfg.get("by_iron", 0.35)) + float(mcfg.get("by_gems", 0.12)) \
			+ float(mcfg.get("by_crystal", 0.08)):
		_add_resource_capped("crystal", 1.0)
		events.append({"type": "quarry_bonus", "res": "crystal"})
		_chron("chron.gem_found")


## Запас прочности тайла гряды по виду (руда жирнее скалы).
func _rock_max_hp(tile: Vector2i) -> float:
	var mcfg: Dictionary = cfg.get("mountain", {})
	var hp := float(mcfg.get("hp", 80.0))
	if int(map.grid[tile.y][tile.x]) == map.TILE_ORE:
		hp *= 1.3
	return hp


## Выработанный тайл гряды: с шансом вскрывается рудная жила, иначе остаётся
## пустая порода (deadrock) — на неё можно поставить шахту. Бонус камня — в руки.
func _exhaust_rock_tile(tile: Vector2i, r: Dictionary) -> void:
	var mcfg: Dictionary = cfg.get("mountain", {})
	map.rock_hp.erase(tile)
	r["raw"] = minf(float(mcfg.get("carry_raw", 8.0)),
			float(r.get("raw", 0.0)) + 2.0)
	var kind := int(map.grid[tile.y][tile.x])
	var roll := _event_rng.randf()
	if kind == map.TILE_ROCK and roll < float(mcfg.get("ore_reveal", 0.25)):
		map.grid[tile.y][tile.x] = map.TILE_ORE
		map.rock_hp[tile] = _rock_max_hp(tile)
		events.append({"type": "ore_revealed"})
		_chron("chron.ore_revealed")
	else:
		map.grid[tile.y][tile.x] = map.TILE_DEADROCK
		map.grid_ver += 1   # v1.28.1: маска скал изменилась
		map.rock_hp[tile] = float(mcfg.get("deadrock_hp", 60.0))
		events.append({"type": "rock_gone"})
		_chron("chron.rock_gone")
	map.refresh_tile_solid(tile)   # и жила, и пустая порода непроходимы
	terrain_dirty = true
	r["gath_tile"] = Vector2i(-1, -1)
	r["gath_res"] = Vector2i(-1, -1)
	r["carry_slow"] = float(mcfg.get("carry_slow", 0.8))


## Гряда в радиусе сбора от каменоломни: {stand, rock} — проходимый тайл-стойка
## у скалы/руды. Липкая цель на жителе (gath_tile — стойка, gath_res — гряда).
func _rock_target(r: Dictionary, bld: Dictionary) -> Dictionary:
	var cached: Vector2i = r.get("gath_tile", Vector2i(-1, -1))
	var cached_res: Vector2i = r.get("gath_res", Vector2i(-1, -1))
	if cached != Vector2i(-1, -1) and cached_res != Vector2i(-1, -1) \
			and map.in_bounds(cached_res) and map.in_bounds(cached) and map.is_walkable(cached) \
			and int(map.grid[cached_res.y][cached_res.x]) in [map.TILE_ROCK, map.TILE_ORE] \
			and _adjacent(cached, cached_res):
		return {"stand": cached, "rock": cached_res}
	var radius := int(cfg.get("gather_range", 6))
	var best := {}
	var best_d := INF
	var bc: Vector2i = bld["tile"]
	for dy in range(-radius - 1, radius + 2):
		for dx in range(-radius - 1, radius + 2):
			var rock: Vector2i = bc + Vector2i(dx, dy)
			if not map.in_bounds(rock) or not (int(map.grid[rock.y][rock.x]) in [map.TILE_ROCK, map.TILE_ORE]):
				continue
			for n in [rock + Vector2i(1, 0), rock + Vector2i(-1, 0), rock + Vector2i(0, 1), rock + Vector2i(0, -1)]:
				if not map.in_bounds(n) or not map.is_walkable(n) or not building_at(n).is_empty():
					continue
				var d: float = Vector2(rock).distance_to(Vector2(bc))
				if d < best_d:
					best_d = d
					best = {"stand": n, "rock": rock}
				break
	if best.is_empty():
		r["gath_tile"] = Vector2i(-1, -1)
		r["gath_res"] = Vector2i(-1, -1)
	else:
		r["gath_tile"] = best["stand"]
		r["gath_res"] = best["rock"]
	return best


func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	var d: Vector2i = a - b
	return (absi(d.x) == 1 and d.y == 0) or (absi(d.y) == 1 and d.x == 0)


# --- шахта ---------------------------------------------------------------------

## Шахта (ставится у жил и пустой породы): медленно добывает железо и камень
## из тайлов в радиусе mine.range клеток; выработанная жила становится породой.
func _mine_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	var day_len := float(cfg["day_length"])
	var mcfg: Dictionary = cfg.get("mountain", {}).get("mine", {})
	var cap: float = float(mcfg.get("carry", 8.0))
	var total: float = float(r.get("carry_iron", 0.0)) + float(r.get("carry_stone", 0.0))
	# жила/порода в радиусе от шахты (липкая цель)
	var pair: Dictionary = _vein_target(r, bld)
	# несём добычу к шахте — когда руки полны или тайлы кончились
	if total > 0.0 and (pair.is_empty() or total >= cap):
		if not at_bld(r, bld):
			r["state"] = "porter"
			_move_towards(r, bld_spot(bld), dt)
			return
		if float(r.get("carry_iron", 0.0)) > 0.0:
			_add_resource_capped("iron", float(r["carry_iron"]) * blessing_boost() * production_mult(bld))
		if float(r.get("carry_stone", 0.0)) > 0.0:
			_add_resource_capped("stone", float(r["carry_stone"]) * blessing_boost() * production_mult(bld))
		events.append({"type": "mine_hauled"})
		r["carry_iron"] = 0.0
		r["carry_stone"] = 0.0
		r["carry_slow"] = 1.0
		return
	if pair.is_empty():
		r["state"] = "idle"
		return
	var stand: Vector2i = pair["stand"]
	var tile: Vector2i = pair["rock"]
	if map.tile_of_px(r["pos"]) != stand:
		_move_towards(r, stand, dt)
		return
	var kind := int(map.grid[tile.y][tile.x])
	var max_hp := float(cfg.get("mountain", {}).get("deadrock_hp", 60.0))
	var per_tile := float(cfg.get("mountain", {}).get("deadrock_stone", 6.0))
	if kind == map.TILE_ORE:
		max_hp = _rock_max_hp(tile)
		per_tile = float(mcfg.get("ore_iron", 8.0))
	var hp := float(map.rock_hp.get(tile, max_hp))
	var drained: float = minf(hp, float(mcfg.get("rate", 35.0)) * dt / day_len * work_mult(r))
	hp -= drained
	var frac := drained / maxf(1.0, max_hp)
	if kind == map.TILE_ORE:
		r["carry_iron"] = minf(cap, float(r.get("carry_iron", 0.0)) + per_tile * frac)
		r["carry_stone"] = minf(cap - float(r.get("carry_iron", 0.0)),
				float(r.get("carry_stone", 0.0)) + float(mcfg.get("ore_stone", 2.0)) * frac)
	else:
		r["carry_stone"] = minf(cap, float(r.get("carry_stone", 0.0)) + per_tile * frac)
	r["state"] = "work"
	r["fatigue"] += dt / day_len * _fatigue_cost(r)
	_grow_skill(r, dt)
	if float(r.get("carry_iron", 0.0)) + float(r.get("carry_stone", 0.0)) >= cap:
		r["carry_slow"] = float(mcfg.get("carry_slow", 0.8))
		r["gath_tile"] = Vector2i(-1, -1)
		r["gath_res"] = Vector2i(-1, -1)
		return
	if hp > 0.0:
		map.rock_hp[tile] = hp
		return
	# жила выработана — становится пустой породой (и дальше шахта её доит)
	map.rock_hp[tile] = float(cfg.get("mountain", {}).get("deadrock_hp", 60.0))
	if kind == map.TILE_ORE:
		map.grid[tile.y][tile.x] = map.TILE_DEADROCK
		map.grid_ver += 1   # v1.28.1: маска скал изменилась
		events.append({"type": "rock_gone"})
		_chron("chron.rock_gone")
	terrain_dirty = true
	r["gath_tile"] = Vector2i(-1, -1)
	r["gath_res"] = Vector2i(-1, -1)


## Жила или пустая порода в радиусе mine.range от прямоугольника шахты:
## {stand, rock} с липкой целью (стойка — проходимый сосед тайла).
func _vein_target(r: Dictionary, bld: Dictionary) -> Dictionary:
	var mcfg: Dictionary = cfg.get("mountain", {}).get("mine", {})
	var radius := int(mcfg.get("range", 2))
	var cached: Vector2i = r.get("gath_tile", Vector2i(-1, -1))
	var cached_res: Vector2i = r.get("gath_res", Vector2i(-1, -1))
	if cached != Vector2i(-1, -1) and cached_res != Vector2i(-1, -1) \
			and map.in_bounds(cached_res) and map.in_bounds(cached) and map.is_walkable(cached) \
			and int(map.grid[cached_res.y][cached_res.x]) in [map.TILE_ORE, map.TILE_DEADROCK] \
			and _adjacent(cached, cached_res):
		return {"stand": cached, "rock": cached_res}
	var bw := bld_w(bld)
	var best := {}
	var best_d := INF
	var bc: Vector2i = bld["tile"]
	for dy in range(-radius - bw, radius + bw + 1):
		for dx in range(-radius - bw, radius + bw + 1):
			var rock: Vector2i = bc + Vector2i(dx, dy)
			if not map.in_bounds(rock) or not (int(map.grid[rock.y][rock.x]) in [map.TILE_ORE, map.TILE_DEADROCK]):
				continue
			# тайл в радиусе range от прямоугольника шахты (чебышев от края)
			var cdx := maxi(rock.x - bc.x, bc.x + bw - 1 - rock.x)
			var cdy := maxi(rock.y - bc.y, bc.y + bw - 1 - rock.y)
			if maxi(cdx, cdy) > radius:
				continue
			if bld_has_cell(bld, rock):
				continue   # под самой шахтой не подкопаться
			for n in [rock + Vector2i(1, 0), rock + Vector2i(-1, 0), rock + Vector2i(0, 1), rock + Vector2i(0, -1)]:
				if not map.in_bounds(n) or not map.is_walkable(n) or not building_at(n).is_empty():
					continue
				var d: float = Vector2(rock).distance_to(Vector2(bc))
				if d < best_d:
					best_d = d
					best = {"stand": n, "rock": rock}
				break
	if best.is_empty():
		r["gath_tile"] = Vector2i(-1, -1)
		r["gath_res"] = Vector2i(-1, -1)
	else:
		r["gath_tile"] = best["stand"]
		r["gath_res"] = best["rock"]
	return best
