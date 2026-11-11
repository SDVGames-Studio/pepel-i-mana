# Часть: данж-лут, метр угрозы, волны мутантов и осады, стражи и спарринг.
# Структура v1.62.0: бывший city_sim_threat.gd разрезан на extends-цепочку
# war -> nature -> threat — это один класс, поведение не меняется.
extends "res://scripts/city_sim_stories.gd"

# --- добыча из данжа -----------------------------------------------------

## Рюкзак героя в пул города (пункт плана M2). Замапленные предметы уходят из
## рюкзака, остальное (руны, снаряжение) в нём остаётся. Возвращает добавленное.
func deposit_loot(inventory: Array) -> Dictionary:
	var pool_map: Dictionary = cfg["loot_to_pool"]
	var added := {}
	var i := 0
	while i < inventory.size():
		var stack: Dictionary = inventory[i]
		var item_id := String(stack["id"])
		if not pool_map.has(item_id):
			i += 1
			continue
		var key := String(pool_map[item_id])
		var want := int(stack["count"])
		# накопление без лимита (заказчик, 2026-10-25)
		res[key] = float(res[key]) + want
		added[key] = int(added.get(key, 0)) + want
		inventory.remove_at(i)
	return added


# --- угрозы и оборона (M5) --------------------------------------------------



## Сила угрозы: растёт со временем и размером города (ТЗ 4.3, решение №12).
func threat_value() -> float:
	var tcfg: Dictionary = cfg.get("threat", {})
	var city_value := 0
	for b in buildings:
		if _active(b):
			city_value += 1
	city_value += residents.size()
	return maxf(0.0, float(day - int(tcfg.get("start_day", 3.0)))) * float(tcfg.get("day_growth", 0.35)) \
			+ float(city_value) * float(tcfg.get("city_growth", 0.08))


## Стадия угрозы для HUD: calm / unease / danger / siege.
func threat_stage() -> String:
	var tcfg: Dictionary = cfg.get("threat", {})
	var v := threat_value()
	if v >= float(tcfg.get("siege_from_threat", 8.0)):
		return "siege"
	if v >= 3.0:
		return "danger"
	if v >= float(tcfg.get("min_threat", 1.0)):
		return "unease"
	return "calm"


## Сколько дней до следующей волны (для индикатора HUD).
func raid_eta_days() -> float:
	if raid_active:
		return 0.0
	return maxf(0.0, (_next_raid_at - time) / float(cfg["day_length"]))


func _schedule_next_raid() -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	# мутанты из аномалии ходят по ровному расписанию — каждые raid_every_days
	# дней, пока данж у города не зачищен (заказчик 2026-10-21); зачистка
	# сдвигает следующую волну на clear_raid_delay_days — время перезарядки данжа
	_raid_gap_days = maxf(0.5, float(tcfg.get("raid_every_days", 10.0)))
	# первая волна — не раньше start_day, как бы ни разросся город (заказчик: на 4-й день пришла)
	_next_raid_at = maxf(maxf(time + _raid_gap_days * float(cfg["day_length"]),
			float(tcfg.get("start_day", 10.0)) * float(cfg["day_length"]) + 1.0),
			_raid_not_before)
	_raid_warned = false


## Данж у города зачищен (все монстры уничтожены): атаки сдвигаются на
## clear_raid_delay_days — столько длится перезарядка данжа рядом с городом.
func delay_raids_after_dungeon_clear() -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	var delay: float = maxf(float(tcfg.get("raid_every_days", 10.0)),
			float(tcfg.get("clear_raid_delay_days", 20.0)))
	_raid_not_before = maxf(_raid_not_before, time + delay * float(cfg["day_length"]))
	if not raid_active and _next_raid_at < _raid_not_before:
		_next_raid_at = _raid_not_before
		_raid_warned = false
	_raid_gap_days = maxf(_raid_gap_days, delay)   # индикатор ETA не врёт
	events.append({"type": "dungeon_calm", "days": int(delay)})


## Планировщик волн: предупреждение за warn_fraction интервала, затем атака.
const HiveSim := preload("res://scripts/hive_sim.gd")

