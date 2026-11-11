# Часть: сейв — СОХРАНЕНИЕ: точка входа save_game/save_snapshot, блоки города,
# мира, навыков, жителей и легенд, сериализация сеток. Один класс.
extends "res://scripts/save_game_base.gd"

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
		# города НПС (v1.41, «Мир v2» этап 3): каждое поселение — целиком
		"npc_cities": _enc(_npc_block(game)),
		"world": _enc(_world_block(game.world_map, game.world_sim)),
		"codex": game.codex,
		"stats": game.stats,
	}


## Города НПС одним блоком ({} — модуля нет, старая сессия/FakeGame).
static func _npc_block(game) -> Dictionary:
	var npc = game.get("npc_cities")
	return npc.save_block() if npc != null else {}


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


static func _city_block(sim, include_map := true) -> Dictionary:
	# v1.43 (большие карты): NPC города хранят только сид — карта
	# детерминированно регенерируется при загрузке (иначе сейв ×20 городов
	# × 110к тайлов раздувался до десятков МБ). Город игрока хранит всё:
	# его правки (дороги, выработка, пни) — часть игры.
	var m = sim.map
	var out := {}
	if include_map:
		out["map"] = {
			"w": int(m.w), "h": int(m.h), "ts": int(m.ts),
			"res_region": String(m.get("region_resource") if "region_resource" in m else "copper"),
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
			"fords": _tile_keys(m.fords),
			"height": _tile_vals(m.height),
			"stairs": _tile_keys(m.stairs),
			"ruin_loot": _tile_keys(m.ruin_loot)
		}
	out["residents"] = _residents_save(sim)
	out["sim"] = _city_sim_block(sim)
	out["hive"] = _hive_block(sim)
	return out


static func _hive_block(sim) -> Dictionary:
	return _enc(sim.hive if sim.get("hive") != null else {})


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
			"river": _tile_keys(wmap.river),
			"water_kind": _kind_rows(wmap),
			"region": _region_rows(wmap),
			"sea_mode": String(wmap.sea_mode),
			"epicenter": (wmap.epicenter if "epicenter" in wmap else {}),
			"height": _height_rows(wmap),
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


## v1.43: регион/тип воды — строками по ряду (плотные слои ×5 карты:
## списки [x,y,v] раздували сейв до мегабайт). Читатель терпит и старый

static func _kind_rows(wmap) -> Array:
	var rows: Array = []
	for y in wmap.h:
		var row := ""
		for x in wmap.w:
			var kind := String(wmap.water_kind.get(Vector2i(x, y), ""))
			row += String({".": ".", "lake": "l", "river": "r", "swamp": "s",
					"sea": "e"}.get(kind, "."))
		rows.append(row)
	return rows



static func _region_rows(wmap) -> Array:
	var rows: Array = []
	for y in wmap.h:
		var row := ""
		for x in wmap.w:
			var rid := String(wmap.region.get(Vector2i(x, y), ""))
			row += String(REGION_CHARS.get(rid, "."))
		rows.append(row)
	return rows



static func _height_rows(wmap) -> Array:
	var rows: Array = []
	for y in wmap.h:
		var row: Array = []
		row.resize(wmap.w)
		for x in wmap.w:
			row[x] = roundf(float(wmap.height[y][x]) * 1000.0) / 1000.0
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

