# Правки приёмки v1.26 (заказчик, 2026-10-25): ворота пропускают своих,
# мутанты ломают стены (и при герое за стеной) и проходят через пролом,
# районы-цвета — рекомендация, FPS в обнесённой стенами осаде.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


## Мгновенно поставить и достроить здание (без строителя) — для каркаса карт.
func _place_now(sim: Object, type_id: String, tile: Vector2i) -> Dictionary:
	if not sim.place_building(type_id, tile):
		return {}
	var b: Dictionary = sim.building_at(tile)
	if b.is_empty():
		return {}
	sim._complete_site(b)
	return sim.building_at(tile)


## Первые реально поставленные ворота кольца (проём мог попасть на воду).
func _first_gate_tile(sim: Object) -> Vector2i:
	for off in sim._gate_offsets():
		var gt: Vector2i = sim.map.spawn_tile + (off as Vector2i)
		var b: Dictionary = sim.building_at(gt)
		if not b.is_empty() and String(b["type"]) == "gate":
			return gt
	return Vector2i(-1, -1)


## Кольцо стен + ворота во всех четырёх проёмах (город заперт наглухо).
func _build_wall_ring(sim: Object) -> int:
	sim.res["wood"] = 500.0
	sim.res["stone"] = 200.0
	var placed := 0
	for i in 220:
		var wt: Vector2i = sim._next_wall_tile()
		if wt == Vector2i(-1, -1):
			break
		if _place_now(sim, "wall", wt).is_empty():
			break
		placed += 1
	for off in sim._gate_offsets():
		var gt: Vector2i = sim.map.spawn_tile + (off as Vector2i)
		if not _place_now(sim, "gate", gt).is_empty():
			placed += 1
	return placed


## Ближайшая к городу проходимая клетка ЗА кольцом (у аномалии).
func _tile_outside_ring(sim: Object) -> Vector2i:
	for radius in range(sim.WALL_RING + 1, sim.map.w):
		var t: Vector2i = sim.map.spawn_tile + Vector2i(radius, 0)
		if sim.map.in_bounds(t) and sim.map.is_walkable(t):
			return t
	return sim.map.spawn_tile


## Ворота — дверь для своих (жители и герой проходят всегда, закрыты только
## для мутантов); кольцо стен реально запирает город от волны.
func _test_v126_gates() -> void:
	print("[v1.26: ворота пропускают жителей и героя]")
	var sim := _make_sim()
	sim._last_daily_day = 999
	var ring := _build_wall_ring(sim)
	_check(ring >= 40, "кольцо стен с воротами построено (%d тайлов)" % ring)
	var gate_tile := _first_gate_tile(sim)
	_check(gate_tile != Vector2i(-1, -1), "ворота в кольце стоят")
	if gate_tile == Vector2i(-1, -1):
		return
	var outside := _tile_outside_ring(sim)
	# своих ворота выпускают: путь из центра наружу есть (через ворота)
	_check(not sim.map.path_px(sim.map.tile_center_px(sim.map.spawn_tile), outside).is_empty(),
			"житель из запертого города выходит через ворота")
	# мутантов закрытые ворота не пускают (без вышек со стражем все заперты)
	_check(sim.map.path_px(sim.map.tile_center_px(sim.map.spawn_tile), outside, true).is_empty(),
			"мутант снаружи не проходит в город через запертые ворота")
	_check(not sim.map.is_raider_walkable(gate_tile),
			"тайл закрытых ворот сплошной для мутантов")
	_check(sim.map.is_walkable(gate_tile),
			"тот же тайл проходим для жителей и героя")
	# страж на вышке у ворот открывает их и для мутантов
	var tt := Vector2i(-1, -1)
	for radius in range(1, 6):
		if tt != Vector2i(-1, -1):
			break
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t: Vector2i = gate_tile + Vector2i(dx, dy)
				if sim.is_buildable_rect("tower", t) and sim.placement_gap_ok("tower", t):
					tt = t
					break
			if tt != Vector2i(-1, -1):
				break
	_check(tt != Vector2i(-1, -1), "у ворот нашлось место 2×2 под вышку")
	if tt == Vector2i(-1, -1):
		return
	var tower := _place_now(sim, "tower", tt)
	_check(not tower.is_empty() and bool(tower["done"]), "вышка у ворот построена")
	tower["worker"] = int(sim.residents[0]["id"])
	sim._update_gates()
	var gate_b: Dictionary = sim.building_at(gate_tile)
	_check(sim.is_gate_open(gate_b), "страж на вышке открыл ворота")
	_check(not sim.map.path_px(sim.map.tile_center_px(sim.map.spawn_tile), outside, true).is_empty(),
			"открытые ворота проходимы и для мутантов")
	# разрушенные ворота — пролом для всех
	tower["worker"] = -1
	sim._update_gates()
	sim._damage_building(gate_b, 9999.0)
	_check(bool(gate_b.get("razed", false)), "ворота разрушены")
	_check(sim.map.is_raider_walkable(gate_tile), "пролом в воротах проходим для мутантов")


