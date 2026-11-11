# Часть: имитация жизни M12 и вечерняя соцжизнь v1.47 (досуг, разговоры,
# дети, прогулки, свидания и ревность).
# Структура v1.62.0: бывший city_sim_tick.gd разрезан — жизнь жителей
# вынесена из тик-хребта. Это один класс, поведение не меняется.
extends "res://scripts/city_sim_tick.gd"

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


## ==================== Вечерняя соцжизнь (v1.47, «Новый мир v2» этап 5) ====

## Прогулка в свободное время: свободный взрослый идёт к лучшему другу /
## симпатии (rel > 25) или к площади/воде. Встреча двух гуляющих в 1.5
## тайлах — СВИДАНИЕ (настроение + отношения); свидетель, чья симпатия к
## одному из пары высока, РЕВНУЕТ — рождается любовный треугольник.
## Возвращает true, если житель занят прогулкой (кадр обработан).
func _social_walk(r: Dictionary, dt: float) -> bool:
	if String(r["prof"]) == "guard" or int(r.get("inside", 1)) != 0 \
			or String(r.get("state", "")) in ["sleep", "sick", "wounded", "child", "hide"]:
		return false
	var ts := float(map.ts)
	# фаза прогулки: цель уже выбрана
	if String(r.get("state", "")) == "walk":
		var goal: Vector2i = Vector2i(r.get("walk_goal", Vector2i(-1, -1)))
		if goal == Vector2i(-1, -1) or not map.is_walkable(goal):
			r["state"] = "idle"
			r.erase("walk_goal")
			return false
		if _arrived(r, goal):
			r["state"] = "idle"
			r.erase("walk_goal")
			r["mood"] = clampf(float(r["mood"]) + 2.0, 0.0, 100.0)
			return true
		_move_towards(r, goal, dt)
		_check_encounter(r)
		return true
	# начать прогулку: только К КОМУ-ТО (друг/симпатия rel > 25) — без
	# близких связей остаёмся в старом досуге (костёр/беседы, v1.28)
	if _event_rng.randf() > 0.5:
		return false
	var best := rel_best(r)
	if best.is_empty():
		return false
	var goal: Vector2i = map.nearest_walkable(map.tile_of_px(Vector2(best["pos"])))
	if goal == Vector2i(-1, -1):
		return false
	if float(r.get("_walk_cd", 0.0)) > time:
		return false
	r["_walk_cd"] = time + float(cfg["day_length"]) * 0.3
	r["state"] = "walk"
	r["walk_goal"] = goal
	return true


## Встречи на прогулке: свидание (взаимная симпатия) или ревность.
func _check_encounter(r: Dictionary) -> void:
	# не чаще раза в секунду на жителя
	if float(r.get("_enc_cd", 0.0)) > time:
		return
	r["_enc_cd"] = time + 1.0
	for other in residents:
		if int(other["id"]) == int(r["id"]) or int(other.get("inside", 1)) != 0:
			continue
		if String(other.get("state", "")) != "walk":
			continue
		var d: float = (other["pos"] as Vector2).distance_to(r["pos"])
		if d > float(map.ts) * 1.5:
			continue
		var score: float = _rel_score(r, int(other["id"]))
		# ревность: у меня высокая симпатия к нему, а он гуляет С ДРУГИМ,
		# чья симпатия к нему ещё выше — треугольник
		var third := _walk_third(other, int(r["id"]))
		if score > 30.0 and third != -1:
			_rel_change(r, other, -25.0)
			var third_res := _resident_by_id(third)
			if not third_res.is_empty():
				_rel_change(r, third_res, -30.0)
			r["mood"] = clampf(float(r["mood"]) - 10.0, 0.0, 100.0)
			events.append({"type": "jealous", "name": String(r["name"]),
					"other": String(other["name"])})
			_chron("chron.jealous", String(r["name"]), String(third_res.get("name", "")) if not third_res.is_empty() else "")
			return
		# свидание: взаимно тёплая встреча
		if score > 15.0:
			_rel_change(r, other, 8.0)
			r["mood"] = clampf(float(r["mood"]) + 3.0, 0.0, 100.0)
			other["mood"] = clampf(float(other["mood"]) + 3.0, 0.0, 100.0)
			if _event_rng.randf() < 0.12:
				events.append({"type": "date", "a": String(r["name"]),
						"b": String(other["name"])})
				_chron("chron.date", String(r["name"]), String(other["name"]))
		return


## Третий в треугольнике: с кем гуляет other (не r).
func _walk_third(other: Dictionary, except_id: int) -> int:
	var best := -1
	var best_s := 20.0
	for cand in residents:
		if int(cand["id"]) == int(other["id"]) or int(cand["id"]) == except_id:
			continue
		if String(cand.get("state", "")) != "walk":
			continue
		if (cand["pos"] as Vector2).distance_to(other["pos"]) > float(map.ts) * 2.0:
			continue
		var s2 := _rel_score(other, int(cand["id"]))
		if s2 > best_s:
			best_s = s2
			best = int(cand["id"])
	return best
