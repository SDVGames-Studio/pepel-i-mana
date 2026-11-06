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
## уничтожаются при падении (destroy). Городов не больше max_cities
## (правки приёмки v1.41.1: страховка от разрастания, по умолчанию 20).
## limit > 0 (v1.54): создать не больше limit БЛИЖАЙШИХ к городу игрока —
## старт игры больше не генерит все 20 городов одним куском; полный набор
## достраивается при входе на карту мира (world.gd) и в сейве.
func ensure(mature_days := 0, limit := 0) -> void:
	if world_map == null:
		return
	var cap := maxi(0, int(ncfg().get("mature_cap_days", 25)))
	var max_cities := maxi(1, int(ncfg().get("max_cities", 20)))
	var todo: Array = []
	for poi in world_map.pois:
		if String(poi["kind"]) != "settlement" or String(poi["state"]) != "ok":
			continue
		if cities.has(int(poi["id"])):
			continue
		todo.append(poi)
	if limit > 0 and todo.size() > limit:
		var ct: Vector2i = world_map.city_tile
		todo.sort_custom(func(a, b) -> bool:
			return Vector2(a["tile"]).distance_squared_to(Vector2(ct)) 					< Vector2(b["tile"]).distance_squared_to(Vector2(ct)))
		todo.resize(limit)
	for poi in todo:
		if cities.size() >= max_cities:
			break
		_create(poi, mini(maxi(0, mature_days), cap))


## Сид города поселения: детерминирован по сиду мира и id точки — старые
## сейвы (до городов НПС) получают те же карты при пересоздании.
func _city_seed(poi_id: int) -> int:
	return hash("%d:%d" % [int(world_map.gen_seed), poi_id])


func _create(poi: Dictionary, mature_days: int) -> void:
	var poi_id := int(poi["id"])
	var seed_value := _city_seed(poi_id)
	var cmap = load(CITY_MAP_SCRIPT).new()
	# гидро-контекст клетки поселения (№117): река на глобали = река в городе.
	# v1.43: у поселений СВОЙ размер карты (по умолчанию 96×72) — генерация
	# и A* ×10-20 городов неподъёмны на городской ×4; растут они как игрок
	var npc_cfg: Dictionary = city_cfg.duplicate(true)
	if ncfg().has("map_w"):
		npc_cfg["map_w"] = int(ncfg()["map_w"])
		npc_cfg["map_h"] = int(ncfg().get("map_h", npc_cfg["map_w"]))
	cmap.generate(seed_value, npc_cfg, world_map.tile_hydro(poi["tile"]))
	var sim = load(CITY_SIM_SCRIPT).new()
	sim.setup(cmap, npc_cfg, int(ncfg().get("start_residents", 8)),
			String(ncfg().get("start_level", "normal")))
	sim.autonomous = true   # живут сами, без старосты (№120)
	# стартовый посёлок (правки приёмки v1.41.1): избы и фермы уже стоят —
	# поселение с первого дня выглядит деревней, а не площадью в чистом поле
	if bool(ncfg().get("hamlet", true)):
		_build_hamlet(sim, int(ncfg().get("start_residents", 8)))
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


## Стартовый посёлок (правки приёмки v1.41.1): «один дом на кучу горожан» —
## город рос с ферма-кризисами, а дома в плане далеко. Поселение строится
## УЖЕ обжитым: избы под первых жителей (по pop_per_house), пара ферм и
## лесопилка — готовые, расставлены самостроем по районам. Ресурсы города
## не тратятся (пул на время стройки накачиваем и возвращаем как был) —
## это прошлое поселенцев, а не подарок экономике.
func _build_hamlet(sim, residents_n: int) -> void:
	var per_house := maxi(1, int(sim.cfg.get("pop_per_house", 1)))
	var plan: Array = []
	for i in ceili(float(residents_n) / float(per_house)):
		plan.append("house")
	for i in clampi(ceili(float(residents_n) / 5.0), 1, 3):
		plan.append("farm")
	if bool(ncfg().get("hamlet_sawmill", true)):
		plan.append("sawmill")
	var pool_backup: Dictionary = (sim.res as Dictionary).duplicate()
	for key in pool_backup:
		sim.res[key] = 999999.0
	for type_id in plan:
		var tile: Vector2i = sim._find_autobuild_tile(String(type_id))
		if tile == Vector2i(-1, -1):
			continue
		if not sim.place_building(String(type_id), tile):
			continue
		var b: Dictionary = sim.building_at(tile)
		if b.is_empty():
			continue
		b["progress"] = float(sim._def(b)["build_work"])
		b["done"] = true
		sim._set_bld_solid(b, true)
	for key in pool_backup:
		sim.res[key] = float(pool_backup[key])
	sim.events.clear()   # тосты стройки прошлого никто не показывает


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