func _update_threat(dt: float, day_len: float) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	if tcfg.is_empty():
		return
	_update_hive(dt, day_len)
	_update_hive_units(dt, tcfg)
	if hero_alive and not hive.is_empty():
		# следы героя: скауты улья читают цепочку (прототип TrackManager)
		hero_tracks = HiveSim.push_track(hero_tracks, hero_pos, float(time),
				float(map.ts) * 4.0)
	if raid_active:
		_update_raid(dt, day_len)
		return
	if _next_raid_at <= 0.0:
		_schedule_next_raid()
		return
	var warn_at: float = _next_raid_at - float(tcfg.get("warn_fraction", 0.3)) * _raid_gap_days * day_len
	if not _raid_warned and time >= warn_at:
		_raid_warned = true
		events.append({"type": "raid_warn", "eta": raid_eta_days()})
		return
	if time >= _next_raid_at:
		if float(day) < float(tcfg.get("start_day", 10.0)) \
				or threat_value() < float(tcfg.get("min_threat", 1.0)):
			_next_raid_at = time + 0.5 * day_len   # город ещё мал или рано — мутанты не идут
			return
		var siege := threat_value() >= float(tcfg.get("siege_from_threat", 8.0)) \
				and _raid_rng.randf() < float(tcfg.get("siege_chance", 0.35))
		var size := int(float(tcfg.get("raid_size_base", 2)) + threat_value() * float(tcfg.get("raid_size_threat", 0.3)))
		size = clampi(size, 1, int(tcfg.get("raid_size_max", 10)))
		if siege:
			size += int(tcfg.get("siege_size_bonus", 4))
		_spawn_raid(size, siege)


## Волна мутантов из аномалии: size тварей, siege — осада покрупнее.
func _spawn_raid(size: int, siege: bool) -> void:
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var tcfg: Dictionary = cfg.get("threat", {})
	raid_active = true
	raid_siege = siege
	_raid_kind = "mutant"
	raid_count += 1
	razed_this_raid = 0
	# каждая следующая волна чуть крепче (заказчик), но размер жёстко ограничен —
	# мутанты из данжа ослаблены (2026-10-21): без выхода размера за потолок
	var wave_no := raid_count - 1
	size = clampi(size + wave_no * int(tcfg.get("wave_growth_size", 1)), 1,
			int(tcfg.get("raid_size_max", 6)))
	# v1.45: выбросы эпицентра усиливают мутантов (power приходит событием)
	var eruption := 1.0 + 0.2 * float(eruption_power)
	var hp_mult := (1.0 + threat_value() * float(tcfg.get("hp_per_threat", 0.04))
			+ float(wave_no) * float(tcfg.get("wave_growth_hp", 0.15))) * eruption
	for i in size:
		var def := _pick_raider_def(tcfg)
		if def.is_empty():
			break
		var hp := int(round(float(def["hp"]) * hp_mult))
		raiders.append({
			"id": _next_id, "type": String(def["id"]), "p": def,
			"hp": hp, "max_hp": hp,
			"pos": _spawn_tile_near_anomaly(),
			"target": Vector2i(-1, -1), "path": PackedVector2Array(),
			"atk_cd": 0.0, "mode": "advance",
		})
		_next_id += 1
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + float(tcfg.get("raid_mood", -15.0)), 0.0, 100.0)
	events.append({"type": "raid_start", "siege": siege, "count": raiders.size()})
	_chron("chron.raid_siege" if siege else "chron.raid", str(raiders.size()))
	_update_gates()   # ворота захлопываются


func _pick_raider_def(tcfg: Dictionary) -> Dictionary:
	var weights: Dictionary = tcfg.get("enemy_weights", {})
	var total := 0
	for w: int in weights.values():
		total += w
	var roll := _raid_rng.randi_range(1, maxi(1, total))
	for def: Dictionary in _enemies_cfg:
		roll -= int(weights.get(String(def["id"]), 0))
		if roll <= 0:
			return def
	return _enemies_cfg[0] if not _enemies_cfg.is_empty() else {}


func _spawn_tile_near_anomaly() -> Vector2:
	for attempt in 40:
		var off := Vector2i(_raid_rng.randi_range(-3, 3), _raid_rng.randi_range(-3, 3))
		var tile: Vector2i = map.anomaly_tile + off
		if map.is_walkable(tile):
			return map.tile_center_px(tile)
	return map.tile_center_px(map.anomaly_tile)


