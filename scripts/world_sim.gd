extends RefCounted
## Мир живёт программно (M8, ответ №92): события вне локаций считаются
## абстрактно и материализуются при визите. Каждый день пути:
## лагеря бандитов растут, бандиты осаждают поселения, павшие поселения
## переселяются другими фракциями (ответ №4), зачищенные данжи сгущаются
## заново, караван перебирается в новые места. Чистая логика — headless-тесты.
##
## События копятся в events (читает сцена) и летописью уходят в город.
## Торговля (ответ №40): монеты + живой обмен. Покупка/продажа ресурсов
## идёт с пулом города — караван доставляет товар (упрощение первого захода).

var map = null                  # world_map.gd, нетипизированно (грабли GDScript 4)
var cfg: Dictionary = {}        # data/world.json
var day := 0                    # дни мира (синхронно с днями города)
var events: Array = []          # [{"type": "siege_start"|...}] — читает сцена
var chronicle: Array = []       # мировая летопись [{day, key, a, b}] — сцена отдаст городу
var sieges: Array = []          # активные осады: {settlement_id, camp_id, left}
var tracks := {}                # Vector2i -> {dir: Vector2i, camp: int, age: int} — следы (M12)
var giants = null               # world_giants.gd — грандиозные создания (M14-E)
var rep: Dictionary = {}        # репутация фракций (M14-H): id -> −100..100
var legends: Array = []         # легендарные странники (v1.22): {id, def, tile, path, state, target_poi, days_left, rumor_used}
var _legend_id := 1
var _rng := RandomNumberGenerator.new()


## --- дипломатия (M14-H, issue #3 H.3) ---------------------------------------

func _factions_cfg() -> Dictionary:
	var parsed: Variant = _read_json_file("res://data/factions.json")
	return parsed if parsed is Dictionary else {}


func get_rep(faction: String) -> float:
	return float(rep.get(faction, 0.0))


func add_rep(faction: String, delta: float) -> void:
	rep[faction] = clampf(get_rep(faction) + delta, -100.0, 100.0)


## Дань фракции (панель управления платит монеты): +репутация.
func tribute(faction: String) -> bool:
	var fcfg: Dictionary = _factions_cfg()
	for f in fcfg.get("factions", []):
		if String(f["id"]) == faction:
			add_rep(faction, float(fcfg.get("tribute_rep", 10)))
			_chron("chron.tribute", faction)
			return true
	return false


## Мир с бандитами: их осады прекращаются.
func bandits_peace() -> bool:
	return get_rep("bandits") >= float(_factions_cfg().get("peace_rep", 60))


## Заказ фракции доступен от порога репутации.
func faction_quest_available(faction: String) -> bool:
	return get_rep(faction) >= float(_factions_cfg().get("quest_rep_min", 40))


func setup(world_map, world_cfg: Dictionary, seed_value := -1) -> void:
	map = world_map
	cfg = world_cfg
	day = 0
	events = []
	chronicle = []
	sieges = []
	tracks = {}
	# гиганты (M14-E): состояние переживает сейв через блок "giants"
	giants = load("res://scripts/world_giants.gd").new()
	giants.setup(map, _read_json_file("res://data/giants.json"), seed_value)
	_spawn_legends()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Один день мира. Возвращает события дня (и копит их в events).
func advance_day() -> Array:
	day += 1
	var today: Array = []
	_grow_camps()
	_update_tracks()
	_roll_tracks()
	today.append_array(_update_sieges())
	today.append_array(_roll_sieges())
	today.append_array(_roll_resettlement())
	today.append_array(_roll_dungeon_resets())
	today.append_array(_roll_caravan())
	today.append_array(_tick_legends())
	if giants != null:
		giants.tick_days(1)   # гнев и дружба гигантов остывают (M14-E)
	events.append_array(today)
	return today


# --- гнёзда бандитов: живые колонии (M12) ---------------------------------
# Скауты ежедневно расширяют радиус поиска (осады чаще), добытчики таскают
# добычу (гнездо богатеет — жирнее лут), строители укрепляют (враги сильнее).
# Идеи — из референса new-world-v-2 (enemy/nest.gd), код свой.

