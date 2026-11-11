# Часть: главный тик и дневные броски, автомат жителя, сон/дома/оборона,
# кучи и движение (путь/A*).
# Структура v1.62.0: жизнь жителей — в city_sim_residents.gd, производство —
# в city_sim_produce.gd, кладбище — в city_sim_necro.gd. Один класс,
# поведение не меняется.
extends "res://scripts/city_sim_people.gd"

# --- главный тик ---------------------------------------------------------

func tick(dt_raw: float) -> void:
	if paused or map == null:
		return
	var dt := dt_raw * speed
	var day_len := float(cfg["day_length"])
	time += dt
	day = int(time / day_len) + 1
	# v1.49 (приёмка): бой не разгоняется ускорением времени — герой двигается
	# в реальном времени, и на x10 мутанты улетали «со скоростью света».
	# Экономика/дни идут на полном множителе, монстры и звери — до потолка.
	var dt_combat := dt_raw * minf(speed, float(cfg.get("combat_speed_cap", 3.0)))
	# еда: все жители едят непрерывно (обжора ×2, ребёнок ×0.5); пусто — город голодает
	var eaters := 0.0
	for r in residents:
		if _is_golem(r):
			continue   # голем-староста не ест (правки v1.20)
		var portion := _trait_prod(r, "food_mult")
		if String(r["prof"]) == "":
			portion *= float(people.get("child_food", 0.5))
		eaters += portion
	var eat: float = float(cfg["food_per_resident_day"]) * dt / day_len * eaters
	if has_law("refuge_shelter"):
		eat *= float(law_param("refuge_shelter", "food_mult", 1.0))   # приют кормит лишние рты (M14-H)
	if season() == "winter":
		eat *= float(_weather_cfg().get("effects", {}).get("winter_food_mult", 1.1))   # зима (M14-J)
	res["food"] = maxf(0.0, float(res["food"]) - eat)
	# голод не ждёт носильщика (2026-10-21): еда кончилась, а кучи лежат у ферм —
	# город разбирает их руками, иначе поселенцы голодают при полных грядках
	if float(res["food"]) < 1.0:
		_pull_food_piles_to_pool()
	_tavern_beer(dt, day_len)
	# инструменты изнашиваются у работающих (мастерская обновляет запас)
	var workers := 0
	for r in residents:
		if String(r["state"]) == "work" or String(r["state"]) == "build":
			workers += 1
	if workers > 0 and float(res.get("tools", 0.0)) > 0.0:
		res["tools"] = maxf(0.0, float(res["tools"]) - float(cfg.get("tools_wear_per_day", 0.1)) * workers * dt / day_len)
	# магия (M3): резонанс, спад загрязнения, стан зданий, дикие события
	if resonance_left > 0.0:
		resonance_left = maxf(0.0, resonance_left - dt)
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	if not pol_cfg.is_empty() and pollution > 0.0:
		pollution = maxf(0.0, pollution - float(pol_cfg.get("decay_per_day", 2.0))
				* research_mult("pollution_decay_mult", 1.0) * dt / day_len)
	for b in buildings:
		if float(b.get("stun_left", 0.0)) > 0.0:
			b["stun_left"] = maxf(0.0, float(b["stun_left"]) - dt)
	_update_wild_events(pol_cfg, day_len)
	_update_storm(dt_combat, day_len)
	_update_threat(dt_combat, day_len)
	_update_animals(dt_combat)
	_update_livestock(dt)
	_update_wanderers(dt)
	_update_zones(dt, day_len)
	_update_forest(dt, day_len)
	_update_cemetery(dt, day_len)   # костры догорают, останки истлевают (v1.23)
	for r in residents:
		_update_resident(r, dt)
	# люди (M4): раз в игровой день — преемник старосты, болезни, беженцы, рождения, стройка, истории.
	# v1.28: дневной блок РАЗБИТ на 3 фазы по тикам — раньше всё (~30 роллов,
	# включая morning_plan с переназначением всех жителей = пакет A*) шло в
	# ОДНОМ тике и давало фризы на границе дня (заказчик связывал их со
	# сменой погоды — она бросается в том же блоке).
	if day > _last_daily_day:
		_last_daily_day = day
		_daily_phase = 1
		_ensure_elder()
		_ensure_plaza()
		_apply_resource_bonuses()   # v1.56: богатства региона
		_craftsman_convert()        # v1.56: ремесленный двор — сырьё в предметы роскоши
		if rivalry_cb.is_valid():
			rivalry_cb.call()   # v1.55: ежедневное соперничество регионов
	match _daily_phase:
		1:
			# фаза 1 — самая тяжёлая: стройка и переназначение всех жителей
			var t0: int = Time.get_ticks_usec()
			_roll_autobuild()
			var t1: int = Time.get_ticks_usec()
			_roll_city_repair()   # город чинит сам: строитель 50%, непрофильный 70% (v1.21.3)
			var t2: int = Time.get_ticks_usec()
			morning_plan()
			var t3: int = Time.get_ticks_usec()
			_daily_phase = 2
		2:
			# фаза 2 — люди и события (болезни/беженцы/рождения/стражи/охота...)
			_roll_ailments()
			_roll_pests()   # v1.56: жуки на поля — обоснованная жалоба фермера
			_roll_refugees()
			_roll_births()
			_roll_stories()
			_roll_couples()
			_roll_festival()
			_roll_guards()
			_roll_hunter()
			_roll_porter()
			_roll_corpse_haul()   # останки врагов несут на кладбище (v1.23)
			_pull_idle_piles()   # без носильщика кучи разносятся руками (v1.21)
			_daily_phase = 3
		3:
			# фаза 3 — экономика, мир, погода/квесты/сюжет
			_roll_auto_roads()
			_roll_animals()
			_roll_storm()
			_roll_livestock()
			_roll_market()
			_roll_wanderer()
			_watchdog_stuck()
			_tick_caravans()
			_tick_tents()
			_tick_orchards()
			_roll_necro()
			_roll_v3()   # жизнь v3 (M14-F): память, отношения, личные цели
			_roll_weather()   # погода и сезоны (M14-J)
			_roll_quests()   # доска объявлений (M14-K)
			_roll_story()   # сюжетная рамка (M14-L)
			_daily_phase = 0
	_update_gates()   # один скан за тик: страж/стройка/волна меняют створки сразу


