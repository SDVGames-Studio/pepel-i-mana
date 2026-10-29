extends SceneTree
## Снимок данжа для визуальной проверки (v1.30.1). Запуск С ГРАФИКОЙ:
## godot --path . --script res://tools/shot_dungeon.gd
## Режимы: SHOT_BIOME=<id> фиксирует биом; SHOT_NIGHT — ночь города
## (ночные твари усилены).

var _frames := 0


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
	# автозагрузку берём локальной ссылкой: на компиляции инструмента
	# глобального имени Game ещё нет (узел добавлен выше руками)
	if OS.get_environment("SHOT_BIOME") != "":
		game.forced_biome = OS.get_environment("SHOT_BIOME")
	if OS.get_environment("SHOT_NIGHT") != "":
		game.city_sim.time = float(game.city_sim.cfg["day_length"]) * 0.95
	var dungeon: Node = load("res://scenes/dungeon.tscn").instantiate()
	root.add_child(dungeon)
	process_frame.connect(_on_frame)


func _find_dungeon(node: Node) -> Node:
	for c in node.get_children():
		var sc = c.get_script()
		if sc != null and String((sc as Script).resource_path).ends_with("dungeon.gd"):
			return c
		var f := _find_dungeon(c)
		if f != null:
			return f
	return null


func _on_frame() -> void:
	_frames += 1
	if _frames < 50:
		return
	var dungeon2: Node = _find_dungeon(root)
	if dungeon2 != null:
		var gen = dungeon2.get("gen")
		var floors := 0
		if gen != null:
			for y2 in gen.h:
				for x2 in gen.w:
					if int(gen.grid[y2][x2]) == int(gen.TILE_FLOOR):
						floors += 1
		var hero2 = dungeon2.get("hero")
		var dark = dungeon2.get("_darkness")
		var cam := dungeon2.get_node_or_null("../HeroCam")
		if cam == null:
			for c in dungeon2.get_children():
				if c is Camera2D:
					cam = c
			if cam == null and hero2 != null:
				for c in hero2.get_children():
					if c is Camera2D:
						cam = c
		var camtxt := "нет"
		if cam != null:
			var vpt := root.get_viewport().get_visible_rect().size
			camtxt = "cam=%s hero_screen=%s gen=%dx%d" % [cam.global_position,
					(hero2.global_position - cam.global_position) + vpt * 0.5
					if hero2 != null else "-", gen.w if gen != null else 0,
					gen.h if gen != null else 0]
		print("diag: floors=%d hero=%s dark=%s view=%s %s" % [floors,
				hero2.global_position if hero2 != null else "нет",
				(dark.color if dark != null else "нет"),
				dungeon2.get_node_or_null("Darkness") != null, camtxt])
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tools/shot_dungeon.png")
	print("shot: сохранён tools/shot_dungeon.png")
	quit(0)
