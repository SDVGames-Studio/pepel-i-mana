extends RefCounted
## Мирная фауна и хищники карты мира (M14-C, issue #3 T01). Чистая логика
## без сцены — headless-тесты. Виды по биомам из data/fauna.json:
## мирные убегают от героя (охота по E), волки охотятся на мирных,
## рыба живёт на воде. Дроп — стандартные предметы loot.json.
## Отрисовка — world_view.gd (герой видит животных рядом с собой).

var cfg: Dictionary = {}
var map = null
var fauna: Array = []      # {id, kind, px: Vector2, tx: Vector2, wait: float}
var _rng := RandomNumberGenerator.new()
var _next_id := 1


func setup(world_map, fauna_cfg: Dictionary, seed_value := -1) -> void:
	map = world_map
	cfg = fauna_cfg
	fauna = []
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func species_def(kind: String) -> Dictionary:
	for s in cfg.get("species", []):
		if String(s["id"]) == kind:
			return s
	return {}


## Биом тайла в терминах фауны: равнина/лес/холмы/пустошь/вода/дорога.
func biome_of(tile: Vector2i) -> String:
	if map == null or not map.in_bounds(tile):
		return ""
	match int(map.grid[tile.y][tile.x]):
		map.TILE_PLAINS: return "plains"
		map.TILE_WATER: return "water"
		map.TILE_FOREST: return "forest"
		map.TILE_HILL: return "hills"
		map.TILE_WASTE: return "waste"
		map.TILE_ROAD: return "road"
	return ""


## Попытка заспавнить зверя возле открытого героем тайла. Возвращает вид или "".
func try_spawn_near(hero_tile: Vector2i) -> String:
	var scfg: Dictionary = cfg.get("spawn", {})
	if fauna.size() >= int(scfg.get("max_active", 12)):
		return ""
	if _rng.randf() > float(scfg.get("chance_per_reveal", 0.1)):
		return ""
	var dmin := int(scfg.get("min_dist", 2))
	var dmax := int(scfg.get("max_dist", 6))
	var candidates: Array = []
	for attempt in 24:
		var d := _rng.randi_range(dmin, dmax)
		var t := hero_tile + Vector2i(_rng.randi_range(-d, d), _rng.randi_range(-d, d))
		if not map.in_bounds(t):
			continue
		if not map.is_explored(t):
			continue
		var biome := biome_of(t)
		if biome == "":
			continue
		var kinds := _species_for_biome(biome)
		if kinds.is_empty():
			continue
		candidates.append([t, kinds[_rng.randi_range(0, kinds.size() - 1)]])
	if candidates.is_empty():
		return ""
	var pick: Array = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var tile: Vector2i = pick[0]
	var kind: String = pick[1]
	fauna.append({
		"id": _next_id, "kind": kind,
		"px": map.tile_center_px(tile) + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)),
		"tx": Vector2.ZERO, "wait": _rng.randf_range(0.5, 2.5),
	})
	_next_id += 1
	return kind


func _species_for_biome(biome: String) -> Array:
	var out: Array = []
	for s in cfg.get("species", []):
		if biome in (s["biomes"] as Array):
			out.append(String(s["id"]))
	return out


## Тик мира: звери бродят; мирные убегают от героя, волк гонится за ближайшим
## мирным (догнал — жертва исчезает, хищник «сыт» и замирает).
func update(delta: float, hero_px: Vector2) -> void:
	var scfg: Dictionary = cfg.get("spawn", {})
	var despawn := float(scfg.get("despawn_dist", 24.0)) * 32.0
	var flee := float(cfg.get("flee_radius_px", 70.0))
	var gone: Array = []
	for a in fauna:
		var def := species_def(String(a["kind"]))
		if def.is_empty():
			gone.append(a)
			continue
		if a["px"].distance_to(hero_px) > despawn:
			gone.append(a)
			continue
		var speed := float(def.get("speed", 50.0))
		var behavior := String(def.get("behavior", "flee"))
		var to_hero: Vector2 = hero_px - a["px"]
		if behavior == "fish":
			continue   # рыба плавает на месте (плеск — отрисовка)
		if behavior == "flee" and to_hero.length() < flee:
			a["px"] -= to_hero.normalized() * speed * delta
			a["wait"] = 1.0
			continue
		if behavior == "hunt":
			var prey := _nearest_prey(a)
			if not prey.is_empty():
				var to_prey: Vector2 = prey["px"] - a["px"]
				if to_prey.length() > 10.0:
					a["px"] += to_prey.normalized() * speed * delta
				else:
					gone.append(prey)   # волк догнал — зверь исчез
					a["wait"] = 3.0
				continue
		# спокойное блуждание по своим тайлам
		a["wait"] = float(a["wait"]) - delta
		if a["wait"] <= 0.0:
			a["tx"] = _wander_target(a["px"])
			a["wait"] = _rng.randf_range(1.5, 4.0)
		if (a["tx"] as Vector2) != Vector2.ZERO:
			var to: Vector2 = a["tx"] - a["px"]
			if to.length() > 4.0:
				a["px"] += to.normalized() * speed * 0.4 * delta
	for a2 in gone:
		if fauna.has(a2):
			fauna.erase(a2)


func _wander_target(px: Vector2) -> Vector2:
	for attempt in 8:
		var t: Vector2i = map.tile_of_px(px) + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-2, 2))
		if map.in_bounds(t) and (map.is_walkable(t) or biome_of(t) == "water"):
			return map.tile_center_px(t)
	return Vector2.ZERO


func _nearest_prey(wolf: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 140.0
	for a in fauna:
		if a == wolf:
			continue
		var def := species_def(String(a["kind"]))
		if String(def.get("behavior", "")) != "flee":
			continue
		var d: float = (a["px"] as Vector2).distance_to(wolf["px"])
		if d < best_d:
			best_d = d
			best = a
	return best


## Осмотр без вмешательства (для подсказки E): {"kind", "behavior"} или {}.
func interact_check(hero_px: Vector2) -> Dictionary:
	var max_d := float(cfg.get("interact_dist_px", 44.0))
	var best: Dictionary = {}
	var best_d := max_d
	for a in fauna:
		var d: float = (a["px"] as Vector2).distance_to(hero_px)
		if d < best_d:
			best_d = d
			best = a
	if best.is_empty():
		return {}
	var def := species_def(String(best["kind"]))
	return {"kind": String(best["kind"]), "behavior": String(def.get("behavior", "flee"))}


## Охота/рыбалка по E: ближайший зверь в радиусе. Убирает его из мира и
## возвращает {"kind", "drops": [{id, count}]} или {} — рядом никого.
func interact(hero_px: Vector2) -> Dictionary:
	var max_d := float(cfg.get("interact_dist_px", 44.0))
	var best: Dictionary = {}
	var best_d := max_d
	for a in fauna:
		var d: float = (a["px"] as Vector2).distance_to(hero_px)
		if d < best_d:
			best_d = d
			best = a
	if best.is_empty():
		return {}
	var kind := String(best["kind"])
	var def := species_def(kind)
	var drops: Array = []
	for d in def.get("drop", []):
		var n := _rng.randi_range(int((d["count"] as Array)[0]), int((d["count"] as Array)[1]))
		if n > 0:
			drops.append({"id": String(d["id"]), "count": n})
	fauna.erase(best)
	return {"kind": kind, "drops": drops}
