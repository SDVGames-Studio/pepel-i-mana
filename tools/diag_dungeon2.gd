extends SceneTree
## Разовая диагностика «Данжи v2»: где жаровни/лужи/руны/порча относительно
## героя и камеры (запуск с графикой, как shot_dungeon.gd).

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
	game.test_mode = true
	game.new_city()
	if OS.get_environment("SHOT_BIOME") != "":
		game.forced_biome = OS.get_environment("SHOT_BIOME")
	var dungeon: Node = load("res://scenes/dungeon.tscn").instantiate()
	root.add_child(dungeon)
	process_frame.connect(_on_frame)

var _frames := 0

func _on_frame() -> void:
	_frames += 1
	if _frames < 30:
		return
	var d2: Node = null
	for c in root.get_children():
		var sc = c.get_script()
		if sc != null and String((sc as Script).resource_path).ends_with("dungeon.gd"):
			d2 = c
			break
	if d2 != null:
		var gen = d2.get("gen")
		var hero = d2.get("hero")
		var hp: Vector2 = hero.global_position
		print("hero ", hp, " start ", gen.start_tile, " biome ", d2.get("biome").get("loc", "?"))
		print("braziers:", gen.brazier_spawns)
		print("runes:", gen.rune_spawns)
		print("puddles:", gen.puddle_zones)
		print("corrupt_rooms:", gen.corrupt_rooms)
		var lights := 0
		var fires := 0
		for c in d2.get_children():
			lights += c.get_children().size() if c is Node2D and String((c.get_script() as Script).resource_path).find("dungeon_lights") >= 0 else 0
			if c is PointLight2D:
				fires += 1
		print("dungeon_lights children:", lights)
		for t in gen.brazier_spawns:
			var wp := Vector2(t) * 32.0 + Vector2(16, 16)
			print("  brazier ", t, " dist от героя ", int(wp.distance_to(hp)), "px")
	quit(0)
