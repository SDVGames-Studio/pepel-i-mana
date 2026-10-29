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


func _on_frame() -> void:
	_frames += 1
	if _frames < 50:
		return
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tools/shot_dungeon.png")
	print("shot: сохранён tools/shot_dungeon.png")
	quit(0)
