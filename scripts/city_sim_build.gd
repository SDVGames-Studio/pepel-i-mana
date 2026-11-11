# Часть: дисциплины города (M7), здания 2×2 и их входы, размещение и стройка,
# дороги, достройка и поле фермы.
# Структура v1.62.0: миграция/урон/ремонт/перенос переехали в
# city_sim_repair.gd. Это один класс, поведение не меняется.
extends "res://scripts/city_sim_life.gd"

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

## Определение здания по типу. v1.21.4: кэш по type_id — конфиги неизменны,
## а _def зовётся из настроения/производства/добытчиков десятки раз за кадр.
func _def(b: Dictionary) -> Dictionary:
	var key := String(b["type"])
	if _def_cache.has(key):
		return _def_cache[key]
	for d in cfg["buildings"]:
		if String(d["id"]) == key:
			_def_cache[key] = d
			return d
	return {}


## Здание по тайлу (прямоугольник 2×2: попадание в любую клетку).
## v1.21.4: индекс клеток вместо скана списка — building_at зовётся из зон,
## героев и входов постоянно; индекс пересобирается при мутации списка
## (_spots_dirty/place_building/сейв инкрементируют _bld_ver).
func building_at(tile: Vector2i) -> Dictionary:
	if _bld_tiles_ver != _bld_ver:
		_bld_tiles_ver = _bld_ver
		_bld_tiles = {}
		for b in buildings:
			var t := Vector2i(b["tile"])
			var w := bld_w(b)
			for dy in w:
				for dx in w:
					var cell := t + Vector2i(dx, dy)
					if not _bld_tiles.has(cell):
						_bld_tiles[cell] = b   # первое здание в списке выигрывает — как в старом скане
	return _bld_tiles.get(tile, {})

# --- здания 2×2 (этап 2, аспект 2) -----------------------------------------

## Ширина здания в клетках: 2 у всех капитальных, 1 у тайловой инфраструктуры
## (стена, ворота, мост — кольцо обороны и переправы по природе тайловые).
## Читается из здания ("w", ставится при стройке/миграции), фолбэк — конфиг.
func bld_w(b: Dictionary) -> int:
	if b.has("w"):
		return int(b["w"])
	var def := _def(b)
	return int(def.get("w", 1)) if not def.is_empty() else 1


## Все клетки прямоугольника здания (tile — левый-верхний угол).
func bld_cells(b: Dictionary) -> Array:
	var out: Array = []
	var t := Vector2i(b["tile"])
	var w := bld_w(b)
	for dy in w:
		for dx in w:
			out.append(t + Vector2i(dx, dy))
	return out


## Клетка прямоугольника содержит тайл?
func bld_has_cell(b: Dictionary, tile: Vector2i) -> bool:
	var t: Vector2i = Vector2i(b["tile"])
	var w := bld_w(b)
	return tile.x >= t.x and tile.y >= t.y and tile.x < t.x + w and tile.y < t.y + w


## Вход здания: клетка снаружи у прямоугольника, к которой примыкает
## проходимый тайл. Приоритет — примыкание к дороге, затем южная сторона.
## Кэш в _spot_cache валиден, пока вход проходим и не занят другим зданием:
## соседние постройки 2×2 в плотном городе перекрывают вход — кэш
## пересчитывается (замечание приёмки: работники простаивали вечно).
func bld_entrance(b: Dictionary) -> Vector2i:
	var key := int(b["id"])
	var tile := Vector2i(b["tile"])
	var cached: Dictionary = _spot_cache.get(key, {})
	if not cached.is_empty() and Vector2i(cached.get("key", Vector2i(-9, -9))) == tile:
		var cs: Vector2i = Vector2i(cached["spot"])
		if not cs == Vector2i(-1, -1) and map.is_walkable(cs) and building_at(cs).is_empty():
			return cs
	var w := bld_w(b)
	var best := Vector2i(-1, -1)
	var best_road := -1
	for dy in range(-1, w + 1):
		for dx in range(-1, w + 1):
			var on_rect := dx >= 0 and dy >= 0 and dx < w and dy < w
			if on_rect:
				continue
			# только клетки, примыкающие к прямоугольнику (не по диагонали)
			if dx != -1 and dx != w and dy != -1 and dy != w:
				continue
			var n := tile + Vector2i(dx, dy)
			if not map.in_bounds(n) or not map.is_walkable(n) or not building_at(n).is_empty():
				continue
			var road := 1 if map.has_road(n) else 0
			var south := 1 if dy == w else 0
			var score := road * 2 + south
			if score > best_road:
				best_road = score
				best = n
	if best == Vector2i(-1, -1):
		best = _walkable_next_to_rect(b)   # замуровано: хоть что-то проходимое рядом
	_spot_cache[key] = {"key": tile, "spot": best}
	return best


