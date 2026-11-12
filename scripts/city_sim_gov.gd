# Часть: староста/голем, мысли и лог жителей, ворота/стены/план города,
# дневные броски (болезни/беженцы), рождения и пары, летопись.
# Структура v1.62.0: планёрка и поиск мест автостройки переехали в
# city_sim_gov_plan.gd, истории — в city_sim_stories.gd. Поведение не меняется.
extends "res://scripts/city_sim_gov_plan.gd"

# --- староста/мэр ----------------------------------------------------------

## Староста на ногах (не болеет) — город может строить сам.
func elder_present() -> bool:
	for r in residents:
		if String(r["prof"]) == "elder" and String(r.get("ail", "")) == "":
			return true
	return false


## Автономная деревня (правки v1.12.0): объявляется с порога жителей
## (city.json -> autonomy.pop). Пока порог не взят — false.
func can_autonomy() -> bool:
	return not autonomous and residents.size() >= int(cfg.get("autonomy", {}).get("pop", 10))


func autonomy_pop() -> int:
	return int(cfg.get("autonomy", {}).get("pop", 10))


## Объявить деревню автономной: она строит без старосты, строит сверх плана
## (комфорт и торговля), притягивает поселенцев и гордится собой. "" — успех,
## иначе ключ локализации с причиной отказа.
func go_autonomous() -> String:
	if autonomous:
		return "city.autonomy_done"
	if residents.size() < autonomy_pop():
		return "city.autonomy_need"
	autonomous = true
	_chron("chron.autonomy", str(residents.size()))
	events.append({"type": "autonomy"})
	return ""


## Староста не сидит: обходит здания и следит за порядком.
func _manage_walk(r: Dictionary, dt: float) -> void:
	if r["target"] == Vector2i(-1, -1) or _arrived(r, r["target"]):
		var t := _manage_target(r)
		if not t == Vector2i(-1, -1):
			r["target"] = t
	_move_towards(r, r["target"], dt)
	r["state"] = "manage"


func _manage_target(r: Dictionary) -> Vector2i:
	for attempt in 20:
		if buildings.is_empty():
			break
		var b: Dictionary = buildings[_event_rng.randi_range(0, buildings.size() - 1)]
		var tile: Vector2i = (b["tile"] as Vector2i) + Vector2i(_event_rng.randi_range(-2, 2), _event_rng.randi_range(-2, 2))
		if map.is_walkable(tile):
			return tile
	var near: Vector2i = map.spawn_tile + Vector2i(_event_rng.randi_range(-4, 4), _event_rng.randi_range(-4, 4))
	return near if map.is_walkable(near) else map.spawn_tile