func _grow_camps() -> void:
	var scfg: Dictionary = cfg.get("sim", {})
	var ncfg: Dictionary = cfg.get("nests", {})
	var gmin := float(scfg.get("camp_growth_min", 0.0))
	var gmax := float(scfg.get("camp_growth_max", 2.0))
	for poi in map.pois:
		if String(poi["kind"]) == "camp" and int(poi["cleared_day"]) < 0:
			poi["strength"] = float(poi["strength"]) + _rng.randf_range(gmin, gmax)
			poi["nest_days"] = int(poi.get("nest_days", 0)) + 1
			poi["nest_level"] = mini(int(ncfg.get("max_level", 3)),
					floori(float(int(poi["nest_days"])) / maxf(1.0, float(ncfg.get("level_days", 4)))))
			if int(poi["nest_level"]) >= 1:
				poi["plunder"] = float(poi.get("plunder", 0.0)) + float(ncfg.get("plunder_per_day", 1.0))


## Уровень гнезда для HUD (0..3).
func nest_level(poi: Dictionary) -> int:
	return int(poi.get("nest_level", 0))


## Скауты: живые лагеря с уровня гнезда оставляют цепочки следов от гнезда —
## герой выслеживает гнездо по стрелкам, пройдя по следу — затирает его.
func _roll_tracks() -> void:
	var ncfg: Dictionary = cfg.get("nests", {})
	if ncfg.is_empty():
		return
	for poi in map.pois:
		if String(poi["kind"]) != "camp" or int(poi["cleared_day"]) >= 0:
			continue
		var level := int(poi.get("nest_level", 0))
		if level < 1:
			continue
		# M14-G: скауты высокого гнезда прячут следы — шанс и длина падают
		var chance := float(ncfg.get("track_chance", 0.3)) * maxf(
				float(ncfg.get("track_chance_min", 0.25)),
				1.0 - float(ncfg.get("track_hide_per_level", 0.15)) * float(level))
		if _rng.randf() > chance:
			continue
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var dir: Vector2i = dirs[_rng.randi_range(0, 3)]
		var tile: Vector2i = poi["tile"]
		var length := _track_length_for(ncfg, level)
		for i in length:
			tile += dir
			if not map.in_bounds(tile) or not map.is_walkable(tile):
				break
			if not tracks.has(tile):
				tracks[tile] = {"dir": dir, "camp": int(poi["id"]), "age": 0}


## Длина цепочки следов с учётом уровня гнезда (отдельно — для тестов).
func _track_length_for(ncfg: Dictionary, level: int) -> int:
	var length := _rng.randi_range(int(ncfg.get("track_len_min", 3)), int(ncfg.get("track_len_max", 6)))
	var shrink := float(ncfg.get("track_len_shrink_per_level", 0.12))
	return maxi(2, roundi(float(length) * maxf(0.4, 1.0 - shrink * float(level))))


func _update_tracks() -> void:
	if tracks.is_empty():
		return
	var ttl := int(cfg.get("nests", {}).get("track_ttl", 5))
	var gone: Array = []
	for t in tracks:
		var tr: Dictionary = tracks[t]
		tr["age"] = int(tr["age"]) + 1
		if int(tr["age"]) > ttl:
			gone.append(t)
	for t in gone:
		tracks.erase(t)


## Герой осматривается (M12→M14-G): затирает след под ногами; рядом со следом
## неоткрытого гнезда — открывает следующий тайл цепочки (выслеживание).
## Узел «выжившего» (skills.json -> track_spot/track_wipe) расширяет радиусы.
func track_scout(hero_tile: Vector2i, spot_bonus := 0, wipe_bonus := 0) -> Dictionary:
	var out := {"found": false, "wiped": false}
	var wipe_radius := 0.8 + float(wipe_bonus)
	var wiped: Array = []
	for t in tracks:
		if Vector2(t).distance_to(Vector2(hero_tile)) <= wipe_radius:
			wiped.append(t)
	for t in wiped:
		tracks.erase(t)
		out["wiped"] = true
	var radius := float(cfg.get("nests", {}).get("spot_radius", 2)) + float(spot_bonus)
	for t in tracks:
		if Vector2(t).distance_to(Vector2(hero_tile)) > radius:
			continue
		var camp: Dictionary = map.poi_by_id(int(tracks[t]["camp"]))
		if camp.is_empty() or bool(camp.get("discovered", false)):
			continue
		# шаг к гнезду — против направления следа
		map.reveal_around(t - Vector2i(tracks[t]["dir"]), 1)
		out["found"] = true
		break
	return out


