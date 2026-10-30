extends SceneTree
## Снимок плато города (v1.36, этап «Многоуровневый рельеф»). Запуск
## С ГРАФИКОЙ: SHOT_SEED=4242 godot --path . --script res://tools/shot_plateau.gd
## Телепортирует героя к крупнейшему плато (уровень 1/2, лестница в кадре),
## ждёт выпечки ландшафта, сохраняет tools/shot_plateau.png и выходит.

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


## Крупнейшая связная область высоты>0; герой — у её лестницы (видны
## кромка-срез, ступени и тень у подножия).
func _goto_plateau(city: Node, game: Node) -> void:
	var sim = game.city_sim
	var map = sim.map
	var seen := {}
	var best: Array = []
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if map.height_at(t) == 0 or seen.has(t):
				continue
			var comp: Array = [t]
			seen[t] = true
			var qi := 0
			while qi < comp.size():
				var c: Vector2i = comp[qi]
				qi += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if map.in_bounds(n) and map.height_at(n) > 0 and not seen.has(n):
						seen[n] = true
						comp.append(n)
			if comp.size() > best.size():
				best = comp
	if best.is_empty():
		print("shot_plateau: плато на карте нет (плохой сид?)")
		quit(1)
		return
	var lv2 := 0
	var stair: Vector2i = Vector2i(-1, -1)
	for t: Vector2i in best:
		if map.height_at(t) == 2:
			lv2 += 1
		if stair.x < 0 and map.is_stair(t):
			stair = t
	print("shot_plateau: плато %d тайлов, терраса %d, лестница %s"
			% [best.size(), lv2, stair])
	var hero = city.get("hero")
	if hero == null or stair.x < 0:
		print("shot_plateau: героя или лестницы нет")
		return
	# камера у подножия лестницы — виден и срез, и ступени, и тень
	var ground: Vector2i = stair
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		var n: Vector2i = stair + d
		if map.in_bounds(n) and map.height_at(n) < map.height_at(stair):
			ground = n
			break
	hero.position = (Vector2(ground) + Vector2(0.5, 0.5)) * map.ts
	var cam: Camera2D = hero.get_node_or_null("Camera")
	if cam != null:
		cam.zoom = Vector2(2.2, 2.2)
	print("shot_plateau: герой у лестницы, база %s" % ground)


func _on_frame() -> void:
	_frames += 1
	if _frames == 20:
		_goto_plateau(_city, _game)
	if _frames < 70:
		return
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("res://tools/shot_plateau.png")
		print("shot_plateau: сохранён tools/shot_plateau.png")
	quit(0)
