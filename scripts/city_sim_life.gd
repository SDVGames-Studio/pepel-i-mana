# Часть: сюжеты, доска заказов, погода, законы, вера, отношения, память + запросы для HUD.
# Правки структуры v1.20.2: огромный city_sim.gd разбит на extends-цепочку
# частей; это один класс, разложенный по файлам — поведение не меняется.
extends "res://scripts/city_sim_base.gd"

## --- сюжетная рамка «Пепел и Мана» (M14-L, issue #3 L) ----------------------

## Флаги из сцен: данж-зачистки, визиты в тёмные биомы и т.п.
func story_progress(flag: String, value) -> void:
	story_flags[flag] = value


## Ежедневная проверка триггеров глав. Главы — тосты и летопись; финал
## выбирается состоянием города; песочница продолжается.
func _roll_story() -> void:
	var scfg: Dictionary = _read_json_file(STORY_CFG_PATH)
	if scfg.is_empty():
		return
	var chapters: Array = scfg.get("chapters", [])
	while story_chapter < chapters.size():
		var ch: Dictionary = chapters[story_chapter]
		if not _story_trigger_met(String(ch.get("when", "")), ch, scfg):
			return
		var id := String(ch["id"])
		if id.begins_with("finale"):
			if story_side == "":
				return   # финал придёт, когда город определится
			if id != "finale_" + story_side:
				story_chapter += 1
				continue
		events.append({"type": "story", "id": id})
		_chron("chron.story", "story." + id)
		story_chapter += 1


func _story_trigger_met(when: String, ch: Dictionary, scfg: Dictionary) -> bool:
	match when:
		"start":
			return true
		"residents":
			return residents.size() >= int(ch.get("count", 10))
		"dark":
			return bool(story_flags.get("dark_visit", false)) or bool(necro_known)
		"pollution":
			return pollution >= float(ch.get("count", 30))
		"side":
			var side := String(ch.get("side", "mana"))
			if story_side != "":
				return story_side == side
			# финал выбирается состоянием города
			var mana: Dictionary = scfg.get("side_mana", {})
			var ash: Dictionary = scfg.get("side_ash", {})
			var altar_ok := false
			for b in buildings:
				if String(b["type"]) == "altar" and _active(b):
					altar_ok = true
			if float(res["crystal"]) >= float(mana.get("crystals", 20)) \
					and pollution <= float(mana.get("max_pollution", 30)) and altar_ok:
				story_side = "mana"
				return true
			if pollution >= float(ash.get("pollution", 60)):
				story_side = "ash"
				return true
			return false
	return false


## --- доска объявлений (M14-K, issue #3 K.1) ---------------------------------

func _quests_cfg() -> Dictionary:
	var parsed: Variant = _read_json_file(QUESTS_CFG_PATH)
	return parsed if parsed is Dictionary else {}


## Ежедневно: старые заказы тухнут, доска пополняется до минимума.
func _roll_quests() -> void:
	var qcfg: Dictionary = _quests_cfg()
	var gone: Array = []
	for q in quests:
		q["days"] = int(q["days"]) - 1
		if int(q["days"]) <= 0:
			gone.append(q)
	for q in gone:
		quests.erase(q)
	var attempts := 0
	while quests.size() < int(qcfg.get("per_day_min", 3)) and attempts < 30:
		attempts += 1
		_spawn_quest(qcfg)


