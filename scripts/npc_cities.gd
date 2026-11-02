extends RefCounted
## Города НПС — программа «Мир v2», этап 3 (ответ №120): поселения фракций
## на глобальной карте — полноценные города. У каждого своя карта (гидро-
## контекст его клетки мира) и свой city_sim: автономия без старосты,
## самострой по плану, беженцы, свои волны мутантов — «живут сами и растут
## так же, как поселение игрока». Герой заходит внутрь как в свой город.
##
## Чистая логика (RefCounted, без автозагрузок) — headless-тесты.
## Живёт в Game рядом с city_sim; сейв — через save_game._city_block.

const CITY_MAP_SCRIPT := "res://scripts/city_map.gd"
const CITY_SIM_SCRIPT := "res://scripts/city_sim.gd"
const SAVE_SCRIPT := "res://scripts/save_game.gd"

var cities := {}            # poi_id -> {poi_id, faction, seed, coins, sim, pop}
var world_map = null        # world_map.gd
var world_cfg: Dictionary = {}
var city_cfg: Dictionary = {}


func setup(wmap, wcfg: Dictionary, ccfg: Dictionary) -> void:
	world_map = wmap
	world_cfg = wcfg
	city_cfg = ccfg
	cities = {}


## Тюнинг городов НПС — world.json -> npc_city.
func ncfg() -> Dictionary:
	return world_cfg.get("npc_city", {})


## Поселения без города получают его (идемпотентно). mature_days — сколько
## дней жизни «догнать» новому городу (миграция старых сейвов: миру N дней —
## поселенцы не новорожденные). Павших поселений здесь нет: их города
## уничтожаются при падении (destroy).
func ensure(mature_days := 0) -> void:
	if world_map == null:
		return
	var cap := maxi(0, int(ncfg().get("mature_cap_days", 25)))
	for poi in world_map.pois:
		if String(poi["kind"]) != "settlement" or String(poi["state"]) != "ok":
			continue
		if cities.has(int(poi["id"])):
			continue
		_create(poi, mini(maxi(0, mature_days), cap))


## Сид города поселения: детерминирован по сиду мира и id точки — старые
## сейвы (до городов НПС) получают те же карты при пересоздании.
func _city_seed(poi_id: int) -> int:
	return hash("%d:%d" % [int(world_map.gen_seed), poi_id])


func _create(poi: Dictionary, mature_days: int) -> void:
	var poi_id := int(poi["id"])
	var seed_value := _city_seed(poi_id)
	var cmap = load(CITY_MAP_SCRIPT).new()
	# гидро-контекст клетки поселения (№117): река на глобали = река в городе
	cmap.generate(seed_value, city_cfg, world_map.tile_hydro(poi["tile"]))
	var sim = load(CITY_SIM_SCRIPT).new()
	sim.setup(cmap, city_cfg, int(ncfg().get("start_residents", 8)),
			String(ncfg().get("start_level", "normal")))
	sim.autonomous = true   # живут сами, без старосты (№120)
	var entry := {
		"poi_id": poi_id,
		"faction": String(poi["faction"]),
		"seed": seed_value,
		"coins": int(ncfg().get("start_coins", 30)),
		"sim": sim,
		"pop": sim.residents.size(),
	}
	attach_wallet(entry)
	cities[poi_id] = entry
	if mature_days > 0:
		sim.advance_days(mature_days)
	_sync_pop(entry)


## Свой кошелёк: рынок и караваны чужого города не лезут в монеты героя.
func attach_wallet(entry: Dictionary) -> void:
	var sim = entry["sim"]
	sim.coins_sink = func(n: int) -> void: entry["coins"] = int(entry["coins"]) + n
	sim.coins_source = func() -> int: return int(entry["coins"])


## Город поселения (city_sim) или null.
func city_of(poi_id: int):
	var e: Dictionary = cities.get(poi_id, {})
	return e.get("sim", null) if not e.is_empty() else null


## Запись поселения (кошелёк/фракция/сим) или {}.
func entry_of(poi_id: int) -> Dictionary:
	return cities.get(poi_id, {})


