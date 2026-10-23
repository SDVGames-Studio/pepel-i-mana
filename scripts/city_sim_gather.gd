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
## Деревьев в радиусе нет — лесорум стоит у лесопилки (доски сами не капают).
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
		r["fatigue"] += dt / day_len
		_grow_skill(r, dt)
		if float(r["saw_t"]) < need_saw:
			r["state"] = "saw"
			return
		var size := int(r["log_size"])
		var planks: float = _planks_for(size) * blessing_boost() * production_mult(bld)
		_add_pile(bld, "wood", planks)
		forest_anger = clampf(forest_anger + float(fcfg.get("anger_per_sawing", 0.5)), 0.0, 100.0)
		events.append({"type": "tree_sawed", "planks": int(planks)})
		_chron("chron.tree_sawed", str(int(planks)))
		r["log_size"] = 0
		r["saw_t"] = 0.0
		r["carry_slow"] = 1.0
		return
	# готовим поваленное бревно к переноске (закрепляем, обрубаем сучья)
	if float(r.get("prep_left", 0.0)) > 0.0:
		r["prep_left"] = maxf(0.0, float(r["prep_left"]) - dt * work_mult(r))
		r["state"] = "prep"
		r["fatigue"] += dt / day_len
		_grow_skill(r, dt)
		if float(r["prep_left"]) <= 0.0:
			r["log_size"] = int(r.get("fell_size", map.TREE_SMALL))
			r["carry_slow"] = _carry_mult(int(r["log_size"]))
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
			if map.saplings.has(t) or map.stumps.has(t) or not map.is_walkable(t):
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
	r["fatigue"] += dt / float(cfg["day_length"])
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
		_add_pile(bld, "stone", raw * blessing_boost() * production_mult(bld))
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
	r["fatigue"] += dt / day_len
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
		_add_pile(bld, "iron", 1.0)
		events.append({"type": "quarry_bonus", "res": "iron"})
	elif roll < float(mcfg.get("by_iron", 0.35)) + float(mcfg.get("by_gems", 0.12)):
		_add_pile(bld, "gems", 1.0)
		events.append({"type": "quarry_bonus", "res": "gems"})
		_chron("chron.gems_found")
	elif roll < float(mcfg.get("by_iron", 0.35)) + float(mcfg.get("by_gems", 0.12)) \
			+ float(mcfg.get("by_crystal", 0.08)):
		_add_pile(bld, "crystal", 1.0)
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
			_add_pile(bld, "iron", float(r["carry_iron"]) * blessing_boost() * production_mult(bld))
		if float(r.get("carry_stone", 0.0)) > 0.0:
			_add_pile(bld, "stone", float(r["carry_stone"]) * blessing_boost() * production_mult(bld))
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
	r["fatigue"] += dt / day_len
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
