extends SceneTree
## E2E-тест композитора биомов (v1.78.0): собираем биом, сохраняем,
## снимаем UI; затем shot_city с SHOT_BIOME показывает его в городе.
var _frames := 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/biome_composer.tscn")
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	var mf: Dictionary = Assets.biome_manifest()
	# сборка: трава весны x3 + степей, вода скал, деревья мёртвого леса + лета
	ui._sel_grass = []
	for i in range(3):
		ui._sel_grass.append(mf["весна"]["grass"][i])
	ui._sel_grass.append(mf["степи"]["grass"][0])
	ui._sel_water = String(mf["скалы"]["water"])
	ui._sel_trees = [mf["мёртвый лес"]["trees"][0], "e:tree2_summer_oak"]
	ui._name_edit.text = "ТЕСТ СМЕСЬ"
	ui._season_btn.select(3)
	ui._season = "autumn"
	ui._rebuild_preview()
	ui._status.text = "e2e"
	print("composer: собрано трава=%d вода=%s деревья=%d" % [ui._sel_grass.size(), ui._sel_water != "", ui._sel_trees.size()])
	process_frame.connect(_on_frame.bind(ui))

func _on_frame(ui) -> void:
	_frames += 1
	if _frames == 8:
		var img: Image = root.get_texture().get_image()
		img.save_png("res://tools/shot_composer.png")
		print("shot: композитор снят")
		ui._on_save()
		print("composer: сохранён? ", Assets.biome_manifest().has("ТЕСТ СМЕСЬ"))
	if _frames >= 10:
		quit(0)
