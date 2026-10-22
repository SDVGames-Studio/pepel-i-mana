# Часть: жители — сон, защита, работа у зданий.
# Правки структуры v1.20.2: огромный city_sim.gd разбит на extends-цепочку
# частей; это один класс, разложенный по файлам — поведение не меняется.
extends "res://scripts/city_sim_build.gd"

# --- жители --------------------------------------------------------------

## Раздача работы: производственные здания и стройплощадки — свободным жителям.
## M4-подмена: если по профессии никого нет, свободный житель замещает (и учится),
## а держатель подмены возвращается на свою профессию, когда она понадобилась.
func _assign_jobs() -> void:
	var taken := {}   # id жителя -> занят
	for r in residents:
		if r["bld"] != null or r["site"] != null:
			taken[int(r["id"])] = true
	# 1. стройки — свободным строителям
	for b in buildings:
		if b["done"]:
			continue   # готовое производственное здание закрепляется ниже
		if int(b["worker"]) > 0 and taken.has(int(b["worker"])):
			continue
		var worker := _free_resident("builder", taken)
		if worker.is_empty():
			continue
		b["worker"] = int(worker["id"])
		worker["site"] = b
		worker["bld"] = null
		taken[int(worker["id"])] = true
	# 2. готовые здания — по основной профессии; торговый двор (M10) забирает
	# торговца раньше палаток (этап 2, аспект 4: палатки дополняют рынок, не конкурируют)
	for pass_n in 2:
		for b in buildings:
			var is_tent := String(b["type"]) == "tent"
			if pass_n == 0 and is_tent:
				continue
			if pass_n == 1 and not is_tent:
				continue
			if not _active(b) or not def_has_worker(b):
				continue
			if int(b["worker"]) > 0 and taken.has(int(b["worker"])):
				continue
			var worker := _free_resident(String(_def(b)["worker"]), taken)
			if worker.is_empty():
				continue   # попробуют замещающие ниже
			b["worker"] = int(worker["id"])
			worker["bld"] = b
			worker["site"] = null
			taken[int(worker["id"])] = true
	# 3. держатели подмен возвращаются на основную профессию, если она нужна
	_substitutes_to_primary(taken)
	# 4. подмена строек и зданий свободными жителями (с обучением)
	for b in buildings:
		if not bool(b["done"]) and (int(b["worker"]) <= 0 or not taken.has(int(b["worker"]))):
			_substitute_into("builder", taken, b, true)
	for pass_n in 2:   # рынок раньше палаток и в подмене (этап 2, аспект 4)
		for b in buildings:
			var is_tent := String(b["type"]) == "tent"
			if (pass_n == 0) == is_tent:
				continue
			if not _active(b) or not def_has_worker(b):
				continue
			if int(b["worker"]) > 0 and taken.has(int(b["worker"])):
				continue
			_substitute_into(String(_def(b)["worker"]), taken, b, false)
	# 5. всё ещё некому — сообщаем игроку
	for b in buildings:
		if not _active(b) or not def_has_worker(b):
			continue
		if int(b["worker"]) <= 0:
			events.append({"type": "no_worker", "bld": String(b["type"])})


## Держатель подмены возвращается на свою профессию, если по ней свободна работа.
func _substitutes_to_primary(taken: Dictionary) -> void:
	for r in residents:
		if String(r.get("sub_prof", "")) == "":
			continue
		var want := String(r["prof"])
		var target: Dictionary = {}
		if want == "builder":
			for b in buildings:
				if not bool(b["done"]) and int(b["worker"]) <= 0:
					target = b
					break
		if target.is_empty():
			for b in buildings:
				if not _active(b) or not def_has_worker(b):
					continue
				if String(_def(b)["worker"]) != want or int(b["worker"]) > 0:
					continue
				target = b
				break
		if target.is_empty():
			continue
		if r["bld"] != null:
			(r["bld"] as Dictionary)["worker"] = -1
		if r["site"] != null:
			(r["site"] as Dictionary)["worker"] = -1
		target["worker"] = int(r["id"])
		var is_site := not bool(target["done"])
		if is_site:
			r["site"] = target
			r["bld"] = null
		else:
			r["bld"] = target
			r["site"] = null
		r["sub_prof"] = ""
		taken[int(r["id"])] = true


## Свободный житель замещает нехватку профессии need: предпочитает выучившего,
## иначе учится сам (профессия попадает в prof_extra — ответ на просьбу заказчика).
## Староста — последний резерв ТОЛЬКО жизненно важных мест (правки v1.20:
## еда/ресурсы/стройка): в одиночном городе без рабочих фермы стояли вечно;
## белому голему не место за стойкой таверны и у алтаря.
func _substitute_into(need: String, taken: Dictionary, bld: Dictionary, is_site: bool) -> void:
	var learned_cand: Dictionary = {}
	var any_cand: Dictionary = {}
	var elder_cand: Dictionary = {}
	var vital := is_site or String(bld.get("type", "")) in ["farm", "pier", "sawmill", "quarry", "mine"]
	for r in residents:
		if taken.has(int(r["id"])) or String(r["prof"]) == need:
			continue
		if String(r["prof"]) == "" or String(r.get("ail", "")) != "":
			continue
		if String(r["prof"]) == "elder":
			# староста управляет, а не замещает — но в одиночном городе
			# без рабочих он берёт жизненно важную нехватку на себя
			if vital and r["bld"] == null and r["site"] == null:
				elder_cand = r
			continue
		if r["bld"] != null or r["site"] != null:
			continue
		if (r.get("prof_extra", []) as Array).has(need):
			learned_cand = r
			break
		if any_cand.is_empty():
			any_cand = r
	var cand: Dictionary = learned_cand if not learned_cand.is_empty() else any_cand
	if cand.is_empty():
		cand = elder_cand   # никого, кроме старосты, — староста берёт кирку
	if cand.is_empty():
		return
	var extras: Array = cand.get("prof_extra", [])
	var learned := not extras.has(need)
	if learned and not _is_golem(cand):
		# голем-староста цветов не учит — белый вне цветовой схемы
		extras.append(need)
		_chron("chron.learned", String(cand["name"]), need)
		events.append({"type": "learned", "name": String(cand["name"]), "prof": need})
	cand["sub_prof"] = need
	cand["site"] = bld if is_site else null
	cand["bld"] = null if is_site else bld
	bld["worker"] = int(cand["id"])
	taken[int(cand["id"])] = true


func def_has_worker(b: Dictionary) -> bool:
	return _def(b).has("worker")


## Свободный житель профессии prof (ничем не занят, здоров и не закреплён).
func _free_resident(prof: String, taken: Dictionary) -> Dictionary:
	for r in residents:
		if taken.has(int(r["id"])):
			continue
		if String(r.get("ail", "")) != "":
			continue   # больной работу не получает
		if String(r["prof"]) == prof and r["bld"] == null and r["site"] == null:
			return r
	return {}


