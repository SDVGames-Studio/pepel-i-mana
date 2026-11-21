extends SceneTree
## ПРОВЕРКА «СЕРЫЙ ПРИ ПАНОРАМЕ» (v1.79.12): город допекается, герой
## телепортируется далеко (камера панорамирует), скрин — земля-полотно
## должна быть видна вокруг НОВОЙ позиции (серого «ничего» быть не должно).
## Запуск С ГРАФИКОЙ: godot --path . --script res://tools/diag_pan.gd

var _frames := 0
var _game: Node = null
var _city: Node = null
var _teleported := false


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
	_city = load("res://scenes/city.tscn").instantiate()
	root.add_child(_city)
	_game = game
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames < 110:
		return
	if not _teleported:
		var map = _city.sim.map
		var st: Vector2i = map.spawn_tile
		_city.hero.position = map.tile_center_px(st + Vector2i(48, 30))
		_teleported = true
		print("панорама: герой -> ", _city.hero.position)
		return
	if _frames >= 130:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://tools/shot_pan.png")
		print("shot: сохранён tools/shot_pan.png")
		quit()
		return
