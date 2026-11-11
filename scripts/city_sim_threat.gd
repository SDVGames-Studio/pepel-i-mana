# Часть: ручной труд героя — посадка/валка леса, добыча скалы, стройка, поля (v1.12.2/M11).
# Структура v1.62.0: некромант переехал в city_sim_necro.gd; здесь остался
# только ручной труд. Один класс, поведение не меняется.
extends "res://scripts/city_sim_necro.gd"

# --- M11: посадка леса -------------------------------------------------------

## Годен ли тайл под саженец.
func can_plant_at(tile: Vector2i) -> bool:
	if not map.in_bounds(tile) or map.grid[tile.y][tile.x] != map.TILE_GRASS:
		return false
	if map.stumps.has(tile) or map.saplings.has(tile) or map.logs.has(tile):
		return false
	if not building_at(tile).is_empty() or _tile_in_fill_zone(tile):
		return false
	return true


## Посадить саженец (из пула саженцев — выпадают из деревьев). "" — успех.
func plant_sapling(tile: Vector2i) -> String:
	var fcfg: Dictionary = cfg.get("forest", {})
	if not can_plant_at(tile):
		return "bad"
	if float(res.get("saplings", 0.0)) < 1.0:
		return "no_seeds"
	res["saplings"] = float(res["saplings"]) - 1.0
	map.saplings[tile] = {"t": 0.0, "grow_days": float(fcfg.get("grow_days", 5.0))}
	terrain_dirty = true
	events.append({"type": "sapling_planted"})
	_chron("chron.sapling_planted")
	return ""


# --- M11: добыча скалы -------------------------------------------------------

## Тайл гряды рядом с добытчиком (свой тайл непроходим — берём соседний).
## Пустая порода (deadrock) герою не по зубам — её медленно доит шахта (v1.21).
func _rock_tile_near(px: Vector2) -> Vector2i:
	var base: Vector2i = map.tile_of_px(px)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var t: Vector2i = base + d
		if not map.in_bounds(t) or not map.rock_hp.has(t):
			continue
		if int(map.grid[t.y][t.x]) not in [map.TILE_ROCK, map.TILE_ORE]:
			continue
		return t
	return Vector2i(-1, -1)


# --- ручной труд героя (правки v1.12.2): E у дерева/скалы/стройки -----------

func _hero_work_cfg() -> Dictionary:
	return cfg.get("hero_work", {})


## Дерево у ног героя (свой тайл тоже — деревья проходимы):
## {tile, hits, need} — для подсказки и добивки. Правки v1.21: число ударов
## зависит от размера дерева (малое/среднее/большое).
func hero_tree_near(px: Vector2) -> Dictionary:
	var base: Vector2i = map.tile_of_px(px)
	for t in [base, base + Vector2i(1, 0), base + Vector2i(-1, 0),
			base + Vector2i(0, 1), base + Vector2i(0, -1)]:
		if map.in_bounds(t) and map.grid[t.y][t.x] == map.TILE_TREE:
			return {"tile": t, "hits": int(_chop_progress.get(t, 0)),
					"size": map.tree_kind(t),
					"need": maxi(1, _hero_chop_hits(map.tree_kind(t)))}
	return {}


## Ударов героя на валку дерева размера size.
func _hero_chop_hits(size: int) -> int:
	var table: Dictionary = _hero_work_cfg().get("chop_hits", {})
	var key := "small" if size == map.TREE_SMALL else ("medium" if size == map.TREE_MEDIUM else "large")
	return int(table.get(key, 7))


## Спелая грядка в шаге от героя (этап 2, аспект 3): {zone, idx, tile, crop}.
func hero_harvest_near(px: Vector2) -> Dictionary:
	var base: Vector2i = map.tile_of_px(px)
	for t in [base, base + Vector2i(1, 0), base + Vector2i(-1, 0),
			base + Vector2i(0, 1), base + Vector2i(0, -1)]:
		var z: Dictionary = field_at(t)
		if z.is_empty():
			continue
		for i in (z["cells"] as Array).size():
			if Vector2i(z["cells"][i]) != t or not (z["crops"] as Array).size() > i:
				continue
			var crop: Dictionary = (z["crops"] as Array)[i]
			if bool(crop.get("ripe", false)):
				return {"zone": z, "idx": i, "tile": t, "crop": String(z.get("crop", "turnip"))}
	return {}


## Сбор спелой грядки героем: еда в общий пул, семя возвращается, клетка
## пересеивается той же культурой (за обычное семя). "" — нет спелой грядки.
func hero_harvest(px: Vector2) -> String:
	var h: Dictionary = hero_harvest_near(px)
	if h.is_empty():
		return ""
	_harvest_cell(h["zone"], int(h["idx"]))
	events.append({"type": "hero_harvest"})
	return "food"


