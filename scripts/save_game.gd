extends RefCounted
## Сейв/загрузка (M14-A, issue #3): JSON в user://saves/save.json.
## Формат версионирован полем "v"; несовместимый или битый сейв честно
## отклоняется (функция возвращает ключ локализации ошибки, "" — успех).
## Сохраняем: город (карта целиком + симуляция), мир (карта + sim),
## героя (рюкзак, гримуар, навыки, тайл, HP/мана). Данжи транзитны —
## из середины данжа сейва нет (сохранение доступно из города и карты мира).
##
## Векторы в JSON кодируются тегами: {"@":"v2"/"v2i","x":..,"y":..},
## PackedVector2Array — {"@":"pv2","p":[[x,y],..]}, словари с нестроковыми
## ключами (Vector2i дорог/следов) — {"@":"d","p":[[ключ,значение],..]}.
## Ссылки жителей на здания (bld/site/home) сохраняются как id и
## восстанавливаются ссылками на словари из buildings после загрузки.

const SAVE_PATH := "user://saves/save.json"
const FORMAT_VERSION := 1

const CITY_CFG_PATH := "res://data/city.json"
const CITY_MAP_SCRIPT := "res://scripts/city_map.gd"
const CITY_SIM_SCRIPT := "res://scripts/city_sim.gd"
const WORLD_CFG_PATH := "res://data/world.json"
const WORLD_MAP_SCRIPT := "res://scripts/world_map.gd"
const WORLD_SIM_SCRIPT := "res://scripts/world_sim.gd"


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func clear_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


## Сохранить игру. hero_tile — где герой сейчас (сцена знает точнее всего),
## hero_hp/hero_mana — состояние героя (из данжа не вызывается).
static func save_game(game, hero_tile: Vector2i, hero_hp: int, hero_mana: int) -> String:
	var data := save_snapshot(game, hero_tile, hero_hp, hero_mana)
	if data.is_empty():
		return "save.no_game"
	return write_snapshot(data)


## Снапшот сейва (v1.28.1): сбор данных БЕЗ записи на диск — быстрый,
## вызывается в кадре. Пустой словарь — нет игры.
static func save_snapshot(game, hero_tile: Vector2i, hero_hp: int, hero_mana: int) -> Dictionary:
	if game.city_sim == null or game.world_map == null or game.world_sim == null:
		return {}
	var wt := Vector2i(-1, -1)
	if bool(game.world_active):
		wt = hero_tile
	var ct: Vector2i = game.city_return_tile
	if not bool(game.world_active):
		ct = hero_tile
	return {
		"v": FORMAT_VERSION,
		"meta": {
			"day": int(game.city_sim.day),
			"date": Time.get_datetime_string_from_system(),
		},
		"game": _enc(_game_block(game, ct, wt)),
		"skills": _enc(_skills_block(game)),
		"hero": {"tile": [hero_tile.x, hero_tile.y], "hp": int(hero_hp), "mana": int(hero_mana)},
		"city": _enc(_city_block(game.city_sim)),
		"world": _enc(_world_block(game.world_map, game.world_sim)),
		"codex": game.codex,
		"stats": game.stats,
	}


## Запись снапшота: строковизация + диск. v1.28.1 — вызывается В ФОНОВОМ
## ПОТОКЕ автосейвом (страшный фриз по утрам был здесь: stringify + запись
## сотен КБ на диск в кадре). Пишет во временный файл и переименовывает —
## читатель не увидит полуфайл. Возвращает "" или ключ ошибки.
static func write_snapshot(data: Dictionary) -> String:
	if DirAccess.make_dir_recursive_absolute(SAVE_PATH.get_base_dir()) != OK \
			and not DirAccess.dir_exists_absolute(SAVE_PATH.get_base_dir()):
		return "save.write_failed"
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "save.write_failed"
	f.store_string(JSON.stringify(data, "\t", true, true))
	f.close()
	if f.get_error() != OK and f.get_error() != ERR_FILE_EOF:
		DirAccess.remove_absolute(tmp)
		return "save.write_failed"
	# атомарная подмена: сначала переименование поверх, потом запасной путь
	if DirAccess.rename_absolute(tmp, SAVE_PATH) != OK:
		DirAccess.remove_absolute(SAVE_PATH)
		if DirAccess.rename_absolute(tmp, SAVE_PATH) != OK:
			return "save.write_failed"
	return ""


