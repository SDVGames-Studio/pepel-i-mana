# -*- coding: utf-8 -*-
## v2.2 патч 4: war-слой — ищейка/охотники ветки рейдеров, дневные броски
## (тайные лагеря, алтарь, доклады охотников), тик духов, отряд после волны.
import io, shutil, sys

p = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts\city_sim_war.gd"
src = io.open(p, encoding="utf-8").read()
if "secret_camp_daily" in src:
    print("ALREADY PATCHED")
    sys.exit(0)

# --- 1. ветки ищейки и охотников в _raider_update ---
a1 = '''		"guard":
			return _hive_guard_update(r, mv, tcfg)
'''
assert a1 in src, "anchor1 (role match) missing"
r1 = a1 + '''		"seeker":
			return _hive_seeker_update(r, mv)
		"hunt_ally":
			return _hunt_ally_update(r, mv)
'''
src = src.replace(a1, r1, 1)

# --- 2. дневной блок: новые броски ---
a2 = '''		night_guests_daily()
		bandit_tribute_daily()
'''
assert a2 in src, "anchor2 (daily block) missing"
r2 = a2 + '''		secret_camp_daily()
		altar_daily()
		hunt_report_daily()
		hunt_squad_daily()
'''
src = src.replace(a2, r2, 1)

# --- 3. шанс отряда охотников после отбонной волны ---
a3 = '''			events.append({"type": "raid_repelled", "crystals": reward})
			_chron("chron.repelled")
'''
assert a3 in src, "anchor3 (raid repelled) missing"
r3 = a3 + '''			_try_spawn_hunt_squad()   # v2.2 п.1: странствующие охотники
'''
src = src.replace(a3, r3, 1)