# --- осады поселений -------------------------------------------------------

func _settlements() -> Array:
	var out: Array = []
	for poi in map.pois:
		if String(poi["kind"]) == "settlement" and String(poi["state"]) == "ok":
			out.append(poi)
	return out


func _roll_sieges() -> Array:
	var out: Array = []
	var scfg: Dictionary = cfg.get("sim", {})
	if not sieges.is_empty():
		return out
	# скауты гнёзд (M12): чем выше уровни лагерей, тем чаще находят поселения
	var boost := 1.0
	var nboost := float(cfg.get("nests", {}).get("siege_boost_per_level", 0.15))
	for poi in map.pois:
		if String(poi["kind"]) == "camp" and int(poi["cleared_day"]) < 0:
			boost += nboost * float(int(poi.get("nest_level", 0)))
	if _rng.randf() > float(scfg.get("siege_chance_per_day", 0.06)) * boost:
		return out
	if bandits_peace():   # мир с бандитами (M14-H): договор о ненападении
		return out
	var camps: Array = []
	for poi in map.pois:
		if String(poi["kind"]) == "camp" and int(poi["cleared_day"]) < 0:
			camps.append(poi)
	var settlements := _settlements()
	if camps.is_empty() or settlements.is_empty():
		return out
	var camp: Dictionary = camps[_rng.randi_range(0, camps.size() - 1)]
	# большой рейд (M12): гнездо верхнего уровня присылает усиленный отряд
	var big := int(camp.get("nest_level", 0)) >= int(cfg.get("nests", {}).get("big_raid_level", 3))
	# бандиты идут в ближнее поселение из нескольких случайных кандидатов
	var target: Dictionary = {}
	var best_d := float(scfg.get("siege_range", 26))
	for i in 4:
		var s: Dictionary = settlements[_rng.randi_range(0, settlements.size() - 1)]
		var d: float = Vector2(s["tile"]).distance_to(Vector2(camp["tile"]))
		if d <= best_d:
			best_d = d
			target = s
	if target.is_empty():
		return out
	sieges.append({"settlement_id": int(target["id"]), "camp_id": int(camp["id"]),
			"left": int(scfg.get("siege_days", 3)), "big": big})
	out.append({"type": "siege_start", "a": _poi_name(camp), "b": _poi_name(target)})
	_chron("chron.world_siege", _poi_name(target))
	return out


func _update_sieges() -> Array:
	var out: Array = []
	var scfg: Dictionary = cfg.get("sim", {})
	var still: Array = []
	for siege: Dictionary in sieges:
		siege["left"] = int(siege["left"]) - 1
		var target: Dictionary = map.poi_by_id(int(siege["settlement_id"]))
		var camp: Dictionary = map.poi_by_id(int(siege["camp_id"]))
		if target.is_empty() or camp.is_empty():
			continue
		if int(siege["left"]) > 0:
			still.append(siege)
			continue
		# осада решила исход: сила лагеря против обороны поселения;
		# большой рейд гнезда (M12) сильнее на полторы
		var power := float(camp["strength"]) * (1.5 if bool(siege.get("big", false)) else 1.0)
		var defense := float(scfg.get("settlement_defense", 12.0)) * _rng.randf_range(0.7, 1.3)
		if power > defense:
			target["state"] = "fallen"
			target["faction"] = "bandits"
			target["fell_day"] = day
			camp["strength"] = float(camp["strength"]) * 0.5
			out.append({"type": "siege_fell", "a": _poi_name(target)})
			_chron("chron.world_fell", _poi_name(target))
		else:
			camp["strength"] = maxf(1.0, float(camp["strength"]) * 0.5)
			out.append({"type": "siege_repelled", "a": _poi_name(target)})
			_chron("chron.world_repelled", _poi_name(target))
	sieges = still
	return out


# --- переселение павших поселений (ответ №4) ------------------------------

