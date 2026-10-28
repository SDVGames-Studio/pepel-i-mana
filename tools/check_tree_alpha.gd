extends SceneTree
## Разовая диагностика (v1.29.4): у каких деревьев пустые прозрачные поля
## снизу — из-за них якорь «низ текстуры» поднимает дерево над тенью.

func _init() -> void:
	var dir := "res://assets/sprites/env/"
	for name in ["tree_oak", "tree_pine", "tree_birch", "tree_autumn",
			"tree_lime", "tree_fruit2", "tree_fruit"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path(dir + name + ".png"))
		if img == null:
			print(name, ": LOAD FAIL")
			continue
		var bottom := -1
		var top := img.get_height()
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.05:
					bottom = y
					top = mini(top, y)
					break
		var h := img.get_height()
		print("%s: %dx%d, контент y=%d..%d, пусто снизу %d px (%.2f тайла), сверху %d px" % [
				name, img.get_width(), h, top, bottom, h - 1 - bottom,
				float(h - 1 - bottom) / 32.0, top])
	quit()