## Город пал (осада мира): жителей нет, город с карты уходит в «лагерь
## бандитов» — экземпляр city_sim удаляем целиком.
func destroy(poi_id: int) -> void:
	cities.erase(poi_id)
	if world_map != null:
		var poi: Dictionary = world_map.poi_by_id(poi_id)
		if not poi.is_empty():
			poi.erase("npc_pop")


## Тик всех городов: пауза — у каждого своя (tick сам проверяет), скорость —
## как у города игрока («те же правила»: игрок ускорил время — мир ускорился).
## skip_id — город, где сейчас герой: его скорость задаёт сцена, его события
## читает сцена города (не дренируем), но живёт он так же, как остальные.
func tick(dt: float, skip_id := -1, ref_speed := 1) -> void:
	for poi_id in cities:
		var sim = cities[poi_id]["sim"]
		if int(poi_id) == skip_id:
			sim.tick(dt)   # гостевой город: тикает с паузой/скоростью сцены
			continue
		if not sim.paused and int(sim.speed) != ref_speed:
			sim.speed = ref_speed
		sim.tick(dt)
		sim.events.clear()   # тосты чужого города никто не показывает; летопись помнит всё
	_sync_populations()


func set_paused(on: bool, skip_id := -1) -> void:
	for poi_id in cities:
		if int(poi_id) == skip_id:
			continue
		cities[poi_id]["sim"].paused = on


## Дни пути по миру: каждый город НПС проживает их как город игрока.
func advance_days(n: int) -> void:
	for poi_id in cities:
		cities[poi_id]["sim"].advance_days(n)
	_sync_populations()


## Число жителей — в POI (панель и маркер карты).
func _sync_populations() -> void:
	for poi_id in cities:
		_sync_pop(cities[poi_id])


func _sync_pop(entry: Dictionary) -> void:
	entry["pop"] = entry["sim"].residents.size()
	if world_map != null:
		var poi: Dictionary = world_map.poi_by_id(int(entry["poi_id"]))
		if not poi.is_empty() and String(poi["state"]) == "ok":
			poi["npc_pop"] = int(entry["pop"])


## Оборона поселения для осад мира: база из world.json + жители, стены и
## вышки реального города (город рос — осадам отпор). 0.0 — города нет.
func defense_of(poi_id: int) -> float:
	var sim = city_of(poi_id)
	if sim == null:
		return 0.0
	var d := float(world_cfg.get("sim", {}).get("settlement_defense", 12.0))
	d += float(sim.residents.size()) * float(ncfg().get("defense_per_resident", 0.5))
	for b in sim.buildings:
		if not bool(b.get("done", false)):
			continue
		match String(b["type"]):
			"wall":
				d += float(ncfg().get("defense_per_wall", 0.35))
			"tower":
				d += float(ncfg().get("defense_per_tower", 1.0))
	return minf(d, float(ncfg().get("defense_cap", 40.0)))


# --- сейв --------------------------------------------------------------------

## Блок сейва: на каждый город — кошелёк/фракция/сид + город целиком
## (та же форма, что блок "city" игрока).
func save_block() -> Dictionary:
	var sg: Script = load(SAVE_SCRIPT)
	var out := {}
	for poi_id in cities:
		var e: Dictionary = cities[poi_id]
		out[str(poi_id)] = {
			"faction": String(e["faction"]),
			"seed": int(e["seed"]),
			"coins": int(e["coins"]),
			"city": sg._city_block(e["sim"]),
		}
	return out


## Восстановление из блока сейва (после setup): города пересобирает
## save_game._build_city. Пустой блок — просто пусто.
func load_block(block: Dictionary) -> void:
	cities = {}
	if world_map == null:
		return
	var sg: Script = load(SAVE_SCRIPT)
	for poi_id in block:
		var d: Dictionary = block[poi_id]
		var sim = sg._build_city(d.get("city", {}))
		if sim == null:
			continue   # битый город — поселение пересоздастся ensure()
		var entry := {
			"poi_id": int(poi_id),
			"faction": String(d.get("faction", "")),
			"seed": int(d.get("seed", 0)),
			"coins": int(d.get("coins", 0)),
			"sim": sim,
			"pop": sim.residents.size(),
		}
		attach_wallet(entry)
		cities[int(poi_id)] = entry
		_sync_pop(entry)