func _roll_resettlement() -> Array:
	var out: Array = []
	var scfg: Dictionary = cfg.get("sim", {})
	for poi in map.pois:
		if String(poi["kind"]) != "settlement" or String(poi["state"]) != "fallen":
			continue
		var ago := day - int(poi.get("fell_day", day))
		if ago < int(scfg.get("resettle_min_days", 5)):
			continue
		if _rng.randf() > float(scfg.get("resettle_chance", 0.35)):
			continue
		poi["state"] = "ok"
		poi["faction"] = "traders" if _rng.randf() < 0.6 else "cult"
		poi["strength"] = float(cfg.get("sim", {}).get("start_strength", {}).get("settlement", 8.0))
		poi["cleared_day"] = -1
		out.append({"type": "resettle", "a": _poi_name(poi), "b": String(poi["faction"])})
		_chron("chron.world_resettle", _poi_name(poi), String(poi["faction"]))
	return out


# --- данжи сгущаются заново ------------------------------------------------

func _roll_dungeon_resets() -> Array:
	var out: Array = []
	var reset_days := int(cfg.get("sim", {}).get("dungeon_reset_days", 10))
	for poi in map.pois:
		var kind := String(poi["kind"])
		if kind != "dungeon" and kind != "ruins" and kind != "camp" and kind != "dragon_castle" \
				and kind != "vampire_keep" and kind != "lich_tower":
			continue
		var cleared := int(poi["cleared_day"])
		if cleared >= 0 and day - cleared >= reset_days:
			poi["cleared_day"] = -1
			var key := kind if kind in ["camp", "ruins", "dragon_castle", "vampire_keep", "lich_tower"] else "dungeon"
			poi["strength"] = float(cfg.get("sim", {}).get("start_strength", {}).get(key, 5.0))
			out.append({"type": "poi_reborn", "a": _poi_name(poi), "b": kind})
	return out


# --- караван перебирается ---------------------------------------------------

func _roll_caravan() -> Array:
	var out: Array = []
	if day == 0 or day % int(cfg.get("sim", {}).get("caravan_move_days", 4)) != 0:
		return out
	for poi in map.pois:
		if String(poi["kind"]) != "caravan":
			continue
		var spot: Vector2i = map._walkable_random()
		if spot != poi["tile"]:
			poi["tile"] = spot
			out.append({"type": "caravan_moved", "a": _poi_name(poi)})
	return out


## Имя точки интереса: id вида (город/данж/руины...) — сцена переводит через Loc.
func _poi_name(poi: Dictionary) -> String:
	return String(poi["kind"])


## Мировая летопись: сцена переносит в общую летопись города (единый журнал M4).
func _chron(key: String, a := "", b := "") -> void:
	chronicle.append({"day": day, "key": key, "a": a, "b": b})
	if chronicle.size() > 200:
		chronicle.pop_front()


# --- легендарные странники (v1.22) ------------------------------------------
# Уникальные NPC-герои живут своей жизнью: ходят к дальним данжам и зачищают
# их раньше игрока (гонка за лут: не успел — досталось страннику), иногда
# гостят в городе. Герой встречает странника на карте (E) и может позвать
# его в город или спросить о дальних землях.

func _legends_cfg() -> Dictionary:
	return cfg.get("legends", {})


## Заселить странников: подальше от города, каждый начинает с отдыха.
func _spawn_legends() -> void:
	legends = []
	_legend_id = 1
	var lcfg := _legends_cfg()
	if lcfg.is_empty():
		return
	for def in lcfg.get("defs", []):
		var tile: Vector2i = map._walkable_random()
		for attempt in 30:
			tile = map._walkable_random()
			if Vector2(tile).distance_to(Vector2(map.city_tile)) >= 12.0:
				break
		legends.append({"id": _legend_id, "def": def, "tile": tile,
				"path": [], "state": "rest",
				"target_poi": -1, "days_left": _rng.randi_range(1, 2),
				"rumor_used": false})
		_legend_id += 1


## Дальние цели странников: незачищенные боевые точки вне «двора» города
## (ближний данж остаётся игроку — гонка идёт за дальними).
func _legend_targets() -> Array:
	var keepout := float(_legends_cfg().get("city_keepout", 6))
	var out: Array = []
	for poi in map.pois:
		if not is_combat_poi(poi) or int(poi["cleared_day"]) >= 0:
			continue
		if String(poi["kind"]) == "settlement":
			continue
		if Vector2(poi["tile"]).distance_to(Vector2(map.city_tile)) <= keepout:
			continue
		out.append(poi)
	return out