## Ежедневный самострой (просьба заказчика): город строится СРАЗУ по плану —
## весь нужный набор строений, без ожидания кризисов. Кризисы (голод, теснота)
## идут вне очереди. Когда план выполнен и все здания достроены — обустройство
## защиты: крепостное кольцо стен с воротами. Игрок строит что хочет поверх.
func _roll_autobuild() -> void:
	# автономная деревня справляется и без старосты (правки v1.12.0)
	if not elder_present() and not autonomous:
		return
	# кризис: еды меньше чем на день — ферма вне очереди (кучи у ферм тоже еда — M6)
	var critical_food: float = float(residents.size()) * float(cfg["food_per_resident_day"])
	if float(res["food"]) + _piled_total_of("food") < critical_food \
			and not _autobuild_site_exists("farm") and not _idle_farm_exists():
		var tile := _find_autobuild_tile("farm")
		if not tile == Vector2i(-1, -1) and place_building("farm", tile):
			_announce_autobuild("farm", true)
			return
	# еда идёт в минус: производство меньше расхода — нужна ещё ферма, пока не выправится (заказчик)
	if _food_deficit() and not _autobuild_site_exists("farm") and not _idle_farm_exists():
		var tile_d := _find_autobuild_tile("farm")
		if not tile_d == Vector2i(-1, -1) and place_building("farm", tile_d):
			_announce_autobuild("farm", true)
			return
	# кризис: мест нет совсем — дом вне очереди
	if residents.size() >= pop_cap() and not _autobuild_site_exists("house"):
		var tile_h := _find_autobuild_tile("house")
		if not tile_h == Vector2i(-1, -1) and place_building("house", tile_h):
			_announce_autobuild("house", true)
			return
	# план города: сразу строим всё нужное по порядку — город растёт
	# интенсивно (v1.21.2: до трёх зданий в день)
	var built := 0
	for i in 3:
		var need := _next_plan_need()
		if need == "":
			break
		var tile_p := _find_autobuild_tile(need)
		if tile_p == Vector2i(-1, -1):
			break
		if not place_building(need, tile_p):
			continue   # не по карману — попробуем следующее нужное
		_announce_autobuild(need, true)
		built += 1
	if built > 0:
		return
	# обустройство защиты: кольцо стен — только когда ВСЕ здания достроены,
	# еды хватает и есть запас дерева на важные постройки
	if _any_unfinished_building() or not _food_reserve_ok():
		return
	if float(res["wood"]) < 12:
		return
	# кольцо ещё не замкнуто — три звена в день (v1.21.2: интенсивнее)
	if not _next_wall_tile() == Vector2i(-1, -1):
		var walls := 0
		for i in 3:
			var wtile := _next_wall_tile()
			if wtile == Vector2i(-1, -1):
				break
			if not place_building("wall", wtile):
				break
			walls += 1
		if walls > 0:
			_announce_autobuild("wall", false)
		return
	# кольцо готово: строим ворота в проёмах (заказчик)
	for off in _gate_offsets():
		var gt: Vector2i = map.spawn_tile + (off as Vector2i)
		if building_at(gt).is_empty():
			if not is_buildable_tile(gt):
				continue   # на воде/камне ворот не будет — природная преграда
			if place_building("gate", gt):
				_announce_autobuild("gate", true)
			return
	# у каждых ворот — вышка: страж на ней открывает ворота
	for off in _gate_offsets():
		var gt2: Vector2i = map.spawn_tile + (off as Vector2i)
		var gate_b: Dictionary = building_at(gt2)
		if gate_b.is_empty() or not _active(gate_b):
			continue   # проём без ворот или ворота ещё строятся
		if not _manned_tower_near(gt2):
			var tt := _tower_tile_near(gt2)
			if tt == Vector2i(-1, -1):
				continue
			if place_building("tower", tt):
				_announce_autobuild("tower", true)
			return


## Записать текущую мысль жителя в журнал отладки (вызывает тултип
## наведения на кружок — правки v1.20: «чтобы это ещё сохранялось в логах»).
func log_thought(r: Dictionary) -> void:
	var text := resident_thought(r)
	if String(r.get("_last_thought", "")) == text:
		return   # мысль не менялась — не спамим журнал
	r["_last_thought"] = text
	_log_line("День %d, %s: %s" % [day, String(r["name"]), text])


## Мысль жителя для тултипа: кто, куда идёт, чем занят (правки v1.20).
func resident_thought(r: Dictionary) -> String:
	var st := String(r["state"])
	var target: Vector2i = r.get("target", Vector2i(-1, -1))
	var dest := ""
	if target != Vector2i(-1, -1):
		dest = " → (%d, %d)" % [target.x, target.y]
	match st:
		"going":
			var job := _thought_job(r)
			return ("Идёт: %s%s" % [job, dest]) if job != "" else ("Идёт по делам%s" % dest)
		"work":
			return "Работает: %s%s" % [_thought_job(r), dest]
		"build":
			return "Строит%s" % dest
		"fill":
			return "Обустраивает зону%s" % dest
		"harvest":
			return "Собирает урожай%s" % dest
		"sleep":
			return "Спит дома"
		"rest":
			return "Отдыхает"
		"eat", "hungry":
			return "Голодает: ищет еду%s" % dest
		"guard":
			return "На страже%s" % dest
		"hide":
			return "Прячется дома"
		"leisure":
			return "Отдыхает вечером%s" % dest
		"chat":
			return "Болтает"
		"porter":
			return "Носит груз%s" % dest
		"manage":
			return "Обходит владения%s" % dest
		"meeting":
			return "На утренней планёрке у площади"
		"hunt":
			return "Охотится%s" % dest
		"tame":
			return "Присматривает скот%s" % dest
		"patrol":
			return "Патрулирует%s" % dest
		"dead":
			return "Погиб"
	var job := _thought_job(r)
	return ("Занят: %s" % job) if job != "" else "Свободен"


