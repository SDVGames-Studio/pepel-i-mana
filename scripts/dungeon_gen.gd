extends RefCounted
## Генератор данжа-прототипа (этап M1): комнаты + L-коридоры, биом «руины».
## Детерминирован по seed. Чистая логика без узлов — тестируется headless.

const TILE_WALL := 0
const TILE_FLOOR := 1

var w := 0
var h := 0
var grid: Array = []            # grid[y][x] -> TILE_*
var rooms: Array = []           # [{x, y, w, h}]
var enemy_spawns: Array = []    # Vector2i (тайлы)
var chest_spawns: Array = []
var crystal_spawns: Array = []
var trap_spawns: Array = []     # {tile, kind} — ловушки M7
var start_tile := Vector2i.ZERO
var exit_tile := Vector2i.ZERO
# «Данжи v2» (v1.42, свет/материалы): жаровни на стенах комнат, холодные
# лужи, рунные круги, «порченые» комнаты (порча-оверлей + красные трещины)
var brazier_spawns: Array = []  # Vector2i (тайл пола у стены)
var puddle_zones: Array = []    # Array[Vector2i] — кластер тайлов лужи
var rune_spawns: Array = []     # Vector2i (центр комнаты)
var corrupt_rooms: Array = []   # индексы комнат со «пепельной порчей»

var _rng := RandomNumberGenerator.new()


## Генерирует данж по параметрам из data/dungeon.json. Возвращает self.
func generate(seed_value: int, params: Dictionary) -> Object:
	w = int(params["map_w"])
	h = int(params["map_h"])
	_rng.seed = seed_value
	grid = []
	for y in h:
		var row: Array = []
		row.resize(w)
		row.fill(TILE_WALL)
		grid.append(row)
	rooms = []
	enemy_spawns = []
	chest_spawns = []
	crystal_spawns = []
	trap_spawns = []
	brazier_spawns = []
	puddle_zones = []
	rune_spawns = []
	corrupt_rooms = []

	_place_rooms(params)
	_carve_corridors()
	_pick_start_and_exit()
	_place_spawns(params)
	_place_v2_spots(params)
	return self


## «Данжи v2»: жаровни/лужи/руны/порча (свет и материалы этапа 4 «Мир v2»).
## Параметры — dungeon.json → v2 (counts/min-max, для малых локаций — та же
## пропорция, что остальному). Всё детерминировано от seed генератора.
func _place_v2_spots(params: Dictionary) -> void:
	var v2: Dictionary = params.get("v2", {})
	var used := {}   # занятые тайлы (пересечение с прочими спотами не критично,
	used[start_tile] = true   # но руны/жаровни не должны совпасть)
	var shuffled := _shuffled_range(rooms.size())
	shuffled = shuffled.filter(func(i: int) -> bool: return i != 0)
	# 1) порченые комнаты («пепельная порча» — оверлей по референсу 5f017950):
	#    не стартовая, дальше по списку перемешанных
	var c_max := _v2_count(v2, "corrupt_rooms", rooms.size() - 1)
	for i in shuffled:
		if corrupt_rooms.size() >= c_max:
			break
		corrupt_rooms.append(i)
	# 2) жаровни: тайл пола у стены комнаты. Первая — ВСЕГДА в стартовой
	#    (герой сразу видит игру света «тёплый огонь + холодная тьма»),
	#    дальше по комнатам; в порченых огонь выжжен — там красное свечение
	var all_rooms := _shuffled_range(rooms.size())
	var b_max := maxi(_v2_count(v2, "braziers", rooms.size()), 1)
	var start_p := _brazier_in_room(rooms[0], used)
	if start_p != Vector2i(-1, -1):
		brazier_spawns.append(start_p)
		used[start_p] = true
	for i in all_rooms:
		if brazier_spawns.size() >= b_max:
			break
		if i == 0 or corrupt_rooms.has(i):
			continue
		var p := _brazier_in_room(rooms[i], used)
		if p != Vector2i(-1, -1):
			brazier_spawns.append(p)
			used[p] = true
	# 3) руны: центры комнат (не старт), не в порченых — порча съедает магию
	var r_max := _v2_count(v2, "runes", rooms.size() - 1)
	for i in shuffled:
		if rune_spawns.size() >= r_max:
			break
		if corrupt_rooms.has(i):
			continue
		var c := room_center(rooms[i])
		if used.has(c) or c == exit_tile:
			continue
		rune_spawns.append(c)
		used[c] = true
	# 4) лужи: кластеры 3-6 соседних тайлов пола (комнаты и коридоры)
	var p_max := _v2_count(v2, "puddles", 3)
	var guard := 0
	while puddle_zones.size() < p_max and guard < p_max * 60:
		guard += 1
		var seed_tile := Vector2i(_rng.randi_range(1, w - 2), _rng.randi_range(1, h - 2))
		if not is_floor(seed_tile) or used.has(seed_tile) \
				or seed_tile.distance_to(start_tile) < 4:
			continue
		var zone := _grow_puddle(seed_tile)
		if zone.is_empty():
			continue
		var clash := false
		for t in zone:
			if used.has(t):
				clash = true
				break
		if clash:
			continue
		puddle_zones.append(zone)
		for t in zone:
			used[t] = true


