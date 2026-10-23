# Часть: главный тик и дневные броски, имитация жизни (вечер, досуг, разговоры).
# Правки структуры v1.20.2: огромный city_sim.gd разбит на extends-цепочку
# частей; это один класс, разложенный по файлам — поведение не меняется.
extends "res://scripts/city_sim_people.gd"

# --- главный тик ---------------------------------------------------------

func tick(dt_raw: float) -> void:
	if paused or map == null:
		return
	var dt := dt_raw * speed
	var day_len := float(cfg["day_length"])
	time += dt
	day = int(time / day_len) + 1
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
	_update_gates()
	_update_wild_events(pol_cfg, day_len)
	_update_storm(dt, day_len)
	_update_threat(dt, day_len)
	_update_animals(dt)
	_update_livestock(dt)
	_update_wanderers(dt)
	_update_zones(dt, day_len)
	_update_forest(dt, day_len)
	for r in residents:
		_update_resident(r, dt)
	# люди (M4): раз в игровой день — преемник старосты, болезни, беженцы, рождения, стройка, истории
	if day > _last_daily_day:
		_last_daily_day = day
		_ensure_elder()
		_ensure_plaza()
		# утро старосты (правки v1.20): размещает требуемые здания, затем
		# собирает жителей на площади и раздаёт план по цветам и приоритетам
		_roll_autobuild()
		morning_plan()
		_roll_ailments()
		_roll_refugees()
		_roll_births()
		_roll_stories()
		_roll_couples()
		_roll_festival()
		_roll_guards()
		_roll_hunter()
		_roll_porter()
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
	_update_gates()   # достроенные за тик вышки/ворота сразу меняют проходимость


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
	# угроза (M5+): трус прячется сразу с предупреждения, бойцы снаряжаются в оружейке
	if raid_active or _raid_warned:
		if _has_trait_flag(r, "flees"):
			_flee_home(r, dt)
			return
		if String(r["prof"]) == "guard":
			_defender_update(r, dt, float(tcfg.get("guard_damage", 2)), float(tcfg.get("guard_cd", 1.0)))
			return
		if _raid_warned and not raid_active:
			# ночью даже при тревоге спят (2026-10-21): при волнах раз в 10 дней
			# предупреждение длится 3 дня — без сна город не заселяет дома и не растёт
			# (стражи отсюда недостижимы — они закрыты веткой защитников выше)
			if night:
				_sleep(r, dt)
			else:
				_gather_fire(r, dt)   # сбор у костра: город ждёт волну вместе (M12)
			return
	if raid_active:
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
		else:
			r["state"] = "idle"
		return
	if String(r["prof"]) == "hunter":
		_hunt(r, dt)
		return
	if String(r["prof"]) == "porter":
		_porter_work(r, dt)   # носит кучи со зданий на склад (M6)
		return
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
	r["state"] = "idle"


## Страж на посту: стоит у закреплённой вышки.
func _guard_post(r: Dictionary, dt: float) -> void:
	var tower := _assigned_done(r, "guard")
	if not tower.is_empty():
		if at_bld(r, tower):
			r["state"] = "guard"
			r["fatigue"] += dt / float(cfg["day_length"])
		else:
			_move_towards(r, bld_spot(tower), dt)
	else:
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


# --- имитация жизни v1 (M12) -------------------------------------------------

## Вечер: доля дня от конца работы до ночи — город живёт (таверна, костёр).
func _is_evening() -> bool:
	var day_len := float(cfg["day_length"])
	var life: Dictionary = cfg.get("life", {})
	var evening: float = float(life.get("evening_len", 0.14))
	var nf := float(cfg["night_fraction"])
	var t := fmod(time, day_len) / day_len
	return t >= maxf(0.0, 1.0 - nf - evening) and t < 1.0 - nf


## Точка городского костра: у главной площади (правки v1.20), если есть колодец — у него.
func fire_tile() -> Vector2i:
	for b in buildings:
		if _active(b) and String(b["type"]) == "well":
			return bld_spot(b)
	if plaza != Vector2i(-1, -1):
		return map.nearest_walkable(plaza)
	return map.spawn_tile