func _thought_job(r: Dictionary) -> String:
	if r["site"] != null:
		return "стройка «%s»" % String(r["site"]["type"])
	if r["bld"] != null:
		var need := String(_def(r["bld"]).get("worker", ""))
		var via := ""
		if need != String(r["prof"]):
			if (r.get("prof_extra", []) as Array).has(need):
				via = " (доп. цвет, ×%.2f)" % color_work_mult(r, need)
			else:
				via = " (не по цвету, ×%.2f)" % color_work_mult(r, need)
		return "«%s»%s" % [String(r["bld"]["type"]), via]
	if String(r["prof"]) == "porter":
		return "носит кучи на склад"
	if String(r["prof"]) == "hunter":
		return "охота"
	return ""


## Раз в день: житель, который застрял (не сдвинулся и не менял занятие),
## получает пинок — путь сброшен, работа перевыдана (анти-фриз 50-го дня).
func _watchdog_stuck() -> void:
	if _stuck_checked_day == day:
		return
	_stuck_checked_day = day
	var calm := ["sleep", "rest", "idle", "guard", "hide", "chat", "leisure", "meeting", "dead",
			"chop", "saw", "prep", "fill", "harvest", "work", "manage"]
	var nudged := 0
	for r in residents:
		var last_pos: Vector2 = r.get("_watch_pos", Vector2(-9999, -9999))
		var last_state := String(r.get("_watch_state", ""))
		if not last_pos.is_equal_approx(Vector2(-9999, -9999)) and last_state != "" \
				and last_state == String(r["state"]) \
				and (last_pos.distance_to(r["pos"]) < float(map.ts)) \
				and not calm.has(last_state) \
				and String(r["prof"]) != "":
			# застрял: сброс пути, шаг в сторону, перевыдача работы
			r["path"] = PackedVector2Array()
			r["target"] = Vector2i(-1, -1)
			var here: Vector2i = map.tile_of_px(r["pos"])
			if not map.is_walkable(here):
				r["pos"] = map.tile_center_px(_nearest_walkable(here))
			r["state"] = "idle"
			_log_line("День %d: %s застрял в «%s» — пнул планом" % [day, String(r["name"]), last_state])
			nudged += 1
		r["_watch_pos"] = r["pos"]
		r["_watch_state"] = r["state"]
	if nudged > 0:
		_assign_jobs()
		events.append({"type": "stuck_nudged", "n": nudged})


## Четыре проёма кольца: север, юг, запад, восток.
func _gate_offsets() -> Array:
	return [Vector2i(0, -WALL_RING), Vector2i(0, WALL_RING), Vector2i(-WALL_RING, 0), Vector2i(WALL_RING, 0)]


func _manned_tower_near(tile: Vector2i) -> bool:
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "guard" and int(b["worker"]) > 0:
			if Vector2(b["tile"]).distance_to(Vector2(tile)) <= 3.0:
				return true
	return false


## Тайл под вышку у ворот — внутри кольца, ближе к центру города.
func _tower_tile_near(gate_tile: Vector2i) -> Vector2i:
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := gate_tile + Vector2i(dx, dy)
				if is_buildable_tile(tile) \
						and Vector2(tile).distance_to(Vector2(map.spawn_tile)) < Vector2(gate_tile).distance_to(Vector2(map.spawn_tile)):
					return tile
	return Vector2i(-1, -1)


## Первое строение из плана города, которого ещё нет в нужном количестве.
## Автономная деревня строит и сверх плана — комфорт и торговлю (autonomy.plan).
func _next_plan_need() -> String:
	var plan: Array = cfg.get("autobuild_plan", [])
	if autonomous:
		plan = plan + (cfg.get("autonomy", {}).get("plan", []) as Array)
	var counts := {}
	for b in buildings:
		counts[String(b["type"])] = int(counts.get(String(b["type"]), 0)) + 1
	for type_id in plan:
		var t := String(type_id)
		if int(counts.get(t, 0)) < _plan_count(plan, t):
			return t
	return ""


func _plan_count(plan: Array, type_id: String) -> int:
	var n := 0
	for t in plan:
		if String(t) == type_id:
			n += 1
	return n


## Есть ли хоть одно недостроенное здание — стены начинаются в полностью
## застроенном городе, а не вперемешку с домами и фермами.
func _any_unfinished_building() -> bool:
	for b in buildings:
		if not bool(b["done"]):
			return true
	return false