func _spawn_quest(qcfg: Dictionary) -> void:
	var adults: Array = _adults()
	if adults.is_empty():
		return
	var customer: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	var roll := _event_rng.randf()
	var q := {"id": _quest_id, "customer": String(customer["name"]),
			"customer_id": int(customer["id"]), "progress": 0, "days": int(qcfg.get("days_active", 3))}
	_quest_id += 1
	if roll < 0.5:
		var bcfg: Dictionary = qcfg.get("bring", {})
		var items: Array = bcfg.get("items", [])
		if items.is_empty():
			return
		q["kind"] = "bring"
		q["item"] = String(items[_event_rng.randi_range(0, items.size() - 1)])
		q["need"] = _event_rng.randi_range(int(bcfg["count"][0]), int(bcfg["count"][1]))
		q["reward"] = _event_rng.randi_range(int(bcfg["reward_coins"][0]), int(bcfg["reward_coins"][1]))
	elif roll < 0.75:
		var hcfg: Dictionary = qcfg.get("hunt", {})
		q["kind"] = "hunt"
		q["need"] = _event_rng.randi_range(int(hcfg["count"][0]), int(hcfg["count"][1]))
		q["reward"] = _event_rng.randi_range(int(hcfg["reward_coins"][0]), int(hcfg["reward_coins"][1]))
	else:
		var bcfg: Dictionary = qcfg.get("build", {})
		var types: Array = bcfg.get("types", [])
		if types.is_empty():
			return
		q["kind"] = "build"
		q["type"] = String(types[_event_rng.randi_range(0, types.size() - 1)])
		q["need"] = 1
		q["reward"] = _event_rng.randi_range(int(bcfg["reward_coins"][0]), int(bcfg["reward_coins"][1]))
	if int(q["reward"]) <= 0:
		return
	quests.append(q)


## Сдать заказ «принести» (панель Q): предметы из рюкзака героя, монеты —
## герою, настроение заказчику. Возвращает "" или ключ ошибки.
func quest_deliver(q_id: int, inventory: Array) -> String:
	var quest: Dictionary = {}
	for q in quests:
		if int(q["id"]) == q_id:
			quest = q
			break
	if quest.is_empty() or String(quest["kind"]) != "bring":
		return "quest.gone"
	if _count_item(inventory, String(quest["item"])) < int(quest["need"]):
		return "quest.no_items"
	_take_item(inventory, String(quest["item"]), int(quest["need"]))
	return _finish_quest(quest)


## Охота героя (город/карта) двигает заказы «добить зверя».
func quest_hunted() -> void:
	for q in quests:
		if String(q["kind"]) == "hunt":
			q["progress"] = int(q["progress"]) + 1
			if int(q["progress"]) >= int(q["need"]):
				_finish_quest(q)
				return


## Достроенное здание двигает заказы «построить».
func quest_built(type_id: String) -> void:
	for q in quests:
		if String(q["kind"]) == "build" and String(q["type"]) == type_id:
			_finish_quest(q)
			return


## Награда: монеты герою (через колбэк города), радость заказчику, летопись.
func _finish_quest(quest: Dictionary) -> String:
	quests.erase(quest)
	if coins_sink != null and coins_sink.is_valid():
		coins_sink.call(int(quest["reward"]))
	for r in residents:
		if int(r["id"]) == int(quest.get("customer_id", -1)):
			r["mood"] = clampf(float(r["mood"]) + 8.0, 0.0, 100.0)
			break
	_chron("chron.quest_done", String(quest["customer"]), str(int(quest["reward"])))
	events.append({"type": "quest_done", "customer": String(quest["customer"]),
			"reward": int(quest["reward"])})
	return ""


## --- погода и сезоны (M14-J) -------------------------------------------------

func _weather_cfg() -> Dictionary:
	var parsed: Variant = _read_json_file(WEATHER_CFG_PATH)
	return parsed if parsed is Dictionary else {}


## Сезон по дню: весна → лето → осень → зима → весна…
func season() -> String:
	var wcfg: Dictionary = _weather_cfg()
	var days := maxi(1, int(wcfg.get("season_days", 12)))
	var seasons: Array = wcfg.get("seasons", ["spring", "summer", "autumn", "winter"])
	return String(seasons[int((day - 1) / days) % seasons.size()])


## Дней до зимы (v1.22): город видит зиму заранее и готовит еду. Зимой
## возвращает дни до СЛЕДУЮЩЕЙ зимы (большое число — готовиться рано).
func days_to_winter() -> int:
	var wcfg: Dictionary = _weather_cfg()
	var per := maxi(1, int(wcfg.get("season_days", 12)))
	var seasons: Array = wcfg.get("seasons", ["spring", "summer", "autumn", "winter"])
	var wi := seasons.find("winter")
	if wi < 0:
		return 999
	var cycle := per * seasons.size()
	var in_cycle := (maxi(1, int(day)) - 1) % cycle
	var left := wi * per - in_cycle
	if left <= 0:
		left += cycle
	return left


