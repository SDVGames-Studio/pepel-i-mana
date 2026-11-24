# -*- coding: utf-8 -*-
## v2.2 патч 5: nature-слой — ищейка улья, волны «не по воздуху»,
## странствующие охотники (спавн отряда и их тик через match в war).
import io, shutil, sys

p = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts\city_sim_nature.gd"
src = io.open(p, encoding="utf-8").read()
if "_hive_seeker_update" in src:
    print("ALREADY PATCHED")
    sys.exit(0)

# --- 1. улей создаётся с пустым знанием о городе ---
a1 = '''						"next_wave_day": float(day) + HiveSim.wave_days(1),
						"respawn_day": 0.0, "alert": 0.0}'''
assert a1 in src, "anchor1 (hive creation) missing"
r1 = '''						"next_wave_day": float(day) + HiveSim.wave_days(1),
						"city_known": {}, "respawn_day": 0.0, "alert": 0.0}'''
src = src.replace(a1, r1, 1)

# --- 2. ищейка: пока город не найден, улей держит одну ищейку ---
a2 = '''	# рост уровня от запаса
	var new_level: int = HiveSim.level_for(int(hive["stock"]))'''
assert a2 in src, "anchor2 (level growth) missing"
r2 = '''	# v2.2 п.3: ищейка — лагерь сам не знает, где город, пока не найдёт
	if (hive.get("city_known", {}) as Dictionary).is_empty():
		var has_seeker := false
		for su in raiders:
			if String(su.get("role", "")) == "seeker" and int(su["hp"]) > 0:
				has_seeker = true
				break
		if not has_seeker and int(day) - _seeker_day >= int(hcfg.get("seeker_gap_days", 2)):
			if _spawn_hive_unit("seeker") != null:
				_seeker_day = int(day)
	# рост уровня от запаса
	var new_level: int = HiveSim.level_for(int(hive["stock"]))'''
src = src.replace(a2, r2, 1)

# --- 3. волны из улья — только когда ищейка нашла город ---
a3 = '''	# волны: ресурс улья оплачивает набеги — чем удачнее сбор, тем сильнее
	if float(day) >= float(hive["next_wave_day"]) \\'''
assert a3 in src, "anchor3 (hive wave branch) missing"
r3 = '''	# v2.2 п.3: волны «не по воздуху» — ищейка должна привести логово к городу
	if (hive.get("city_known", {}) as Dictionary).is_empty():
		hive["next_wave_day"] = float(day) + HiveSim.wave_days(level)
		return
	# волны: ресурс улья оплачивает набеги — чем удачнее сбор, тем сильнее
	if float(day) >= float(hive["next_wave_day"]) \\'''
src = src.replace(a3, r3, 1)

# --- 4. новые функции в хвост ---
tail = '''

## ==================== ИЩЕЙКА УЛЬЯ (v2.2 п.3) ====================
## Лагерь мутантов не знает, где город: ищейка прочёсывает окрестность
## (кольцо растёт с днями поиска), идёт по свежим следам жителей; учует
## героя — бежит, оставляя логову «грязную» метку «примерно здесь»;
## дошла до жилья — несёт точную точку, и волны идут в цель, не «по воздуху».
const TRACKS := preload("res://scripts/city_tracks.gd")


func _hive_seeker_update(r: Dictionary, mv: float) -> bool:
	var speed: float = float(r["p"]["speed"]) * mv
	var pos := r["pos"] as Vector2
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
	var goal := r.get("sk_goal", hive["pos"]) as Vector2
	if not _raider_move_to(r, map.tile_of_px(goal), speed):
		r["sk_retarget"] = 0.0   # путь перекрыт — ищет новую цель
	return true


## Есть ли жильё в паре тайлов от точки (искейка вышла к городу).
func _seeker_near_building(pos: Vector2) -> bool:
	var t := map.tile_of_px(pos)
	for b in buildings:
		if _active(b) and Vector2((b["tile"] as Vector2i) - t).length() < 2.5:
			return true
	return false


## Ищейка добирается до логова.
func _seeker_reach_home(r: Dictionary, speed: float) -> bool:
	var home := hive["pos"] as Vector2
	if (r["pos"] as Vector2).distance_to(home) < float(map.ts):
		return true
	return _raider_move_to(r, map.tile_of_px(home), speed)


## ==================== СТРАНСТВУЮЩИЕ ОХОТНИКИ (v2.2 п.1) ====================
## Чужой отряд на чудовищ: приходит с края после волны (war._try_spawn_hunt_squad),
## сам штурмует улей (рубит стражей, колупает улей), забирает часть добычи —
## городу доля. Чемпиона не заменяет: тот остаётся отдельным редким событием.
func hunt_squad_daily() -> void:
	if hunter_squad.is_empty():
		return
	var state := String(hunter_squad.get("state", ""))
	if state == "come" and int(day) >= int(hunter_squad["eta_day"]):
		var hcfg: Dictionary = cfg.get("hunt_squad", {})
		var edge: Vector2i = hunter_squad["edge"]
		var def := {}
		for d2 in _enemies_def_list():
			if String(d2["id"]) == "wander_hunter":
				def = d2
				break
		if not def.is_empty():
			for i in int(hcfg.get("members", 3)):
				var px := map.tile_center_px(edge)
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


## Список врагов (кэш как у волн).
func _enemies_def_list() -> Array:
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	return _enemies_cfg


## Тик странствующего охотника (ветка "hunt_ally" в war._raider_update).
func _hunt_ally_update(r: Dictionary, mv: float) -> bool:
	var speed: float = float(r["p"]["speed"]) * mv
	match String(r.get("ha_state", "march")):
		"march":
			if hive.is_empty() or not bool(hive.get("active", false)):
				r["ha_state"] = "leave"
				return true
			var home := hive["pos"] as Vector2
			if (r["pos"] as Vector2).distance_to(home) < float(map.ts) * 1.5:
				# у логова: колупает улей и рубит его обитателей
				_hive_take_damage(float(r["p"]["damage"]) * mv * 1.2)
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
					var share := HiveSim.loot_for(int(hive.get("level", 1)))
					_add_resource_capped("food", float(share.get("food", 0)) * 0.5)
					_add_resource_capped("crystal", float(share.get("crystal", 0)) * 0.5)
					if coins_sink.is_valid():
						coins_sink.call(int(float(share.get("coins", 0)) * 0.5))
					events.append({"type": "hunt_squad_win"})
					_chron("chron.hunt_squad_win")
				return true
			return _raider_move_to(r, map.tile_of_px(home), speed)
		"leave":
			var edge := r.get("ha_edge", Vector2.ZERO) as Vector2
			if (r["pos"] as Vector2).distance_to(edge) < float(map.ts):
				return false   # ушёл с карты
			return _raider_move_to(r, map.tile_of_px(edge), speed)
	return true
'''

src = src.rstrip("\n") + "\n" + tail
shutil.copy(p, p + ".bak")
io.open(p, "w", encoding="utf-8", newline="\n").write(src)
print("OK city_sim_nature.gd")
