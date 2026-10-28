# Часть: данж-лут, волны мутантов и осады, бури, охота, духи леса, ручной труд героя, некромант.
# Правки структуры v1.20.2: огромный city_sim.gd разбит на extends-цепочку
# частей; это один класс, разложенный по файлам — поведение не меняется.
extends "res://scripts/city_sim_gov.gd"

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
func _update_threat(dt: float, day_len: float) -> void:
	var tcfg: Dictionary = cfg.get("threat", {})
	if tcfg.is_empty():
		return
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
	var hp_mult := 1.0 + threat_value() * float(tcfg.get("hp_per_threat", 0.04)) \
			+ float(wave_no) * float(tcfg.get("wave_growth_hp", 0.15))
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
		if not _raider_update(r, dt, tcfg):
			raiders.remove_at(i)
			continue
		i += 1
	if raiders.is_empty():
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
		_hit_raider(target, int(round((float(tcfg.get("tower_damage", 2)) + research_sum("tower_damage")) * mult)))


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
	var p: Dictionary = r["p"]
	if String(r.get("mode", "")) == "hunt":
		return _spirit_update(r, dt)
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
					events.append({"type": "hero_hit", "dmg": int(p["damage"])})
				return true
			if _raider_move_to(r, map.tile_of_px(hero_pos), float(p["speed"]) * dt):
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
		return true
	# путь к центру открыт — идём (проверка не каждый тик: A* по обнесённой
	# стенами карте дорог — так держим FPS и в осаду, правки приёмки v1.26)
	r["_center_cd"] = float(r.get("_center_cd", 0.0)) - dt
	if float(r["_center_cd"]) <= 0.0:
		r["_center_cd"] = 0.4
		r["_center_open"] = map.path_px(r["pos"], map.spawn_tile, true).size() > 1
	if bool(r.get("_center_open", false)) \
			and _raider_move_to(r, map.spawn_tile, float(p["speed"]) * dt):
		return true
	# заперты в кольце: идём ломать ближайшую стену или ворота
	return _raider_break_obstacle(r, dt, p, near)


## Ближайшее к мутанту действующее здание (кэш на _near_gap секунд: скан всех
## зданий каждый тик всей волной — заметная цена на большой карте).
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
func _hit_raider(r: Dictionary, dmg: int) -> void:
	r["hp"] = int(r["hp"]) - dmg
	if int(r["hp"]) <= 0:
		_drop_corpse(r)
		raiders.erase(r)


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


## Удар героя в городе (участие в обороне): дуга в сторону курсора. Возвращает, скольких задел.
func hero_slash(origin_px: Vector2, facing: Vector2, range_px: float, arc_deg: float, dmg: int) -> int:
	var hits := 0
	for r in raiders.duplicate():
		var to: Vector2 = (r["pos"] as Vector2) - origin_px
		if to.length() > range_px + float(r["p"]["radius"]):
			continue
		if absf(facing.angle_to(to)) > deg_to_rad(arc_deg) / 2.0:
			continue
		_hit_raider(r, dmg)
		hits += 1
	if raid_active and raiders.is_empty():
		_raid_end(true)
	return hits


## Выстрел героя (M14-B, лук/посох в городе): ближайший рейдер в узком конусе.
func hero_shoot(origin_px: Vector2, facing: Vector2, range_px: float, dmg: int) -> int:
	var target: Dictionary = _nearest_raider(origin_px, range_px)
	if target.is_empty():
		return 0
	var to: Vector2 = (target["pos"] as Vector2) - origin_px
	if absf(facing.angle_to(to)) > 0.3:
		return 0
	_hit_raider(target, dmg)
	if raid_active and raiders.is_empty():
		_raid_end(true)
	return 1


## Конец волны: true — отбита (награда), false — осада удалась (город понёс потери).
## M11: награда и переналадка мутантских волн — только для волн мутантов;
## лес и неспокойные духи не трогают расписание угроз.
func _raid_end(defended: bool) -> void:
	var kind := _raid_kind
	raid_active = false
	raiders.clear()
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


## --- магическая буря (M5) ---------------------------------------------------

## Дневной бросок: буря редка сама по себе и частит с загрязнением.
func _roll_storm() -> void:
	if storm_state != "" or residents.is_empty():
		return
	var scfg: Dictionary = cfg.get("storm", {})
	if scfg.is_empty():
		return
	var chance: float = float(scfg.get("base_chance", 0.02)) \
			+ float(scfg.get("pollution_chance", 0.25)) * pollution / 100.0
	if _event_rng.randf() >= chance:
		return
	storm_state = "warn"
	storm_left = float(scfg.get("warn_days", 0.3)) * float(cfg["day_length"])
	events.append({"type": "storm_warn"})
	_chron("chron.storm_warn")


func _update_storm(dt: float, day_len: float) -> void:
	if storm_state == "":
		return
	var scfg: Dictionary = cfg.get("storm", {})
	storm_left = maxf(0.0, storm_left - dt)
	if storm_state == "warn":
		if storm_left <= 0.0:
			storm_state = "active"
			storm_left = float(scfg.get("duration_days", 0.6)) * day_len
			_storm_struck_at = time
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(scfg.get("mood_hit", -10.0)), 0.0, 100.0)
			events.append({"type": "storm_start"})
			_chron("chron.storm")
		return
	# активная буря: портит воздух и бьёт по зданиям («Оберег» защищает)
	add_pollution(float(scfg.get("pollution_per_day", 10.0)) * dt / day_len)
	if time - _storm_struck_at >= float(scfg.get("strike_period_days", 0.12)) * day_len:
		_storm_struck_at = time
		var target := _storm_strike_target()
		if not target.is_empty():
			_damage_building(target, float(scfg.get("strike_damage", 12)))
			if buildings.has(target):
				events.append({"type": "storm_strike", "bld": String(target["type"])})
	if storm_left <= 0.0:
		storm_state = ""
		events.append({"type": "storm_end"})
		_chron("chron.storm_end")


## Случайное готовое здание без «Оберега» — цель удара бури.
func _storm_strike_target() -> Dictionary:
	var candidates: Array = []
	for b in buildings:
		if _active(b) and String(b.get("enchant", "")) != "ward":
			candidates.append(b)
	if candidates.is_empty():
		return {}
	return candidates[_event_rng.randi_range(0, candidates.size() - 1)]


# --- охота, животные, стражи (M5.1) ------------------------------------------