## Дикие события (ответ №61): при переборе загрязнения (>= band_wild) раз в день
## с шансом event_chance_per_day: вспышка (стан здания), прилив маны (+загрязнение,
## усталость), сгущение маны (+кристалл). Защищает только зачарование «Оберег».
func _update_wild_events(pol_cfg: Dictionary, day_len: float) -> void:
	if pol_cfg.is_empty() or pollution < float(pol_cfg.get("band_wild", 85.0)):
		return
	if day == _last_event_day:
		return
	_last_event_day = day
	if _event_rng.randf() > float(pol_cfg.get("event_chance_per_day", 0.5)):
		return
	var kind := _weighted_pick(pol_cfg.get("event_weights", {"flash": 5, "surge": 3, "gift": 2}))
	match kind:
		"flash":
			var target := _wild_flash_target()
			if target.is_empty():
				_wild_surge(pol_cfg)
				return
			target["stun_left"] = float(pol_cfg.get("flash_stun_days", 1.0)) * day_len
			events.append({"type": "wild_flash", "bld": String(target["type"])})
		"surge":
			_wild_surge(pol_cfg)
		"gift":
			_add_resource_capped("crystal", float(pol_cfg.get("gift_crystals", 1)))
			events.append({"type": "wild_gift"})


func _wild_surge(pol_cfg: Dictionary) -> void:
	pollution = minf(float(pol_cfg.get("max", 100.0)), pollution + float(pol_cfg.get("surge_pollution", 5.0)))
	for r in residents:
		r["fatigue"] = float(r["fatigue"]) + float(pol_cfg.get("surge_fatigue", 0.2))
	events.append({"type": "wild_surge"})
	# дикая мана калечит (M4): случайный взрослый получает рану
	var acfg: Dictionary = people.get("ailments", {})
	var wounded_n := int(acfg.get("wounded_on_surge", 1))
	var adults := _adults()
	for i in wounded_n:
		if adults.is_empty():
			break
		var r: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
		_make_ail(r, "wounded", "chron.wounded")
		events.append({"type": "wounded", "name": String(r["name"])})


## Случайное готовое здание без «Оберега» (для дикой вспышки).
func _wild_flash_target() -> Dictionary:
	var candidates: Array = []
	for b in buildings:
		if _active(b) and String(b.get("enchant", "")) != "ward":
			candidates.append(b)
	if candidates.is_empty():
		return {}
	return candidates[_event_rng.randi_range(0, candidates.size() - 1)]


