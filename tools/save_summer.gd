extends SceneTree
## Сохранить тестовый «лето»-биом (нарисованная карта) для скрина города.
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
	var sp: String = ui._sources[0]["sheet"]
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
			var v := 0
			if x > 13 and y < 6:
				v = 2
			elif (x * 5 + y * 11) % 13 == 0:
				v = 3
			elif (x / 2 + y / 2) % 7 == 0:
				v = 3
			g[y * 20 + x] = v
	ui._grid = g
	ui._name_edit.text = ""
	ui._on_save()
	print("saved: has лето=", Assets.biome_manifest().has("лето"),
			" grid=", int((Assets.biome_manifest()["лето"].get("grid", []) as Array).size()))
	quit(0)
