# v1.60 «Караваны и союзы»: торговля с городами НПС, союзные походы на
# гнездовья, бонусы серебра/янтаря, письма из серии «region».
extends "res://tests/test_base.gd"

var _coins_box := {"n": 0}


func _make_nc() -> Object:
	var nc: Object = load("res://scripts/npc_cities.gd").new()
	var wmap: Object = load("res://scripts/world_map.gd").new()
	wmap.generate(11, _read_json("res://data/world.json"))
	nc.setup(wmap, _read_json("res://data/world.json"), _read_json("res://data/city.json"))
	return nc


func _make_ally_city(nc: Object, poi_id: int, rel: int) -> Dictionary:
	nc.cities[poi_id] = {"poi_id": poi_id, "faction": "traders", "seed": 1,
			"coins": 50, "sim": null, "pop": 10, "rel": rel,
			"standing": 5.0, "name": "Тестовый Торг"}
	return nc.cities[poi_id]


func _test_v160_caravan_in() -> void:
	print("[v1.60: входящий караван — ресурс фракции за монеты]")
	var nc: Object = _make_nc()
	var sim := _make_sim()
	_coins_box["n"] = 100
	sim.coins_source = func() -> int: return int(_coins_box["n"])
	sim.coins_sink = func(n: int) -> void: _coins_box["n"] += int(n)
	var city: Dictionary = _make_ally_city(nc, 7, 60)
	var evs: Array = nc.trade_day(sim, 0.05)   # < in_chance — караван
	_check(evs.size() == 1 and String(evs[0]["type"]) == "caravan_in",
			"караван пришёл по дружбе")
	if evs.is_empty():
		return
	var rid := String(evs[0]["res"])
	_check(rid == "silver", "город торговцев привозит СВОЙ ресурс (серебро)")
	_check(float(sim.res.get(rid, 0.0)) >= 2.0, "ресурс в пуле города (+%d)" % int(evs[0]["n"]))
	_check(int(_coins_box["n"]) == 100 - int(evs[0]["pay"]), "заплатили %d монет" % int(evs[0]["pay"]))
	_check(int(city["rel"]) == 62, "торговля укрепляет отношения (+2)")
	# враждебный город не торгует
	city["rel"] = -20
	var evs2: Array = nc.trade_day(sim, 0.05)
	_check(evs2.is_empty(), "при rel <= 40 караванов нет")


func _test_v160_caravan_out() -> void:
	print("[v1.60: исходящий караван — скупка богатства региона]")
	var nc: Object = _make_nc()
	var sim := _make_sim()
	_coins_box["n"] = 0
	sim.coins_source = func() -> int: return int(_coins_box["n"])
	sim.coins_sink = func(n: int) -> void: _coins_box["n"] += int(n)
	_make_ally_city(nc, 7, 50)
	var region := String(sim.map.region_resource)
	sim.res[region] = 10.0
	var before: float = float(sim.res[region])
	var evs: Array = nc.trade_day(sim, 0.25)   # между in и out шансами
	_check(evs.size() == 1 and String(evs[0]["type"]) == "caravan_out",
			"караван скупил богатство региона")
	if evs.is_empty():
		return
	_check(String(evs[0]["res"]) == region, "скупают именно региональный ресурс")
	_check(float(sim.res[region]) == before - 4.0, "вывезено 4 единицы")
	_check(int(_coins_box["n"]) >= 10, "город заплатил монетами")


func _test_v160_ally_raid() -> void:
	print("[v1.60: союзный поход на гнездовье]")
	var nc: Object = _make_nc()
	var sim := _make_sim()
	_coins_box["n"] = 0
	sim.coins_sink = func(n: int) -> void: _coins_box["n"] += int(n)
	var wmap: Object = nc.world_map
	# город-союзник — существующее поселение; рядом — лагерь с гнездовьем
	var city_poi: Dictionary = {}
	var camp: Dictionary = {}
	for poi in wmap.pois:
		if city_poi.is_empty() and String(poi["kind"]) == "settlement":
			city_poi = poi
		elif camp.is_empty() and String(poi["kind"]) == "camp":
			camp = poi
	_check(not city_poi.is_empty() and not camp.is_empty(), "на карте есть город и лагерь")
	camp["tile"] = Vector2i(city_poi["tile"]) + Vector2i(3, 0)   # рядом с союзником
	camp["nest_level"] = 2
	var city: Dictionary = _make_ally_city(nc, int(city_poi["poi_id"]), 75)
	var evs: Array = nc.trade_day(sim, 0.40)   # окно союзного похода
	_check(evs.size() == 1 and String(evs[0]["type"]) == "ally_raid",
			"союзник сам выбивает гнездовье")
	if evs.is_empty():
		return
	_check(int(camp["nest_level"]) == 1, "гнездовье ослаблено (2 -> 1)")
	_check(int(_coins_box["n"]) >= 8, "союзники поделились добычей")
	# слабый союз (rel 50) не ходит в поход
	city["rel"] = 50
	camp["nest_level"] = 2
	_check(nc.trade_day(sim, 0.40).is_empty(), "при rel < 70 союзных походов нет")


func _test_v160_trade_bonuses() -> void:
	print("[v1.60: серебро и янтарь дают бонусы городу]")
	var sim := _make_sim()
	sim.res["silver"] = 12.0
	sim.res["amber"] = 9.0
	sim.res["gold"] = 0.0
	sim.res["alcohol"] = 0.0
	_coins_box["n"] = 0
	sim.coins_sink = func(n: int) -> void: _coins_box["n"] += int(n)
	var before := {}
	for r in sim.residents:
		before[int(r["id"])] = float(r["mood"])
	sim._apply_resource_bonuses()
	_check(int(_coins_box["n"]) == 2, "серебро >= 10: +2 монеты в день")
	var grew: bool = not sim.residents.is_empty()
	for r in sim.residents:
		if sim._is_golem(r):
			continue   # голем-староста вне бонусов настроения
		var d: float = float(r["mood"]) - float(before[int(r["id"])])
		if d < 1.0 - 0.01:
			print("    DEBUG житель %s: настроение +%.2f" % [String(r["name"]), d])
			grew = false
	_check(grew, "янтарь >= 8: настроение городу (+1 каждому)")


func _test_v160_letters_region() -> void:
	print("[v1.60: письма караванов — в серии «регион»]")
	var nf: Script = load("res://scripts/notice_feed.gd")
	var kinds: Dictionary = nf.LETTER_KINDS
	for k in ["caravan_in", "caravan_out", "ally_raid"]:
		_check(String(kinds.get(k, "")) == "region", "%s -> группа region" % k)