func _weighted_pick(weights: Dictionary) -> String:
	var total := 0
	for w: int in weights.values():
		total += w
	var roll := _event_rng.randi_range(1, maxi(1, total))
	for key in weights:
		roll -= int(weights[key])
		if roll <= 0:
			return String(key)
	return ""


func _update_resident(r: Dictionary, dt: float) -> void:
	var day_len := float(cfg["day_length"])
	r["inside"] = 0   # бодрый житель снаружи; _sleep/_lie_ill/_flee_home ставят заново у входа
	_update_mood(r, dt, day_len)
	r["chat_cd_left"] = maxf(0.0, float(r.get("chat_cd_left", 0.0)) - dt)
	# голод: без дела — идёт в очередь к складу; занятый работает вполсилы (иначе город умирает навсегда)
	if float(res["food"]) <= 0.0 and r["site"] == null and r["bld"] == null:
		_hungry_queue(r, dt)
		return
	# ребёнок: растёт, не работает; играет у колодца (M12); повзрослел — профессия и черты
	if String(r["prof"]) == "":
		_child_update(r, dt, day_len)
		return
	# болен или ранен: идёт домой и лежит
	if String(r.get("ail", "")) != "":
		_lie_ill(r, dt)
		return
	# утренняя планёрка (правки v1.20): после раздачи плана город собирается
	# у главной площади — планёрка короткая, работа не страдает; несущий груз
	# носильщик идёт сдавать груз, а не стоять в кругу
	if not raid_active and not _raid_warned \
			and float(r.get("meeting_until", 0.0)) > time and String(r["prof"]) != "" \
			and float(r.get("carry", 0.0)) <= 0.0:
		var mt: Vector2i = r.get("meeting_tile", map.spawn_tile)
		if _arrived(r, mt):
			r["state"] = "meeting"
			r["path"] = PackedVector2Array()
			_try_chat(r)
		else:
			_move_towards(r, mt, dt)
		return
	var night := is_night()
	var tcfg: Dictionary = cfg.get("threat", {})
	# v1.47: ВЕЧЕРНЯЯ СОЦЖИЗНЬ («Новый мир v2» этап 5) — до ночи, без осады:
	# свободные жители гуляют к другу/любимому; встреча — свидание; свидетель
	# ревнует (любовный треугольник рождается из прогулок).
	# v1.50: бригада починки вечером не гуляет — чинит целый день
	if not night and not raid_active and not raid_breached \
			and int(r.get("repair_bld", 0)) <= 0:
		var day_frac := fmod(time, float(cfg["day_length"])) / float(cfg["day_length"])
		var evening := day_frac >= float(cfg.get("evening_start", 0.62)) \
				and day_frac <= 1.0 - float(cfg.get("night_fraction", 0.22))
		if evening and _social_walk(r, dt):
			return
	# угроза (M5+): бойцы снаряжаются в оружейке с предупреждения; трус прячется,
	# только когда волна пришла (v1.25, заказчик: предупреждение длится дни —
	# город не должен всё это время стоять у костра, работа идёт до самой атаки)
	if raid_active or _raid_warned:
		if raid_active and _has_trait_flag(r, "flees"):
			_flee_home(r, dt)
			return
		if String(r["prof"]) == "guard":
			_defender_update(r, dt, float(tcfg.get("guard_damage", 2)), float(tcfg.get("guard_cd", 1.0)))
			return
	if raid_active:
		# v1.47: ПРОРЫВ — паника: непанельные (не страж/ополчение) бегут домой
		if raid_breached and String(r["prof"]) != "guard" \
				and not _has_trait_flag(r, "fearless") \
				and (r["site"] != null or r["bld"] != null or int(r.get("inside", 1)) == 0):
			if _event_rng.randf() < 0.5:
				r["mood"] = clampf(float(r["mood"]) - 8.0, 0.0, 100.0)
			_flee_home(r, dt)
			return
		# ополчение: бьются все свободные взрослые и храбрые работники (заказчик)
		var free := r["site"] == null and r["bld"] == null
		if (free or _has_trait_flag(r, "fearless")) \
				and String(r["prof"]) != "" and String(r["prof"]) != "elder":
			_defender_update(r, dt, float(tcfg.get("militia_damage", 1)), float(tcfg.get("militia_cd", 1.5)))
			return
	# похороны (M12): носильщики процессии идут к кладбищу
	if int(r.get("funeral", 0)) > 0:
		_funeral_update(r, dt)
		return
	# тайный некромант (v1.23): ночью крадётся на кладбище изучать тьму;
	# главное — чтобы никто не видел (кроме сна его ничто не перебивает)
	if night and String(r.get("secret", "")) == "necromancer" and not necro_known:
		if _necro_night_walk(r, dt):
			return
	# несёт бревно прохожим (v1.23): довести до лесопилки важнее дел
	# (v1.25: и во время предупреждения о волне — работа не встаёт)
	if not raid_active and not night and bool(r.get("haul_log", false)):
		if _log_haul_work(r, dt):
			return
	# ночь: спят все, кроме стража ночной смены (дежурство день/ночь — заказчик)
	var guard_on_duty := String(r["prof"]) == "guard" \
			and ((night and String(r.get("shift", "day")) == "night") \
				or (not night and String(r.get("shift", "day")) == "day"))
	if night and not guard_on_duty and not _is_golem(r):
		_sleep(r, dt)
		return
	if night and _is_golem(r) and String(r["prof"]) == "elder":
		# голем не спит: ночью обходит владения (правки v1.20); днём — работает
		# как обычный резерв (стройка/ферма в соло-городе)
		if not _zone_fill_work(r, dt):
			_manage_walk(r, dt)
		return
	# сильная усталость: отдых в любое время
	if float(r["fatigue"]) >= float(cfg["tired_at"]):
		r["state"] = "rest"
		r["fatigue"] = maxf(0.0, float(r["fatigue"]) - _restore_rate(r, false) * dt / day_len)
		r["path"] = PackedVector2Array()
		return
	# бригада починки (v1.50): работа целого дня — раньше вечерних увеселений
	if _repair_errand(r, dt):
		return
	# вечер (M12): работа кончилась; правки v1.20.1 — сперва работник уносит
	# произведённую кучу своего здания на склад (или в центр), потом отдыхает
	if not raid_active and not _raid_warned and _is_evening() \
			and r["site"] == null and String(r["prof"]) != "elder":
		if _evening_haul(r, dt):
			return
		_leisure(r, dt)
		return
	if r["site"] != null:
		_do_build(r, r["site"], dt)
		return
	# поваленное дерево рядом (v1.23): прохожий со свободными руками
	# подберёт бревно и отнесёт его на лесопилку
	if not raid_active and _try_haul_log(r, dt):
		return
	# останки павшего врага (v1.23): донести до кладбища и похоронить
	if _corpse_work(r, dt):
		return
	if r["bld"] != null:
		var bld_type := String(r["bld"]["type"])
		if bld_type == "tent":
			_tent_tend(r, r["bld"], dt)   # торговец за прилавком (этап 2, аспект 4)
			return
		if bld_type == "workshop":
			_workshop_work(r, r["bld"], dt)   # сперва ремонт повреждённых, потом переработка (M6)
			return
		if bld_type == "farm":
			_farm_work(r, r["bld"], dt)   # грядки своей фермы: сбор спелых, вспашка (v1.21)
			return
		if bld_type == "sawmill" or bld_type == "quarry" or bld_type == "mine":
			_gather_work(r, r["bld"], dt)   # добытчики у источника (v1.21: без пассива)
			return
		if _def(r["bld"]).has("produce"):
			_do_work(r, r["bld"], dt)
		elif guard_on_duty:
			_guard_post(r, dt)   # на смене — стоит на посту (вышка рядом открывает ворота)
		elif String(r["prof"]) == "guard" and _help_build(r, dt):
			pass                 # вне смены страж помогает городу строить (заказчик)
		elif String(r["prof"]) == "guard" and _guard_patrol(r, dt):
			pass                 # строек нет — страж обходит ворота (M12)
		elif String(r["prof"]) == "guard" and _guard_spar(r, dt):
			pass                 # и ворот нет — стражи тренируются друг с другом (v1.23)
		else:
			r["state"] = "idle"
		return
	if String(r["prof"]) == "hunter":
		_hunt(r, dt)
		return
	if String(r["prof"]) == "porter":
		_porter_work(r, dt)   # носит кучи со зданий на склад (M6)
		return
	# (бригадная починка проверяется выше — v1.50: работа целого дня,
	# раньше вечерних увеселений)
	if String(r["prof"]) == "elder":
		# староста при деле: пока есть незаполненные клетки зон и спелые
		# грядки — работает ими (иначе в соло-городе поле стоит пустым),
		# всё обустроено — обходит владения (правка 2026-10-21)
		if not _zone_fill_work(r, dt):
			_manage_walk(r, dt)
		return
	if guard_on_duty:
		_guard_post(r, dt)
		return
	if _tame_work(r, dt):
		return   # ловчий тащит дикого зверя на пастбище (этап 2)
	if _tent_visit(r, dt):
		return   # зашёл «купить» к работающей палатке (этап 2, аспект 4);
	          # короткое отвлечение — раньше стройки-помощи, иначе в живом
	          # городе свободных жителей перехватят площадки
	if _zone_fill_work(r, dt):
		return   # свободный житель обустраивает зоны (M6: город заполняет их сам)
	if _help_build(r, dt):
		return   # свободный житель в мирное время тоже помогает строить (заказчик)
	if String(r["prof"]) == "guard" and _guard_spar(r, dt):
		return   # стражу нет работы — тренировка с напарником (v1.23)
	r["state"] = "idle"