## Тик волны: движение мутантов, атаки по герою и зданиям, огонь вышек.
func _update_raid(dt: float, _day_len: float) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	_shoot_towers(dt, tcfg)
	var i := 0
	while i < raiders.size():
		var r: Dictionary = raiders[i]
		# v1.44: юниты улья живут вне жизненного цикла волны
		if not String(r.get("role", "")).is_empty():
			raiders.remove_at(i)
			continue
		if not _raider_update(r, dt, tcfg):
			raiders.remove_at(i)
			continue
		i += 1
	if raid_active and _wave_raiders_left() == 0:
		_raid_end(true)
		return
	if razed_this_raid >= int(tcfg.get("defeat_razes", 3)):
		_raid_end(false)


## Вышка со стражем бьёт ближайшего мутанта в радиусе (страж реально воюет).
func _shoot_towers(dt: float, tcfg: Dictionary) -> void:
	# дисциплина «Оборона» (M7): дальность и урон вышек растут
	var range_px := (float(tcfg.get("tower_range", 4.5)) + research_sum("tower_range")) * float(map.ts)
	for b in buildings:
		if not bool(b["done"]) or _def(b).get("effect", "") != "guard" or int(b["worker"]) <= 0:
			continue
		if float(b.get("stun_left", 0.0)) > 0.0:
			continue
		b["cd"] = float(b.get("cd", 0.0)) - dt
		if float(b["cd"]) > 0.0:
			continue
		var target: Dictionary = _nearest_raider(map.tile_center_px(b["tile"]), range_px)
		if target.is_empty():
			continue
		b["cd"] = float(tcfg.get("tower_cd", 1.2))
		# комплект стража усиливает и выстрелы его вышки
		var mult := 1.0
		var worker := _resident_by_id(int(b["worker"]))
		if not worker.is_empty() and bool(worker.get("kit", false)):
			mult = float(tcfg.get("kit_damage_mult", 2.0))
		if has_law("martial_law"):
			mult *= float(law_param("martial_law", "tower_mult", 1.0))   # военное положение (M14-H)
		# v1.36: вышка на плато бьёт сверху с бонусом высоты (№113)
		_hit_raider(target, int(round((float(tcfg.get("tower_damage", 2)) + research_sum("tower_damage")) * mult)),
				b["tile"])