## Окно зимней готовности (v1.22): последние дни осени город собирает
## урожай и строит фермы заранее — winter_prep_days из city.json.
func winter_prep_window() -> int:
	return maxi(1, int(cfg.get("farming", {}).get("winter_prep_days", 4)))


## Зима на пороге: сейчас предзимнее окно (не сама зима).
func winter_coming() -> bool:
	return season() != "winter" and days_to_winter() <= winter_prep_window()


## Множитель полей: осень жирнее, зима глухая; дождь поливает, снег глушит.
func crop_mult() -> float:
	var wcfg: Dictionary = _weather_cfg()
	var effects: Dictionary = wcfg.get("effects", {})
	var mult := 1.0
	match season():
		"autumn":
			mult *= float(effects.get("autumn_field_mult", 1.2))
		"winter":
			mult *= float(effects.get("snow_field_mult", 0.3))
	if weather == "rain":
		mult *= float(effects.get("rain_field_mult", 1.1))
	elif weather == "snow":
		mult *= float(effects.get("snow_field_mult", 0.3))
	elif weather == "ash_storm":
		mult *= float(effects.get("ash_orchard_mult", 0.5))
	return mult


## Множитель яблонь: лето жирнее; пепельная буря бьёт по урожаю.
func orchard_mult() -> float:
	var effects: Dictionary = _weather_cfg().get("effects", {})
	var mult := 1.0
	if season() == "summer":
		mult *= float(effects.get("summer_orchard_mult", 1.3))
	if weather == "ash_storm":
		mult *= float(effects.get("ash_orchard_mult", 0.5))
	return mult


## Ежедневный бросок погоды по весам сезона + эффекты дня (M14-J).
func _roll_weather() -> void:
	var wcfg: Dictionary = _weather_cfg()
	var effects: Dictionary = wcfg.get("effects", {})
	var pool: Dictionary = wcfg.get("weather_by_season", {}).get(season(), {"clear": 1})
	var total := 0
	for w in pool:
		total += int(pool[w])
	var roll := _event_rng.randi_range(1, maxi(1, total))
	for w in pool:
		roll -= int(pool[w])
		if roll <= 0:
			weather = String(w)
			break
	# зима: отопление — дрова на жителей; нет дров — город мёрз
	froze_last_night = false
	if season() == "winter":
		var need := float(residents.size()) * float(effects.get("heating_wood_per_resident", 0.15))
		if float(res["wood"]) >= need:
			res["wood"] = float(res["wood"]) - need
		else:
			res["wood"] = 0.0
			froze_last_night = true
	# туман: рейды видят город хуже — следующий налёт откладывается
	if weather == "fog":
		_next_raid_at += float(cfg["day_length"]) * float(effects.get("fog_raid_days", 0.5))


## --- законы и совет (M14-H) -------------------------------------------------

func _laws_cfg() -> Dictionary:
	var parsed: Variant = _read_json_file(LAWS_CFG_PATH)
	return parsed if parsed is Dictionary else {}


func has_law(law_id: String) -> bool:
	return active_laws.has(law_id)


func law_param(law_id: String, key: String, fallback: float) -> float:
	var cfg2: Dictionary = _laws_cfg()
	for l in cfg2.get("laws", []):
		if String(l["id"]) == law_id:
			return float(l.get(key, fallback))
	return fallback


## Совет: староста + лучшие мастера (для голосования и панели).
func council() -> Array:
	var elders: Array = []
	for r in residents:
		if String(r["prof"]) == "elder":
			elders.append(r)
	if elders.is_empty() and not residents.is_empty():
		elders.append(residents[0])
	var rest: Array = []
	for r in _adults():
		if r in elders:
			continue
		rest.append(r)
	rest.sort_custom(func(x, y) -> bool: return float(x.get("skill", 0.0)) > float(y.get("skill", 0.0)))
	var size := int(_laws_cfg().get("council_size", 4))
	return elders + rest.slice(0, maxi(0, size - 1))