## Страж на посту: стоит у закреплённой вышки. Вышки нет — тренируется
## с напарником (v1.23), напарника нет — ждёт.
func _guard_post(r: Dictionary, dt: float) -> void:
	var tower := _assigned_done(r, "guard")
	if not tower.is_empty():
		if at_bld(r, tower):
			r["state"] = "guard"
			r["fatigue"] += dt / float(cfg["day_length"]) * _fatigue_cost(r)
		else:
			_move_towards(r, bld_spot(tower), dt)
	elif not _guard_spar(r, dt):
		r["state"] = "idle"


## Страж вне смены помогает городу: строит ближайшую площадку. False — помогать нечем.
func _help_build(r: Dictionary, dt: float) -> bool:
	if raid_active or _raid_warned:
		return false   # при угрозе все силы — обороне
	var site: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if bool(b["done"]):
			continue
		var d: float = map.tile_center_px(b["tile"]).distance_to(r["pos"])
		if d < best_d:
			best_d = d
			site = b
	if site.is_empty():
		return false
	_do_build(r, site, dt)
	return true


## Патруль стража вне смены (M12): обходит ворота по кругу. False — ворот нет.
func _guard_patrol(r: Dictionary, dt: float) -> bool:
	var gates: Array = []
	for b in buildings:
		if _active(b) and String(_def(b).get("effect", "")) == "gate":
			gates.append(Vector2i(b["tile"]))
	if gates.is_empty():
		return false
	var i := int(r.get("patrol_i", 0)) % gates.size()
	var target: Vector2i = map.nearest_walkable(gates[i])
	if _arrived(r, target):
		r["patrol_i"] = i + 1
		r["state"] = "patrol"
		r["path"] = PackedVector2Array()
		return true
	_move_towards(r, target, dt)
	if String(r["state"]) != "going":
		r["patrol_i"] = i + 1
		r["state"] = "patrol"
	return true


