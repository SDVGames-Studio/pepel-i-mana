# Часть: староста/голем, утренняя планёрка, события-истории.
# Правки структуры v1.20.2: огромный city_sim.gd разбит на extends-цепочку
# частей; это один класс, разложенный по файлам — поведение не меняется.
extends "res://scripts/city_sim_trade.gd"

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


# --- утренняя планёрка старосты (правки v1.20) --------------------------------
## Белый голем-староста каждое утро: определяет требуемые здания (самострой),
## собирает жителей на площади и распределяет их по цветам и приоритетам:
## 1) профильные цвета (при конкуренции — самый компетентный, тай-брейк по id);
## 2) жизненно важные объекты (еда/ресурсы/стройка) — жители без нужного цвета;
## 3) остаток — вторичные задачи, резерв или дополнительные цвета со штрафом.
## Незакрытое жизненно важное — явный дефицит с предложением решения.
## План возвращается структурой, пишется в летопись и отладочный лог.

## Рабочие места утра: {bld, need, vital, is_site}.
func _work_spots() -> Array:
	var out: Array = []
	for b in buildings:
		if not bool(b["done"]):
			out.append({"bld": b, "need": "builder", "vital": true, "is_site": true})
			continue
		if not _active(b) or not _def(b).has("worker"):
			continue
		var need := String(_def(b)["worker"])
		var vital := String(b["type"]) in ["farm", "pier", "sawmill", "quarry", "mine"]
		out.append({"bld": b, "need": need, "vital": vital, "is_site": false})
	return out


func _spot_name(spot: Dictionary) -> String:
	return String(spot["bld"]["type"])


## Снять все рабочие назначения (утро — новый план).
func _reset_assignments() -> void:
	_workers_ver += 1   # v1.26: кэш таверны устарел
	for r in residents:
		if r["bld"] != null:
			(r["bld"] as Dictionary)["worker"] = -1
		if r["site"] != null:
			(r["site"] as Dictionary)["worker"] = -1
		r["bld"] = null
		r["site"] = null
		r["sub_prof"] = ""
	for b in buildings:
		if int(b["worker"]) > 0 and not _taken_by(b):
			b["worker"] = -1


func _taken_by(b: Dictionary) -> bool:
	for r in residents:
		if r["bld"] == b or r["site"] == b:
			return true
	return false


## Назначить жителя на место (одно назначение на жителя).
func _assign_spot(r: Dictionary, spot: Dictionary, note: String) -> void:
	_workers_ver += 1   # v1.26: кэш таверны устарел
	if r["bld"] != null and r["bld"] != spot["bld"]:
		(r["bld"] as Dictionary)["worker"] = -1
	if r["site"] != null and r["site"] != spot["bld"]:
		(r["site"] as Dictionary)["worker"] = -1
	spot["bld"]["worker"] = int(r["id"])
	if spot["is_site"]:
		r["site"] = spot["bld"]
		r["bld"] = null
	else:
		r["bld"] = spot["bld"]
		r["site"] = null
	var need := String(spot["need"])
	if need != String(r["prof"]) and not _is_golem(r) \
			and not (r.get("prof_extra", []) as Array).has(need):
		# работа не по цвету: цвет «учится» на месте (много цветов — штраф КПД)
		(r["prof_extra"] as Array).append(need)
		_chron("chron.learned", String(r["name"]), need)
	r["sub_prof"] = ""


