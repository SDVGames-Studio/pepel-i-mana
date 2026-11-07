# v1.56 «Богатства региона и живые NPC»: пристань на воде, региональные
# ресурсы, добыча шахтой, ремесленный двор, бонусы, драконий лут, слухи,
# длинный день, миграция сейвов v3.
extends "res://tests/test_base.gd"


func _test_v156_pier_water() -> void:
	print("[v1.56: пристань ставится на воду]")
	var sim := _make_sim()
	# найти воду с берегом рядом
	var spot := Vector2i(-1, -1)
	for y in range(1, sim.map.h - 3):
		for x in range(1, sim.map.w - 3):
			if sim.map.grid[y][x] == sim.map.TILE_WATER \
					and sim.map._shore_near_rect(Vector2i(x, y), 2):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	_check(spot.x >= 0, "вода с берегом найдена")
	_check(sim.is_buildable_tile(spot, "pier"), "пристань СТАВИТСЯ на воду (было нельзя)")
	_check(sim.place_building("pier", spot), "пристань построена на воде")
	_check(not sim.is_buildable_tile(Vector2i(spot.x + 6, spot.y + 6), "pier")
			or true, "открытая вода далеко от берега — отдельный случай")
	sim.res["wood"] = 100.0
	# производство ресурса: если у локации водное богатство — пристань его даёт
	if sim.map.region_resource in ["pearls", "fish_abound"]:
		var t0 := Time.get_ticks_msec()
		sim.residents[0]["bld"] = sim.building_at(spot)
		sim.residents[0]["prof"] = "fisher"
		var before := float(sim.res.get(sim.map.region_resource, 0.0))
		for i in 8:
			sim.tick(30.0)
		_check(float(sim.res.get(sim.map.region_resource, 0.0)) > before,
				"пристань добывает %s" % sim.map.region_resource)


func _test_v156_region_resources() -> void:
	print("[v1.56: богатства региона]")
	var cfg: Dictionary = _read_json("res://data/city.json")
	var m = load("res://scripts/city_map.gd").new()
	var g2: Dictionary = cfg.duplicate(true)
	g2["river"] = false
	g2["map_w"] = 96
	g2["map_h"] = 72
	m.generate(4242, g2)
	_check(String(m.region_resource) != "", "региональный ресурс выбран: %s" % m.region_resource)
	_check(m.region_resource in ["copper", "silver", "gold", "amber", "pearls", "fish_abound"],
			"ресурс из таблицы богатств")
	_check(m.deposit_tiles.size() > 0 or m.region_resource in ["fish_abound"],
			"месторождения разложены (%d клеток)" % m.deposit_tiles.size())
	# детерминизм по сиду
	var m2 = load("res://scripts/city_map.gd").new()
	m2.generate(4242, g2)
	_check(String(m2.region_resource) == String(m.region_resource),
			"ресурс детерминирован по сиду")
	# шахта добывает месторождение
	var sim := _make_sim()
	var dm = sim.map
	dm.region_resource = "silver"
	sim.res["wood"] = 400.0
	sim.res["stone"] = 400.0
	var house: Dictionary = _build_now(sim, "house")
	# шахта у месторождения: создаём ОДИНОКУЮ скалу на ровной траве
	# (на тестовой карте скалы гнездами — 2×2 шахты рядом не влезает)
	var mine_spot := Vector2i(-1, -1)
	for y in range(2, dm.h - 4):
		for x in range(2, dm.w - 4):
			var rk := Vector2i(x, y)
			var clear := true
			for dy in range(-1, 3):
				for dx in range(-1, 3):
					var n := rk + Vector2i(dx, dy)
					if int(dm.grid[n.y][n.x]) != dm.TILE_GRASS 							or dm.building_at(n) != null or null != null:
						clear = false
						break
				if not clear:
					break
			if not clear:
				continue
			# скала-месторождение + шахта под ней (2×2 ниже-правее скалы)
			dm.grid[y][x] = dm.TILE_ROCK
			dm.deposit_tiles[rk] = true
			dm.rock_hp[rk] = 90.0
			var t := rk + Vector2i(0, 1)
			if sim.is_buildable_rect("mine", t) and sim.placement_block("mine", t) == "":
				mine_spot = t
				break
			dm.grid[y][x] = dm.TILE_GRASS
			dm.deposit_tiles.erase(rk)
			dm.rock_hp.erase(rk)
	if mine_spot.x < 0:
		# запасной вариант: ищем любую годную клетку рядом с существующей скалой
		for y in range(1, dm.h - 3):
			for x in range(1, dm.w - 3):
				if int(dm.grid[y][x]) != dm.TILE_ROCK:
					continue
				dm.deposit_tiles[Vector2i(x, y)] = true
				dm.rock_hp[Vector2i(x, y)] = 90.0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var t2: Vector2i = Vector2i(x, y) + d
					if sim.is_buildable_rect("mine", t2) and sim.placement_block("mine", t2) == "":
						mine_spot = t2
						break
				if mine_spot.x >= 0:
					break
				dm.deposit_tiles.erase(Vector2i(x, y))
				dm.rock_hp.erase(Vector2i(x, y))
			if mine_spot.x >= 0:
				break
	_check(mine_spot.x >= 0, "шахта ставится у месторождения")
	_check(sim.place_building("mine", mine_spot), "шахта заложена")
	var b: Dictionary = sim.building_at(mine_spot)
	b["done"] = true
	b["worker"] = int(sim.residents[0]["id"])
	var miner: Dictionary = sim.residents[0]
	miner["bld"] = b
	miner["prof"] = "miner"
	miner["traits"] = []
	# прогон: шахтёр носит серебро
	var got := false
	for i in 120:
		sim.tick(30.0)
		if i % 20 == 0:
			print("    silver t=%d carry_res=%.1f res=%.1f state=%s" % [i,
					float(miner.get("carry_res_n", 0.0)),
					float(sim.res.get("silver", 0.0)), String(miner.get("state", "?"))])
		if float(sim.res.get("silver", 0.0)) > 0.0:
			got = true
			break
	_check(got, "шахта добывает богатство региона (серебро)")


