extends SceneTree
## Снимок «Природы 2.0» (v1.39.0): живая вода (озеро/река/болото, пена,
## камыши, рябь) или скалы-утёсы с травяными шапками. Запуск С ГРАФИКОЙ:
##   SHOT_TARGET=water SHOT_SEED=4242 godot --path . --script res://tools/shot_nature2.gd
##   SHOT_TARGET=rocks SHOT_SEED=4242 godot --path . --script res://tools/shot_nature2.gd
## Сохраняет tools/shot_nature2_water.png / tools/shot_nature2_rocks.png.

var _frames := 0
var _game: Node = null
var _city: Node = null
var _target := "water"
var _out := "res://tools/shot_nature2_water.png"
var _center_px := Vector2.ZERO   # центр блоба-цели (в тайлах) — для камеры


func _initialize() -> void:
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		game.name = "Game"
		root.add_child(game)
	var loc: Node = root.get_node_or_null("Loc")
	if loc == null:
		loc = load("res://scripts/loc.gd").new()
		loc.name = "Loc"
		root.add_child(loc)
	_target = OS.get_environment("SHOT_TARGET")
	if _target == "":
		_target = "water"
	_out = "res://tools/shot_nature2_%s.png" % _target
	if OS.get_environment("SHOT_SEED") != "":
		seed(int(OS.get_environment("SHOT_SEED")))
	game.test_mode = true
	game.new_city()
	var city: Node = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	_game = game
	_city = city
	process_frame.connect(_on_frame)


## Найти тайл-якорь: центр крупнейшего водоёма (не болото) или крупнейшей
## скальной гряды; герой встаёт на ближайший сухой тайл, камера отзумится.
func _anchor() -> Vector2i:
	var sim = _game.city_sim
	var map = sim.map
	var is_set: Callable
	if _target == "rocks":
		is_set = func(t: Vector2i) -> bool:
			var g: int = map.grid[t.y][t.x]
			return g == map.TILE_ROCK or g == map.TILE_ORE
	elif _target == "swamp":
		is_set = func(t: Vector2i) -> bool:
			return map.grid[t.y][t.x] == map.TILE_WATER \
					and map.water_kind_at(t) == "swamp"
	else:
		# озеро: компонент воды, где большинство тайлов — lake
		is_set = func(t: Vector2i) -> bool:
			return map.grid[t.y][t.x] == map.TILE_WATER \
					and map.water_kind_at(t) == "lake"
	var seen := {}
	var best: Array = []
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if seen.has(t) or not is_set.call(t):
				continue
			var comp: Array = [t]
			seen[t] = true
			var qi := 0
			while qi < comp.size():
				var c: Vector2i = comp[qi]
				qi += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if map.in_bounds(n) and not seen.has(n) and is_set.call(n):
						seen[n] = true
						comp.append(n)
			if comp.size() > best.size():
				best = comp
	if best.is_empty():
		return Vector2i(-1, -1)
	var sum := Vector2.ZERO
	for t: Vector2i in best:
		sum += Vector2(t)
	var center := sum / float(best.size())
	_center_px = center + Vector2(0.5, 0.5)
	print("shot_nature2: цель=%s tiles=%d center=%s" % [_target, best.size(), center])
	var center_i := Vector2i(int(center.x), int(center.y))
	for r in range(0, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := center_i + Vector2i(dx, dy)
				if map.in_bounds(t) and not is_set.call(t) \
						and map.grid[t.y][t.x] != map.TILE_WATER:
					return t
	return center_i


func _on_frame() -> void:
	_frames += 1
	if _frames == 20:
		var t := _anchor()
		if t.x >= 0:
			var hero = _city.get("hero")
			var map = _game.city_sim.map
			if hero != null:
				hero.position = (Vector2(t) + Vector2(0.5, 0.5)) * map.ts
				var cam: Camera2D = hero.get_node_or_null("Camera")
				if cam != null:
					cam.zoom = Vector2(1.8, 1.8)
					# цель в центре кадра: сдвигаем камеру к центру блоба
					var target_px: Vector2 = _center_px * float(map.ts)
					cam.offset = (target_px - hero.position) * 0.55
				print("shot_nature2: герой у %s" % t)
	if _frames == 30 and OS.get_environment("SHOT_PROBE") != "":
		_probe()
	if _frames < 70:
		return
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(_out)
		print("shot_nature2: сохранён %s" % _out)
	quit(0)


## Дамп тайлов вокруг героя (SHOT_PROBE=1): W вода R скала/руда T дерево
## D выработанная P плато-высота, . трава; в скобках — тип воды.
func _probe() -> void:
	var map = _game.city_sim.map
	var hero = _city.get("hero")
	var ht: Vector2i = Vector2i(int(hero.position.x / map.ts), int(hero.position.y / map.ts))
	for dy in range(-10, 11):
		var row := ""
		for dx in range(-8, 9):
			var t := ht + Vector2i(dx, dy)
			if not map.in_bounds(t):
				row += " ##"
				continue
			var g: int = map.grid[t.y][t.x]
			var ch := "."
			if g == map.TILE_WATER:
				ch = "W"
			elif g == map.TILE_ROCK:
				ch = "R"
			elif g == map.TILE_ORE:
				ch = "O"
			elif g == map.TILE_TREE:
				ch = "T"
			elif g == map.TILE_DEADROCK:
				ch = "D"
			var lv: int = map.height_at(t)
			if lv > 0:
				ch += str(lv)
			if ch == "W":
				ch += "(" + map.water_kind_at(t).left(1) + ")"
			row += " " + ch.rpad(4)
		print("probe %3d:%s" % [ht.y + dy, row])
	quit(0)