## Ближайшая проходимая клетка снаружи прямоугольника (без приоритетов).
func _walkable_next_to_rect(b: Dictionary) -> Vector2i:
	var t: Vector2i = Vector2i(b["tile"])
	var w := bld_w(b)
	for dy in range(-1, w + 1):
		for dx in range(-1, w + 1):
			if dx >= 0 and dy >= 0 and dx < w and dy < w:
				continue
			if dx != -1 and dx != w and dy != -1 and dy != w:
				continue
			var n := t + Vector2i(dx, dy)
			if map.in_bounds(n) and map.is_walkable(n) and building_at(n).is_empty():
				return n
	return Vector2i(-1, -1)


## Точка подхода к зданию: вход (проходимая клетка у прямоугольника).
func bld_spot(b: Dictionary) -> Vector2i:
	var e := bld_entrance(b)
	return e if not e == Vector2i(-1, -1) else Vector2i(b["tile"])


## Житель стоит у здания (на входе или — для незамкнутых случаев — в клетке).
func at_bld(r: Dictionary, b: Dictionary) -> bool:
	var t: Vector2i = map.tile_of_px(r["pos"])
	return t == bld_spot(b)


## Здание занимает тайл? (в отличие от building_at — по прямоугольнику)
func building_at_rect(tile: Vector2i) -> Dictionary:
	return building_at(tile)


## Ширина здания типа из конфига (без конкретного здания).
func bld_w_of_type(type_id: String) -> int:
	if _bld_w_cache.has(type_id):
		return int(_bld_w_cache[type_id])
	var w := 1
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			w = int(d.get("w", 1))
			break
	_bld_w_cache[type_id] = w
	return w


## Прямоугольник w×w с углом в tile годен под здание типа type_id?
## Стройплощадки и мосты проходимы — учитываются отдельно (мост на воде).
func is_buildable_rect(type_id: String, tile: Vector2i) -> bool:
	var w := bld_w_of_type(type_id)
	for dy in w:
		for dx in w:
			if not is_buildable_tile(tile + Vector2i(dx, dy), type_id):
				return false
	return true


## Расстояние по пикселям от точки до ближайшей клетки прямоугольника.
func bld_dist_px(pos: Vector2, b: Dictionary) -> float:
	var w := bld_w(b)
	var t := Vector2i(b["tile"])
	var best := INF
	for dy in w:
		for dx in w:
			best = minf(best, map.tile_center_px(t + Vector2i(dx, dy)).distance_to(pos))
	return best


## Зазор между прямоугольниками зданий в клетках (шебышев): 0 — касаются
## или пересекаются. Используется правилами размещения (этап 2).
func rects_gap(a: Dictionary, b: Dictionary) -> int:
	var at: Vector2i = Vector2i(a["tile"])
	var bt: Vector2i = Vector2i(b["tile"])
	var aw := bld_w(a)
	var bw := bld_w(b)
	var dx := maxf(maxi(at.x - (bt.x + bw), bt.x - (at.x + aw)), 0)
	var dy := maxf(maxi(at.y - (bt.y + bw), bt.y - (at.y + aw)), 0)
	return int(maxf(float(dx), float(dy)))


## Правила размещения (этап 2, замечание приёмки): между обычными зданиями —
## зазор минимум build_gap (клетка под дорогу); стена/ворота строятся
## сплошным кольцом (между собой зазора не держат), но держат wall_house_gap
## минимум до ближайшего дома.
func placement_gap_ok(type_id: String, tile: Vector2i, skip_id := -1) -> bool:
	var pcfg: Dictionary = cfg.get("placement", {})
	var new_b := {"type": type_id, "tile": tile}
	var wall_class := type_id == "wall" or type_id == "gate"
	for b in buildings:
		if int(b["id"]) == skip_id:
			continue   # перенос здания: собственные клетки не мешают (этап 2, аспект 5)
		var other_type := String(b["type"])
		var gap := rects_gap(new_b, b)
		if wall_class:
			if other_type == "house" and gap < int(pcfg.get("wall_house_gap", 3)):
				return false
		elif other_type != "wall" and other_type != "gate":
			if gap < int(pcfg.get("build_gap", 1)):
				return false
	return true