## Загрузить игру в переданный инстанс Game. Возвращает "" или ключ ошибки.
static func load_game(game) -> String:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return "save.no_save"
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return "save.load_failed"
	var data: Dictionary = parsed
	if int(data.get("v", 0)) != FORMAT_VERSION:
		return "save.bad_version"
	if not (data.has("game") and data.has("city") and data.has("world")):
		return "save.load_failed"
	if _apply_world(game, data["world"]) != "":
		return "save.load_failed"
	if _apply_city(game, data["city"]) != "":
		return "save.load_failed"
	_apply_game(game, data["game"], data.get("skills", {}), data.get("hero", {}))
	# кодекс и статистика (M14-K)
	if data.get("codex", {}) is Dictionary:
		game.codex = data["codex"]
	if data.get("stats", {}) is Dictionary:
		game.stats = data["stats"]
	game.in_dungeon = false
	game._autosave_day = int(game.city_sim.day)
	return ""


## Тайл героя в городе (для автосейва, когда сцена недоступна).
static func city_hero_tile(game) -> Vector2i:
	if game.city_sim != null and bool(game.city_sim.hero_alive) \
			and game.city_sim.map != null:
		return game.city_sim.map.tile_of_px(game.city_sim.hero_pos)
	if game.city_return_tile.x >= 0:
		return game.city_return_tile
	if game.city_sim != null:
		return game.city_sim.map.spawn_tile
	return Vector2i(-1, -1)


# --- сохранение -------------------------------------------------------------

static func _game_block(game, city_tile: Vector2i, world_tile: Vector2i) -> Dictionary:
	return {
		"inventory": game.inventory,
		"spellbook": game.spellbook,
		"coins": int(game.coins),
		"last_run_death": bool(game.last_run_death),
		"dungeon_clears": int(game.dungeon_clears),
		"dungeon_lock_day": int(game.dungeon_lock_day),
		"hero_kits": int(game.hero_kits),
		"start_residents": int(game.start_residents),
		"start_level": String(game.start_level),
		"conflicts_enabled": bool(game.conflicts_enabled),
		"world_active": bool(game.world_active),
		"equipment": game.equipment,
		"hero_stats": game.get("hero_stats") if game.get("hero_stats") != null else {},   # статы героя (v1.24)
		"city_return_tile": [city_tile.x, city_tile.y],
		"world_hero_tile": [world_tile.x, world_tile.y],
	}


static func _skills_block(game) -> Dictionary:
	if game.skills == null:
		return {}
	return {
		"xp": int(game.skills.xp),
		"level": int(game.skills.level),
		"pending": int(game.skills.pending),
		"taken": game.skills.taken,
	}


static func _city_block(sim) -> Dictionary:
	var m = sim.map
	return {
		"map": {
			"w": int(m.w), "h": int(m.h), "ts": int(m.ts),
			"grid": _grid_rows(m),
			"anomaly": [m.anomaly_tile.x, m.anomaly_tile.y],
			"spawn": [m.spawn_tile.x, m.spawn_tile.y],
			"world_exit": [m.world_exit_tile.x, m.world_exit_tile.y],
			"road": _tile_keys(m.road),
			"wear": _tile_vals(m.wear),
			"rock_hp": _tile_vals(m.rock_hp),
			"stumps": _tile_keys(m.stumps),
			"saplings": _tile_vals(m.saplings),
			"tree_size": _tile_vals(m.tree_size),
			"tree_growth": _tile_vals(m.tree_growth),
			"logs": _tile_vals(m.logs),
			"bridges": _tile_keys(m.bridges),
		},
		"residents": _residents_save(sim),
		"sim": _city_sim_block(sim),
	}


