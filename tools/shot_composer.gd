extends SceneTree
## E2E композитора v2 (v1.78.5): клетки листов, вода листа, скрины лета/осени.
var _frames := 0
var _stage := 0


func _initialize() -> void:
	# автозагрузки вручную (--script их не поднимает; если живы — скип)
	for pair in [["Loc", "res://scripts/loc.gd"],
			["Game", "res://scripts/game.gd"],
			["SfxDirector", "res://scripts/sfx_director.gd"]]:
		if root.get_node_or_null(String(pair[0])) == null:
			var n: Node = load(String(pair[1])).new()
			n.name = String(pair[0])
			root.add_child(n)
	var scene: PackedScene = load("res://scenes/biome_composer.tscn")
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	print("composer: источников=", ui._sources.size())
	process_frame.connect(_on_frame.bind(ui))


func _on_frame(ui) -> void:
	_frames += 1
	if _stage > 4:
		return
	var sp: String = ui._sources[0]["sheet"]
	var an: Dictionary = ui._analyze_sheet(sp)
	if _stage == 0 and _frames == 30:
		# лето: 7 клеток земли + авто-вода, превью
		var cells: Array = an["cells"]
		ui._sel_grass = []
		for i in range(7):
			ui._sel_grass.append({"sheet": sp, "cx": int(cells[i]["cx"]),
					"cy": int(cells[i]["cy"])})
		ui._sel_water = an["water"]
		ui._name_edit.text = "Моё лето"
		ui._season_btn.select(2)
		ui._season = "summer"
		ui._after_toggle()
		_stage = 1
	elif _stage == 1 and _frames >= 45:
		var img: Image = root.get_texture().get_image()
		img.save_png("res://tools/shot_composer.png")
		print("shot: лето снят")
		# осень: вкладка 2
		ui._open_biome(2)
		var sp2: String = ui._sources[2]["sheet"]
		var an2: Dictionary = ui._analyze_sheet(sp2)
		var cells2: Array = an2["cells"]
		ui._sel_grass = []
		for j in range(6):
			ui._sel_grass.append({"sheet": sp2, "cx": int(cells2[j]["cx"]),
					"cy": int(cells2[j]["cy"])})
		ui._sel_water = an2["water"]
		ui._name_edit.text = "Моя осень"
		ui._season_btn.select(3)
		ui._season = "autumn"
		ui._after_toggle()
		_stage = 2
	elif _stage == 2 and _frames >= 60:
		var img2: Image = root.get_texture().get_image()
		img2.save_png("res://tools/shot_composer_autumn.png")
		print("shot: осень снят")
		# весна (лист с запечённым фоном) — контроль читаемости библиотеки
		ui._open_biome(1)
		var sp3: String = ui._sources[1]["sheet"]
		var an3: Dictionary = ui._analyze_sheet(sp3)
		print("spring cells=", (an3["cells"] as Array).size())
		# сборка из весенних клеток (чистка шашечки -> единый тон)
		var cells3: Array = an3["cells"]
		ui._sel_grass = []
		for j3 in range(6):
			ui._sel_grass.append({"sheet": sp3, "cx": int(cells3[j3]["cx"]),
					"cy": int(cells3[j3]["cy"])})
		ui._name_edit.text = "Моя весна"
		ui._season_btn.select(1)
		ui._season = "spring"
		ui._after_toggle()
		_stage = 3
	elif _stage == 3 and _frames >= 100:
		var img3: Image = root.get_texture().get_image()
		img3.save_png("res://tools/shot_composer_spring.png")
		print("shot: весна снят")
		_stage = 4
		quit(0)
