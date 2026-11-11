# Часть: некромант и кладбище — обряды, могилы, тьма, восстание мёртвых (M11/v1.23).
# Структура v1.62.0: некромант переехал сюда из city_sim_threat.gd,
# кладбище — из city_sim_tick.gd. Один класс, поведение не меняется.
extends "res://scripts/city_sim_nature.gd"

# --- кладбище (M12 + v1.23): обряды, основание места, останки -----------------

## Конфиг кладбища.
func _cemetery_cfg() -> Dictionary:
	return cfg.get("cemetery", {})


## Место кладбища: готовое здание, основанное первой могилой место, или {}.
func _cemetery_spot() -> Dictionary:
	for b in buildings:
		if _active(b) and String(b["type"]) == "cemetery":
			return b
	if cemetery_tile != Vector2i(-1, -1):
		return {"tile": cemetery_tile, "id": -1}
	return {}


## Первая могила основывает кладбище (v1.23): трава в ~found_dist клетках
## от ближайшего строения города (но не дальше max_dist), поближе к городу.
func _found_cemetery_tile() -> Vector2i:
	var ccfg := _cemetery_cfg()
	var min_d := float(ccfg.get("found_dist", 10.0))
	var max_d := float(ccfg.get("max_dist", 22.0))
	var best := Vector2i(-1, -1)
	var best_score := INF
	for y in range(2, map.h - 2):
		for x in range(2, map.w - 2):
			var t := Vector2i(x, y)
			if not map.in_bounds(t) or not map.is_nature_walkable(t):
				continue
			if map.grid[t.y][t.x] != map.TILE_GRASS:
				continue
			if not building_at(t).is_empty() or _tile_in_zone(t) or near_plaza(t):
				continue
			if map.stumps.has(t) or map.saplings.has(t) or map.logs.has(t):
				continue
			var nearest := INF
			if buildings.is_empty():
				nearest = Vector2(map.spawn_tile).distance_to(Vector2(t))
			else:
				for b in buildings:
					nearest = minf(nearest, Vector2(b["tile"]).distance_to(Vector2(t)))
			if nearest < min_d or nearest > max_d:
				continue
			var score: float = absf(nearest - min_d) \
					+ Vector2(t).distance_to(Vector2(map.spawn_tile)) * 0.05
			if score < best_score:
				best_score = score
				best = t
	return best


## Похороны (M12): носильщик дошёл до кладбища — стоит прощание, могилка
## готова (закопанным — сразу; погребальный костёр догорает два дня, v1.23).
func _funeral_update(r: Dictionary, dt: float) -> void:
	if not _arrived(r, funeral_target):
		_move_towards(r, funeral_target, dt)
		if String(r["state"]) != "going":
			r["funeral"] = 0   # не добрался — вернулся к делам
		return
	r["state"] = "funeral"
	r["path"] = PackedVector2Array()
	r["funeral_wait"] = float(r.get("funeral_wait", 0.0)) + dt
	if float(r["funeral_wait"]) >= 2.0:
		r["funeral"] = 0
		r["funeral_wait"] = 0.0
		for g in graves:
			if not bool(g.get("ready", false)) and String(g.get("rite", "bury")) == "bury":
				g["ready"] = true


## Обряд горожане выбирают сами (v1.23): закопать — быстро и дёшево, сжечь —
## дрова (или магия алтаря) и два дня, зато прах не кормит тьму кладбища.
## Избранное божество склоняет выбор: Пепел — предать огню, Дом — земле.
func _pick_rite() -> String:
	var ccfg := _cemetery_cfg()
	var rite := String(god_def().get("rite", ""))
	if rite == "":
		rite = "burn" if _event_rng.randf() < float(ccfg.get("burn_share_no_god", 0.25)) else "bury"
	if rite != "burn":
		return "bury"
	var wood := float(ccfg.get("burn_cost_wood", 3))
	var cry := float(ccfg.get("burn_cost_crystal", 1))
	if float(res.get("wood", 0.0)) >= wood:
		res["wood"] = float(res["wood"]) - wood
		return "burn"
	if altar_ready() and float(res.get("crystal", 0.0)) >= cry:
		res["crystal"] = float(res["crystal"]) - cry
		return "burn"   # костёр зажгла магия алтаря
	return "bury"   # на костёр не наскребли — закопали как смогли


## Запуск похорон: свободные жители несут умершего к кладбищу, готовится
## могила. Кладбища нет — первая могила основывает его (v1.23).
func _start_funeral(dead: Dictionary, dead_pos: Vector2) -> void:
	var cem := _cemetery_spot()
	if cem.is_empty():
		var tile := _found_cemetery_tile()
		if tile == Vector2i(-1, -1):
			return   # места под кладбище не нашлось
		cemetery_tile = tile
		cem = {"tile": tile, "id": -1}
		events.append({"type": "cemetery_founded"})
		_chron("chron.cemetery_founded")
	var grave := _next_grave_tile(Vector2i(cem["tile"]))
	if grave == Vector2i(-1, -1):
		return
	var rite := _pick_rite()
	var g := {"tile": grave, "name": String(dead["name"]), "ready": false, "rite": rite}
	if rite == "burn":
		g["burn_left"] = float(_cemetery_cfg().get("burn_days", 2.0))
	graves.append(g)
	funeral_target = map.nearest_walkable(Vector2i(cem["tile"]))
	funeral_pos = dead_pos
	var bearers := 0
	for other in residents:
		if other == dead or String(other["prof"]) == "" or String(other.get("ail", "")) != "":
			continue
		if other["site"] != null or other["bld"] != null or int(other.get("funeral", 0)) > 0:
			continue
		other["funeral"] = 1
		other["funeral_wait"] = 0.0
		bearers += 1
		if bearers >= 2:
			break


