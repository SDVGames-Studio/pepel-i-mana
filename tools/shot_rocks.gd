extends SceneTree
## Снимок скальной гряды (v1.37.0, поручение приёмки: «скалы — так же,
## как плато»). Запуск С ГРАФИКОЙ:
##   SHOT_SEED=4242 godot --path . --script res://tools/shot_rocks.gd
## Телепортирует героя к крупнейшей гряде (южнее центра — видны срез
## кромки, тень и зелень на вершине), сохраняет tools/shot_rocks.png.

var _frames := 0
var _game: Node = null
var _city: Node = null


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
	if OS.get_environment("SHOT_SEED") != "":
		seed(int(OS.get_environment("SHOT_SEED")))
	game.test_mode = true
	game.new_city()
	var city: Node = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	_game = game
	_city = city
	process_frame.connect(_on_frame)


## Крупнейшая связная гряда (ROCK/ORE); герой — на траве ЮЖНЕЕ центра
## гряды: южный срез с тенью смотрит «в камеру».
func _goto_rocks(city: Node, game: Node) -> void:
	var sim = game.city_sim
	var map = sim.map
	var seen := {}
	var best: Array = []
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			var g: int = map.grid[y][x]
			if (g != map.TILE_ROCK and g != map.TILE_ORE) or seen.has(t):
				continue
			var comp: Array = [t]
			seen[t] = true
			var qi := 0
			while qi < comp.size():
				var cc: Vector2i = comp[qi]
				qi += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cc + d
					var g2: int = map.grid[n.y][n.x] if map.in_bounds(n) else -1
					if map.in_bounds(n) and not seen.has(n) \
							and (g2 == map.TILE_ROCK or g2 == map.TILE_ORE):
						seen[n] = true
						comp.append(n)
			if comp.size() > best.size():
				best = comp
	if best.is_empty():
		print("shot_rocks: гряд на карте нет")
		quit(1)
		return
	# самая южная точка гряды + 2 тайла вниз — камера смотрит на срез
	var south: Vector2i = best[0]
	for t: Vector2i in best:
		if t.y > south.y:
			south = t
	var hero = city.get("hero")
	if hero == null:
		print("shot_rocks: героя нет")
		return
	var stand := south + Vector2i(0, 2)
	if not map.is_nature_walkable(stand):
		stand = map.nearest_walkable(stand)
	hero.position = (Vector2(stand) + Vector2(0.5, 0.5)) * map.ts
	var cam: Camera2D = hero.get_node_or_null("Camera")
	if cam != null:
		cam.zoom = Vector2(2.4, 2.4)
	print("shot_rocks: гряда %d тайлов, герой у южного среза %s" % [best.size(), stand])


func _on_frame() -> void:
	_frames += 1
	if _frames == 20:
		_goto_rocks(_city, _game)
	if _frames < 70:
		return
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("res://tools/shot_rocks.png")
		print("shot_rocks: сохранён tools/shot_rocks.png")
	quit(0)