## Следующий тайл кольца стен (обход по часовой). Ворота — 4 середины сторон.
func _next_wall_tile() -> Vector2i:
	var c: Vector2i = map.spawn_tile
	var ring := 2 * WALL_RING
	for i in range(0, 4 * ring):
		var side := i / ring
		var step := i % ring
		var off: Vector2i
		match side:
			0: off = Vector2i(-WALL_RING + step, -WALL_RING)
			1: off = Vector2i(WALL_RING, -WALL_RING + step)
			2: off = Vector2i(WALL_RING - step, WALL_RING)
			3: off = Vector2i(-WALL_RING, WALL_RING - step)
		if off.x == 0 or off.y == 0:
			continue   # ворота на север, юг, запад и восток
		var tile := c + off
		if is_buildable_tile(tile):
			return tile
	return Vector2i(-1, -1)




## Легендарный странник поселился в городе (v1.22): сильный профильный
## житель с высоким навыком — герой позвал его на карте мира.
func add_legend_resident(res_name: String, prof: String, skill: float) -> Dictionary:
	var r := _new_resident(res_name, prof, map.spawn_tile)
	r["skill"] = skill
	r["mood"] = 80.0
	r["traits"] = []
	residents.append(r)
	_next_id += 1
	_chron("chron.legend_joined_city", res_name, prof)
	events.append({"type": "legend_joined", "name": res_name, "prof": prof})
	_assign_jobs()
	return r


## Еда идёт в минус: ожидаемый урожай полей меньше дневного расхода города.
## Правки v1.21: ферма больше не даёт пассивную еду — считаем по грядкам
## действующих ферм. Вспаханные клетки — по устойчивой скорости урожая,
## невспаханные — ограниченным потенциалом (фермер ведь пашет), иначе город
## бесконечно строил бы фермы, пока поле не вспахано.
## v1.22: на пороге зимы прикидка умножается на зимний коэффициент — город
## ДО зимы видит голодную арифметику и достраивает фермы заранее.
func _food_deficit() -> bool:
	var fcfg: Dictionary = cfg.get("farming", {})
	var est: float = float(fcfg.get("est_per_farm", 16.0))
	var production := 0.0
	var farms := {}
	for b in buildings:
		if _active(b) and String(b["type"]) == "farm":
			farms[int(b["id"])] = true
	for z in zones:
		if String(z["type"]) != "field" or not farms.has(int(z.get("farm", -1))):
			continue
		var cdef: Dictionary = crop_def(String(z.get("crop", "turnip")))
		var cycle: float = maxf(0.1, float(cdef.get("stage_days", 0.8))) * maxf(1, int(fcfg.get("stages", 4)))
		var rate: float = float(cdef.get("harvest", 4.0)) / cycle
		var filled := 0
		var total := 0
		for i in (z["cells"] as Array).size():
			total += 1
			if _cell_filled(z, i) and building_at(z["cells"][i]).is_empty():
				filled += 1
		production += rate * float(filled) + minf(est, rate * float(total - filled))
	if winter_coming():
		production *= float(_weather_cfg().get("effects", {}).get("snow_field_mult", 0.3))
	return production < float(residents.size()) * float(cfg["food_per_resident_day"])


## Готовая ферма без работника: строить новую бессмысленно — сперва некому работать.
func _idle_farm_exists() -> bool:
	for b in buildings:
		if _active(b) and String(b["type"]) == "farm" and int(b["worker"]) <= 0:
			return true
	return false



## Староста погиб — деревня не остаётся без управления: у площади просыпается
## новый голем-староста (правки v1.20: староста — голем, а не повышенный житель).
func _ensure_elder() -> void:
	for r in residents:
		if String(r["prof"]) == "elder":
			return
	_spawn_golem()
	_assign_jobs()