static func _city_sim_block(sim) -> Dictionary:
	return {
		"res": sim.res,
		"time": float(sim.time),
		"day": int(sim.day),
		"speed": int(sim.speed),
		"pollution": float(sim.pollution),
		"resonance_left": float(sim.resonance_left),
		"resonance_mult": float(sim.resonance_mult),
		"chronicle": sim.chronicle,
		"base_pop": int(sim.base_pop),
		"conflicts": bool(sim.conflicts),
		"buildings": sim.buildings,
		"zones": sim.zones,
		"_zone_id": int(sim._zone_id),
		"plaza": [int(sim.plaza.x), int(sim.plaza.y)],
		"day_plans": sim.day_plans,
		"_next_id": int(sim._next_id),
		"animals": sim.animals,
		"livestock": sim.livestock,
		"_livestock_id": int(sim._livestock_id),
		"caravans_out": sim.caravans_out,
		"caravan_here": bool(sim.caravan_here),
		"_last_caravan_day": int(sim._last_caravan_day),
		"wanderers": sim.wanderers,
		"_wanderer_id": int(sim._wanderer_id),
		"_last_wanderer_day": int(sim._last_wanderer_day),
		"raiders": sim.raiders,
		"raid_active": bool(sim.raid_active),
		"raid_siege": bool(sim.raid_siege),
		"raid_count": int(sim.raid_count),
		"razed_this_raid": int(sim.razed_this_raid),
		"storm_state": String(sim.storm_state),
		"storm_left": float(sim.storm_left),
		"_spell_ready": sim._spell_ready,
		"_last_event_day": int(sim._last_event_day),
		"_last_daily_day": int(sim._last_daily_day),
		"_gate_state": sim._gate_state,
		"_next_raid_at": float(sim._next_raid_at),
		"_raid_gap_days": float(sim._raid_gap_days),
		"_raid_not_before": float(sim._raid_not_before),
		"_raid_warned": bool(sim._raid_warned),
		"_raid_kind": String(sim._raid_kind),
		"graves": sim.graves,
		"funeral_target": sim.funeral_target,
		"funeral_pos": sim.funeral_pos,
		"cemetery_tile": [int(sim.cemetery_tile.x), int(sim.cemetery_tile.y)],
		"corpses": sim.corpses,
		"_bld_id": int(sim._bld_id),
		"_storm_struck_at": float(sim._storm_struck_at),
		"researched": sim.researched,
		"forest_anger": float(sim.forest_anger),
		"necro_dark": float(sim.necro_dark),
		"necro_army": int(sim.necro_army),
		"necro_known": bool(sim.necro_known),
		"necro_ghosts": sim.necro_ghosts,
		"_necro_chosen": bool(sim._necro_chosen),
		"_forest_warned": bool(sim._forest_warned),
		"_forest_cooldown": float(sim._forest_cooldown),
		"active_laws": sim.active_laws,
		"god": String(sim.god),
		"autonomous": bool(sim.autonomous),
		"prayed_day": int(sim.prayed_day),
		"weather": String(sim.weather),
		"froze_last_night": bool(sim.froze_last_night),
		"story_chapter": int(sim.story_chapter),
		"story_side": String(sim.story_side),
		"story_flags": sim.story_flags,
	}


static func _world_block(wmap, wsim) -> Dictionary:
	return {
		"map": {
			"w": int(wmap.w), "h": int(wmap.h), "ts": int(wmap.ts),
			"grid": _grid_rows(wmap),
			"city_tile": [wmap.city_tile.x, wmap.city_tile.y],
			"fog": _tile_keys(wmap.fog),
			"pois": wmap.pois,
		},
		"sim": {
			"day": int(wsim.day),
			"chronicle": wsim.chronicle,
			"sieges": wsim.sieges,
			"tracks": wsim.tracks,
			"giants": wsim.giants.giants if wsim.giants != null else [],
			"rep": wsim.rep,
			"legends": _legends_save(wsim),
			"_legend_id": int(wsim._legend_id),
		},
	}


## Странники: def — ссылка на конфиг, в сейв кладём id (v1.22).
static func _legends_save(wsim) -> Array:
	var out: Array = []
	for l in wsim.legends:
		var d := {}
		for k in l:
			d[k] = String(l[k]["id"]) if k == "def" else l[k]
		d["tile"] = [int(l["tile"].x), int(l["tile"].y)]
		out.append(d)
	return out


## Жители: ссылки на здания (bld/site/home) превращаем в id зданий.
## v1.28.1: защитно — ссылка без id (битая/чужая) сохраняется как null,
## а не роняет весь сейв (было: «Invalid access 'id'» и отмена сохранения).
static func _residents_save(sim) -> Array:
	var out: Array = []
	for r in sim.residents:
		var d := {}
		for k in r:
			if k in ["bld", "site", "home"]:
				var v: Variant = r[k]
				d[k] = int(v["id"]) if (v is Dictionary and v.has("id")) else null
			else:
				d[k] = r[k]
		out.append(d)
	return out


## Сетка картой строк-цифр: grid[y][x] 0..5 -> "00123...".
static func _grid_rows(m) -> Array:
	var rows: Array = []
	for y in m.h:
		var row := ""
		for x in m.w:
			row += str(int(m.grid[y][x]))
		rows.append(row)
	return rows


