# -*- coding: utf-8 -*-
## v2.2 фикс 1b (только war): хуки, перенос функций, чистка дублей/типов.
import io, sys

pw = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts\city_sim_war.gd"
w = io.open(pw, encoding="utf-8").read()
if "func _hive_seeker_update" in w:
    print("ALREADY PATCHED")
    sys.exit(0)

# 1) тик духов — в начало _update_ambush_units
a1 = '''func _update_ambush_units(dt: float, tcfg: Dictionary) -> void:
	# раз в игровой день — бросок засады и тик памяти мира (проверка
	# здесь, в nature: выше по extends-цепочке (city_sim_tick) члены
	# природы не видны парсеру)
'''
assert a1 in w, "war: ambush_units head missing"
r1 = '''func _update_ambush_units(dt: float, tcfg: Dictionary) -> void:
	if not spirits.is_empty():
		_update_spirits(dt)   # v2.2 п.2: духи благодати работают и гибнут
	# раз в игровой день — бросок засады и тик памяти мира (проверка
	# здесь, в nature: выше по extends-цепочке (city_sim_tick) члены
	# природы не видны парсеру)
'''
w = w.replace(a1, r1, 1)

# 2) TRACKS уже в предке tick — дубль убрать
a2 = '''## ==================== СЛЕДЫ: ОХОТНИКИ-ГОРОЖАНЕ (v2.2 п.3) ====================
const TRACKS := preload("res://scripts/city_tracks.gd")

'''
assert a2 in w, "war: TRACKS const block missing"
r2 = '''## ==================== СЛЕДЫ: ОХОТНИКИ-ГОРОЖАНЕ (v2.2 п.3) ====================
## (TRACKS наследуется от city_sim_tick)
'''
w = w.replace(a2, r2, 1)

# 3) явные типы из untyped map
a3 = "\tvar pos := map.tile_center_px(camp[\"tile\"])\n"
assert a3 in w, "war: pos infer missing"
w = w.replace(a3, "\tvar pos: Vector2 = map.tile_center_px(camp[\"tile\"])\n", 1)
a4 = "\t\tvar p2 := pos + Vector2(_event_rng.randf_range(-ts, ts), _event_rng.randf_range(-ts, ts))\n"
assert a4 in w, "war: p2 infer missing"
w = w.replace(a4, "\t\tvar p2: Vector2 = pos + Vector2(_event_rng.randf_range(-ts, ts), _event_rng.randf_range(-ts, ts))\n", 1)

