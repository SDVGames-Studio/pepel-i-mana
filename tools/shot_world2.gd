extends SceneTree
## Снимок карты мира с гидрологией (v2, этап 1 «Мир v2»). Запуск С ГРАФИКОЙ:
##   SHOT_SEED=4242 godot --path . --script res://tools/shot_world2.gd
## Открывает сцену мира, вскрывает весь туман, зумит камеру на всю карту,
## сохраняет tools/shot_world2.png и выходит.

var _frames := 0
var _world: Node = null


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
	game.new_world()
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	_world = world
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 5:
		_reveal_all()
	if _frames < 40:
		return
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("res://tools/shot_world2.png")
		print("shot_world2: сохранён tools/shot_world2.png")
	quit(0)


## Вскрыть туман, показать все POI, зумить камеру на всю карту.
func _reveal_all() -> void:
	var map = _world.map
	if map == null:
		return
	for y in map.h:
		for x in map.w:
			map.fog[Vector2i(x, y)] = true
	for poi in map.pois:
		poi["discovered"] = true
	var cam: Camera2D = _world.camera
	if cam != null:
		var vp := root.get_visible_rect().size
		var z := minf(vp.x / (map.w * map.ts), vp.y / (map.h * map.ts)) * 0.98
		cam.zoom = Vector2(z, z)
		cam.position = Vector2(map.w, map.h) * map.ts * 0.5
	print("shot_world2: fog снят, зум %s" % cam.zoom)
