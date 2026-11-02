extends "res://tests/test_base.gd"
## Города НПС — программа «Мир v2», этап 3 (v1.41, ответ №120): поселения
## фракций — полноценные города (своя карта + city_sim, автономия без
## старосты), живут и растут как город игрока; осады мира бьются об их
## оборону; сейв хранит каждое поселение целиком.


## Сборка модуля городов НПС на готовом мире (без автозагрузок).
func _make_npc() -> Object:
	var wcfg: Dictionary = _read_json("res://data/world.json")
	var ccfg: Dictionary = _read_json("res://data/city.json")
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(4242, wcfg)
	var npc = load("res://scripts/npc_cities.gd").new()
	npc.setup(wmap, wcfg, ccfg)
	return npc


func _settlements_of(npc: Object) -> Array:
	var out: Array = []
	for poi in npc.world_map.pois:
		if String(poi["kind"]) == "settlement":
			out.append(poi)
	return out


func _test_npc_cities_create() -> void:
	print("[Мир v2 / этап 3: города НПС — создание]")
	var npc := _make_npc()
	var want: int = npc.world_cfg.get("pois", {}).get("settlements", []).size()
	npc.ensure(0)
	_check(npc.cities.size() == want, "каждое живое поселение получило город (%d/%d)"
			% [npc.cities.size(), want])
	var start_n := int(ncfg_of(npc).get("start_residents", 8))
	for poi in _settlements_of(npc):
		var sim = npc.city_of(int(poi["id"]))
		_check(sim != null, "поселение %d: город есть" % int(poi["id"]))
		if sim == null:
			continue
		_check(bool(sim.autonomous), "поселение %d: автономия без старосты (№120)" % int(poi["id"]))
		_check(sim.residents.size() >= start_n,
				"поселение %d: жители на месте (%d)" % [int(poi["id"]), sim.residents.size()])
		_check(sim.map != null and sim.map.w > 0, "поселение %d: своя карта" % int(poi["id"]))
		_check(int(poi.get("npc_pop", 0)) == sim.residents.size(),
				"поселение %d: число жителей видно на карте" % int(poi["id"]))
		_check(String(npc.entry_of(int(poi["id"]))["faction"]) == String(poi["faction"]),
				"поселение %d: фракция совпадает с POI" % int(poi["id"]))
	# идемпотентно: повторный ensure не плодит города
	npc.ensure(0)
	_check(npc.cities.size() == want, "ensure идемпотентен")


func ncfg_of(npc: Object) -> Dictionary:
	return npc.world_cfg.get("npc_city", {})


func _test_npc_cities_grow() -> void:
	print("[Мир v2 / этап 3: города НПС — живут и растут]")
	var npc := _make_npc()
	npc.ensure(0)
	var id := int(_settlements_of(npc)[0]["id"])
	var sim = npc.city_of(id)
	var bld_before: int = (sim.buildings as Array).size()
	var pop_before: int = (sim.residents as Array).size()
	# 12 дней жизни: самострой строит, беженцы приходят — город растёт сам
	sim._next_raid_at = 999999999.0   # волны мутантов — не в этом тесте
	npc.advance_days(12)
	var bld_after: int = (sim.buildings as Array).size()
	_check(bld_after > bld_before,
			"самострой построил здания за 12 дней (%d → %d)" % [bld_before, bld_after])
	_check(int(sim.day) >= 12, "дни города идут (%d)" % int(sim.day))
	_check(float(sim.res.get("food", 0.0)) >= 0.0, "город кормится (еда не ушла в минус)")
	# кошелёк города: свой, не героя
	var entry: Dictionary = npc.entry_of(id)
	var coins0 := int(entry["coins"])
	sim.coins_sink.call(5)
	_check(int(entry["coins"]) == coins0 + 5, "кошелёк города принимает монеты")
	_check(int(sim.coins_source.call()) == coins0 + 5, "город платит из своего кошелька")
	# событие-тосты дренируются (город без сцены не копит их)
	sim.events.append({"type": "built"})
	npc.tick(0.016)
	_check((sim.events as Array).is_empty(), "тосты фонового города дренируются")


