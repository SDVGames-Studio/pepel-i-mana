# Общая база тестовых модулей (структура v1.20.2): счётчики, _check,
# хелперы (_make_sim/_build_now/...), фейки (FakeGame и пр.). Каждый модуль
# tests/test_*.gd extends этот файл; раннер — tests/run_all.gd.
extends RefCounted

# Дерево сцены подставляет раннер (нужно редким тестам для root.add_child)
var tree: SceneTree = null


## Автотесты этапов M0 + M1 + M2 + M3.
## Запуск headless: godot --headless --path . --script res://tests/run_all.gd
## В этом режиме автозагрузки не работают — всё проверяем через load()/FileAccess.

const REQUIRED_LOCALES := preload("res://tests/test_locales.gd").REQUIRED_LOCALES


## Список ведётся не вручную: папка scripts/ сканируется целиком (урок v1.11.0 —
## city_weather.gd с typo не попал в рукописный список и сломал HUD города).
func _collect_scripts(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir() and not f.begins_with("."):
			out.append_array(_collect_scripts(dir_path + "/" + f))
		elif f.ends_with(".gd") and not f.ends_with(".uid"):
			out.append(dir_path + "/" + f)
		f = dir.get_next()
	out.sort()
	return out

var _fails := 0
var _oks := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		_oks += 1
		print("  ok: " + what)
	else:
		_fails += 1
		print("  FAIL: " + what)


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _reachable_from(gen: Object) -> Dictionary:
	var seen := {gen.start_tile: true}
	var queue: Array = [gen.start_tile]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if not seen.has(n) and gen.is_floor(n):
				seen[n] = true
				queue.append(n)
	return seen


func _make_sim(level: String = "normal") -> Object:
	var cfg: Variant = _read_json("res://data/city.json")
	var city_map = load("res://scripts/city_map.gd").new()
	# v1.28: в тестах карта без реки — фиксированные координаты проверок
	var gen_cfg: Dictionary = (cfg as Dictionary).duplicate(true)
	gen_cfg["river"] = false
	# v1.36: старые модули проверяют фиксированную геометрию — карта без
	# плато; рельеф со уровнями тестирует свой модуль test_plateau.gd
	gen_cfg["plateaus"] = {}
	gen_cfg["map_w"] = 80   # геометрия под фиксированные координаты тестов
	gen_cfg["map_h"] = 60
	city_map.generate(7, gen_cfg)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(city_map, cfg, 6, level)
	# в игре дневные броски идут с первого дня; в тестах фиксируем день 1,
	# чтобы тики строек не вызывали случайно беженцев и событий
	sim._last_daily_day = 1
	# волны мутантов в обычных тестах выключены: мир M5 живёт по своим правилам,
	# проверяется отдельно в _test_threat (там волны зовутся вручную)
	sim._next_raid_at = 999999999.0
	return sim


func _resident_by_prof(sim: Object, prof: String) -> Dictionary:
	for r in sim.residents:
		if String(r["prof"]) == prof:
			return r
	return {}


## Телепорт жителя на тайл и сброс пути (чтобы не ждать ходьбы в тесте).
func _teleport(sim: Object, r: Dictionary, tile: Vector2i) -> void:
	var t := tile
	# этап 2, аспект 2: клетка занята ГОТОВЫМ зданием (сплошная) — выносим на
	# вход; стройплощадки и непроходимый рельеф (руда под шахтой) не трогаем
	if not sim.map.is_walkable(t):
		var b: Dictionary = sim.building_at(t)
		if not b.is_empty() and bool(b.get("done", false)):
			var spot: Vector2i = sim.bld_spot(b)
			if not spot == Vector2i(-1, -1):
				t = spot
	r["pos"] = sim.map.tile_center_px(t)
	r["target"] = Vector2i(-1, -1)
	r["path"] = PackedVector2Array()


func _find_free_tile(sim: Object, near: Vector2i, type_id: String = "") -> Vector2i:
	# добытчики ставятся только у своего ресурса — ищем честное место
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id and String(d.get("place", "")) != "":
			var kinds: Array = []
			var on_resource := false
			match String(type_id):
				"mine":
					kinds = [sim.map.TILE_ORE, sim.map.TILE_DEADROCK]
					on_resource = true
				"sawmill":
					kinds = [sim.map.TILE_TREE]
				"quarry":
					kinds = [sim.map.TILE_ROCK, sim.map.TILE_ORE]
			return sim._find_gather_tile(type_id, kinds, on_resource, true)
	for radius in range(1, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := near + Vector2i(dx, dy)
				# этап 2, аспект 2: здания 2×2 — ищем место под весь прямоугольник
				if sim.is_buildable_rect(type_id, tile) and sim.placement_block(type_id, tile) == "" \
						and sim.placement_gap_ok(type_id, tile):
					return tile
	# районы (v1.21.1): рядом не вышло (правило цветовой ветки) — ищем у кластера
	if type_id != "":
		var anchor: Vector2i = sim._district_anchor(type_id)
		if anchor != Vector2i(-1, -1):
			var t_c: Vector2i = sim._tile_near_cluster(type_id, anchor)
			if t_c != Vector2i(-1, -1):
				return t_c
	return Vector2i(-1, -1)


## Построить здание мгновенно: ставим площадку, телепортируем строителя, тикаем.
func _build_now(sim: Object, type_id: String, near_from: Vector2i = Vector2i(-999, -999)) -> Dictionary:
	var builder: Dictionary = _resident_by_prof(sim, "builder")
	# личности M4 не мешают стройке в тестах: строитель в идеальном состоянии
	builder["mood"] = 100.0
	builder["traits"] = []
	builder["skill"] = 0.0
	builder["fatigue"] = 0.0   # v1.50: без усталости — длинные цепочки строек
	var near: Vector2i = near_from if near_from.x > -900 else sim.map.spawn_tile
	var tile := _find_free_tile(sim, near, type_id)
	_check(not tile == Vector2i(-1, -1), "%s: найдено место под стройку" % type_id)
	_check(sim.place_building(type_id, tile), "%s: стройплощадка заложена" % type_id)
	var site: Dictionary = sim.building_at(tile)
	_check(not site.is_empty() and not bool(site["done"]), "%s: площадка ждёт строителя" % type_id)
	var work: float = 0.0
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			work = float(d["build_work"])
	_teleport(sim, builder, tile)
	sim.tick(work + 0.1)
	site = sim.building_at(tile)
	_check(bool(site["done"]), "%s: строитель достроил за build_work" % type_id)
	return site


func _make_magic() -> Object:
	var magic = load("res://scripts/magic.gd").new()
	magic.setup(_read_json("res://data/magic.json"))
	return magic


func _build_at(sim: Object, type_id: String, tile: Vector2i) -> Dictionary:
	var builder: Dictionary = _resident_by_prof(sim, "builder")
	builder["mood"] = 100.0
	builder["traits"] = []
	builder["skill"] = 0.0
	var placed: bool = sim.place_building(type_id, tile)
	if not placed:
		# шахта/лесопилка/каменоломня: честный поиск у своего ресурса (2×2)
		var kinds: Array = []
		var on_resource := false
		match String(type_id):
			"mine":
				kinds = [sim.map.TILE_ORE, sim.map.TILE_DEADROCK]
				on_resource = true
			"sawmill":
				kinds = [sim.map.TILE_TREE]
			"quarry":
				kinds = [sim.map.TILE_ROCK, sim.map.TILE_ORE]
		if not kinds.is_empty():
			var g: Vector2i = sim._find_gather_tile(type_id, kinds, on_resource)
			if not g == Vector2i(-1, -1) and sim.place_building(type_id, g):
				tile = g
				placed = true
	if not placed:
		# районы (v1.21.1): заданный тайл не прошёл правило ветки — место
		# ищет сам симулятор (кластер своего типа, затем ветка)
		var auto_t: Vector2i = sim._find_autobuild_tile(type_id)
		if not auto_t == Vector2i(-1, -1) and sim.place_building(type_id, auto_t):
			tile = auto_t
			placed = true
	if not placed and String(type_id) == "armory":
		# оружейная: ищем 2×2 вокруг готовой кузни
		for b in sim.buildings:
			if not bool(b["done"]) or String(b["type"]) != "forge":
				continue
			var done := false
			for radius in range(1, 6):
				for dy in range(-radius, radius + 1):
					for dx in range(-radius, radius + 1):
						var t: Vector2i = (b["tile"] as Vector2i) + Vector2i(dx, dy)
						if sim.place_building("armory", t):
							tile = t
							placed = true
							done = true
							break
					if done:
						break
				if done:
					break
			if placed:
				break
	if not placed:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234567
		for i in 600:
			var t := Vector2i(rng.randi_range(2, sim.map.w - 3), rng.randi_range(2, sim.map.h - 3))
			if sim.place_building(type_id, t):
				tile = t
				placed = true
				break
	_check(placed, "%s: стройплощадка в заданном тайле" % type_id)
	var work := 1.0
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			work = float(d["build_work"])
	_teleport(sim, builder, tile)
	sim.tick(work + 0.1)
	return sim.building_at(tile)


## Волна из одного мутанта заданного типа в заданном тайле (детерминированно).
func _spawn_one_raider(sim: Object, type_id: String, tile: Vector2i) -> Dictionary:
	sim._enemies_cfg = _read_json("res://data/enemies.json")
	sim._spawn_raid(1, false)
	var r: Dictionary = sim.raiders[0]
	for e: Dictionary in sim._enemies_cfg:
		if String(e["id"]) == type_id:
			r["p"] = e
			r["type"] = type_id
	r["pos"] = sim.map.tile_center_px(tile)
	r["path"] = PackedVector2Array()
	return r


func _ward_test_farm_tile(sim: Object) -> Vector2i:
	for b in sim.buildings:
		if bool(b["done"]) and String(b.get("enchant", "")) != "ward":
			return b["tile"]
	return Vector2i(-1, -1)


## Первый тайл руды на карте.
func _ore_tile_of(sim: Object) -> Vector2i:
	for y in sim.map.h:
		for x in sim.map.w:
			if sim.map.grid[y][x] == sim.map.TILE_ORE:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Добавить жителя редкой профессии (в стартовом наборе её нет).
func _add_resident(sim: Object, res_name: String, prof: String) -> Dictionary:
	var r: Dictionary = sim._new_resident(res_name, prof, sim.map.spawn_tile)
	sim.residents.append(r)
	sim._next_id += 1
	return r


func _grass_tiles(sim: Object, near: Vector2i, n: int) -> Array:
	var out: Array = []
	for radius in range(0, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if out.size() >= n:
					return out
				var t: Vector2i = near + Vector2i(dx, dy)
				if sim.map.in_bounds(t) and sim.map.grid[t.y][t.x] == sim.map.TILE_GRASS \
						and sim.building_at(t).is_empty() and not (t in out):
					out.append(t)
	return out


func sim_m8_setup(map_b, scfg: Dictionary) -> void:
	var sim = load("res://scripts/world_sim.gd").new()
	sim.setup(map_b, scfg, 777)
	var ruin: Dictionary = {}
	var caravan: Dictionary = {}
	var camp_strength0 := 0.0
	for poi in map_b.pois:
		match String(poi["kind"]):
			"ruins":
				ruin = poi
			"caravan":
				caravan = poi
			"camp":
				camp_strength0 += float(poi["strength"])
	sim.mark_cleared(int(ruin["id"]))
	# v1.40.3: легендарные странники сами зачищают POI (legend "clear") и
	# рандомно пере-зачищали руину под конец прогона — флейк «сгустившийся
	# заново данж снова принимает героя». Странники не предмет этого теста.
	sim.legends = []
	_check(int(ruin["cleared_day"]) == 0, "зачистка локации отмечается в мире")
	_check(not sim.poi_enterable(ruin), "в зачищенный данж нельзя войти, пока он не сгустится заново")
	var caravan_tile0: Vector2i = caravan["tile"]
	var saw_siege := false
	var saw_outcome := false
	var saw_resettle := false
	var saw_reborn := false
	var caravan_moved := false
	for i in 90:
		for ev: Dictionary in sim.advance_day():
			match String(ev["type"]):
				"siege_start":
					saw_siege = true
				"siege_fell", "siege_repelled":
					saw_outcome = true
				"resettle":
					saw_resettle = true
				"poi_reborn":
					saw_reborn = true
				"caravan_moved":
					caravan_moved = true
	var camp_strength1 := 0.0
	for poi in map_b.pois:
		if String(poi["kind"]) == "camp":
			camp_strength1 += float(poi["strength"])
	_check(camp_strength1 > camp_strength0, "лагеря бандитов растут со временем")
	_check(saw_siege, "бандиты осаждают поселения — мир живёт без игрока (ответ №92)")
	_check(saw_outcome, "осады решаются: поселение падает или отбивается")
	_check(saw_resettle, "павшие поселения переселяются другими фракциями (ответ №4)")
	_check(saw_reborn, "зачищенные локации сгущаются заново")
	_check(sim.poi_enterable(ruin), "сгустившийся заново данж снова принимает героя")
	_check(caravan_moved, "караван перебирается по миру")
	_check(sim.chronicle.size() > 0, "мировые события пишутся в летопись")

	# торговля (ответ №40): монеты + живой обмен
	var pool := {"food": 50.0, "wood": 0.0, "stone": 0.0, "crystal": 0.0}
	var coins := 20
	var out: Dictionary = sim.trade_buy(pool, coins, "wood", 5, caravan, 9999)
	var wood_cost: int = int(ceilf(sim.buy_price("wood", caravan) * 5))
	_check(String(out["err"]) == "" and int(out["coins"]) == coins - wood_cost,
			"покупка ресурсов за монеты (у каравана — скидка)")
	_check(float(pool["wood"]) == 5.0, "купленное попадает в пул города (караван доставляет)")
	_check(String(sim.trade_buy(pool, 1, "stone", 100, caravan, 9999)["err"]) == "no_coins",
			"без монет покупки нет")
	var sell_out: Dictionary = sim.trade_sell(pool, 0, "wood", 3, caravan)
	_check(String(sell_out["err"]) == "" and float(pool["wood"]) == 2.0 and int(sell_out["coins"]) > 0,
			"продажа ресурсов приносит монеты")
	var out4: Dictionary = sim.trade_barter(pool, {"give": "food", "get": "stone", "give_n": 3, "get_n": 2})
	_check(String(out4["err"]) == "" and float(pool["food"]) == 47.0 and float(pool["stone"]) == 2.0,
			"живой обмен: ресурс на ресурс по таблице")
	var inv: Array = []
	var rune_id: String = sim.cult_rune_offer()
	_check(rune_id != "", "культ предлагает руну")
	var rune_out: Dictionary = sim.trade_rune(inv, 30, rune_id)
	_check(String(rune_out["err"]) == "" and inv.size() == 1 and String(inv[0]["id"]) == rune_id,
			"руна культа покупается за монеты в рюкзак")
	_check(String(sim.trade_rune(inv, 0, rune_id)["err"]) == "no_coins", "без монет руну не продадут")
	_check(String(sim.trade_rune(inv, 30, "")["err"]) == "no_runes", "рун у культа нет — продажи нет")
	_check(sim.coin_reward({"kind": "camp"}) > 0, "за лагерь бандитов платят монетами")

	# край города: выход на карту мира — проходим и ДОСТИЖИМ пешком от старта
	# (иначе герой не доберётся до края — «не переходит на карту мира»)
	var city_cfg: Dictionary = _read_json("res://data/city.json")
	var exit_ok := true
	for i in 12:
		var cmap = load("res://scripts/city_map.gd").new()
		cmap.generate(1000 + i * 3571, city_cfg)
		if cmap.is_walkable(cmap.world_exit_tile) == false \
				or cmap.astar.get_id_path(cmap.spawn_tile, cmap.world_exit_tile).is_empty():
			exit_ok = false
	_check(exit_ok, "выход на карту мира проходим и достижим пешком (12 сидов)")
	# вся рамка карты — зона перехода: направление наружу определяется верно
	var cm0 = load("res://scripts/city_map.gd").new()
	cm0.generate(424242, city_cfg)
	var border_ok: bool = cm0.border_dir(Vector2i(0, 5)) == Vector2i(-1, 0) \
			and cm0.border_dir(Vector2i(cm0.w - 1, 5)) == Vector2i(1, 0) \
			and cm0.border_dir(Vector2i(5, 0)) == Vector2i(0, -1) \
			and cm0.border_dir(Vector2i(5, cm0.h - 1)) == Vector2i(0, 1) \
			and cm0.border_dir(Vector2i(0, 0)) == Vector2i(-1, -1) \
			and cm0.border_dir(cm0.spawn_tile) == Vector2i.ZERO
	_check(border_ok, "рамка карты — зона перехода: border_dir по всем краям")
	_check(cm0.nearest_walkable(Vector2i(0, 0)) != Vector2i(-1, -1),
			"nearest_walkable всегда возвращает проходимый тайл")


# --- M9: полировка — спрайты, ассеты, платформенные мелочи -------------------

const _ASSETS := preload("res://scripts/assets.gd")

var _coins_log: Array = []


# --- M11: вишлист — духи леса, некромант, добыча скалы -----------------------

class FakeGame extends RefCounted:
	var inventory: Array = []
	var spellbook: Array = []
	var coins := 15
	var last_run_death := false
	var dungeon_clears := 0
	var dungeon_lock_day := 0
	var hero_kits := 0
	var start_residents := 10
	var start_level := "normal"
	var conflicts_enabled := true
	var world_active := false
	var city_return_tile := Vector2i(-1, -1)
	var world_hero_tile := Vector2i(-1, -1)
	var return_scene := ""
	var forced_biome := ""
	var dungeon_scale := 1.0
	var poi_id := 0
	var poi_coins := 0
	var in_dungeon := false
	var hero_saved_hp := -1
	var hero_saved_mana := -1
	var _autosave_day := 0
	var equipment := {"weapon": "", "armor": "", "accessory": "", "mount": ""}
	# v1.24: статы героя (как в Game — их читает/пишет сейв)
	const HERO_STAT_KEYS := ["str", "agi", "end", "int", "wis"]
	var hero_stats: Dictionary = {"str": 2.0, "agi": 2.0, "end": 2.0, "int": 2.0, "wis": 2.0}
	var codex := {"enemies": {}, "biomes": {}, "spells": {}, "items": {}, "gods": {}, "factions": {}}
	var stats := {"days": 0, "bosses": 0, "buildings": 0, "quests": 0, "hunts": 0}
	var city_sim = null
	var world_map = null
	var world_sim = null
	var skills = null
	# v1.41 («Мир v2», этап 3): города НПС и гостевой визит — как в Game
	var npc_cities = null
	var visiting_city_id := -1


func _make_game() -> FakeGame:
	var g := FakeGame.new()
	g.skills = load("res://scripts/skills.gd").new()
	g.skills.setup(_read_json("res://data/skills.json"))
	g.skills.add_xp(50)
	g.skills.choose("w1")
	g.city_sim = _make_sim()
	g.world_map = load("res://scripts/world_map.gd").new()
	g.world_map.generate(11, _read_json("res://data/world.json"))
	g.world_sim = load("res://scripts/world_sim.gd").new()
	g.world_sim.setup(g.world_map, _read_json("res://data/world.json"), 7)
	g.world_sim.advance_day()
	return g


func _count_runes(g: FakeGame, rune_id: String) -> int:
	var n := 0
	for stack in g.inventory:
		if String(stack["id"]) == rune_id:
			n += int(stack["count"])
	return n


class FakePotionHero extends RefCounted:
	var healed: Array = []
	var mana: Array = []
	var temp_dmg: Array = []
	var temp_armor: Array = []
	func heal(n: int) -> void: healed.append(n)
	func add_mana(n: int) -> void: mana.append(n)
	func temp_damage_bonus(dur: float, n: int) -> void: temp_dmg.append([dur, n])
	func temp_armor_bonus(dur: float, n: int) -> void: temp_armor.append([dur, n])


## Фейковый герой для анти-кайта: позиция/флаг смерти/приём урона (duck typing).
class FakeKiteHero extends RefCounted:
	var global_position := Vector2(50, 0)
	var dead := false
	var p := {"radius": 10}
	var hits := 0
	func take_damage(n: int) -> void: hits += 1


class SaveTestHook:
	static func run_save_roundtrip(wsim) -> void:
		var SG: Script = load("res://scripts/save_game.gd")
		var world_block: Dictionary = SG._world_block(wsim.map, wsim)
		var saved: Variant = world_block["sim"].get("giants", [])
		var parsed: Variant = JSON.parse_string(JSON.stringify(SG._enc(saved)))
		var restored: Array = []
		if parsed is Array:
			for g in SG._dec(parsed):
				var def: Dictionary = wsim.giants.species_def(String(g.get("id", "")))
				if not def.is_empty():
					restored.append(g)
		var ok: bool = restored.size() == wsim.giants.giants.size()
		if ok:
			for i in wsim.giants.giants.size():
				if String(wsim.giants.giants[i]["id"]) != String(restored[i]["id"]) \
						or String(wsim.giants.giants[i]["mood"]) != String(restored[i]["mood"]):
					ok = false
		if ok:
			print("  ok: гиганты переживают сейв (позиции и настроение, %d шт)" % restored.size())
		else:
			print("  FAIL: гиганты не переживают сейв")


func _w_by_id(wlist: Array, weapon_id: String) -> Dictionary:
	for w: Dictionary in wlist:
		if String(w["id"]) == weapon_id:
			return w
	return {}


func _spell_exists(magic: Dictionary, spell_id: String) -> bool:
	if spell_id == "":
		return false
	for s in magic.get("spells", []):
		if String(s["id"]) == spell_id:
			return String(s.get("where", "")) == "dungeon"
	return false


func _enemy_row_by_id(enemies: Array, enemy_id: String) -> Dictionary:
	for e in enemies:
		if String(e["id"]) == enemy_id:
			return e
	return {}


# --- M12: живой город — досуг, разговоры, похороны, сбор у костра ------------

class FakeInteractHero extends RefCounted:
	var global_position := Vector2.ZERO
	var dead := false
	var hits := 0
	func take_damage(_n: int, _s: String = "") -> void:
		hits += 1


# --- M14-G: навыки следов (issue #3) -----------------------------------------

func any_siege_start(evs: Array) -> bool:
	for ev in evs:
		if String(ev["type"]) == "siege_start":
			return true
	return false


# --- M14-I: вода и болото (issue #3) -----------------------------------------

func _homeless_t(r: Dictionary) -> bool:
	var h = r.get("home", null)
	return h == null or (h is Dictionary and (h as Dictionary).is_empty())


## Правки приёмки v1.20.1: видимый рост поля (дни вместо секунд, растения
## рисуются сами), вечерний снос продукции работником, саженцы из деревьев
## и автопосадка у лесопилки, липкие цели против «перебора действий».