## Выбор цели: иногда город в гости, иначе дальний данж.
func _pick_legend_target(l: Dictionary) -> void:
	var lcfg := _legends_cfg()
	var dest: Vector2i
	if _rng.randf() < float(lcfg.get("visit_chance", 0.25)) or _legend_targets().is_empty():
		l["target_poi"] = -2   # город
		dest = map.city_tile
	else:
		var targets := _legend_targets()
		var poi: Dictionary = targets[_rng.randi_range(0, targets.size() - 1)]
		l["target_poi"] = int(poi["id"])
		dest = poi["tile"]
	l["path"] = map.tile_path(l["tile"], dest)
	l["state"] = "travel"


## День странника: отдых → путь → зачистка/гости → снова в путь.
func _tick_legends() -> Array:
	var out: Array = []
	var lcfg := _legends_cfg()
	var step_n := maxi(1, int(lcfg.get("move_tiles_per_day", 2)))
	for l in legends:
		match String(l["state"]):
			"rest":
				l["days_left"] = int(l["days_left"]) - 1
				if int(l["days_left"]) <= 0:
					_pick_legend_target(l)
			"travel":
				var path: Array = l["path"]
				for i in step_n:
					if path.size() > 1:
						path.pop_at(0)
				l["tile"] = path[0] if not path.is_empty() else l["tile"]
				l["path"] = path
				if path.size() <= 1:
					if int(l["target_poi"]) == -2:
						l["state"] = "visit"
						l["days_left"] = int(lcfg.get("visit_days", 3))
						l["tile"] = map.city_tile + Vector2i(1, 0)
						out.append({"type": "legend_visit", "legend": String(l["def"]["loc"])})
						_chron("chron.legend_visit", String(l["def"]["loc"]))
					else:
						var poi: Dictionary = map.poi_by_id(int(l["target_poi"]))
						if poi.is_empty() or int(poi["cleared_day"]) >= 0:
							# данж уже кто-то взял — странник передумал
							l["state"] = "rest"
							l["days_left"] = 1
						else:
							l["state"] = "clear"
							var days: Array = lcfg.get("clear_days", [2, 3])
							l["days_left"] = _rng.randi_range(int(days[0]), int(days[1]))
			"clear":
				l["days_left"] = int(l["days_left"]) - 1
				if int(l["days_left"]) <= 0:
					var poi2: Dictionary = map.poi_by_id(int(l["target_poi"]))
					if not poi2.is_empty() and int(poi2["cleared_day"]) < 0:
						poi2["cleared_day"] = day
						var kind := String(poi2["kind"])
						var key := kind if kind in ["camp", "ruins", "dragon_castle", "vampire_keep", "lich_tower"] else "dungeon"
						poi2["strength"] = float(cfg.get("sim", {}).get("start_strength", {}).get(key, 5.0))
						out.append({"type": "legend_cleared", "legend": String(l["def"]["loc"]),
								"poi": kind})
						_chron("chron.legend_cleared", String(l["def"]["loc"]), kind)
					l["state"] = "rest"
					var rd: Array = lcfg.get("rest_days", [2, 4])
					l["days_left"] = _rng.randi_range(int(rd[0]), int(rd[1]))
			"visit":
				l["days_left"] = int(l["days_left"]) - 1
				if int(l["days_left"]) <= 0:
					l["state"] = "rest"
					l["days_left"] = _rng.randi_range(1, 2)
					l["rumor_used"] = false
					out.append({"type": "legend_left", "legend": String(l["def"]["loc"])})
	return out


## Странник у ног героя ({} — нет): живой и не ушедший в город.
func legend_near(hero_tile: Vector2i) -> Dictionary:
	for l in legends:
		if String(l["state"]) == "gone":
			continue
		if Vector2(l["tile"]).distance_to(Vector2(hero_tile)) <= 1.5:
			return l
	return {}


## Позвать странника в город (сцена уже проверила место в городе).
## Возвращает определение странника (def) или {}.
func legend_invite(legend_id: int) -> Dictionary:
	for l in legends:
		if int(l["id"]) == legend_id:
			l["state"] = "gone"
			_chron("chron.legend_joined", String(l["def"]["loc"]))
			return l["def"]
	return {}


