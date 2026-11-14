# Часть: карта мира — POI (данжи/руины/лагеря/замки), туман войны, эпицентр
# катастрофы, A* и пути. Корень цепочки: load("res://scripts/world_map.gd").
extends "res://scripts/world_map_gen.gd"

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


func is_walkable(p: Vector2i) -> bool:
	if boats_enabled and in_bounds(p) and grid[p.y][p.x] == TILE_WATER:
		return true   # лодка (M14-I): вода — медленный, но проходимый путь
	return in_bounds(p) and grid[p.y][p.x] != TILE_WATER


## Ближайший проходимый тайл (спираль до радиуса 4); фолбэк — город.
func nearest_walkable(tile: Vector2i) -> Vector2i:
	if is_walkable(tile):
		return tile
	for radius in range(1, 5):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := tile + Vector2i(dx, dy)
				if is_walkable(t):
					return t
	return city_tile


## Цена тайла для времени пути (биом; дорога быстрее равнины). Русло —
## брод: дороже равнины, но проходим (река на глобали не режет пути).
func tile_cost(p: Vector2i) -> float:
	if not is_walkable(p):
		return 0.0
	var cost := 0.0
	if river.has(p):
		cost = float(cfg.get("biomes", {}).get("river", {}).get("cost", 1.4))
	else:
		var biomes: Dictionary = cfg["biomes"]
		match grid[p.y][p.x]:
			TILE_PLAINS: cost = float(biomes["plains"]["cost"])
			TILE_FOREST: cost = float(biomes["forest"]["cost"])
			TILE_HILL: cost = float(biomes["hills"]["cost"])
			TILE_WASTE: cost = float(biomes["waste"]["cost"])
			TILE_ROAD: cost = float(biomes["road"]["cost"])
			TILE_SWAMP: cost = float(biomes.get("swamp", {}).get("cost", 2.5))
	# регион дорожает путь (снег/вулкан/пустыня/мёртвель — суровая земля)
	var rd: Dictionary = region_def(region_at(p))
	if not rd.is_empty():
		cost *= float(rd.get("cost_mult", 1.0))
	return cost


# --- точки интереса -------------------------------------------------------