## Голосование совета: принять закон или отменить активный.
## Каждый советник голосует «за» с шансом = настроение/100 (недовольные против).
func propose_law(law_id: String) -> Dictionary:
	var cfg2: Dictionary = _laws_cfg()
	var known := false
	for l in cfg2.get("laws", []):
		if String(l["id"]) == law_id:
			known = true
			break
	if not known:
		return {"ok": false, "yes": 0, "no": 0, "err": "law.unknown"}
	var councilors: Array = council()
	if councilors.is_empty():
		return {"ok": false, "yes": 0, "no": 0, "err": "law.no_council"}
	var vote_mood := float(cfg2.get("vote_mood_yes", 60))
	var repealing := active_laws.has(law_id)
	var yes := 0
	var no := 0
	for c in councilors:
		if repealing:
			# отмена: недовольные законом хотят её (тем меньше настроения — тем «за»)
			if _event_rng.randf() < clampf((100.0 - float(c["mood"])) / 100.0, 0.05, 0.95):
				yes += 1
			else:
				no += 1
		elif _event_rng.randf() < clampf(float(c["mood"]) / 100.0, 0.05, 0.95) \
				and float(c["mood"]) >= vote_mood * 0.6:
			yes += 1
		else:
			no += 1
	var ok := yes > no
	if ok:
		if active_laws.has(law_id):
			active_laws.erase(law_id)   # повторное голосование отменяет закон
		else:
			active_laws.append(law_id)
	_chron("chron.law_vote", String(law_id), "%d/%d" % [yes, no])
	events.append({"type": "law_vote", "law": law_id, "ok": ok, "yes": yes, "no": no})
	return {"ok": ok, "yes": yes, "no": no}


## --- вера (M14-H): божество и молитва ---------------------------------------

func _religion_cfg() -> Dictionary:
	var parsed: Variant = _read_json_file(RELIGION_CFG_PATH)
	return parsed if parsed is Dictionary else {}


func god_def() -> Dictionary:
	for g in _religion_cfg().get("gods", []):
		if String(g["id"]) == god:
			return g
	return {}


## Храм построен и при нём служка?
func temple_staffed() -> bool:
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == "temple" and int(b["worker"]) > 0:
			return true
	return false


## Молитва у храма (E, раз в день, нужен служка): избирает божество.
func pray(god_id: String) -> String:
	if day == prayed_day:
		return "god.prayed_today"
	if not temple_staffed():
		return "god.no_temple"
	for g in _religion_cfg().get("gods", []):
		if String(g["id"]) == god_id:
			god = god_id
			prayed_day = day
			_chron("chron.pray", String(g["loc"]))
			events.append({"type": "pray", "god": god_id})
			return ""
	return "god.unknown"


## Балл отношений a→b (и симметрично b→a хранится отдельно, меняются вместе).
func _rel_change(a: Dictionary, b: Dictionary, delta: float) -> void:
	var cap := 100.0
	var lo := -100.0
	for pair in [[a, b], [b, a]]:
		var rel: Dictionary = pair[0].get("rel", {})
		if (rel as Dictionary).is_empty() and delta > 0.0 and not (pair[0] as Dictionary).has("rel"):
			pair[0]["rel"] = {}
		rel = pair[0].get("rel", {})
		var key := str(int(pair[1]["id"]))
		rel[key] = clampf(float(rel.get(key, 0.0)) + delta, lo, cap)


func _rel_score(r: Dictionary, other_id: int) -> float:
	var rel: Dictionary = r.get("rel", {})
	return float(rel.get(str(other_id), 0.0))


## Лучший друг / заклятый враг по карте отношений (для панели и досуга).
func rel_best(r: Dictionary) -> Dictionary:
	var rel: Dictionary = r.get("rel", {})
	var best_id := -1
	var best_score := float(_v3().get("friend_threshold", 50.0))
	for k in rel:
		if float(rel[k]) >= best_score:
			best_score = float(rel[k])
			best_id = int(k)
	if best_id < 0:
		return {}
	var other := _resident_by_id(best_id)
	if other.is_empty():
		return {}
	return {"other": other, "score": best_score}