## Спросить о дальних землях: открывает кусок карты (раз за визит).
## Возвращает число открытых точек (0 — уже рассказывал).
func legend_rumor(legend_id: int) -> int:
	for l in legends:
		if int(l["id"]) == legend_id:
			if bool(l["rumor_used"]) or String(l["state"]) == "gone":
				return 0
			l["rumor_used"] = true
			return map.reveal_far(2).size()
	return 0


# --- случайные встречи в пути (v1.22) ---------------------------------------
# Путь больше не безопасен: на каждый день дороги бросок кубика. Бой (засада)
# открывает сцену данжа, остальные встречи — выбор с эффектами.

## Бросок дня пути: id встречи из конфига или "" (не случилось).
func roll_encounter() -> String:
	var ecfg: Dictionary = cfg.get("encounters", {})
	if ecfg.is_empty() or _rng.randf() > float(ecfg.get("chance_per_day", 0.25)):
		return ""
	var kinds: Dictionary = ecfg.get("kinds", {})
	var total := 0
	for k in kinds:
		total += int(kinds[k].get("w", 1))
	if total <= 0:
		return ""
	var roll := _rng.randi_range(1, total)
	for k in kinds:
		roll -= int(kinds[k].get("w", 1))
		if roll <= 0:
			return String(k)
	return ""


## Раненый путник: помочь едой из пула города (+репутация торговцев).
func encounter_help_wounded(pool: Dictionary) -> bool:
	var k: Dictionary = cfg.get("encounters", {}).get("kinds", {}).get("wounded", {})
	var cost := float(k.get("food_cost", 5))
	if float(pool.get("food", 0.0)) < cost:
		return false
	pool["food"] = float(pool["food"]) - cost
	add_rep("traders", float(k.get("rep", 8)))
	return true


## Схрон контрабандистов: монеты в кошель героя.
func encounter_cache_coins() -> int:
	var k: Dictionary = cfg.get("encounters", {}).get("kinds", {}).get("cache", {})
	var range: Array = k.get("coins", [5, 15])
	return _rng.randi_range(int(range[0]), int(range[1]))


## Пепельная буря «напролом»: караван теряет долю еды.
func encounter_storm_loss(pool: Dictionary) -> float:
	var frac := float(cfg.get("encounters", {}).get("kinds", {}).get("storm", {}).get("food_frac", 0.1))
	var loss: float = float(pool.get("food", 0.0)) * frac
	pool["food"] = float(pool.get("food", 0.0)) - loss
	return loss


## Паломник культа: пожертвование монет за репутацию культа.
func encounter_pilgrim_donate(coins: int) -> int:
	var k: Dictionary = cfg.get("encounters", {}).get("kinds", {}).get("pilgrim", {})
	var cost := int(k.get("coins_cost", 5))
	if coins < cost:
		return coins
	add_rep("cult", float(k.get("rep", 10)))
	return coins - cost


## Засада: монеты за зачистку и масштаб лагеря (сцена данжа).
func encounter_ambush_coins() -> int:
	var k: Dictionary = cfg.get("encounters", {}).get("kinds", {}).get("ambush", {})
	var range: Array = k.get("coins", [4, 10])
	return _rng.randi_range(int(range[0]), int(range[1]))


func encounter_ambush_scale() -> float:
	return float(cfg.get("encounters", {}).get("kinds", {}).get("ambush", {}).get("scale", 0.7))


# --- зачистка и осмотр локаций ---------------------------------------------

## Локация зачищена (вызов из данжа). Возвращает события для тостов:
## руины и обелиски открывают далёкие места (ответ №24).
## M14-H: зачистка лагеря бандитов портит репутацию с ними, но радует торговцев.
func mark_cleared(poi_id: int) -> Array:
	var poi: Dictionary = map.poi_by_id(poi_id)
	if poi.is_empty():
		return []
	poi["cleared_day"] = day
	var out: Array = []
	match String(poi["kind"]):
		"ruins":
			var opened: Array = map.reveal_far(2)
			if not opened.is_empty():
				out.append({"type": "map_found", "a": str(opened.size())})
		"camp":
			poi["strength"] = 0.0
			var fcfg: Dictionary = _factions_cfg()
			add_rep("bandits", float(fcfg.get("camp_clear_bandits", -5)))
			add_rep("traders", float(fcfg.get("camp_clear_traders", 2)))
		"settlement":
			# освобождённое поселение пусто — позже переселится (ответ №4)
			poi["strength"] = 0.0
			poi["fell_day"] = day
	return out