func _place_pois(params: Dictionary) -> void:
	var pconf: Dictionary = params.get("pois", {})
	var dist_cfg: Dictionary = params.get("distances", {})
	# город — всегда
	_add_poi("city", "", "", city_tile)
	# городская аномалия — ближайший данж (старый вход сохранён, пункт плана M8)
	var d: Array = dist_cfg.get("city_dungeon", [3, 5])
	_place_kind("dungeon", "", int(d[0]), int(d[1]), 1)
	# аномалии-данжи: по одной на каждый биом данжей (M7)
	var biome_list: Array = pconf.get("dungeon_biomes", [])
	d = dist_cfg.get("dungeon", [12, 30])
	for biome_id: String in biome_list:
		var poi := _place_kind("dungeon", biome_id, int(d[0]), int(d[1]), 1)
		if poi.is_empty():
			_add_poi("dungeon", biome_id, "", _walkable_random())
	# поселения фракций (M8: торговцы, культ; бандиты живут в лагерях)
	d = dist_cfg.get("settlement", [10, 20])
	for faction: String in pconf.get("settlements", []):
		var poi2 := _place_kind("settlement", "", int(d[0]), int(d[1]), 1, faction)
		if poi2.is_empty():
			_add_poi("settlement", "", faction, _walkable_random())
	# караван/лагерь торговцев
	d = dist_cfg.get("caravan", [8, 18])
	_place_kind("caravan", "", int(d[0]), int(d[1]), int(pconf.get("caravans", 1)), "traders")
	# лагерь торговцев «гуляй-город» (M10): телеги по кругу, торговля на месте
	d = dist_cfg.get("trade_camp", [6, 14])
	_place_kind("trade_camp", "", int(d[0]), int(d[1]), int(pconf.get("trade_camps", 1)), "traders")
	# руины, лагеря бандитов, обелиски
	d = dist_cfg.get("ruins", [8, 26])
	_place_kind("ruins", "", int(d[0]), int(d[1]), int(pconf.get("ruins", 3)))
	d = dist_cfg.get("camp", [8, 24])
	_place_kind("camp", "", int(d[0]), int(d[1]), int(pconf.get("camps", 4)), "bandits")
	d = dist_cfg.get("obelisk", [18, 34])
	_place_kind("obelisk", "", int(d[0]), int(d[1]), int(pconf.get("obelisks", 2)))
	# замок дракона (вишлист M13): один дальний, логово-биом и сокровищница
	# v1.57: БИОМ СМЕРТИ — крипты жмутся к замкам вампира/лича (нежить
	# гнездится у своих владений); числа — расстояния от замков
	for keep in pois:
		if String(keep["kind"]) in ["vampire_keep", "lich_tower"]:
			for i in 1:
				var near := _walkable_near(keep["tile"], 3, 6)
				if near != Vector2i(-1, -1) and _poi_near(near, 2) == null:
					_add_poi("dungeon", "midnight_crypt", "", near)
	d = dist_cfg.get("dragon_castle", [20, 36])
	_place_kind("dragon_castle", "dragon_lair", int(d[0]), int(d[1]), int(pconf.get("dragon_castles", 0)))
	# замок вампира и башня лича (M14-D): уникальные тёмные POI
	d = dist_cfg.get("vampire_keep", [20, 34])
	_place_kind("vampire_keep", "vampire_keep", int(d[0]), int(d[1]), int(pconf.get("vampire_keeps", 1)))
	d = dist_cfg.get("lich_tower", [16, 30])
	_place_kind("lich_tower", "lich_tower", int(d[0]), int(d[1]), int(pconf.get("lich_towers", 1)))
	# стартовые силы из конфига
	var strengths: Dictionary = params.get("sim", {}).get("start_strength", {})
	for poi in pois:
		match String(poi["kind"]):
			"camp", "settlement":
				poi["strength"] = float(strengths.get("camp" if String(poi["kind"]) == "camp" else "settlement", 6.0))
			"dragon_castle":
				poi["strength"] = float(strengths.get("dragon_castle", 12.0))
			"vampire_keep", "lich_tower":
				poi["strength"] = float(strengths.get(String(poi["kind"]), 13.0))
			"dungeon", "ruins":
				poi["strength"] = float(strengths.get("dungeon" if String(poi["kind"]) == "dungeon" else "ruins", 5.0))


## Добавить POI на точный тайл (город, страховки генерации).
func _add_poi(kind: String, biome: String, faction: String, tile: Vector2i) -> Dictionary:
	var poi := {
		"id": _poi_id, "kind": kind, "biome": biome, "faction": faction,
		"tile": tile, "discovered": kind == "city",
		"strength": 0.0, "state": "ok", "cleared_day": -1, "used": false,
	}
	_poi_id += 1
	pois.append(poi)
	return poi


## Разместить count POI на подходящих тайлах; возвращает последний или {}.
func _place_kind(kind: String, biome: String, dmin: int, dmax: int, count: int, faction := "") -> Dictionary:
	var last: Dictionary = {}
	for i in count:
		var tile := _find_spot(dmin, dmax)
		if tile == Vector2i(-1, -1):
			return last
		last = _add_poi(kind, biome, faction, tile)
	return last


## Свободный проходимый тайл в кольце расстояний от города, подальше от прочих POI.
## v2: не на русло реки (POI на берегу, не посреди брода).
func _find_spot(dmin: int, dmax: int) -> Vector2i:
	for attempt in 300:
		var p := _random_inner_tile()
		var dist := int(Vector2(p).distance_to(Vector2(city_tile)))
		if dist < dmin or dist > dmax or not is_walkable(p) or river.has(p):
			continue
		if _poi_near(p, 4) != null:
			continue
		return p
	# страховка: ослабляем требование разрежения
	for attempt in 300:
		var p := _random_inner_tile()
		if Vector2(p).distance_to(Vector2(city_tile)) >= float(dmin) and is_walkable(p) \
				and not river.has(p) and _poi_near(p, 2) == null:
			return p
	return Vector2i(-1, -1)