func rel_worst(r: Dictionary) -> Dictionary:
	var rel: Dictionary = r.get("rel", {})
	var worst_id := -1
	var worst_score := float(_v3().get("foe_threshold", -30.0))
	for k in rel:
		if float(rel[k]) <= worst_score:
			worst_score = float(rel[k])
			worst_id = int(k)
	if worst_id < 0:
		return {}
	var other := _resident_by_id(worst_id)
	if other.is_empty():
		return {}
	return {"other": other, "score": worst_score}


## Память (M14-F): последние N личных событий; вклад в настроение тает со
## временем, но не гаснет до нуля (негаснущий хвост, grief затухает медленно).
func _mem_push(r: Dictionary, key: String) -> void:
	var slots := int(_v3().get("memory_slots", 3))
	var mem: Array = r.get("mem", [])
	mem.append({"k": key, "age": 0.0})
	while mem.size() > slots:
		mem.pop_front()
	r["mem"] = mem


func _memory_mood(r: Dictionary) -> float:
	var v3 := _v3()
	var moods: Dictionary = v3.get("mood_per_event", {})
	var decay_days := maxf(1.0, float(v3.get("memory_decay_days", 10.0)))
	var min_factor := float(v3.get("memory_min_factor", 0.2))
	var total := 0.0
	for m in r.get("mem", []):
		var decay := maxf(min_factor, 1.0 - float(m["age"]) / decay_days)
		total += float(moods.get(String(m["k"]), 0.0)) * decay
	return total


## Ежедневный тик v3: память стареет; отношения от совместной работы;
## друг = лучший балл; новые личные цели.
func _roll_v3() -> void:
	var v3 := _v3()
	var adults: Array = _adults()
	# память стареет
	for r in adults:
		var mem: Array = r.get("mem", [])
		for m in mem:
			m["age"] = float(m["age"]) + 1.0
	# отношения: работа рядом сближает
	var near_tiles := float(v3.get("work_near_tiles", 3))
	var bonus := float(v3.get("work_near_bonus", 1.0))
	for i in adults.size():
		var a: Dictionary = adults[i]
		var bld_a = a.get("bld")
		if bld_a == null or not bool((bld_a as Dictionary).get("done", false)):
			continue
		for j in range(i + 1, adults.size()):
			var b: Dictionary = adults[j]
			var bld_b = b.get("bld")
			if bld_b == null or not bool((bld_b as Dictionary).get("done", false)):
				continue
			if Vector2(bld_a["tile"]).distance_to(Vector2(bld_b["tile"])) <= near_tiles:
				_rel_change(a, b, bonus)
	# друг = лучший балл отношений (используется вечерним досугом M12)
	var friend_at := float(v3.get("friend_threshold", 50.0))
	for r in adults:
		var rel: Dictionary = r.get("rel", {})
		var best_id := -1
		var best_score := friend_at
		for k in rel:
			if float(rel[k]) >= best_score:
				best_score = float(rel[k])
				best_id = int(k)
		r["friend"] = best_id
	# вечерняя попойка в таверне забыта до следующего вечера
	for r in residents:
		r["tavern_visited"] = false
	_roll_goals()


## Новая личная цель свободному взрослому; выполненная — награда и новая.
func _roll_goals() -> void:
	var v3 := _v3()
	var pool: Array = people.get("goals", [])
	if pool.is_empty():
		return
	for r in _adults():
		var goal := String(r.get("goal", ""))
		if goal == "":
			_assign_goal(r, pool)
			continue
		var done := false
		match goal:
			"become_master":
				done = int(r.get("rank", 0)) >= 5
			"feast_tavern":
				done = bool(r.get("tavern_visited", false))
			"store_food":
				var need := float(_adults().size()) * float(cfg.get("food_per_resident_day", 2.0)) \
						* float(v3.get("goal_food_days", 7))
				done = float(res["food"]) >= need
			"build_garden":
				pass   # завершается постройкой сада/статуи (см. _complete_site)
		if done:
			_complete_goal(r, pool)


