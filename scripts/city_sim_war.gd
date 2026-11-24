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
	_update_ambush_units(dt, tcfg)   # v1.80.1: засады на карте города
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
	# v1.83: спасённый караван — торговцы присылают обоз с подмогой
	if trader_support > 0:
		trader_support -= 1
		_add_resource_capped("food", 12.0)
		_add_resource_capped("wood", 10.0)
		_add_resource_capped("stone", 10.0)
		events.append({"type": "trader_support_arrived"})
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
		# v1.80.7: засадные юниты тоже мимо тика рейда (двойной тик = двойное
		# движение и A*; их ведёт _update_ambush_units)
		if bool(r.get("ambush", false)):
			i += 1
			continue
		if not String(r.get("role", "")).is_empty():
			# v1.80.7: ПРОПУСК, а не удаление — комментарий v1.44 «юниты улья
			# живут вне жизненного цикла волны», а код УДАЛЯЛ их каждый тик
			# рейда: во время волны улей пуст («улей пропал», фидбек)
			i += 1
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
		"seeker":
			return _hive_seeker_update(r, mv)
		"hunt_ally":
			return _hunt_ally_update(r, mv)
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
	# v2.1: чемпион города — та же приманка, что герой: держит волну на стенах
	if not (champion as Dictionary).is_empty() and bool(champion.get("alive", true)):
		var to_ch: Vector2 = (champion["pos"] as Vector2) - (r["pos"] as Vector2)
		var ch_d: float = to_ch.length()
		if ch_d <= float(p["aggro"]):
			if ch_d <= float(p["attack_range"]) + 12.0:
				if float(r["atk_cd"]) <= 0.0:
					r["atk_cd"] = float(p["attack_cooldown"])
					champion["hp"] = float(champion["hp"]) - float(p["damage"])
				return true
			if _raider_move_to(r, map.tile_of_px(champion["pos"] as Vector2),
					float(p["speed"]) * mv):
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
	# v1.70: если сухопутный обход ВОДЫ длиннее прямой линии в 2.5 раза —
	# волна предпочитает навести мост (приёмка: «мутанты должны уметь
	# строить мосты», «проход через воду только по мостам»)
	r["_center_cd"] = float(r.get("_center_cd", 0.0)) - dt
	if float(r["_center_cd"]) <= 0.0:
		r["_center_cd"] = 0.4
		var path: PackedVector2Array = map.path_px(r["pos"], map.spawn_tile, true)
		r["_center_open"] = path.size() > 1
		var line_tiles: float = Vector2(map.spawn_tile - map.tile_of_px(r["pos"])).length()
		r["_center_detour"] = float(path.size()) > line_tiles * 1.8
	if bool(r.get("_center_open", false)) \
			and not bool(r.get("_center_detour", false)) \
			and _raider_move_to(r, map.spawn_tile, float(p["speed"]) * mv):
		return true
	# путь перегорожен водой (или обход слишком долог) — волна наводит мост
	if _raider_try_bridge(r, mv, p):
		return true
	# заперты в кольце: идём ломать ближайшую стену или ворота
	return _raider_break_obstacle(r, mv, p, near)


## v1.70 «Мосты мутантов»: путь к городу перегорожен водой — волна наводит
## мост через ближайший водный тайл на линии к городу. Стройка занимает
## threat.bridge_build_time (по умолчанию 3 с); мост = map.bridges, как у
## жителей (M14-I), и сразу открывает путь (refresh_tile_solid).
func _raider_try_bridge(r: Dictionary, dt: float, p: Dictionary) -> bool:
	var w := _first_water_on_line(map.tile_of_px(r["pos"]), map.spawn_tile)
	if w == Vector2i(-1, -1):
		r.erase("bridge_p")
		r["mode"] = "advance"
		return false   # воды на линии нет — не наш случай
	var here: Vector2i = map.tile_of_px(r["pos"])
	var shore := _walkable_shore_next_to(w)
	if shore != here and shore != Vector2i(-1, -1):
		r["mode"] = "advance"
		_raider_move_to(r, shore, float(p["speed"]) * dt)
		return true
	# на берегу — строим (несколько мутантов строят параллельно свои тайлы)
	r["mode"] = "bridge"
	r["bridge_p"] = float(r.get("bridge_p", 0.0)) + dt
	if float(r["bridge_p"]) < float(cfg.get("threat", {}).get("bridge_build_time", 3.0)):
		return true
	r["bridge_p"] = 0.0
	r["mode"] = "advance"
	r["target"] = Vector2i(-1, -1)
	map.bridges[w] = true
	map.note_edit(w)
	map.refresh_tile_solid(w)
	events.append({"type": "monster_bridge"})
	_chron("chron.monster_bridge")
	return true


