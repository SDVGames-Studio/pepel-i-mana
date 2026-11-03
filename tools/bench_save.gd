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
	game.set("test_mode", true)
	game.call("new_city")
	var t0 := Time.get_ticks_msec()
	var sg: Script = load("res://scripts/save_game.gd")
	var snap: Dictionary = sg.save_snapshot(game, sg.city_hero_tile(game), -1, -1)
	var err: String = sg.write_snapshot(snap)
	var t1 := Time.get_ticks_msec()
	var f := FileAccess.open("user://saves/save.json", FileAccess.READ)
	var size := f.get_length() if f != null else -1
	print("save: %d bytes, %d ms, err=%s" % [size, t1 - t0, err])
	quit(0)
func _process(_d) -> bool:
	return false
