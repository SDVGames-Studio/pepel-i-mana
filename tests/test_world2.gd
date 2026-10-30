extends "res://tests/test_base.gd"
## Гидрология и рельеф генерации — программа «Мир v2», этап 1 (v1.35.0).
## Карта высот → реки из скал к морю (N→S + меандры), озёра/болота по
## влажности, клетка мира несёт свои водоёмы в локацию города (№117–118).

const SEEDS := [11, 42, 1000, 77777, 424242]


func _test_world2_hydro() -> void:
	print("[Мир v2 / этап 1: гидрология]")
	var cfg: Dictionary = _read_json("res://data/world.json")
	var city_cfg: Dictionary = _read_json("res://data/city.json")

	# детерминизм: тот же сид — та же карта (grid, русла, POI-число)
	var a = load("res://scripts/world_map.gd").new()
	a.generate(12345, cfg)
	var b = load("res://scripts/world_map.gd").new()
	b.generate(12345, cfg)
	var same: bool = a.w == b.w and a.h == b.h
	for y in a.h:
		for x in a.w:
			if int(a.grid[y][x]) != int(b.grid[y][x]):
				same = false
	_check(same and a.river.keys().size() == b.river.keys().size(),
			"генерация детерминирована по сиду")

	for seed_value in SEEDS:
		var map = load("res://scripts/world_map.gd").new()
		map.generate(seed_value, cfg)
		var label := "сид %d" % seed_value

		# океан на юге: нижняя строка — вода
		var sea := true
		for x in map.w:
			if int(map.grid[map.h - 1][x]) != map.TILE_WATER:
				sea = false
		_check(sea, label + ": океан лежит вдоль южного края")

		# река: течёт с севера и впадает в воду (море/озеро) или доходит до юга
		var river_top := false
		var river_mouth := false
		for t: Vector2i in map.river:
			if t.y <= map.h * 0.4:
				river_top = true
			if t.y >= map.h * 0.75:
				river_mouth = true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n: Vector2i = t + Vector2i(dx, dy)
					if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER:
						river_mouth = true
		_check(map.river.size() > 0 and river_top and river_mouth,
				label + ": реки текут с северных скал к воде (%d тайлов)" % map.river.size())

		# река — оверлей: тайл проходим (брод), но дороже равнины
		var any_river: Vector2i = map.river.keys()[0]
		_check(map.is_walkable(any_river),
				label + ": речной тайл проходим (брод на глобали)")
		_check(map.tile_cost(any_river) > float(cfg["biomes"]["plains"]["cost"]),
				label + ": река замедляет путь (цена выше равнины)")

		# скалы сконцентрированы на севере (река начинается в скалах)
		var hills_top := 0
		var hills_bot := 0
		for y in map.h:
			for x in map.w:
				if int(map.grid[y][x]) == map.TILE_HILL:
					if y < map.h * 0.5:
						hills_top += 1
					else:
						hills_bot += 1
		_check(hills_top > hills_bot and hills_top > 0,
				label + ": скалы в основном на севере (%d/%d)" % [hills_top, hills_bot])

		# болота и вода по влажности есть на карте
		var swamp_n := 0
		var water_n := 0
		for y in map.h:
			for x in map.w:
				match int(map.grid[y][x]):
					map.TILE_SWAMP:
						swamp_n += 1
					map.TILE_WATER:
						water_n += 1
		_check(swamp_n > 0 and water_n > 0,
				label + ": болота (%d) и вода (%d) на карте" % [swamp_n, water_n])

		# город — на суше, не на болоте; POI — не на руслах, все достижимы
		var ct: int = map.grid[map.city_tile.y][map.city_tile.x]
		_check(ct != map.TILE_WATER and ct != map.TILE_SWAMP,
				label + ": город стоит на сухой земле")
		var on_river := 0
		var paths_ok := true
		for poi in map.pois:
			if String(poi["kind"]) != "city" and map.river.has(poi["tile"]):
				on_river += 1   # город сам стоит на реке — это фича, не дефект
			if map.tile_path(map.city_tile, poi["tile"]).is_empty():
				paths_ok = false
		_check(on_river == 0 and paths_ok,
				label + ": POI не на руслах и все достижимы из города")

		# клетка города несёт водоёмы в локацию города (ответ №117)
		var hydro: Dictionary = map.city_hydro()
		_check(hydro.has("river") and hydro.has("lake") and hydro.has("swamp"),
				label + ": гидро-контекст клетки города собран")
		var cmap = load("res://scripts/city_map.gd").new()
		cmap.generate(seed_value, city_cfg, hydro)
		var city_river := 0
		for y in cmap.h:
			for x in cmap.w:
				var t := Vector2i(x, y)
				if int(cmap.grid[y][x]) == cmap.TILE_WATER \
						and String(cmap.water_kind.get(t, "")) == "river":
					city_river += 1
		if bool(hydro["river"]):
			_check(city_river > 0,
					label + ": река на глобале повторилась в городе (%d тайлов)" % city_river)
		else:
			_check(city_river == 0,
					label + ": реки на глобале нет — в городе реки тоже нет")

	# обратное направление: без реки на глобале город генерируется без реки;
	# с озером-соседом — минимум одно озеро, с болотом — минимум болота
	var map2 = load("res://scripts/world_map.gd").new()
	map2.generate(11, cfg)
	var cmap2 = load("res://scripts/city_map.gd").new()
	cmap2.generate(555, city_cfg, {"river": false, "lake": true, "swamp": true})
	var lakes := 0
	var swamps := 0
	for y in cmap2.h:
		for x in cmap2.w:
			var t := Vector2i(x, y)
			if int(cmap2.grid[y][x]) == cmap2.TILE_WATER:
				if String(cmap2.water_kind.get(t, "")) == "swamp":
					swamps += 1
				else:
					lakes += 1
	_check(lakes > 0 and swamps > 0,
			"озеро/болото клетки мира переходят в город (%d/%d тайлов)" % [lakes, swamps])

	# сейв: русла, типы воды и высоты рельефа сохраняются и восстанавливаются
	var sv: Script = load("res://scripts/save_game.gd")
	var block: Dictionary = sv._world_block(map2, _fake_world_sim(map2))
	_check(block["map"].has("river") and (block["map"]["river"] as Array).size() == map2.river.size(),
			"русла уходят в сейв (%d)" % (block["map"]["river"] as Array).size())
	_check(block["map"].has("water_kind") and (block["map"]["water_kind"] as Array).size() == map2.water_kind.size(),
			"типы воды уходят в сейв (%d)" % (block["map"]["water_kind"] as Array).size())
	var hrows: Array = block["map"].get("height", [])
	var h_ok: bool = hrows.size() == map2.h
	if h_ok:
		for y in mini(3, map2.h):
			for x in mini(5, map2.w):
				if absf(float(hrows[y][x]) - float(map2.height[y][x])) > 0.002:
					h_ok = false
	_check(h_ok, "высоты рельефа уходят в сейв (строк %d)" % hrows.size())
	print("[Мир v2 / этап 1] готово")


## Минимальный фейк world_sim для _world_block (нужны day/chronicle/... поля).
func _fake_world_sim(map) -> RefCounted:
	var sim: RefCounted = load("res://scripts/world_sim.gd").new()
	sim.setup(map, _read_json("res://data/world.json"), 7)
	return sim