## Незаполненная клетка зоны (поле/пастбище/жилая) в шаге от героя:
## {zone, idx, tile} — герой может вспахать её сам (2026-10-21).
func hero_till_near(px: Vector2) -> Dictionary:
	var base: Vector2i = map.tile_of_px(px)
	for t in [base, base + Vector2i(1, 0), base + Vector2i(-1, 0),
			base + Vector2i(0, 1), base + Vector2i(0, -1)]:
		for z in zones:
			for i in (z["cells"] as Array).size():
				if Vector2i(z["cells"][i]) != t or _cell_filled(z, i):
					continue
				if not building_at(t).is_empty():
					continue
				return {"zone": z, "idx": i, "tile": t}
	return {}


## Вспашка клетки зоны героем: каждый E продвигает обустройство на fill_per_hit.
## "" — рядом нет клетки зоны, "till" — удар засчитан, "tilled" — клетка готова.
func hero_till(px: Vector2) -> String:
	var h: Dictionary = hero_till_near(px)
	if h.is_empty():
		return ""
	var z: Dictionary = h["zone"]
	var i := int(h["idx"])
	var fill_work: float = float(cfg.get("zones", {}).get("fill_work", 4.0))
	var was: float = float(z["progress"][i])
	z["progress"][i] = minf(fill_work, was + float(_hero_work_cfg().get("fill_per_hit", 2.0)))
	if float(z["progress"][i]) >= fill_work and was < fill_work:
		events.append({"type": "zone_cell", "zone": String(z["type"])})
		_zone_check_done(z, {})
		return "tilled"
	return "till"


## Засеянная пустая клетка поля в шаге от героя (заполнена, без посева):
## {zone, idx, tile} — герой сеет сам, если семян не нашлось автоматом.
func hero_sow_near(px: Vector2) -> Dictionary:
	var base: Vector2i = map.tile_of_px(px)
	for t in [base, base + Vector2i(1, 0), base + Vector2i(-1, 0),
			base + Vector2i(0, 1), base + Vector2i(0, -1)]:
		for z in zones:
			if String(z["type"]) != "field":
				continue
			var crops: Array = z.get("crops", [])
			for i in (z["cells"] as Array).size():
				if Vector2i(z["cells"][i]) != t or not _cell_filled(z, i):
					continue
				if not building_at(t).is_empty():
					continue
				if crops.size() > i and not (crops[i] as Dictionary).is_empty():
					continue   # уже растёт
				return {"zone": z, "idx": i, "tile": t}
	return {}


## Посев клетки поля героем: 1 семя из пула, росток той же культуры поля.
## "" — сеять нечего, "no_seeds" — нет семян, "sow" — посеяно.
func hero_sow(px: Vector2) -> String:
	var h: Dictionary = hero_sow_near(px)
	if h.is_empty():
		return ""
	var fcfg: Dictionary = cfg.get("farming", {})
	if float(res.get("seeds", 0.0)) < float(fcfg.get("seed_sow", 1)):
		return "no_seeds"
	res["seeds"] = float(res["seeds"]) - float(fcfg.get("seed_sow", 1))
	var zone: Dictionary = h["zone"]
	if not (zone as Dictionary).has("crops"):
		zone["crops"] = []
	var crops: Array = zone["crops"]
	while crops.size() <= int(h["idx"]):
		crops.append({})
	crops[int(h["idx"])] = {"stage": 0, "t": 0.0, "ripe": false}
	events.append({"type": "hero_sow"})
	return "sow"


## Работа фермера (правки v1.21): ферма при постройке распахивает поле вокруг
## себя — грядки стали её собственностью. Фермер сперва собирает спелые клетки
## СВОЕГО поля, затем вспахивает его незаполненные клетки; своё поле в порядке —
## помогает чужим полям и пастбищам. Пассивной еды ферма больше не даёт.
func _farm_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		r["state"] = "idle"
		return
	var farm_id := int(bld["id"])
	# 1) спелая клетка поля — собрать (сначала своё поле)
	var ripe := _nearest_ripe_field_cell(r, farm_id)
	if not ripe.is_empty():
		var tile: Vector2i = ripe["tile"]
		if _arrived(r, tile):
			_harvest_cell(ripe["zone"], int(ripe["idx"]))
			r["state"] = "harvest"
			r["fatigue"] += dt / float(cfg["day_length"])
			_grow_skill(r, dt)
		else:
			_move_towards(r, tile, dt)
		return
	# 2) незаполненная клетка поля — вспахать (сначала своё)
	var fill := _nearest_field_cell(r, farm_id)
	if not fill.is_empty():
		var tile2: Vector2i = fill["tile"]
		if _arrived(r, tile2):
			r["state"] = "fill"
			var zz: Dictionary = fill["zone"]
			var i2 := int(fill["idx"])
			zz["progress"][i2] = float(zz["progress"][i2]) + dt * work_mult(r)
			r["fatigue"] += dt / float(cfg["day_length"])
			_grow_skill(r, dt)
			if _cell_filled(zz, i2):
				events.append({"type": "zone_cell", "zone": "field"})
				_zone_check_done(zz, r)
		else:
			_move_towards(r, tile2, dt)
		return
	# 3) своё поле в порядке — помочь чужим полям и пастбищам, иначе стоит у фермы
	if _zone_fill_work(r, dt):
		return
	if at_bld(r, bld):
		r["state"] = "idle"
	else:
		_move_towards(r, bld_spot(bld), dt)


