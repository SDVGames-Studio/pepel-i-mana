extends SceneTree
## Скан-строки: где fog ярче clear существенно (не HUD).

func _init() -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path("res://tools/night_fog.png"))
	var b := Image.load_from_file(ProjectSettings.globalize_path("res://tools/night_clear.png"))
	for y in [300, 450, 600, 750]:
		var runs := 0
		var sample := ""
		for x in range(100, a.get_width() - 100):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			var d := (ca.r - cb.r) + (ca.g - cb.g) + (ca.b - cb.b)
			if d > 0.25:
				runs += 1
				if sample == "":
					sample = "fog=(%.2f,%.2f,%.2f) clear=(%.2f,%.2f,%.2f) @(%d,%d)" % [
							ca.r, ca.g, ca.b, cb.r, cb.g, cb.b, x, y]
		print("y=%d: ярче в fog %d px | %s" % [y, runs, sample])
	quit()
