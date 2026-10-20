extends RefCounted
## Грандиозные создания карты мира (M14-E, issue #3 T19): хранитель леса,
## пепельный титан, дух-мамонт. Чистая логика без сцены — headless-тесты.
## Три роли (по issue):
##  — своя задача: медленно бродит к тайлам «своего» биома;
##  — помогает: хранитель усмиряет гнев леса (в городе), титан сокрушает
##    ближайшую тьму (если герой чист от порчи), мамонт отдаёт редкий дроп;
##  — атакует: провокация (E без дара, высокий гнев леса, высокая порча) —
##    преследует героя; настиг — отбрасывает (сцена гасит маршрут).
## Живёт в world_sim (сохраняется в сейве мира), рисует world_view.

const GIANTS_CFG_PATH := "res://data/giants.json"

var cfg: Dictionary = {}
var map = null
var giants: Array = []     # {id, def, px, tx, mood: neutral|friendly|angered, days, wait}
var _rng := RandomNumberGenerator.new()


func setup(world_map, giants_cfg: Dictionary, seed_value := -1) -> void:
	map = world_map
	cfg = giants_cfg
	giants = []
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	var scfg: Dictionary = cfg.get("spawn", {})
	var defs: Array = cfg.get("giants", [])
	var guard := 0
	while giants.size() < mini(int(scfg.get("count", 3)), defs.size()) and guard < 500:
		guard += 1
		var def: Dictionary = defs[giants.size()]
		var t := _spawn_tile(int(scfg.get("min_dist", 14)), int(scfg.get("max_dist", 30)))
		if t == Vector2i(-1, -1):
			continue
		giants.append({
			"id": String(def["id"]), "def": def,
			"px": map.tile_center_px(t), "tx": Vector2.ZERO,
			"mood": "neutral", "days": 0.0, "wait": _rng.randf_range(1.0, 4.0),
		})


func _spawn_tile(dmin: int, dmax: int) -> Vector2i:
	for attempt in 40:
		var d := _rng.randi_range(dmin, dmax)
		var t: Vector2i = map.city_tile + Vector2i(_rng.randi_range(-d, d), _rng.randi_range(-d, d))
		if not map.in_bounds(t) or not map.is_walkable(t):
			continue
		if not map.is_explored(t) and _rng.randf() < 0.5:
			continue   # чаще на открытой земле, но не обязательно
		if not map.poi_at(t).is_empty():
			continue   # не ломает существующие POI
		return t
	return Vector2i(-1, -1)


func species_def(id: String) -> Dictionary:
	for d in cfg.get("giants", []):
		if String(d["id"]) == id:
			return d
	return {}


## Ближайший гигант к точке ({} — далеко).
func giant_at(hero_px: Vector2, max_dist := -1.0) -> Dictionary:
	var limit := float(cfg.get("interact_dist_px", 56.0)) if max_dist < 0.0 else max_dist
	var best: Dictionary = {}
	var best_d := limit
	for g in giants:
		var d: float = (g["px"] as Vector2).distance_to(hero_px)
		if d < best_d:
			best_d = d
			best = g
	return best


## Тик мира: гиганты бродят к своим биомам; разгневанный преследует героя
## и при контакте «топает» (сцена отбрасывает героя). Возвращает события.
func update(delta: float, hero_px: Vector2) -> Array:
	var events: Array = []
	var chase := float(cfg.get("chase_speed", 88.0))
	var contact := float(cfg.get("contact_px", 28.0))
	for g in giants:
		if g["mood"] == "angered":
			var to_hero: Vector2 = hero_px - (g["px"] as Vector2)
			if to_hero.length() <= contact:
				events.append({"type": "stomp", "giant": g})
				g["mood"] = "neutral"
				g["days"] = 0.0
				g["wait"] = 4.0
			else:
				g["px"] = (g["px"] as Vector2) + to_hero.normalized() * chase * delta
			continue
		# своя задача: путь к тайлам домашнего биома
		g["wait"] = float(g["wait"]) - delta
		if float(g["wait"]) <= 0.0 or (g["tx"] as Vector2) == Vector2.ZERO:
			g["tx"] = _wander_target(g)
			g["wait"] = _rng.randf_range(5.0, 11.0)
		var to: Vector2 = (g["tx"] as Vector2) - (g["px"] as Vector2)
		if to.length() > 6.0:
			g["px"] = (g["px"] as Vector2) + to.normalized() * float(g["def"].get("speed", 20.0)) * delta
	return events


