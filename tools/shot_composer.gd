extends SceneTree
## E2E композитора v3 (v1.78.7): У КАЖДОЙ ВКЛАДКИ СВОЯ СБОРКА И СОХРАНЕНИЕ.
## Лето: собрал — сохранил — осень (своя пустая) — назад на лето
## (выбор восстановлен из сохранения). Скрины всех шагов.
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
	if _stage > 4:
		return
	if _stage == 0 and _frames == 30:
		var sp: String = ui._sources[0]["sheet"]
		var an: Dictionary = ui._analyze_sheet(sp)
		var cells: Array = an["cells"]
		ui._sel_grass = []
		for i in range(5):
			ui._sel_grass.append({"sheet": sp, "cx": int(cells[i]["cx"]),
					"cy": int(cells[i]["cy"])})
		ui._sel_water = an["water"]
		ui._name_edit.text = ""
		ui._after_toggle()
		ui._on_save()
		print("v3: лето сохранён; манифест has лето=",
				Assets.biome_manifest().has("лето"))
		_stage = 1
	elif _stage == 1 and _frames >= 45:
		root.get_texture().get_image().save_png("res://tools/shot_composer.png")
		print("shot: лето (сохранён) снят")
		ui._open_biome(2)
		_stage = 2
	elif _stage == 2 and _frames >= 60:
		root.get_texture().get_image().save_png("res://tools/shot_composer_autumn.png")
		print("shot: осень (пустая своя) снят")
		ui._open_biome(0)
		_stage = 3
	elif _stage == 3 and _frames >= 75:
		root.get_texture().get_image().save_png("res://tools/shot_composer_back.png")
		print("shot: лето снова (восстановлено), клеток=", ui._sel_grass.size())
		var d2 := DirAccess.open("user://biomes_composed/лето")
		if d2 != null:
			for f in d2.get_files():
				d2.remove(f)
			DirAccess.remove_absolute(
					ProjectSettings.globalize_path("user://biomes_composed/лето"))
		Assets.reload_biome_manifest()
		_stage = 4
		quit(0)
