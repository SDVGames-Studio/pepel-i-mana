extends SceneTree
## Сохранить юзер-«весна» (рисовалка) для проверки города как у заказчика.
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
	var sp: String = ui._sources[1]["sheet"]
	var an: Dictionary = ui._analyze_sheet(sp)
	var cells: Array = an["cells"]
	ui._sel_grass = []
	for i in range(4):
		ui._sel_grass.append({"sheet": sp, "cx": int(cells[i]["cx"]),
				"cy": int(cells[i]["cy"])})
	ui._sel_water = an["water"]
	var g: Array = []
	g.resize(400)
	for y in range(20):
		for x in range(20):
			g[y * 20 + x] = (x * 3 + y * 5) % 4
	ui._grid = g
	ui._name_edit.text = ""
	ui._on_save()
	print("saved: весна has=", Assets.biome_manifest().has("весна"))
	quit(0)
