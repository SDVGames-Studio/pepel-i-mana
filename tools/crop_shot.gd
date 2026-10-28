extends SceneTree
## Разовая диагностика: вырезать и увеличить фрагмент снимка города.

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://tools/v8_rock.png"))
	if img == null:
		print("no shot")
		quit(1)
		return
	var crop := img.get_region(Rect2i(700, 240, 560, 420))
	crop.resize(1120, 840, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path("res://tools/shot_crop4.png"))
	print("saved crop")
	quit()
