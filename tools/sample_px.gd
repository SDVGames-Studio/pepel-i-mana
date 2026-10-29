extends SceneTree
## Сэмплы пикселей: пятно у пруда vs обычная трава (ночной кадр).

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://tools/w_nodark.png"))
	if img == null:
		print("no shot")
		quit(1)
		return
	for label in [["пятно1", 640, 320], ["пятно2", 700, 380], ["пятно3", 760, 300],
			["трава1", 400, 600], ["трава2", 1000, 700], ["пруд", 720, 400]]:
		var c: Color = img.get_pixel(int(label[1]), int(label[2]))
		print("%s @(%d,%d) = (%.2f, %.2f, %.2f, %.2f)" % [label[0], label[1], label[2], c.r, c.g, c.b, c.a])
	quit()