## Утренний план: распределение жителей по приоритетам. Вызывается раз в день
## (и после загрузки сейва — утренний тик). Возвращает структуру плана.
func morning_plan() -> Dictionary:
	_reset_assignments()
	var spots := _work_spots()
	var plan := {
		"day": day,
		"profile": [], "vital": [], "rest": [], "extra": [],
		"deficits": [], "conflicts": [], "reserve": [],
	}
	var taken := {}
	for r in residents:
		if String(r.get("ail", "")) != "" or String(r["prof"]) == "":
			taken[int(r["id"])] = true   # больные и дети в раздаче не участвуют

	# 1) профильные назначения: цвет места = основная специальность жителя;
	# конкуренция за место — берёт самый компетентный (тай-брейк — меньший id)
	for spot in spots:
		var cands := _plan_candidates(String(spot["need"]), taken, true)
		if cands.is_empty():
			continue
		var winner: Dictionary = cands[0]
		_assign_spot(winner, spot, "profile")
		taken[int(winner["id"])] = true
		var entry := {"bld": _spot_name(spot), "who": String(winner["name"])}
		if cands.size() > 1:
			entry["why"] = "%s > %s" % [String(winner["name"]), String(cands[1]["name"])]
			plan["conflicts"].append({
				"bld": _spot_name(spot), "chosen": String(winner["name"]),
				"why": "competence:%.1f" % float(winner.get("skill", 0.0))})
		plan["profile"].append(entry)
		if bool(spot["vital"]):
			plan["vital"].append({"bld": _spot_name(spot), "who": String(winner["name"]), "color": "primary"})

	# 2) жизненно важные объекты без работника: еда / ресурсы / стройка —
	# любой свободный житель (лучше — с дополнительным цветом места);
	# самый последний резерв — голем-староста без цветового бонуса
	for spot in spots:
		if not bool(spot["vital"]) or int(spot["bld"]["worker"]) > 0:
			continue
		var cands := _plan_candidates(String(spot["need"]), taken, false)
		var winner: Dictionary = {}
		if cands.is_empty():
			for r in residents:
				if _is_golem(r) and not taken.has(int(r["id"])) \
						and String(r.get("ail", "")) == "":
					winner = r
					break
			if winner.is_empty():
				continue
		else:
			winner = cands[0]
		var via_extra: bool = not _is_golem(winner) \
				and (winner.get("prof_extra", []) as Array).has(String(spot["need"]))
		_assign_spot(winner, spot, "vital")
		taken[int(winner["id"])] = true
		plan["vital"].append({"bld": _spot_name(spot), "who": String(winner["name"]),
				"color": ("golem" if _is_golem(winner) else
						("extra" if via_extra else "none"))})
		if via_extra:
			plan["extra"].append({"who": String(winner["name"]), "color": String(spot["need"]),
					"penalty": color_work_mult(winner, String(spot["need"]))})
		elif String(winner["prof"]) != String(spot["need"]) and not _is_golem(winner):
			(winner["prof_extra"] as Array).append(String(spot["need"]))
			plan["extra"].append({"who": String(winner["name"]), "color": String(spot["need"]),
					"penalty": color_work_mult(winner, String(spot["need"]))})

	# 3) остаток: вторичные производства — свободные жители (доп. цвета со штрафом)
	for spot in spots:
		if int(spot["bld"]["worker"]) > 0:
			continue
		var cands := _plan_candidates(String(spot["need"]), taken, false)
		if cands.is_empty():
			continue
		var winner: Dictionary = cands[0]
		var via_extra: bool = (winner.get("prof_extra", []) as Array).has(String(spot["need"]))
		_assign_spot(winner, spot, "rest")
		taken[int(winner["id"])] = true
		plan["rest"].append({"bld": _spot_name(spot), "who": String(winner["name"])})
		if String(winner["prof"]) != String(spot["need"]):
			plan["extra"].append({"who": String(winner["name"]), "color": String(spot["need"]),
					"penalty": color_work_mult(winner, String(spot["need"]))})

	# 4) контроль дефицита: незакрытое жизненно важное — предложить решение:
	# снять жителя с менее важного производства или доп. цвет со штрафом
	for spot in spots:
		if not bool(spot["vital"]) or int(spot["bld"]["worker"]) > 0:
			continue
		var donor := _deficit_donor(spot, taken)
		if donor.is_empty():
			plan["deficits"].append({"bld": _spot_name(spot),
					"note": "нет работника — построить/подождать беженца"})
			continue
		var freed_bld: Dictionary = donor["bld"] if donor["bld"] != null else donor["site"]
		_assign_spot(donor, spot, "deficit")
		plan["vital"].append({"bld": _spot_name(spot), "who": String(donor["name"]),
				"color": "swap"})
		plan["deficits"].append({"bld": _spot_name(spot),
				"note": "снят %s с «%s»" % [String(donor["name"]), String(freed_bld["type"])]})

	# резерв: кому не нашлось места (староста-голем, больные и дети не в счёте)
	for r in residents:
		if taken.has(int(r["id"])) or r["bld"] != null or r["site"] != null:
			continue
		if String(r["prof"]) != "" and not _is_golem(r):
			plan["reserve"].append(String(r["name"]))

	# планёрка на площади: свободные взрослые собираются ненадолго
	var meet_len := float(cfg.get("plaza", {}).get("meeting_len", 0.06))
	var tiles := plaza_gather_tiles()
	var i := 0
	for r in residents:
		if String(r["prof"]) == "" or _is_golem(r) or String(r.get("ail", "")) != "":
			continue
		r["meeting_until"] = time + float(cfg["day_length"]) * meet_len
		if not tiles.is_empty():
			r["meeting_tile"] = tiles[i % tiles.size()]
			i += 1

	# v1.22: зимняя готовность — на пороге зимы староста каждый день держит
	# в плане запасы еды (город сам собирает спелое и достраивает фермы —
	# ограничений на запас нет, «пусть добывают сколько могут»)
	if winter_coming():
		plan["winter"] = {"days": days_to_winter(),
				"food_per_res": food_per_resident()}
		if not _winter_announced:
			_winter_announced = true
			events.append({"type": "winter_soon", "days": days_to_winter()})
			_chron("chron.winter_soon", str(days_to_winter()))
	elif season() == "spring":
		_winter_announced = false

	day_plans.append(plan)
	if day_plans.size() > 7:
		day_plans.pop_front()
	_chron("chron.morning_plan", str(day),
			str(plan["profile"].size() + plan["vital"].size() + plan["rest"].size()))
	events.append({"type": "morning_plan", "day": day})
	_log_line(_plan_text(plan))
	return plan


