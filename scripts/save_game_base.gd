# Часть: сейв — константы формата, миграции и кодек (enc/dec Vector2i/Variant).
# Структура v1.62.0: бывший save_game.gd (1119 строк, статический класс)
# разрезан на extends-цепочку (save_game_base -> save_game_write -> save_game.gd) —
# это один класс, внешние вызовы SaveGame.* идут через корень save_game.gd.
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


## Пошаговая миграция сейва: from-1 → to. Возвращает мигрированный словарь
## или {} (миграция невозможна). v1→v2: города НПС добирают rel/standing
## (дефолты подставит npc_cities.load_block), в мир — метка формата.
## v1.55 «Сейвы — не мина»: каждое будущее изменение формата добавляет

static func _migrate_save(data: Dictionary, to: int) -> Dictionary:
	match to:
		2:
			if not data.has("npc_cities"):
				return data   # старый сейв без городов НПС — совместимо
			var nc: Variant = data.get("npc_cities", {})
			if not (nc is Dictionary) or (nc as Dictionary).is_empty():
				return data
			for poi_id in (nc as Dictionary):
				var blk: Variant = (nc as Dictionary)[poi_id]
				if blk is Dictionary and not (blk as Dictionary).has("rel"):
					(blk as Dictionary)["rel"] = 0
					(blk as Dictionary)["standing"] = 0.0
			return data
		3:
			# v2→v3: у города игрока появилось богатство региона — дефолт
			var city: Variant = data.get("city", {})
			if city is Dictionary:
				var cb: Dictionary = city.get("city", city)
				if cb is Dictionary and not (cb as Dictionary).has("res_region"):
					(cb as Dictionary)["res_region"] = "copper"
			return data
	return {}

const FORMAT_VERSION := 3   # v3 (v1.56): у города игрока — богатство региона

const CITY_CFG_PATH := "res://data/city.json"
const CITY_MAP_SCRIPT := "res://scripts/city_map.gd"
const CITY_SIM_SCRIPT := "res://scripts/city_sim.gd"
const WORLD_CFG_PATH := "res://data/world.json"
const WORLD_MAP_SCRIPT := "res://scripts/world_map.gd"
const WORLD_SIM_SCRIPT := "res://scripts/world_sim.gd"

const WATER_KIND_NAMES := {".": "", "l": "lake", "r": "river", "s": "swamp", "e": "sea"}

const REGION_CHARS := {"snow": "a", "volcanic": "b", "desert": "c", "dead": "d"}
const REGION_IDS := {"a": "snow", "b": "volcanic", "c": "desert", "d": "dead"}

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
