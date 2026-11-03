extends SceneTree
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
	root.add_child(load("res://scenes/world.tscn").instantiate())
func _process(_d) -> bool:
	_frames += 1
	if _frames % 60 == 0:
		print("FPS @", _frames, ": ", Engine.get_frames_per_second())
	if _frames >= 300:
		quit(0)
	return false