## Проходимая клетка в кольце [rmin..rmax] от центра (для гнездований POI).
func _walkable_near(center: Vector2i, rmin: int, rmax: int) -> Vector2i:
	for dy in range(-rmax, rmax + 1):
		for dx in range(-rmax, rmax + 1):
			var d := int(Vector2(dx, dy).length())
			if d < rmin or d > rmax:
				continue
			var p := center + Vector2i(dx, dy)
			if in_bounds(p) and is_walkable(p) and not river.has(p) and _poi_near(p, 2) == null:
				return p
	return Vector2i(-1, -1)


func _poi_near(tile: Vector2i, radius: float):
	for poi in pois:
		if Vector2(poi["tile"]).distance_to(Vector2(tile)) <= radius:
			return poi
	return null


## Все POI на суше и не слиплись (связность проверяется тестами по путям).
func _pois_ok() -> bool:
	if pois.is_empty():
		return false
	for poi in pois:
		if not is_walkable(poi["tile"]):
			return false
	# город+аномалия+данжи биомов+3 поселения+караван+гуляй-город+3 руины
	# +4 лагеря+2 обелиска+замок дракона+замок вампира+башня лича
	var expected := 1 + 1 + int(cfg.get("pois", {}).get("dungeon_biomes", []).size()) + 3 + 1 + 1 \
			+ 3 + 4 + 2 + int(cfg.get("pois", {}).get("dragon_castles", 0)) \
			+ int(cfg.get("pois", {}).get("vampire_keeps", 1)) + int(cfg.get("pois", {}).get("lich_towers", 1))
	return pois.size() >= expected


func poi_at(tile: Vector2i) -> Dictionary:
	for poi in pois:
		if poi["tile"] == tile:
			return poi
	return {}


func poi_by_id(poi_id: int) -> Dictionary:
	for poi in pois:
		if int(poi["id"]) == poi_id:
			return poi
	return {}


# --- туман войны ----------------------------------------------------------

func _setup_fog() -> void:
	fog = {}
	reveal_around(city_tile, int(cfg.get("city_reveal_radius", 9)))


## Открыть круг тайлов; попавшие в круг POI становятся найденными.
func reveal_around(center: Vector2i, radius: int) -> void:
	fog_ver += 1
	# fog_new накапливается до разбора view'ом (параллельные раскрытия —
	# следы симуляции, обелиски — не теряют тайлы стирания)
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and Vector2(p).distance_to(Vector2(center)) <= float(radius):
				if not fog.has(p):
					fog_new.append(p)
				fog[p] = true
	for poi in pois:
		if not bool(poi["discovered"]) \
				and Vector2(poi["tile"]).distance_to(Vector2(center)) <= float(radius) + 1.0:
			poi["discovered"] = true


func is_explored(p: Vector2i) -> bool:
	return fog.has(p)


## Найденные карты и обелиски (ответ №24): открыть count далёких мест.
## Возвращает открытые POI.
func reveal_far(count: int) -> Array:
	var hidden: Array = []
	for poi in pois:
		if not bool(poi["discovered"]):
			hidden.append(poi)
	hidden.shuffle()
	var opened: Array = []
	for poi: Dictionary in hidden:
		if opened.size() >= count:
			break
		poi["discovered"] = true
		reveal_around(poi["tile"], 4)
		opened.append(poi)
	return opened


# --- пути и время пути (дни) ----------------------------------------------

