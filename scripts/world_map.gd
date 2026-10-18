extends RefCounted
## Карта мира (M8): процедурная по сиду, биомы цветом, точки интереса (POI),
## туман войны, старые дороги. Чистая логика без сцены — тестируется headless.
## Город игрока — стартовая локация; от него герой выходит на карту и входит назад.
##
## Тайл: 0 равнина, 1 вода (непроходима), 2 лес, 3 холмы, 4 пепел, 5 старая дорога.
## POI: {id, kind, biome, faction, tile, discovered, strength, state,
##       cleared_day, used} — kind: city|dungeon|ruins|camp|settlement|
##       caravan|obelisk; biome — биом данжа из dungeon.json ("" у городской
##       аномалии, она выбирает биом как раньше); faction — traders|bandits|cult.

const TILE_PLAINS := 0
const TILE_WATER := 1
const TILE_FOREST := 2
const TILE_HILL := 3
const TILE_WASTE := 4
const TILE_ROAD := 5

var w := 0
var h := 0
var ts := 32
var cfg: Dictionary = {}
var grid: Array = []
var city_tile := Vector2i.ZERO      # город игрока — стартовая локация
var pois: Array = []                # точки интереса, см. шапку
var fog: Dictionary = {}            # Vector2i -> true: исследованные тайлы
var astar: AStarGrid2D = null
var _rng := RandomNumberGenerator.new()
var _poi_id := 1


## Генерация по сиду: детерминированная (тот же сид — та же карта и POI).
func generate(seed_value: int, params: Dictionary) -> void:
	cfg = params
	w = int(params["map_w"])
	h = int(params["map_h"])
	ts = int(params["tile_size"])
	_rng.seed = seed_value
	for attempt in 20:
		_generate_once(seed_value + attempt * 977, params)
		if _pois_ok():
			break
	_setup_astar()
	_setup_fog()


func _generate_once(seed_value: int, params: Dictionary) -> void:
	_rng.seed = seed_value
	w = int(params["map_w"])
	h = int(params["map_h"])
	grid = []
	for y in h:
		var row := []
		row.resize(w)
		row.fill(TILE_PLAINS)
		grid.append(row)
	# пятна биомов, не у краёв (как озёра и скалы города)
	var blobs: Dictionary = params.get("blobs", {})
	var radii: Dictionary = params.get("blob_radius", {})
	var kinds := {"forest": TILE_FOREST, "hills": TILE_HILL, "waste": TILE_WASTE, "water": TILE_WATER}
	for key in blobs:
		for i in int(blobs[key]):
			var r: Array = radii.get(key, [3, 5])
			_blob(_random_inner_tile(), _rng.randi_range(int(r[0]), int(r[1])), kinds[key])
	# город в центре, вокруг чистая равнина
	city_tile = Vector2i(w / 2, h / 2)
	_clear_around(city_tile, 3)
	pois = []
	_poi_id = 1
	_place_pois(params)
	_draw_roads()


## Пятна круглой формы (как в city_map.gd).
func _blob(center: Vector2i, radius: int, kind: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if Vector2(x, y).distance_to(Vector2(center)) <= radius:
				grid[y][x] = kind


func _clear_around(center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x >= 0 and y >= 0 and x < w and y < h:
				grid[y][x] = TILE_PLAINS


func _random_inner_tile() -> Vector2i:
	return Vector2i(_rng.randi_range(4, w - 5), _rng.randi_range(4, h - 5))


## Случайный проходимый тайл (страховка генерации POI).
func _walkable_random() -> Vector2i:
	for attempt in 300:
		var p := _random_inner_tile()
		if is_walkable(p):
			return p
	return city_tile


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


func is_walkable(p: Vector2i) -> bool:
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


## Цена тайла для времени пути (биом; дорога быстрее равнины).
func tile_cost(p: Vector2i) -> float:
	if not is_walkable(p):
		return 0.0
	var biomes: Dictionary = cfg["biomes"]
	match grid[p.y][p.x]:
		TILE_PLAINS: return float(biomes["plains"]["cost"])
		TILE_FOREST: return float(biomes["forest"]["cost"])
		TILE_HILL: return float(biomes["hills"]["cost"])
		TILE_WASTE: return float(biomes["waste"]["cost"])
		TILE_ROAD: return float(biomes["road"]["cost"])
	return 1.0


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
	d = dist_cfg.get("dragon_castle", [20, 36])
	_place_kind("dragon_castle", "dragon_lair", int(d[0]), int(d[1]), int(pconf.get("dragon_castles", 0)))
	# стартовые силы из конфига
	var strengths: Dictionary = params.get("sim", {}).get("start_strength", {})
	for poi in pois:
		match String(poi["kind"]):
			"camp", "settlement":
				poi["strength"] = float(strengths.get("camp" if String(poi["kind"]) == "camp" else "settlement", 6.0))
			"dragon_castle":
				poi["strength"] = float(strengths.get("dragon_castle", 12.0))
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
func _find_spot(dmin: int, dmax: int) -> Vector2i:
	for attempt in 300:
		var p := _random_inner_tile()
		var dist := int(Vector2(p).distance_to(Vector2(city_tile)))
		if dist < dmin or dist > dmax or not is_walkable(p):
			continue
		if _poi_near(p, 4) != null:
			continue
		return p
	# страховка: ослабляем требование разрежения
	for attempt in 300:
		var p := _random_inner_tile()
		if Vector2(p).distance_to(Vector2(city_tile)) >= float(dmin) and is_walkable(p) and _poi_near(p, 2) == null:
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
	# город+аномалия+6 данжей+3 поселения+караван+гуляй-город+3 руины+4 лагеря+2 обелиска+замок дракона
	var expected := 1 + 1 + 6 + 3 + 1 + 1 + 3 + 4 + 2 \
			+ int(cfg.get("pois", {}).get("dragon_castles", 0))
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
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and Vector2(p).distance_to(Vector2(center)) <= float(radius):
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

func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(ts, ts)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if not is_walkable(p):
				astar.set_point_solid(p, true)
				continue
			astar.set_point_weight_scale(p, tile_cost(p))


## Тайлы пути от тайла к тайлу (по воде не пройти). Пустой — пути нет.
func tile_path(from: Vector2i, to: Vector2i) -> Array:
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
	if in_bounds(p) and is_walkable(p) and p != city_tile:
		grid[p.y][p.x] = TILE_ROAD
