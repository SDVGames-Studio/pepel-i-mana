extends SceneTree
## E2E композитора v2 (v1.78.1): кнопки биомов, вкладки, смесь тайлов.
var _frames := 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/biome_composer.tscn")
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	print("composer: источников=", ui._sources.size())
	# смесь: 3 тайла весны + 1 тайл зимы (разные тайлы — края срастаются)
	ui._sel_grass = [
		ui._sources[1]["grass"][0], ui._sources[1]["grass"][2],
		ui._sources[1]["grass"][4], ui._sources[3]["grass"][0],
	]
	ui._sel_water = String(ui._sources[13]["water"])
	ui._sel_trees = [ui._sources[7]["trees"][0], "e:tree2_summer_oak"]
	ui._name_edit.text = "ТЕСТ СМЕСЬ 2"
	ui._season_btn.select(3)
	ui._season = "autumn"
	ui._rebuild_preview()
	ui._rebuild_tray()
	ui._open_biome(1)
	print("composer: смесь трава=%d" % ui._sel_grass.size())
	process_frame.connect(_on_frame.bind(ui))

func _on_frame(ui) -> void:
	_frames += 1
	if _frames == 8:
		var img: Image = root.get_texture().get_image()
		img.save_png("res://tools/shot_composer.png")
		print("shot: композитор v2 снят")
	if _frames >= 10:
		quit(0)