## Вечерний снос продукции (правки v1.20.1): поработавший в здании житель
## уносит кучу своего здания на склад (а без склада — в центр города)
## и только потом идёт отдыхать. Одна ходка за вечер, вся куча разом.
func _evening_haul(r: Dictionary, dt: float) -> bool:
	if r["bld"] == null:
		return false
	var bld: Dictionary = r["bld"]
	# несёт бревно или сырой камень (v1.21) — груз продолжит путь утром,
	# вечернюю кучу поверх груза не берём
	if int(r.get("log_size", 0)) > 0 or float(r.get("raw", 0.0)) > 0.0 \
			or float(r.get("carry_iron", 0.0)) > 0.0 or float(r.get("carry_stone", 0.0)) > 0.0:
		return false
	if float(r.get("carry", 0.0)) <= 0.0:
		if int(r.get("hauled_day", 0)) == day:
			return false   # сегодня уже снёс — отдыхаем
		if _pile_total(bld) < 0.5:
			return false   # производить произвёл нечего
		if not at_bld(r, bld):
			_move_towards(r, bld_spot(bld), dt)
			return true
		# забираем самую большую кучу здания целиком (как герой по E)
		var pile: Dictionary = bld.get("pile", {})
		var key := ""
		var best := 0.0
		for k in pile:
			if float(pile[k]) > best:
				best = float(pile[k])
				key = String(k)
		if key == "":
			r["hauled_day"] = day
			return false
		r["carry"] = best
		r["carry_res"] = key
		pile.erase(key)
		bld["pile"] = pile
		r["state"] = "porter"
		return true
	# несём: склад есть — на склад, нет — в центр города (амбар)
	var barn := _nearest_done_of_type(r["pos"], "warehouse")
	var goal: Vector2i = bld_spot(barn) if not barn.is_empty() else map.nearest_walkable(fire_tile())
	if not _arrived(r, goal):
		_move_towards(r, goal, dt)
		return true
	_add_resource_capped(String(r["carry_res"]), float(r["carry"]))
	events.append({"type": "hauled", "name": String(r["name"]),
			"res": String(r["carry_res"]), "n": int(float(r["carry"]))})
	r["carry"] = 0.0
	r["carry_res"] = ""
	r["hauled_day"] = day
	return false


## Вечерний досуг: таверна (если стоит), визит к другу, костёр в центре.
func _leisure(r: Dictionary, dt: float) -> void:
	var lcfg: Dictionary = cfg.get("life", {})
	# разговор: стоит, пока звучит реплика
	if float(r.get("chat_left", 0.0)) > 0.0:
		r["chat_left"] = float(r["chat_left"]) - dt
		if float(r["chat_left"]) <= 0.0:
			r["chat_key"] = ""
			r["chat_left"] = 0.0
			r["state"] = "leisure"
		else:
			r["state"] = "chat"
			r["path"] = PackedVector2Array()
		return
	var plan: Dictionary = r.get("leisure", {})
	if plan.is_empty() or (plan.has("tile") and not map.in_bounds(Vector2i(plan["tile"]))):
		plan = _pick_leisure(r)
		r["leisure"] = plan
	var target: Vector2i = Vector2i(plan.get("tile", map.spawn_tile))
	if not _arrived(r, target):
		_move_towards(r, target, dt)
		if String(r["state"]) != "going":
			r["state"] = "leisure"   # не добрался (замурован) — гуляет где стоит
	if _arrived(r, target):
		r["state"] = "leisure"
		r["path"] = PackedVector2Array()
		# личная цель «пировать в таверне» (M14-F): вечер в таверне засчитан
		if bool(plan.get("tavern", false)):
			r["tavern_visited"] = true
		_try_chat(r)


