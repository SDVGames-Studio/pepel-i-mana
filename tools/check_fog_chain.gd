extends SceneTree
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
	game.new_world()
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	_world = world
	process_frame.connect(_tick)

func _tick() -> void:
	_frames += 1
	if _frames < 10:
		return
	var map = _world.map
	var view = _world.get("view")
	var target: Vector2i = map.city_tile + Vector2i(12, 6)
	print("до: fog_has_target=", map.fog.has(target),
			" fog_new_size=", (map.fog_new as Array).size())
	_world._reveal(target)
	print("после reveal: fog_has=", map.fog.has(target),
			" fog_new=", (map.fog_new as Array).size())
	# даём _process view'а отработать кадр
	if _frames == 12:
		var view_img: Image = view._fog_img
		var hts: float = view._fog_hts
		var c := Vector2(float(target.x) + 0.5, float(target.y) + 0.5) * hts
		var px: Color = view_img.get_pixel(int(c.x), int(c.y))
		print("пиксель тумана в центре раскрытого тайла: a=", px.a)
		# ещё пара тайлов вокруг
		var p2: Color = view_img.get_pixel(int(c.x) + 16, int(c.y))
		print("пиксель в 1 тайле восточнее: a=", p2.a)
		print("fog_tex=", view._fog_tex)
		quit()