## Мутант ломает ворота/стену даже когда герой стоит за ними в радиусе аггро
## (раньше залипал «иду к герою» с пустым путём), и после пролома
## продолжает путь в город.
func _test_v126_raiders_walls() -> void:
	print("[v1.26: мутанты ломают стены и проходят через пролом]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	sim._last_daily_day = 999
	# город без ополчения (остаётся только голем-староста) — чистая осада
	for r in sim.residents.duplicate():
		if String(r["prof"]) != "elder":
			sim.residents.erase(r)
	for r in sim.residents:
		r["traits"] = []
	# запертое кольцо стен с воротами: герой внутри у восточных ворот,
	# мутант снаружи у тех же ворот — видит героя, но путь закрыт
	_build_wall_ring(sim)
	var gate_e: Vector2i = sim.map.spawn_tile + Vector2i(sim.WALL_RING, 0)
	var gate_b: Dictionary = sim.building_at(gate_e)
	_check(not gate_b.is_empty() and String(gate_b["type"]) == "gate",
			"восточные ворота кольца на месте")
	if gate_b.is_empty():
		return
	var hero_tile: Vector2i = sim.map.nearest_walkable(
			sim.map.spawn_tile + Vector2i(sim.WALL_RING - 2, 0))
	sim.hero_alive = true
	sim.hero_pos = sim.map.tile_center_px(hero_tile)
	var raider := _spawn_one_raider(sim, "mutant",
			sim.map.nearest_walkable(gate_e + Vector2i(1, 0)))
	var aggro: float = float(raider["p"]["aggro"])
	_check(sim.map.tile_center_px(sim.map.tile_of_px(raider["pos"])).distance_to(sim.hero_pos) <= aggro,
			"мутант видит героя за воротами (в радиусе аггро)")
	_check(sim.map.path_px(raider["pos"], hero_tile, true).is_empty(),
			"путь мутанта к герою закрыт воротами")
	var hp0 := float(gate_b["hp"])
	var ticks := 0
	for i in 1500:   # ворота 40 hp, мутант бьёт 2 раз в секунду + подход
		sim.tick(0.2)
		ticks = i
		if bool(sim.building_at(gate_e).get("razed", false)):
			break
	_check(bool(sim.building_at(gate_e).get("razed", false)) or float(sim.building_at(gate_e)["hp"]) < hp0,
			"мутант ломает ворота, а не толчётся перед ними с героем за стеной (тик %d)" % ticks)
	# пролом открыт — мутант идёт к герою, путь пересчитался сам.
	# v1.28: порог 1.5 тайла — вплотную мутанта не подпускает контактная
	# остановка («монстры не входят в модель персонажа», v1.26)
	var dist0: float = (raider["pos"] as Vector2).distance_to(sim.hero_pos)
	var moved_in := false
	for i in 600:
		sim.tick(0.2)
		if sim.raiders.is_empty():
			break   # пал под городом — значит, вошёл
		if (raider["pos"] as Vector2).distance_to(sim.hero_pos) < dist0 - float(sim.map.ts) * 1.5:
			moved_in = true
			break
	_check(moved_in, "через разрушенные ворота мутант проходит к герою")


## Кладбище строится рядом с могилами (могилы по дизайну в 10+ клетках
## от города — районное правило «своего цвета» больше не запрещает).
func _test_v126_cemetery() -> void:
	print("[v1.26: кладбище строится у могил]")
	var sim := _make_sim()
	sim._last_daily_day = 999
	# в городе стоит таверна — «специальная» ветка существует (раньше держала район)
	var tavern := _build_now(sim, "tavern")
	_check(bool(tavern["done"]), "таверна (ветка special) построена")
	var spot: Vector2i = sim._found_cemetery_tile()
	_check(spot != Vector2i(-1, -1), "место под кладбище нашлось")
	sim.cemetery_tile = spot
	sim.graves.append({"tile": spot, "name": "Старый", "ready": true, "rite": "bury"})
	# 2×2 рядом с могилой: то самое место, куда игрок хочет поставить здание
	var near_grave := Vector2i(-1, -1)
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t: Vector2i = spot + Vector2i(dx, dy)
				if sim.is_buildable_rect("cemetery", t) and sim.placement_gap_ok("cemetery", t):
					near_grave = t
					break
			if near_grave != Vector2i(-1, -1):
				break
		if near_grave != Vector2i(-1, -1):
			break
	_check(near_grave != Vector2i(-1, -1), "у могил нашлось место 2×2")
	_check(sim.placement_block("cemetery", near_grave) == "",
			"кладбище у могил строить можно (районы — рекомендация)")
	var cem := _place_now(sim, "cemetery", near_grave)
	_check(not cem.is_empty() and bool(cem["done"]), "кладбище у могил построено")


## FPS-дым: запертый стенами город ~38 жителей + осада у стен — тик должен
## укладываться в бюджет кадра (замер печатается, порог щедрый для CI).
func _test_v126_fps() -> void:
	print("[v1.26: тик осады у стен не роняет FPS]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	sim._last_daily_day = 999
	sim.res["food"] = 500.0
	_build_wall_ring(sim)
	# население как в плейтесте заказчика (38), герои-ополченцы бегают по пути
	var extra := 0
	while sim.residents.size() < 38:
		var profs := ["farmer", "guard", "lumberjack", "miner", "crafter"]
		var r_x: Dictionary = sim._new_resident("Тар%d" % extra,
				profs[extra % profs.size()], sim.map.spawn_tile)
		r_x["traits"] = []
		sim.residents.append(r_x)
		sim._next_id += 1
		extra += 1
	sim.hero_alive = true
	sim.hero_pos = sim.map.tile_center_px(sim.map.spawn_tile)
	sim._spawn_raid(6, false)
	_check(sim.raid_active and sim.raiders.size() == 6, "осада из 6 мутантов у стен")
	var t_start := Time.get_ticks_usec()
	var ticks := 240
	for i in ticks:
		sim.tick(1.0 / 30.0)
	var elapsed_ms := float(Time.get_ticks_usec() - t_start) / 1000.0
	var per_tick := elapsed_ms / float(ticks)
	print("    тик осады: %.2f мс (%d тиков, %.0f мс всего)" % [per_tick, ticks, elapsed_ms])
	_check(per_tick < 25.0, "тик осады у стен дешевле 25 мс (%.2f мс)" % per_tick)