## Кандидаты на место: primary_only — только основной цвет; сортировка:
## компетентность (skill) по убыванию, стабильный тай-брейк — меньший id.
func _plan_candidates(need: String, taken: Dictionary, primary_only: bool) -> Array:
	var out: Array = []
	for r in residents:
		if taken.has(int(r["id"])) or String(r.get("ail", "")) != "":
			continue
		if String(r["prof"]) == "":
			continue   # дети не работают
		if primary_only:
			if String(r["prof"]) != need:
				continue
		else:
			if _is_golem(r):
				continue   # голем — последний резерв, не цветная замена
			if String(r["prof"]) == need:
				continue   # уже разобраны профильным шагом (или заняты)
		out.append(r)
	out.sort_custom(func(a, b) -> bool:
		var sa := float(a.get("skill", 0.0))
		var sb := float(b.get("skill", 0.0))
		if sa != sb:
			return sa > sb
		return int(a["id"]) < int(b["id"]))
	return out


## Донор для дефицита: житель с менее важного производства, чей цвет (или доп.
## цвет) подходит под незакрытое жизненно важное место.
func _deficit_donor(spot: Dictionary, taken: Dictionary) -> Dictionary:
	var need := String(spot["need"])
	var best: Dictionary = {}
	var best_score := -1
	for r in residents:
		if taken.has(int(r["id"])) or String(r.get("ail", "")) != "" or String(r["prof"]) == "":
			continue
		var cur: Dictionary = r["bld"] if r["bld"] != null else r["site"]
		if cur.is_empty():
			continue   # свободных уже нет — только снимать с работы
		var sdef: Dictionary = {}
		for s in _work_spots():
			if s["bld"] == cur:
				sdef = s
				break
		if sdef.is_empty() or bool(sdef["vital"]):
			continue   # не снимаем с жизненно важного
		var score := 2 if String(r["prof"]) == need \
				else (1 if (r.get("prof_extra", []) as Array).has(need) else 0)
		if score > best_score:
			best_score = score
			best = r
	if best.is_empty() or best_score <= 0:
		if best.is_empty():
			return {}
		# никто с подходящим цветом — всё же снять самого бесполезного
		return best
	return best