## Ближайшая спелая клетка поля (сначала поля фермы farm_id, потом любые).
## Правки v1.20.1: цель «липкая» — начатую грядку доводят до конца.
func _nearest_ripe_field_cell(r: Dictionary, farm_id := -1) -> Dictionary:
	var sticky_z: Dictionary = zone_by_id(int(r.get("_ripe_zone", -1)))
	if not sticky_z.is_empty():
		var si := int(r.get("_ripe_idx", -1))
		var scrops: Array = sticky_z.get("crops", [])
		if si >= 0 and si < (sticky_z["cells"] as Array).size() \
				and scrops.size() > si and bool((scrops[si] as Dictionary).get("ripe", false)):
			return {"zone": sticky_z, "idx": si, "tile": sticky_z["cells"][si]}
	var best := {}
	var best_d := INF
	var fallback := {}
	var fallback_d := INF
	for z in zones:
		if String(z["type"]) != "field":
			continue
		var own := farm_id > 0 and int(z.get("farm", -1)) == farm_id
		var crops: Array = z.get("crops", [])
		for i in (z["cells"] as Array).size():
			if not _cell_filled(z, i) or not building_at(z["cells"][i]).is_empty():
				continue
			# v1.28: null-дыры в посевах старых сейвов не роняют поиск
			if crops.size() <= i or not (crops[i] is Dictionary) \
					or not bool((crops[i] as Dictionary).get("ripe", false)):
				continue
			var d: float = map.tile_center_px(z["cells"][i]).distance_to(r["pos"])
			if own and d < best_d:
				best_d = d
				best = {"zone": z, "idx": i, "tile": z["cells"][i]}
			elif not own and d < fallback_d:
				fallback_d = d
				fallback = {"zone": z, "idx": i, "tile": z["cells"][i]}
	if best.is_empty():
		best = fallback
	if not best.is_empty():
		r["_ripe_zone"] = int((best["zone"] as Dictionary)["id"])
		r["_ripe_idx"] = int(best["idx"])
	else:
		r["_ripe_zone"] = -1
		r["_ripe_idx"] = -1
	return best


## Незаполненная клетка поля: сначала поле своей фермы (липкая цель).
func _nearest_field_cell(r: Dictionary, farm_id := -1) -> Dictionary:
	# липкая цель (правки v1.20.1): начатую клетку доводим до конца
	var sticky_z: Dictionary = zone_by_id(int(r.get("_fill_zone", -1)))
	if not sticky_z.is_empty():
		var si := int(r.get("_fill_idx", -1))
		if si >= 0 and si < (sticky_z["cells"] as Array).size() \
				and String(sticky_z["type"]) == "field" \
				and not _cell_filled(sticky_z, si) \
				and building_at(sticky_z["cells"][si]).is_empty():
			return {"zone": sticky_z, "idx": si, "tile": sticky_z["cells"][si]}
	var best := {}
	var best_d := INF
	var fallback := {}
	var fallback_d := INF
	for z in zones:
		if String(z["type"]) != "field":
			continue
		var own := farm_id > 0 and int(z.get("farm", -1)) == farm_id
		for i in (z["cells"] as Array).size():
			if _cell_filled(z, i) or not building_at(z["cells"][i]).is_empty():
				continue
			var d: float = map.tile_center_px(z["cells"][i]).distance_to(r["pos"])
			if own and d < best_d:
				best_d = d
				best = {"zone": z, "idx": i, "tile": z["cells"][i]}
			elif not own and d < fallback_d:
				fallback_d = d
				fallback = {"zone": z, "idx": i, "tile": z["cells"][i]}
	if best.is_empty():
		best = fallback
	if not best.is_empty():
		r["_fill_zone"] = int((best["zone"] as Dictionary)["id"])
		r["_fill_idx"] = int(best["idx"])
	else:
		r["_fill_zone"] = -1
		r["_fill_idx"] = -1
	return best


