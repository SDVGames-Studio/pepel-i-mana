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
var start_tile := Vector2i.ZERO
var exit_tile := Vector2i.ZERO

var _rng := RandomNumberGenerator.new()


## Генерирует данж по параметрам из data/dungeon.json. Возвращает self.
func generate(seed_value: int, params: Dictionary) -> "DungeonGen":
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

	_place_rooms(params)
	_carve_corridors()
	_pick_start_and_exit()
	_place_spawns(params)
	return self


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


## Враги, сундуки и кристаллы — на свободные тайлы пола вне стартовой комнаты.
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