## Сбросить кэш входов и индекс клеток (при любой мутации зданий; v1.21.4 —
## сюда же садится версионирование building_at).
func _spots_dirty() -> void:
	_spot_cache.clear()
	_bld_ver += 1



# --- стройка -------------------------------------------------------------

## Тайл годен под стройку: проходимая суша (или руда под шахту), нет здания, не аномалия.
func is_buildable_tile(tile: Vector2i, type_id := "") -> bool:
	if not map.in_bounds(tile) or tile == map.anomaly_tile:
		return false
	# v1.36: лестница — единственный проход на плато (№113), строить на
	# ней нельзя: иначе город замурует сам себе выход наверх
	if map.is_stair(tile):
		return false
	# главная площадь (правки v1.20): в радиусе plaza.radius клеток строить нельзя
	if type_id != "bridge" and near_plaza(tile):
		return false
	if not map.is_nature_walkable(tile):
		# шахту ставим и на рудную жилу, и на пустую породу выработанного
		# массива (v1.21); поле фермы под шахтой не вспахано — до шахты ей дела нет
		if type_id == "mine" and (map.grid[tile.y][tile.x] == map.TILE_ORE \
				or map.grid[tile.y][tile.x] == map.TILE_DEADROCK):
			pass
		# мост (M14-I) ставится прямо на воду
		elif type_id == "bridge" and map.grid[tile.y][tile.x] == map.TILE_WATER:
			pass
		# v1.56: здания с place="water" (ПРИСТАНЬ) — прямо на воду. Прежде
		# «place: water» требовал лишь воды рядом, и пристань приходилось
		# лепить на землю — заказчик: «пристань не работает, не ставится».
		elif _place_of_type(type_id) == "water" \
				and map.grid[tile.y][tile.x] == map.TILE_WATER:
			pass
		else:
			return false
	if type_id == "bridge" and map.grid[tile.y][tile.x] != map.TILE_WATER:
		return false   # мост — только на воде
	# пристани на открытои воде нужен берег под боком (рабочий дойдёт до
	# входа bld_entrance); 2×2 в чистом озере — недостижима
	if type_id == "pier" and map.grid[tile.y][tile.x] == map.TILE_WATER \
			and not _shore_near_rect(tile, 2):
		return false
	return building_at(tile).is_empty()


## Месторождение региона в радиусе (v1.56).
func _deposit_near(tile: Vector2i, radius: float) -> bool:
	var r2 := radius * radius
	for dt in map.deposit_tiles:
		if Vector2(dt).distance_squared_to(Vector2(tile)) <= r2:
			return true
	return false


## place здания по типу ("", если нет) — v1.56 для water-построек.
func _place_of_type(type_id: String) -> String:
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			return String(d.get("place", ""))
	return ""


## Есть ли проходимая суша вплотную к прямоугольнику w×w от tile.
func _shore_near_rect(tile: Vector2i, w: int) -> bool:
	for dy in range(-1, w + 1):
		for dx in range(-1, w + 1):
			if dx >= 0 and dy >= 0 and dx < w and dy < w:
				continue
			if dx != -1 and dx != w and dy != -1 and dy != w:
				continue   # только периметр, не диагонали
			var n := tile + Vector2i(dx, dy)
			if map.in_bounds(n) and map.is_nature_walkable(n):
				return true
	return false