func _nearest_raider(from_px: Vector2, radius_px: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius_px
	for r in raiders:
		var d: float = (r["pos"] as Vector2).distance_to(from_px)
		if d < best_d:
			best_d = d
			best = r
	return best


## ИИ мутанта: герой рядом и достижим — дерётся с героем; здание в досягаемости —
## ломает; путь к центру открыт — идёт; заперт стеной — идёт к ближайшей стене/воротам.
## v1.26 (правки приёмки): герой за стеной больше не «прилипает» мутанта к месту —
## без пути до героя ИИ проваливается к преградам и ломает их; пустой путь
## пересчитывается по таймеру — разрушенная стена выпускает волну.
## M11: духи леса в режиме «hunt» гонятся за своей жертвой (лесорубом/каменотёсом).
## Возвращает false, если мутант погиб или волне нечего делать (убрать из списка).
func _raider_update(r: Dictionary, dt: float, tcfg: Dictionary) -> bool:
	if int(r["hp"]) <= 0:
		return false
	r["atk_cd"] = maxf(0.0, float(r["atk_cd"]) - dt)
	# v1.49: корни/чума героя — движение вдвое медленнее, пока действует
	var mv := dt
	if float(r.get("slow_left", 0.0)) > 0.0:
		r["slow_left"] = maxf(0.0, float(r["slow_left"]) - dt)
		mv = dt * 0.5
	var p: Dictionary = r["p"]
	# v1.44: юниты улья — свои роли поверх общего боевого каркаса
	match String(r.get("role", "")):
		"gatherer":
			return _hive_gatherer_update(r, mv)
		"scout":
			return _hive_scout_update(r, mv)
		"guard":
			return _hive_guard_update(r, mv, tcfg)
	if String(r.get("mode", "")) == "hunt":
		return _spirit_update(r, mv)
	# герой в городе и рядом — мутант отвлекается на чемпиона (путь как у жителей:
	# напрямую он резал бы углы сквозь скалы — заказчик видел проходы насквозь);
	# путь к герою закрыт стеной — мутант не толчётся у стены, а ломает её
	if hero_alive:
		var to_hero: Vector2 = hero_pos - (r["pos"] as Vector2)
		var hero_d: float = to_hero.length()
		if hero_d <= float(p["aggro"]):
			if hero_d <= float(p["attack_range"]) + 12.0:
				if float(r["atk_cd"]) <= 0.0:
					r["atk_cd"] = float(p["attack_cooldown"])
					# v1.36: герой на плато — мутант снизу бьёт слабее (№113)
					var hero_dmg := int(round(float(p["damage"])
							* map.plateau_def_mult(map.tile_of_px(r["pos"]), map.tile_of_px(hero_pos))))
					events.append({"type": "hero_hit", "dmg": hero_dmg})
				return true
			if _raider_move_to(r, map.tile_of_px(hero_pos), float(p["speed"]) * mv):
				return true
	# v1.46 («Новый мир v2» этап 4): герой далеко или его нет — мутанты
	# переключаются на ближайшего жителя (город перестаёт быть невидимым)
	var hero_d2: float = (r["pos"] as Vector2).distance_to(hero_pos) if hero_alive else 1e9
	var vic: Dictionary = {}
	# в автотестах таргетинг жителей выключен (осадные тесты считают стены)
	if not (OS.has_environment("PEPEL_TEST_MAPS") and not OS.has_environment("PEPEL_HIVE_ON")) 			and (not hero_alive or hero_d2 > float(p["aggro"])):
		vic = _nearest_resident(r["pos"], float(p["aggro"]) * 1.5)
		if OS.get_environment("RAIDER_DEBUG") != "":
			print("[raider] role=%s vic=%s state=%s" % [
					String(r.get("role", "")), String(vic.get("name", "-")),
					String(vic.get("state", ""))])
	if not vic.is_empty():
		var to_v: Vector2 = (vic["pos"] as Vector2) - (r["pos"] as Vector2)
		if to_v.length() <= float(p["attack_range"]) + 10.0:
			if float(r["atk_cd"]) <= 0.0:
				r["atk_cd"] = float(p["attack_cooldown"])
				if _event_rng.randf() < 0.5:
					_make_ail(vic, "wounded", "chron.wounded")
					events.append({"type": "mutant_hit", "name": String(vic["name"])})
				else:
					vic["mood"] = clampf(float(vic["mood"]) - 12.0, 0.0, 100.0)
			return true
		if _raider_move_to(r, map.tile_of_px(vic["pos"]), float(p["speed"]) * mv):
			return true
	var reach := float(p["attack_range"]) + float(map.ts) * 0.5
	# здание в пределах досягаемости — крушим (иначе осцилляция «центр ↔ стена»:
	# обходной путь всегда существует, и мутант ни разу не ударит)
	var near := _raider_near_building(r)
	if not near.is_empty() and bld_dist_px(r["pos"], near) <= reach:
		if float(r["atk_cd"]) <= 0.0:
			r["atk_cd"] = float(p["attack_cooldown"])
			var mult := float(tcfg.get("brute_bld_mult", 3.0)) if String(r["type"]) == "brute" else 1.0
			if _damage_building(near, float(p["damage"]) * mult):
				razed_this_raid += 1
				# v1.47: ПРОРЫВ — паника: все, кто снаружи, бегут домой
				if not raid_breached:
					raid_breached = true
					events.append({"type": "raid_panic"})
		return true
	# путь к центру открыт — идём (проверка не каждый тик: A* по обнесённой
	# стенами карте дорог — так держим FPS и в осаду, правки приёмки v1.26)
	r["_center_cd"] = float(r.get("_center_cd", 0.0)) - dt
	if float(r["_center_cd"]) <= 0.0:
		r["_center_cd"] = 0.4
		r["_center_open"] = map.path_px(r["pos"], map.spawn_tile, true).size() > 1
	if bool(r.get("_center_open", false)) \
			and _raider_move_to(r, map.spawn_tile, float(p["speed"]) * mv):
		return true
	# заперты в кольце: идём ломать ближайшую стену или ворота
	return _raider_break_obstacle(r, mv, p, near)


## Ближайшее к мутанту действующее здание (кэш на _near_gap секунд: скан всех
## зданий каждый тик всей волной — заметная цена на большой карте).
## v1.46: ближайший житель ПОД ОТКРЫТЫМ небом (inside==0) в радиусе.
func _nearest_resident(from_px: Vector2, radius_px: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius_px
	for v in residents:
		if int(v.get("inside", 1)) != 0 or String(v.get("state", "")) in ["sick", "wounded", "child"]:
			continue
		var d: float = (v["pos"] as Vector2).distance_to(from_px)
		if d < best_d:
			best_d = d
			best = v
	return best


func _raider_near_building(r: Dictionary) -> Dictionary:
	var b: Dictionary = r.get("_near_bld", {})
	if not b.is_empty() and _active(b):
		return b
	if time < float(r.get("_near_at", 0.0)):
		return {}
	b = _nearest_building_of(r, [])
	r["_near_bld"] = b
	r["_near_at"] = time + 0.25
	return b


## Мутант заперт: идёт к ближайшей стене/воротам и ломает их.
## False — ломать нечего (города нет), true — занят преградой.
func _raider_break_obstacle(r: Dictionary, dt: float, p: Dictionary, near: Dictionary) -> bool:
	var b := _nearest_building_of(r, ["wall", "gate"])
	if b.is_empty():
		b = near
	if b.is_empty():
		return false   # город пуст — волне нечего делать
	var goal := _walkable_next_to_rect(b)
	if goal == Vector2i(-1, -1):
		return true
	_raider_move_to(r, goal, float(p["speed"]) * dt)
	return true


## Движение мутанта по кэшированному пути (как у жителей): без кэша путь
## перестраивается каждый тик и мутант дёргается на границе тайла на месте.
## v1.26: пустой путь пересчитывается по таймеру (раз в полсекунды) — стены
## рушатся, ворота отпираются, и волна продолжает путь, а не встаёт навсегда.
## Возвращает false, если пути нет (замурован) — ИИ переключается на преграду.
func _raider_move_to(r: Dictionary, tile: Vector2i, step: float) -> bool:
	var path: PackedVector2Array = r["path"]
	if r["target"] != tile:
		r["target"] = tile
		r["path"] = map.path_px(r["pos"], tile, true)
		path = r["path"]
	elif path.is_empty() and time >= float(r.get("_repath_at", 0.0)):
		r["path"] = map.path_px(r["pos"], tile, true)
		r["_repath_at"] = time + 0.5
		path = r["path"]
	var here: Vector2i = map.tile_of_px(r["pos"])
	if here == tile:
		r["path"] = PackedVector2Array()
		return true   # пришли
	if path.is_empty():
		# стоит на СПЛОШНОМ для мутантов тайле (ворота заперли под ногами,
		# стену достроили) — сходит на ближайшую свободную клетку
		if map.is_solid(here, true):
			var free := _nearest_raider_walkable(here)
			if free != Vector2i(-1, -1):
				r["pos"] = map.tile_center_px(free)
				r["target"] = Vector2i(-1, -1)
				r["path"] = PackedVector2Array()
		return false
	var pos: Vector2 = r["pos"]
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
	r["pos"] = pos
	r["path"] = path
	return true


## Ближайшая клетка, проходимая для мутантов (спираль до радиуса 3).
func _nearest_raider_walkable(tile: Vector2i) -> Vector2i:
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n: Vector2i = tile + Vector2i(dx, dy)
				if map.is_raider_walkable(n):
					return n
	return Vector2i(-1, -1)


## Ближайшее к мутанту готовое здание с эффектом из wanted (пустой — любое).
func _nearest_building_of(r: Dictionary, wanted: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if not _active(b):
			continue   # руины мутанты не бьют (этап 2, аспект 5)
		if not wanted.is_empty() and not (String(_def(b).get("effect", b.get("type", ""))) in wanted):
			continue
		var d: float = bld_dist_px(r["pos"], b)
		if d < best_d:
			best_d = d
			best = b
	return best


func _walkable_next_to(tile: Vector2i) -> Vector2i:
	for n in [tile + Vector2i(1, 0), tile + Vector2i(-1, 0), tile + Vector2i(0, 1), tile + Vector2i(0, -1)]:
		if map.is_walkable(n):
			return n
	return Vector2i(-1, -1)


## Урон мутанту (вышка, страж, герой). Слабость к школе не учитывается — урон физический.
## v1.23: павший с телом остаётся останками — их унесут на кладбище;
## духи, призраки и элементали бесплотны, от них не остаётся даже костей.
## v1.36: src_tile — откуда нанесён удар (оборонный бонус плато, №113):
## атакующий сверху бьёт больнее, по защитнику сверху — слабее.
## v1.49: killer — «hero» для рук героя: убийство качает навыки (как в данже).
func _hit_raider(r: Dictionary, dmg: int, src_tile := Vector2i(-9999, -9999), killer := "") -> void:
	var mult := 1.0
	if src_tile != Vector2i(-9999, -9999):
		mult = map.plateau_def_mult(src_tile, map.tile_of_px(r["pos"]))
	dmg = int(round(float(dmg) * mult))
	r["hp"] = int(r["hp"]) - dmg
	if int(r["hp"]) <= 0:
		if killer == "hero" and r["p"].has("xp"):
			events.append({"type": "hero_kill", "xp": int(r["p"]["xp"]),
					"kind": String(r["type"])})
		_drop_corpse(r)
		raiders.erase(r)


## Боевое заклинание героя в городе: урон рейдерам в круге (max_targets 0 = все,
## иначе — БЛИЖАЙШИЕ N, как цепная молния). Возвращает {hits, dmg} —
## суммарный урон (для «высасывания жизни»).
func hero_spell_burst(pos_px: Vector2, radius_px: float, dmg: int, max_targets := 0) -> Dictionary:
	var hits := 0
	var total := 0
	var hero_tile: Vector2i = map.tile_of_px(pos_px)
	var cand: Array = []
	for r in raiders:
		if (r["pos"] as Vector2).distance_to(pos_px) <= radius_px:
			cand.append(r)
	if max_targets > 0 and cand.size() > max_targets:
		cand.sort_custom(func(a, b): return (a["pos"] as Vector2).distance_to(pos_px) \
				< (b["pos"] as Vector2).distance_to(pos_px))
		cand = cand.slice(0, max_targets)
	for r in cand:
		var before: int = int(r["hp"])
		_hit_raider(r, dmg, hero_tile, "hero")
		total += before - maxi(0, int(r["hp"]))
		hits += 1
	if raid_active and _wave_raiders_left() == 0:
		_raid_end(true)
	return {"hits": hits, "dmg": total}


## Корни/чума: замедлить рейдеров в круге (движение ×0.5 на duration сек).
func slow_raiders_at(pos_px: Vector2, radius_px: float, duration: float) -> int:
	var n := 0
	for r in raiders:
		if (r["pos"] as Vector2).distance_to(pos_px) <= radius_px:
			r["slow_left"] = maxf(float(r.get("slow_left", 0.0)), duration)
			n += 1
	return n


## Останки павшего врага (v1.23): бесплотные (cemetery.bodiless — духи,
## призраки, элементали) не оставляют тела; первая могила, даже вражья,
## основывает кладбище.
func _drop_corpse(r: Dictionary) -> void:
	var ccfg: Dictionary = cfg.get("cemetery", {})
	if ccfg.is_empty():
		return
	var kind := String(r.get("type", ""))
	if kind == "" or (ccfg.get("bodiless", []) as Array).has(kind):
		return
	if cemetery_tile == Vector2i(-1, -1) and _done_building_of_type("cemetery").is_empty():
		var f := _found_cemetery_tile()
		if f == Vector2i(-1, -1):
			return   # места под кладбище не нашлось — останки истлеют на месте
		cemetery_tile = f
		events.append({"type": "cemetery_founded"})
		_chron("chron.cemetery_founded")
	corpses.append({"tile": map.tile_of_px(r["pos"]), "kind": kind, "rot": 0.0})



## Сколько осталось участников ВОЛНЫ (юниты улья не считаются).
func _wave_raiders_left() -> int:
	var n := 0
	for r in raiders:
		if String(r.get("role", "")).is_empty():
			n += 1
	return n


## Конец волны: true — отбита (награда), false — осада удалась (город понёс потери).
## M11: награда и переналадка мутантских волн — только для волн мутантов;
## лес и неспокойные духи не трогают расписание угроз.
func _raid_end(defended: bool) -> void:
	var kind := _raid_kind
	raid_active = false
	raid_breached = false
	# v1.44: юнитов улья не вычищаем — они живут вне волны
	raiders = raiders.filter(func(r): return not String(r.get("role", "")).is_empty())
	var tcfg: Dictionary = cfg.get("threat", {})
	if kind == "mutant":
		if defended:
			var reward := int(tcfg.get("reward_crystals", 2))
			_add_resource_capped("crystal", reward)
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(tcfg.get("repelled_mood", 8.0)), 0.0, 100.0)
			events.append({"type": "raid_repelled", "crystals": reward})
			_chron("chron.repelled")
		else:
			events.append({"type": "raid_breached", "razed": razed_this_raid})
			_chron("chron.breach")
		razed_this_raid = 0
		_schedule_next_raid()
		_update_gates()   # ворота снова по правилу стража
		return
	# лес (M11): духи ушли или перебиты — лес немного успокаивается
	var fcfg: Dictionary = cfg.get("forest", {})
	if defended:
		forest_anger = maxf(0.0, forest_anger - float(fcfg.get("anger_per_tree", 2.5)) * 4.0)
		if kind == "forest":
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + 6.0, 0.0, 100.0)
			events.append({"type": "forest_repelled"})
			_chron("chron.forest_repelled")
		elif kind == "undead":
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(tcfg.get("repelled_mood", 8.0)), 0.0, 100.0)
			events.append({"type": "raid_repelled", "crystals": 0})
			_chron("chron.repelled")
	else:
		# духам всё же надоели рабочие / мёртвые разграбили город
		if kind == "forest":
			forest_anger = maxf(0.0, forest_anger - float(fcfg.get("anger_per_tree", 2.5)) * 6.0)
	razed_this_raid = 0
	_update_gates()


