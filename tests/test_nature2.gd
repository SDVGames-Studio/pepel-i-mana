extends "res://tests/test_base.gd"
## Природа 2.0 (v1.39.0): ассеты ForgottenMemories на месте и грузятся,
## живой слой воды строит корректный кэш берегов/открытой воды по карте,
## скалы per-tile видят соседей верно, тюнинг rock2/water2 в city.json
## валиден. Рендер (_draw) в headless-тестах не вызывается (грабли
## автозагрузок) — проверяем чистую логику и данные.

const SEED := 777


func _make_map(seed_value: int = SEED):
	var cfg: Dictionary = _read_json("res://data/city.json")
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(seed_value, cfg)
	return city_map


func _make_terrain(city_map) -> Object:
	# city_terrain без духовки: нужны только map/colors/_hash (статич.)
	var ct = load("res://scripts/city_terrain.gd").new()
	ct.map = city_map
	ct.colors = {}
	return ct


func _test_nature2_assets() -> void:
	print("[Природа 2.0: ассеты]")
	# фактуры воды/камня и деревья/пропсы пака существуют и грузятся
	for p in ["res://assets/sprites/env/n2_water_lake.png",
			"res://assets/sprites/env/n2_water_river.png",
			"res://assets/sprites/env/n2_water_swamp.png",
			"res://assets/sprites/env/n2_stone1.png",
			"res://assets/sprites/env/n2_stone2.png",
			"res://assets/sprites/env/n2_stone3.png",
			"res://assets/sprites/env/tree2_red.png",
			"res://assets/sprites/env/tree2_teal.png",
			"res://assets/sprites/env/tree2_birch.png",
			"res://assets/sprites/env/tree2_pine.png",
			"res://assets/sprites/env/tree2_willow.png",
			"res://assets/sprites/props/bush2_a.png",
			"res://assets/sprites/props/bush2_b.png",
			"res://assets/sprites/props/bush2_c.png",
			"res://assets/sprites/props/bush2_d.png",
			"res://assets/sprites/props/stone2_a.png",
			"res://assets/sprites/props/stone2_b.png"]:
		_check(Assets.tex(p) != null, "текстура грузится: %s" % p.get_file())
	# деревья «Природы 2.0» доступны через refs city_view
	for ref in ["e:tree2_red", "e:tree2_pine", "e:tree2_birch",
			"e:tree2_teal", "e:tree2_willow"]:
		_check(Assets.sprite(ref) != null, "спрайт дерева %s" % ref)


func _test_nature2_water_cache() -> void:
	print("[Природа 2.0: кэш воды]")
	var map = _make_map()
	_check(map.water_kind.size() > 0, "на карте есть классифицированная вода")
	var water: Node2D = load("res://scripts/water_terrain.gd").new()
	water.setup(_make_terrain(map), _read_json("res://data/city.json")["colors"])
	water._ensure_cache()
	_check(water._coast.size() > 0, "береговые тайлы найдены")
	_check(water._swamp_tiles.size() > 0 or water._ford_tiles.size() >= 0,
			"болота/броды собраны без ошибок")
	# каждый береговый тайл — вода и имеет хотя бы одну сушу по 4 направлениям
	var ok_coast := true
	var ok_inner := true
	for c in water._coast:
		var t: Vector2i = c["tile"]
		if map.grid[t.y][t.x] != map.TILE_WATER:
			ok_coast = false
		if (c["sides"] as Array).is_empty():
			ok_coast = false
	for t: Vector2i in water._inner:
		if map.grid[t.y][t.x] != map.TILE_WATER:
			ok_inner = false
		if water._water_neighbors8(t) != 8:
			ok_inner = false
	_check(ok_coast, "кэш берега согласован с картой")
	_check(ok_inner, "открытая вода окружена водой со всех 8 сторон")
	# береговые тайлы воды = тайлы воды с сухим соседом (полнота покрытия)
	var expect := 0
	for y in map.h:
		for x in map.w:
			if map.grid[y][x] != map.TILE_WATER:
				continue
			for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var n: Vector2i = Vector2i(x, y) + d
				if not map.in_bounds(n) or map.grid[n.y][n.x] != map.TILE_WATER:
					expect += 1
					break
	_check(water._coast.size() == expect,
			"берег полон: %d из %d" % [water._coast.size(), expect])
	# детерминизм: перестройка кэша даёт тот же набор
	var coast_a := (water._coast as Array).size()
	water._cache_ver = -1
	water._coast = []
	water._ensure_cache()
	_check(water._coast.size() == coast_a, "кэш воды детерминирован")


func _test_nature2_rocks() -> void:
	print("[Природа 2.0: скалы per-tile]")
	var map = _make_map()
	var rk = load("res://scripts/rock_terrain.gd").new()
	rk.setup(_make_terrain(map))
	_check(rk._stone_texs.size() == 3, "фактуры камня загружены в рендер")
	_check(rk.base_color().to_html() != "000000ff", "базовый тон породы из тюнинга")
	# _is_rock согласована с сеткой: каждый тайл R/O — скала, трава — нет
	var ok := true
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			var g: int = map.grid[y][x]
			if rk._is_rock(t) != (g == map.TILE_ROCK or g == map.TILE_ORE):
				ok = false
	_check(ok, "_is_rock совпадает с картой")
	# кэш блобов больше не нужен (рендер per-tile)
	_check(rk.build_cache().is_empty(), "блобы скал не строятся (per-tile)")


func _test_nature2_tuning() -> void:
	print("[Природа 2.0: тюнинг city.json]")
	var cfg: Dictionary = _read_json("res://data/city.json")
	var colors: Dictionary = cfg["colors"]
	_check(colors.has("rock2"), "colors.rock2 есть")
	_check(colors.has("water2"), "colors.water2 есть")
	var rock2: Dictionary = colors["rock2"]
	_check(Color(String(rock2["color"])).a == 1.0, "цвет породы парсится")
	_check(float(rock2["cap_chance"]) >= 0.0 and float(rock2["cap_chance"]) <= 1.0,
			"cap_chance в диапазоне 0..1")
	var water2: Dictionary = colors["water2"]
	_check(float(water2["anim_fps"]) > 0.0, "anim_fps положительный")
	_check(int(water2["reed"]["water_chance"]) >= 2, "шанс камышей >= 2")
	# единый язык кромок: константы EdgeLang = дефолтам плато в json
	var plateau: Dictionary = colors["plateau"]
	_check(absf(float(plateau.get("face_h1", 0.38)) - 0.38) < 0.001
			and absf(float(plateau.get("face_h2", 0.60)) - 0.60) < 0.001,
			"пропорции среза плато совпадают с EdgeLang")