## Бездомный ли житель: дом бывает null или пустой словарь от неудачного
## поиска ДО постройки домов — пустышка не должна прилипать навсегда (фикс 2026-10-21).
func _homeless(r: Dictionary) -> bool:
	if r["home"] == null:
		return true
	return (r["home"] as Dictionary).is_empty()


func _sleep(r: Dictionary, dt: float) -> void:
	if _homeless(r) or not _home_family_ok(r, r["home"]):
		r["home"] = _free_home(r)
	var home: Dictionary = r["home"]
	if not home.is_empty():
		if not at_bld(r, home):
			_move_towards(r, bld_spot(home), dt)
			return
		r["inside"] = 1   # спит внутри дома: с карты не виден, окно светится
	r["state"] = "sleep"
	r["fatigue"] = maxf(0.0, float(r["fatigue"]) - _restore_rate(r, true) * dt / float(cfg["day_length"]))


## Свободный дом по правилу «один дом — один человек» (правки v1.20):
## ребёнок живёт с родителями; пара — в одном доме (второй дом освобождается);
## одиночка получает дом, где не живёт чужая семья.
func _free_home(r: Dictionary) -> Dictionary:
	# ребёнок — к живому родителю (дом родителей и есть его дом)
	if String(r["prof"]) == "":
		for pid in (r.get("parents", []) as Array):
			var parent := _resident_by_id(int(pid))
			if parent.is_empty() or _homeless(parent):
				continue
			return parent["home"]
	# взрослый при паре — дом партнёра (пара занимает один дом)
	var partner := _resident_by_id(int(r.get("partner", -1)))
	if not partner.is_empty() and not _homeless(partner):
		return partner["home"]
	# свой дом ещё годен (там только он, его пара и его дети) — остаётся
	if not _homeless(r) and _home_family_ok(r, r["home"]):
		return r["home"]
	# пустой дом без чужих взрослых: первый подошедший его занимает
	var best: Dictionary = {}
	var best_dist := INF
	var busy := _homes_adults()
	for b in buildings:
		if not _active(b) or _def(b).get("effect", "") != "pop":
			continue
		if busy.has(int(b["id"])):
			continue   # в доме живёт чужой взрослый
		var dist: float = map.tile_center_px(b["tile"]).distance_to(r["pos"])
		if dist < best_dist:
			best_dist = dist
			best = b
	return best


