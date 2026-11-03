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

		# море по режиму мира (№118): ocean/both — вода у южного края;
		# inner — внутреннее море в середине карты, южный край — суша
		var sea := true
		for x in map.w:
			if int(map.grid[map.h - 1][x]) != map.TILE_WATER:
				sea = false
		if map.sea_mode == "inner":
			var mid_water := false
			for y in range(int(map.h * 0.3), map.h - 5):
				for x in range(3, map.w - 4):
					if int(map.grid[y][x]) == map.TILE_WATER:
						mid_water = true
			_check(mid_water, label + ": мир «inner» несёт внутреннее море")
			_check(not sea, label + ": мир «inner» без океана у южного края")
		else:
			_check(sea, label + ": океан лежит вдоль южного края (режим %s)" % map.sea_mode)

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
	# v1.43: типы воды хранятся строками-рядами — проверяем восстановление
	var wk_rows: Array = block["map"]["water_kind"]
	_check((wk_rows as Array).size() == map2.h,
			"типы воды уходят в сейв (%d рядов)" % (wk_rows as Array).size())
	var wk_before: int = map2.water_kind.size()
	map2.water_kind = {}
	sv._apply_kind_rows(map2, wk_rows)
	_check(map2.water_kind.size() == wk_before,
			"типы воды восстанавливаются из рядов (%d)" % map2.water_kind.size())
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


## Биом-регионы и пергаментный туман — «Мир v2» этап 2 (v1.40):
## режим моря — рандом мира; снег/вулкан/пустыня/мёртвель красят сушу
## и дорожают путь; вода/болото не перекрашиваются; регионы в сейве.
func _test_world2_regions() -> void:
	print("[Мир v2 / этап 2: биом-регионы и пергамент]")
	var cfg: Dictionary = _read_json("res://data/world.json")
	var ids: Array = []
	for e: Dictionary in cfg["regions"]["list"]:
		ids.append(String(e["id"]))

	var modes := {}
	var region_found := {}
	for seed_value in SEEDS + [777, 5150, 90210]:
		var map = load("res://scripts/world_map.gd").new()
		map.generate(seed_value, cfg)
		modes[map.sea_mode] = true
		_check(map.sea_mode in ["ocean", "inner", "both"],
				"сид %d: режим моря корректен (%s)" % [seed_value, map.sea_mode])
		# регионы: валидные id, только на суше, не на болоте
		var ok_tiles := true
		for t: Vector2i in map.region:
			if not ids.has(String(map.region[t])):
				ok_tiles = false
			if int(map.grid[t.y][t.x]) == map.TILE_WATER 					or int(map.grid[t.y][t.x]) == map.TILE_SWAMP:
				ok_tiles = false
		_check(ok_tiles, "сид %d: регионы валидны и только на суше" % seed_value)
		if not map.region.is_empty():
			for t2: Vector2i in map.region:
				region_found[String(map.region[t2])] = true
		# цена пути: в регионе дороже базовой
		var any_region: Vector2i = map.region.keys()[0] if not map.region.is_empty() else Vector2i(-1, -1)
		if any_region.x >= 0:
			var rd: Dictionary = map.region_def(String(map.region[any_region]))
			var base: float = float(cfg["biomes"]["plains"]["cost"])
			if int(map.grid[any_region.y][any_region.x]) == map.TILE_PLAINS:
				_check(absf(map.tile_cost(any_region) - base * float(rd["cost_mult"])) < 0.001,
						"сид %d: регион дорожает путь (x%s)" % [seed_value, String(rd["cost_mult"])])
	# рандом мира даёт разные режимы на серии сидов
	_check(modes.size() >= 2, "режим моря рандомится по сидам (%s)" % [modes.keys()])
	# хотя бы один регион встретился на серии сидов
	_check(region_found.size() >= 2, "регионы встречаются на картах (%s)" % [region_found.keys()])
	# цвета регионов парсятся
	for e2: Dictionary in cfg["regions"]["list"]:
		for tn in e2["colors"]:
			var c := Color(String(e2["colors"][tn]))
			_check(c.a == 1.0, "цвет региона %s/%s парсится" % [String(e2["id"]), String(tn)])
	# пергаментный туман (№112, вариант агента): конфиг на месте
	_check(String(cfg["fog"]["parchment"]) != "", "пергаментный туман настроен (№112)")


## Туман — чёрная пелена со стиранием (v1.40.2): reveal_around отдаёт
## только НОВЫЕ тайлы в fog_new (повторное раскрытие не стирает заново).
func _test_world2_fog_erase() -> void:
	print("[Мир v2 / этап 2: стирание тумана]")
	var cfg: Dictionary = _read_json("res://data/world.json")
	var map = load("res://scripts/world_map.gd").new()
	map.generate(4242, cfg)
	var city: Vector2i = map.city_tile
	map.fog.clear()
	map.fog_new.clear()   # генерация уже наполнила (city_reveal) — чистим
	map.reveal_around(city, 5)
	var first: int = (map.fog_new as Array).size()
	_check(first >= 40, "первое раскрытие открывает круг (%d тайлов)" % first)
	# все новые тайлы действительно новые и у города
	var ok_new := true
	for t: Vector2i in map.fog_new:
		if map.fog.get(t) != true or Vector2(t).distance_to(Vector2(city)) > 5.5:
			ok_new = false
	_check(ok_new, "fog_new содержит только что раскрытые тайлы")
	map.fog_new.clear()   # view сливает список каждый кадр (эмуляция)
	map.reveal_around(city, 5)
	_check((map.fog_new as Array).is_empty(),
			"повторное раскрытие того же места не даёт новых тайлов")
	map.fog_new.clear()
	map.reveal_around(city + Vector2i(4, 0), 3)
	_check((map.fog_new as Array).size() > 0,
			"соседнее раскрытие даёт новые тайлы (рассеяние по мере ходьбы)")