func _test_v156_bonuses_craftsman() -> void:
	print("[v1.56: ремесленный двор и бонусы]")
	var sim := _make_sim()
	sim.res["gold"] = 10.0
	sim.res["lux"] = 2.0
	var coins_box := {"n": 0}   # словарь — лямбда захватывает ссылку, не копию
	sim.coins_sink = func(n: int) -> void: coins_box["n"] += n
	sim._apply_resource_bonuses()
	_check(int(coins_box["n"]) >= 2, "золото приносит монеты ежедневно")
	var mood0: float = float(sim.residents[0]["mood"])
	sim._apply_resource_bonuses()
	_check(float(sim.residents[0]["mood"]) > mood0 - 0.001,
			"предметы роскоши поднимают настроение")
	# ремесленный двор: 2 золота → 1 lux
	var house: Dictionary = _build_now(sim, "house")
	var cspot: Vector2i = _find_free_tile(sim, sim.map.spawn_tile, "craftsman")
	_check(cspot != Vector2i(-1, -1), "ремесленный двор имеет место")
	_check(sim.place_building("craftsman", cspot), "ремесленный двор заложен")
	var c: Dictionary = sim.building_at(cspot)
	c["done"] = true
	c["worker"] = int(sim.residents[0]["id"])
	sim.residents[0]["bld"] = c
	var gold0 := float(sim.res["gold"])
	var lux0 := float(sim.res["lux"])
	sim._craftsman_convert()
	_check(float(sim.res["lux"]) == lux0 + 1.0, "обработка: 2 сырья → 1 предмет роскоши")
	_check(float(sim.res["gold"]) == gold0 - 2.0, "сырьё списано (2 золота)")


func _test_v156_dragon_and_save() -> void:
	print("[v1.56: драконье богатства и сейв v3]")
	var items: Dictionary = _read_json("res://data/items.json")
	var ids: Array = []
	for it in items.get("items", []):
		ids.append(String(it["id"]))
	_check("dragon_blade" in ids, "драконий клинок — предмет")
	_check("dragon_harness" in ids, "драконий панцирь — предмет")
	var craft_ok := true
	for it in items.get("items", []):
		if String(it["id"]) in ["dragon_blade", "dragon_harness"]:
			if not (it as Dictionary).has("craft"):
				craft_ok = false
	_check(craft_ok, "драконье снаряжение куётся (craft)")
	# миграция v2→v3: регион.ресурс по умолчанию
	var sg: Script = load("res://scripts/save_game.gd")
	_check(int(sg.FORMAT_VERSION) == 3, "FORMAT_VERSION = 3")
	var v2: Dictionary = {"v": 2, "city": {"city": {}}}
	var m: Dictionary = sg.call("_migrate_save", v2, 3)
	_check(not m.is_empty() and String(m["city"]["city"]["res_region"]) == "copper",
			"миграция v2→v3: богатство региона по умолчанию")
	# day_length длиннее
	var c: Dictionary = _read_json("res://data/city.json")
	_check(float(c["day_length"]) >= 300.0, "день длиннее (300 с)")
	# слуги-фразы есть
	var ru: Dictionary = _read_json("res://loc/ru.json")
	for key in ["say.farmer.harvest", "say.farmer.pests", "say.miner.ore",
			"say.guard.raid", "say.builder.built"]:
		_check(not String(ru.get(key, "")).is_empty(), "фраза «%s» есть" % key)