static func _tile_keys(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append([int(k.x), int(k.y)])
	return out


static func _tile_vals(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append([int(k.x), int(k.y), d[k]])
	return out


# --- загрузка ---------------------------------------------------------------

static func _apply_game(game, gd: Variant, skd: Variant, hero_d: Variant) -> void:
	var g: Dictionary = gd if gd is Dictionary else {}
	game.inventory = []
	for stack in g.get("inventory", []):
		game.inventory.append({"id": String(stack["id"]), "count": int(stack["count"])})
	game.spellbook = []
	for s in g.get("spellbook", []):
		game.spellbook.append(String(s))
	game.coins = int(g.get("coins", 0))
	game.last_run_death = bool(g.get("last_run_death", false))
	game.dungeon_clears = int(g.get("dungeon_clears", 0))
	game.dungeon_lock_day = int(g.get("dungeon_lock_day", 0))
	game.hero_kits = int(g.get("hero_kits", 0))
	game.start_residents = int(g.get("start_residents", 1))
	game.start_level = String(g.get("start_level", "normal"))
	game.conflicts_enabled = bool(g.get("conflicts_enabled", true))
	game.world_active = bool(g.get("world_active", false))
	var eq: Dictionary = g.get("equipment", {})
	game.equipment = {
		"weapon": String(eq.get("weapon", "")),
		"armor": String(eq.get("armor", "")),
		"accessory": String(eq.get("accessory", "")),
		"mount": String(eq.get("mount", "")),
	}
	# статы героя (v1.24): рост от дел — переживает забеги и сейвы
	var hs: Dictionary = _dec(g.get("hero_stats", {}))
	var stat_keys: Variant = game.get("HERO_STAT_KEYS")
	if stat_keys is Array and game.get("hero_stats") is Dictionary:
		for st_id in stat_keys:
			if hs.has(st_id):
				game.hero_stats[String(st_id)] = float(hs[st_id])
	var ct: Array = g.get("city_return_tile", [-1, -1])
	game.city_return_tile = Vector2i(int(ct[0]), int(ct[1]))
	var wt: Array = g.get("world_hero_tile", [-1, -1])
	game.world_hero_tile = Vector2i(int(wt[0]), int(wt[1]))
	game.return_scene = ""
	game.forced_biome = ""
	game.dungeon_scale = 1.0
	game.poi_id = 0
	game.poi_coins = 0
	var sk: Dictionary = skd if skd is Dictionary else {}
	if game.skills != null and not sk.is_empty():
		game.skills.xp = int(sk.get("xp", 0))
		game.skills.level = int(sk.get("level", 1))
		game.skills.pending = int(sk.get("pending", 0))
		game.skills.taken = []
		for t in sk.get("taken", []):
			game.skills.taken.append(String(t))
	var hero: Dictionary = hero_d if hero_d is Dictionary else {}
	# HP героя восстановится при следующем спавне в городе (мана в городе с нуля)
	game.hero_saved_hp = int(hero.get("hp", -1))
	game.hero_saved_mana = int(hero.get("mana", -1))


static func _apply_city(game, cd: Variant) -> String:
	if not (cd is Dictionary):
		return "save.load_failed"
	var cfg_v: Variant = _read_json(CITY_CFG_PATH)
	if not (cfg_v is Dictionary):
		return "save.load_failed"
	var cfg: Dictionary = cfg_v
	var map = load(CITY_MAP_SCRIPT).new()
	map.generate(0, cfg)   # каркас (astar, размеры) — состояние перекрывается ниже
	if _apply_city_map(map, cd.get("map", {}), cfg) != "":
		return "save.load_failed"
	map.classify_water()   # v1.29.1: типы воды (река/озеро/болото) — по
	                       # ВОССТАНОВЛЕННОЙ сетке, не по каркасу сида 0
	var sim = load(CITY_SIM_SCRIPT).new()
	sim.map = map
	sim.cfg = cfg
	var people_v: Variant = _read_json(sim.PEOPLE_CFG_PATH)
	sim.people = people_v if people_v is Dictionary else {}
	sim._trait_map = {}
	for td in sim.people.get("traits", []):
		sim._trait_map[String(td["id"])] = td
	var rdata: Variant = _read_json(sim.RESEARCH_CFG_PATH)
	sim.research_cfg = rdata if rdata is Dictionary else {}
	sim.researched = []
	sim._event_rng.randomize()
	sim._raid_rng.randomize()
	var sd: Dictionary = _dec(cd.get("sim", {}))
	if sd.is_empty():
		return "save.load_failed"
	sim.res = _num_dict(sd.get("res", {}))
	# v1.21: новые ресурсы (gems) и всё, что могло не попасть в старый сейв, —
	# ключи должны существовать: _add_resource_capped читает их напрямую
	for key in sim.RESOURCES:
		if not sim.res.has(key):
			sim.res[key] = 0
	sim.time = float(sd.get("time", 0.0))
	sim.day = int(sd.get("day", 1))
	sim.speed = 1
	sim.paused = false
	sim.pollution = float(sd.get("pollution", 0.0))
	sim.resonance_left = float(sd.get("resonance_left", 0.0))
	sim.resonance_mult = float(sd.get("resonance_mult", 1.0))
	sim.chronicle = _dec(sd.get("chronicle", []))
	for e in sim.chronicle:
		e["day"] = int(e.get("day", 0))
	sim.base_pop = int(sd.get("base_pop", 0))
	sim.conflicts = bool(sd.get("conflicts", true))
	sim.buildings = _dec(sd.get("buildings", []))
	sim._bld_ver += 1   # список зданий заменён целиком — индекс клеток устарел (v1.21.4)
	for b in sim.buildings:
		b["id"] = int(b.get("id", 0))
		b["done"] = bool(b.get("done", false))
		b["progress"] = float(b.get("progress", 0.0))
		b["worker"] = int(b.get("worker", -1))
		b["ench_mult"] = float(b.get("ench_mult", 1.0))
		b["stun_left"] = float(b.get("stun_left", 0.0))
		b["hp"] = float(b.get("hp", 1.0))
		var pile: Dictionary = b.get("pile", {})
		for k in pile:
			pile[k] = float(pile[k])
	sim.zones = _dec(sd.get("zones", []))
	var kept_zones: Array = []
	for z in sim.zones:
		# правки v1.20: остались только Поле и Пастбище — старые зоны вычищаем
		if String(z.get("type", "")) in ["field", "pasture"]:
			z["id"] = int(z.get("id", 0))
			kept_zones.append(z)
	sim.zones = kept_zones
	sim._zone_id = int(sd.get("_zone_id", 1))
	var pz: Array = sd.get("plaza", [-1, -1])
	sim.plaza = Vector2i(int(pz[0]), int(pz[1]))
	sim.day_plans = _dec(sd.get("day_plans", []))
	sim.events = []   # пересчёт не переигрывает тосты прошлой сессии
	sim._next_id = int(sd.get("_next_id", 1))
	sim.animals = _dec(sd.get("animals", []))
	sim.livestock = _dec(sd.get("livestock", []))
	for a in sim.livestock:
		a["id"] = int(a.get("id", 0))
		a["pasture"] = int(a.get("pasture", -1))
	sim._livestock_id = int(sd.get("_livestock_id", 1))
	sim.caravans_out = _dec(sd.get("caravans_out", []))
	sim.caravan_here = bool(sd.get("caravan_here", false))
	sim._last_caravan_day = int(sd.get("_last_caravan_day", -99))
	# бродячие торговцы у палаток (этап 2, аспект 4): путь и поле edge — векторы
	sim.wanderers = _dec(sd.get("wanderers", []))
	for w in sim.wanderers:
		w["tent"] = int(w.get("tent", -1))
	sim._wanderer_id = int(sd.get("_wanderer_id", 1))
	sim._last_wanderer_day = int(sd.get("_last_wanderer_day", -99))
	sim.raiders = _dec(sd.get("raiders", []))
	sim.raid_active = bool(sd.get("raid_active", false))
	sim.raid_siege = bool(sd.get("raid_siege", false))
	sim.raid_count = int(sd.get("raid_count", 0))
	sim.razed_this_raid = int(sd.get("razed_this_raid", 0))
	sim.storm_state = String(sd.get("storm_state", ""))
	sim.storm_left = float(sd.get("storm_left", 0.0))
	sim._spell_ready = {}
	var sready: Dictionary = sd.get("_spell_ready", {})
	for k in sready:
		sim._spell_ready[String(k)] = float(sready[k])
	sim._last_event_day = int(sd.get("_last_event_day", 0))
	sim._last_daily_day = int(sd.get("_last_daily_day", 0))
	sim._gate_state = {}
	var gstate: Dictionary = sd.get("_gate_state", {})
	for k in gstate:
		sim._gate_state[int(k)] = bool(gstate[k])
	sim._next_raid_at = float(sd.get("_next_raid_at", 0.0))
	sim._raid_gap_days = float(sd.get("_raid_gap_days", 10.0))
	sim._raid_not_before = float(sd.get("_raid_not_before", 0.0))
	sim._raid_warned = bool(sd.get("_raid_warned", false))
	sim._raid_kind = String(sd.get("_raid_kind", "mutant"))
	sim.graves = _dec(sd.get("graves", []))
	for gr in sim.graves:
		gr["ready"] = bool(gr.get("ready", false))
	sim.funeral_target = _dec_v2i(sd.get("funeral_target", Vector2i(-1, -1)))
	sim.funeral_pos = _dec_v2(sd.get("funeral_pos", Vector2.ZERO))
	# кладбище и останки (v1.23): тайлы останков — Vector2i, _dec их восстановил
	var cem: Array = sd.get("cemetery_tile", [-1, -1])
	sim.cemetery_tile = Vector2i(int(cem[0]), int(cem[1]))
	sim.corpses = _dec(sd.get("corpses", []))
	sim._bld_id = int(sd.get("_bld_id", 1))
	sim._storm_struck_at = float(sd.get("_storm_struck_at", 0.0))
	sim.researched = []
	for t in sd.get("researched", []):
		sim.researched.append(String(t))
	sim.forest_anger = float(sd.get("forest_anger", 0.0))
	sim.necro_dark = float(sd.get("necro_dark", 0.0))
	sim.necro_army = int(sd.get("necro_army", 0))
	sim.necro_known = bool(sd.get("necro_known", false))
	sim.necro_ghosts = _dec(sd.get("necro_ghosts", []))
	sim._necro_chosen = bool(sd.get("_necro_chosen", false))
	sim._forest_warned = bool(sd.get("_forest_warned", false))
	sim._forest_cooldown = float(sd.get("_forest_cooldown", 0.0))
	# законы и вера (M14-H)
	sim.active_laws = []
	for l in sd.get("active_laws", []):
		sim.active_laws.append(String(l))
	sim.god = String(sd.get("god", ""))
	sim.prayed_day = int(sd.get("prayed_day", -1))
	# автономная деревня (правки v1.12.0)
	sim.autonomous = bool(sd.get("autonomous", false))
	# погода (M14-J)
	sim.weather = String(sd.get("weather", "clear"))
	sim.froze_last_night = bool(sd.get("froze_last_night", false))
	# сюжет (M14-L)
	sim.story_chapter = int(sd.get("story_chapter", 0))
	sim.story_side = String(sd.get("story_side", ""))
	sim.story_flags = _dec(sd.get("story_flags", {}))
	# жители после зданий: ссылки bld/site/home восстанавливаются по id
	sim.residents = _dec(cd.get("residents", []))
	for r in sim.residents:
		r["id"] = int(r.get("id", 0))
		r["fatigue"] = float(r.get("fatigue", 0.0))
		r["mood"] = float(r.get("mood", 50.0))
		r["skill"] = float(r.get("skill", 0.0))
		r["rank"] = int(r.get("rank", 0))
		r["age_days"] = float(r.get("age_days", 100.0))
		r["ail_days"] = float(r.get("ail_days", 0.0))
		r["friend"] = int(r.get("friend", -1))
		r["work_bonus"] = float(r.get("work_bonus", 0.0))
		r["partner"] = int(r.get("partner", -1))
		r["bld"] = _building_ref(sim, r.get("bld"))
		r["site"] = _building_ref(sim, r.get("site"))
		r["home"] = _building_ref(sim, r.get("home"))
		# жизнь v3 (M14-F): старые сейвы без новых полей получают пустые значения
		if not r.has("rel"):
			r["rel"] = {}
		if not r.has("mem"):
			r["mem"] = []
		if not r.has("goal"):
			r["goal"] = ""
		if not r.has("goal_prev"):
			r["goal_prev"] = ""
		if not r.has("tavern_visited"):
			r["tavern_visited"] = false
		if not r.has("parents"):
			r["parents"] = []   # родители-жители (жильё v1.20)
		if not r.has("golem"):
			r["golem"] = false   # голем-староста (правки v1.20)
	# события-тосты прошлой сессии не переигрываем; ландшафт перерисовать
	sim.events = []
	sim.hero_alive = false
	sim.hero_pos = Vector2.ZERO
	sim.terrain_dirty = true
	sim.static_dirty = true   # земля (зоны/дороги/плиты) — перевыпечь (v1.22)
	# миграция старых сейвов: здания 1×1 → 2×2 (этап 2, аспект 2), затем
	# сплошные клетки всем готовым зданиям (препятствие для всех)
	sim.migrate_legacy_buildings()
	for b in sim.buildings:
		if bool(b["done"]):
			sim._set_bld_solid(b, true)
	sim._update_gates()
	# утренний тик после загрузки (правки v1.20): площадь и голем на месте,
	# староста раздаёт план заново — город не «застызает» между сессиями
	sim._ensure_plaza()
	sim._spawn_golem()
	sim.morning_plan()
	game.city_sim = sim
	return ""


static func _apply_city_map(map, md: Variant, cfg: Dictionary) -> String:
	if not (md is Dictionary):
		return "save.load_failed"
	map.w = int(md.get("w", 0))
	map.h = int(md.get("h", 0))
	map.ts = int(md.get("ts", 32))
	if map.w <= 0 or map.h <= 0:
		return "save.load_failed"
	map.grid = []
	for row_s in md.get("grid", []):
		var row := []
		row.resize(map.w)
		var s := String(row_s)
		for x in map.w:
			row[x] = int(s.substr(x, 1)) if x < s.length() else 0
		map.grid.append(row)
	var an: Array = md.get("anomaly", [0, 0])
	map.anomaly_tile = Vector2i(int(an[0]), int(an[1]))
	var sp: Array = md.get("spawn", [0, 0])
	map.spawn_tile = Vector2i(int(sp[0]), int(sp[1]))
	var we: Array = md.get("world_exit", [0, 0])
	map.world_exit_tile = Vector2i(int(we[0]), int(we[1]))
	map.road = {}
	for e in md.get("road", []):
		map.road[Vector2i(int(e[0]), int(e[1]))] = true
	map.wear = {}
	for e in md.get("wear", []):
		map.wear[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	map.rock_hp = {}
	for e in md.get("rock_hp", []):
		map.rock_hp[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	map.stumps = {}
	for e in md.get("stumps", []):
		map.stumps[Vector2i(int(e[0]), int(e[1]))] = true
	map.bridges = {}
	for e in md.get("bridges", []):
		map.bridges[Vector2i(int(e[0]), int(e[1]))] = true
	map.saplings = {}
	for e in md.get("saplings", []):
		map.saplings[Vector2i(int(e[0]), int(e[1]))] = {"t": float(e[2].get("t", 0.0))}
	map.tree_size = {}   # размеры деревьев (v1.21); старые сейвы — малые
	for e in md.get("tree_size", []):
		map.tree_size[Vector2i(int(e[0]), int(e[1]))] = int(e[2])
	map.tree_growth = {}
	for e in md.get("tree_growth", []):
		map.tree_growth[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	map.logs = {}   # поваленные брёвна (v1.21.2)
	for e in md.get("logs", []):
		map.logs[Vector2i(int(e[0]), int(e[1]))] = {"size": int(e[2].get("size", 1))}
	# миграция старых сейвов (v1.21): лес без размеров — назначаем по хэшу тайла
	if map.tree_size.is_empty():
		for y in map.h:
			for x in map.w:
				if map.grid[y][x] == map.TILE_TREE:
					var roll := float((int((x * 73856093) ^ (y * 19349663)) % 100 + 100) % 100)
					map.tree_size[Vector2i(x, y)] = map.TREE_SMALL if roll < 30.0 \
							else (map.TREE_MEDIUM if roll < 75.0 else map.TREE_LARGE)
	map._setup_astar()
	map.mark_terrain_solid()   # вода/скалы/руда сплошные (этап 2); мосты учтены выше
	var weight := float(cfg.get("roads", {}).get("astar_weight", 0.4))
	for p in map.road:
		map.astar.set_point_weight_scale(p, weight)
		map.astar_raider.set_point_weight_scale(p, weight)   # сетка мутантов (v1.26)
	return ""


static func _apply_world(game, wd: Variant) -> String:
	if not (wd is Dictionary):
		return "save.load_failed"
	var cfg_v: Variant = _read_json(WORLD_CFG_PATH)
	if not (cfg_v is Dictionary):
		return "save.load_failed"
	var cfg: Dictionary = cfg_v
	var map = load(WORLD_MAP_SCRIPT).new()
	map.generate(0, cfg)   # каркас — сетка/туман/POI перекрываются ниже
	var md: Dictionary = wd.get("map", {})
	map.w = int(md.get("w", 0))
	map.h = int(md.get("h", 0))
	map.ts = int(md.get("ts", 32))
	if map.w <= 0 or map.h <= 0:
		return "save.load_failed"
	map.grid = []
	for row_s in md.get("grid", []):
		var row := []
		row.resize(map.w)
		var s := String(row_s)
		for x in map.w:
			row[x] = int(s.substr(x, 1)) if x < s.length() else 0
		map.grid.append(row)
	var ct: Array = md.get("city_tile", [0, 0])
	map.city_tile = Vector2i(int(ct[0]), int(ct[1]))
	map.fog = {}
	for e in md.get("fog", []):
		map.fog[Vector2i(int(e[0]), int(e[1]))] = true
	map.pois = []
	var max_poi_id := 0
	for pd in md.get("pois", []):
		var poi: Dictionary = _dec(pd)
		poi["id"] = int(poi.get("id", 0))
		poi["kind"] = String(poi.get("kind", ""))
		poi["biome"] = String(poi.get("biome", ""))
		poi["faction"] = String(poi.get("faction", ""))
		poi["discovered"] = bool(poi.get("discovered", false))
		poi["strength"] = float(poi.get("strength", 0.0))
		poi["state"] = String(poi.get("state", "ok"))
		poi["cleared_day"] = int(poi.get("cleared_day", -1))
		poi["used"] = bool(poi.get("used", false))
		poi["nest_days"] = int(poi.get("nest_days", 0))
		poi["nest_level"] = int(poi.get("nest_level", 0))
		poi["plunder"] = float(poi.get("plunder", 0.0))
		poi["fell_day"] = int(poi.get("fell_day", -1))
		map.pois.append(poi)
		max_poi_id = maxi(max_poi_id, poi["id"])
	map._poi_id = max_poi_id + 1
	map._setup_astar()   # веса — по перекрытой сетке (дороги уже в тайлах)
	var sim = load(WORLD_SIM_SCRIPT).new()
	sim.setup(map, cfg, 12345)
	var wsd: Dictionary = _dec(wd.get("sim", {}))
	sim.day = int(wsd.get("day", 0))
	sim.chronicle = []
	for e in wsd.get("chronicle", []):
		e["day"] = int(e.get("day", 0))
		sim.chronicle.append(e)
	sim.sieges = []
	for s in wsd.get("sieges", []):
		s["settlement_id"] = int(s.get("settlement_id", 0))
		s["camp_id"] = int(s.get("camp_id", 0))
		s["left"] = int(s.get("left", 0))
		s["big"] = bool(s.get("big", false))
		sim.sieges.append(s)
	sim.tracks = _dec(wsd.get("tracks", {}))
	for t in sim.tracks:
		var tr: Dictionary = sim.tracks[t]
		tr["dir"] = Vector2i(tr["dir"]) if tr["dir"] is Vector2i else Vector2i(int(tr["dir"][0]), int(tr["dir"][1]))
		tr["camp"] = int(tr.get("camp", 0))
		tr["age"] = int(tr.get("age", 0))
	# репутация фракций (M14-H)
	sim.rep = {}
	var repd: Dictionary = wsd.get("rep", {})
	for k in repd:
		sim.rep[k] = float(repd[k])
	# гиганты (M14-E): позиции/настроение из сейва, описания — из конфига
	if sim.giants != null:
		var saved_giants: Array = _dec(wsd.get("giants", []))
		var restored: Array = []
		for g in saved_giants:
			var def: Dictionary = sim.giants.species_def(String(g.get("id", "")))
			if def.is_empty():
				continue
			restored.append({
				"id": String(g["id"]), "def": def,
				"px": g.get("px", Vector2.ZERO), "tx": g.get("tx", Vector2.ZERO),
				"mood": String(g.get("mood", "neutral")),
				"days": float(g.get("days", 0.0)),
				"wait": float(g.get("wait", 1.0)),
			})
		if not restored.is_empty():
			sim.giants.giants = restored
	# легендарные странники (v1.22): состояние из сейва, def — из конфига;
	# в старых сейвах ключа нет — свежесозданные странники остаются как есть
	if wsd.has("legends"):
		var legend_defs := {}
		for d in cfg.get("legends", {}).get("defs", []):
			legend_defs[String(d["id"])] = d
		var restored_legends: Array = []
		for ld in _dec(wsd.get("legends", [])):
			var ldef: Dictionary = legend_defs.get(String(ld.get("def", "")), {})
			if ldef.is_empty():
				continue
			var lt: Array = ld.get("tile", [0, 0])
			restored_legends.append({
				"id": int(ld.get("id", 0)), "def": ldef,
				"tile": Vector2i(int(lt[0]), int(lt[1])),
				"path": [], "state": String(ld.get("state", "rest")),
				"target_poi": int(ld.get("target_poi", -1)),
				"days_left": int(ld.get("days_left", 1)),
				"rumor_used": bool(ld.get("rumor_used", false)),
			})
		sim.legends = restored_legends
		sim._legend_id = int(wsd.get("_legend_id", restored_legends.size() + 1))
	game.world_map = map
	game.world_sim = sim
	return ""


# --- ссылки и конвертеры ----------------------------------------------------

static func _building_ref(sim, v: Variant):
	if v == null:
		return null
	var id := int(v) if not (v is Dictionary) else int(v.get("id", -1))
	for b in sim.buildings:
		if int(b["id"]) == id:
			return b
	return null


static func _num_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = float(d[k])
	return out


static func _dec_v2i(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


static func _dec_v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


## Рекурсивная упаковка в JSON-совместимые значения (векторы/пути/ключи).
static func _enc(v: Variant) -> Variant:
	if v is Vector2:
		return {"@": "v2", "x": v.x, "y": v.y}
	if v is Vector2i:
		return {"@": "v2i", "x": v.x, "y": v.y}
	if v is PackedVector2Array:
		var pts: Array = []
		for p in v:
			pts.append([p.x, p.y])
		return {"@": "pv2", "p": pts}
	if v is Dictionary:
		var simple := true
		for k in v:
			if not (k is String):
				simple = false
				break
		if simple:
			var out := {}
			for k in v:
				out[k] = _enc(v[k])
			return out
		var pairs: Array = []
		for k in v:
			pairs.append([_enc(k), _enc(v[k])])
		return {"@": "d", "p": pairs}
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(_enc(x))
		return out
	return v


## Обратная распаковка (см. _enc).
static func _dec(v: Variant) -> Variant:
	if v is Dictionary:
		match String(v.get("@", "")):
			"v2":
				return Vector2(float(v.get("x", 0.0)), float(v.get("y", 0.0)))
			"v2i":
				return Vector2i(int(v.get("x", 0)), int(v.get("y", 0)))
			"pv2":
				var arr := PackedVector2Array()
				for pt in v.get("p", []):
					arr.append(Vector2(float(pt[0]), float(pt[1])))
				return arr
			"d":
				var out := {}
				for pair in v.get("p", []):
					out[_dec(pair[0])] = _dec(pair[1])
				return out
		var out := {}
		for k in v:
			out[k] = _dec(v[k])
		return out
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(_dec(x))
		return out
	return v


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