## Обелиск: одноразовое открытие далёких земель (ответ №24).
func touch_obelisk(poi_id: int) -> Array:
	var poi: Dictionary = map.poi_by_id(poi_id)
	if poi.is_empty() or bool(poi["used"]):
		return []
	poi["used"] = true
	var opened: Array = map.reveal_far(2)
	if opened.is_empty():
		return []
	return [{"type": "obelisk_seen", "a": str(opened.size())}]


## Можно ли войти в локацию. Данж/руины/лагерь — пока не зачищены;
## поселение (в т.ч. павшее — там лагерь бандитов) и лагерь торговцев — всегда.
func poi_enterable(poi: Dictionary) -> bool:
	if poi.is_empty():
		return false
	match String(poi["kind"]):
		"dungeon", "ruins", "camp", "dragon_castle", "vampire_keep", "lich_tower":
			return int(poi["cleared_day"]) < 0
		"settlement", "trade_camp":
			return true
		_:
			return false


## Локация боевого типа (входим в сцену данжа)?
func is_combat_poi(poi: Dictionary) -> bool:
	return String(poi["kind"]) in ["dungeon", "ruins", "camp", "dragon_castle", "vampire_keep", "lich_tower"] \
			or (String(poi["kind"]) == "settlement" and String(poi["state"]) == "fallen")


## Торговая точка (открываем панель торговли)?
func is_trade_poi(poi: Dictionary) -> bool:
	return String(poi["kind"]) in ["caravan", "settlement"] and String(poi["state"]) == "ok"


## Скидка каравана: у лагеря торговцев (в т.ч. гуляй-города) цены лучше.
func trade_discount(poi: Dictionary) -> float:
	var tcfg: Dictionary = cfg.get("trade", {})
	if String(poi["kind"]) in ["caravan", "trade_camp"]:
		return float(tcfg.get("camp_discount", 0.7))
	return 1.0


# --- торговля (ответ №40): монеты + живой обмен ---------------------------
# Пул города передаётся явно — чистые функции легко проверить headless.
# Возврат: {"err": "", "coins": N} — err это ключ локализации без префикса.

## Купить count ресурса за монеты (в пул города, караван доставит).
func trade_buy(pool: Dictionary, coins: int, key: String, count: int, poi: Dictionary, cap := 999999) -> Dictionary:
	var price := buy_price(key, poi)
	var cost := int(ceilf(price * count))
	if cost > coins:
		return {"err": "no_coins", "coins": coins}
	var free := float(cap) - float(pool.get(key, 0.0))
	var add := minf(float(count), maxf(0.0, free))
	if add <= 0.0:
		return {"err": "storage_full", "coins": coins}
	pool[key] = float(pool.get(key, 0.0)) + add
	add_rep("traders", float(_factions_cfg().get("trade_rep_per_deal", 1)))   # дипломатия (M14-H)
	return {"err": "", "coins": coins - int(ceilf(price * add))}


## Продать count ресурса из пула за монеты.
func trade_sell(pool: Dictionary, coins: int, key: String, count: int, poi: Dictionary) -> Dictionary:
	var have := float(pool.get(key, 0.0))
	var take := minf(float(count), have)
	if take <= 0.0:
		return {"err": "no_res", "coins": coins}
	var price := sell_price(key, poi)
	pool[key] = have - take
	add_rep("traders", float(_factions_cfg().get("trade_rep_per_deal", 1)))   # дипломатия (M14-H)
	return {"err": "", "coins": coins + int(floorf(price * take))}


## Живой обмен: ресурс на ресурс по таблице barter.
func trade_barter(pool: Dictionary, deal: Dictionary) -> Dictionary:
	var give := String(deal["give"])
	var get := String(deal["get"])
	var give_n := float(deal["give_n"])
	var get_n := float(deal["get_n"])
	if float(pool.get(give, 0.0)) < give_n:
		return {"err": "no_res"}
	pool[give] = float(pool[give]) - give_n
	pool[get] = float(pool.get(get, 0.0)) + get_n
	return {"err": ""}


