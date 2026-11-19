extends SceneTree
## E2E рисовалки v4 (v1.78.8): кисти + ручная карта 20×20 → сохранение →
## восстановление вкладки. Скрины холста.
var _frames := 0
var _stage := 0


func _initialize() -> void:
	for pair in [["Loc", "res://scripts/loc.gd"],
			["Game", "res://scripts/game.gd"],
			["SfxDirector", "res://scripts/sfx_director.gd"]]:
		if root.get_node_or_null(String(pair[0])) == null:
			var n: Node = load(String(pair[1])).new()
			n.name = String(pair[0])
			root.add_child(n)
	var ui = load("res://scenes/biome_composer.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	process_frame.connect(_on_frame.bind(ui))


func _on_frame(ui) -> void:
	_frames += 1
	if _stage > 3:
		return
	if _stage == 0 and _frames == 30:
		# кисти: 4 клетки лета
		var sp: String = ui._sources[0]["sheet"]
		var an: Dictionary = ui._analyze_sheet(sp)
		var cells: Array = an["cells"]
		ui._sel_grass = []
		for i in range(4):
			ui._sel_grass.append({"sheet": sp, "cx": int(cells[i]["cx"]),
					"cy": int(cells[i]["cy"])})
		ui._sel_water = an["water"]
		ui._brush = 1
		# НАРИСОВАННАЯ РУКАМИ карта: поля травы, пятна, дорожка
		var g: Array = []
		g.resize(400)
		for y in range(20):
			for x in range(20):
				var v := 0
				if x > 13 and y < 6:
					v = 2            # угол камней
				elif (x * 5 + y * 11) % 13 == 0:
					v = 3            # цветочные пятна
				elif y > 15:
					v = 1            # тёмная трава снизу
				elif (x / 2 + y / 2) % 7 == 0:
					v = 3
				g[y * 20 + x] = v
		ui._grid = g
		ui._name_edit.text = ""
		ui._redraw_canvas()
		ui._on_save()
		print("v4: лето нарисован и сохранён; grid в json=",
				int((Assets.biome_manifest()["лето"].get("grid", []) as Array).size()))
		_stage = 1
	elif _stage == 1 and _frames >= 45:
		root.get_texture().get_image().save_png("res://tools/shot_composer.png")
		print("shot: нарисованный холст снят")
		ui._open_biome(2)
		_stage = 2
	elif _stage == 2 and _frames >= 60:
		print("осень: палитра=", ui._sel_grass.size(), " grid400=",
				(ui._grid as Array).size())
		ui._open_biome(0)
		_stage = 3
	elif _stage == 3 and _frames >= 75:
		print("лето снова: палитра=", ui._sel_grass.size(),
				" нарисовано=", ui._grid.filter(func(v): return int(v) >= 0).size())
		var d2 := DirAccess.open("user://biomes_composed/лето")
		if d2 != null:
			for f in d2.get_files():
				d2.remove(f)
			DirAccess.remove_absolute(
					ProjectSettings.globalize_path("user://biomes_composed/лето"))
		Assets.reload_biome_manifest()
		_stage = 4
		quit(0)