## Дневной бросок: болезни и выздоровления (лекарь лечит, запущенная болезнь убивает).
func _roll_ailments() -> void:
	if OS.get_environment("AIL_OFF") != "":
		return   # биопсия: глушим тело для бисекции фриза
	var acfg: Dictionary = people.get("ailments", {})
	for r in residents.duplicate():
		if String(r["prof"]) == "" or _is_golem(r):
			continue   # дети и голем не болеют
		var ail := String(r.get("ail", ""))
		if ail == "":
			var chance: float = float(acfg.get("sick_chance", 0.02)) \
					+ float(acfg.get("pollution_sick_extra", 0.1)) * pollution / 100.0
			# черта «болезненный» (M7): хвори цепляются вдвое чаще
			if _has_trait_flag(r, "frail"):
				chance *= float(acfg.get("frail_mult", 2.0))
			if _event_rng.randf() < chance:
				_make_ail(r, "sick", "chron.sick")
			continue
		r["ail_days"] = float(r.get("ail_days", 0.0)) + 1.0
		var recov: float = float(acfg.get("recover_chance", 0.25))
		if _healer_ready():
			recov = float(acfg.get("healer_recover_chance", 0.7))
		elif residents.size() <= 2:
			# v1.59: малому городу нельзя вымирать от одной хвори — без
			# лекаря и без преемников болезнь означала конец поселения
			recov = maxf(recov, float(acfg.get("tiny_recover_chance", 0.5)))
		if _event_rng.randf() < recov:
			r["ail"] = ""
			_assign_jobs()   # выздоровел — вернулся в раздачу работы
			continue
		var risk: float = float(acfg.get("death_chance", 0.04))
		var overdue: float = float(r["ail_days"]) - float(acfg.get("death_risk_after_days", 3.0))
		if overdue > 0.0:
			risk += float(acfg.get("death_risk_growth", 0.05)) * overdue
		if _event_rng.randf() < risk:
			_kill(r, "chron.died_sick")


## Дневной бросок: беженцы идут сами (ответ №27) — шанс выше при вышках со стражей.
## Малый город растёт быстрее (early_bonus, правки v1.12.0: старт с одного жителя),
## автономная деревня притягивает людей (autonomy -> refugee_mult).
func _refugee_chance() -> float:
	var rcfg: Dictionary = people.get("refugees", {})
	var chance: float = float(rcfg.get("chance_per_day", 0.35)) \
			+ minf(float(rcfg.get("tower_bonus", 0.1)) * _manned_towers(), float(rcfg.get("tower_bonus_max", 0.4)))
	if residents.size() < int(rcfg.get("early_below", 8)):
		chance += float(rcfg.get("early_bonus", 0.0))
	if autonomous:
		chance *= float(cfg.get("autonomy", {}).get("refugee_mult", 1.0))
	if has_law("refuge_shelter"):
		chance *= float(law_param("refuge_shelter", "refugee_mult", 1.0))   # приют (M14-H)
	return chance


func _roll_refugees() -> void:
	var rcfg: Dictionary = people.get("refugees", {})
	if rcfg.is_empty() or residents.size() >= pop_cap():
		return
	if not _food_reserve_ok():
		return
	# v1.59: в городе из 1-2 человек настроение не блокирует переселенцев —
	# иначе смерть одного жителя (горе -20) навсегда закрывала приток людей
	# и город вымирал за считанные недели (приёмка v1.59: 3 жителя к 60 дню)
	if residents.size() > 2 and _avg_mood() < float(rcfg.get("mood_gate", 45.0)):
		return
	if _event_rng.randf() >= _refugee_chance():
		return
	var wave := _event_rng.randi_range(1, maxi(1, int(rcfg.get("wave_max", 2))))
	for i in wave:
		if residents.size() >= pop_cap():
			break
		var profs: Array = cfg["start"]["professions"]
		var prof := String(profs[_event_rng.randi_range(0, profs.size() - 1)])
		var names: Array = cfg["names"]
		var r := _new_resident(String(names[_event_rng.randi_range(0, names.size() - 1)]), prof, _edge_tile())
		residents.append(r)
		_next_id += 1
		_chron("chron.refugee", String(r["name"]), prof)
		events.append({"type": "refugee", "name": String(r["name"]), "prof": prof})
	_assign_jobs()


func _edge_tile() -> Vector2i:
	for attempt in 100:
		var side := _event_rng.randi_range(0, 3)
		var tile := Vector2i.ZERO
		match side:
			0: tile = Vector2i(_event_rng.randi_range(0, map.w - 1), 0)
			1: tile = Vector2i(_event_rng.randi_range(0, map.w - 1), map.h - 1)
			2: tile = Vector2i(0, _event_rng.randi_range(0, map.h - 1))
			3: tile = Vector2i(map.w - 1, _event_rng.randi_range(0, map.h - 1))
		if map.is_walkable(tile) and building_at(tile).is_empty():
			return tile
	return map.spawn_tile