## Перемешанный 0..n-1 СВОИМ ГПСЧ (Array.shuffle() мешает глобальным
## рандомом — ломает воспроизводимость по сиду).
func _shuffled_range(n: int) -> Array:
	var arr := range(n)
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


## Число из v2-конфига (min..max), урезанное до lim (комнат/мест столько-то).
func _v2_count(v2: Dictionary, key: String, lim: int) -> int:
	var box: Dictionary = v2.get(key, {})
	var n := _rng.randi_range(int(box.get("min", 1)), int(box.get("max", 2)))
	return mini(n, lim)


## Жаровня в комнате: пол рядом со стеной (северная стена комнаты — свет
## «висит» на видимой грани, как факелы на референсах).
func _brazier_in_room(room: Dictionary, used: Dictionary) -> Vector2i:
	var rx := int(room["x"])
	var ry := int(room["y"])
	var rw := int(room["w"])
	var rh := int(room["h"])
	for attempt in 6:
		var px := _rng.randi_range(rx, rx + rw - 1)
		var py := ry + _rng.randi_range(0, 1)
		var p := Vector2i(px, py)
		if is_floor(p) and not used.has(p):
			return p
	var fallback := Vector2i(rx + rw / 2, ry)
	return fallback if is_floor(fallback) and not used.has(fallback) else Vector2i(-1, -1)


## Кластер тайлов лужи: от seed-тайла случайное блуждание по полу.
func _grow_puddle(seed_tile: Vector2i) -> Array:
	var target := 3 + _rng.randi_range(0, 3)
	var zone: Array = [seed_tile]
	var seen := {seed_tile: true}
	var guard := 0
	while zone.size() < target and guard < target * 12:
		guard += 1
		var from: Vector2i = zone[_rng.randi_range(0, zone.size() - 1)]
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var to: Vector2i = from + dirs[_rng.randi_range(0, 3)]
		if not is_floor(to) or seen.has(to):
			continue
		seen[to] = true
		zone.append(to)
	if zone.size() < 2:
		return []
	return zone


