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
var _rng := RandomNumberGenerator.new()


func setup(world_map, world_cfg: Dictionary, seed_value := -1) -> void:
	map = world_map
	cfg = world_cfg
	day = 0
	events = []
	chronicle = []
	sieges = []
	tracks = {}
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
		if int(poi.get("nest_level", 0)) < 1:
			continue
		if _rng.randf() > float(ncfg.get("track_chance", 0.3)):
			continue
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var dir: Vector2i = dirs[_rng.randi_range(0, 3)]
		var tile: Vector2i = poi["tile"]
		var length := _rng.randi_range(int(ncfg.get("track_len_min", 3)), int(ncfg.get("track_len_max", 6)))
		for i in length:
			tile += dir
			if not map.in_bounds(tile) or not map.is_walkable(tile):
				break
			if not tracks.has(tile):
				tracks[tile] = {"dir": dir, "camp": int(poi["id"]), "age": 0}


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


## Герой осматривается (M12): затирает след под ногами; рядом со следом
## неоткрытого гнезда — открывает следующий тайл цепочки (выслеживание).
func track_scout(hero_tile: Vector2i) -> Dictionary:
	var out := {"found": false, "wiped": false}
	if tracks.has(hero_tile):
		tracks.erase(hero_tile)
		out["wiped"] = true
	var radius := float(cfg.get("nests", {}).get("spot_radius", 2))
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
		if kind != "dungeon" and kind != "ruins" and kind != "camp":
			continue
		var cleared := int(poi["cleared_day"])
		if cleared >= 0 and day - cleared >= reset_days:
			poi["cleared_day"] = -1
			var key := "camp" if kind == "camp" else ("ruins" if kind == "ruins" else "dungeon")
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


# --- зачистка и осмотр локаций ---------------------------------------------

## Локация зачищена (вызов из данжа). Возвращает события для тостов:
## руины и обелиски открывают далёкие места (ответ №24).
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
		"dungeon", "ruins", "camp":
			return int(poi["cleared_day"]) < 0
		"settlement", "trade_camp":
			return true
		_:
			return false


## Локация боевого типа (входим в сцену данжа)?
func is_combat_poi(poi: Dictionary) -> bool:
	return String(poi["kind"]) in ["dungeon", "ruins", "camp"] \
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
	return {"err": "", "coins": coins - int(ceilf(price * add))}


## Продать count ресурса из пула за монеты.
func trade_sell(pool: Dictionary, coins: int, key: String, count: int, poi: Dictionary) -> Dictionary:
	var have := float(pool.get(key, 0.0))
	var take := minf(float(count), have)
	if take <= 0.0:
		return {"err": "no_res", "coins": coins}
	var price := sell_price(key, poi)
	pool[key] = have - take
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


## Цена покупки за единицу (скидка каравана — торговцы щедрее).
func buy_price(key: String, poi: Dictionary) -> float:
	var base := float(cfg.get("trade", {}).get("buy", {}).get(key, 3))
	return maxf(1.0, base * trade_discount(poi))


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
func coin_reward(poi: Dictionary) -> int:
	var tcfg: Dictionary = cfg.get("trade", {})
	match String(poi["kind"]):
		"camp", "settlement":
			var loot := int(float(poi.get("plunder", 0.0)) * float(cfg.get("nests", {}).get("coin_per_plunder", 1.0)))
			return _rng.randi_range(int(tcfg.get("camp_coins_min", 8)), int(tcfg.get("camp_coins_max", 16))) + loot
		"ruins":
			return _rng.randi_range(int(tcfg.get("ruins_coins_min", 3)), int(tcfg.get("ruins_coins_max", 8)))
	return 0


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