## Дневной бросок: рождение ребёнка у случайного взрослого, когда всем хорошо.
## Пары повышают шанс рождения (couple_boost, M13).
func _roll_births() -> void:
	var bcfg: Dictionary = people.get("births", {})
	if bcfg.is_empty() or residents.size() >= pop_cap():
		return
	if not _food_reserve_ok() or _avg_mood() < float(bcfg.get("mood_gate", 60.0)):
		return
	var chance := float(bcfg.get("chance_per_day", 0.25))
	if _couples_count() > 0:
		chance *= float(bcfg.get("couple_boost", 1.5))
	if _event_rng.randf() >= chance:
		return
	var adults := _adults()
	if adults.is_empty():
		return
	var parent: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	var names: Array = cfg["names"]
	var child := _new_resident(String(names[_event_rng.randi_range(0, names.size() - 1)]), "", map.tile_of_px(parent["pos"]))
	child["race"] = String(parent.get("race", "human"))   # v1.64: дети наследуют расу
	child["age_days"] = 0.0
	child["traits"] = []
	child["mood"] = float(people.get("mood_base", 50.0))
	# ребёнок знает родителей и живёт их домом (жильё v1.20)
	var prnts: Array = [int(parent["id"])]
	var pp := _resident_by_id(int(parent.get("partner", -1)))
	if not pp.is_empty() and String(pp["prof"]) != "":
		prnts.append(int(pp["id"]))
	child["parents"] = prnts
	if not _homeless(parent):
		child["home"] = parent["home"]
	residents.append(child)
	_next_id += 1
	_chron("chron.birth", String(child["name"]))
	events.append({"type": "birth", "name": String(child["name"])})


## Число пар (M13): свадьбы друзей, поддержка и дети.
func _couples_count() -> int:
	var n := 0
	for r in residents:
		if int(r.get("partner", -1)) >= 0:
			n += 1
	return n / 2


## Пары (M13): друзья с хорошим настроением со временем женятся;
## живые пары каждый день поддерживают друг друга настроением.
func _roll_couples() -> void:
	var ccfg: Dictionary = people.get("couples", {})
	if ccfg.is_empty():
		return
	var gate := float(ccfg.get("mood_gate", 62.0))
	for r in residents:
		if int(r.get("partner", -1)) >= 0 or String(r["prof"]) == "":
			continue
		var other := _friend_of(r)
		if other.is_empty() or int(other.get("partner", -1)) >= 0:
			continue
		if float(r["mood"]) < gate or float(other["mood"]) < gate:
			continue
		if _event_rng.randf() >= float(ccfg.get("chance_per_day", 0.25)):
			continue
		r["partner"] = int(other["id"])
		other["partner"] = int(r["id"])
		_wedding_unify_home(r, other)   # пара живёт одним домом (правки v1.20)
		var boost := float(people.get("wedding_mood", 12.0))
		r["mood"] = clampf(float(r["mood"]) + boost, 0.0, 100.0)
		other["mood"] = clampf(float(other["mood"]) + boost, 0.0, 100.0)
		_rel_change(r, other, float(_v3().get("wedding_rel_bonus", 40.0)))   # v3
		_mem_push(r, "wedding")
		_mem_push(other, "wedding")
		_chron("chron.wedding", String(r["name"]), String(other["name"]))
		events.append({"type": "wedding", "a": String(r["name"]), "b": String(other["name"])})
	var pm := float(ccfg.get("pair_mood", 4.0))
	for r in residents:
		var pid := int(r.get("partner", -1))
		if pid < 0:
			continue
		if not _resident_by_id(pid).is_empty():
			r["mood"] = clampf(float(r["mood"]) + pm, 0.0, 100.0)


