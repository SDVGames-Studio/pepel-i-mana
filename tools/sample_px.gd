extends SceneTree
## Замер яркости данжа: комната далеко от героя.

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://tools/v1311_dungeon.png"))
	if img == null:
		print("no shot")
		quit(1)
		return
	for pt in [[960, 200], [960, 400], [300, 900], [1600, 900], [960, 540]]:
		var c: Color = img.get_pixel(pt[0], pt[1])
		print("@(%d,%d) = (%.3f, %.3f, %.3f)" % [pt[0], pt[1], c.r, c.g, c.b])
	quit()