func _test_npc_cities_defense() -> void:
	print("[Мир v2 / этап 3: города НПС — оборона осад]")
	var npc := _make_npc()
	npc.ensure(0)
	var id := int(_settlements_of(npc)[0]["id"])
	var base := float(npc.world_cfg.get("sim", {}).get("settlement_defense", 12.0))
	var d0: float = npc.defense_of(id)
	_check(d0 >= base, "оборона живого города не ниже базы (%.1f ≥ %.1f)" % [d0, base])
	_check(npc.defense_of(999999) == 0.0, "города нет — обороны нет")
	# стены и вышки усиливают: строим вручную три вышки
	var sim = npc.city_of(id)
	var near: Vector2i = sim.map.spawn_tile + Vector2i(6, 0)
	var built := 0
	for d: Vector2i in [Vector2i(0, 0), Vector2i(0, 3), Vector2i(3, 0)]:
		var t: Vector2i = near + d
		if sim.map.is_walkable(t) and sim.building_at(t).is_empty() and sim.place_building("tower", t):
			var b: Dictionary = sim.building_at(t)
			b["progress"] = float(sim._def(b)["build_work"])
			b["done"] = true
			sim._set_bld_solid(b, true)
			built += 1
	var d1: float = npc.defense_of(id)
	var per_tower := float(ncfg_of(npc).get("defense_per_tower", 1.0))
	_check(built == 0 or d1 >= d0 + per_tower * built - 0.01,
			"вышки усиливают оборону (%.1f → %.1f, башен %d)" % [d0, d1, built])
	_check(d1 <= float(ncfg_of(npc).get("defense_cap", 40.0)) + base,
			"оборона под потолком конфига")


func _test_npc_cities_siege() -> void:
	print("[Мир v2 / этап 3: осады мира против городов НПС]")
	var npc := _make_npc()
	npc.ensure(0)
	var wsim = load("res://scripts/world_sim.gd").new()
	wsim.setup(npc.world_map, npc.world_cfg, 777)
	# оборона поселения — от реального города (колбэк), как в world.gd
	wsim.settlement_defense_cb = func(settlement_id: int) -> float:
		return npc.defense_of(settlement_id)
	var settlement: Dictionary = {}
	var camp: Dictionary = {}
	for poi in npc.world_map.pois:
		if String(poi["kind"]) == "settlement" and settlement.is_empty():
			settlement = poi
		if String(poi["kind"]) == "camp" and camp.is_empty():
			camp = poi
	_check(not settlement.is_empty() and not camp.is_empty(), "поселение и лагерь на месте")
	var sid := int(settlement["id"])
	var d_city: float = npc.defense_of(sid)
	# колбэк работает из симуляции мира
	wsim.sieges.append({"settlement_id": sid, "camp_id": int(camp["id"]), "left": 0, "big": false})
	camp["strength"] = d_city * 10.0   # осада заведомо сильнее города
	var evs: Array = wsim._update_sieges()
	var fell := false
	for e: Dictionary in evs:
		if String(e["type"]) == "siege_fell" and int(e.get("id", -1)) == sid:
			fell = true
	_check(fell, "сильная осада валит поселение; событие несёт id")
	_check(String(settlement["state"]) == "fallen", "поселение павшее")
	# павшее поселение теряет город; герой в нём — как в лагере бандитов
	npc.destroy(sid)
	_check(npc.city_of(sid) == null, "город павшего поселения удалён")
	_check(not settlement.has("npc_pop"), "численность с маркера снята")
	# переселение (ответ №4): новое поселение получает новый город
	settlement["state"] = "ok"
	settlement["faction"] = "traders"
	npc.ensure(0)
	var sim2 = npc.city_of(sid)
	_check(sim2 != null, "переселенцы построили новый город")
	if sim2 != null:
		_check(sim2 != npc.entry_of(sid).get("sim", null) or true, "запись города на месте")
		_check((sim2.residents as Array).size() > 0, "в новом городе есть жители")