## План одной строкой (для лога и отладки).
func _plan_text(plan: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("=== День %d: утренний план старосты ===" % int(plan["day"]))
	parts.append("Профильные: " + _plan_names(plan["profile"]))
	parts.append("Жизненно важные: " + _plan_names(plan["vital"]))
	parts.append("Остаток: " + _plan_names(plan["rest"]))
	var extras: Array = plan["extra"]
	if extras.is_empty():
		parts.append("Доп. цвета: не использованы")
	else:
		var lines := PackedStringArray()
		for e in extras:
			lines.append("%s→%s(×%.2f)" % [String(e["who"]), String(e["color"]), float(e["penalty"])])
		parts.append("Доп. цвета: " + ", ".join(lines))
	if (plan["deficits"] as Array).is_empty():
		parts.append("Дефицитов нет")
	else:
		var lines := PackedStringArray()
		for d in plan["deficits"]:
			lines.append("%s: %s" % [String(d["bld"]), String(d["note"])])
		parts.append("Дефициты: " + "; ".join(lines))
	if (plan["conflicts"] as Array).size() > 0:
		var lines := PackedStringArray()
		for c in plan["conflicts"]:
			lines.append("%s→%s (%s)" % [String(c["bld"]), String(c["chosen"]), String(c["why"])])
		parts.append("Конфликты: " + ", ".join(lines))
	var reserve: Array = plan["reserve"]
	parts.append("Резерв: " + (", ".join(reserve) if not reserve.is_empty() else "—"))
	if plan.has("winter"):
		var w: Dictionary = plan["winter"]
		parts.append("ЗИМА ЧЕРЕЗ %d ДНЕЙ: еды %s на жителя — собрать спелое, фермы вперёд"
				% [int(w["days"]), "%.1f" % float(w["food_per_res"])])
	return "\n".join(parts)


func _plan_names(entries: Array) -> String:
	if entries.is_empty():
		return "—"
	var lines := PackedStringArray()
	for e in entries:
		lines.append("%s→%s" % [String(e.get("who", "?")), String(e.get("bld", "?"))])
	return ", ".join(lines)


## Строка в отладочный лог (user://city_debug.log) — «логи исправления»:
## планы, застрявания, ключевые события города.
func _log_line(text: String) -> void:
	thought_log.append({"t": day + fmod(time, float(cfg["day_length"])) / float(cfg["day_length"]),
			"name": "", "text": text})
	if thought_log.size() > 600:
		thought_log.pop_front()
	if _log_file == null:
		_log_file = FileAccess.open("user://city_debug.log", FileAccess.READ_WRITE \
				if FileAccess.file_exists("user://city_debug.log") else FileAccess.WRITE_READ)
		if _log_file != null:
			_log_file.seek_end()
	if _log_file != null:
		_log_file.store_line(text)
		_log_file.flush()


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


## Еда на одного жителя (v1.22): планёрка видит запас на пороге зимы.
func food_per_resident() -> float:
	return float(res.get("food", 0.0)) / maxf(1.0, float(residents.size()))


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


func _autobuild_site_exists(type_id: String) -> bool:
	for b in buildings:
		if not bool(b["done"]) and String(b["type"]) == type_id:
			return true
	return false


## Тайл под самострой: добытчики — у своего ресурса (заказчик), следующие —
## максимально близко к своему типу/ветке (районы, v1.21.1), иначе — по
## районам от центра (жилые к западу, производственные к востоку).
## Правки v1.21: лесопилка ставится где угодно; шахта — у жил/выработанного
## массива (ставится рядом, не на тайл).
func _find_autobuild_tile(type_id: String) -> Vector2i:
	var place := ""
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			place = String(d.get("place", ""))
			break
	if place == "veins" or place == "ore":
		var vein_t := _find_gather_tile(type_id, [map.TILE_ORE, map.TILE_DEADROCK], false)
		if not vein_t == Vector2i(-1, -1):
			return vein_t
	if place == "rock":
		var rock_t := _find_gather_tile(type_id, [map.TILE_ROCK, map.TILE_ORE], false)
		if not rock_t == Vector2i(-1, -1):
			return rock_t
	if type_id == "sawmill":
		# v1.21: правило «только у леса» снято (заказчик: ставится где угодно),
		# но САМОСТРОЙ ищет место с деревьями в радиусе сбора — иначе лесоруб
		# останется без работы и город без досок
		var forest_t := _find_tile_near_nature("sawmill", [map.TILE_TREE],
				float(cfg.get("gather_range", 6)))
		if not forest_t == Vector2i(-1, -1):
			return forest_t
	# районы (v1.21.1): якорь — ближайшее к центру готовое здание того же
	# типа (затем — той же цветовой ветки); место ищем кольцами от якоря
	var anchor := _district_anchor(type_id)
	if anchor != Vector2i(-1, -1):
		var cluster_t := _tile_near_cluster(type_id, anchor)
		if not cluster_t == Vector2i(-1, -1):
			return cluster_t
	var district := "work"
	for d in cfg["buildings"]:
		if String(d["id"]) == type_id:
			district = String(d.get("district", "work"))
			break
	var center: Vector2i = map.spawn_tile
	if district == "living":
		center += Vector2i(-4, 0)
	else:
		center += Vector2i(4, 0)
	var tile := _ring_buildable(center, 4, type_id)
	if not tile == Vector2i(-1, -1):
		return tile
	return _ring_buildable(map.spawn_tile, 8, type_id)


## Ближайший к центру города билдабл-тайл рядом с природой заданных видов
## (радиус от прямоугольника здания). Для самостроя добытчиков (v1.21).
func _find_tile_near_nature(type_id: String, kinds: Array, radius: float,
		sync := false) -> Vector2i:
	# v1.28.1: кэш + возобновляемый скан — продвижение каждый тик
	# (_advance_gather_scans_all), sync=true — до конца за один вызов.
	var key := "nat:" + type_id
	var c: Dictionary = _gather_cache.get(key, {})
	if c.is_empty() or int(c.get("ver", -1)) != int(map.grid_ver) \
			or radius != float(c.get("radius", radius)):
		c = {"ver": int(map.grid_ver), "best": Vector2i(-1, -1), "best_d": INF,
				"y": 0, "x": 0, "done": false, "type_id": type_id,
				"kinds": kinds, "on_res": false, "nature": true, "radius": radius}
		_gather_cache[key] = c
	if bool(c["done"]):
		# ревалидация: место могло застроиться или лес вокруг вырубили
		var fb: Vector2i = c["best"]
		var valid := fb != Vector2i(-1, -1) and is_buildable_rect(type_id, fb) \
				and placement_gap_ok(type_id, fb) \
				and placement_block(type_id, fb) == "" \
				and _nature_near_rect(type_id, fb, kinds, radius) != Vector2i(-1, -1)
		if not valid:
			c["done"] = false
			c["best"] = Vector2i(-1, -1)
			c["best_d"] = INF
			c["y"] = 0
			c["x"] = 0
	if not bool(c["done"]) and sync:
		_advance_gather_scan(c, 1 << 30)
	return c["best"]


## Якорь района (v1.21.1): ближайшее к центру города ГОТОВОЕ здание того же
## типа («дом к дому»); своего типа нет — ближайшее здание той же цветовой
## ветки. Пусто — района ещё нет ({} нет и тайла: Vector2i(-1,-1)).
func _district_anchor(type_id: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var cat := _cat_of(type_id)
	for pass_n in 2:   # 0 — тот же тип, 1 — та же цветовая ветка
		for b in buildings:
			if not _active(b):
				continue
			var ok := false
			if pass_n == 0:
				ok = String(b["type"]) == type_id
			else:
				ok = cat != "" and _cat_of(String(b["type"])) == cat
			if not ok:
				continue
			var d: float = Vector2(b["tile"]).distance_to(Vector2(map.spawn_tile))
			if d < best_d:
				best_d = d
				best = b["tile"]
		if best != Vector2i(-1, -1):
			return best
	return best


## Место у кластера (v1.21.1): кольцами от якоря, ближайшее годное
## (все правила размещения, включая зазоры и поля ферм).
func _tile_near_cluster(type_id: String, anchor: Vector2i) -> Vector2i:
	var radius := int(cfg.get("district", {}).get("search", 6))
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue   # только кольцо радиуса r — ближе сперва сами здания
				var t: Vector2i = anchor + Vector2i(dx, dy)
				if not is_buildable_rect(type_id, t):
					continue
				if placement_block(type_id, t) != "":
					continue
				if not placement_gap_ok(type_id, t):
					continue
				return t
	return Vector2i(-1, -1)


## Ближайший к центру города тайл рядом с ресурсом, куда можно поставить здание.
## on_resource — здание ставится прямо на тайл (шахта на руде).
var _gather_cache := {}   # type_id -> состояние возобновляемого скана (v1.28.1)

## Бюджет тайлов на один тик: полный скан размазывается по тикам, фриза нет.
## sync=true — пройти до конца за один вызов (автотесты).
const GATHER_SCAN_BUDGET := 400


## Поиск места у ресурса: скан идёт по тикам (продвижение — каждый тик),
## sync=true — до конца за один вызов (автотесты).
func _find_gather_tile(type_id: String, kinds: Array, on_resource: bool,
		sync := false) -> Vector2i:
	var c := _gather_scan_entry(type_id, kinds, on_resource,
			GATHER_SCAN_BUDGET if not sync else 1 << 30)
	if not bool(c["done"]) and sync:
		_advance_gather_scan(c, 1 << 30)
	return c["best"]


func _gather_scan_entry(type_id: String, kinds: Array, on_resource: bool,
		budget: int) -> Dictionary:
	var ver := int(map.grid_ver)
	var c: Dictionary = _gather_cache.get(type_id, {})
	if c.is_empty() or int(c.get("ver", -1)) != ver:
		c = {"ver": ver, "best": Vector2i(-1, -1), "best_d": INF,
				"y": 0, "x": 0, "done": false, "type_id": type_id,
				"kinds": kinds, "on_res": on_resource}
		_gather_cache[type_id] = c
	if bool(c["done"]):
		# скан завершён: быстрое ревалидирование найденного места
		var fb: Vector2i = c["best"]
		var valid := fb != Vector2i(-1, -1) and is_buildable_rect(type_id, fb) \
				and placement_block(type_id, fb) == "" and placement_gap_ok(type_id, fb)
		if not valid:
			# место заняли/испортили — скан заново (догонит за пару тиков)
			c["done"] = false
			c["best"] = Vector2i(-1, -1)
			c["best_d"] = INF
			c["y"] = 0
			c["x"] = 0
	return c


func _advance_gather_scan(c: Dictionary, budget: int) -> void:
	if bool(c["done"]):
		return
	var type_id: String = c["type_id"]
	var kinds: Array = c["kinds"]
	var on_resource: bool = c["on_res"]
	var best: Vector2i = c["best"]
	var best_d: float = c["best_d"]
	var w := bld_w_of_type(type_id)
	var others: Array = []
	for b in buildings:
		others.append({"r": Rect2i(Vector2i(b["tile"]), Vector2i(bld_w(b), bld_w(b))),
				"wall": String(b["type"]) == "wall" or String(b["type"]) == "gate",
				"house": String(b["type"]) == "house"})
	var pcfg: Dictionary = cfg.get("placement", {})
	var build_gap := int(pcfg.get("build_gap", 1))
	var wall_gap := int(pcfg.get("wall_house_gap", 3))
	var processed := 0
	var y: int = c["y"]
	while y < map.h and processed < budget:
		var row_d: float = absf(float(y) - float(map.spawn_tile.y))
		if row_d > best_d:
			y += 1
			continue
		var x: int = c["x"]
		while x < map.w and processed < budget:
			processed += 1
			var t := Vector2i(x, y)
			var col_d: float = maxf(row_d, absf(float(x) - float(map.spawn_tile.x)))
			x += 1
			if col_d >= best_d:
				continue
			if on_resource and not (map.grid[t.y][t.x] in kinds):
				continue
			var ok := true
			for dy in w:
				for dx in w:
					var ct := t + Vector2i(dx, dy)
					if not is_buildable_tile(ct) or not building_at(ct).is_empty():
						ok = false
						break
				if not ok:
					break
			# особые правила места (шахта на жиле, оружейная у кузни...) —
			# без этого скан находил формально годное, но игрово неверное место
			if ok and placement_block(type_id, t) != "":
				ok = false
			if ok and bool(c.get("nature", false)) \
					and _nature_near_rect(type_id, t, kinds,
							float(c.get("radius", 6))) == Vector2i(-1, -1):
				ok = false
			if ok:
				for o in others:
					var r: Rect2i = o["r"]
					var dx2: int = maxi(maxi(t.x - r.end.x, r.position.x - (t.x + w)), 0)
					var dy2: int = maxi(maxi(t.y - r.end.y, r.position.y - (t.y + w)), 0)
					if maxi(dx2, dy2) < (wall_gap if (o["wall"] and o["house"]) else build_gap):
						ok = false
						break
			if not ok:
				continue
			best = t
			best_d = col_d
		if x >= map.w:
			y += 1
			x = 0
		c["y"] = y
		c["x"] = x
	if y >= map.h:
		c["done"] = true
	c["best"] = best
	c["best_d"] = best_d


## Тик-продвижение всех незавершённых сканов — каждый тик, по бюджету:
## полный скан доезжает за ~17 тиков (~2 игровые секунды), фриза нет.
func _advance_gather_scans_all() -> void:
	for key in _gather_cache.keys():
		var c: Dictionary = _gather_cache[key]
		if not bool(c.get("done", true)):
			_advance_gather_scan(c, GATHER_SCAN_BUDGET)


func _ring_buildable(center: Vector2i, max_radius: int, type_id := "") -> Vector2i:
	for radius in range(1, max_radius + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := center + Vector2i(dx, dy)
				if type_id != "":
					# этап 2: автострой учитывает зазор между зданиями;
					# v1.23: и запреты размещения (поля ферм) — сюда тоже
					if is_buildable_rect(type_id, tile) and placement_gap_ok(type_id, tile) \
							and placement_block(type_id, tile) == "":
						return tile
				elif is_buildable_tile(tile):
					return tile
	return Vector2i(-1, -1)


func _announce_autobuild(type_id: String, toast: bool) -> void:
	var manager := ""
	for r in residents:
		if String(r["prof"]) == "elder":
			manager = String(r["name"])
			break
	_chron("chron.autobuild", manager, type_id)
	if toast:
		events.append({"type": "autobuild", "name": manager, "bld": type_id})


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
	if not _food_reserve_ok() or _avg_mood() < float(rcfg.get("mood_gate", 45.0)):
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


## Дневной бросок: события-истории про конкретных жителей (пункт плана M4).
func _roll_stories() -> void:
	var scfg: Dictionary = people.get("stories", {})
	if scfg.is_empty():
		return
	if _event_rng.randf() >= float(scfg.get("chance_per_day", 0.5)):
		return
	match _weighted_pick(scfg.get("weights", {})):
		"quarrel":
			_story_quarrel(scfg)
		"friendship":
			_story_friendship(scfg)
		"discovery":
			_story_discovery(scfg)
		"betrayal":
			_story_betrayal(scfg)
		"mutation":
			_story_mutation(scfg)
		"festival":
			_story_festival(scfg)
		"prodigy":
			_story_prodigy(scfg)
		"brave_deed":
			_story_brave_deed(scfg)
		"meteor":
			_story_meteor(scfg)
		"herbs":
			_story_herbs(scfg)
		"night_terror":
			_story_night_terror(scfg)
		"wedding":
			_story_wedding(scfg)
		"artifact":
			_story_artifact(scfg)
		"good_harvest":
			_story_good_harvest(scfg)
		"stranger":
			_story_stranger(scfg)


## Ссора (ответ №29, отключается галочкой): ворчун портит настроение ещё кому-то.
func _story_quarrel(scfg: Dictionary) -> void:
	if not conflicts or residents.size() < 2:
		return
	# сухой закон (M14-H): ссор реже
	if has_law("prohibition") \
			and _event_rng.randf() < float(law_param("prohibition", "quarrel_chance_mult", 1.0)):
		return
	var instigators: Array = []
	for r in _adults():
		if _has_trait_flag(r, "instigator"):
			instigators.append(r)
	if instigators.is_empty():
		return
	var a: Dictionary = instigators[_event_rng.randi_range(0, instigators.size() - 1)]
	var others: Array = []
	for r in _adults():
		if r != a:
			others.append(r)
	if others.is_empty():
		return
	var b: Dictionary = others[_event_rng.randi_range(0, others.size() - 1)]
	var dm: float = float(scfg.get("quarrel_mood", -15.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_rel_change(a, b, float(_v3().get("quarrel_rel_hit", -18.0)))   # отношения v3
	_mem_push(a, "quarrel")
	_mem_push(b, "quarrel")
	_chron("chron.quarrel", String(a["name"]), String(b["name"]))
	events.append({"type": "quarrel", "a": String(a["name"]), "b": String(b["name"])})


## Дружба (ответ №34): пара работает вместе эффективнее и бодрее духом.
func _story_friendship(scfg: Dictionary) -> void:
	var cands: Array = []
	for r in _adults():
		if int(r.get("friend", -1)) < 0 and float(r["mood"]) >= 50.0:
			cands.append(r)
	if cands.size() < 2:
		return
	var a: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	var b: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	if a == b:
		return
	a["friend"] = int(b["id"])
	b["friend"] = int(a["id"])
	var dm: float = float(scfg.get("friendship_mood", 10.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_chron("chron.friendship", String(a["name"]), String(b["name"]))
	events.append({"type": "friendship", "a": String(a["name"]), "b": String(b["name"])})


## Находка (навык пригодился): излишек ресурса в общий пул.
func _story_discovery(scfg: Dictionary) -> void:
	var skilled: Array = []
	var expert_at: float = float(people.get("skill_expert_at", 3.0))
	for r in _adults():
		if float(r.get("skill", 0.0)) >= expert_at:
			skilled.append(r)
	if skilled.is_empty():
		return
	var r: Dictionary = skilled[_event_rng.randi_range(0, skilled.size() - 1)]
	var roll := _event_rng.randf()
	var key := "food"
	var amount: float = float(scfg.get("discovery_food", 12))
	if roll > 0.8:
		key = "crystal"
		amount = float(scfg.get("discovery_crystal", 1))
	elif roll > 0.4:
		key = "stone"
		amount = float(scfg.get("discovery_stone", 6))
	_add_resource_capped(key, amount)
	_chron("chron.discovery", String(r["name"]), key)
	events.append({"type": "discovery", "name": String(r["name"]), "res": key})


## Предательство (жадный в унынии крадёт еду; страж в городе — пойман).
func _story_betrayal(scfg: Dictionary) -> void:
	if not conflicts:
		return
	var thieves: Array = []
	for r in _adults():
		if _has_trait_flag(r, "can_steal") and float(r["mood"]) < 40.0:
			thieves.append(r)
	if thieves.is_empty():
		return
	var r: Dictionary = thieves[_event_rng.randi_range(0, thieves.size() - 1)]
	var guard_near := false
	for other in residents:
		if String(other["prof"]) == "guard":
			guard_near = true
			break
	if guard_near:
		r["mood"] = clampf(float(r["mood"]) - 15.0, 0.0, 100.0)
		_chron("chron.betrayal_caught", String(r["name"]))
		events.append({"type": "betrayal_caught", "name": String(r["name"])})
		return
	var amount: float = minf(float(scfg.get("betrayal_food", 10)), float(res["food"]))
	res["food"] = maxf(0.0, float(res["food"]) - amount)
	var dm: float = float(scfg.get("betrayal_mood", -5.0))
	for other in residents:
		other["mood"] = clampf(float(other["mood"]) + dm, 0.0, 100.0)
	_chron("chron.betrayal", String(r["name"]))
	events.append({"type": "betrayal", "name": String(r["name"])})


## Мутация (ответ №35): дикая магия меняет жителя — кому улучшение, кому болезнь.
func _story_mutation(scfg: Dictionary) -> void:
	if pollution < float(scfg.get("mutation_pollution", 30.0)):
		return
	var adults := _adults()
	if adults.is_empty():
		return
	var r: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	if _event_rng.randf() < 0.5:
		r["work_bonus"] = float(r.get("work_bonus", 0.0)) + float(scfg.get("mutation_work_bonus", 0.1))
		_chron("chron.mutation_good", String(r["name"]))
		events.append({"type": "mutation_good", "name": String(r["name"])})
	else:
		_make_ail(r, "sick", "chron.mutation_bad")
		events.append({"type": "mutation_bad", "name": String(r["name"])})


## --- события-истории M7 (до 15) ---------------------------------------------

## Праздник в таверне: городу есть чем поживиться — все гуляют.
func _story_festival(scfg: Dictionary) -> void:
	if not tavern_active() or float(res["food"]) < float(scfg.get("festival_food", 15)):
		return
	res["food"] = maxf(0.0, float(res["food"]) - float(scfg.get("festival_food", 15)))
	var dm: float = float(scfg.get("festival_mood", 10.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.festival")
	events.append({"type": "festival"})


## Одарённый ученик: умелый житель обучает товарища — навык растёт скачком.
func _story_prodigy(scfg: Dictionary) -> void:
	var expert_at: float = float(people.get("skill_expert_at", 3.0))
	var teacher: Dictionary = {}
	var student: Dictionary = {}
	for r in _adults():
		if float(r.get("skill", 0.0)) >= expert_at:
			teacher = r
			break
	for r in _adults():
		if not r.is_empty() and r != teacher and float(r.get("skill", 0.0)) < float(people.get("skill_max", 5.0)):
			student = r
			break
	if teacher.is_empty() or student.is_empty():
		return
	student["skill"] = minf(float(people.get("skill_max", 5.0)),
			float(student["skill"]) + float(scfg.get("prodigy_skill", 1.0)))
	_chron("chron.prodigy", String(teacher["name"]), String(student["name"]))
	events.append({"type": "prodigy", "a": String(teacher["name"]), "b": String(student["name"])})


## Храбрый поступок: храбрец спасает жителя — город гордится.
func _story_brave_deed(scfg: Dictionary) -> void:
	var heroes: Array = []
	for r in _adults():
		if _has_trait_flag(r, "fearless"):
			heroes.append(r)
	if heroes.is_empty():
		return
	var hero_r: Dictionary = heroes[_event_rng.randi_range(0, heroes.size() - 1)]
	var dm: float = float(scfg.get("brave_deed_mood", 8.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.brave_deed", String(hero_r["name"]))
	events.append({"type": "brave_deed", "name": String(hero_r["name"])})


## Метеорит: упал камень с неба — добыча даром, но воздух дурит.
func _story_meteor(scfg: Dictionary) -> void:
	_add_resource_capped("stone", float(scfg.get("meteor_stone", 20)))
	add_pollution(float(scfg.get("meteor_pollution", 8.0)))
	_chron("chron.meteor")
	events.append({"type": "meteor"})


## Целебные травы: лекарь находит сбор — все больные выздоравливают разом.
func _story_herbs(scfg: Dictionary) -> void:
	if not _healer_ready():
		return
	var healed := 0
	for r in residents:
		if String(r.get("ail", "")) != "":
			r["ail"] = ""
			healed += 1
	if healed == 0:
		return
	_assign_jobs()
	_chron("chron.herbs", str(healed))
	events.append({"type": "herbs", "n": healed})


## Кошмары: наэлектризованный воздух не даёт спать — настроение чуть проседает.
func _story_night_terror(scfg: Dictionary) -> void:
	if pollution < float(scfg.get("terror_pollution", 20.0)):
		return
	var dm: float = float(scfg.get("terror_mood", -6.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.night_terror")
	events.append({"type": "night_terror"})


## Свадьба: двое свободных жителей соединяются — им и городу веселей.
func _story_wedding(scfg: Dictionary) -> void:
	var cands: Array = []
	for r in _adults():
		if int(r.get("friend", -1)) < 0:
			cands.append(r)
	if cands.size() < 2:
		return
	var a: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	var b: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	if a == b:
		return
	a["friend"] = int(b["id"])
	b["friend"] = int(a["id"])
	var dm: float = float(scfg.get("wedding_mood", 12.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_chron("chron.wedding", String(a["name"]), String(b["name"]))
	events.append({"type": "wedding", "a": String(a["name"]), "b": String(b["name"])})


## Артефакт: житель выкапывает странную вещь — кристалл в пул, мастерство в голову.
func _story_artifact(scfg: Dictionary) -> void:
	var adults := _adults()
	if adults.is_empty():
		return
	var r: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	_add_resource_capped("crystal", float(scfg.get("artifact_crystal", 1)))
	r["skill"] = minf(float(people.get("skill_max", 5.0)),
			float(r["skill"]) + float(scfg.get("artifact_skill", 0.5)))
	_chron("chron.artifact", String(r["name"]))
	events.append({"type": "artifact", "name": String(r["name"])})


## Урожайный год: погода и руки сошлись — лишняя еда в амбар.
func _story_good_harvest(scfg: Dictionary) -> void:
	if _assigned_done_of_farm().is_empty():
		return
	_add_resource_capped("food", float(scfg.get("harvest_food", 18)))
	_chron("chron.good_harvest")
	events.append({"type": "good_harvest"})


## Странник: изгнанник делится припасами и слухами о данже.
func _story_stranger(scfg: Dictionary) -> void:
	_add_resource_capped("food", float(scfg.get("stranger_food", 10)))
	_add_resource_capped("crystal", float(scfg.get("stranger_crystal", 1)))
	_chron("chron.stranger")
	events.append({"type": "stranger"})


## Готовая ферма с работающим фермером — условие «Урожайного года».
func _assigned_done_of_farm() -> Dictionary:
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == "farm" and int(b["worker"]) > 0:
			return b
	return {}


## Летопись: хранит ключи локализации, текст собирает HUD.
func _chron(key: String, a: String = "", b: String = "") -> void:
	chronicle.append({"day": day, "key": key, "a": a, "b": b})
	if chronicle.size() > 200:
		chronicle.pop_front()