## Заложить стройплощадку: ресурсы списываются сразу (ответ №16 — достраивают рабочие).
## Особые здания требуют места: шахта — руда, пирс — вода рядом, оружейная — кузня рядом.
func place_building(type_id: String, tile: Vector2i) -> bool:
	# мост (M14-I): единственная постройка НА воде, соединяет берега
	if String(type_id) == "bridge":
		return _place_bridge(tile)
	var def := _def({"type": type_id})
	if def.is_empty() or not is_buildable_rect(type_id, tile) or not can_afford(def["cost"]):
		return false
	if int(def.get("max_count", 0)) > 0 and _count_type(type_id) >= int(def["max_count"]):
		return false   # лимит числа построек (этап 2: палатки — не больше трёх)
	if placement_block(type_id, tile) != "":
		return false
	if not placement_gap_ok(type_id, tile):
		return false   # зазор между зданиями / стена ближе 3 к дому (этап 2)
	for key in def["cost"]:
		res[key] = int(res[key]) - int(def["cost"][key])
	var w := int(def.get("w", 1))
	buildings.append({
		"id": _next_id, "type": type_id, "tile": tile, "w": w,
		"done": false, "progress": 0.0, "worker": -1,
		"enchant": "", "ench_mult": 1.0, "stun_left": 0.0,
		"hp": float(_bld_max_hp(type_id)),
		"pile": {},
	})
	_next_id += 1
	_bld_ver += 1   # новое здание — индекс клеток перестроится (v1.21.4)
	# здание занимает прямоугольник: дороги и клетки зон под ним уступают место
	for dy in w:
		for dx in w:
			var cell := tile + Vector2i(dx, dy)
			map.remove_road(cell)
			_drop_zone_cell(cell)
	events.append({"type": "site", "bld": type_id})
	_assign_jobs()
	return true


## Мост (M14-I): дерево 4 — строится только на воде, делает тайл проходимым.
func _place_bridge(tile: Vector2i) -> bool:
	if not map.in_bounds(tile) or map.grid[tile.y][tile.x] != map.TILE_WATER \
			or map.bridges.has(tile) or not can_afford(_def({"type": "bridge"})["cost"]):
		return false
	for key in _def({"type": "bridge"})["cost"]:
		res[key] = float(res[key]) - float(_def({"type": "bridge"})["cost"][key])
	map.bridges[tile] = true
	map.note_edit(tile)
	map.refresh_tile_solid(tile)   # мост открывает воду для путей (этап 2)
	_chron("chron.bridge")
	events.append({"type": "bridge"})
	return true


## Проложить дорогу (M6): трава без зданий и зон, камень за тайл. "" — успех.
## Через зоны-слои дорога проходит (этап 2, аспект 6).
func place_road(tile: Vector2i) -> String:
	if not map.in_bounds(tile) or not map.is_nature_walkable(tile) \
			or not building_at(tile).is_empty() or _tile_in_fill_zone(tile):
		return "bad"
	if map.has_road(tile):
		return ""
	var rcfg: Dictionary = cfg.get("roads", {})
	var cost := int(rcfg.get("cost_stone", 1))
	if int(res["stone"]) < cost:
		return "no_stone"
	res["stone"] = int(res["stone"]) - cost
	map.set_road(tile, float(rcfg.get("astar_weight", 0.4)))
	static_dirty = true   # новая плитка дороги — духовка №2 (v1.22)
	map.note_edit_static(tile)   # v1.52.2: инкремент, а не вся карта
	return ""


## v1.59: поле (зона-«field») ближе dist клеток к прямоугольнику здания?
func _farm_zone_near(tile: Vector2i, dist: int) -> bool:
	var w := bld_w_of_type("sawmill")
	for z in zones:
		if String(z["type"]) != "field":
			continue
		for c in z["cells"]:
			if c.x >= tile.x - dist and c.x < tile.x + w + dist \
					and c.y >= tile.y - dist and c.y < tile.y + w + dist:
				return true
	return false


## Клетка занята зоной?
func _tile_in_zone(tile: Vector2i) -> bool:
	for z in zones:
		if (z["cells"] as Array).has(tile):
			return true
	return false


## Клетка занята зоной (поле/пастбище): дороги и посадка леса туда не идут.
func _tile_in_fill_zone(tile: Vector2i) -> bool:
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
	static_dirty = true   # земля менялась — перевыпечь духовку (v1.22)
	for z in zones:
		var idx: int = (z["cells"] as Array).find(tile)
		if idx >= 0:
			z["cells"].remove_at(idx)
			z["progress"].remove_at(idx)
			return


