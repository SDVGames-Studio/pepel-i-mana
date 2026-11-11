# Часть: утренняя планёрка старосты, отладочный лог и поиск мест автостройки.
# Структура v1.62.0: бывший city_sim_gov.gd разрезан — планёрка/лог/сканы
# подняты выше gov (их зовёт _roll_autobuild), истории уехали вниз.
# Это один класс, поведение не меняется.
extends "res://scripts/city_sim_trade.gd"

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


## Еда на одного жителя (v1.22): планёрка видит запас на пороге зимы.
func food_per_resident() -> float:
	return float(res.get("food", 0.0)) / maxf(1.0, float(residents.size()))


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
