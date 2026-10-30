extends SceneTree
## Временная проверка гидрологии (этап 1 «Мир v2»): статистика по сидам.

func _initialize() -> void:
	var cfg: Variant = JSON.parse_string(FileAccess.open(
			"res://data/world.json", FileAccess.READ).get_as_text())
	var fails := 0
	for seed_value in [11, 42, 1000, 77777]:
		var map = load("res://scripts/world_map.gd").new()
		map.generate(seed_value, cfg)
		var hills_n := 0
		var hills_top := 0
		var water_n := 0
		var swamp_n := 0
		for y in map.h:
			for x in map.w:
				match int(map.grid[y][x]):
					3:
						hills_n += 1
						if y < map.h * 0.5:
							hills_top += 1
					1:
						water_n += 1
					6:
						swamp_n += 1
		var river_n: int = map.river.size()
		var river_top := false
		var river_mouth := false
		for t: Vector2i in map.river:
			if t.y <= map.h * 0.4:
				river_top = true
			if t.y >= map.h * 0.75:
				river_mouth = true   # дошла до южной полосы
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n: Vector2i = t + Vector2i(dx, dy)
					if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER:
						river_mouth = true   # впадает в море/озеро
		var sea_ok := true
		for x in map.w:
			if int(map.grid[map.h - 1][x]) != 1:
				sea_ok = false
		var hydro: Dictionary = map.city_hydro()
		var paths_ok := true
		for poi in map.pois:
			if map.travel_days(map.city_tile, poi["tile"]) <= 0:
				paths_ok = false
		print("seed=%d hills=%d(top %d) water=%d swamp=%d river=%d(top:%s mouth:%s) sea=%s city=(%d,%d) hydro=%s paths=%s pois=%d" % [
			seed_value, hills_n, hills_top, water_n, swamp_n, river_n, river_top, river_mouth,
			sea_ok, map.city_tile.x, map.city_tile.y, hydro, paths_ok, map.pois.size()])
		if river_n == 0 or not river_top or not river_mouth:
			print("  FAIL: река не течёт с севера на юг")
			fails += 1
		if not sea_ok:
			print("  FAIL: юг не море")
			fails += 1
		if swamp_n == 0:
			print("  FAIL: болот нет")
			fails += 1
		if water_n == 0:
			print("  FAIL: воды нет")
			fails += 1
		if hills_n == 0 or hills_top == 0:
			print("  FAIL: скал на севере нет")
			fails += 1
		if not paths_ok:
			print("  FAIL: какой-то POI недостижим")
			fails += 1
	# город с рекой / без реки
	var city_cfg: Variant = JSON.parse_string(FileAccess.open(
			"res://data/city.json", FileAccess.READ).get_as_text())
	var map2 = load("res://scripts/world_map.gd").new()
	map2.generate(11, cfg)
	var hydro2: Dictionary = map2.city_hydro()
	var cmap = load("res://scripts/city_map.gd").new()
	cmap.generate(123, city_cfg, hydro2)
	var river_tiles := 0
	for y in cmap.h:
		for x in cmap.w:
			if cmap.grid[y][x] == cmap.TILE_WATER and String(cmap.water_kind.get(Vector2i(x, y), "")) == "river":
				river_tiles += 1
	print("hydro=%s -> город рекных тайлов: %d" % [hydro2, river_tiles])
	if hydro2["river"] and river_tiles == 0:
		print("  FAIL: река на глобале не повторилась в городе")
		fails += 1
	var cmap2 = load("res://scripts/city_map.gd").new()
	cmap2.generate(123, city_cfg, {"river": false})
	var river_tiles2 := 0
	for y in cmap2.h:
		for x in cmap2.w:
			if cmap2.grid[y][x] == cmap2.TILE_WATER \
					and String(cmap2.water_kind.get(Vector2i(x, y), "")) == "river":
				river_tiles2 += 1
	print("hydro без реки -> город рекных тайлов: %d" % river_tiles2)
	if river_tiles2 > 0:
		print("  FAIL: без реки на глобале река в городе")
		fails += 1
	if fails == 0:
		print("OK: гидрология работает")
	quit(0 if fails == 0 else 1)