func _assign_goal(r: Dictionary, pool: Array) -> void:
	for attempt in 6:
		var pick: Dictionary = pool[_event_rng.randi_range(0, pool.size() - 1)]
		var gid := String(pick["id"])
		if gid == String(r.get("goal_prev", "")) and attempt < 5:
			continue
		r["goal"] = gid
		return


## Цель достигнута: настроение, летопись, память — и новая цель.
func _complete_goal(r: Dictionary, pool: Array) -> void:
	var goal := String(r.get("goal", ""))
	if goal == "":
		return
	r["goal_prev"] = goal
	r["goal"] = ""
	r["mood"] = clampf(float(r["mood"]) + float(_v3().get("goal_mood", 6.0)), 0.0, 100.0)
	_mem_push(r, "goal")
	_chron("chron.goal_done", String(r["name"]), "goal." + goal)
	events.append({"type": "goal_done", "name": String(r["name"]), "goal": goal})
	_assign_goal(r, pool)


## Достигнуть цель «построить сад» у строителя (декор готов, M14-F).
func _goal_garden_built(worker_id: int) -> void:
	var r := _resident_by_id(worker_id)
	if not r.is_empty() and String(r.get("goal", "")) == "build_garden":
		_complete_goal(r, people.get("goals", []))


func _start_mood(traits: Array) -> float:
	var mood: float = float(people.get("mood_base", 50.0))
	for t_id in traits:
		var td: Dictionary = _trait_map.get(String(t_id), {})
		mood += float(td.get("mood", 0.0))
	return clampf(mood, 0.0, 100.0)


## 1-2 случайные черты по весам, без повторов.
func _random_traits() -> Array:
	var tmin := int(people.get("traits_per_resident_min", 1))
	var tmax := int(people.get("traits_per_resident_max", 2))
	var tdefs: Array = people.get("traits", [])
	var picked := {}
	var out: Array = []
	for i in _event_rng.randi_range(tmin, maxi(tmin, tmax)):
		var total := 0
		for td: Dictionary in tdefs:
			if not picked.has(String(td["id"])):
				total += int(td.get("weight", 1))
		var roll := _event_rng.randi_range(1, maxi(1, total))
		for td: Dictionary in tdefs:
			if picked.has(String(td["id"])):
				continue
			roll -= int(td.get("weight", 1))
			if roll <= 0:
				picked[String(td["id"])] = true
				out.append(String(td["id"]))
				break
	return out


func _read_json_file(path: String) -> Variant:
	# v1.21.4: без кэша погода/законы/вера читались с диска и парсились по
	# 3–5 раз на жителя в кадре из _mood_target — главный убийца FPS к 70-му дню.
	# res:// в сессии неизменен, кэшируем навсегда.
	if _json_cache.has(path):
		return _json_cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	_json_cache[path] = parsed
	return parsed


# --- запросы для HUD и тестов -------------------------------------------

func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if int(res.get(key, 0)) < int(cost[key]):
			return false
	return true


func storage_cap() -> int:
	var extra := 0
	for b in buildings:
		if _active(b) and _def(b).get("effect", "") == "storage":
			extra += int(cfg["storage_per_warehouse"])
	return int(cfg["storage_base"]) + extra


func pop_cap() -> int:
	# один дом — один человек (правки v1.20): пара с детьми живёт в одном
	# доме и освобождает второй — деревня растёт, строя новые дома.
	# Голем-староста — не житель: своего слота в лимите не занимает,
	# но в residents.size() он есть — компенсируем, чтобы рост не вставал.
	var houses := 0
	for b in buildings:
		if _active(b) and _def(b).get("effect", "") == "pop":
			houses += 1
	var golems := 0
	for r in residents:
		if _is_golem(r):
			golems += 1
	# жёсткий потолок населения (v1.21.5, просьба заказчика): 0 = без потолка
	var cap := base_pop + houses * int(cfg["pop_per_house"]) + golems
	var hard := int(cfg.get("pop_max", 0))
	return mini(cap, hard) if hard > 0 else cap


func is_night() -> bool:
	var t := fmod(time, float(cfg["day_length"]))
	return t >= float(cfg["day_length"]) * (1.0 - float(cfg["night_fraction"]))


func day_number() -> int:
	return day


