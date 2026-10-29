extends SceneTree
## Диагностика тумана/света (v1.33.3): где центр градиента, что с героем.
## Запуск: godot --path . --script res://tools/debug_fog.gd (С ГРАФИКОЙ)
var _frames := 0
var _dungeon: Node = null


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
	var dungeon: Node = load("res://scenes/dungeon.tscn").instantiate()
	root.add_child(dungeon)
	_dungeon = dungeon
	process_frame.connect(_on_frame)


func _find(node: Node, path_suffix: String) -> Node:
	for c in node.get_children():
		var sc = c.get_script()
		if sc != null and String((sc as Script).resource_path).ends_with(path_suffix):
			return c
		var f := _find(c, path_suffix)
		if f != null:
			return f
	return null


func _on_frame() -> void:
	_frames += 1
	if _frames < 78:
		return
	var hero: Node = _find(_dungeon, "hero.gd")
	if _frames == 78:
		var cam2: Camera2D = hero.get_node("Camera")
		var z: float = cam2.zoom.x
		# эффективный центр камеры с учётом лимитов (кламп движка)
		var vpt := root.get_viewport().get_visible_rect().size
		var half := vpt * 0.5 / z
		var cx: float = clampf(cam2.global_position.x,
				cam2.limit_left + half.x, cam2.limit_right - half.x)
		var cy: float = clampf(cam2.global_position.y,
				cam2.limit_top + half.y, cam2.limit_bottom - half.y)
		var hs: Vector2 = (hero.global_position - Vector2(cx, cy)) * z + vpt * 0.5
		print("HEROSCREEN=", int(hs.x), ",", int(hs.y))
		root.get_texture().get_image().save_png("res://tools/xp_0_as-is.png")
		quit(0)