## Дикое животное (M5.1 → M14-C правка): виды из data/fauna.json — олени,
## кабаны, птицы и волки («не мирные»: охотятся на прочих зверей).
func _new_animal() -> Dictionary:
	_next_id += 1
	return {"id": _next_id, "kind": _roll_animal_kind(), "pos": _random_walkable_px(),
			"target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "idle": _event_rng.randf_range(0.0, 4.0)}


## Виды диких животных города: мирные чаще, волк — реже.
func _roll_animal_kind() -> String:
	var roll := _event_rng.randf()
	if roll < 0.38:
		return "deer"
	if roll < 0.60:
		return "boar"
	if roll < 0.80:
		return "bird"
	return "wolf"


func _random_walkable_px() -> Vector2:
	for attempt in 60:
		var tile := Vector2i(_event_rng.randi_range(1, map.w - 2), _event_rng.randi_range(1, map.h - 2))
		if map.is_walkable(tile) and building_at(tile).is_empty():
			return map.tile_center_px(tile)
	return map.tile_center_px(map.spawn_tile)


## Животные бродят по карте (чистая симуляция — без графики, для оптимизации).
func _update_animals(dt: float) -> void:
	# волки («не мирные», замечание 2026-10-20): гонятся за ближайшим мирным
	# зверем; догнали — добыча исчезает
	var eaten: Array = []
	for a in animals:
		if String(a.get("kind", "deer")) != "wolf":
			continue
		var prey := _nearest_prey_animal(a)
		if prey.is_empty():
			continue
		var to_prey: Vector2 = (prey["pos"] as Vector2) - (a["pos"] as Vector2)
		if to_prey.length() > 10.0:
			a["pos"] = (a["pos"] as Vector2) + to_prey.normalized() * 48.0 * dt
			a["path"] = PackedVector2Array()
			a["idle"] = 0.5
		else:
			eaten.append(prey)
	for prey in eaten:
		if animals.has(prey):
			animals.erase(prey)
	for a in animals:
		a["idle"] = float(a["idle"]) - dt
		if float(a["idle"]) > 0.0:
			continue
		a["idle"] = _event_rng.randf_range(2.0, 6.0)
		var here: Vector2i = map.tile_of_px(a["pos"])
		var goal: Vector2i = here + Vector2i(_event_rng.randi_range(-3, 3), _event_rng.randi_range(-3, 3))
		if map.is_walkable(goal):
			a["target"] = goal
			a["path"] = map.path_px(a["pos"], goal)
	var path: PackedVector2Array = PackedVector2Array()
	for a in animals:
		path = a["path"]
		if (path as PackedVector2Array).is_empty():
			continue
		var pos: Vector2 = a["pos"]
		var step: float = 30.0 * dt
		while step > 0.0 and not (path as PackedVector2Array).is_empty():
			var to_next: Vector2 = path[0] - pos
			var dist := to_next.length()
			if dist <= step:
				pos = path[0]
				step -= dist
				path.remove_at(0)
			else:
				pos += to_next / dist * step
				step = 0.0
		a["pos"] = pos
		a["path"] = path


## Ближайший к хищнику мирный зверь в радиусе погони.
func _nearest_prey_animal(wolf: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 140.0
	for a in animals:
		if a == wolf or String(a.get("kind", "deer")) == "wolf":
			continue
		var d: float = (a["pos"] as Vector2).distance_to(wolf["pos"])
		if d < best_d:
			best_d = d
			best = a
	return best


## Охота героя в городе (замечание 2026-10-20): удар ЛКМ снимает зверя в
## дуге; дроп — по data/fauna.json, стандартные предметы. {} — промах.
func hero_hit_animal(origin_px: Vector2, facing: Vector2, range_px: float, arc_deg: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := range_px + 8.0
	for a in animals:
		var to: Vector2 = (a["pos"] as Vector2) - origin_px
		var d := to.length()
		if d > best_d:
			continue
		if absf(facing.angle_to(to)) > deg_to_rad(arc_deg) / 2.0:
			continue
		best_d = d
		best = a
	if best.is_empty():
		return {}
	var kind := String(best.get("kind", "deer"))
	var drops: Array = []
	var fcfg: Variant = _read_json_file("res://data/fauna.json")
	if fcfg is Dictionary:
		for s in fcfg.get("species", []):
			if String(s["id"]) != kind:
				continue
			for d in s.get("drop", []):
				var n := _event_rng.randi_range(int((d["count"] as Array)[0]), int((d["count"] as Array)[1]))
				if n > 0:
					drops.append({"id": String(d["id"]), "count": n})
	animals.erase(best)
	return {"kind": kind, "drops": drops}


func _nearest_animal(from_px: Vector2, radius_px: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius_px
	for a in animals:
		var d: float = (a["pos"] as Vector2).distance_to(from_px)
		if d < best_d:
			best_d = d
			best = a
	return best


## Охотник: догоняет зверя, разделывает (hunt_time), еда в пул.
func _hunt(r: Dictionary, dt: float) -> void:
	var hcfg: Dictionary = cfg.get("hunting", {})
	var prey := _nearest_animal(r["pos"], float(hcfg.get("roam_range", 15)) * float(map.ts))
	if prey.is_empty():
		r["state"] = "idle"
		return
	if (prey["pos"] as Vector2).distance_to(r["pos"]) <= float(map.ts) * 1.3:
		r["state"] = "hunt"
		r["hunt_t"] = float(r.get("hunt_t", 0.0)) + dt
		if float(r["hunt_t"]) >= float(hcfg.get("hunt_time", 2.0)):
			r["hunt_t"] = 0.0
			animals.erase(prey)
			var food: float = float(hcfg.get("hunt_food", 6.0))
			_add_resource_capped("food", food)
			_chron("chron.hunt", String(r["name"]), str(int(food)))
			events.append({"type": "hunt", "name": String(r["name"]), "food": int(food)})
	else:
		r["hunt_t"] = 0.0
		_move_towards(r, map.tile_of_px(prey["pos"]), dt)


## Дневной бросок: зверьё восстанавливается.
func _roll_animals() -> void:
	var hcfg: Dictionary = cfg.get("hunting", {})
	if hcfg.is_empty():
		return
	if animals.size() >= int(hcfg.get("animals", 8)):
		return
	if _event_rng.randf() < float(hcfg.get("respawn_chance", 0.35)):
		animals.append(_new_animal())


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


# --- M11: духи леса ---------------------------------------------------------

## Лес живёт (правки v1.21): саженец 5 дней растёт до малого дерева (гнев −),
## малое +5 дней — до среднего, среднее +10 дней — до большого (любое дерево
## на карте растёт); гнев спадает медленно; переполнение — духи, потом Древень.
func _update_forest(dt: float, day_len: float) -> void:
	var fcfg: Dictionary = cfg.get("forest", {})
	if fcfg.is_empty():
		return
	# посаженное растёт до малого дерева
	if not map.saplings.is_empty():
		for tile: Vector2i in map.saplings.keys():
			var s: Dictionary = map.saplings[tile]
			s["t"] = float(s.get("t", 0.0)) + dt
			if float(s["t"]) < float(s.get("grow_days", fcfg.get("grow_days", 5.0))) * day_len:
				continue
			map.saplings.erase(tile)
			if map.grid[tile.y][tile.x] == map.TILE_GRASS and building_at(tile).is_empty():
				map.grid[tile.y][tile.x] = map.TILE_TREE
				map.tree_size[tile] = map.TREE_SMALL   # роста в этом тике не будет
				forest_anger = maxf(0.0, forest_anger - float(fcfg.get("calm_per_tree", 2.0)))
				events.append({"type": "tree_grown"})
				_chron("chron.tree_grown")
			terrain_dirty = true
	# растут и дикие деревья: малое → среднее (5 дней), среднее → большое (10).
	# Первый тик жизни нового дерева не считается (оно выросло из саженца
	# посреди тика — полный dt роста был бы двойным учётом, v1.21)
	for tile: Vector2i in map.tree_size.keys():
		if int(map.tree_size[tile]) >= map.TREE_LARGE:
			continue
		if not map.in_bounds(tile) or map.grid[tile.y][tile.x] != map.TILE_TREE:
			map.tree_growth.erase(tile)
			continue
		if not map.tree_growth.has(tile):
			map.tree_growth[tile] = 0.0
			continue
		var t_days: float = float(map.tree_growth.get(tile, 0.0)) + dt / day_len
		var size := int(map.tree_size[tile])
		var need := float(fcfg.get("grow_days_medium", 5.0)) if size == map.TREE_SMALL \
				else float(fcfg.get("grow_days_large", 10.0))
		if t_days >= need:
			map.tree_size[tile] = size + 1
			t_days = 0.0
			terrain_dirty = true
		map.tree_growth[tile] = t_days
	# гнев леса медленно уходит сам
	forest_anger = maxf(0.0, forest_anger - float(fcfg.get("calm_per_day", 0.35)) * dt / day_len)
	if raid_active:
		return
	if forest_anger >= float(fcfg.get("warn_anger", 8.0)) and not _forest_warned:
		_forest_warned = true
		events.append({"type": "forest_warn"})
		_chron("chron.forest_warn")
	if forest_anger < float(fcfg.get("spirit_anger", 14.0)) or time < _forest_cooldown:
		return
	_spawn_forest_wave(forest_anger >= float(fcfg.get("boss_anger", 26.0)))
	_forest_cooldown = time + float(fcfg.get("cooldown_days", 1.5)) * day_len


## Волна леса: духи охотятся на рубящих; с Древенем — покрупнее.
func _spawn_forest_wave(boss: bool) -> void:
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var def_spirit: Dictionary = {}
	var def_boss: Dictionary = {}
	for d: Dictionary in _enemies_cfg:
		if String(d["id"]) == "forest_spirit":
			def_spirit = d
		elif String(d["id"]) == "forest_boss":
			def_boss = d
	if def_spirit.is_empty():
		return
	var fcfg: Dictionary = cfg.get("forest", {})
	raid_active = true
	raid_siege = false
	_raid_kind = "forest"
	# жертвы — те, кто рубит лес и ломает камень
	var victims: Array = []
	for r in residents:
		if String(r["prof"]) in ["lumberjack", "miner", "hunter"] and r["bld"] != null:
			victims.append(r)
	if victims.is_empty():
		for r in residents:
			if String(r["prof"]) != "" and r["bld"] != null:
				victims.append(r)
	var count := int(fcfg.get("boss_spirits", 5)) if boss else int(fcfg.get("spirit_count", 3))
	for i in count:
		var vic: Dictionary = victims[_event_rng.randi_range(0, maxi(0, victims.size() - 1))] if not victims.is_empty() else {}
		raiders.append({
			"id": _next_id, "type": "forest_spirit", "p": def_spirit,
			"hp": int(def_spirit["hp"]), "max_hp": int(def_spirit["hp"]),
			"pos": _spirit_spawn_px(vic), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "atk_cd": 0.0, "mode": "hunt",
			"victim_id": int(vic["id"]) if not vic.is_empty() else -1,
			"ttl": float(cfg["day_length"]) * 0.5,
		})
		_next_id += 1
	if boss and not def_boss.is_empty():
		var vic2: Dictionary = victims[0] if not victims.is_empty() else {}
		raiders.append({
			"id": _next_id, "type": "forest_boss", "p": def_boss,
			"hp": int(def_boss["hp"]), "max_hp": int(def_boss["hp"]),
			"pos": _spirit_spawn_px(vic2), "target": Vector2i(-1, -1),
			"path": PackedVector2Array(), "atk_cd": 0.0, "mode": "hunt",
			"victim_id": int(vic2["id"]) if not vic2.is_empty() else -1,
			"ttl": float(cfg["day_length"]) * 0.75,
		})
		_next_id += 1
	var mood_hit := float(fcfg.get("boss_mood", -12.0)) if boss else float(fcfg.get("spirit_mood", -6.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + mood_hit, 0.0, 100.0)
	events.append({"type": "forest_boss_attack" if boss else "spirit_attack", "count": raiders.size()})
	_chron("chron.forest_boss" if boss else "chron.spirit_attack", str(raiders.size()))
	_update_gates()


## Дух является из леса: тайл рядом с жертвой, иначе — у любого дерева.
func _spirit_spawn_px(victim: Dictionary) -> Vector2:
	var anchor: Vector2i = map.tile_of_px(victim["pos"]) if not victim.is_empty() else map.spawn_tile
	for attempt in 40:
		var off := Vector2i(_event_rng.randi_range(-4, 4), _event_rng.randi_range(-4, 4))
		var tile := anchor + off
		if map.is_walkable(tile):
			return map.tile_center_px(tile)
	return map.tile_center_px(anchor)


## Охота духа (M11): догоняет свою жертву, ранит и пугает; без жертвы —
## ломает лесопилку, а если и её нет — растворяется. v1.26: жертва за стеной —
## дух ломает преграду, а не толчётся у неё до рассвета.
func _spirit_update(r: Dictionary, dt: float) -> bool:
	var p: Dictionary = r["p"]
	var vic := _resident_by_id(int(r.get("victim_id", -1)))
	if not vic.is_empty():
		var to: Vector2 = (vic["pos"] as Vector2) - (r["pos"] as Vector2)
		if to.length() <= float(p["attack_range"]) + 10.0:
			if float(r["atk_cd"]) <= 0.0:
				r["atk_cd"] = float(p["attack_cooldown"])
				if _event_rng.randf() < 0.5:
					_make_ail(vic, "wounded", "chron.spirit_hit")
					events.append({"type": "spirit_hit", "name": String(vic["name"])})
				else:
					vic["mood"] = clampf(float(vic["mood"]) - 12.0, 0.0, 100.0)
			return true
		if _raider_move_to(r, map.tile_of_px(vic["pos"]), float(p["speed"]) * dt):
			return true
		return _raider_break_obstacle(r, dt, p, _nearest_building_of(r, ["wall", "gate"]))
	# жертвы нет: мстим лесопилке или растворяемся
	r["ttl"] = float(r.get("ttl", 30.0)) - dt
	if float(r["ttl"]) <= 0.0:
		return false
	var mill := _nearest_building_of(r, ["sawmill"])
	if mill.is_empty():
		return true
	var reach := float(p["attack_range"]) + float(map.ts) * 0.5
	if bld_dist_px(r["pos"], mill) <= reach:
		if float(r["atk_cd"]) <= 0.0:
			r["atk_cd"] = float(p["attack_cooldown"])
			_damage_building(mill, float(p["damage"]))
		return true
	var goal := _walkable_next_to_rect(mill)
	if goal == Vector2i(-1, -1):
		return true
	_raider_move_to(r, goal, float(p["speed"]) * dt)
	return true


# --- M11: посадка леса -------------------------------------------------------

## Годен ли тайл под саженец.
func can_plant_at(tile: Vector2i) -> bool:
	if not map.in_bounds(tile) or map.grid[tile.y][tile.x] != map.TILE_GRASS:
		return false
	if map.stumps.has(tile) or map.saplings.has(tile) or map.logs.has(tile):
		return false
	if not building_at(tile).is_empty() or _tile_in_fill_zone(tile):
		return false
	return true


## Посадить саженец (из пула саженцев — выпадают из деревьев). "" — успех.
func plant_sapling(tile: Vector2i) -> String:
	var fcfg: Dictionary = cfg.get("forest", {})
	if not can_plant_at(tile):
		return "bad"
	if float(res.get("saplings", 0.0)) < 1.0:
		return "no_seeds"
	res["saplings"] = float(res["saplings"]) - 1.0
	map.saplings[tile] = {"t": 0.0, "grow_days": float(fcfg.get("grow_days", 5.0))}
	terrain_dirty = true
	events.append({"type": "sapling_planted"})
	_chron("chron.sapling_planted")
	return ""


# --- M11: добыча скалы -------------------------------------------------------

## Тайл гряды рядом с добытчиком (свой тайл непроходим — берём соседний).
## Пустая порода (deadrock) герою не по зубам — её медленно доит шахта (v1.21).
func _rock_tile_near(px: Vector2) -> Vector2i:
	var base: Vector2i = map.tile_of_px(px)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var t: Vector2i = base + d
		if not map.in_bounds(t) or not map.rock_hp.has(t):
			continue
		if int(map.grid[t.y][t.x]) not in [map.TILE_ROCK, map.TILE_ORE]:
			continue
		return t
	return Vector2i(-1, -1)


# --- ручной труд героя (правки v1.12.2): E у дерева/скалы/стройки -----------

func _hero_work_cfg() -> Dictionary:
	return cfg.get("hero_work", {})


## Дерево у ног героя (свой тайл тоже — деревья проходимы):
## {tile, hits, need} — для подсказки и добивки. Правки v1.21: число ударов
## зависит от размера дерева (малое/среднее/большое).
func hero_tree_near(px: Vector2) -> Dictionary:
	var base: Vector2i = map.tile_of_px(px)
	for t in [base, base + Vector2i(1, 0), base + Vector2i(-1, 0),
			base + Vector2i(0, 1), base + Vector2i(0, -1)]:
		if map.in_bounds(t) and map.grid[t.y][t.x] == map.TILE_TREE:
			return {"tile": t, "hits": int(_chop_progress.get(t, 0)),
					"size": map.tree_kind(t),
					"need": maxi(1, _hero_chop_hits(map.tree_kind(t)))}
	return {}


## Ударов героя на валку дерева размера size.
func _hero_chop_hits(size: int) -> int:
	var table: Dictionary = _hero_work_cfg().get("chop_hits", {})
	var key := "small" if size == map.TREE_SMALL else ("medium" if size == map.TREE_MEDIUM else "large")
	return int(table.get(key, 7))


## Спелая грядка в шаге от героя (этап 2, аспект 3): {zone, idx, tile, crop}.
func hero_harvest_near(px: Vector2) -> Dictionary:
	var base: Vector2i = map.tile_of_px(px)
	for t in [base, base + Vector2i(1, 0), base + Vector2i(-1, 0),
			base + Vector2i(0, 1), base + Vector2i(0, -1)]:
		var z: Dictionary = field_at(t)
		if z.is_empty():
			continue
		for i in (z["cells"] as Array).size():
			if Vector2i(z["cells"][i]) != t or not (z["crops"] as Array).size() > i:
				continue
			var crop: Dictionary = (z["crops"] as Array)[i]
			if bool(crop.get("ripe", false)):
				return {"zone": z, "idx": i, "tile": t, "crop": String(z.get("crop", "turnip"))}
	return {}


## Сбор спелой грядки героем: еда в общий пул, семя возвращается, клетка
## пересеивается той же культурой (за обычное семя). "" — нет спелой грядки.
func hero_harvest(px: Vector2) -> String:
	var h: Dictionary = hero_harvest_near(px)
	if h.is_empty():
		return ""
	_harvest_cell(h["zone"], int(h["idx"]))
	events.append({"type": "hero_harvest"})
	return "food"


## Незаполненная клетка зоны (поле/пастбище/жилая) в шаге от героя:
## {zone, idx, tile} — герой может вспахать её сам (2026-10-21).
func hero_till_near(px: Vector2) -> Dictionary:
	var base: Vector2i = map.tile_of_px(px)
	for t in [base, base + Vector2i(1, 0), base + Vector2i(-1, 0),
			base + Vector2i(0, 1), base + Vector2i(0, -1)]:
		for z in zones:
			for i in (z["cells"] as Array).size():
				if Vector2i(z["cells"][i]) != t or _cell_filled(z, i):
					continue
				if not building_at(t).is_empty():
					continue
				return {"zone": z, "idx": i, "tile": t}
	return {}


## Вспашка клетки зоны героем: каждый E продвигает обустройство на fill_per_hit.
## "" — рядом нет клетки зоны, "till" — удар засчитан, "tilled" — клетка готова.
func hero_till(px: Vector2) -> String:
	var h: Dictionary = hero_till_near(px)
	if h.is_empty():
		return ""
	var z: Dictionary = h["zone"]
	var i := int(h["idx"])
	var fill_work: float = float(cfg.get("zones", {}).get("fill_work", 4.0))
	var was: float = float(z["progress"][i])
	z["progress"][i] = minf(fill_work, was + float(_hero_work_cfg().get("fill_per_hit", 2.0)))
	if float(z["progress"][i]) >= fill_work and was < fill_work:
		events.append({"type": "zone_cell", "zone": String(z["type"])})
		_zone_check_done(z, {})
		return "tilled"
	return "till"


## Засеянная пустая клетка поля в шаге от героя (заполнена, без посева):
## {zone, idx, tile} — герой сеет сам, если семян не нашлось автоматом.
func hero_sow_near(px: Vector2) -> Dictionary:
	var base: Vector2i = map.tile_of_px(px)
	for t in [base, base + Vector2i(1, 0), base + Vector2i(-1, 0),
			base + Vector2i(0, 1), base + Vector2i(0, -1)]:
		for z in zones:
			if String(z["type"]) != "field":
				continue
			var crops: Array = z.get("crops", [])
			for i in (z["cells"] as Array).size():
				if Vector2i(z["cells"][i]) != t or not _cell_filled(z, i):
					continue
				if not building_at(t).is_empty():
					continue
				if crops.size() > i and not (crops[i] as Dictionary).is_empty():
					continue   # уже растёт
				return {"zone": z, "idx": i, "tile": t}
	return {}


## Посев клетки поля героем: 1 семя из пула, росток той же культуры поля.
## "" — сеять нечего, "no_seeds" — нет семян, "sow" — посеяно.
func hero_sow(px: Vector2) -> String:
	var h: Dictionary = hero_sow_near(px)
	if h.is_empty():
		return ""
	var fcfg: Dictionary = cfg.get("farming", {})
	if float(res.get("seeds", 0.0)) < float(fcfg.get("seed_sow", 1)):
		return "no_seeds"
	res["seeds"] = float(res["seeds"]) - float(fcfg.get("seed_sow", 1))
	var zone: Dictionary = h["zone"]
	if not (zone as Dictionary).has("crops"):
		zone["crops"] = []
	var crops: Array = zone["crops"]
	while crops.size() <= int(h["idx"]):
		crops.append({})
	crops[int(h["idx"])] = {"stage": 0, "t": 0.0, "ripe": false}
	events.append({"type": "hero_sow"})
	return "sow"


## Работа фермера (правки v1.21): ферма при постройке распахивает поле вокруг
## себя — грядки стали её собственностью. Фермер сперва собирает спелые клетки
## СВОЕГО поля, затем вспахивает его незаполненные клетки; своё поле в порядке —
## помогает чужим полям и пастбищам. Пассивной еды ферма больше не даёт.
func _farm_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		r["state"] = "idle"
		return
	var farm_id := int(bld["id"])
	# 1) спелая клетка поля — собрать (сначала своё поле)
	var ripe := _nearest_ripe_field_cell(r, farm_id)
	if not ripe.is_empty():
		var tile: Vector2i = ripe["tile"]
		if _arrived(r, tile):
			_harvest_cell(ripe["zone"], int(ripe["idx"]))
			r["state"] = "harvest"
			r["fatigue"] += dt / float(cfg["day_length"])
			_grow_skill(r, dt)
		else:
			_move_towards(r, tile, dt)
		return
	# 2) незаполненная клетка поля — вспахать (сначала своё)
	var fill := _nearest_field_cell(r, farm_id)
	if not fill.is_empty():
		var tile2: Vector2i = fill["tile"]
		if _arrived(r, tile2):
			r["state"] = "fill"
			var zz: Dictionary = fill["zone"]
			var i2 := int(fill["idx"])
			zz["progress"][i2] = float(zz["progress"][i2]) + dt * work_mult(r)
			r["fatigue"] += dt / float(cfg["day_length"])
			_grow_skill(r, dt)
			if _cell_filled(zz, i2):
				events.append({"type": "zone_cell", "zone": "field"})
				_zone_check_done(zz, r)
		else:
			_move_towards(r, tile2, dt)
		return
	# 3) своё поле в порядке — помочь чужим полям и пастбищам, иначе стоит у фермы
	if _zone_fill_work(r, dt):
		return
	if at_bld(r, bld):
		r["state"] = "idle"
	else:
		_move_towards(r, bld_spot(bld), dt)


## Ближайшая спелая клетка поля (сначала поля фермы farm_id, потом любые).
## Правки v1.20.1: цель «липкая» — начатую грядку доводят до конца.
func _nearest_ripe_field_cell(r: Dictionary, farm_id := -1) -> Dictionary:
	var sticky_z: Dictionary = zone_by_id(int(r.get("_ripe_zone", -1)))
	if not sticky_z.is_empty():
		var si := int(r.get("_ripe_idx", -1))
		var scrops: Array = sticky_z.get("crops", [])
		if si >= 0 and si < (sticky_z["cells"] as Array).size() \
				and scrops.size() > si and bool((scrops[si] as Dictionary).get("ripe", false)):
			return {"zone": sticky_z, "idx": si, "tile": sticky_z["cells"][si]}
	var best := {}
	var best_d := INF
	var fallback := {}
	var fallback_d := INF
	for z in zones:
		if String(z["type"]) != "field":
			continue
		var own := farm_id > 0 and int(z.get("farm", -1)) == farm_id
		var crops: Array = z.get("crops", [])
		for i in (z["cells"] as Array).size():
			if not _cell_filled(z, i) or not building_at(z["cells"][i]).is_empty():
				continue
			# v1.28: null-дыры в посевах старых сейвов не роняют поиск
			if crops.size() <= i or not (crops[i] is Dictionary) \
					or not bool((crops[i] as Dictionary).get("ripe", false)):
				continue
			var d: float = map.tile_center_px(z["cells"][i]).distance_to(r["pos"])
			if own and d < best_d:
				best_d = d
				best = {"zone": z, "idx": i, "tile": z["cells"][i]}
			elif not own and d < fallback_d:
				fallback_d = d
				fallback = {"zone": z, "idx": i, "tile": z["cells"][i]}
	if best.is_empty():
		best = fallback
	if not best.is_empty():
		r["_ripe_zone"] = int((best["zone"] as Dictionary)["id"])
		r["_ripe_idx"] = int(best["idx"])
	else:
		r["_ripe_zone"] = -1
		r["_ripe_idx"] = -1
	return best


## Незаполненная клетка поля: сначала поле своей фермы (липкая цель).
func _nearest_field_cell(r: Dictionary, farm_id := -1) -> Dictionary:
	# липкая цель (правки v1.20.1): начатую клетку доводим до конца
	var sticky_z: Dictionary = zone_by_id(int(r.get("_fill_zone", -1)))
	if not sticky_z.is_empty():
		var si := int(r.get("_fill_idx", -1))
		if si >= 0 and si < (sticky_z["cells"] as Array).size() \
				and String(sticky_z["type"]) == "field" \
				and not _cell_filled(sticky_z, si) \
				and building_at(sticky_z["cells"][si]).is_empty():
			return {"zone": sticky_z, "idx": si, "tile": sticky_z["cells"][si]}
	var best := {}
	var best_d := INF
	var fallback := {}
	var fallback_d := INF
	for z in zones:
		if String(z["type"]) != "field":
			continue
		var own := farm_id > 0 and int(z.get("farm", -1)) == farm_id
		for i in (z["cells"] as Array).size():
			if _cell_filled(z, i) or not building_at(z["cells"][i]).is_empty():
				continue
			var d: float = map.tile_center_px(z["cells"][i]).distance_to(r["pos"])
			if own and d < best_d:
				best_d = d
				best = {"zone": z, "idx": i, "tile": z["cells"][i]}
			elif not own and d < fallback_d:
				fallback_d = d
				fallback = {"zone": z, "idx": i, "tile": z["cells"][i]}
	if best.is_empty():
		best = fallback
	if not best.is_empty():
		r["_fill_zone"] = int((best["zone"] as Dictionary)["id"])
		r["_fill_idx"] = int(best["idx"])
	else:
		r["_fill_zone"] = -1
		r["_fill_idx"] = -1
	return best


## Скала или рудная жила в шаге от героя: {tile, kind: "rock"|"ore"}.
func hero_rock_near(px: Vector2) -> Dictionary:
	var tile: Vector2i = _rock_tile_near(px)
	if tile == Vector2i(-1, -1):
		return {}
	return {"tile": tile,
			"kind": "ore" if int(map.grid[tile.y][tile.x]) == map.TILE_ORE else "rock"}


## Недостроенное здание в шаге от героя ({}, если стройки рядом нет).
func hero_site_near(px: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1.6 * float(map.ts) + float(map.ts) * 0.5   # прямоугольник 2×2: чуть щедрее
	for b in buildings:
		if bool(b["done"]):
			continue
		var d: float = bld_dist_px(px, b)
		if d <= best_d:
			best_d = d
			best = b
	return best


## Удар топором: hits зависят от размера — малое 4, среднее 7, большое 11.
## Поваленное дерево ложится БРЕВНОМ на землю (v1.21.2: доски даёт только
## лесопилка) — лесоруб подберёт и распилит; пень и гнев леса как у всех,
## из дерева выпадают саженцы.
## "" — рядом нет дерева, "hit" — удар засчитан, "fell" — дерево повалено.
func hero_chop(px: Vector2) -> String:
	var tree: Dictionary = hero_tree_near(px)
	if tree.is_empty():
		return ""
	var tile: Vector2i = tree["tile"]
	var hits := int(_chop_progress.get(tile, 0)) + 1
	if hits < int(tree["need"]):
		_chop_progress[tile] = hits
		return "hit"
	_chop_progress.erase(tile)
	var fcfg: Dictionary = cfg.get("forest", {})
	map.grid[tile.y][tile.x] = map.TILE_GRASS
	map.stumps[tile] = true
	map.tree_size.erase(tile)
	map.tree_growth.erase(tile)
	map.logs[tile] = {"size": int(tree["size"])}   # бревно ждёт лесопилку (v1.21.2)
	terrain_dirty = true
	forest_anger = clampf(forest_anger + float(fcfg.get("anger_per_tree", 1.0)), 0.0, 100.0)
	_drop_saplings()   # из поваленного дерева выпадают саженцы
	events.append({"type": "tree_felled", "log": true})
	_chron("chron.tree_felled")
	return "fell"


## Удар киркой: герою — только строительный камень (железо и кристаллы
## добывают каменоломня и шахта, v1.21). Выработанный тайл не исчезает:
## под ним жила (шанс) или пустая порода — место под шахту.
## "" — рядом нет скалы, "hit" — удар засчитан, "ore"/"stone" — тайл выработан.
func hero_mine(px: Vector2) -> String:
	var rock: Dictionary = hero_rock_near(px)
	if rock.is_empty():
		return ""
	var mcfg: Dictionary = cfg.get("mountain", {})
	var tile: Vector2i = rock["tile"]
	_add_resource_capped("stone", float(_hero_work_cfg().get("stone_per_hit", 2)))
	var max_hp := _rock_max_hp(tile)
	var hp := float(map.rock_hp.get(tile, max_hp)) \
			- max_hp / float(maxi(1, int(_hero_work_cfg().get("mine_hits", 4))))
	if hp > 0.0:
		map.rock_hp[tile] = hp
		return "hit"
	# тайл выработан: жила или пустая порода (v1.21 — травы больше нет)
	var kind := int(map.grid[tile.y][tile.x])
	var roll := _event_rng.randf()
	map.rock_hp.erase(tile)
	terrain_dirty = true
	if kind == map.TILE_ROCK and roll < float(mcfg.get("ore_reveal", 0.25)):
		map.grid[tile.y][tile.x] = map.TILE_ORE
		map.refresh_tile_solid(tile)
		map.rock_hp[tile] = _rock_max_hp(tile)
		events.append({"type": "ore_revealed"})
		_chron("chron.ore_revealed")
		return "ore"
	_add_resource_capped("stone", float(mcfg.get("bonus_stone", 6)))
	map.grid[tile.y][tile.x] = map.TILE_DEADROCK
	map.rock_hp[tile] = float(mcfg.get("deadrock_hp", 60.0))
	map.refresh_tile_solid(tile)
	events.append({"type": "rock_gone"})
	_chron("chron.rock_gone")
	return "stone"


## Удар молотком у стройки: работа идёт в прогресс, достройка — общая
## (стены становятся преградой, декор радует, заказ «построить» закрывается).
## "" — рядом нет стройки, "hit" — удар засчитан, "done" — здание готово.
func hero_build(px: Vector2) -> String:
	var site: Dictionary = hero_site_near(px)
	if site.is_empty():
		return ""
	site["progress"] = float(site["progress"]) + float(_hero_work_cfg().get("build_per_hit", 2.5))
	if float(site["progress"]) >= float(_def(site)["build_work"]):
		_complete_site(site)
		return "done"
	return "hit"


# --- M11: некромант и кладбище ----------------------------------------------

## Кладбище ({} — нет): готовое здание или место, основанное первой могилой (v1.23).
func _cemetery() -> Dictionary:
	return _cemetery_spot()


## Закопанный прах (v1.23): тьма питается именно им — сожжённые чисты.
func _buried_count() -> int:
	var n := 0
	for g in graves:
		if String(g.get("rite", "bury")) == "bury":
			n += 1
	return n


## Ночной ритуал (дневной бросок): зов слышит один из наименее мудрых жителей
## (мудрость противится тьме, v1.24), только когда на кладбище есть закопанный
## прах (легендарный случай); тьма растёт от закопанных, армия — только от
## ночных ритуалов некроманта (см. _necro_night_walk) — без ритуалов мёртвые
## не встанут. Исключение — тёмная буря: при storm_dark тьмы мёртвые
## поднимаются и сами. Здание кладбища пассивно гасит тьму (_update_cemetery).
func _roll_necro() -> void:
	var ncfg: Dictionary = cfg.get("necro", {})
	var cem := _cemetery()
	if ncfg.is_empty() or cem.is_empty():
		return
	var buried := _buried_count()
	# однажды кто-то из взрослых «слышит зов»: мудрые противятся (v1.24)
	if not _necro_chosen and buried >= 1 \
			and _event_rng.randf() < float(ncfg.get("call_chance", 0.05)):
		var cands := _adults()
		cands.sort_custom(func(a, b) -> bool:
			return _stat(a, "wis") < _stat(b, "wis"))
		if not cands.is_empty():
			# зов берёт одного из трёх наименее мудрых
			var who: Dictionary = cands[_event_rng.randi_range(0, mini(2, cands.size() - 1))]
			who["secret"] = "necromancer"
			_necro_chosen = true
			_chron("chron.necro_chosen", String(who["name"]))
	# кладбище темнеет: тьму кормит закопанный прах; всё сожжено — тьма тает
	var dark_rate := float(ncfg.get("dark_base", 0.4)) \
			+ float(ncfg.get("dark_grave_factor", 0.15)) * float(buried)
	if buried == 0:
		dark_rate = -float(ncfg.get("dark_decay", 0.03))
	necro_dark = clampf(necro_dark + float(ncfg.get("dark_per_night", 0.06)) * dark_rate, 0.0, 1.0)
	if not necro_known and necro_dark >= float(ncfg.get("reveal_dark", 0.45)):
		necro_known = true
		events.append({"type": "necro_revealed"})
		_chron("chron.necro_revealed")
	# раскрытая некромантия: у кладбища видны огни и тени (армия растёт
	# только от ночных ритуалов — v1.23)
	if necro_known and _event_rng.randf() < float(ncfg.get("summon_chance", 0.6)):
		necro_ghosts.clear()
		var c: Vector2i = cem["tile"]
		for i in mini(3, necro_army):
			var t := _walkable_next_to(c + Vector2i(_event_rng.randi_range(-1, 1), _event_rng.randi_range(-1, 1)))
			if t != Vector2i(-1, -1):
				necro_ghosts.append(map.tile_center_px(t))
		events.append({"type": "necro_summon"})
	# тёмная буря (v1.24): тьма перелилась через край — мёртвые встают и без
	# некроманта, буря спускает накопленную тьму
	if not raid_active and necro_dark >= float(ncfg.get("storm_dark", 0.5)) \
			and _event_rng.randf() < float(ncfg.get("storm_chance", 0.08)):
		_spawn_undead_wave(clampi(buried, 2, int(ncfg.get("wave_max", 8))))
		events.append({"type": "dark_storm"})
		_chron("chron.dark_storm")
		necro_dark = clampf(necro_dark - 0.25, 0.0, 1.0)
	# тайная армия созрела — восстание (армия растёт только от ритуалов)
	if necro_army >= int(ncfg.get("rise_at", 8)):
		_spawn_undead_wave()


## Ночной путь некроманта (v1.23): крадётся к могилам, режется над прахом
## и возвращается к рассвету. Поймать можно ТОЛЬКО на кладбище — в пути он
## тень среди теней (v1.24): разоблачение лишь пока длится ритуал.
## False — некромант этой ночью спит как все.
func _necro_night_walk(r: Dictionary, dt: float) -> bool:
	if raid_active or _raid_warned or _is_golem(r):
		return false
	var ncfg: Dictionary = cfg.get("necro", {})
	var cem := _cemetery()
	if cem.is_empty() or float(r.get("fatigue", 0.0)) >= float(cfg.get("tired_at", 0.85)):
		return false
	var day_len := float(cfg["day_length"])
	var phase := String(r.get("necro_phase", ""))
	if phase == "":
		r["necro_phase"] = "go"
		r["necro_study"] = 0.0
		phase = "go"
	if phase == "go":
		var goal: Vector2i = map.nearest_walkable(Vector2i(cem["tile"]))
		if not _arrived(r, goal):
			_move_towards(r, goal, dt)
			r["state"] = "sneak"
			r["fatigue"] += dt / day_len * 0.5
			return true
		r["necro_phase"] = "rite"
		phase = "rite"
	if phase == "rite":
		# только здесь, у могил, его можно увидеть (v1.24)
		if _necro_seen(r):
			_necro_caught(r)
			return true
		r["state"] = "necro"
		r["path"] = PackedVector2Array()
		r["necro_study"] = float(r.get("necro_study", 0.0)) + dt
		r["fatigue"] += dt / day_len
		# над могилами теплятся огни — тень запрещённого искусства
		if _event_rng.randf() < dt * 0.05 and necro_ghosts.size() < 3:
			var gt := _walkable_next_to(Vector2i(cem["tile"])
					+ Vector2i(_event_rng.randi_range(-1, 1), _event_rng.randi_range(-1, 1)))
			if gt != Vector2i(-1, -1):
				necro_ghosts.append(map.tile_center_px(gt))
		var need := float(ncfg.get("night_ritual_frac", 0.6)) * day_len * float(cfg["night_fraction"])
		if float(r["necro_study"]) >= need:
			# ночь у могил удалась: тьма гуще, армия крепнет
			necro_dark = clampf(necro_dark + float(ncfg.get("ritual_dark", 0.02)), 0.0, 1.0)
			if _event_rng.randf() < float(ncfg.get("army_per_ritual_chance", 0.5)):
				necro_army += _event_rng.randi_range(1, 2)
			_chron("chron.necro_whisper")
			r["necro_phase"] = "done"
		return true
	# "done": до рассвета — тихо домой
	var home = r.get("home", null)
	var hgoal: Vector2i = bld_spot(home) if home != null and not (home as Dictionary).is_empty() \
			else map.nearest_walkable(map.spawn_tile)
	if not _arrived(r, hgoal):
		_move_towards(r, hgoal, dt)
		r["state"] = "sneak"
		r["fatigue"] += dt / day_len * 0.5
		return true
	r["necro_phase"] = ""
	return false   # дома — засыпает как все


## Заметит ли кто-нибудь тайного некроманта: бодрствующий (не спящий, не в
## доме) житель или герой в радиусе sight_radius клеток.
func _necro_seen(r: Dictionary) -> bool:
	var radius := float(cfg.get("necro", {}).get("sight_radius", 4.0)) * float(map.ts)
	for other in residents:
		if other == r or int(other.get("inside", 0)) == 1:
			continue
		var st := String(other.get("state", ""))
		if st == "sleep" or st == "" or bool(other.get("golem", false)):
			continue
		if Vector2(other["pos"]).distance_to(r["pos"]) <= radius:
			return true
	return hero_alive and hero_pos.distance_to(r["pos"]) <= radius


## Скрыт ли некромант от смотрящего (v1.24): на кладбище ночная тьма прячет
## его — пока не подойти на hidden_radius клеток (4), он не виден вовсе.
func necro_hidden_from(r: Dictionary, viewer_px: Vector2) -> bool:
	if String(r.get("secret", "")) != "necromancer":
		return false
	var cem := _cemetery()
	if cem.is_empty():
		return false
	var at_cem: float = Vector2(r["pos"]).distance_to(map.tile_center_px(Vector2i(cem["tile"])))
	if at_cem > float(map.ts) * 2.5:
		return false   # прячет только кладбище
	var radius := float(cfg.get("necro", {}).get("hidden_radius", 4.0)) * float(map.ts)
	return viewer_px.distance_to(r["pos"]) > radius


## Некроманта увидели (v1.23): тайна раскрыта, городу не по себе.
func _necro_caught(r: Dictionary) -> void:
	r["necro_phase"] = ""
	necro_known = true
	events.append({"type": "necro_revealed", "name": String(r["name"])})
	_chron("chron.necro_seen", String(r["name"]))
	for other in residents:
		if other != r:
			other["mood"] = clampf(float(other["mood"]) - 6.0, 0.0, 100.0)


## Восстание (M11): мертвецы выходят из кладбища, армия тает вдвое.
## v1.24: storm_size >= 0 — волна тёмной бури (мёртвые встают сами,
## по числу закопанных могил; тайная армия некроманта не тратится).
func _spawn_undead_wave(storm_size := -1) -> void:
	var ncfg: Dictionary = cfg.get("necro", {})
	var cem := _cemetery()
	if cem.is_empty():
		return
	if _enemies_cfg.is_empty():
		var ed: Variant = _read_json_file("res://data/enemies.json")
		_enemies_cfg = ed if ed is Array else []
	var skel: Dictionary = {}
	for d: Dictionary in _enemies_cfg:
		if String(d["id"]) == "skeleton":
			skel = d
			break
	if skel.is_empty():
		return
	raid_active = true
	raid_siege = true
	_raid_kind = "undead"
	var size := clampi(storm_size, 1, int(ncfg.get("wave_max", 8))) if storm_size >= 0 \
			else mini(necro_army, int(ncfg.get("wave_max", 8)))
	if storm_size < 0:
		necro_army = int(necro_army / 2)
	var hp_mult := 1.0 + threat_value() * float(cfg.get("threat", {}).get("hp_per_threat", 0.04))
	var anchor: Vector2i = cem["tile"]
	for i in size:
		var hp := int(round(float(skel["hp"]) * hp_mult))
		var t := _walkable_next_to(anchor)
		raiders.append({
			"id": _next_id, "type": "skeleton", "p": skel,
			"hp": hp, "max_hp": hp,
			"pos": map.tile_center_px(t if t != Vector2i(-1, -1) else anchor),
			"target": Vector2i(-1, -1), "path": PackedVector2Array(),
			"atk_cd": 0.0, "mode": "advance",
		})
		_next_id += 1
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + float(ncfg.get("mood_hit", -8.0)), 0.0, 100.0)
	events.append({"type": "undead_rising", "count": size})
	_chron("chron.undead_rising", str(size))
	_update_gates()


## Кладбище разрушено — тайная армия рассыпается, некромант раскрыт.
func _necro_purge() -> void:
	necro_army = 0
	necro_dark = 0.0
	necro_ghosts = []
	for r in residents:
		if String(r.get("secret", "")) == "necromancer":
			r["secret"] = ""
			r["mood"] = clampf(float(r["mood"]) - 15.0, 0.0, 100.0)
	_necro_chosen = false
	events.append({"type": "necro_purged"})
	_chron("chron.necro_purged")


## Удар героя по кладбищу (M11): единственное здание, которое герой рушит сам.
## Возвращает "" | "necro_hit" | "necro_purged".
func hero_hit_building(origin_px: Vector2, facing: Vector2, range_px: float, arc_deg: float, dmg: int) -> String:
	for b in buildings:
		if String(b["type"]) != "cemetery" or not _active(b):
			continue
		var to: Vector2 = map.tile_center_px(b["tile"]) - origin_px
		if to.length() > range_px + float(map.ts) * 0.6:
			continue
		if absf(facing.angle_to(to)) > deg_to_rad(arc_deg) / 2.0:
			continue
		_damage_building(b, float(dmg))
		return "necro_purged" if bool(b.get("razed", false)) else "necro_hit"
	return ""