## Дневной бросок: город держит стражей — двое на постоянке (день и ночь),
## больше при росте населения; берут свободных взрослых, если есть еда (заказчик).
func _roll_guards() -> void:
	var gcfg: Dictionary = cfg.get("guards", {})
	if gcfg.is_empty():
		return
	var desired: int = int(gcfg.get("base", 2)) + residents.size() / maxi(1, int(gcfg.get("per_pop", 8)))
	var have := 0
	for r in residents:
		if String(r["prof"]) == "guard":
			have += 1
	if have >= desired or not _food_reserve_ok():
		return
	for r in residents:
		if have >= desired:
			break
		if String(r["prof"]) in ["", "elder", "guard", "hunter", "porter"] or String(r.get("ail", "")) != "":
			continue
		if r["bld"] != null or r["site"] != null:
			continue
		r["prof"] = "guard"
		r["bld"] = null
		r["site"] = null
		r["sub_prof"] = ""
		have += 1
		_chron("chron.guard_trained", String(r["name"]))
		events.append({"type": "guard_trained", "name": String(r["name"])})
	_assign_shifts()
	_assign_jobs()


## Смены стражей: первый — дневной, второй — ночной, дальше чередуются.
func _assign_shifts() -> void:
	var i := 0
	for r in residents:
		if String(r["prof"]) == "guard":
			r["shift"] = "day" if i % 2 == 0 else "night"
			i += 1