## В доме только сам житель, его пара и их дети? (чужих выселять нельзя)
func _home_family_ok(r: Dictionary, home: Dictionary) -> bool:
	if home.is_empty():
		return false
	var hid := int(home["id"])
	var pid := int(r.get("partner", -1))
	for other in residents:
		if other == r:
			continue
		if String(other["prof"]) == "":
			var parents: Array = other.get("parents", [])
			if parents.has(int(r["id"])) or (pid >= 0 and parents.has(pid)):
				continue   # его ребёнок (или ребёнок пары) — живёт с ним
			var ok_kid := false
			for opid in parents:   # ребёнок партнёра от прежнего — тоже семья
				var op := _resident_by_id(int(opid))
				if not op.is_empty() and int(op.get("partner", -1)) == int(r["id"]):
					ok_kid = true
			if ok_kid:
				continue
		if int(other.get("partner", -1)) == int(r["id"]):
			continue   # его пара — общий дом
		var oh = other.get("home", null)
		if oh != null and not (oh as Dictionary).is_empty() \
				and int((oh as Dictionary).get("id", -1)) == hid:
			return false
	return true


## Список id домов, где живёт хоть один взрослый.
func _homes_adults() -> Dictionary:
	var busy := {}
	for other in residents:
		if String(other["prof"]) == "":
			continue   # дети живут с родителями и дом не «занимают»
		var oh = other.get("home", null)
		if oh != null and not (oh as Dictionary).is_empty():
			busy[int((oh as Dictionary)["id"])] = true
	return busy


## Скорость восстановления усталости (в единицах усталости за игровой день).
## Дом ускоряет сон, колодец ускоряет любой отдых.
func _restore_rate(r: Dictionary, sleeping: bool) -> float:
	var base: float = float(cfg["sleep_restore_home"] if sleeping and r["home"] != null and not r["home"].is_empty() else cfg["sleep_restore_no_home"])
	if not sleeping:
		base *= float(cfg["rest_fraction"])
	for b in buildings:
		if _active(b) and _def(b).get("effect", "") == "sleep":
			base *= 1.0 + float(cfg["well_bonus"])
			break
	return base


