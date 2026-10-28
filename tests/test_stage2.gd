# Этап 2: аспекты 1-6 и перекрытый вход.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_stage2_aspect1() -> void:
	print("[Этап 2, аспект 1: схематичный режим]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	if not (city is Dictionary and loc is Dictionary):
		_check(false, "city.json и loc/ru.json читаются")
		return
	var cats: Dictionary = city.get("cats", {})
	_check(cats.size() >= 5, "палитра категорий есть в city.json (%d шт.)" % cats.size())
	var used := {}
	for b in city.get("buildings", []):
		var bid := String(b["id"])
		var cat := String(b.get("cat", ""))
		used[cat] = true
		_check(cat != "", "у здания «%s» задана категория" % bid)
		if cats.has(cat):
			var cval := String(cats[cat].get("color", ""))
			_check(cval.begins_with("#") and cval.length() >= 7, "категория «%s» имеет цвет" % cat)
		_check(String(b.get("short", "")) != "", "у здания «%s» задан ключ краткой подписи" % bid)
		var skey := String(b.get("short", ""))
		if skey != "":
			_check(String(loc.get(skey, "")) != "", "подпись «%s» есть в локализации" % skey)
		var lkey := String(b.get("loc", ""))
		_check(String(loc.get(lkey, "")) != "", "полное название «%s» есть в локализации" % lkey)
	for cat in used:
		_check(cats.has(cat), "категория «%s» из зданий определена в cats" % cat)
	_check(String(loc.get("bld.short.wall", "")) != "", "у стены есть ключ подписи (резерв)")
	# цвета категорий различимы: хотя бы 5 уникальных
	var uniq := {}
	for c in cats:
		uniq[String(cats[c]["color"])] = true
	_check(uniq.size() == cats.size(), "цвета категорий попарно различны")
	print("[Этап 2, аспект 1] готово")


## Этап 2, аспект 2 — здания 2×2, коллизия, «жизнь внутри», миграция сейвов.
func _test_stage2_aspect2() -> void:
	print("[Этап 2, аспект 2: здания 2×2]")
	var city: Variant = _read_json("res://data/city.json")
	_check(city is Dictionary, "city.json читается")
	if not (city is Dictionary):
		return
	# конфиг: размер w у каждого здания; инфраструктура — 1×1, остальное — 2×2;
	# палатка — дешёвая 1×1 по решению заказчика (этап 2, аспект 4)
	var infra := {"wall": true, "gate": true, "bridge": true, "tent": true}
	for b in city.get("buildings", []):
		var w := int(b.get("w", 0))
		var bid := String(b["id"])
		if infra.has(bid):
			_check(w == 1, "инфраструктура «%s» осталась 1×1" % bid)
		else:
			_check(w == 2, "здание «%s» — 2×2" % bid)
	var sim := _make_sim()
	# размещение: дом ставится прямоугольником; повторно — нельзя
	var t1: Vector2i = _find_free_tile(sim, sim.map.spawn_tile, "house")
	_check(sim.place_building("house", t1), "дом 2×2 ставится")
	var site: Dictionary = sim.building_at(t1)
	_check(not site.is_empty() and sim.bld_w(site) == 2, "построенный дом занимает 2×2")
	_check(not sim.is_buildable_rect("house", t1), "занятый прямоугольник дважды не застраивается")
	_check(sim.map.is_walkable(t1), "стройплощадка проходима")
	# готовое здание — сплошное во всех клетках, вход проходим
	# (v1.20: площадь у спавна — стройки дальше, строителю дать дойти)
	site["progress"] = 9999.0
	var builder_a2: Dictionary = _resident_by_prof(sim, "builder")
	_teleport(sim, builder_a2, site["tile"])
	sim.tick(0.2)
	_check(bool(site["done"]), "дом достроен")
	var solid_cnt := 0
	for c in sim.bld_cells(site):
		if not sim.map.is_walkable(c):
			solid_cnt += 1
	_check(solid_cnt == 4, "готовый дом непроходим во всех 4 клетках")
	var spot: Vector2i = sim.bld_entrance(site)
	_check(not spot == Vector2i(-1, -1) and sim.map.is_walkable(spot), "у дома есть проходимый вход")
	# стена — по-прежнему одна клетка
	var wall_t: Vector2i = _find_free_tile(sim, sim.map.spawn_tile, "wall")
	_check(sim.place_building("wall", wall_t), "стена ставится на 1 клетку")
	# «жизнь внутри»: спящий у входа житель помечен inside и не виден
	var r0: Dictionary = sim.residents[0]
	r0["home"] = site
	r0["pos"] = sim.map.tile_center_px(spot)
	r0["target"] = Vector2i(-1, -1)
	r0["path"] = PackedVector2Array()
	sim.time = float(sim.cfg["day_length"]) * 0.9
	sim._sleep(r0, 0.1)
	_check(int(r0.get("inside", 0)) == 1 and String(r0["state"]) == "sleep",
			"ночной житель «внутри» дома (не рисуется)")
	# миграция legacy-здания 1×1 → 2×2 (расширение или бесплатный перенос)
	var legacy: Dictionary = {"id": 9999, "type": "garden", "tile": t1 + Vector2i(4, 0),
			"done": true, "progress": 0.0, "worker": -1, "hp": 20.0, "pile": {}}
	sim.buildings.append(legacy)
	sim.migrate_legacy_buildings()
	_check(int(legacy["w"]) == 2, "мигрированному саду присвоен размер 2×2")
	var covered := 0
	for c in sim.bld_cells(legacy):
		if sim.bld_has_cell(legacy, c):
			covered += 1
	_check(covered == 4, "мигрированный сад занимает 4 клетки")
	_check(String(sim._def(legacy).get("effect", "")) == "decor", "мигрированный сад работает как декор")
	# этап 2, правка приёмки: вода/скалы/руда сплошные для A* — никто не срезает
	var m: Object = sim.map
	var solid_ok := true
	var walk_sample: Vector2i = Vector2i(-1, -1)
	for y in m.h:
		for x in m.w:
			var t := Vector2i(x, y)
			var nw: bool = m.is_nature_walkable(t)
			var water: bool = m.grid[t.y][t.x] == m.TILE_WATER
			# клетки под зданиями сплошные по правилу зданий (аспект 2) — не рельеф
			if sim.building_at(t).is_empty():
				# брод v1.29.1: вода не сплошная для жителей (вес > 1) и
				# сплошная для мутантов; скалы/руда/порода — сплошные для всех
				if m.astar.is_point_solid(t) != (not nw and not water):
					solid_ok = false
				if water and m.astar.get_point_weight_scale(t) <= 1.0:
					solid_ok = false
				if m.astar_raider.is_point_solid(t) != (not nw):
					solid_ok = false
			if nw and walk_sample == Vector2i(-1, -1):
				walk_sample = t
	_check(solid_ok, "A*: сплошность по рельефу (вода — брод для своих, скалы для всех)")
	var path_clean := true
	if not walk_sample == Vector2i(-1, -1):
		var goal: Vector2i = m.nearest_walkable(m.spawn_tile)
		for cell in m.path_px(m.tile_center_px(walk_sample), goal):
			var pt := Vector2i(int(cell.x / m.ts), int(cell.y / m.ts))
			# брод: путь может включать воду — нельзя только по сплошным тайлам
			if m.is_solid(pt):
				path_clean = false
				break
	_check(path_clean, "путь A* не содержит непроходимых клеток")
	# этап 2, правка приёмки: мясо/рыба кормят город (сдать лут — еда в пул)
	var sim_food := _make_sim()
	var food0: float = float(sim_food.res["food"])
	var food_inv: Array = [{"id": "meat", "count": 3}, {"id": "hide", "count": 1}]
	var added_food: Dictionary = sim_food.deposit_loot(food_inv)
	_check(int(added_food.get("food", 0)) == 3, "мясо из лута ушло в пул еды")
	_check(float(sim_food.res["food"]) == food0 + 3.0, "пул еды вырос от мяса")
	_check(food_inv.size() == 1 and String(food_inv[0]["id"]) == "hide",
			"шкура осталась в рюкзаке (не еда)")
	print("[Этап 2, аспект 2] готово")


## Этап 2, аспект 3 — поля-грядки DF-стиля: культура целиком на поле,
## быстрая/медленная культуры, смена культуры, герой собирает урожай.
func _test_stage2_aspect3() -> void:
	print("[Этап 2, аспект 3: поля-грядки]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	_check(city is Dictionary and loc is Dictionary, "конфиги читаются")
	if not (city is Dictionary and loc is Dictionary):
		return
	var crops: Dictionary = city.get("farming", {}).get("crops", {})
	_check(crops.size() == 3, "три культуры (репа, тыква, пшеница — v1.22)")
	_check(crops.has("turnip") and crops.has("pumpkin") and crops.has("wheat"), "культуры: turnip, pumpkin, wheat")
	var t_days := float(crops.get("turnip", {}).get("stage_days", 9.0))
	var p_days := float(crops.get("pumpkin", {}).get("stage_days", 0.0))
	var t_food := float(crops.get("turnip", {}).get("harvest", 0.0))
	var p_food := float(crops.get("pumpkin", {}).get("harvest", 0.0))
	_check(t_days < p_days, "репа зреет быстрее тыквы")
	_check(t_food < p_food, "тыква даёт больше еды")
	for cid in crops:
		_check(String(loc.get("crop." + String(cid), "")) != "", "культура «%s» названа в локализации" % cid)
	var sim := _make_sim()
	# поле создаётся с культурой и сеется ею целиком
	var cells: Array = []
	var base: Vector2i = sim.map.spawn_tile + Vector2i(3, 3)
	for dy in 2:
		for dx in 2:
			cells.append(base + Vector2i(dx, dy))
	sim.res["seeds"] = 50.0
	_check(sim.add_zone("field", cells, "pumpkin") == 4, "поле 2×2 засеяно тыквой")
	var z: Dictionary = sim.zones[0]
	_check(String(z.get("crop", "")) == "pumpkin", "культура поля — тыква")
	z["progress"] = [9.0, 9.0, 9.0, 9.0]   # клетки «обустроены» (fill_work = 4)
	# смена культуры очищает посевы и пересеивает
	_check(sim.set_field_crop(z, "turnip"), "культура поля меняется")
	_check(String(z["crop"]) == "turnip" and (z["crops"] as Array).is_empty(),
			"после смены поле пусто — пересеется репой")
	# герой собирает спелую грядку: еда в пул, семя назад, пересев той же культурой
	var spot: Vector2i = base
	var crops_arr: Array = z["crops"]
	while crops_arr.size() <= 4:
		crops_arr.append({})
	crops_arr[0] = {"stage": 9, "t": 0.0, "ripe": true}   # спелая репа
	sim.res["seeds"] = 5.0
	var food0: float = float(sim.res["food"])
	var seeds0: float = float(sim.res["seeds"])
	var near: Dictionary = sim.hero_harvest_near(sim.map.tile_center_px(spot))
	_check(not near.is_empty() and String(near["crop"]) == "turnip", "герой видит спелую грядку")
	_check(sim.hero_harvest(sim.map.tile_center_px(spot)) == "food", "E собирает урожай")
	var got: float = float(sim.crop_def("turnip")["harvest"]) * float(sim.crop_mult())
	_check(float(sim.res["food"]) >= food0 + got - 0.01, "еда за клетку в общем пуле")
	_check(float(sim.res["seeds"]) >= seeds0, "семя вернулось")
	var cell0: Dictionary = (z["crops"] as Array)[0]
	_check(not cell0.is_empty() and int(cell0["stage"]) == 0, "грядка пересеяна той же культурой")
	_check(sim.hero_harvest(sim.map.tile_center_px(spot)) == "", "несозревшая клетка не собирается")
	# ключи локализации пикера
	for key in ["city.crop_pick_hint", "city.crop_pick_change", "city.crop_changed",
			"city.hint_harvest", "city.hero_harvest_done"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	print("[Этап 2, аспект 3] готово")


## Правка приёмки v1.15.1: соседняя постройка 2×2 перекрыла вход здания —
## работник не должен простаивать вечно, вход пересчитывается.
## v1.21: ферма больше не производит у входа (она на грядках) — проверяем
## на плавильне: копит металл в общем пуле, стоя у входа (v1.25: кучи упразднены).
func _test_stage2_entrance_recalc() -> void:
	print("[Этап 2: перекрытый вход]")
	var sim_e := _make_sim()
	sim_e._last_daily_day = 999
	sim_e.cfg["food_per_resident_day"] = 0.0
	var smelter_e_res := _add_resident(sim_e, "Огнь", "smelter")
	smelter_e_res["traits"] = []
	smelter_e_res["mood"] = 100.0
	sim_e.res["iron"] = 50.0
	var smelt_e := _build_now(sim_e, "smelter", sim_e.map.spawn_tile + Vector2i(14, 8))
	smelt_e["worker"] = int(smelter_e_res["id"])
	smelter_e_res["bld"] = smelt_e
	var spot0: Vector2i = sim_e.bld_spot(smelt_e)
	_teleport(sim_e, smelter_e_res, spot0)
	for i in 4:
		sim_e.tick(2.0)
	var pile0: float = float(sim_e.res["metal"])
	_check(pile0 > 0.0, "плавильщик работает у входа плавильни")
	# ставим стену 1×1 поверх текущего входа: стена — сплошное кольцо, зазора
	# не держит и может перекрыть вход (правило зазоров — для обычных зданий)
	var placed := false
	for off in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var a: Vector2i = spot0 + off
		if sim_e.place_building("wall", a):
			placed = true
			break
	_check(placed, "вход плавильни перекрыт стеной")
	var spot1: Vector2i = sim_e.bld_spot(smelt_e)
	_check(spot1 != spot0 and sim_e.map.is_walkable(spot1),
			"вход пересчитан на свободную сторону")
	_teleport(sim_e, smelter_e_res, spot1)
	for i in 5:
		sim_e.tick(2.0)
	_check(float(sim_e.res["metal"]) > pile0, "плавильщик вернулся к работе через новый вход")
	print("[Этап 2: перекрытый вход] готово")


## Этап 2, аспект 4 — торговые палатки: постройка 1×1 с лимитом, торговец,
## доход монетами от излишков пула, живая сцена, бродячие торговцы.
func _test_stage2_aspect4() -> void:
	print("[Этап 2, аспект 4: торговые палатки]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	_check(city is Dictionary and loc is Dictionary, "конфиги читаются")
	if not (city is Dictionary and loc is Dictionary):
		return
	var tdef: Dictionary = {}
	for d in city.get("buildings", []):
		if String(d["id"]) == "tent":
			tdef = d
	_check(not tdef.is_empty(), "палатка есть в списке зданий")
	_check(int(tdef.get("w", 2)) == 1, "палатка — постройка 1×1")
	_check(int(tdef.get("max_count", 0)) == 3, "лимит палаток — 3")
	_check(String(tdef.get("worker", "")) == "trader", "палатке нужен торговец")
	_check(int((tdef.get("cost", {}) as Dictionary).get("wood", 99)) <= 8,
			"палатка дешёвая (дерево ≤ 8)")
	for key in ["bld.tent", "bld.desc.tent", "bld.short.tent", "city.tent_limit",
			"city.tent_income_toast", "city.wanderer_toast", "shop.1", "wshop.1"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	_check(not (city.get("tent", {}) as Dictionary).is_empty(), "баланс палаток в city.json")
	var sim := _make_sim()
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	# --- торговец и приоритет рынка ---
	# рынок строим ПЕРВЫМ, пока жители свободны (стройплощадки палаток ниже
	# разберут всех, и рынок останется без строителя); если профессионального
	# строителя нет — назначаем свободного, чтобы не зависеть от подмены
	var builder_r: Dictionary = _resident_by_prof(sim, "builder")
	if builder_r.is_empty() or builder_r["bld"] != null or builder_r["site"] != null:
		for r in sim.residents:
			if r["bld"] == null and r["site"] == null and String(r["prof"]) != "" \
					and String(r["prof"]) != "elder" and String(r.get("ail", "")) == "":
				r["prof"] = "builder"
				break
	var market := _build_now(sim, "market")
	# --- лимит и стройка ---
	var placed := 0
	for i in 4:
		var tile := _find_free_tile(sim, sim.map.spawn_tile + Vector2i(i * 3, 5), "tent")
		if tile == Vector2i(-1, -1):
			break
		if sim.place_building("tent", tile):
			placed += 1
	_check(placed == 3, "три палатки ставятся, четвёртая — нет (поставилось %d)" % placed)
	_check(sim.placement_block("tent", _find_free_tile(sim, sim.map.spawn_tile, "tent"))
			== "city.tent_limit", "placement_block объясняет лимит палаток")
	var free1: Dictionary = {}
	for r in sim.residents:
		if r["bld"] == null and r["site"] == null and String(r["prof"]) != "" \
				and String(r["prof"]) != "elder" and String(r.get("ail", "")) == "":
			free1 = r
			break
	_check(not free1.is_empty(), "есть свободный житель под торговца")
	free1["prof"] = "trader"
	var tents: Array = []
	for b in sim.buildings:
		if String(b["type"]) == "tent":
			b["done"] = true   # достроим мгновенно: проверяем назначение, не стройку
			tents.append(b)
	for r in sim.residents:
		if r != free1 and String(r["prof"]) != "":
			r["prof_saved"] = String(r["prof"])
			r["prof"] = ""   # дети не подменяют (механика подмены M4)
	# чистый слэш: места, разобранные ещё на стройплощадках, сбрасываем —
	# проверяем именно раздачу готовых палаток с одним торговцем
	for b in sim.buildings:
		b["worker"] = -1
	for r in sim.residents:
		r["bld"] = null
		r["site"] = null
		r["sub_prof"] = ""
	sim._assign_jobs()
	var market_worker := int(market["worker"])
	_check(market_worker > 0, "торговый двор (M10) забирает торговца первым")
	var idle_tents := 0
	for b in tents:
		if int(b["worker"]) <= 0:
			idle_tents += 1
	_check(idle_tents == 3, "без второго торговца палатки стоят (%d пустых)" % idle_tents)
	for r in sim.residents:   # возвращаем профессии (подмена больше не помешает)
		if String(r.get("prof_saved", "")) != "":
			r["prof"] = String(r["prof_saved"])
			r.erase("prof_saved")
	# --- доход от излишков ---
	# палатка №1 работает (торговец вручную): проверяем именно экономику
	tents[0]["worker"] = int(free1["id"])
	free1["bld"] = tents[0]
	for key in sim.res:
		sim.res[key] = 0.0
	sim.res["food"] = 0.0
	_check(sim._tent_income(tents[0]) == 0, "пустой пул — палатка стоит (доход 0)")
	sim.res["wood"] = 300.0
	sim.res["stone"] = 200.0
	sim.res["food"] = 60.0
	var inc: int = sim._tent_income(tents[0])
	_check(inc > 0, "излишки пула приносят монеты (%d)" % inc)
	var maxc := int(city.get("tent", {}).get("max_coins_per_day", 8))
	_check(inc <= maxc, "доход палатки ограничен потолком (%d ≤ %d)" % [inc, maxc])
	sim.res["food"] = 60.0
	sim.events.clear()
	sim._tick_tents()
	var got_event := false
	for ev in sim.events:
		if String(ev["type"]) == "tent_income" and int(ev["coins"]) > 0:
			got_event = true
	_check(got_event, "дневной тик даёт событие дохода палаток")
	# --- бродячий торговец ---
	var spot: Vector2i = sim.bld_spot(tents[0])
	sim._last_wanderer_day = -99
	sim.wanderers = []
	sim._roll_wanderer()
	_check(sim.wanderers.size() == 1, "к работающей палатке заходит бродячий торговец")
	var w: Dictionary = sim.wanderers[0]
	w["pos"] = sim.map.tile_center_px(spot)
	w["target"] = Vector2i(-1, -1)
	sim.events.clear()
	sim._update_wanderers(0.05)
	_check(String(w["mode"]) == "trade", "бродячий пришёл и торгует")
	_check(sim._wanderer_at(tents[0]), "бродячий стоит именно у палатки")
	var ev_arrived := false
	for ev in sim.events:
		if String(ev["type"]) == "wanderer_arrived":
			ev_arrived = true
	_check(ev_arrived, "приход бродячего — событие для тоста")
	var inc2: int = sim._tent_income(tents[0])
	_check(inc2 > inc, "бродячий скупает оптом: доход палатки вырос (%d > %d)" % [inc2, inc])
	w["left"] = 0.01
	sim._update_wanderers(0.05)
	_check(String(w["mode"]) == "leave", "отторговал — уходит")
	w["pos"] = sim.map.tile_center_px(Vector2i(w["edge"]))
	w["target"] = Vector2i(-1, -1)
	sim._update_wanderers(0.05)
	_check(sim.wanderers.is_empty(), "дошёл до края — ушёл из города")
	# --- живая сцена: покупатель ---
	free1["bld"] = null
	var shopper: Dictionary = {}
	for r in sim.residents:
		if r["bld"] == null and r["site"] == null and String(r["prof"]) != "" \
				and String(r["prof"]) != "trader" and String(r.get("ail", "")) == "":
			shopper = r
			break
	_check(not shopper.is_empty(), "есть житель-покупатель")
	shopper["shop_cd_left"] = 0.0
	var started := false
	for i in 400:   # шанс визита за тик мал — гоняем до срабатывания
		if sim._tent_visit(shopper, 2.0):
			started = true
			if not (shopper.get("shop", {}) as Dictionary).is_empty():
				break
	_check(started and not (shopper.get("shop", {}) as Dictionary).is_empty(),
			"свободный житель собирается к палатке")
	var shop_tent: Dictionary = sim._building_by_id(int((shopper.get("shop", {}) as Dictionary).get("bld", -1)))
	_teleport(sim, shopper, sim.bld_spot(shop_tent))
	sim._tent_visit(shopper, 2.0)
	_check(String(shopper["state"]) == "chat" and String(shopper.get("chat_key", "")).begins_with("shop."),
			"у палатки житель «покупает» с репликой-облачком")
	shopper["chat_left"] = 0.001
	sim._tent_visit(shopper, 2.0)
	_check((shopper.get("shop", {}) as Dictionary).is_empty() and float(shopper.get("shop_cd_left", 0.0)) > 0.0,
			"после покупки — кулдаун, визит закрыт")
	print("[Этап 2, аспект 4] готово")


## Этап 2, аспект 5 — ремонт за 40% стоимости и бесплатный перенос зданий:
## руины вместо исчезновения, E-ремонт героя, инструмент переноса.
func _test_stage2_aspect5() -> void:
	print("[Этап 2, аспект 5: ремонт за 40% и перенос зданий]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	_check(city is Dictionary and loc is Dictionary, "конфиги читаются")
	if not (city is Dictionary and loc is Dictionary):
		return
	var frac: float = float((city.get("repair", {}) as Dictionary).get("cost_frac", 0.4))
	_check(is_equal_approx(frac, 0.4), "ремонт — 40% стоимости (конфиг)")
	for key in ["city.repair_hint", "city.repaired_toast", "city.restored_toast",
			"city.repair_no_res", "city.move", "city.move_pick", "city.move_place",
			"city.moved_toast", "city.move_bad_spot", "city.move_bad_bld",
			"city.razed_tag", "city.hover_razed", "city.hover_damaged",
			"chron.repaired", "chron.moved"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	var sim := _make_sim()
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	var house := _build_now(sim, "house")
	var house_cost: Dictionary = {}
	var house_hp: float = float(sim._bld_max_hp("house"))
	for d in city.get("buildings", []):
		if String(d["id"]) == "house":
			house_cost = d.get("cost", {})
	# --- цена ремонта: 40% стоимости, каждый ресурс вверх ---
	var rc: Dictionary = sim.repair_cost("house")
	var cost_ok := not rc.is_empty()
	for key in house_cost:
		if int(rc.get(key, -1)) != maxi(1, int(ceil(float(house_cost[key]) * 0.4))):
			cost_ok = false
	_check(cost_ok, "цена ремонта = ceil(40% стоимости) по каждому ресурсу")
	# --- повреждённое здание: E-ремонт восстанавливает за 40% ---
	sim._damage_building(house, house_hp * 0.6)
	_check(not bool(house.get("razed", false)) and float(house["hp"]) > 0.0,
			"повреждённое здание стоит (hp > 0)")
	var wood_before: int = int(sim.res["wood"])
	_check(sim.repair_building(house) == "", "ремонт повреждённого проходит")
	_check(is_equal_approx(float(house["hp"]), house_hp), "после ремонта hp = максимум")
	_check(int(sim.res["wood"]) == wood_before - int(rc.get("wood", 0)),
			"ресурсы за ремонт списаны (по цене 40%)")
	_check(sim.repair_building(house) == "full", "целое здание чинить не нужно")
	# --- руины: разрушение не удаляет здание (ответ №17 «ремонт, не снос») ---
	var razed_ev := false
	sim.events.clear()
	_check(sim._damage_building(house, house_hp * 10.0), "добивание возвращает «разрушено»")
	for ev in sim.events:
		if String(ev["type"]) == "razed":
			razed_ev = true
	_check(razed_ev, "разрушение — событие razed для тоста")
	_check(sim.buildings.has(house) and bool(house.get("razed", false)), "здание осталось руинами")
	_check(int(house["worker"]) == -1, "работник руин освобождён")
	var cell_in: Vector2i = sim.bld_cells(house)[0]
	_check(sim.map.is_walkable(cell_in), "клетки руин проходимы (обломки)")
	_check(not sim._active(house), "руины — не действующее здание")
	var probe: Dictionary = {"pos": sim.map.tile_center_px(Vector2i(house["tile"]))}
	var target: Dictionary = sim._nearest_building_of(probe, [])
	_check(target.is_empty() or not bool(target.get("razed", false)),
			"мутанты руины не бьют (цель — только целые)")
	# --- дом руин не считается жильём ---
	var pop_razed: int = sim.pop_cap()
	_check(sim.repair_building(house) == "", "руины восстанавливаются за те же 40%")
	_check(not bool(house.get("razed", false)) and is_equal_approx(float(house["hp"]), house_hp),
			"после восстановления руин здание целое")
	_check(not sim.map.is_walkable(cell_in), "клетки восстановленного здания снова сплошные")
	_check(sim.pop_cap() > pop_razed, "восстановленный дом снова даёт места")
	# --- стена: разрушена = проход, отремонтирована = преграда ---
	var wall_tile := _find_free_tile(sim, sim.map.spawn_tile + Vector2i(0, 4), "wall")
	_check(not wall_tile == Vector2i(-1, -1), "место под стену нашлось")
	var wall: Dictionary = {}
	if not wall_tile == Vector2i(-1, -1):
		sim.res["stone"] = 50.0
		if sim.place_building("wall", wall_tile):
			wall = sim.building_at(wall_tile)
			wall["done"] = true
			sim._complete_site(wall)
	if not wall.is_empty():
		var wall_hp := float(sim._bld_max_hp("wall"))
		_check(sim._damage_building(wall, wall_hp * 10.0), "стена разрушена")
		_check(sim.map.is_walkable(wall_tile), "пролом в стене проходим")
		_check(sim.repair_building(wall) == "", "стена отремонтирована")
		_check(not sim.map.is_walkable(wall_tile), "отремонтированная стена снова преграда")
	# --- перенос: бесплатно, правила места те же ---
	# кузню достраиваем мгновенно (как стену выше): строитель после мутаций
	# теста мог быть занят — проверяем перенос, а не стройку
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	var forge: Dictionary = {}
	var forge_tile := _find_free_tile(sim, sim.map.spawn_tile + Vector2i(-6, 6), "forge")
	_check(not forge_tile == Vector2i(-1, -1), "forge: место под переносимую постройку")
	if not forge_tile == Vector2i(-1, -1) and sim.place_building("forge", forge_tile):
		forge = sim.building_at(forge_tile)
		forge["done"] = true
		sim._complete_site(forge)
	_check(not forge.is_empty() and bool(forge.get("done", false)), "forge готова (достройка мгновенно)")
	var res_before := {}
	for key in sim.res:
		res_before[key] = sim.res[key]
	var new_tile := _find_free_tile(sim, sim.map.spawn_tile + Vector2i(8, 8), "forge")
	_check(not new_tile == Vector2i(-1, -1), "новое место под перенос нашлось")
	if not forge.is_empty() and not new_tile == Vector2i(-1, -1):
		var old_tile: Vector2i = Vector2i(forge["tile"])
		_check(sim.move_spot_ok(forge, new_tile), "годное место проходит проверку")
		_check(sim.move_building(forge, new_tile) == "", "перенос проходит")
		_check(Vector2i(forge["tile"]) == new_tile, "здание стоит на новом месте")
		_check(sim.building_at(old_tile).is_empty(), "старое место свободно")
		_check(not sim.map.is_walkable(new_tile), "новые клетки сплошные")
		_check(sim.map.is_walkable(old_tile), "старые клетки проходимы")
		var same_res := true
		for key in res_before:
			if float(sim.res[key]) != float(res_before[key]):
				same_res = false
		_check(same_res, "перенос бесплатный (ресурсы не тронуты)")
		# на занятое место — отказ, здание остаётся где стояло
		var occupied := Vector2i(house["tile"])
		_check(not sim.move_spot_ok(forge, occupied), "на место другого здания нельзя")
		_check(sim.move_building(forge, occupied) == "bad_spot", "перенос на занятое отклонён")
		_check(Vector2i(forge["tile"]) == new_tile, "здание осталось на месте после отказа")
	# --- перенос руины и стройплощадки запрещён ---
	sim._damage_building(house, house_hp * 10.0)
	_check(sim.move_building(house, new_tile) == "bad_bld", "руину переносить нельзя — сперва ремонт")
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	var site_tile := _find_free_tile(sim, sim.map.spawn_tile + Vector2i(-4, -6), "house")
	if not site_tile == Vector2i(-1, -1):
		_check(sim.place_building("house", site_tile), "стройплощадка заложена")
		var site: Dictionary = sim.building_at(site_tile)
		_check(sim.move_building(site, site_tile + Vector2i(4, 4)) == "bad_bld",
				"стройплощадку переносить нельзя")
	print("[Этап 2, аспект 5] готово")


## Правки приёмки v1.20 (второй чат правок): зоны-слои (промышленная/
## магическая/складская/отдыха), жилая зона и кварталы УБРАНЫ по решению
## заказчика («убери зоны, жилые и тд») — остались только Поле и Пастбище.
## Взамен: главная площадь 2×2, голем-староста и утренняя планёрка (отдельный
## блок тестов ниже). Здесь — обратная совместимость: конфиг чист, старые
## типы зон отвергаются, сейвы с лишними зонами вычищаются при загрузке.
func _test_stage2_aspect6() -> void:
	print("[Правки v1.20: зоны убраны (жилая и слои)]")
	var city: Variant = _read_json("res://data/city.json")
	var loc: Variant = _read_json("res://loc/ru.json")
	_check(city is Dictionary and loc is Dictionary, "конфиги читаются")
	if not (city is Dictionary and loc is Dictionary):
		return
	var zcfg: Dictionary = city.get("zones", {})
	var ztypes: Dictionary = zcfg.get("types", {})
	_check(ztypes.has("field") and ztypes.has("pasture"), "остались только Поле и Пастбище")
	for zid in ["living", "industrial", "magic", "storage", "leisure"]:
		_check(not ztypes.has(zid), "тип зоны убран из конфига: " + zid)
	_check(not zcfg.has("quarters"), "кварталы убраны из конфига")
	_check(not city.has("pop_per_house") or int(city["pop_per_house"]) == 1,
			"один дом — один человек (pop_per_house = 1)")
	for key in ["city.plaza_move", "city.plaza_pick", "city.plaza_moved",
			"city.plaza_bad_spot", "city.golem_toast", "city.morning_plan_toast",
			"city.zone_field_added", "chron.plaza_moved", "chron.golem_awakens",
			"chron.morning_plan", "chron.wedding_home"]:
		_check(String(loc.get(key, "")) != "", "ключ локализации есть: " + key)
	# больше нет кнопок «Ещё зоны» и подсказок слоёв
	for key in ["city.zones_more", "city.zones_more_tooltip", "city.zone_overlay_hint",
			"city.zone_overlay_bad"]:
		_check(String(loc.get(key, "")) == "", "ключ слоёв убран: " + key)

	# стройка у площади запрещена, дальше — можно; перенос площади работает
	var sim := _make_sim()
	sim.res["wood"] = 500.0
	sim.res["stone"] = 500.0
	_check(sim.plaza != Vector2i(-1, -1), "площадь 2×2 появилась у спавна")
	_check(sim.plaza_cells().size() == 4, "площадь занимает 4 клетки")
	_check(sim.near_plaza(sim.plaza), "клетки площади сами в запретном радиусе")
	_check(not sim.is_buildable_tile(sim.plaza), "на клетках площади строить нельзя")
	var near_t: Vector2i = sim.plaza + Vector2i(2, 1)
	_check(sim.near_plaza(near_t), "радиус 3: близко к площади строить нельзя")
	var far_t: Vector2i = sim.plaza + Vector2i(5, 0)
	while not (sim.map.in_bounds(far_t) and sim.map.grid[far_t.y][far_t.x] == sim.map.TILE_GRASS):
		far_t += Vector2i(1, 0)
	_check(not sim.near_plaza(far_t), "далее 3 клеток от площади строить можно")
	var plaza_far: Vector2i = sim.map.spawn_tile + Vector2i(12, 8)
	while not sim._plaza_ok(plaza_far) or not sim.building_at(plaza_far).is_empty():
		plaza_far += Vector2i(1, 0)
	_check(sim.move_plaza(plaza_far) == "", "площадь переносится")
	_check(sim.plaza == plaza_far, "площадь на новом месте")
	sim.move_plaza(sim.map.spawn_tile + Vector2i(-1, -1))   # вернули как было

	# сейв со старыми зонами: лишние типы вычищаются, Поле остаётся
	var SG: Script = load("res://scripts/save_game.gd")
	SG.clear_save()
	var g1 := _make_game()
	var s1: Object = g1.city_sim
	var fcells: Array = []
	var fb: Vector2i = s1.map.spawn_tile + Vector2i(8, 8)
	for dy in 2:
		for dx in 2:
			if s1.map.grid[fb.y + dy][fb.x + dx] == s1.map.TILE_GRASS:
				fcells.append(fb + Vector2i(dx, dy))
	_check(s1.add_zone("field", fcells) == fcells.size(), "поле перед сейвом разбито")
	# подсовываем «наследие»: старая жилая зона руками в список зон
	s1.zones.append({"id": 999, "type": "living", "cells": [s1.map.spawn_tile + Vector2i(9, 9)],
			"progress": [0.0]})
	var p_before: Vector2i = s1.plaza
	_check(SG.save_game(g1, s1.map.spawn_tile, 7, 3) == "", "сейв с площадью записан")
	var g2 := FakeGame.new()
	g2.skills = load("res://scripts/skills.gd").new()
	g2.skills.setup(_read_json("res://data/skills.json"))
	_check(SG.load_game(g2) == "", "сейв читается")
	var g2s = g2.city_sim
	var field_kept := false
	var living_gone := true
	for z in g2s.zones:
		if String(z["type"]) == "field":
			field_kept = true
		if String(z["type"]) == "living":
			living_gone = false
	_check(field_kept, "поле пережило сейв-цикл")
	_check(living_gone, "старая жилая зона вычищена при загрузке")
	_check(g2s.plaza == p_before, "площадь пережила сейв-цикл")
	_check(not g2s.day_plans.is_empty(), "утренний план построен после загрузки")
	SG.clear_save()
	print("[Правки v1.20: зоны убраны] готово")




## Правки приёмки v1.19.1 (2026-10-21): жители приходят (соло-старт строит и
## живёт), волны из аномалии раз в 10 дней и ослаблены, зачистка данжа у города
## сдвигает атаки на 20 дней и светлеет данж, герой сам пашет/сеет/собирает поля,
## зоны Поле/Пастбище цветные и подписываются при наведении.