## Первый водный (без моста/брода) тайл на прямой от мутанта к цели.
func _first_water_on_line(from_tile: Vector2i, to_tile: Vector2i) -> Vector2i:
	var a := Vector2(from_tile) + Vector2(0.5, 0.5)
	var b := Vector2(to_tile) + Vector2(0.5, 0.5)
	var dir := (b - a)
	var dist := dir.length()
	if dist < 0.5:
		return Vector2i(-1, -1)
	dir /= dist
	var steps := int(dist / 0.5)
	for i in steps:
		var t := Vector2i(((a + dir * (float(i) * 0.5)) - Vector2(0.5, 0.5)).round())
		if not map.in_bounds(t):
			return Vector2i(-1, -1)
		if map.grid[t.y][t.x] == map.TILE_WATER and not map.bridges.has(t) \
				and not map.fords.has(t):
			return t
	return Vector2i(-1, -1)


## Сухой проходимый берег рядом с водным тайлом (ближе к мутанту).
func _walkable_shore_next_to(w: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var t: Vector2i = w + d
		if map.in_bounds(t) and map.is_walkable(t) \
				and map.grid[t.y][t.x] != map.TILE_WATER:
			return t
	return Vector2i(-1, -1)


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
	# v1.80.7: засадные юниты (ambush) живут вне волн — раньше они
	# считались волновыми, и рейд улья НЕ ЗАКАНЧИВАЛСЯ, пока жива хоть
	# одна засада: raid_active зависал, юниты улья удалялись каждый тик
	# («улей пропал», «мутанты рядом с данжом»)
	var n := 0
	for r in raiders:
		if String(r.get("role", "")).is_empty() and not bool(r.get("ambush", false)):
			n += 1
	return n


## Конец волны: true — отбита (награда), false — осада удалась (город понёс потери).
## M11: награда и переналадка мутантских волн — только для волн мутантов;
## лес и неспокойные духи не трогают расписание угроз.
func _raid_end(defended: bool) -> void:
	var kind := _raid_kind
	raid_active = false
	raid_breached = false
	# v1.85: бандиты (не заплатили дань) — жгут поля: посевы теряют стадии
	if kind == "bandit":
		var burned := 0
		for z in zones:
			if String(z.get("type", "")) != "field":
				continue
			for crop in (z.get("crops", []) as Array):
				if (crop as Dictionary).is_empty():
					continue
				if bool(crop.get("ripe", false)):
					crop["ripe"] = false
					burned += 1
				crop["stage"] = maxi(0, int(crop.get("stage", 0)) - 2)
		events.append({"type": "fields_burned", "crops": burned})
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
			_try_spawn_hunt_squad()   # v2.2 п.1: странствующие охотники
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
		res_log(r, "dlog.conscript", ["guard"])   # v1.89
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
		res_log(r, "dlog.conscript", ["hunter"])   # v1.89
		_chron("chron.hunter_trained", String(r["name"]))
		events.append({"type": "hunter_trained", "name": String(r["name"])})
		_assign_jobs()
		return


## ==================== ЗАСАДЫ НА КАРТЕ ГОРОДА (v1.80.1) ====================
## Фидбек заказчика: «засады должны происходить на карте города, не
## глобальной карты. Могут быть меньше по размеру, но разнообразнее».
## Засада = заслон на дикой окраине города (зема-слой рисует сценку по
## kind): бандиты — поваленные деревья и телеги, мутанты — скальный
## проход, волки — заросли, мертвецы — костяная ограда. Герой подошёл —
## враги встают из заслона (общая система рейдеров: героя бьют, герой
## бьёт), всех уложил — монеты и снятие заслона.

var ambush_sites: Array = []   # {tile: Vector2i, kind: String, n: int, sprung: bool, ids: Array}
var _ambush_day := 0            # день последнего броска засады (v1.80.1)
const AMBUSH_POOLS := {
	"bandits": ["bandit", "bandit", "bandit_archer"],
	"mutants": ["mutant", "mutant", "brute", "spitter"],
	"wolves": ["wolf", "wolf", "crawler"],
	"undead": ["skeleton", "skeleton", "ghoul"],
}


## Ежедневный бросок: шанс засады на дикой окраине (не более 2 активных).
func ambush_tick_day() -> void:
	if map == null or ambush_sites.size() >= 2:
		return
	if _event_rng.randf() > 0.2:
		return
	ambush_stage_now()


## Принудительно заложить засаду (бросок дня пути на карте мира: «бандиты
## подбираются к городу»). false — не нашлось места.
func ambush_stage_now() -> bool:
	if map == null or ambush_sites.size() >= 2:
		return false
	var t := _ambush_tile()
	if t == Vector2i(-1, -1):
		return false
	var kinds: Array = AMBUSH_POOLS.keys()
	var kind: String = kinds[_event_rng.randi_range(0, kinds.size() - 1)]
	ambush_sites.append({"tile": t, "kind": kind,
			"n": 2 + _event_rng.randi_range(0, 2), "sprung": false, "ids": []})
	events.append({"type": "ambush_staged", "kind": kind})
	return true


func _ambush_tile() -> Vector2i:
	for attempt in 60:
		var ang := TAU * _event_rng.randf()
		var rr := 22.0 + _event_rng.randf() * 38.0
		var t: Vector2i = map.spawn_tile + Vector2i(
				int(round(cos(ang) * rr)), int(round(sin(ang) * rr)))
		if not map.in_bounds(t) or not map.is_walkable(t):
			continue
		if int(map.grid[t.y][t.x]) != map.TILE_GRASS:
			continue
		var ok := true
		for b in buildings:
			if _active(b) and Vector2((b["tile"] as Vector2i) - t).length() < 4.0:
				ok = false
				break
		if not ok:
			continue
		for s in ambush_sites:
			if Vector2((s["tile"] as Vector2i) - t).length() < 10.0:
				ok = false
				break
		if ok:
			return t
	return Vector2i(-1, -1)


## Герой подошёл к заслону — враги встают из засады.
func spring_ambush(site: Dictionary) -> void:
	if bool(site.get("sprung", false)) or map == null:
		return
	site["sprung"] = true
	var pool: Array = AMBUSH_POOLS.get(String(site["kind"]), ["bandit"])
	var ids: Array = []
	for i in int(site["n"]):
		var def_id: String = pool[_event_rng.randi_range(0, pool.size() - 1)]
		var def := {}
		if _enemies_cfg.is_empty():
			var ed: Variant = _read_json_file("res://data/enemies.json")
			_enemies_cfg = ed if ed is Array else []
		for d2 in _enemies_cfg:
			if String(d2["id"]) == def_id:
				def = d2
				break
		if def.is_empty():
			continue
		var pos: Vector2 = map.tile_center_px(site["tile"] as Vector2i)
		for attempt in 10:
			var off := Vector2i(_event_rng.randi_range(-2, 2), _event_rng.randi_range(-2, 2))
			var t2: Vector2i = (site["tile"] as Vector2i) + off
			if map.is_walkable(t2):
				pos = map.tile_center_px(t2)
				break
		raiders.append({
			"id": _next_id, "type": def_id, "p": def,
			"hp": int(def["hp"]), "max_hp": int(def["hp"]),
			"pos": pos, "target": Vector2i(-1, -1), "path": PackedVector2Array(),
			"atk_cd": 0.0, "mode": "", "ambush": true,
			"site_tile": site["tile"], "ttl": float(cfg["day_length"]) * 0.6,
		})
		ids.append(_next_id)
		_next_id += 1
	site["ids"] = ids
	events.append({"type": "ambush_sprung", "kind": String(site["kind"])})
	_chron("chron.ambush_sprung")


## Тик засадных юнитов (вне волн улья; герой далеко — ждут в засаде).
func _update_ambush_units(dt: float, tcfg: Dictionary) -> void:
	if not spirits.is_empty():
		_update_spirits(dt)   # v2.2 п.2: духи благодати работают и гибнут
	_update_champion(dt)   # v2.1: чемпион города держит волну
	# раз в игровой день — бросок засады и тик памяти мира (проверка
	# здесь, в nature: выше по extends-цепочке (city_sim_tick) члены
	# природы не видны парсеру)
	if int(day) != int(_ambush_day) and int(day) > 1:
		_ambush_day = int(day)
		ambush_tick_day()
		memory_daily()
		mold_daily()
		night_guests_daily()
		bandit_tribute_daily()
		defence_rush_daily()   # v2.1 причина 1: оборонный рывок до волны
		tavern_request_daily() # v2.1 причина 2: мечта «пировать» -> таверна
		_champion_daily()      # v2.1 причина 3: чемпион после гибели героя
		secret_camp_daily()
		altar_daily()
		hunt_report_daily()
		hunt_squad_daily()
	if ambush_sites.is_empty():
		return
	var i := 0
	while i < raiders.size():
		var r: Dictionary = raiders[i]
		if not bool(r.get("ambush", false)):
			i += 1
			continue
		r["ttl"] = float(r.get("ttl", 0.0)) - dt
		var alive := int(r["hp"]) > 0 and float(r["ttl"]) > 0.0
		if alive and not _ambush_unit_tick(r, dt):
			alive = false
		if not alive:
			raiders.remove_at(i)
			continue
		i += 1
	_ambush_settle()


## Итоги: все юниты засады мертвы — заслон снят, монеты герою; юниты
## растаяли по времени — засада снова в заслоне (можно прийти снова).
func _ambush_settle() -> void:
	var i := ambush_sites.size() - 1
	while i >= 0:
		var site: Dictionary = ambush_sites[i]
		if not bool(site.get("sprung", false)):
			i -= 1
			continue
		var left := 0
		var expired := 0
		for uid: int in (site["ids"] as Array):
			var found := false
			for r in raiders:
				if int(r["id"]) == uid:
					found = true
					left += 1
					break
			if not found:
				expired += 1
		if left == 0 and expired > 0:
			# убиты героем — засада разогнана
			if coins_sink.is_valid():
				coins_sink.call(6 + 4 * expired)
			events.append({"type": "ambush_cleared", "kind": String(site["kind"]),
					"coins": 6 + 4 * expired})
			_chron("chron.ambush_cleared")
			ambush_sites.remove_at(i)
		elif left == 0:
			# растаяли по времени — заслон снова ждёт
			site["sprung"] = false
			site["ids"] = []
		i -= 1

## Лёгкий тик засадного юнита (v1.80.2): БЕЗ _raider_update — тот на
## герое «вдалеке» запускал A* через всю карту до центра города
## (засада на дикой окраине = ФРИЗ, фидбек «игра опять зависла»).
## Юнит ждёт в засаде; герой близко — преследует НАПРЯМУЮ и бьёт;
## герой ушёл — стоит на месте (поле открытое, стены не мешают).
func _ambush_unit_tick(r: Dictionary, dt: float) -> bool:
	var p: Dictionary = r["p"]
	r["atk_cd"] = maxf(0.0, float(r["atk_cd"]) - dt)
	var mv := dt
	if float(r.get("slow_left", 0.0)) > 0.0:
		r["slow_left"] = maxf(0.0, float(r["slow_left"]) - dt)
		mv = dt * 0.5
	if not hero_alive:
		return true
	var to_hero: Vector2 = hero_pos - (r["pos"] as Vector2)
	var hero_d: float = to_hero.length()
	if hero_d > float(p.get("aggro", 220.0)) * 1.4:
		return true   # ждёт в засаде
	if hero_d <= float(p["attack_range"]) + 12.0:
		if float(r["atk_cd"]) <= 0.0:
			r["atk_cd"] = float(p["attack_cooldown"])
			events.append({"type": "hero_hit", "dmg": maxi(1, int(round(float(p["damage"]))))})
		return true
	var step := float(p["speed"]) * mv
	var next: Vector2 = (r["pos"] as Vector2) + to_hero.normalized() * step
	if map.is_walkable(map.tile_of_px(next)):
		r["pos"] = next
	return true


## ==================== ПАМЯТЬ МИРА (v1.81, док 18) ==========================
## Староста-голем даёт задания на поиск утраченной памяти мира: осколки
## падают с боссов данжей. Данные сдаются старосте, он СКАНИРУЕТ их
## несколько дней (сам называет срок), потом награда и следующая стадия.
## После третьей стадии — ОТКРОВЕНИЕ: эпицентр аномалии на карте мира
## должен быть уничтожен (цель кампании, док 18).

var memory_stage := 0          # 0 — не начали; 1..3 — стадии; 4 — откровение
var memory_brought := 0        # осколков сдано на текущей стадии
var memory_crystals_ready := false  # стадия 2: кристаллы сданы
var memory_scan_left := 0.0    # дней до конца сканирования
var memory_shards_in_scan := 0
const MEMORY_STAGES := [
	{"shards": 2, "scan": 1.5, "coins": 30},
	{"shards": 3, "crystals": 8, "scan": 2.0, "coins": 45},
	{"shards": 4, "scan": 2.5, "coins": 80},
]


## Раз в игровой день (вызывается из тика засад): сканирование идёт днями.
func memory_daily() -> void:
	if memory_scan_left > 0.0:
		memory_scan_left = maxf(0.0, memory_scan_left - 1.0)
		if memory_scan_left <= 0.0:
			_memory_scan_done()


func _memory_scan_done() -> void:
	var st: Dictionary = MEMORY_STAGES[clampi(memory_stage - 1, 0, MEMORY_STAGES.size() - 1)]
	var coins: int = int(st.get("coins", 30))
	if coins_sink.is_valid():
		coins_sink.call(coins)
	events.append({"type": "memory_scan_done", "stage": memory_stage,
			"coins": coins})
	memory_stage += 1
	if memory_stage > MEMORY_STAGES.size():
		memory_stage = 4   # вся память собрана — откровение
		events.append({"type": "memory_revealed"})
		_chron("chron.memory_revealed")


## ==================== СЕРАЯ ПЛЕСЕНЬ (v1.84) ================================
## «Пепел» — живая серая плесень (фидбек заказчика): при загрязнении она
## заражает дикие травяные тайлы, расползается по соседям, плодит тварей.
## Лечится магией героя: E на заражённой земле — 10 маны (см. city_events).
## Параметры — city.json → "mold".

var mold: Dictionary = {}      # Vector2i -> возраст в днях
var mold_day := 0              # день последнего тика плесени
var mold_burned: Dictionary = {}  # v1.88: выжженные магией клетки (след)


func mold_daily() -> void:
	if map == null or OS.has_environment("PEPEL_TEST_MAPS"):
		return
	var mcfg: Dictionary = cfg.get("mold", {})
	# вспышка: загрязнение перевалило порог — сеются первые клетки на диком краю
	if mold.is_empty():
		if float(pollution) < float(mcfg.get("start_pollution", 25.0)):
			return
		var seeded := _mold_seed()
		for t in seeded:
			mold[t] = 1
		if not seeded.is_empty():
			events.append({"type": "mold_started", "count": seeded.size()})
			_chron("chron.mold_started")
		return
	# распространение: соседние травяные тайлы, шанс растёт от загрязнения
	var spread: float = float(mcfg.get("spread_chance", 0.10)) + float(pollution) / 400.0
	var news: Array = []
	for t in mold.keys():
		mold[t] = int(mold[t]) + 1
		if mold.size() >= int(mcfg.get("max_tiles", 45)):
			continue
		if _event_rng.randf() > spread:
			continue
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var n: Vector2i = t + dirs[_event_rng.randi_range(0, 3)]
		if map.in_bounds(n) and map.is_walkable(n) 				and int(map.grid[n.y][n.x]) == map.TILE_GRASS 				and not mold.has(n) and not _mold_near_bld(n):
			news.append(n)
	for n2 in news:
		mold[n2] = 1
	if not news.is_empty():
		events.append({"type": "mold_spread", "count": news.size()})
	# твари из плесени: при большой площади каждые 3 дня выползает тварь
	if mold.size() >= 6 and int(day) % 3 == 0:
		_mold_spawn_critter()


func _mold_near_bld(t: Vector2i) -> bool:
	for b in buildings:
		if _active(b) and Vector2((b["tile"] as Vector2i) - t).length() < 3.0:
			return true
	return false


func _mold_seed() -> Array:
	var out: Array = []
	for attempt in 60:
		var ang := TAU * _event_rng.randf()
		var rr := 34.0 + _event_rng.randf() * 30.0
		var t: Vector2i = map.spawn_tile + Vector2i(
				int(round(cos(ang) * rr)), int(round(sin(ang) * rr)))
		if not map.in_bounds(t) or not map.is_walkable(t):
			continue
		if int(map.grid[t.y][t.x]) != map.TILE_GRASS or mold.has(t):
			continue
		if _mold_near_bld(t):
			continue
		out.append(t)
		if out.size() >= 3:
			break
	return out


func _mold_spawn_critter() -> void:
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var pool := ["crawler", "ghoul", "crawler"]
	var def_id: String = pool[_event_rng.randi_range(0, pool.size() - 1)]
	var def := {}
	for d2 in _enemies_cfg:
		if String(d2["id"]) == def_id:
			def = d2
			break
	if def.is_empty():
		return
	var tiles := mold.keys()
	var src: Vector2i = tiles[_event_rng.randi_range(0, tiles.size() - 1)]
	var pos: Vector2 = map.tile_center_px(src)
	for attempt in 8:
		var off := Vector2i(_event_rng.randi_range(-1, 1), _event_rng.randi_range(-1, 1))
		var t2: Vector2i = src + off
		if map.is_walkable(t2):
			pos = map.tile_center_px(t2)
			break
	raiders.append({
		"id": _next_id, "type": def_id, "p": def,
		"hp": int(def["hp"]), "max_hp": int(def["hp"]),
		"pos": pos, "target": Vector2i(-1, -1), "path": PackedVector2Array(),
		"atk_cd": 0.0, "mode": "", "ambush": true,
		"site_tile": src, "ttl": float(cfg["day_length"]) * 0.6,
	})
	_next_id += 1
	events.append({"type": "mold_critter", "kind": def_id})


func mold_cure(t: Vector2i) -> void:
	# магия героя выжигает плесень: клетка + соседей с шансом
	mold.erase(t)
	mold_burned[t] = 1   # v1.88: след — выжженная земля
	var cured := 1
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = t + d
		if mold.has(n) and _event_rng.randf() < 0.6:
			mold.erase(n)
			mold_burned[n] = 1
			cured += 1
	if cured > 1:
		events.append({"type": "mold_cured", "count": cured})


## ==================== НОЧЬ НЕЧИСТИ (v1.85) ================================
## Ночница/кикимора приходят к спящим, если в городе нет стражей: крадут
## еду, могут изранить жильца. Страж на посту отгоняет гостью (фидбек:
## «ночью город обороняется, днём работает» — игрок распределяет стражей).
func night_guests_daily() -> void:
	# v1.85: автотесты детерминированы — воровство еды ломает замеры
	# (гейт здесь: test_hive оставляет PEPEL_HIVE_ON=1 после себя)
	if OS.has_environment("PEPEL_TEST_MAPS"):
		return
	var guards := 0
	for r in residents:
		if String(r["prof"]) == "guard" and String(r.get("ail", "")) != "dead":
			guards += 1
	var chance := clampf(0.45 - 0.15 * float(mini(guards, 2)), 0.05, 0.45)
	if _event_rng.randf() >= chance:
		return
	var stolen: float = 4.0 + _event_rng.randf() * 8.0
	res["food"] = maxf(0.0, float(res["food"]) - stolen)
	var victim: Dictionary = {}
	var sleepers: Array = residents.filter(func(r):
		return String(r.get("state", "")) in ["sleep", "rest"] 				and String(r.get("ail", "")) != "dead")
	if sleepers.is_empty():
		sleepers = residents
	if not sleepers.is_empty():
		victim = sleepers[_event_rng.randi_range(0, sleepers.size() - 1)]
		if _event_rng.randf() < 0.4:
			_make_ail(victim, "wounded", "chron.wounded")
	events.append({"type": "night_guest", "food": int(stolen),
			"who": String(victim.get("name", ""))})


## ==================== ДАНЬ БАНДИТОВ (v1.85) ================================
## Бандиты приходят С ПОСЛАНИЕМ (фидбек заказчика): требуют долю еды,
## срок 2 дня. Платишь — отступают на срок (растёт с каждой выплатой);
## не платишь — рейд бандитов (отдельный от мутантов) и поля горят.
var tribute_food := 0
var tribute_due := 0
var tribute_paid := 0
var tribute_next_day := 8
var tribute_pending := false


func bandit_tribute_daily() -> void:
	if OS.has_environment("PEPEL_TEST_MAPS"):
		return
	if tribute_pending:
		if int(day) >= tribute_due:
			tribute_pending = false
			_spawn_bandit_raid()
		return
	if int(day) < tribute_next_day:
		return
	tribute_food = 8 + tribute_paid * 4
	tribute_due = int(day) + 2
	tribute_pending = true
	events.append({"type": "bandit_message", "food": tribute_food,
			"due": tribute_due})


## Заплатить дань (кнопка у старосты — он ведёт дела с окрестностью).
## "" — заплатили, иначе ключ ошибки.
func pay_tribute() -> String:
	if not tribute_pending:
		return ""
	if float(res["food"]) < float(tribute_food):
		return "no_food"
	res["food"] = maxf(0.0, float(res["food"]) - float(tribute_food))
	tribute_paid += 1
	tribute_pending = false
	tribute_next_day = int(day) + 4 + tribute_paid * 2
	events.append({"type": "tribute_paid", "food": tribute_food})
	return ""


## Рейд бандитов: 2+выплаты тварей-грабителей с краю карты; по окончании
## поля горят (см. _raid_end).
func _spawn_bandit_raid() -> void:
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var pool := ["bandit", "bandit", "bandit_archer"]
	raid_active = true
	raid_siege = false
	_raid_kind = "bandit"
	razed_this_raid = 0
	var n := 2 + mini(tribute_paid, 3)
	for i in n:
		var def_id: String = pool[_event_rng.randi_range(0, pool.size() - 1)]
		var def := {}
		for d2 in _enemies_cfg:
			if String(d2["id"]) == def_id:
				def = d2
				break
		if def.is_empty():
			continue
		raiders.append({
			"id": _next_id, "type": def_id, "p": def,
			"hp": int(def["hp"]), "max_hp": int(def["hp"]),
			"pos": _spawn_tile_near_anomaly(), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "atk_cd": 0.0, "mode": "",
			"ttl": float(cfg["day_length"]) * 0.7,
		})
		_next_id += 1
	_update_gates()


## ==================== СЛЕДЫ: ОХОТНИКИ-ГОРОЖАНЕ (v2.2 п.3) ====================
## (TRACKS наследуется от city_sim_tick)
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
	var pos: Vector2 = map.tile_center_px(camp["tile"])
	for i in 3:
		var p2: Vector2 = pos + Vector2(_event_rng.randf_range(-ts, ts), _event_rng.randf_range(-ts, ts))
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
			# добыча как у собирателей: ближайшее дерево -> брёвна,
			# скала -> камень (дух не истощает тайл — берёт силой благодати)
			if not _spirit_res_ok(Vector2i(s.get("res_tile", Vector2i(-1, -1)))):
				s["res_tile"] = _spirit_find_res(Vector2(s["pos"]))
			var rt: Vector2i = Vector2i(s.get("res_tile", Vector2i(-1, -1)))
			if rt.x >= 0:
				var goal2: Vector2 = map.tile_center_px(rt)
				if (s["pos"] as Vector2).distance_to(goal2) < float(map.ts) * 0.9:
					var kind := "wood" if int(map.grid[rt.y][rt.x]) == map.TILE_TREE else "stone"
					_add_resource_capped(kind, float(gcfg.get("gather_per_trip", 2.0))
							* float(s["eff"]))
					s["res_tile"] = Vector2i(-1, -1)
				else:
					_spirit_walk(s, goal2, dt, gcfg)
	# волны бьют духа
	if raid_active:
		for r in raiders:
			if String(r.get("role", "")) != "":
				continue
			for s2 in spirits:
				if (s2["pos"] as Vector2).distance_to(r["pos"] as Vector2) < float(map.ts) 						and not dead.has(s2["id"]):
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


## ==================== ИЩЕЙКА УЛЬЯ (v2.2 п.3) ====================
## Лагерь мутантов не знает, где город: ищейка прочёсывает окрестность
## (кольцо растёт с днями поиска), идёт по свежим следам жителей; учует
## героя — бежит, оставляя логову «грязную» метку «примерно здесь»;
## дошла до жилья — несёт точную точку, и волны идут в цель, не «по воздуху».
func _hive_seeker_update(r: Dictionary, mv: float) -> bool:
	var speed: float = float(r["p"]["speed"]) * mv
	var pos: Vector2 = r["pos"] as Vector2
	# герой рядом — паника: грязная метка «примерно здесь» и бегство
	if hero_alive and pos.distance_to(hero_pos) < float(r["p"]["aggro"]) * 1.2 \
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
	if pos.distance_to(map.tile_center_px(map.spawn_tile)) < float(map.ts) * 7.0 \
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
					if String(u.get("role", "")) in ["guard", "gatherer", "scout", "seeker"] \
							and (u["pos"] as Vector2).distance_to(r["pos"] as Vector2) < float(map.ts):
						near.append(u)
				for u2 in near:
					_hit_raider(u2, int(r["p"]["damage"]), Vector2i(-9999, -9999), "hunt_ally")
				if not bool(r.get("ha_win", false)) \
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


## ==================== ДОПРОС ЛАЗУТЧИКА (v2.2 п.4а) ====================
## Герой (или житель) допрашивает «путника» (E рядом, из city_events).
## "" — не лазутчик; "alibi" — отговорка (подозрение мало); "confess" —
## выдал лагерь; "fled" — запаниковал и убегает.
func interrogate_spy(wanderer_id: int) -> String:
	var w: Dictionary = {}
	for x in wanderers:
		if int(x["id"]) == wanderer_id:
			w = x
			break
	if w.is_empty() or not bool(w.get("spy", false)):
		return ""
	var sname := String(w.get("spy_name", "путник"))
	var kn: Dictionary = spy_known.get(sname, {"visits": 0})
	var camp: Dictionary = {}
	for c2 in secret_camps:
		if int(c2["id"]) == int(w.get("spy_camp", -1)):
			camp = c2
			break
	var suspicion := int(camp.get("suspicion", 0)) if not camp.is_empty() else int(kn["visits"])
	if suspicion < 2:
		return "alibi"
	if _event_rng.randf() < 0.6 and not camp.is_empty():
		reveal_camp()          # улика: лагерь раскрыт
		w["mode"] = "leave"    # путник спешит уйти
		w["target"] = Vector2i(-1, -1)
		_chron("chron.spy_confess", sname)
		return "confess"
	# паника: убегает, лагерь не выдал
	w["mode"] = "leave"
	w["target"] = Vector2i(-1, -1)
	_chron("chron.spy_fled")
	return "fled"


## Тайл ещё годен для духа: живое дерево или скала.
func _spirit_res_ok(t: Vector2i) -> bool:
	if map == null or not map.in_bounds(t):
		return false
	if int(map.grid[t.y][t.x]) == map.TILE_TREE:
		return true
	return map.rock_hp.has(t)


## Ближайшее дерево/скала в радиусе 12 тайлов ({} духа: Vector2i(-1,-1)).
func _spirit_find_res(from: Vector2) -> Vector2i:
	var c: Vector2i = map.tile_of_px(from)
	var best := Vector2i(-1, -1)
	var best_d := 1e9
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var t: Vector2i = c + Vector2i(dx, dy)
			if _spirit_res_ok(t):
				var d := float(dx * dx + dy * dy)
				if d < best_d:
					best_d = d
					best = t
	return best


## ==================== v2.1 «МОЗГ СТАРОСТЫ» ====================
## Диагноз 100-дневного прогона: город не строил оборону до волны
## (стены начинались только после полной застройки), таверна по мечте
## жителя ничем не подкреплена, после гибели героя город гас без замены.

## Герой пал (данж или симуляция): город молится о странствующем чемпионе.
func hero_fell() -> void:
	if champion_due_day > 0 or not (champion as Dictionary).is_empty():
		return   # уже ждём или чемпион на месте
	var ccfg: Dictionary = cfg.get("champion", {})
	champion_due_day = int(day) + int(ccfg.get("delay_min", 3)) \
			+ (_event_rng.randi_range(0, maxi(0, int(ccfg.get("delay_max", 5))
					- int(ccfg.get("delay_min", 3)))))
	events.append({"type": "hero_fell"})
	_chron("chron.hero_fell")


## Ежедневно: чемпиона ждут — и он приходит (один раз, без замены).
func _champion_daily() -> void:
	if champion_due_day < 0 or not (champion as Dictionary).is_empty():
		return
	if int(day) < champion_due_day or map == null:
		return
	var ccfg: Dictionary = cfg.get("champion", {})
	var names: Array = ccfg.get("names", ["Ратмир", "Добрыня", "Горазд", "Свенн"])
	var nm := String(names[_event_rng.randi_range(0, names.size() - 1)])
	var t: Vector2i = map.spawn_tile
	for attempt in 40:
		var ang := TAU * _event_rng.randf()
		var rr := 6.0 + _event_rng.randf() * 4.0
		var t2: Vector2i = map.spawn_tile + Vector2i(int(round(cos(ang) * rr)),
				int(round(sin(ang) * rr)))
		if map.in_bounds(t2) and map.is_walkable(t2):
			t = t2
			break
	champion = {
		"name": nm, "hp": float(ccfg.get("hp", 60.0)), "hp_max": float(ccfg.get("hp", 60.0)),
		"atk": float(ccfg.get("atk", 9.0)), "speed": float(ccfg.get("speed", 80.0)),
		"pos": map.tile_center_px(t), "target": Vector2i(-1, -1), "cd": 0.0,
		"alive": true,
	}
	champion_due_day = -1
	events.append({"type": "champion_arrived", "name": nm})
	_chron("chron.champion_arrived", nm)


## Тик чемпиона: в волне держит строй мутантов у стен, вне волны — у ворот.
func _update_champion(dt: float) -> void:
	if (champion as Dictionary).is_empty():
		return
	if not bool(champion.get("alive", true)):
		champion = {}
		return
	champion["cd"] = maxf(0.0, float(champion["cd"]) - dt)
	# мутанты рядом бьют чемпиона (отвлечение уже в _raider_update)
	if raid_active:
		var vic: Dictionary = _nearest_raider(champion["pos"] as Vector2,
				float(map.ts) * 5.0)
		if not vic.is_empty():
			var goal: Vector2 = vic["pos"] as Vector2
			if (champion["pos"] as Vector2).distance_to(goal) < float(map.ts) * 0.9:
				if float(champion["cd"]) <= 0.0:
					champion["cd"] = 0.7
					_hit_raider(vic, int(round(float(champion["atk"]))),
							Vector2i(-9999, -9999), "champion")
			else:
				var v: Vector2 = goal - (champion["pos"] as Vector2)
				champion["pos"] = (champion["pos"] as Vector2) \
						+ v.normalized() * float(champion["speed"]) * dt
		if float(champion["hp"]) <= 0.0:
			champion = {}
			events.append({"type": "champion_fell"})
			_chron("chron.champion_fell")


## Причина 1: ОБОРОННЫЙ РЫВОК — волна близко (ETA <= eta_days), а город
## не укреплён: староста ставит кузню (стражи с железом) и ведёт стены
## сегментами вокруг жилья, не дожидаясь полной застройки.
func defence_rush_daily() -> void:
	if map == null:
		return
	var rcfg: Dictionary = cfg.get("defence_rush", {})
	if rcfg.get("enabled", true) == false:
		return
	if float(raid_eta_days()) > float(rcfg.get("eta_days", 5.0)):
		return
	if _defence_ready():
		return
	var built := 0
	# 1) кузня — без неё стражам нечем вооружиться
	var forge := false
	for b in buildings:
		if String(b["type"]) == "forge" and _active(b):
			forge = true
			break
	if not forge and not _autobuild_site_exists("forge"):
		var ft := _find_autobuild_tile("forge")
		if ft != Vector2i(-1, -1) and place_building("forge", ft):
			_announce_autobuild("forge", true)
			built += 1
	# 2) стены — три звена за день по кольцу жилья
	for i in 3:
		var wt := _next_wall_tile()
		if wt == Vector2i(-1, -1):
			break
		if not place_building("wall", wt):
			break
		built += 1
	if built > 0:
		events.append({"type": "defence_rush", "built": built})
		_chron("chron.defence_rush")


## Город готов к волне: кольцо стен замкнуто, кузня стоит, стражей двое.
func _defence_ready() -> bool:
	if _next_wall_tile() != Vector2i(-1, -1):
		return false
	var forge := false
	for b in buildings:
		if String(b["type"]) == "forge" and _active(b):
			forge = true
			break
	if not forge:
		return false
	var guards := 0
	for r in residents:
		if String(r["prof"]) == "guard":
			guards += 1
	return guards >= 2


## Причина 2: мечта «пировать в таверне» — житель ПИШЕТ старосте
## («Кира просит таверну»), и при pop >= 8 таверна строится вне очереди.
func tavern_request_daily() -> void:
	if map == null:
		return
	var tcfg: Dictionary = cfg.get("tavern_request", {})
	if tcfg.get("enabled", true) == false:
		return
	# таверна уже есть или строится
	var have := false
	for b in buildings:
		if String(b["type"]) == "tavern":
			have = true
			break
	if have:
		return
	if residents.size() < int(tcfg.get("pop", 8)):
		return
	for r in residents:
		if String(r.get("goal", "")) != "feast_tavern" or bool(r.get("tavern_asked", false)):
			continue
		r["tavern_asked"] = true
		events.append({"type": "tavern_request", "name": String(r["name"])})
		_chron("chron.tavern_request", String(r["name"]))
		var tt := _find_autobuild_tile("tavern")
		if tt != Vector2i(-1, -1) and place_building("tavern", tt):
			_announce_autobuild("tavern", true)
		return   # одно письмо в день — староста не читает пачками
