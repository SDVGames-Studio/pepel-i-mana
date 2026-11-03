extends SceneTree
var _frames := 0
var game: Node = null
func _initialize() -> void:
	game = root.get_node_or_null("Game")
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
func _process(_d) -> bool:
	_frames += 1
	if _frames == 90:
		var npc = game.get("npc_cities")
		var n: int = npc.cities.size() if npc != null else -1
		var setts := 0
		for poi in game.world_map.pois:
			if String(poi["kind"]) == "settlement":
				setts += 1
		print("settlement POIs=%d, npc cities=%d" % [setts, n])
		quit(0)
	return false