# --- 4. новые функции в хвост файла ---
tail = '''

## ==================== СЛЕДЫ: ОХОТНИКИ-ГОРОЖАНЕ (v2.2 п.3) ====================
const TRACKS := preload("res://scripts/city_tracks.gd")

## Профессия hunter зеркальна ищейкам: раз в день охотник читает свежие
## следы мутантов — докладывает, с какой стороны логово и когда ждать волну.
func hunt_report_daily() -> void:
	if hive.is_empty() or not bool(hive.get("active", false)):
		return
	var hunter := {}
	for r in residents:
		if String(r["prof"]) == "hunter" and String(r.get("ail", "")) == "":
			hunter = r
			break
	if hunter.is_empty():
		return
	var tcfg: Dictionary = cfg.get("tracks", {})
	var life := float(tcfg.get("life_days", 1.2)) * float(cfg["day_length"])
	var tr: Dictionary = TRACKS.near(city_tracks, Vector2(hunter["pos"]),
			float(tcfg.get("hunter_sense", 220.0)), time, life, "raider")
	if tr.is_empty():
		return
	var side := _compass_of(-(tr["dir"] as Vector2))
	var eta := -1
	if not (hive.get("city_known", {}) as Dictionary).is_empty():
		eta = int(maxf(0.0, float(hive["next_wave_day"]) - float(day)))
	events.append({"type": "hunt_report", "side": side, "eta": eta})
	_chron("chron.hunt_report", side)


## Сторона света по вектору (для доклада охотника).
func _compass_of(v: Vector2) -> String:
	if absf(v.x) >= absf(v.y):
		return "восток" if v.x > 0.0 else "запад"
	return "юг" if v.y > 0.0 else "север"


## ==================== ТАЙНЫЕ ЛАГЕРЯ (v2.2 п.4) ====================
## Бандиты/сектанты ставят лагерь на дикой окраине (скрытая POI, не видна
## пока не найдена): кражи со складов, сектантские проповеди, порча полей.
## Находится по следам лазутчиков и уликам; разгром — героем или стражей.
const CAMP_SPY_NAMES := ["Горий", "Влада", "Твердило", "Милана", "Ждан", "Купава"]


func secret_camp_daily() -> void:
	if map == null:
		return
	var ccfg: Dictionary = cfg.get("camps", {})
	if ccfg.get("enabled", true) == false:
		return
	if not secret_camps.is_empty():
		_camp_crimes(ccfg)
		_camp_clue_roll()
		return
	if int(day) < int(ccfg.get("start_day", 8)):
		return
	if _last_camp_day > 0 and int(day) - _last_camp_day < int(ccfg.get("gap_days", 7)):
		return
	if _event_rng.randf() >= float(ccfg.get("chance", 0.35)):
		return
	var t := _camp_tile()
	if t == Vector2i(-1, -1):
		return
	_last_camp_day = int(day)
	var kind := "sect" if _event_rng.randf() < 0.4 else "bandit"
	var names: Array = CAMP_SPY_NAMES.duplicate()
	var spies: Array = []
	for i in 2:
		var idx := _event_rng.randi_range(0, names.size() - 1)
		spies.append(names[idx])
		names.remove_at(idx)
	secret_camps.append({
		"id": _camp_id, "tile": t, "kind": kind, "found": false,
		"suspicion": 0, "visits": 0, "spies": spies, "last_crime": -99,
	})
	_camp_id += 1


## Тайл под лагерь: дикая окраина (по образцу засад — подальше от жилья).
func _camp_tile() -> Vector2i:
	for attempt in 40:
		var ang := TAU * _event_rng.randf()
		var rr := 22.0 + _event_rng.randf() * 14.0
		var t: Vector2i = map.spawn_tile + Vector2i(
				int(round(cos(ang) * rr)), int(round(sin(ang) * rr)))
		if not map.in_bounds(t) or not map.is_walkable(t):
			continue
		if Vector2i(t - map.spawn_tile).length() < 20.0:
			continue
		return t
	return Vector2i(-1, -1)


## Преступления лагеря: раз в несколько дней (кража / проповедь) + следы.
func _camp_crimes(ccfg: Dictionary) -> void:
	var camp: Dictionary = secret_camps[0]
	if int(day) - int(camp.get("last_crime", -99)) < int(ccfg.get("crime_every_days", 3)):
		return
	camp["last_crime"] = int(day)
	if String(camp["kind"]) == "bandit":
		var took := minf(float(ccfg.get("steal_food", 5.0)), float(res.get("food", 0.0)))
		if took > 0.0:
			res["food"] = float(res["food"]) - took
		if float(res.get("coins", 0.0)) > 0.0:
			var c := minf(float(ccfg.get("steal_coins", 4.0)), float(res["coins"]))
			res["coins"] = float(res["coins"]) - c
		camp["suspicion"] = int(camp["suspicion"]) + 1
		events.append({"type": "warehouse_theft", "food": int(took)})
		_chron("chron.theft", str(int(took)))
	else:
		for r in residents:
			r["mood"] = clampf(float(r["mood"]) - float(ccfg.get("sermon_mood", 3.0)), 0.0, 100.0)
		camp["suspicion"] = int(camp["suspicion"]) + 1
		events.append({"type": "sect_sermon"})
		_chron("chron.sermon")
	# у лагеря топчутся свои — сеем следы-зацепки (кто следит, тот найдёт)
	var ts := float(map.ts)
	var pos := map.tile_center_px(camp["tile"])
	for i in 3:
		var p2 := pos + Vector2(_event_rng.randf_range(-ts, ts), _event_rng.randf_range(-ts, ts))
		city_tracks = TRACKS.push(city_tracks, p2, float(time), "spy",
				Vector2.from_angle(_event_rng.randf() * TAU), 1.0)


## Случайная улика: подозрение велико — житель находит след лагеря.
func _camp_clue_roll() -> void:
	var camp: Dictionary = secret_camps[0]
	if bool(camp["found"]) or int(camp["suspicion"]) < 2:
		return
	if _event_rng.randf() >= 0.15:
		return
	reveal_camp()


## Лагерь раскрыт (улика, допрос или выслеживание по следам).
func reveal_camp() -> void:
	if secret_camps.is_empty():
		return
	var camp: Dictionary = secret_camps[0]
	if bool(camp["found"]):
		return
	camp["found"] = true
	var kind := String(camp["kind"])
	events.append({"type": "camp_found", "kind": kind})
	_chron("chron.camp_found", "camp.kind." + kind)
	_letter("camp_found", Loc.t("city.camp_found_toast"))


## Разгром лагеря: героем (бой) или отрядом стражи. "" — успех.
func assault_camp(by_hero: bool) -> String:
	if secret_camps.is_empty():
		return "city.camp_none"
	var camp: Dictionary = secret_camps[0]
	if not bool(camp["found"]):
		return "city.camp_not_found"
	var ccfg: Dictionary = cfg.get("camps", {})
	if by_hero:
		var hero_power := int(ccfg.get("hero_power", 3)) + raid_count / 2
		var camp_power := int(ccfg.get("camp_power", 4)) + raid_count / 4
		if hero_power < camp_power:
			events.append({"type": "hero_hit", "dmg": 12})
			return "city.camp_assault_fail"
	else:
		var guards := 0
		for r in residents:
			if String(r["prof"]) == "guard" and String(r.get("ail", "")) == "":
				guards += 1
		if guards < int(ccfg.get("guards_needed", 2)):
			return "city.camp_need_guards"
		if _event_rng.randf() > float(ccfg.get("guards_win", 0.75)):
			var g := {}
			for r2 in residents:
				if String(r2["prof"]) == "guard" and String(r2.get("ail", "")) == "":
					g = r2
					break
			if not g.is_empty():
				_make_ail(g, "wounded", "chron.wounded")
			return "city.camp_assault_fail"
	razed_camp()
	return ""


## Лагерь снесён: награда, перемирие с бандитами, радость городу.
func razed_camp() -> void:
	if secret_camps.is_empty():
		return
	var camp: Dictionary = secret_camps[0]
	var ccfg: Dictionary = cfg.get("camps", {})
	var kind := String(camp["kind"])
	_add_resource_capped("food", float(ccfg.get("loot_food", 8.0)))
	if coins_sink.is_valid():
		coins_sink.call(int(ccfg.get("loot_coins", 15)))
	if kind == "bandit":
		# бандиты перегруппировываются — дань не спросят долго
		tribute_next_day = int(day) + int(ccfg.get("truce_days", 12))
		tribute_pending = false
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + 5.0, 0.0, 100.0)
	secret_camps.clear()
	events.append({"type": "camp_razed", "kind": kind})
	_chron("chron.camp_razed", "camp.kind." + kind)
	_letter("camp_razed", Loc.t("city.camp_razed_toast"))


## ==================== АЛТАРЬ БЛАГОДАТИ (v2.2 п.2) ====================
## Ежедневно: аколит-контролёр растёт в мастерстве, алтарь фонит
## магическим загрязнением (тянет серую плесень), погибший дух
## перезывается через N дней.
func altar_daily() -> void:
	var gcfg: Dictionary = cfg.get("grace_altar", {})
	if gcfg.is_empty():
		return
	var altars := 0
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == "grace_altar":
			altars += 1
			if int(b.get("worker", -1)) > 0:
				acolyte_skill = minf(float(gcfg.get("skill_max", 20.0)),
						acolyte_skill + float(gcfg.get("skill_per_day", 1.0)))
			var sp := spirit_of(b)
			if sp.is_empty():
				var rd := int(b.get("spirit_respawn_day", -1))
				if rd < 0:
					b["spirit_respawn_day"] = int(day) + int(gcfg.get("respawn_days", 3))
				elif int(day) >= rd:
					spirit_summon(b)
	if altars > 0:
		add_pollution(float(gcfg.get("pollution_per_day", 1.5)) * float(altars))
	for s in spirits:
		s["eff"] = spirit_eff()


## ==================== ДУХИ: ТИК (v2.2 п.2) ====================
## Дух ходит на работу (стройка/добыча) и работает с эффективностью eff;
## волны его бьют — погибает, алтарь перезывает (altar_daily).
func _update_spirits(dt: float) -> void:
	if spirits.is_empty():
		return
	var gcfg: Dictionary = cfg.get("grace_altar", {})
	var dead: Array = []
	for s in spirits:
		var b: Dictionary = _building_by_id(int(s["bld"]))
		if b.is_empty() or not bool(b["done"]):
			dead.append(s["id"])
			continue
		var mode := String(s["mode"])
		if mode == "build":
			var site := _nearest_unfinished_site(Vector2(s["pos"]))
			if site.is_empty():
				continue
			var goal: Vector2 = map.tile_center_px(
					(site["tile"] as Vector2i) + Vector2i(0, bld_w(site)))
			if (s["pos"] as Vector2).distance_to(goal) < float(map.ts):
				site["progress"] = float(site["progress"]) + dt * float(s["eff"])
				if float(site["progress"]) >= float(_def(site)["build_work"]):
					_complete_site(site)
			else:
				_spirit_walk(s, goal, dt, gcfg)
		elif mode == "gather":
			var bld: Dictionary = _nearest_gather_bld(Vector2(s["pos"]))
			if bld.is_empty():
				continue
			var goal2: Vector2 = map.tile_center_px(
					(bld["tile"] as Vector2i) + Vector2i(0, bld_w(bld)))
			if (s["pos"] as Vector2).distance_to(goal2) < float(map.ts):
				_produce_tick(s, bld, dt * float(s["eff"]))
			else:
				_spirit_walk(s, goal2, dt, gcfg)
	# волны бьют духа
	if raid_active:
		for r in raiders:
			if String(r.get("role", "")) != "":
				continue
			for s2 in spirits:
				if (s2["pos"] as Vector2).distance_to(r["pos"] as Vector2) < float(map.ts) \
						and not dead.has(s2["id"]):
					s2["hp"] = float(s2["hp"]) - float(r["p"]["damage"]) * dt * 0.6
	for s3 in spirits:
		if float(s3["hp"]) <= 0.0 and not dead.has(s3["id"]):
			dead.append(s3["id"])
			var b3: Dictionary = _building_by_id(int(s3["bld"]))
			if not b3.is_empty():
				b3["spirit_respawn_day"] = int(day) + int(gcfg.get("respawn_days", 3))
			events.append({"type": "spirit_died"})
			_chron("chron.spirit_died")
	if not dead.is_empty():
		spirits = spirits.filter(func(x) -> bool: return not dead.has(x["id"]))


## Дух парит к цели — стены не мешают (он дух).
func _spirit_walk(s: Dictionary, goal: Vector2, dt: float, gcfg: Dictionary) -> void:
	var v: Vector2 = goal - (s["pos"] as Vector2)
	if v.length() > 1.0:
		s["pos"] = (s["pos"] as Vector2) + v.normalized() * float(gcfg.get("speed", 70.0)) * dt


## Ближайшая недостроенная стройка.
func _nearest_unfinished_site(from: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if bool(b["done"]):
			continue
		var d := (Vector2(b["tile"]) * float(map.ts)).distance_to(from)
		if d < best_d:
			best_d = d
			best = b
	return best


## Ближайшая добывающая постройка (лесопилка/каменоломня/шахта/пристань).
func _nearest_gather_bld(from: Vector2) -> Dictionary:
	var kinds := ["sawmill", "quarry", "mine", "pier"]
	var best: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if not (bool(b["done"]) and String(b["type"]) in kinds):
			continue
		if _def(b).get("produce", {}).is_empty():
			continue
		var d := (Vector2(b["tile"]) * float(map.ts)).distance_to(from)
		if d < best_d:
			best_d = d
			best = b
	return best


## ==================== СТРАНСТВУЮЩИЕ ОХОТНИКИ (v2.2 п.1) ====================
## Шанс после отбонной волны: чужой отряд идёт на логово мутантов сам.
func _try_spawn_hunt_squad() -> void:
	var hcfg: Dictionary = cfg.get("hunt_squad", {})
	if hcfg.get("enabled", true) == false or hive.is_empty():
		return
	if not bool(hive.get("active", false)) or not hunter_squad.is_empty():
		return
	if _last_squad_day > 0 and int(day) - _last_squad_day < int(hcfg.get("gap_days", 5)):
		return
	if _event_rng.randf() >= float(hcfg.get("chance", 0.25)):
		return
	_last_squad_day = int(day)
	hunter_squad = {
		"state": "come", "eta_day": int(day) + int(hcfg.get("travel_days", 1)),
		"edge": _edge_tile(), "left": 0.0,
	}
	events.append({"type": "hunt_squad_come"})
	_chron("chron.hunt_squad_come")
'''

src = src.rstrip("\n") + "\n" + tail
shutil.copy(p, p + ".bak")
io.open(p, "w", encoding="utf-8", newline="\n").write(src)
print("OK city_sim_war.gd")
