# Часть: дисциплины города, здания 2×2, размещение и стройка.
# Правки структуры v1.20.2: огромный city_sim.gd разбит на extends-цепочку
# частей; это один класс, разложенный по файлам — поведение не меняется.
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
		else:
			return false
	if type_id == "bridge" and map.grid[tile.y][tile.x] != map.TILE_WATER:
		return false   # мост — только на воде
	return building_at(tile).is_empty()


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
	static_dirty = true   # новая плитка дороги — перевыпечь духовку (v1.22)
	return ""


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
	match place:
		"ore", "veins":
			# шахта (v1.21) — у рудной жилы или выработанного массива (радиус 2)
			if _nature_near_rect(type_id, tile, [map.TILE_ORE, map.TILE_DEADROCK], 2.0) == Vector2i(-1, -1):
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
## за other_frac (v1.21.3). "" — успех | "bad" | "full" | "no_res".
func repair_building(b: Dictionary, frac_v := -1.0) -> String:
	if b.is_empty() or not bool(b.get("done", false)):
		return "bad"
	var max_hp := float(_bld_max_hp(String(b["type"])))
	var was_razed := bool(b.get("razed", false))
	if not was_razed and float(b.get("hp", max_hp)) >= max_hp:
		return "full"   # чинить нечего
	var cost := repair_cost(String(b["type"]), frac_v)
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


## Дневной бросок (v1.21.3): город чинит сам. Самое битое здание (сперва
## руины, затем минимум прочности) получает мастера: свободный строитель
## чинит за 50% стоимости, строителя нет — любой непрофильный взрослый
## за 70%. Не по карману — завтра (мастерская лечит медленно бесплатно).
func _roll_city_repair() -> void:
	var rcfg: Dictionary = cfg.get("repair", {})
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
	var repairer := {}
	var frac := 0.0
	for r in residents:
		if String(r["prof"]) == "builder" and r["site"] == null and r["bld"] == null \
				and String(r.get("ail", "")) == "" and int(r.get("repair_bld", 0)) <= 0:
			repairer = r
			frac = float(rcfg.get("builder_frac", 0.5))
			break
	if repairer.is_empty():
		for r in residents:
			var prof := String(r["prof"])
			if prof != "" and prof != "elder" and prof != "builder" \
					and r["site"] == null and r["bld"] == null \
					and String(r.get("ail", "")) == "" and int(r.get("repair_bld", 0)) <= 0:
				repairer = r
				frac = float(rcfg.get("other_frac", 0.7))
				break
	if repairer.is_empty():
		return
	if not can_afford(repair_cost(String(worst["type"]), frac)):
		return   # не по карману — завтра
	repairer["repair_bld"] = int(worst["id"])
	repairer["repair_frac"] = frac


## Поручение города (v1.21.3): житель идёт с инструментом к битому зданию,
## по приходе поднимает его за долю стоимости. False — поручения нет.
func _repair_errand(r: Dictionary, dt: float) -> bool:
	var bid := int(r.get("repair_bld", 0))
	if bid <= 0:
		return false
	var b: Dictionary = {}
	for bb in buildings:
		if int(bb["id"]) == bid:
			b = bb
			break
	var max_hp := float(_bld_max_hp(String(b["type"]))) if not b.is_empty() else 0.0
	if b.is_empty() or not bool(b.get("done", false)) \
			or (not bool(b.get("razed", false)) and float(b.get("hp", max_hp)) >= max_hp):
		r["repair_bld"] = 0   # исчезло или уже починили (герой/мастерская)
		return false
	if not at_bld(r, b):
		r["state"] = "repair"
		_move_towards(r, bld_spot(b), dt)
		return true
	var frac := float(r.get("repair_frac", 0.7))
	r["repair_bld"] = 0
	if not can_afford(repair_cost(String(b["type"]), frac)):
		return true   # дошёл, денег не хватает — завтра снова
	repair_building(b, frac)
	events.append({"type": "city_repaired", "bld": String(b["type"]),
			"name": String(r["name"]), "frac": frac})
	_chron("chron.city_repaired", String(r["name"]), String(b["type"]))
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