## Выбор вечернего занятия: в День основания — весь город гуляет (M13),
## иначе таверна 50%, любимый 60% / друг 40%, костёр — остальное.
func _pick_leisure(r: Dictionary) -> Dictionary:
	var tavern := _nearest_done_of_type(r["pos"], "tavern")
	var plan: Dictionary
	if _festival_today():
		if not tavern.is_empty() and randf() < 0.7:
			plan = {"tile": bld_spot(tavern), "tavern": true}
		else:
			plan = {"tile": map.nearest_walkable(fire_tile())}
	else:
		var partner := _partner_of(r)
		if not partner.is_empty() and randf() < 0.6:
			plan = {"tile": map.nearest_walkable(map.tile_of_px(partner["pos"]))}
		elif not tavern.is_empty() and randf() < 0.5:
			plan = {"tile": bld_spot(tavern), "tavern": true}
		elif not working_tents().is_empty() and randf() < 0.25:
			# вечерняя торговая палатка (этап 2, аспект 4): зайти «купить» по пути
			var tents := working_tents()
			plan = {"tile": bld_spot(tents[randi() % tents.size()])}
		else:
			var friend := _friend_of(r)
			if not friend.is_empty() and randf() < 0.4:
				plan = {"tile": map.nearest_walkable(map.tile_of_px(friend["pos"]))}
			else:
				plan = {"tile": map.nearest_walkable(fire_tile())}
	# ссорящиеся (M14-F) избегают друг друга вечером: цель рядом с врагом — к костру
	var foe: Dictionary = rel_worst(r)
	if not foe.is_empty():
		var foe_tile: Vector2i = map.tile_of_px(foe["other"]["pos"])
		if Vector2i(plan["tile"]).distance_to(foe_tile) <= 2:
			plan = {"tile": map.nearest_walkable(fire_tile())}
	return plan


func _friend_of(r: Dictionary) -> Dictionary:
	var fid := int(r.get("friend", -1))
	if fid < 0:
		return {}
	for other in residents:
		if int(other["id"]) == fid and String(other.get("ail", "")) == "":
			return other
	return {}


func _partner_of(r: Dictionary) -> Dictionary:
	var pid := int(r.get("partner", -1))
	if pid < 0:
		return {}
	for other in residents:
		if int(other["id"]) == pid and String(other.get("ail", "")) == "":
			return other
	return {}


## День основания (M13): каждые N дней весь город гуляет у таверны и костра.
func _festival_today() -> bool:
	var every := int(cfg.get("life", {}).get("festival_every_days", 0))
	return every > 0 and day_number() % every == 0 and not is_night()


## Разговор (M12): два праздных жителя рядом обмениваются репликой-облачком.
## В День основания — праздничные реплики, пары говорят о своём (M13).
func _try_chat(r: Dictionary) -> void:
	var lcfg: Dictionary = cfg.get("life", {})
	if float(r.get("chat_cd_left", 0.0)) > 0.0:
		return
	for other in residents:
		if other == r or String(other["prof"]) == "":
			continue
		var st := String(other.get("state", ""))
		if st != "leisure" and st != "chat":
			continue
		if float(other.get("chat_left", 0.0)) > 0.0 or float(other.get("chat_cd_left", 0.0)) > 0.0:
			continue
		if Vector2(other["pos"]).distance_to(Vector2(r["pos"])) > float(map.ts) * 1.5:
			continue
		var base := "chat"
		var lines := maxi(1, int(lcfg.get("chat_lines", 8)))
		if _festival_today():
			base = "fest"
			lines = maxi(1, int(lcfg.get("festival_lines", 4)))
		elif int(other.get("partner", -1)) == int(r["id"]):
			base = "love"
			lines = maxi(1, int(lcfg.get("love_lines", 4)))
		elif _rel_score(r, int(other["id"])) <= float(_v3().get("foe_threshold", -30.0)):
			# ссорящиеся (M14-F): обмениваются колкостями
			base = "spite"
			lines = maxi(1, int(_v3().get("spite_lines", 4)))
		var key := "%s.%d" % [base, randi() % lines]
		r["chat_key"] = key
		other["chat_key"] = key
		r["chat_left"] = float(lcfg.get("chat_seconds", 4.0))
		other["chat_left"] = float(lcfg.get("chat_seconds", 4.0))
		r["chat_cd_left"] = float(lcfg.get("chat_cd", 25.0))
		other["chat_cd_left"] = float(lcfg.get("chat_cd", 25.0))
		return


## Голодный (M12): идёт в очередь к складу (или к центру, если склада нет).
## state остаётся "hungry" и в пути — панель жителей объясняет простой.
func _hungry_queue(r: Dictionary, dt: float) -> void:
	var barn := _nearest_done_of_type(r["pos"], "warehouse")
	var goal: Vector2i = bld_spot(barn) if not barn.is_empty() else map.spawn_tile
	if _arrived(r, goal):
		r["state"] = "hungry"
		r["path"] = PackedVector2Array()
		return
	_move_towards(r, map.nearest_walkable(goal), dt)
	r["state"] = "hungry"   # _move_towards ставит "going" — голод важнее