# 4) перенести из nature: ищейка (3 функции), _hunt_ally_update,
#    hunt_squad_daily, _hive_take_damage
tail = '''

## ==================== ИЩЕЙКА УЛЬЯ (v2.2 п.3) ====================
## Лагерь мутантов не знает, где город: ищейка прочёсывает окрестность
## (кольцо растёт с днями поиска), идёт по свежим следам жителей; учует
## героя — бежит, оставляя логову «грязную» метку «примерно здесь»;
## дошла до жилья — несёт точную точку, и волны идут в цель, не «по воздуху».
func _hive_seeker_update(r: Dictionary, mv: float) -> bool:
	var speed: float = float(r["p"]["speed"]) * mv
	var pos: Vector2 = r["pos"] as Vector2
	# герой рядом — паника: грязная метка «примерно здесь» и бегство
	if hero_alive and pos.distance_to(hero_pos) < float(r["p"]["aggro"]) * 1.2 \\
			and String(r.get("sk_state", "prowl")) == "prowl":
		r["sk_state"] = "flee"
		if (hive.get("city_known", {}) as Dictionary).is_empty():
			r["sk_mark"] = {"pos": pos, "r": float(map.ts) * 9.0, "exact": false}
	match String(r.get("sk_state", "prowl")):
		"flee":
			if _seeker_reach_home(r, speed):
				var mark: Dictionary = r.get("sk_mark", {})
				if not mark.is_empty():
					hive["city_known"] = mark
					events.append({"type": "hive_alert_fuzzy"})
					_chron("chron.hive_alert_fuzzy")
				return false   # добежал и доложил — убираем
			return true
		"home":
			if _seeker_reach_home(r, speed):
				hive["city_known"] = {"pos": r["sk_goal"] as Vector2, "r": 0.0, "exact": true}
				events.append({"type": "hive_knows_city"})
				_chron("chron.hive_knows")
				return false
			return true
	var tcfg: Dictionary = cfg.get("tracks", {})
	var life := float(tcfg.get("life_days", 1.2)) * float(cfg["day_length"])
	# нюх: свежие человеческие следы вокруг (жители/путники/лазутчики)
	var trail: Dictionary = {}
	for who in ["res", "wanderer", "spy"]:
		trail = TRACKS.near(city_tracks, pos, float(r["p"]["aggro"]) * 2.0, time, life, who)
		if not trail.is_empty():
			break
	if trail.is_empty():
		# следов нет — прочёсывает расходящимся кольцом от логова
		if float(r.get("sk_retarget", 0.0)) <= 0.0:
			var age := float(int(day) - _seeker_day + 1)
			var ring: float = float(map.ts) * 6.0 * age
			var ang := _raid_rng.randf() * TAU
			r["sk_goal"] = (hive["pos"] as Vector2) + Vector2(cos(ang), sin(ang)) * ring
			r["sk_retarget"] = 5.0
		r["sk_retarget"] = float(r["sk_retarget"]) - mv
	else:
		r["sk_goal"] = trail["pos"]
	# дошла до жилья — точная метка и бегом в логово
	if pos.distance_to(map.tile_center_px(map.spawn_tile)) < float(map.ts) * 7.0 \\
			or _seeker_near_building(pos):
		r["sk_state"] = "home"
		r["sk_goal"] = pos
		return true
	var goal: Vector2 = r.get("sk_goal", hive["pos"]) as Vector2
	if not _raider_move_to(r, map.tile_of_px(goal), speed):
		r["sk_retarget"] = 0.0   # путь перекрыт — ищет новую цель
	return true


## Есть ли жильё в паре тайлов от точки (ищейка вышла к городу).
func _seeker_near_building(pos: Vector2) -> bool:
	var t: Vector2i = map.tile_of_px(pos)
	for b in buildings:
		if _active(b) and Vector2((b["tile"] as Vector2i) - t).length() < 2.5:
			return true
	return false


## Ищейка добирается до логова.
func _seeker_reach_home(r: Dictionary, speed: float) -> bool:
	var home: Vector2 = hive["pos"] as Vector2
	if (r["pos"] as Vector2).distance_to(home) < float(map.ts):
		return true
	return _raider_move_to(r, map.tile_of_px(home), speed)


## ==================== УЛЕЙ: УРОН (перенесено из nature) ====================
## Улей бьют (удар героя по позиции улья в дуге; v2.2 — и странствующие охотники).
func _hive_take_damage(dmg: int) -> void:
	hive["hp"] = float(hive["hp"]) - float(dmg)
	if float(hive["hp"]) > 0.0:
		return
	var level: int = int(hive["level"])
	var loot: Dictionary = HiveSim.loot_for(level)
	for key in loot:
		res[key] = float(res.get(key, 0.0)) + float(loot[key])
	events.append({"type": "hive_destroyed", "level": level})
	_chron("chron.hive_destroyed", str(level))
	# юниты без дома бросают роли и разбегаются (остаются как волна)
	for r in raiders:
		if not String(r.get("role", "")).is_empty():
			r.erase("role")
			r["mode"] = "advance"
	hive = {"active": false, "respawn_day": float(day) + float(HiveSim.RESPAWN_DAYS),
			"pos": hive.get("pos", Vector2.ZERO), "tile": hive.get("tile", map.anomaly_tile)}


## ==================== СТРАНСТВУЮЩИЕ ОХОТНИКИ (v2.2 п.1) ====================
## Чужой отряд на чудовищ: приходит с края после волны (_try_spawn_hunt_squad),
## сам штурмует улей (рубит стражей, колупает улей), городу — доля добычи.
## Чемпиона не заменяет: тот остаётся отдельным редким событием (v2.1).
func hunt_squad_daily() -> void:
	if hunter_squad.is_empty():
		return
	var state := String(hunter_squad.get("state", ""))
	if state == "come" and int(day) >= int(hunter_squad["eta_day"]):
		var hcfg: Dictionary = cfg.get("hunt_squad", {})
		var edge: Vector2i = hunter_squad["edge"]
		var def: Dictionary = {}
		if _enemies_cfg.is_empty():
			var ed: Variant = _read_json_file("res://data/enemies.json")
			_enemies_cfg = ed if ed is Array else []
		for d2 in _enemies_cfg:
			if String(d2["id"]) == "wander_hunter":
				def = d2
				break
		if not def.is_empty():
			for i in int(hcfg.get("members", 3)):
				var px: Vector2 = map.tile_center_px(edge)
				var u := {
					"id": _next_id, "type": "wander_hunter", "p": def,
					"hp": int(def["hp"]), "max_hp": int(def["hp"]),
					"pos": px, "target": Vector2i(-1, -1), "path": PackedVector2Array(),
					"atk_cd": 0.0, "mode": "", "role": "hunt_ally",
					"ha_state": "march", "ha_edge": px, "ha_win": false,
				}
				_next_id += 1
				raiders.append(u)
		hunter_squad["state"] = "assault"
		events.append({"type": "hunt_squad_here"})
		_chron("chron.hunt_squad_here")
	elif state == "assault":
		var left := 0
		for r2 in raiders:
			if String(r2.get("role", "")) == "hunt_ally":
				left += 1
		if left == 0:
			hunter_squad = {}


## Тик странствующего охотника (ветка "hunt_ally" в _raider_update).
func _hunt_ally_update(r: Dictionary, mv: float) -> bool:
	var speed: float = float(r["p"]["speed"]) * mv
	match String(r.get("ha_state", "march")):
		"march":
			if hive.is_empty() or not bool(hive.get("active", false)):
				r["ha_state"] = "leave"
				return true
			var home: Vector2 = hive["pos"] as Vector2
			if (r["pos"] as Vector2).distance_to(home) < float(map.ts) * 1.5:
				# у логова: колупает улей и рубит его обитателей
				_hive_take_damage(int(round(float(r["p"]["damage"]) * mv * 1.2)))
				var near: Array = []
				for u in raiders:
					if String(u.get("role", "")) in ["guard", "gatherer", "scout", "seeker"] \\
							and (u["pos"] as Vector2).distance_to(r["pos"] as Vector2) < float(map.ts):
						near.append(u)
				for u2 in near:
					_hit_raider(u2, int(r["p"]["damage"]), Vector2i(-9999, -9999), "hunt_ally")
				if not bool(r.get("ha_win", false)) \\
						and (hive.is_empty() or not bool(hive.get("active", false))):
					# логово разорено охотниками — городу доля добычи
					r["ha_win"] = true
					var share: Dictionary = HiveSim.loot_for(int(hive.get("level", 1)))
					_add_resource_capped("food", float(share.get("food", 0)) * 0.5)
					_add_resource_capped("crystal", float(share.get("crystal", 0)) * 0.5)
					if coins_sink.is_valid():
						coins_sink.call(int(float(share.get("coins", 0)) * 0.5))
					events.append({"type": "hunt_squad_win"})
					_chron("chron.hunt_squad_win")
				return true
			return _raider_move_to(r, map.tile_of_px(home), speed)
		"leave":
			var edge: Vector2 = r.get("ha_edge", Vector2.ZERO) as Vector2
			if (r["pos"] as Vector2).distance_to(edge) < float(map.ts):
				return false   # ушёл с карты
			return _raider_move_to(r, map.tile_of_px(edge), speed)
	return true
'''
w = w.rstrip("\n") + "\n" + tail
io.open(pw, "w", encoding="utf-8", newline="\n").write(w)
print("war: hooks fixed, functions moved in")