# --- спарринг стражей (v1.23) -------------------------------------------------

## Стражам нет другой работы — они тренируются друг с другом: пара сходится
## в свободном месте, обменивается условными ударами; растут боевой навык,
## сила и ловкость, дружба и настроение. False — партнёра или сил нет.
func _guard_spar(r: Dictionary, dt: float) -> bool:
	var scfg: Dictionary = cfg.get("spar", {})
	if scfg.is_empty() or raid_active or _raid_warned or is_night():
		return false
	if float(r.get("fatigue", 0.0)) >= float(scfg.get("max_fatigue", 0.75)) \
			or float(r.get("spar_until", 0.0)) > time:
		return false
	var partner := _resident_by_id(int(r.get("spar_with", -1)))
	if not _spar_partner_ok(partner) or int(partner.get("spar_with", -1)) != int(r["id"]):
		partner = _pick_spar_partner(r)
		if partner.is_empty():
			return false
		r["spar_with"] = int(partner["id"])
		partner["spar_with"] = int(r["id"])
		var spot := _spar_spot(r, partner)
		r["spar_tile"] = spot
		partner["spar_tile"] = spot
		r["spar_t"] = 0.0
		partner["spar_t"] = 0.0
	var tile: Vector2i = r.get("spar_tile", Vector2i(-1, -1))
	if tile == Vector2i(-1, -1):
		return false
	if not _arrived(r, tile) \
			or Vector2(r["pos"]).distance_to(partner["pos"]) > float(map.ts) * float(scfg.get("radius", 1.5)):
		_move_towards(r, tile, dt)
		r["state"] = "spar"
		return true
	# сошлись: лицом к партнёру, обмениваемся условными ударами
	r["dir"] = "left" if (partner["pos"] as Vector2).x < float(r["pos"].x) else "right"
	r["state"] = "spar"
	r["path"] = PackedVector2Array()
	r["spar_t"] = float(r.get("spar_t", 0.0)) + dt
	r["fatigue"] += dt / float(cfg["day_length"]) * float(scfg.get("fatigue", 0.35))
	r["spar_hit"] = float(r.get("spar_hit", 0.0)) - dt
	if float(r["spar_hit"]) <= 0.0:
		r["spar_hit"] = float(scfg.get("hit_cd", 1.5))
		_grow_combat(r, float(scfg.get("hit_cd", 1.5)))
	if float(r["spar_t"]) >= float(scfg.get("len", 0.18)) * float(cfg["day_length"]):
		_end_spar(r, partner)
	return true