## Почему здание нельзя поставить здесь: ключ локализации или "" (для тоста сцены).
## skip_count — перенос своего здания: лимит числа построек не проверяется.
func placement_block(type_id: String, tile: Vector2i, skip_count := false) -> String:
	var place := ""
	var max_count := 0
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			place = String(d.get("place", ""))
			max_count = int(d.get("max_count", 0))
			break
	if not skip_count and max_count > 0 and _count_type(type_id) >= max_count:
		return "city.tent_limit"   # лимит построек типа (этап 2, аспект 4)
	# v1.59 (заказчик): лесопилку не ставят вплотную к полям — щепа и пыль
	# портят урожай; правило для игрока и самостроя одинаково
	if type_id == "sawmill" and _farm_zone_near(tile, 2):
		return "city.placement_sawmill_farm"
	match place:
		"ore", "veins":
			# шахта (v1.21) — у жилы, выработки ИЛИ месторождения региона (v1.56)
			if _nature_near_rect(type_id, tile, [map.TILE_ORE, map.TILE_DEADROCK], 2.0) == Vector2i(-1, -1) \
					and not _deposit_near(tile, 2.0):
				return "city.placement_ore"
		"water":
			if not _water_near(tile):
				return "city.placement_water"
		"near_forge":
			# этап 2: кузня «в 1–2 клетках зазора» (здания 2×2 не касаются);
			# руины кузни оружейной не годятся (этап 2, аспект 5)
			var near_f := false
			for b in buildings:
				if not _active(b) or String(b["type"]) != "forge":
					continue
				var g := rects_gap({"type": type_id, "tile": tile}, b)
				if g >= 1 and g <= 2:
					near_f = true
					break
			if not near_f:
				return "city.placement_forge"
		"rock":
			# каменоломня — только у скал (заказчик)
			if _nature_near_rect(type_id, tile, [map.TILE_ROCK, map.TILE_ORE], 2.0) == Vector2i(-1, -1):
				return "city.placement_rock"
	# клетки полей ферм (v1.21) — строить нельзя; v1.23: фермы тоже — новая
	# ферма не отбирает грядки у соседней, её поле распахивается вокруг
	# свободной земли
	var w := bld_w_of_type(type_id)
	for dy in w:
		for dx in w:
			if _tile_in_field_zone(tile + Vector2i(dx, dy)):
				return "city.placement_field"
	# районы (v1.21.1) стали РЕКОМЕНДАЦИЕЙ, не запретом (заказчик, 2026-10-25:
	# «строительство рядом со своим же цветом — всего лишь рекомендация»):
	# игрок ставит здание где хочет, в том числе кладбище — у могил;
	# самострой по-прежнему предпочитает кластеры ветки (_find_autobuild_tile)
	return ""


## Цветовая ветка здания (cat из конфига: living/resource/craft/...).
func _cat_of(type_id: String) -> String:
	for d in cfg.get("buildings", []):
		if String(d.get("id", "")) == type_id:
			return String(d.get("cat", ""))
	return ""


## Клетка занята полем фермы (не любой зоной — пастбище стройке не мешает).
func _tile_in_field_zone(tile: Vector2i) -> bool:
	for z in zones:
		if String(z["type"]) == "field" and (z["cells"] as Array).has(tile):
			return true
	return false


## Сколько построек этого типа стоит (включая стройплощадки).
func _count_type(type_id: String) -> int:
	var n := 0
	for b in buildings:
		if String(b["type"]) == type_id:
			n += 1
	return n


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


## Тайл природы у прямоугольника здания (радиус от КАЖДОЙ клетки, v1.21) —
## так «в радиусе 2 клеток от шахты» честно считается от всего здания.
func _nature_near_rect(type_id: String, tile: Vector2i, kinds: Array, radius: float) -> Vector2i:
	var w := bld_w_of_type(type_id)
	for dy in w:
		for dx in w:
			var found: Vector2i = _nature_near(tile + Vector2i(dx, dy), kinds, radius)
			if found != Vector2i(-1, -1):
				return found
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
		if not _active(b) or not (String(b["type"]) in types):
			continue
		var d: float = Vector2(b["tile"]).distance_to(Vector2(tile))
		if d <= best_d:
			best_d = d
			best = b
	return best