## Цена покупки за единицу (скидка каравана — торговцы щедрее; репутация
## торговцев (M14-H) делает цены ещё лучше).
func buy_price(key: String, poi: Dictionary) -> float:
	var base := float(cfg.get("trade", {}).get("buy", {}).get(key, 3))
	var price := maxf(1.0, base * trade_discount(poi))
	var fcfg: Dictionary = _factions_cfg()
	var mult := 1.0 - get_rep("traders") * float(fcfg.get("discount_per_rep", 0.0015))
	mult = maxf(mult, float(fcfg.get("discount_min_mult", 0.75)))
	return maxf(1.0, price * mult)


## Цена продажи за единицу (доля от покупки).
func sell_price(key: String, poi: Dictionary) -> float:
	return buy_price(key, poi) * float(cfg.get("trade", {}).get("sell_mult", 0.5))


## Культ продаёт руну за монеты (в рюкзак героя). rune_id — "" если руны кончились.
func trade_rune(inventory: Array, coins: int, rune_id: String) -> Dictionary:
	if rune_id == "":
		return {"err": "no_runes", "coins": coins}
	var price := int(cfg.get("trade", {}).get("rune_price", 25))
	if coins < price:
		return {"err": "no_coins", "coins": coins}
	inventory.append({"id": rune_id, "count": 1})
	return {"err": "", "coins": coins - price}


## Награда монетами за зачистку лагеря/руин (диапазоны из конфига).
## Добытчики гнезда (M12) накопили добычу — лагерь жирнее.
## M14-C (T17): награды растут с уровнем точки — гнездо уровня L даёт
## монеты × (1 + coin_mult_per_nest_level × L) из balance.json -> rewards.
func coin_reward(poi: Dictionary) -> int:
	var tcfg: Dictionary = cfg.get("trade", {})
	var rewards := _balance_rewards()
	match String(poi["kind"]):
		"camp", "settlement":
			var loot := int(float(poi.get("plunder", 0.0)) * float(cfg.get("nests", {}).get("coin_per_plunder", 1.0)))
			var base := _rng.randi_range(int(tcfg.get("camp_coins_min", 8)), int(tcfg.get("camp_coins_max", 16))) + loot
			var level := float(int(poi.get("nest_level", 0)))
			if String(poi["kind"]) == "settlement":
				level = 0.0   # у поселений своего уровня роста нет
			return int(round(float(base) * (1.0 + float(rewards.get("coin_mult_per_nest_level", 0.25)) * level)))
		"ruins":
			return _rng.randi_range(int(tcfg.get("ruins_coins_min", 3)), int(tcfg.get("ruins_coins_max", 8)))
		"dragon_castle":
			# сокровищница дракона (M13)
			return _rng.randi_range(int(tcfg.get("dragon_coins_min", 30)), int(tcfg.get("dragon_coins_max", 60)))
		"vampire_keep":
			# гробница-замок (M14-D): 20–40 монет по issue
			return _rng.randi_range(int(tcfg.get("vampire_coins_min", 20)), int(tcfg.get("vampire_coins_max", 40)))
		"lich_tower":
			# рунная башня (M14-D): скромнее монетами, руна босса гарантирована
			return _rng.randi_range(int(tcfg.get("lich_coins_min", 12)), int(tcfg.get("lich_coins_max", 25)))
	return 0


## Секция rewards из balance.json (читается один раз за вызов — вызовов мало).
func _balance_rewards() -> Dictionary:
	var parsed: Variant = _read_json_file("res://data/balance.json")
	if parsed is Dictionary:
		return parsed.get("rewards", {})
	return {}


## Масштаб локации (M12): строители укрепляют гнездо — враги в лагере сильнее.
func location_scale(poi: Dictionary) -> float:
	if String(poi["kind"]) not in ["camp", "settlement"]:
		return 1.0
	return 0.5 + float(cfg.get("nests", {}).get("fortify_scale_per_level", 0.1)) * float(int(poi.get("nest_level", 0)))


## Случайная руна, которую готов продать культ (из лута — чистая логика без
## автозагрузок, headless-тесты). rune_id — из item.rune_* loot.json.
func cult_rune_offer() -> String:
	var runes: Array = []
	for item in _read_json_file("res://data/loot.json").get("items", []):
		if String(item["id"]).begins_with("rune_"):
			runes.append(String(item["id"]))
	if runes.is_empty():
		return ""
	return String(runes[_rng.randi_range(0, runes.size() - 1)])


func _read_json_file(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())