## Годен ли текущий партнёр по спаррингу.
func _spar_partner_ok(partner: Dictionary) -> bool:
	return not partner.is_empty() and String(partner.get("prof", "")) == "guard" \
			and String(partner.get("ail", "")) == "" \
			and partner.get("site", null) == null \
			and float(partner.get("spar_until", 0.0)) <= time \
			and not raid_active and not _raid_warned


## Второй страж на тренировку: свободный (без стройки), не на спарринге с
## другим, не уставший, в радиусе seek клеток.
func _pick_spar_partner(r: Dictionary) -> Dictionary:
	var scfg: Dictionary = cfg.get("spar", {})
	var seek := float(scfg.get("seek", 40.0)) * float(map.ts)
	var best: Dictionary = {}
	var best_d := INF
	for other in residents:
		if other == r or String(other.get("prof", "")) != "guard":
			continue
		if String(other.get("ail", "")) != "" or other.get("site", null) != null:
			continue
		if int(other.get("spar_with", -1)) >= 0 and int(other.get("spar_with", -1)) != int(r["id"]):
			continue   # уже спаррингует с другим
		if float(other.get("spar_until", 0.0)) > time \
				or float(other.get("fatigue", 0.0)) >= float(scfg.get("max_fatigue", 0.75)):
			continue
		var st := String(other.get("state", ""))
		if not (st in ["idle", "patrol", "guard", "spar", "going", "leisure"]):
			continue
		var d: float = Vector2(other["pos"]).distance_to(r["pos"])
		if d <= seek and d < best_d:
			best_d = d
			best = other
	return best


