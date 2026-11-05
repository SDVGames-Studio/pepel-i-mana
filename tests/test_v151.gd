# v1.51 «Карта и место»: обзорная карта города (данные/легенда) и выбор
# места города на старте (валидация клетки, перенос города на карте мира).
extends "res://tests/test_base.gd"


func _test_v151_overview() -> void:
	print("[v1.51: обзорная карта города]")
	var sim := _make_sim()
	var ov = load("res://scripts/city_overview.gd").new()
	ov.setup(sim.map, sim)
	_check(ov.legend_entries().size() >= 8, "легенда: есть ключевые цвета")
	# цвет тайла — чистая функция: вода/скала/руда/дерево/луг/дорога
	var m = sim.map
	var kinds := {"water": false, "rock": false, "tree": false, "grass": false}
	for y in m.h:
		for x in m.w:
			var t := Vector2i(x, y)
			var g: int = m.grid[y][x]
			var c: Color = ov._tile_color(t)
			if g == m.TILE_WATER and c == Color(0.25, 0.47, 0.68):
				kinds["water"] = true
			elif g == m.TILE_ROCK and c == Color(0.55, 0.55, 0.58):
				kinds["rock"] = true
			elif g == m.TILE_TREE and c == Color(0.16, 0.34, 0.16):
				kinds["tree"] = true
			elif g == m.TILE_GRASS and not m.road.has(t) \
					and c == Color(0.35, 0.62, 0.28):
				kinds["grass"] = true
	_check(kinds["water"], "обзор: вода своим цветом")
	_check(kinds["rock"], "обзор: скалы своим цветом")
	_check(kinds["tree"], "обзор: лес своим цветом")
	_check(kinds["grass"], "обзор: луг своим цветом")
	# запечка карты в текстуру: размер = тайлы карты
	ov._rebake_map()
	_check(ov._tex != null and int(ov._tex.get_width()) == m.w
			and int(ov._tex.get_height()) == m.h,
			"обзор: земля запечена 1px/тайл (%dx%d)" % [int(ov._tex.get_width()), int(ov._tex.get_height())])
	ov.free()


func _test_v151_start_pick() -> void:
	print("[v1.51: выбор места города на старте]")
	var wcfg: Dictionary = _read_json("res://data/world.json")
	var wm = load("res://scripts/world_map.gd").new()
	wm.generate(42, wcfg)
	# валидатор клетки: вода/болото/русло — отказ, край — отказ
	var water := Vector2i(-1, -1)
	var land := Vector2i(-1, -1)
	var center := Vector2i(wm.w / 2, wm.h / 2)
	var bd := 1 << 30
	for y in range(4, wm.h - 4):
		for x in range(4, wm.w - 4):
			var t := Vector2i(x, y)
			if water == Vector2i(-1, -1) \
					and wm.grid[t.y][t.x] == wm.TILE_WATER:
				water = t
			# годная клетка — БЛИЖЕ К ЦЕНТРУ (кольцо «двери» 3–5 влезает)
			if wm.can_found_city_at(t, []) == "":
				var d := int(Vector2(t).distance_to(Vector2(center)))
				if d < bd:
					bd = d
					land = t
	_check(land != Vector2i(-1, -1), "валидатор: годная клетка найдена")
	_check(water != Vector2i(-1, -1), "на карте есть вода для отказа")
	_check(wm.can_found_city_at(water, []) == "pick.bad_water",
			"валидатор: на воде город не ставится")
	_check(wm.can_found_city_at(Vector2i(0, 0), []) == "pick.bad_edge",
			"валидатор: у края карты город не ставится")
	# рядом с поселением — отказ
	if not _occupancies(wm).is_empty() and land != Vector2i(-1, -1):
		var near: Vector2i = Vector2i(_occupancies(wm)[0]) + Vector2i(2, 0)
		if wm.in_bounds(near):
			_check(wm.can_found_city_at(near, _occupancies(wm)) == "pick.bad_near",
					"валидатор: рядом с поселением нельзя")
	# перенос города: POI города двигается, площадка чистится
	var old_tile: Vector2i = wm.city_tile
	wm.set_city_tile(land)
	_check(wm.city_tile == land, "set_city_tile: город перенесён")
	var city_pois := 0
	for poi in wm.pois:
		if String(poi["kind"]) == "city":
			city_pois += 1
			_check(Vector2i(poi["tile"]) == land, "POI города на новой клетке")
	_check(city_pois == 1, "POI города на карте один")
	# «дверь» в данж переехала вместе с городом (3–5 клеток)
	var gate_far := false
	for poi in wm.pois:
		if String(poi["kind"]) == "dungeon" and String(poi["biome"]) == "":
			var d: float = Vector2(poi["tile"]).distance_to(Vector2(land))
			if d > 7.0:
				gate_far = true
	_check(not gate_far, "городская аномалия рядом с новым местом")
	_check(wm.tile_hydro(land) is Dictionary, "гидро-контекст новой клетки читается")


func _occupancies(wm) -> Array:
	var out: Array = []
	for poi in wm.pois:
		if String(poi["kind"]) == "settlement":
			out.append(Vector2i(poi["tile"]))
	return out
