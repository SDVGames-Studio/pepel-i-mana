extends SceneTree
## Превью-лист нечисти: 7×2 сетки 32×40 в один PNG.

func _init() -> void:
	var ids := ["leshy", "vodyanoy", "kikimora", "rusalka", "upyr", "volkolak",
			"bannik", "polevik", "nochnitsa", "black_hen", "viy", "baba_yaga",
			"koshchei", "death_needle"]
	var sheet := Image.create(7 * 34, 2 * 42, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#20242c"))
	for i in ids.size():
		var img := Image.load_from_file(ProjectSettings.globalize_path(
				"res://assets/sprites/creatures/" + ids[i] + ".png"))
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i((i % 7) * 34 + 1, (i / 7) * 42 + 1))
	sheet.resize(7 * 34 * 2, 2 * 42 * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(ProjectSettings.globalize_path("res://tools/creatures_preview.png"))
	print("preview saved")
	quit()