## Запас прочности здания (M5): стены/ворота крепче, остальное — базовое.
## Дисциплина «Оборона» (M7) умножает прочность стен и ворот.
func _bld_max_hp(type_id: String) -> int:
	# v1.21.4: скан конфига закэширован (заводится много раз за кадр из зон,
	# героев и ремонта); исследования меняют только множитель стен — он живой.
	var hp_cfg: Dictionary = cfg.get("threat", {}).get("bld_hp", {})
	if not _bld_hp_cache.has(type_id):
		var def := _def({"type": type_id})
		var base: int = int(hp_cfg.get("default", 20))
		var wall := false
		if not def.is_empty():
			var eff := String(def.get("effect", "default"))
			base = int(hp_cfg.get(eff, base))
			wall = eff == "wall" or eff == "gate"
		_bld_hp_cache[type_id] = [base, wall]
	var cached: Array = _bld_hp_cache[type_id]
	var hp := int(cached[0])
	if bool(cached[1]):
		hp = int(round(float(hp) * research_mult("wall_hp_mult", 1.0)))
	return hp



## Цель достигнута (стройка готова): декор закрывает цель «построить сад».
func _complete_site(site: Dictionary) -> void:
	var worker_id := int(site.get("worker", -1))
	site["done"] = true
	site["progress"] = 0.0
	site["worker"] = -1
	if _def(site).get("mood", 0) != 0 or String(_def(site).get("effect", "")) == "decor":
		_goal_garden_built(worker_id)   # личная цель v3: «построить сад»
	quest_built(String(site["type"]))   # доска объявлений (M14-K)
	if _def(site).get("effect", "") == "wall":
		map.set_solid(site["tile"], true)
		_step_off_solid(site["tile"])
	else:
		# готовое здание — препятствие для всех (этап 2, аспект 2):
		# клетки прямоугольника сплошные, стоявшие на них шагают наружу
		_set_bld_solid(site, true)
		_step_off_bld(site)
	if _def(site).get("effect", "") == "gate":
		_update_gates()   # ворота при достройке сразу закрываются/открываются
	events.append({"type": "built", "bld": String(site["type"])})
	if String(site["type"]) == "farm":
		_make_farm_field(site)   # вокруг фермы распахивается поле (v1.21)
	_assign_jobs()


## Поле фермы (правки v1.21): при достройке фермы вокруг неё распахивается
## поле радиусом farming.field_radius клеток — трава без посторонних строений,
## дорог, пней и чужих зон. На клетках поля строить нельзя; сама ферма может
## стоять вплотную к стене — полю это не мешает.
func _make_farm_field(b: Dictionary) -> void:
	var fcfg: Dictionary = cfg.get("farming", {})
	var radius := int(fcfg.get("field_radius", 2))
	var cells: Array = []
	var progress: Array = []
	var w := bld_w(b)
	var t: Vector2i = b["tile"]
	for dy in range(-radius, w + radius):
		for dx in range(-radius, w + radius):
			var c: Vector2i = t + Vector2i(dx, dy)
			if dx >= 0 and dy >= 0 and dx < w and dy < w:
				continue   # прямоугольник самой фермы
			if not map.in_bounds(c) or c == map.anomaly_tile:
				continue
			if map.grid[c.y][c.x] != map.TILE_GRASS:
				continue   # мешает сторона: вода, скала, дерево, порода
			if map.stumps.has(c) or map.saplings.has(c) or map.logs.has(c) or map.has_road(c) or map.bridges.has(c):
				continue
			if not building_at(c).is_empty() or _tile_in_zone(c):
				continue
			cells.append(c)
			progress.append(0.0)
	if cells.is_empty():
		return
	zones.append({"id": _zone_id, "type": "field", "cells": cells,
			"progress": progress, "crop": "turnip", "crops": [], "farm": int(b["id"])})
	_zone_id += 1
	events.append({"type": "farm_field", "cells": cells.size()})
	_chron("chron.farm_field", str(cells.size()))


## Клетки готового здания сплошные/проходимые (кроме ворот — ими ведёт страж).
func _set_bld_solid(b: Dictionary, solid: bool) -> void:
	if String(_def(b).get("effect", "")) == "gate":
		_update_gates()
		return
	for cell in bld_cells(b):
		map.set_solid(cell, solid)
	_spots_dirty()


## Жители, стоявшие в клетках достроенного здания, шагают на свободного соседа.
func _step_off_bld(b: Dictionary) -> void:
	for cell in bld_cells(b):
		_step_off_solid(cell)


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