## Быстрая перемотка на n дней (M8): герой в пути — город живёт (ежедневные
## броски, еда, угрозы, стройка). Шаг по четверти дня — устойчиво для боёв.
func advance_days(n: int) -> void:
	var was_paused := paused
	paused = false
	var step := float(cfg["day_length"]) / 4.0
	for i in n * 4:
		tick(step)
	paused = was_paused


## Событие в летопись из внешней симуляции (карта мира пишет свои истории, M8).
func chronicle_add(key: String, a: String = "", b: String = "") -> void:
	_chron(key, a, b)


## Благословение алтаря: есть готовый алтарь с работающим магом-учеником.
func has_blessing() -> bool:
	return altar_ready()


## Алтарь готов и на нём работает маг-ученик (крафт, зачарование, городские заклинания).
func altar_ready() -> bool:
	for b in buildings:
		if _active(b) and _def(b).get("effect", "") == "altar" and int(b["worker"]) > 0:
			return true
	return false


## На алтаре зачарование «Мана» (больше запас и быстрее регенерация у героя).
func altar_enchanted() -> bool:
	for b in buildings:
		if _active(b) and String(b["type"]) == "altar" and String(b.get("enchant", "")) == "mana":
			return true
	return false


## Полоса загрязнения: clean / mild / heart / wild (для HUD и множителя).
func pollution_band() -> String:
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	if pollution >= float(pol_cfg.get("band_wild", 85.0)):
		return "wild"
	if pollution >= float(pol_cfg.get("band_heart", 60.0)):
		return "heart"
	if pollution >= float(pol_cfg.get("band_mild", 30.0)):
		return "mild"
	return "clean"


## Множитель производства от загрязнения («магическое сердце» — ответ №64),
## дикого резонанса, зачарования здания, планировки (склад рядом — M6)
## и дисциплин (M7: «Земледелие» — еде, «Тайное» — всем).
func production_mult(bld: Dictionary) -> float:
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	var mult := 1.0
	var band := pollution_band()
	if band == "heart":
		mult *= float(pol_cfg.get("prod_heart", 1.15))
	elif band == "mild":
		mult *= float(pol_cfg.get("prod_mild", 1.05))
	if resonance_left > 0.0:
		mult *= resonance_mult
	mult *= float(bld.get("ench_mult", 1.0))
	mult *= layout_mult(bld)
	mult *= research_mult("prod_all", 1.0)
	if not bld.is_empty() and bld.has("type") \
			and String(_def(bld).get("produce", {}).get("res", "")) == "food":
		mult *= research_mult("food_prod", 1.0)
	# законы (M14-H): налоги ускоряют, военное положение замедляет
	if has_law("taxes"):
		mult *= float(law_param("taxes", "production_mult", 1.0))
	if has_law("martial_law"):
		mult *= float(law_param("martial_law", "production_mult", 1.0))
	return mult


## Бонус планировки (M6): склад рядом со зданием ускоряет производство
## («склад рядом с фермами = +скорость», пункт плана M6).
func layout_mult(bld: Dictionary) -> float:
	if bld.is_empty() or not bld.has("type") or not _def(bld).has("produce"):
		return 1.0
	var lcfg: Dictionary = cfg.get("layout", {})
	if lcfg.is_empty():
		return 1.0
	var radius := float(lcfg.get("warehouse_radius", 4))
	var best := 1.0
	for b in buildings:
		if not _active(b) or _def(b).get("effect", "") != "storage":
			continue
		if Vector2(b["tile"]).distance_to(Vector2(bld["tile"])) <= radius:
			best = maxf(best, float(lcfg.get("warehouse_mult", 1.25)))
	return best


## Комфорт от готового декора (сад, статуя — ответ №18) с потолком.
func decor_mood() -> float:
	var total := 0.0
	for b in buildings:
		if _active(b) and _def(b).get("effect", "") == "decor":
			total += float(_def(b).get("mood", 0.0))
	return minf(total, float(cfg.get("decor_mood_max", 20.0)))


## Прибавить загрязнение (дикая магия в данже тоже — город в том же регионе).
func add_pollution(amount: float) -> void:
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	pollution = clampf(pollution + amount, 0.0, float(pol_cfg.get("max", 100.0)))