## Боец (страж или ополченец) при угрозе: без комплекта идёт в оружейку
## (страж перед осадой снаряжается и ждёт — заказчик), с комплектом бьёт сильнее.
## v1.23: урон растёт от боевого навыка и силы, бой их и прокачивает.
func _defender_update(r: Dictionary, dt: float, dmg: float, cd: float) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	var acfg: Dictionary = cfg.get("attributes", {})
	var armory := _done_building_of_type("armory")
	# снаряжение: в хранилище есть комплекты, боец ещё без него
	if not bool(r.get("kit", false)) and float(res.get("kits", 0.0)) > 0.0 and not armory.is_empty():
		if at_bld(r, armory):
			res["kits"] = maxf(0.0, float(res["kits"]) - 1.0)
			r["kit"] = true
		else:
			_move_towards(r, bld_spot(armory), dt)
			return
	var mult := float(tcfg.get("kit_damage_mult", 2.0)) if bool(r.get("kit", false)) else 1.0
	var sk: Dictionary = r.get("skills", {})
	mult *= 1.0 + float(acfg.get("combat_skill_dmg", 0.06)) * float(sk.get("warrior", 0.0))
	mult *= 1.0 + float(acfg.get("combat_str_dmg", 0.04)) * _stat(r, "str")
	var target := _nearest_raider(r["pos"], float(map.ts) * 10.0)
	if target.is_empty():
		# волна ещё в пути: страж ждёт на вышке, ополчение — в центре города
		if String(r["prof"]) == "guard":
			var tower := _assigned_done(r, "guard")
			if not tower.is_empty():
				if at_bld(r, tower):
					r["state"] = "guard"
				else:
					_move_towards(r, bld_spot(tower), dt)
				return
		if not _arrived(r, map.spawn_tile + Vector2i(1, 0)):
			_move_towards(r, map.spawn_tile + Vector2i(1, 0), dt)
		else:
			r["state"] = "guard"
		return
	var dist: float = (target["pos"] as Vector2).distance_to(r["pos"])
	if dist <= float(map.ts) * 1.5:
		r["atk_cd"] = maxf(0.0, float(r.get("atk_cd", 0.0)) - dt)
		if float(r["atk_cd"]) <= 0.0:
			r["atk_cd"] = cd
			# v1.36: страж на плато бьёт мутанта снизу с бонусом высоты (№113)
			_hit_raider(target, int(round(dmg * mult)), map.tile_of_px(r["pos"]))
			_grow_combat(r, cd)   # бой прокачивает воина, силу и ловкость (v1.23)
		r["state"] = "guard"
	else:
		_move_towards(r, map.tile_of_px(target["pos"]), dt)


func _done_building_of_type(type_id: String) -> Dictionary:
	for b in buildings:
		if _active(b) and String(b["type"]) == type_id:
			return b
	return {}


## Трус прячется дома, пока в городе мутанты.
func _flee_home(r: Dictionary, dt: float) -> void:
	if _homeless(r):
		r["home"] = _free_home(r)
	var home: Dictionary = r["home"]
	if not home.is_empty():
		if not at_bld(r, home):
			_move_towards(r, bld_spot(home), dt)
			return
		r["inside"] = 1   # трус прячется внутри дома
	r["state"] = "hide"


func _do_build(r: Dictionary, site: Dictionary, dt: float) -> void:
	if site["done"]:
		r["site"] = null
		r["sub_prof"] = ""
		return
	if bld_has_cell(site, map.tile_of_px(r["pos"])):
		r["state"] = "build"
		# v1.56: медные инструменты ускоряют стройку на 10%
		var copper_mult := 1.1 if float(res.get("copper", 0.0)) >= 5.0 else 1.0
		site["progress"] = float(site["progress"]) + dt * work_mult(r) * copper_mult
		r["fatigue"] += dt / float(cfg["day_length"]) * _fatigue_cost(r)
		_grow_skill(r, dt)
		if float(site["progress"]) >= float(_def(site)["build_work"]):
			r["site"] = null
			r["sub_prof"] = ""
			_complete_site(site)
	else:
		_move_towards(r, site["tile"], dt)


