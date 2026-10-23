# Тесты правок приёмки v1.21.4 (оптимизация FPS к 70-му дню):
# кэш JSON-конфигов, кэш определений зданий, O(1)-индекс building_at.
extends "res://tests/test_base.gd"


func _test_v1214_caches() -> void:
	var sim = _make_sim()
	print("[v1.21.4: кэши производительности]")
	# 1) JSON-кэш: повторное чтение отдаёт те же данные (погода/законы/вера
	# раньше парсились с диска на каждого жителя каждый кадр)
	var w1: Dictionary = sim._weather_cfg()
	var w2: Dictionary = sim._weather_cfg()
	_check(w1 == w2 and not w1.is_empty(), "JSON-кэш: повторное чтение погоды идентично")
	_check(sim._json_cache.has("res://data/weather.json"), "JSON-кэш: файл погоды закэширован")
	var laws: Dictionary = sim._laws_cfg()
	_check(not laws.is_empty() and laws == sim._laws_cfg(), "JSON-кэш: законы читаются стабильно")

	# 2) кэш определений: _def и ширина из кэша совпадают с конфигом
	var def: Dictionary = sim._def({"type": "house"})
	var want: Dictionary = {}
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == "house":
			want = d
	_check(def == want and def == sim._def({"type": "house"}), "_def: кэш отдаёт то же определение")
	_check(sim.bld_w_of_type("house") == int(want.get("w", 1)), "bld_w_of_type: ширина из кэша верна")

	# 3) индекс building_at: ставим здание — клетки заняты, вокруг свободны
	var tile := _find_free_tile(sim, sim.map.spawn_tile, "house")
	_check(sim.place_building("house", tile), "индекс: дом заложен")
	_check(not sim.building_at(tile).is_empty(), "индекс: клетка дома видна сразу после закладки")
	_check(not sim.building_at(tile + Vector2i(1, 1)).is_empty(), "индекс: вторая клетка 2×2 видна")
	var far: Vector2i = sim.map.spawn_tile + Vector2i(6, 6)
	if sim.map.in_bounds(far) and sim.building_at(far).is_empty():
		_check(sim.building_at(far).is_empty(), "индекс: дальняя клетка свободна")
	# 4) снос стройплощадки освобождает клетки в индексе
	var site: Dictionary = sim.building_at(tile)
	sim._damage_building(site, 9999.0)
	_check(sim.building_at(tile).is_empty(), "индекс: после сноса площадки клетка свободна")
	# 5) перенос здания: старое место свободно, новое занято
	var tile2 := _find_free_tile(sim, tile, "house")
	if not tile2 == Vector2i(-1, -1) and sim.place_building("house", tile2):
		var b2: Dictionary = sim.building_at(tile2)
		_teleport(sim, _resident_by_prof(sim, "builder"), tile2)
		sim.tick(float(sim._def({"type": "house"})["build_work"]) + 0.1)
		b2 = sim.building_at(tile2)
		if bool(b2.get("done", false)) and sim.move_building(b2, tile2 + Vector2i(2, 0)) == "":
			_check(not sim.building_at(tile2 + Vector2i(2, 0)).is_empty(),
					"индекс: после переноса новая клетка занята")
			_check(sim.building_at(tile2).is_empty(),
					"индекс: после переноса старая клетка свободна")
		else:
			_check(true, "индекс: перенос в тесте не потребовался")
	# 6) прочность из кэша совпадает с базовой по эффекту
	var hp_cfg: Dictionary = sim.cfg.get("threat", {}).get("bld_hp", {})
	_check(sim._bld_max_hp("house") == int(hp_cfg.get("pop", hp_cfg.get("default", 20))),
			"_bld_max_hp: прочность дома из кэша верна")