## Место под могилку: свободный травяной тайл по спирали вокруг кладбища
## (v1.23: кладбище растёт до grow_radius клеток от первой могилы).
func _next_grave_tile(center: Vector2i) -> Vector2i:
	for radius in range(1, int(_cemetery_cfg().get("grow_radius", 5)) + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := center + Vector2i(dx, dy)
				if not map.in_bounds(t) or not map.is_nature_walkable(t):
					continue
				if not building_at(t).is_empty():
					continue
				var taken := false
				for g in graves:
					if Vector2i(g["tile"]) == t:
						taken = true
						break
				if not taken:
					return t
	return Vector2i(-1, -1)


## Кладбище живёт (v1.23): погребальные костры догорают (два дня) и прах
## успокаивается, останки врагов истлевают, если их не унесли.
## v1.24: ГОТОВОЕ ЗДАНИЕ кладбища само гонит тьму — освящённая земля
## выжигает её день за днём, и без ритуалов некроманта мёртвым не встать.
func _update_cemetery(dt: float, day_len: float) -> void:
	var bld_decay := 0.0
	for b in buildings:
		if _active(b) and String(b["type"]) == "cemetery":
			bld_decay = float(_cemetery_cfg().get("building_decay_per_day", 0.08))
			break
	if bld_decay > 0.0 and necro_dark > 0.0:
		necro_dark = maxf(0.0, necro_dark - bld_decay * dt / day_len)
	for g in graves:
		if bool(g.get("ready", false)) or String(g.get("rite", "bury")) != "burn":
			continue
		g["burn_left"] = float(g.get("burn_left", 2.0)) - dt / day_len
		if float(g["burn_left"]) <= 0.0:
			g["ready"] = true
			g.erase("burn_left")
			events.append({"type": "cremated", "name": String(g.get("name", ""))})
			_chron("chron.cremated", String(g.get("name", "")))
			for r in residents:
				r["mood"] = clampf(float(r["mood"]) + float(_cemetery_cfg().get("burn_mood", 2.0)), 0.0, 100.0)
	var rot := float(_cemetery_cfg().get("corpse_rot_days", 3.0))
	if rot <= 0.0:
		return
	var gone := []
	for c in corpses:
		c["rot"] = float(c.get("rot", 0.0)) + dt / day_len
		if float(c["rot"]) >= rot:
			gone.append(c)
	for c in gone:
		corpses.erase(c)


## Ежедневный бросок (v1.23): останки врагов кто-то сгребает и относит на
## кладбище — до двух носильщиков в день; не успели — истлеют.
func _roll_corpse_haul() -> void:
	if corpses.is_empty():
		return
	var assigned := 0
	for r in residents:
		if assigned >= mini(2, corpses.size()):
			break
		if String(r["prof"]) in ["", "elder", "guard"] or String(r.get("ail", "")) != "":
			continue
		if r["site"] != null or r["bld"] != null or int(r.get("funeral", 0)) > 0 \
				or int(r.get("spar_with", -1)) >= 0 or not (r.get("corpse_task", {}) as Dictionary).is_empty():
			continue
		var task := {}
		for c in corpses:
			if not c.has("claim"):
				task = c
				break
		if task.is_empty():
			break
		task["claim"] = int(r["id"])
		r["corpse_task"] = {"tile": task["tile"], "kind": task["kind"]}
		assigned += 1


## Ноша останков (v1.23): дойти, поднять, отнести на кладбище и похоронить.
## Врагу тоже нужна могила — иначе тьма кладбища останется голодной… или нет?
func _corpse_work(r: Dictionary, dt: float) -> bool:
	var task: Dictionary = r.get("corpse_task", {})
	if task.is_empty():
		return false
	var cem := _cemetery_spot()
	if cem.is_empty():
		r["corpse_task"] = {}
		return false
	if task.has("tile"):
		# идём за останками
		var tile: Vector2i = task["tile"]
		var found := false
		for c in corpses:
			if Vector2i(c["tile"]) == tile and int(c.get("claim", -1)) == int(r["id"]):
				found = true
				break
		if not found:
			r["corpse_task"] = {}   # истлели или унесли другие
			return false
		if not map.is_walkable(tile):
			r["corpse_task"] = {}   # останки замурованы — бросаем
			return false
		if not _arrived(r, tile):
			_move_towards(r, tile, dt)
			r["state"] = "porter"
			return true
		for c in corpses:
			if Vector2i(c["tile"]) == tile and int(c.get("claim", -1)) == int(r["id"]):
				corpses.erase(c)
				break
		r["corpse_task"] = {"kind": String(task["kind"])}
		r["carry_slow"] = 0.85
		return true
	# несём на кладбище
	var goal: Vector2i = map.nearest_walkable(Vector2i(cem["tile"]))
	if not _arrived(r, goal):
		_move_towards(r, goal, dt)
		r["state"] = "porter"
		return true
	var grave := _next_grave_tile(Vector2i(cem["tile"]))
	if grave != Vector2i(-1, -1):
		graves.append({"tile": grave, "name": "", "kind": String(task["kind"]),
				"ready": true, "rite": "bury"})
		events.append({"type": "corpse_buried", "kind": String(task["kind"])})
		_chron("chron.corpse_buried")
	r["corpse_task"] = {}
	r["carry_slow"] = 1.0
	return false


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