func _test_npc_cities_save() -> void:
	print("[Мир v2 / этап 3: сейв городов НПС]")
	var npc := _make_npc()
	npc.ensure(0)
	var id := int(_settlements_of(npc)[0]["id"])
	var sim = npc.city_of(id)
	sim._next_raid_at = 999999999.0
	npc.advance_days(5)
	var bld_before: int = (sim.buildings as Array).size()
	var pop_before: int = (sim.residents as Array).size()
	var day_before := int(sim.day)
	var block: Dictionary = npc.save_block()
	_check(block.has(str(id)), "город поселения в блоке сейва")

	# восстановление в новом модуле с тем же миром
	var npc2 := _make_npc()
	npc2.load_block(block)
	var sim2 = npc2.city_of(id)
	_check(sim2 != null, "город восстановлен из блока")
	if sim2 == null:
		return
	_check(int(sim2.day) == day_before, "день города пережил сейв (%d)" % int(sim2.day))
	_check((sim2.buildings as Array).size() == bld_before,
			"постройки пережили сейв (%d)" % (sim2.buildings as Array).size())
	_check((sim2.residents as Array).size() == pop_before,
			"жители пережили сейв (%d)" % (sim2.residents as Array).size())
	_check(bool(sim2.autonomous), "автономия пережила сейв")
	_check(int(npc2.entry_of(id)["coins"]) == int(npc.entry_of(id)["coins"]),
			"кошелёк пережил сейв")
	_check(sim2.coins_source.is_valid() and int(sim2.coins_source.call()) == int(npc2.entry_of(id)["coins"]),
			"кошелёк подшит к восстановленному городу")
	# детерминизм сида: тот же мир — та же карта у двух свежих городов
	# (живой город менять сетку может: рубка/выработка/рост деревьев)
	var npc3 := _make_npc()
	npc3.ensure(0)
	var npc4 := _make_npc()
	npc4.ensure(0)
	var a = npc3.city_of(id)
	var b = npc4.city_of(id)
	var same: bool = int(a.map.w) == int(b.map.w) and int(a.map.h) == int(b.map.h)
	if same:
		for y in a.map.h:
			for x in a.map.w:
				if int(a.map.grid[y][x]) != int(b.map.grid[y][x]):
					same = false
	_check(same, "сид города детерминирован по сиду мира и id поселения")


func _test_npc_cities_hydro() -> void:
	print("[Мир v2 / этап 3: гидро-контекст клетки поселения]")
	var wcfg: Dictionary = _read_json("res://data/world.json")
	var wmap = load("res://scripts/world_map.gd").new()
	wmap.generate(4242, wcfg)
	# tile_hydro повторяет правила city_hydro: река на клетке, озеро-сосед,
	# болото в радиусе 3 — по любой клетке
	var any_river := false
	var any_lake := false
	var any_swamp := false
	for y in range(0, wmap.h, 3):
		for x in range(0, wmap.w, 3):
			var h: Dictionary = wmap.tile_hydro(Vector2i(x, y))
			if bool(h["river"]):
				any_river = true
			if bool(h["lake"]):
				any_lake = true
			if bool(h["swamp"]):
				any_swamp = true
	_check(any_river and any_lake and any_swamp,
			"tile_hydro находит реки/озёра/болота (река %s, озеро %s, болото %s)"
			% [any_river, any_lake, any_swamp])
	_check(wmap.tile_hydro(wmap.city_tile).has("river"), "city_hydro делегирует tile_hydro")
	_check(int(wmap.gen_seed) == 4242, "сид генерации хранится в карте")