## Ребёнок (M12): растёт и играет у костра — бегает между соседними тайлами.
func _child_update(r: Dictionary, dt: float, day_len: float) -> void:
	r["age_days"] = float(r.get("age_days", 0.0)) + dt / day_len
	var bcfg: Dictionary = people.get("births", {})
	if float(r["age_days"]) >= float(bcfg.get("child_days", 8.0)):
		_grow_up(r)
		return
	var base := fire_tile()
	var target: Vector2i = Vector2i(r.get("play_tile", base))
	if not _arrived(r, target):
		_move_towards(r, target, dt)
		if String(r["state"]) != "going":
			r["state"] = "child"
		return
	r["state"] = "child"
	r["path"] = PackedVector2Array()
	r["play_left"] = float(r.get("play_left", 0.0)) - dt
	if float(r["play_left"]) <= 0.0:
		r["play_left"] = 2.0 + randf() * 3.0
		var off := Vector2i(randi_range(-2, 2), randi_range(-2, 2))
		r["play_tile"] = map.nearest_walkable(base + off)


## Тревога (M12): свободные жители собираются у костра, пока звучит предупреждение.
func _gather_fire(r: Dictionary, dt: float) -> void:
	var ring := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	var target: Vector2i = map.nearest_walkable(fire_tile() + ring[int(r["id"]) % ring.size()])
	r["state"] = "gather"
	if _arrived(r, target):
		r["path"] = PackedVector2Array()
		return
	_move_towards(r, target, dt)


## Похороны (M12): носильщик дошёл до кладбища — стоит прощание, могилка готова.
func _funeral_update(r: Dictionary, dt: float) -> void:
	if not _arrived(r, funeral_target):
		_move_towards(r, funeral_target, dt)
		if String(r["state"]) != "going":
			r["funeral"] = 0   # не добрался — вернулся к делам
		return
	r["state"] = "funeral"
	r["path"] = PackedVector2Array()
	r["funeral_wait"] = float(r.get("funeral_wait", 0.0)) + dt
	if float(r["funeral_wait"]) >= 2.0:
		r["funeral"] = 0
		r["funeral_wait"] = 0.0
		for g in graves:
			g["ready"] = true


## Запуск похорон: свободные жители несут умершего к кладбищу, готовится могилка.
func _start_funeral(dead: Dictionary, dead_pos: Vector2) -> void:
	var cemetery: Dictionary = {}
	for b in buildings:
		if _active(b) and String(b["type"]) == "cemetery":
			cemetery = b
			break
	if cemetery.is_empty():
		return
	var grave := _next_grave_tile(Vector2i(cemetery["tile"]))
	if grave == Vector2i(-1, -1):
		return
	funeral_target = map.nearest_walkable(Vector2i(cemetery["tile"]))
	funeral_pos = dead_pos
	graves.append({"tile": grave, "name": String(dead["name"]), "ready": false})
	var bearers := 0
	for other in residents:
		if other == dead or String(other["prof"]) == "" or String(other.get("ail", "")) != "":
			continue
		if other["site"] != null or other["bld"] != null or int(other.get("funeral", 0)) > 0:
			continue
		other["funeral"] = 1
		other["funeral_wait"] = 0.0
		bearers += 1
		if bearers >= 2:
			break


## Место под могилку: свободный травяной тайл по спирали вокруг кладбища.
func _next_grave_tile(center: Vector2i) -> Vector2i:
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := center + Vector2i(dx, dy)
				if not map.in_bounds(t) or not map.is_nature_walkable(t):
					continue
				if not building_at(t).is_empty():
					continue
				var taken := false
				for g in graves:
					if Vector2i(g["tile"]) == t:
						taken = true
						break
				if not taken:
					return t
	return Vector2i(-1, -1)


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
func _defender_update(r: Dictionary, dt: float, dmg: float, cd: float) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
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
			_hit_raider(target, int(round(dmg * mult)))
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
		site["progress"] = float(site["progress"]) + dt * work_mult(r)
		r["fatigue"] += dt / float(cfg["day_length"])
		_grow_skill(r, dt)
		if float(site["progress"]) >= float(_def(site)["build_work"]):
			r["site"] = null
			r["sub_prof"] = ""
			_complete_site(site)
	else:
		_move_towards(r, site["tile"], dt)