func tile_at(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
		return TILE_WALL
	return grid[p.y][p.x]


func is_floor(p: Vector2i) -> bool:
	return tile_at(p) == TILE_FLOOR


## Центр комнаты в тайлах (Vector2i).
static func room_center(r: Dictionary) -> Vector2i:
	return Vector2i(int(r["x"]) + int(r["w"]) / 2, int(r["y"]) + int(r["h"]) / 2)


func _place_rooms(params: Dictionary) -> void:
	var min_s := int(params["room_min"])
	var max_s := int(params["room_max"])
	var attempts := int(params["room_attempts"])
	for i in attempts:
		if rooms.size() >= int(params["max_rooms"]):
			return
		var rw := _rng.randi_range(min_s, max_s)
		var rh := _rng.randi_range(min_s, max_s)
		var rx := _rng.randi_range(1, w - rw - 2)
		var ry := _rng.randi_range(1, h - rh - 2)
		var room := {"x": rx, "y": ry, "w": rw, "h": rh}
		if _overlaps(room):
			continue
		rooms.append(room)
		_carve_room(room)


func _overlaps(room: Dictionary) -> bool:
	for other in rooms:
		if int(room["x"]) < int(other["x"]) + int(other["w"]) + 1 \
				and int(room["x"]) + int(room["w"]) + 1 > int(other["x"]) \
				and int(room["y"]) < int(other["y"]) + int(other["h"]) + 1 \
				and int(room["y"]) + int(room["h"]) + 1 > int(other["y"]):
			return true
	return false


func _carve_room(r: Dictionary) -> void:
	for y in range(int(r["y"]), int(r["y"]) + int(r["h"])):
		for x in range(int(r["x"]), int(r["x"]) + int(r["w"])):
			grid[y][x] = TILE_FLOOR


## Соединяет комнаты цепочкой L-образными коридорами (связность гарантирована).
func _carve_corridors() -> void:
	for i in range(1, rooms.size()):
		var a := room_center(rooms[i - 1])
		var b := room_center(rooms[i])
		if _rng.randi_range(0, 1) == 0:
			_carve_h(a.x, b.x, a.y)
			_carve_v(a.y, b.y, b.x)
		else:
			_carve_v(a.y, b.y, a.x)
			_carve_h(a.x, b.x, b.y)


func _carve_h(x1: int, x2: int, y: int) -> void:
	for x in range(mini(x1, x2), maxi(x1, x2) + 1):
		grid[y][x] = TILE_FLOOR


func _carve_v(y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		grid[y][x] = TILE_FLOOR


## Старт — центр первой комнаты; выход — центр самой дальней комнаты.
func _pick_start_and_exit() -> void:
	start_tile = room_center(rooms[0])
	var best_d := -1
	exit_tile = start_tile
	for i in range(1, rooms.size()):
		var c := room_center(rooms[i])
		var d := absi(c.x - start_tile.x) + absi(c.y - start_tile.y)
		if d > best_d:
			best_d = d
			exit_tile = c


## Враги, сундуки, кристаллы и ловушки (M7) — на свободные тайлы пола вне стартовой комнаты.
func _place_spawns(params: Dictionary) -> void:
	var start_room: Dictionary = rooms[0]
	var used := {start_tile: true}
	var counts := {
		"enemies": int(params["enemy_count"]),
		"chests": int(params["chest_count"]),
		"crystals": int(params["crystal_count"]),
	}
	var lists := {
		"enemies": enemy_spawns,
		"chests": chest_spawns,
		"crystals": crystal_spawns,
	}
	for kind in ["enemies", "chests", "crystals"]:
		var placed := 0
		var guard := 0
		while placed < counts[kind] and guard < counts[kind] * 200:
			guard += 1
			var room: Dictionary = rooms[_rng.randi_range(1, rooms.size() - 1)]
			var p := Vector2i(
				_rng.randi_range(int(room["x"]), int(room["x"]) + int(room["w"]) - 1),
				_rng.randi_range(int(room["y"]), int(room["y"]) + int(room["h"]) - 1))
			if p == exit_tile or used.has(p) or not is_floor(p):
				continue
			used[p] = true
			lists[kind].append(p)
			placed += 1
	# ловушки: в коридоры и комнаты, тип — случайный из разрешённых (M7)
	var trap_cfg: Dictionary = params.get("traps", {})
	var kinds: Array = trap_cfg.get("types", [])
	if kinds.is_empty():
		return
	var placed_traps := 0
	var guard := 0
	while placed_traps < int(trap_cfg.get("count", 0)) and guard < int(trap_cfg.get("count", 0)) * 200:
		guard += 1
		var room: Dictionary = rooms[_rng.randi_range(1, rooms.size() - 1)]
		var p := Vector2i(
			_rng.randi_range(int(room["x"]), int(room["x"]) + int(room["w"]) - 1),
			_rng.randi_range(int(room["y"]), int(room["y"]) + int(room["h"]) - 1))
		if p == exit_tile or used.has(p) or not is_floor(p):
			continue
		used[p] = true
		trap_spawns.append({"tile": p, "kind": String(kinds[_rng.randi_range(0, kinds.size() - 1)])})
		placed_traps += 1