## Цель прогулки: тайл домашнего биома неподалёку (лес — хранитель и т.д.).
func _wander_target(g: Dictionary) -> Vector2:
	var biome_name := String(g["def"].get("home_biome", ""))
	var here: Vector2i = map.tile_of_px(g["px"])
	for attempt in 30:
		var t: Vector2i = here + Vector2i(_rng.randi_range(-8, 8), _rng.randi_range(-8, 8))
		if not map.in_bounds(t) or not map.is_walkable(t):
			continue
		if biome_name != "" and _biome_of(t) != biome_name and attempt < 20:
			continue
		return map.tile_center_px(t)
	return g["px"]


func _biome_of(tile: Vector2i) -> String:
	match int(map.grid[tile.y][tile.x]):
		map.TILE_PLAINS: return "plains"
		map.TILE_WATER: return "water"
		map.TILE_FOREST: return "forest"
		map.TILE_HILL: return "hills"
		map.TILE_WASTE: return "waste"
		map.TILE_ROAD: return "road"
	return ""


## Дни мира текут — гнев и дружба остывают.
func tick_days(n: int) -> void:
	for g in giants:
		if float(g["days"]) > 0.0:
			g["days"] = maxf(0.0, float(g["days"]) - float(n))
			if float(g["days"]) <= 0.0 and String(g["mood"]) == "friendly":
				g["mood"] = "neutral"


## E у гиганта. ctx: {has_gift, provoked, forest_anger, pollution}.
## Дар сильнее гнева: поднести мясо можно даже разъярённому — он примет.
## Возвращает план для сцены: {type: gift|help|angered|nothing, giant, help?}.
func interact(hero_px: Vector2, ctx: Dictionary) -> Dictionary:
	var g := giant_at(hero_px)
	if g.is_empty():
		return {}
	var id := String(g["id"])
	var anger: Dictionary = cfg.get("anger", {})
	# дар: главный мирный ход (усмиряет даже разгневанного)
	if bool(ctx.get("has_gift", false)):
		g["mood"] = "friendly"
		g["days"] = float(cfg.get("gift_days", 5))
		return {"type": "gift", "giant": g, "help": _help_plan(g)}
	var angry_now := false
	match id:
		"forest_warden":
			angry_now = float(ctx.get("forest_anger", 0.0)) >= float(anger.get("forest_anger_min", 60.0))
		"ash_titan":
			angry_now = float(ctx.get("pollution", 0.0)) >= float(anger.get("pollution_min", 50.0))
		"mammoth_spirit":
			angry_now = bool(ctx.get("provoked", false))
	if angry_now and String(g["mood"]) != "friendly":
		g["mood"] = "angered"
		return {"type": "angered", "giant": g}
	# помогает сам, если герой чист от порчи (титан — по issue)
	if id == "ash_titan" and float(ctx.get("pollution", 100.0)) < float(anger.get("pollution_help_max", 30.0)):
		return {"type": "help", "giant": g, "help": _help_plan(g)}
	return {"type": "nothing", "giant": g}


## План помощи по виду (сцена исполняет: город/мир/рюкзак).
func _help_plan(g: Dictionary) -> Dictionary:
	var def: Dictionary = g["def"]
	match String(def.get("role_help", "")):
		"calm_forest":
			return {"type": "calm_forest"}
		"smite_dark":
			return {"type": "smite_dark"}
		"gift_drop":
			var drops: Array = []
			for d in def.get("drop", []):
				var n := _rng.randi_range(int((d["count"] as Array)[0]), int((d["count"] as Array)[1]))
				if n > 0:
					drops.append({"id": String(d["id"]), "count": n})
			return {"type": "gift_drop", "drops": drops}
	return {}