## Свадьба: один из пары «выписывается» из своего дома — пара с детьми
## занимает ОДИН дом, второй дом освобождается деревне (правки v1.20).
func _wedding_unify_home(a: Dictionary, b: Dictionary) -> void:
	var ha: Dictionary = a["home"] if a["home"] != null else {}
	var hb: Dictionary = b["home"] if b["home"] != null else {}
	var keep: Dictionary = ha if (not ha.is_empty() and _home_family_ok(a, ha)) else hb
	if keep.is_empty():
		keep = hb if not hb.is_empty() else {}
	if keep.is_empty():
		return   # дома нет ни у кого — заселятся ночью вместе
	var freed := ""
	if not ha.is_empty() and int(ha.get("id", -1)) != int(keep.get("id", -2)) \
			and _home_family_ok(a, ha):
		freed = String(a["name"])
	if not hb.is_empty() and int(hb.get("id", -1)) != int(keep.get("id", -2)) \
			and _home_family_ok(b, hb):
		freed = String(b["name"])
	a["home"] = keep
	b["home"] = keep
	# дети обоих — в общий дом
	for other in residents:
		if String(other["prof"]) != "":
			continue
		var parents: Array = other.get("parents", [])
		if parents.has(int(a["id"])) or parents.has(int(b["id"])):
			other["home"] = keep
	if freed != "":
		_chron("chron.wedding_home", freed)
		events.append({"type": "wedding_home", "name": freed})


## День основания (M13): раз в N дней город гуляет всем городом —
## вечером все у таверны и костра, еда расходуется, настроение поднимается.
func _roll_festival() -> void:
	var lcfg: Dictionary = cfg.get("life", {})
	var every := int(lcfg.get("festival_every_days", 0))
	if every <= 0 or day_number() % every != 0:
		return
	var cost := float(lcfg.get("festival_food", 12.0))
	if float(res["food"]) + _piled_total_of("food") < cost:
		_chron("chron.found_skip")
		events.append({"type": "found_skip"})
		return
	res["food"] = maxf(0.0, float(res["food"]) - cost)
	var dm := float(lcfg.get("festival_mood", 8.0))
	for r in residents:
		if String(r["prof"]) != "":
			r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	# друзья дарят подарки (M14-F): отношения крепнут, память хранит праздник
	var friends_at := float(_v3().get("friend_threshold", 50.0))
	var gift_bonus := float(_v3().get("gift_rel_bonus", 6.0))
	var gifted: Array = []
	for r in _adults():
		var rel: Dictionary = r.get("rel", {})
		for k in rel:
			var other := _resident_by_id(int(k))
			if other.is_empty() or gifted.has(other) or gifted.has(r):
				continue
			if float(rel[k]) >= friends_at and _rel_score(other, int(r["id"])) >= friends_at:
				_rel_change(r, other, gift_bonus)
				_mem_push(r, "gift")
				_mem_push(other, "gift")
				gifted.append(r)
				gifted.append(other)
				_chron("chron.fest_gift", String(r["name"]), String(other["name"]))
				events.append({"type": "fest_gift", "a": String(r["name"]), "b": String(other["name"])})
				break
	# служба в храме (M14-H): на праздник с живым служкой город молится усерднее
	if temple_staffed():
		for r in _adults():
			r["mood"] = clampf(float(r["mood"]) + 8.0, 0.0, 100.0)
		_chron("chron.service")
		events.append({"type": "service"})
	_chron("chron.found_day")
	events.append({"type": "found_day"})


## Ребёнок повзрослел: получает профессию (реже всех) и черты характера.
func _grow_up(r: Dictionary) -> void:
	var pool: Array = []
	if not elder_present():
		pool.append("elder")   # город без старосты вырастит нового из повзрослевшего
	for prof in cfg["start"]["professions"]:
		pool.append(String(prof))
	var counts := {}
	for other in residents:
		if String(other["prof"]) != "":
			counts[String(other["prof"])] = int(counts.get(String(other["prof"]), 0)) + 1
	var best := ""
	var best_count := 999999
	for prof in pool:
		var c := int(counts.get(String(prof), 0))
		if c < best_count:
			best_count = c
			best = String(prof)
	r["prof"] = best
	r["traits"] = _random_traits()
	r["age_days"] = 100.0
	_chron("chron.grown", String(r["name"]), best)
	events.append({"type": "grown", "name": String(r["name"]), "prof": best})
	_assign_jobs()


## Летопись: хранит ключи локализации, текст собирает HUD.
func _chron(key: String, a: String = "", b: String = "") -> void:
	chronicle.append({"day": day, "key": key, "a": a, "b": b})
	if chronicle.size() > 200:
		chronicle.pop_front()