## Скала или рудная жила в шаге от героя: {tile, kind: "rock"|"ore"}.
func hero_rock_near(px: Vector2) -> Dictionary:
	var tile: Vector2i = _rock_tile_near(px)
	if tile == Vector2i(-1, -1):
		return {}
	return {"tile": tile,
			"kind": "ore" if int(map.grid[tile.y][tile.x]) == map.TILE_ORE else "rock"}


## Недостроенное здание в шаге от героя ({}, если стройки рядом нет).
func hero_site_near(px: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1.6 * float(map.ts) + float(map.ts) * 0.5   # прямоугольник 2×2: чуть щедрее
	for b in buildings:
		if bool(b["done"]):
			continue
		var d: float = bld_dist_px(px, b)
		if d <= best_d:
			best_d = d
			best = b
	return best


## Удар топором: hits зависят от размера — малое 4, среднее 7, большое 11.
## Поваленное дерево ложится БРЕВНОМ на землю (v1.21.2: доски даёт только
## лесопилка) — лесоруб подберёт и распилит; пень и гнев леса как у всех,
## из дерева выпадают саженцы.
## "" — рядом нет дерева, "hit" — удар засчитан, "fell" — дерево повалено.
func hero_chop(px: Vector2) -> String:
	var tree: Dictionary = hero_tree_near(px)
	if tree.is_empty():
		return ""
	var tile: Vector2i = tree["tile"]
	var hits := int(_chop_progress.get(tile, 0)) + 1
	if hits < int(tree["need"]):
		_chop_progress[tile] = hits
		return "hit"
	_chop_progress.erase(tile)
	var fcfg: Dictionary = cfg.get("forest", {})
	map.grid[tile.y][tile.x] = map.TILE_GRASS
	map.stumps[tile] = true
	map.tree_size.erase(tile)
	map.tree_growth.erase(tile)
	map.logs[tile] = {"size": int(tree["size"])}   # бревно ждёт лесопилку (v1.21.2)
	terrain_dirty = true
	forest_anger = clampf(forest_anger + float(fcfg.get("anger_per_tree", 1.0)), 0.0, 100.0)
	_drop_saplings()   # из поваленного дерева выпадают саженцы
	events.append({"type": "tree_felled", "log": true})
	_chron("chron.tree_felled")
	return "fell"


## Удар киркой: герою — только строительный камень (железо и кристаллы
## добывают каменоломня и шахта, v1.21). Выработанный тайл не исчезает:
## под ним жила (шанс) или пустая порода — место под шахту.
## "" — рядом нет скалы, "hit" — удар засчитан, "ore"/"stone" — тайл выработан.
func hero_mine(px: Vector2) -> String:
	var rock: Dictionary = hero_rock_near(px)
	if rock.is_empty():
		return ""
	var mcfg: Dictionary = cfg.get("mountain", {})
	var tile: Vector2i = rock["tile"]
	_add_resource_capped("stone", float(_hero_work_cfg().get("stone_per_hit", 2)))
	var max_hp := _rock_max_hp(tile)
	var hp := float(map.rock_hp.get(tile, max_hp)) \
			- max_hp / float(maxi(1, int(_hero_work_cfg().get("mine_hits", 4))))
	if hp > 0.0:
		map.rock_hp[tile] = hp
		return "hit"
	# тайл выработан: жила или пустая порода (v1.21 — травы больше нет)
	var kind := int(map.grid[tile.y][tile.x])
	var roll := _event_rng.randf()
	map.rock_hp.erase(tile)
	terrain_dirty = true
	if kind == map.TILE_ROCK and roll < float(mcfg.get("ore_reveal", 0.25)):
		map.grid[tile.y][tile.x] = map.TILE_ORE
		map.refresh_tile_solid(tile)
		map.rock_hp[tile] = _rock_max_hp(tile)
		events.append({"type": "ore_revealed"})
		_chron("chron.ore_revealed")
		return "ore"
	_add_resource_capped("stone", float(mcfg.get("bonus_stone", 6)))
	map.grid[tile.y][tile.x] = map.TILE_DEADROCK
	map.rock_hp[tile] = float(mcfg.get("deadrock_hp", 60.0))
	map.refresh_tile_solid(tile)
	events.append({"type": "rock_gone"})
	_chron("chron.rock_gone")
	return "stone"


## Удар молотком у стройки: работа идёт в прогресс, достройка — общая
## (стены становятся преградой, декор радует, заказ «построить» закрывается).
## "" — рядом нет стройки, "hit" — удар засчитан, "done" — здание готово.
func hero_build(px: Vector2) -> String:
	var site: Dictionary = hero_site_near(px)
	if site.is_empty():
		return ""
	site["progress"] = float(site["progress"]) + float(_hero_work_cfg().get("build_per_hit", 2.5))
	if float(site["progress"]) >= float(_def(site)["build_work"]):
		_complete_site(site)
		return "done"
	return "hit"

