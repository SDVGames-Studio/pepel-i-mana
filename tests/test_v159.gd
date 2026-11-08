# v1.59 «Город тянет сам»: маркер стартового города на карте мира,
# жизненно важные здания отбирают работников, ремонт без строителя,
# лесопилку не ставят у полей, переселенцы идут в малый город.
extends "res://tests/test_base.gd"


func _test_v159_sawmill_not_near_fields() -> void:
	print("[v1.59: лесопилку не ставят у полей]")
	var sim := _make_sim()
	# ферма — вокруг неё распахивается поле (farming.field_radius)
	var farm_t: Vector2i = Vector2i(-1, -1)
	for r in [10, 14, 18]:
		farm_t = sim._ring_buildable(sim.map.spawn_tile, r, "farm")
		if farm_t != Vector2i(-1, -1) and sim.place_building("farm", farm_t):
			break
		farm_t = Vector2i(-1, -1)
	_check(farm_t != Vector2i(-1, -1), "место под ферму найдено")
	if farm_t == Vector2i(-1, -1):
		return
	var farm0: Dictionary = sim.building_at(farm_t)
	if not farm0.is_empty():
		farm0["done"] = true
		sim._make_farm_field(farm0)   # достройка фермы распахивает поле
	var zones_n := 0
	for z in sim.zones:
		if String(z["type"]) == "field":
			zones_n += 1
	_check(zones_n > 0, "поле распахано вокруг фермы")
	# тайл рядом с полем: лесопилку БЛОКИРУЮТ
	var near_t := Vector2i(-1, -1)
	var far_t := Vector2i(-1, -1)
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var t: Vector2i = farm_t + Vector2i(dx, dy)
			if not sim.map.in_bounds(t) or not sim.is_buildable_tile(t, "sawmill"):
				continue
			if sim._farm_zone_near(t, 2):
				if near_t == Vector2i(-1, -1):
					near_t = t
			elif far_t == Vector2i(-1, -1):
				far_t = t
	_check(near_t != Vector2i(-1, -1), "есть место рядом с полем")
	_check(sim.placement_block("sawmill", near_t) == "city.placement_sawmill_farm",
			"лесопилка у поля запрещена")
	_check(not sim.place_building("sawmill", near_t), "построить у поля нельзя")
	if far_t != Vector2i(-1, -1):
		_check(sim.placement_block("sawmill", far_t) == "",
				"вдали от полей — можно")


func _test_v159_vital_steal() -> void:
	print("[v1.59: жизненно важное здание отбирает работника]")
	var sim := _make_sim()
	# ферма готова, работника нет; торговец сидит на рынке (не жизненно важное)
	var farm_t: Vector2i = sim._ring_buildable(sim.map.spawn_tile, 5, "farm")
	_check(farm_t != Vector2i(-1, -1) and sim.place_building("farm", farm_t),
			"ферма построена")
	var farm: Dictionary = sim.building_at(farm_t)
	if farm.is_empty():
		return
	farm["done"] = true
	farm["worker"] = -1
	var mkt_t: Vector2i = sim._ring_buildable(sim.map.spawn_tile, 9, "tent")
	if mkt_t == Vector2i(-1, -1):
		mkt_t = sim._ring_buildable(sim.map.spawn_tile, 12, "tent")
	_check(mkt_t != Vector2i(-1, -1), "место под торговый ряд найдено")
	var trader: Dictionary = sim._new_resident("ПробаТест", "trader", sim.map.spawn_tile)
	sim.residents.append(trader)
	if mkt_t != Vector2i(-1, -1):
		_check(sim.place_building("tent", mkt_t), "торговый ряд построен")
		var mkt: Dictionary = sim.building_at(mkt_t)
		if not mkt.is_empty():
			mkt["done"] = true
			mkt["worker"] = int(trader["id"])
			trader["bld"] = mkt
			trader["prof_extra"] = ["trader"]
	sim._assign_jobs()
	_check(int(farm.get("worker", -1)) > 0, "ферма получила работника (отобрали у рынка)")
	var staffed: Dictionary = sim._resident_by_id(int(farm.get("worker", -1)))
	_check(not staffed.is_empty() and staffed["bld"] == farm,
			"работник переведён на ферму (подмена с обучением)")


func _test_v159_repair_without_builder() -> void:
	print("[v1.59: руины чинит любой здоровый житель]")
	var sim := _make_sim()
	# готовое здание-руина; жителей трое, строителя НЕТ
	var spot: Vector2i = sim._ring_buildable(sim.map.spawn_tile, 3, "well")
	if spot == Vector2i(-1, -1):
		spot = sim._ring_buildable(sim.map.spawn_tile, 6, "well")
	_check(spot != Vector2i(-1, -1), "место под колодец найдено")
	_check(sim.place_building("well", spot), "колодец построен")
	var well: Dictionary = sim.building_at(spot)
	if well.is_empty():
		return
	well["done"] = true
	well["hp"] = 0.0
	well["razed"] = true
	# один жилец-рыбак при деле (bld занят), второй свободен
	var fisher: Dictionary = sim._new_resident("РыбаТест", "fisher", sim.map.spawn_tile)
	sim.residents.append(fisher)
	sim.residents[0]["bld"] = null
	sim.residents[0]["site"] = null
	sim._roll_city_repair()
	_check(not sim.brigade_job.is_empty(), "бригада собралась без строителя")
	_check(int(fisher.get("repair_bld", 0)) == int(well["id"]) \
			or int(sim.residents[0].get("repair_bld", 0)) == int(well["id"]),
			"назначен здоровый не-строитель")
	# работа целым днём: эмулируем приход бригады на место и работу
	var worker: Dictionary = fisher if int(fisher.get("repair_bld", 0)) > 0 \
			else sim.residents[0]
	var spot_t: Vector2i = sim.bld_spot(well)
	worker["pos"] = Vector2(float(spot_t.x) + 0.5, float(spot_t.y) + 0.5) * float(sim.map.ts)
	var need := float(sim.brigade_job["need"])
	sim._repair_errand(worker, need)
	_check(float(well["hp"]) >= float(sim._bld_max_hp("well")) or not bool(well.get("razed", false)),
			"руина поднята за бригадный день")


func _test_v159_refugees_to_tiny_city() -> void:
	print("[v1.59: переселенцы идут в малый город несмотря на горе]")
	var sim := _make_sim()
	while sim.residents.size() > 2:
		sim.residents.remove_at(sim.residents.size() - 1)
	for r in sim.residents:
		r["mood"] = 10.0   # горе: обычный гейт (45) закрыл бы приток навсегда
	var rolled := 0
	for i in range(40):
		var before: int = sim.residents.size()
		sim._event_rng.seed = 1000 + i
		sim._roll_refugees()
		if sim.residents.size() > before:
			rolled += 1
	_check(rolled > 0, "переселенцы приходят в город из 1-2 жителей при низком настроении")


func _test_v159_world_home_marker() -> void:
	print("[v1.59: стартовый город отмечен на карте мира]")
	var g: Object = _make_game()
	if g.world_map == null:
		g.world_map.generate(11, _read_json("res://data/world.json"))
	var city_pois := 0
	for poi in g.world_map.pois:
		if String(poi.get("kind", "")) == "city":
			city_pois += 1
			_check(poi["tile"] == g.world_map.city_tile,
					"точка «city» стоит на клетке стартового города")
	_check(city_pois == 1, "стартовый город на карте — единственная точка «city»")