## Тик всех городов. Город в гостях (skip_id) тикает КАЖДЫЙ кадр — герой
## внутри, жизнь плавная. Фоновые города — ПАКЕТОМ раз в tick_period:
## за кадр копим реальное время и проживаем разом (замер правок v1.41.1:
## 3 города каждый кадр — 9.5 мс/кадр, пакетом — в десятки раз дешевле;
## большие шаги времени безопасны: advance_days пути гоняет по 30 сек).
## Скорость/пауза — как у города игрока («те же правила»).
var _bg_accum := 0.0
var _bg_order: Array = []      # v1.48.1: round-robin городов (один за вызов)
var _bg_i := 0


func tick(dt: float, skip_id := -1, ref_speed := 1) -> void:
	var period := maxf(0.05, float(ncfg().get("tick_period", 0.5)))
	for poi_id in cities:
		var sim = cities[poi_id]["sim"]
		if int(poi_id) == skip_id:
			sim.tick(dt)
			continue
		if not sim.paused and int(sim.speed) != ref_speed:
			sim.speed = ref_speed
	# v1.48.1 (фидбек «2 FPS на старте»): пакет прогонял ВСЕ города сразу
	# по накопленному времени (10 городов × 0.5 с сима = ~4 с фриза каждые
	# полсекунды). Теперь ROUND-ROBIN: один город за вызов, шаг не больше
	# period; догоняя по кругу, поселения живут равномерно и без фризов.
	_bg_accum += dt
	if _bg_accum < period:
		return
	var step := minf(_bg_accum, period)
	_bg_accum = 0.0
	if _bg_order.is_empty() or _bg_order.size() != cities.size():
		_bg_order = cities.keys()
		_bg_i = 0
	if _bg_order.is_empty():
		return
	# один город за вызов
	var attempts := _bg_order.size()
	while attempts > 0:
		var pid = _bg_order[_bg_i % _bg_order.size()]
		_bg_i += 1
		attempts -= 1
		if int(pid) == skip_id or not cities.has(pid):
			continue
		var sim2 = cities[pid]["sim"]
		if sim2.paused:
			continue
		sim2.tick(step)
		sim2.events.clear()   # тосты чужого города никто не показывает; летопись помнит всё
		break
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
	# v1.43 (большие карты): поселение хранит СИД, а не по-тайловую карту —
	# карта регенерируется детерминированно при загрузке (иначе сейв
	# раздувался на ×4 площадь × число городов). Правки карты поселения
	# (выработка/пни) не сохраняются — это фон, деревья отрастают.
	var sg: Script = load(SAVE_SCRIPT)
	var out := {}
	for poi_id in cities:
		var e: Dictionary = cities[poi_id]
		out[str(poi_id)] = {
			"faction": String(e["faction"]),
			"seed": int(e["seed"]),
			"coins": int(e["coins"]),
			"city": sg._city_block(e["sim"], false),
		}
	return out


## Восстановление из блока сейва (после setup): города пересобирает
## save_game._build_city. Пустой блок — просто пусто. v1.43: худому блоку
## нужен сид + гидро клетки (тайл ищется в pois по id).
func load_block(block: Dictionary) -> void:
	cities = {}
	if world_map == null:
		return
	var sg: Script = load(SAVE_SCRIPT)
	for poi_id in block:
		var d: Dictionary = block[poi_id]
		var poi_tile := Vector2i(-1, -1)
		for poi in world_map.pois:
			if int(poi.get("id", -1)) == int(poi_id):
				poi_tile = Vector2i(poi["tile"])
				break
		var hydro: Dictionary = {}
		if poi_tile.x >= 0:
			hydro = world_map.tile_hydro(poi_tile)
		var sim = sg._build_city(d.get("city", {}), int(d.get("seed", 0)), hydro)
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
