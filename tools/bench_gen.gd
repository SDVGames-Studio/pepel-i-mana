extends SceneTree
## Замер генерации карт новых размеров (v1.43).

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var wcfg: Dictionary = JSON.parse_string(FileAccess.open("res://data/world.json", FileAccess.READ).get_as_text())
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(randi(), wcfg)
	var t1 := Time.get_ticks_msec()
	print("world generate %dx%d: %d ms" % [wmap.w, wmap.h, t1 - t0])
	var ccfg: Dictionary = JSON.parse_string(FileAccess.open("res://data/city.json", FileAccess.READ).get_as_text())
	var cmap = load("res://scripts/city_map.gd").new()
	t0 = Time.get_ticks_msec()
	cmap.generate(12345, ccfg, {})
	t1 = Time.get_ticks_msec()
	print("city generate %dx%d: %d ms" % [cmap.w, cmap.h, t1 - t0])
	quit(0)