## Куча у здания — УПРАЗДНЕНА (v1.25): производство идёт сразу в пул.
## Функция оставлена на всякий случай для сейвов/модов, новые кучи
## никто не создаёт; старые разносит носильщик и дневной разбор.
func _add_pile(bld: Dictionary, key: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var pile: Dictionary = bld.get("pile", {})
	var total := 0.0
	for k in pile:
		total += float(pile[k])
	var left: float = maxf(0.0, float(cfg.get("piles", {}).get("max", 20.0)) - total)
	if left <= 0.0:
		return
	pile[key] = float(pile.get(key, 0.0)) + minf(amount, left)
	bld["pile"] = pile


## Всего ресурса key в кучах по всем зданиям (для запаса еды город учитывает и кучи).
func _piled_total_of(key: String) -> float:
	var total := 0.0
	for b in buildings:
		if not bool(b["done"]) or not (b as Dictionary).has("pile"):
			continue
		total += float((b["pile"] as Dictionary).get(key, 0.0))
	return total


## Голодный город разбирает кучи еды у зданий прямо в общий пул (без носильщика).
func _pull_food_piles_to_pool() -> void:
	for b in buildings:
		if not bool(b["done"]) or not (b as Dictionary).has("pile"):
			continue
		var pile: Dictionary = b["pile"]
		var have := float(pile.get("food", 0.0))
		if have <= 0.0:
			continue
		_add_resource_capped("food", have)
		pile.erase("food")
		if pile.is_empty():
			b.erase("pile")


func _pile_total(b: Dictionary) -> float:
	var total := 0.0
	for k in b.get("pile", {}):
		total += float(b["pile"][k])
	return total


## Закреплённое готовое здание с работником r (для вышки стража).
func _assigned_done(r: Dictionary, worker_prof: String) -> Dictionary:
	for b in buildings:
		if b["done"] and int(b["worker"]) == int(r["id"]) and String(_def(b).get("worker", "")) == worker_prof:
			return b
	return {}


func _resident_by_id(rid: int) -> Dictionary:
	for cand in residents:
		if int(cand["id"]) == rid:
			return cand
	return {}


func _arrived(r: Dictionary, tile: Vector2i) -> bool:
	return map.tile_of_px(r["pos"]) == tile


func _move_towards(r: Dictionary, tile: Vector2i, dt: float) -> void:
	r["state"] = "going"
	var path: PackedVector2Array = r["path"]
	# v1.26 (FPS в осаду): полный A* дорог, а цели у догоняющих (охотник за
	# зверем, ополченец за мутантом) мельтешат каждый тик — новая цель сначала
	# доигрывается по старому пути (repath_gap), пустой путь (замуровали)
	# пересчитывается по таймеру empty_retry: снесённая стена выпускает жителя
	var pcfg: Dictionary = cfg.get("pathing", {})
	if r["target"] != tile:
		var cd := float(r.get("_repath_cd", 0.0)) - dt
		r["_repath_cd"] = cd
		if path.is_empty() or cd <= 0.0:
			r["target"] = tile
			r["path"] = map.path_px(r["pos"], tile)
			r["_repath_cd"] = float(pcfg.get("repath_gap", 0.3))
			path = r["path"]
	elif path.is_empty() and time >= float(r.get("_repath_at", 0.0)):
		r["path"] = map.path_px(r["pos"], tile)
		r["_repath_at"] = time + float(pcfg.get("empty_retry", 1.0))
		path = r["path"]
	if path.is_empty():
		# страховка: замурован на СПЛОШНОМ тайле (стену достроили под ногами);
		# v1.29.2 вода тоже сплошная — житель из старого сейва, застрявший в
		# броде, выталкивается на ближайшую сушу
		var here: Vector2i = map.tile_of_px(r["pos"])
		if map.is_solid(here):
			var free := _nearest_walkable(here)
			if not free == Vector2i(-1, -1):
				r["pos"] = map.tile_center_px(free)
				r["target"] = Vector2i(-1, -1)
				return
		r["state"] = "idle"
		return
	var pos: Vector2 = r["pos"]
	# ловкость ускоряет шаг (v1.23), груз — замедляет
	var step: float = float(cfg["resident_speed"]) * dt * float(r.get("carry_slow", 1.0)) \
			* (1.0 + float(cfg.get("attributes", {}).get("agi_speed", 0.02)) * _stat(r, "agi"))
	# дорога под ногами ускоряет; носильщику — сильнее всех (M6)
	if map.has_road(map.tile_of_px(pos)):
		var rcfg: Dictionary = cfg.get("roads", {})
		step *= float(rcfg.get("porter_mult", 1.8)) if String(r["prof"]) == "porter" \
				else float(rcfg.get("mult", 1.4))
	var step_total := step
	while step > 0.0 and not path.is_empty():
		var to_next: Vector2 = path[0] - pos
		var dist := to_next.length()
		if dist <= step:
			pos = path[0]
			step -= dist
			path.remove_at(0)
		else:
			pos += to_next / dist * step
			step = 0.0
		if absf(to_next.x) >= absf(to_next.y) and absf(to_next.x) > 0.5:
			r["dir"] = "left" if to_next.x < 0.0 else "right"
		elif absf(to_next.y) > 0.5:
			r["dir"] = "back" if to_next.y < 0.0 else "front"
	r["pos"] = pos
	r["path"] = path
	# протоптанная тропа (M6): сколько прошёл — столько износа оставил
	var moved := step_total - step
	r["moving"] = moved > 0.05
	if moved > 0.0:
		map.add_wear(map.tile_of_px(pos), moved / float(map.ts) * float(cfg.get("roads", {}).get("wear_per_tile", 1.0)))