func _do_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		# дикая вспышка: здание молчит, работник стоит
		r["state"] = "idle"
		return
	if at_bld(r, bld):
		_produce_tick(r, bld, dt)
	else:
		_move_towards(r, bld_spot(bld), dt)


## Добытчики у источников (лесопилка/каменоломня/шахта) — правки v1.21
## переехали в city_sim_gather.gd: лесоруб валит и пилит, шахтёр носит
## сырой камень на переработку. Ниже — мастерская и производство.


## Мастерская (M6, перепрофилирование): сперва чинит повреждённые здания,
## когда чинить нечего — перерабатывает дерево и камень в инструменты.
func _workshop_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		r["state"] = "idle"
		return
	var broken := _damaged_building(bld)
	if broken.is_empty():
		_produce_tick(r, bld, dt)   # переработка излишков в инструменты
		return
	if at_bld(r, broken):
		r["state"] = "repair"
		var rate: float = float(cfg.get("repair", {}).get("per_day", 15.0)) * work_mult(r)
		var max_hp := float(_bld_max_hp(String(broken["type"])))
		broken["hp"] = minf(float(broken.get("hp", max_hp)) + rate * dt / float(cfg["day_length"]), max_hp)
		r["fatigue"] += dt / float(cfg["day_length"])
		_grow_skill(r, dt)
	else:
		_move_towards(r, bld_spot(broken), dt)


## Повреждённое готовое здание ближе прочих (для мастерской). Руины мастерская
## не поднимает — только стоящие повреждённые (этап 2, аспект 5).
func _damaged_building(near: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if not _active(b):
			continue
		var max_hp := float(_bld_max_hp(String(b["type"])))
		if float(b.get("hp", max_hp)) >= max_hp:
			continue
		var d: float = map.tile_center_px(b["tile"]).distance_to(map.tile_center_px(near["tile"]))
		if d < best_d:
			best_d = d
			best = b
	return best



## Само производство: расход материалов, множители, добавка в КУЧУ у здания.
## Общее для работников у здания и добытчиков у источника. В общий пул ресурс
## попадает только с носильщиком (M6: физическая логистика, ответ №20).
func _produce_tick(r: Dictionary, bld: Dictionary, dt: float) -> void:
	r["state"] = "work"
	r["fatigue"] += dt / float(cfg["day_length"])
	_grow_skill(r, dt)
	var prod: Dictionary = _def(bld)["produce"]
	# расход материалов (мастерская: дерево + камень -> инструменты)
	var portion: float = dt / float(cfg["day_length"])
	var inputs: Dictionary = prod.get("inputs", {})
	for key in inputs:
		if float(res.get(String(key), 0.0)) < float(inputs[key]) * portion:
			r["state"] = "idle"   # материалы кончились — стоит
			return
	for key in inputs:
		res[String(key)] = maxf(0.0, float(res[key]) - float(inputs[key]) * portion)
	var boost: float = blessing_boost()
	var amount: float = float(prod["per_day"]) * portion * boost * production_mult(bld) * work_mult(r)
	_add_pile(bld, String(prod["res"]), amount)
	# шахта даёт и камень вместе с рудой (заказчик)
	if prod.has("res2"):
		var amount2: float = float(prod["per_day2"]) * portion * boost * production_mult(bld) * work_mult(r)
		_add_pile(bld, String(prod["res2"]), amount2)


## Куча у здания (M6): производство копится здесь, пока её не унесёт носильщик.
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


func _arrived(r: Dictionary, tile: Vector2i) -> bool:
	return map.tile_of_px(r["pos"]) == tile


func _move_towards(r: Dictionary, tile: Vector2i, dt: float) -> void:
	r["state"] = "going"
	if r["target"] != tile:
		r["target"] = tile
		r["path"] = map.path_px(r["pos"], tile)
	var path: PackedVector2Array = r["path"]
	if path.is_empty():
		# страховка: замурован на сплошном тайле (стену достроили под ногами)
		var here: Vector2i = map.tile_of_px(r["pos"])
		if not map.is_walkable(here):
			var free := _nearest_walkable(here)
			if not free == Vector2i(-1, -1):
				r["pos"] = map.tile_center_px(free)
				r["target"] = Vector2i(-1, -1)
				return
		r["state"] = "idle"
		return
	var pos: Vector2 = r["pos"]
	var step: float = float(cfg["resident_speed"]) * dt * float(r.get("carry_slow", 1.0))
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