## Каст городского заклинания (M3). def — строка data/magic.json.
## Возвращает "" при успехе или ключ ошибки локализации ("magic." + ключ).
func cast_city_spell(def: Dictionary) -> String:
	if not altar_ready():
		return "no_altar"
	var spell_id := String(def["id"])
	if float(_spell_ready.get(spell_id, 0.0)) > time:
		return "cooldown"
	var cost := int(def.get("crystals_cost", 0))
	if int(res["crystal"]) < cost:
		return "no_crystals"
	res["crystal"] = float(res["crystal"]) - float(cost)
	_spell_ready[spell_id] = time + float(def.get("cooldown", 0.0))
	var params: Dictionary = def.get("params", {})
	match spell_id:
		"wild_resonance":
			resonance_left = float(params.get("duration", 120.0))
			resonance_mult = float(params.get("prod_mult", 1.5))
			add_pollution(float(def.get("pollution", 0.0)) * _magic_pollution_mult())
		"cleanse":
			pollution = maxf(0.0, pollution - float(params.get("amount", 25.0)))
		"forest_gift":
			_add_resource_capped("food", float(params.get("food", 15.0)))
			add_pollution(float(def.get("pollution", 0.0)) * _magic_pollution_mult())
		"meteor_shard":
			_add_resource_capped("stone", float(params.get("stone", 30.0)))
			add_pollution(float(def.get("pollution", 0.0)) * _magic_pollution_mult())
		"bless":
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(params.get("mood", 12.0)), 0.0, 100.0)
		"harvest_blessing":
			_add_resource_capped("food", float(params.get("food", 25.0)))
			add_pollution(float(def.get("pollution", 0.0)) * _magic_pollution_mult())
	return ""


## Добавить ресурс с ограничением хранилища, но БЕЗ уменьшения запаса:
## если его больше капа (тест-режим, излишки) — просто ничего не добавляем.
func _add_resource_capped(key: String, amount: float) -> void:
	var cap := float(storage_cap())
	if float(res[key]) >= cap:
		return
	res[key] = minf(cap, float(res[key]) + amount)


## Зачаровать готовое здание (ответ №60): руна из рюкзака + кристаллы из пула.
## def — строка "enchantments" из data/magic.json. Возвращает "" или ключ ошибки.
func enchant_building(bld: Dictionary, def: Dictionary, inventory: Array) -> String:
	if bld.is_empty() or not _active(bld):
		return "enchant_not_done"
	var target := String(def.get("target", "any"))
	if target != "any" and String(bld["type"]) != target:
		return "enchant_wrong"
	var cost := int(def.get("crystals", 1))
	if int(res["crystal"]) < cost:
		return "no_crystals"
	var rune := String(def["rune"])
	if _count_item(inventory, rune) < 1:
		return "no_rune"
	res["crystal"] = float(res["crystal"]) - float(cost)
	_take_item(inventory, rune, 1)
	bld["enchant"] = String(def["id"])
	bld["ench_mult"] = float(def.get("prod_mult", 1.0))
	return ""


## Руной «Мана» алтарь усиливает ману героя (параметры из city.json -> "hero_mana").
func hero_mana_params() -> Dictionary:
	var mana_cfg: Dictionary = cfg.get("hero_mana", {})
	var regen: float = float(mana_cfg.get("regen_period", 8.0))
	if altar_enchanted():
		regen = float(mana_cfg.get("altar_regen_period", 5.0))
	# этап 2, аспект 6: магическая зона и магический квартал усиливают алтарь
	regen /= _altar_work_mult()
	# дисциплина «Тайное» (M7): регенерация маны героя быстрее
	regen *= research_mult("mana_regen_mult", 1.0)
	var cap_extra := int(mana_cfg.get("altar_cap_extra", 4)) if altar_enchanted() else 0
	# благословение «Маны» (M14-H): +запас маны, пока божество избрано
	if god == "mana":
		cap_extra += int(god_def().get("value", 0))
	return {"cap_extra": cap_extra, "regen_period": regen}