## Эпицентр катастрофы: суша подальше от города игрока и всех поселений
## (директива: «не может быть слишком рядом к поселениям»).
func _place_epicenter() -> void:
	var ecfg: Dictionary = cfg.get("catastrophe", {})
	var radius := float(ecfg.get("radius", 14))
	var min_sett := int(ecfg.get("min_settlement_dist", 40))
	var cands: Array = []
	for y in range(int(h * 0.1), h - int(h * 0.1), 3):
		for x in range(int(w * 0.1), w - int(w * 0.1), 3):
			var t := Vector2i(x, y)
			if not is_walkable(t):
				continue
			if t.distance_to(city_tile) < min_sett:
				continue
			var ok := true
			for poi in pois:
				if String(poi["kind"]) == "settlement" 						and Vector2(t).distance_to(Vector2(poi["tile"])) < min_sett:
					ok = false
					break
			if ok:
				cands.append(t)
	if cands.is_empty():
		return
	var tile: Vector2i = cands[_rng.randi_range(0, cands.size() - 1)]
	epicenter = {"tile": tile, "radius": radius, "power": 0,
			"next_event_day": int(ecfg.get("eruption_days", 25)),
			"eruption_days": int(ecfg.get("eruption_days", 25))}
	# лагерь искажённых рядом (3-6 тайлов): фракция культа, биом проклятый
	for attempt in 30:
		var off := Vector2i(_rng.randi_range(-7, 7), _rng.randi_range(-7, 7))
		var t: Vector2i = tile + off
		if is_walkable(t) and t.distance_to(tile) >= 3:
			_place_kind("twisted", "cursed_hall", 3, 6, 1, "twisted")
			break


func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(ts, ts)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	# v1.43 (карта ×5): вызовы AStarGrid2D только для ОТКЛОНЕНИЙ от дефолта
	# (сплошные/дорогие тайлы) — на 93к тайлах это вдвое-втрое быстрее
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if not is_walkable(p):
				astar.set_point_solid(p, true)
				continue
			var cost := tile_cost(p)
			if cost > 1.001:
				astar.set_point_weight_scale(p, cost)


## Лодки (M14-I): вода становится проходимой (медленной) — пересборка путей.
func set_boats(on: bool) -> void:
	if boats_enabled == on:
		return
	boats_enabled = on
	_setup_astar()
	astar_ready = true


## Тайлы пути от тайла к тайлу (по воде не пройти). Пустой — пути нет.
func tile_path(from: Vector2i, to: Vector2i) -> Array:
	if not astar_ready:
		_setup_astar()
		astar_ready = true
	if not in_bounds(from) or not in_bounds(to) or not is_walkable(to):
		return []
	return astar.get_id_path(from, to)


## Время пути в днях: сумма цен тайлов маршрута / тайлов за день, минимум 1.
## Расстояние и биом влияют на дни, старые дороги ускоряют (пункт плана M8).
func travel_days(from: Vector2i, to: Vector2i) -> int:
	var path := tile_path(from, to)
	if path.is_empty():
		return 0
	var cost := 0.0
	for i in range(1, path.size()):
		cost += tile_cost(path[i])
	var per_day: float = float(cfg.get("tiles_per_day", 22.0))
	return maxi(1, int(ceilf(cost / maxf(1.0, per_day))))


func tile_center_px(p: Vector2i) -> Vector2:
	return Vector2(p.x * ts + ts / 2.0, p.y * ts + ts / 2.0)


func tile_of_px(px: Vector2) -> Vector2i:
	return Vector2i(px / ts)


# --- старые дороги ---------------------------------------------------------

## Дороги от города к поселениям (L-образные старые тракты; вода прерывает).
func _draw_roads() -> void:
	for poi in pois:
		if String(poi["kind"]) != "settlement":
			continue
		_road_l(city_tile, poi["tile"])


func _road_l(from: Vector2i, to: Vector2i) -> void:
	var p := from
	while p.x != to.x:
		p.x += 1 if to.x > p.x else -1
		_set_road(p)
	while p.y != to.y:
		p.y += 1 if to.y > p.y else -1
		_set_road(p)


func _set_road(p: Vector2i) -> void:
	# v2: через реку дорога не кладётся (переправа — не тракт)
	if in_bounds(p) and is_walkable(p) and p != city_tile and not river.has(p):
		grid[p.y][p.x] = TILE_ROAD