## Место тренировки: свободная клетка на полпути между стражами.
func _spar_spot(a: Dictionary, b: Dictionary) -> Vector2i:
	var mid := ((a["pos"] as Vector2) + (b["pos"] as Vector2)) * 0.5
	return map.nearest_walkable(map.tile_of_px(mid))


## Тренировка окончена: перерыв обоим, настроение и дружба.
func _end_spar(r: Dictionary, partner: Dictionary) -> void:
	var scfg: Dictionary = cfg.get("spar", {})
	for who in [r, partner]:
		var w: Dictionary = who
		if int(w.get("spar_with", -1)) < 0:
			continue   # второй уже завершил тренировку
		w["spar_with"] = -1
		w["spar_tile"] = Vector2i(-1, -1)
		w["spar_t"] = 0.0
		w["spar_until"] = time + float(scfg.get("cd", 0.4)) * float(cfg["day_length"])
		w["mood"] = clampf(float(w["mood"]) + float(scfg.get("mood", 2.0)), 0.0, 100.0)
	_rel_change(r, partner, float(scfg.get("rel", 2.0)))
	_chron("chron.spar", String(r["name"]), String(partner["name"]))
	events.append({"type": "spar", "a": String(r["name"]), "b": String(partner["name"])})


## Дневной бросок: зверь водится, а охотника нет — свободный взрослый становится
## охотником (заказчик: никто не охотится, потому что профессию никто не давал).
func _roll_hunter() -> void:
	if animals.is_empty() or not _food_reserve_ok():
		return
	for r in residents:
		if String(r["prof"]) == "hunter" and String(r.get("ail", "")) == "":
			return   # охотник уже есть и на ногах
	for r in residents:
		if String(r["prof"]) in ["", "elder", "guard", "hunter", "porter"] or String(r.get("ail", "")) != "":
			continue
		if r["bld"] != null or r["site"] != null:
			continue
		r["prof"] = "hunter"
		r["bld"] = null
		r["site"] = null
		r["sub_prof"] = ""
		_chron("chron.hunter_trained", String(r["name"]))
		events.append({"type": "hunter_trained", "name": String(r["name"])})
		_assign_jobs()
		return
