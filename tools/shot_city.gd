extends SceneTree
## Снимок города для визуальной проверки (M11). Запуск С ГРАФИКОЙ (не headless):
## godot --path . --script res://tools/shot_city.gd
## Собирает демо-город (дома, лесопилка, каменоломня, кладбище, пни, саженцы,
## духи), ждёт кадры, сохраняет tools/shot_city.png и выходит.

var _frames := 0


func _initialize() -> void:
	# автозагрузки: в оконном --script-режиме Godot создаёт их сам; если нет — вешаем вручную
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
	var city: Node = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	_call_deferred(_decorate.bind(city, game))
	process_frame.connect(_on_frame)


func _call_deferred(cb: Callable) -> void:
	cb.call_deferred()


func _decorate(city: Node, game: Node) -> void:
	var sim = game.city_sim
	var map = sim.map
	var cfg: Dictionary = sim.cfg
	# дом/постройки вокруг центра: дом x3, лесопилка у дерева, каменоломня у скалы,
	# мастерская, таверна, кладбище
	var spots := {
		"house": [Vector2i(-3, -2), Vector2i(-5, 1), Vector2i(-2, 3)],
		"farm": [Vector2i(3, -2)],
		"tavern": [Vector2i(2, 2)],
		"cemetery": [Vector2i(-6, -3)],
	}
	for type_id in spots:
		for off: Vector2i in spots[type_id]:
			var t: Vector2i = map.spawn_tile + off
			var ok: bool = sim.is_buildable_tile(t, type_id) and sim.placement_block(type_id, t) == ""
			var done: bool = ok and sim.place_building(type_id, t)
			print("shot: %s @ %s buildable=%s placed=%s wood=%d" % [type_id, t, ok, done, int(sim.res["wood"])])
	print("shot: test wood after setup = %d" % int(sim.res["wood"]))
	# добытчики: лесопилка у ближайшего дерева, каменоломня у гряды
	var tree_tile := Vector2i(-1, -1)
	var rock_tile := Vector2i(-1, -1)
	for y in map.h:
		for x in map.w:
			if tree_tile == Vector2i(-1, -1) and map.grid[y][x] == map.TILE_TREE \
					and Vector2(x, y).distance_to(Vector2(map.spawn_tile)) < 14.0:
				tree_tile = Vector2i(x, y)
			if rock_tile == Vector2i(-1, -1) and map.grid[y][x] == map.TILE_ROCK \
					and Vector2(x, y).distance_to(Vector2(map.spawn_tile)) < 18.0:
				rock_tile = Vector2i(x, y)
	for pair in [["sawmill", tree_tile], ["quarry", rock_tile], ["workshop", null]]:
		var type_id: String = pair[0]
		var anchor: Vector2i = pair[1] if pair[1] != null else map.spawn_tile + Vector2i(4, 3)
		if anchor == Vector2i(-1, -1):
			continue
		for dy in range(-2, 3):
			var placed := false
			for dx in range(-2, 3):
				var t2: Vector2i = anchor + Vector2i(dx, dy)
				if sim.is_buildable_tile(t2, type_id) and sim.placement_block(type_id, t2) == "":
					sim.place_building(type_id, t2)
					placed = true
					break
			if placed:
				break
	# мгновенно «достроить» и дать кучи, пни, саженцы
	var ids := [3, 4, 5]
	for b in sim.buildings:
		b["done"] = true
		b["progress"] = 0.0
		if String(b["type"]) in ["sawmill", "quarry"]:
			b["pile"] = {"wood" if String(b["type"]) == "sawmill" else "stone": 12.0}
	for b2 in sim.buildings:
		if String(b2["type"]) == "cemetery":
			b2["hp"] = 25.0
	sim.map.stumps[map.spawn_tile + Vector2i(5, -1)] = true
	sim.map.stumps[map.spawn_tile + Vector2i(6, -2)] = true
	sim.map.saplings[map.spawn_tile + Vector2i(-4, 2)] = {"t": 30.0, "grow_days": 1.2}
	sim.map.saplings[map.spawn_tile + Vector2i(-4, 3)] = {"t": 100.0, "grow_days": 1.2}
	# некромантия раскрыта: тьма и скелеты у кладбища
	sim.necro_dark = 0.55
	sim.necro_known = true
	sim.necro_army = 5
	var cem: Dictionary = sim._cemetery()
	if not cem.is_empty():
		var c: Vector2i = cem["tile"]
		sim.necro_ghosts = [map.tile_center_px(c + Vector2i(1, 0)), map.tile_center_px(c + Vector2i(-1, 1))]
	# пара духов леса у лесопилки
	var spirit_def: Dictionary = {}
	for d: Dictionary in sim._enemies_cfg:
		if String(d["id"]) == "forest_spirit":
			spirit_def = d
	if spirit_def.is_empty():
		var ed: Variant = sim._read_json_file("res://data/enemies.json")
		sim._enemies_cfg = ed if ed is Array else []
		for d2: Dictionary in sim._enemies_cfg:
			if String(d2["id"]) == "forest_spirit":
				spirit_def = d2
	if not spirit_def.is_empty() and tree_tile != Vector2i(-1, -1):
		for i in 2:
			sim.raiders.append({
				"id": 900 + i, "type": "forest_spirit", "p": spirit_def,
				"hp": int(spirit_def["hp"]), "max_hp": int(spirit_def["hp"]),
				"pos": map.tile_center_px(tree_tile + Vector2i(1 + i, 1)),
				"target": Vector2i(-1, -1), "path": PackedVector2Array(),
				"atk_cd": 0.0, "mode": "hunt", "victim_id": -1, "ttl": 999.0,
			})
	sim.terrain_dirty = true
	if OS.get_environment("SHOT_NIGHT") != "":
		sim.time = float(sim.cfg["day_length"]) * 0.93   # ночь: видны скелеты кладбища
	elif OS.get_environment("SHOT_EVENING") != "":
		# вечер (M12): костёр горит, жители в досуге, разговоры-облачка
		sim.time = float(sim.cfg["day_length"]) * 0.65
	print("shot: город украшен")


func _on_frame() -> void:
	_frames += 1
	if _frames < 45:
		return
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tools/shot_city.png")
	print("shot: сохранён tools/shot_city.png")
	quit(0)
