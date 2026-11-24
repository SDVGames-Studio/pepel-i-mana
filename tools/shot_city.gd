extends SceneTree
## Снимок города для визуальной проверки (M11). Запуск С ГРАФИКОЙ (не headless):
## godot --path . --script res://tools/shot_city.gd
## Собирает демо-город (дома, лесопилка, каменоломня, кладбище, пни, саженцы,
## духи), ждёт кадры, сохраняет tools/shot_city.png и выходит.

var _frames := 0
var _season := ""
var _game: Node = null
var _city: Node = null
var _weather_override := ""   # погода перед кадром: дневной ролл её перебивает


func _initialize() -> void:
	# автозагрузки: в оконном --script-режиме Godot создаёт их сам; если нет — вешаем вручную
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		game.name = "Game"
		root.add_child(game)
	var loc: Node = root.get_node_or_null("Loc")
	if loc == null:
		loc = load("res://scripts/loc.gd").new()
		loc.name = "Loc"
		root.add_child(loc)
	game.test_mode = true
	game.new_city()
	var city: Node = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	_call_deferred(_decorate.bind(city, game))
	process_frame.connect(_on_frame)


func _call_deferred(cb: Callable) -> void:
	cb.call_deferred()


func _decorate(city: Node, game: Node) -> void:
	_game = game
	_city = city
	var names := []
	for ch in city.get_children():
		names.append(String(ch.name))
	print("diag-layers: ", ", ".join(names))
	if OS.get_environment("SHOT_SEED") != "":
		seed(int(OS.get_environment("SHOT_SEED")))
	var sim = game.city_sim
	var map = sim.map
	var cfg: Dictionary = sim.cfg
	if OS.get_environment("SHOT_WATER") != "":
		# дамп компонентов воды: позиция/тип/размер — сверка с белыми пятнами
		var seen := {}
		for y in map.h:
			for x in map.w:
				var t := Vector2i(x, y)
				if map.grid[t.y][t.x] != map.TILE_WATER or seen.has(t):
					continue
				var comp: Array = [t]
				seen[t] = true
				var mn: Vector2i = t
				var mx: Vector2i = t
				var qi := 0
				while qi < comp.size():
					var c: Vector2i = comp[qi]
					qi += 1
					mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
					mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var n: Vector2i = c + d
						if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER and not seen.has(n):
							seen[n] = true
							comp.append(n)
				print("water: %s tiles=%d bbox=%s..%s" % [map.water_kind_at(t), comp.size(), mn, mx])
	# дом/постройки вокруг центра: дом x3, лесопилка у дерева, каменоломня у скалы,
	# мастерская, таверна, кладбище
	var spots := {
		"house": [Vector2i(-3, -2), Vector2i(-5, 1), Vector2i(-2, 3)],
		"farm": [Vector2i(3, -2)],
		"tavern": [Vector2i(2, 2)],
		"cemetery": [Vector2i(-6, -3)],
	}
	for type_id in spots:
		for off: Vector2i in spots[type_id]:
			var t: Vector2i = map.spawn_tile + off
			var ok: bool = sim.is_buildable_tile(t, type_id) and sim.placement_block(type_id, t) == ""
			var done: bool = ok and sim.place_building(type_id, t)
			print("shot: %s @ %s buildable=%s placed=%s wood=%d" % [type_id, t, ok, done, int(sim.res["wood"])])
	print("shot: test wood after setup = %d" % int(sim.res["wood"]))
	# добытчики: лесопилка у ближайшего дерева, каменоломня у гряды
	var tree_tile := Vector2i(-1, -1)
	var rock_tile := Vector2i(-1, -1)
	for y in map.h:
		for x in map.w:
			if tree_tile == Vector2i(-1, -1) and map.grid[y][x] == map.TILE_TREE \
					and Vector2(x, y).distance_to(Vector2(map.spawn_tile)) < 14.0:
				tree_tile = Vector2i(x, y)
			if rock_tile == Vector2i(-1, -1) and map.grid[y][x] == map.TILE_ROCK \
					and Vector2(x, y).distance_to(Vector2(map.spawn_tile)) < 18.0:
				rock_tile = Vector2i(x, y)
	for pair in [["sawmill", tree_tile], ["quarry", rock_tile], ["workshop", null]]:
		var type_id: String = pair[0]
		var anchor: Vector2i = pair[1] if pair[1] != null else map.spawn_tile + Vector2i(4, 3)
		if anchor == Vector2i(-1, -1):
			continue
		for dy in range(-2, 3):
			var placed := false
			for dx in range(-2, 3):
				var t2: Vector2i = anchor + Vector2i(dx, dy)
				if sim.is_buildable_tile(t2, type_id) and sim.placement_block(type_id, t2) == "":
					sim.place_building(type_id, t2)
					placed = true
					break
			if placed:
				break
	# мгновенно «достроить» и дать кучи, пни, саженцы
	var ids := [3, 4, 5]
	for b in sim.buildings:
		b["done"] = true
		b["progress"] = 0.0
		if String(b["type"]) in ["sawmill", "quarry"]:
			b["pile"] = {"wood" if String(b["type"]) == "sawmill" else "stone": 12.0}
	for b2 in sim.buildings:
		if String(b2["type"]) == "cemetery":
			b2["hp"] = 25.0
	sim.map.stumps[map.spawn_tile + Vector2i(5, -1)] = true
	sim.map.stumps[map.spawn_tile + Vector2i(6, -2)] = true	# v2.4: показательные поваленные брёвна пакета B (SHOT_LOGS=1)
	if OS.get_environment("SHOT_LOGS") != "":
		for i in 3:
			var lt: Vector2i = map.spawn_tile + Vector2i(6 + i, 1 + (i % 2))
			map.logs[lt] = {"size": 1 + i % 3}
	# v2.4: кадр в чаще (SHOT_FOREST=1): герой телепортируется к густым
	# деревьям — новые деревья пакета B в кадре, рядом пень и бревно
	if OS.get_environment("SHOT_FOREST") != "":
		var best_t: Vector2i = map.spawn_tile
		var best_n := -1
		for fy in range(2, map.h - 2):
			for fx in range(2, map.w - 2):
				var t3 := Vector2i(fx, fy)
				if map.grid[fy][fx] != map.TILE_TREE:
					continue
				var n3 := 0
				for d3 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
						Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
					if map.in_bounds(t3 + d3) and map.grid[t3.y + d3.y][t3.x + d3.x] == map.TILE_TREE:
						n3 += 1
				if n3 > best_n:
					best_n = n3
					best_t = t3
		_city.hero.position = map.tile_center_px(best_t + Vector2i(1, 1))
		sim.map.stumps[best_t + Vector2i(2, 0)] = true
		sim.map.logs[best_t + Vector2i(2, 1)] = {"size": 2}
	# v2.4: звери у площади для кадра (SHOT_ANIMALS=1): медведь, лось,
	# волк, лиса, заяц — виды и новые кадры фауны B
	if OS.get_environment("SHOT_ANIMALS") != "":
		var kinds := ["bear", "elk", "wolf", "fox", "hare"]
		for i2 in kinds.size():
			var at: Vector2i = map.spawn_tile + Vector2i(-7 + i2 * 2, -5)
			if not map.is_walkable(at):
				at = map.spawn_tile + Vector2i(-7 + i2 * 2, -4)
			sim.animals.append({
				"id": 500 + i2, "kind": kinds[i2],
				"pos": map.tile_center_px(at),
				"target": Vector2i(-1, -1),
				"path": PackedVector2Array(), "idle": 2.0 + float(i2),
			})
	sim.map.saplings[map.spawn_tile + Vector2i(-4, 2)] = {"t": 30.0, "grow_days": 1.2}
	sim.map.saplings[map.spawn_tile + Vector2i(-4, 3)] = {"t": 100.0, "grow_days": 1.2}
	# некромантия раскрыта: тьма и скелеты у кладбища
	sim.necro_dark = 0.55
	sim.necro_known = true
	sim.necro_army = 5
	# SHOT_SEASON=spring|summer|autumn|winter: принудительный сезон
	# (v1.76, проверка сезонных тайлов; v1.78.6 — все 4 сезона)
	if OS.get_environment("SHOT_SEASON") != "":
		# день считается из времени (city_sim_tick) — двигаем ВРЕМЯ
		var wcfg: Dictionary = _city.sim._weather_cfg()
		var seasons: Array = wcfg.get("seasons", ["spring", "summer", "autumn", "winter"])
		var sidx := maxi(0, seasons.find(OS.get_environment("SHOT_SEASON")))
		# середина ДНЯ середины сезона (ночь ничего не показывает;
		# фаза суток 0.3 = полдень, ночь при t >= 1 - night_fraction)
		_city.sim.time = (float(sidx) * float(wcfg.get("season_days", 12)) + 1.3) \
				* float(_city.sim.cfg["day_length"])
		print("shot: season=", sim.season(), " day=", sim.day)
	# SHOT_DEMO=1: демо-застройка — все типы зданий и профессий у площади
	# (v1.73, оценка арта домов)
	if OS.get_environment("SHOT_DEMO") == "1":
		var dres: Vector3i = sim.demo_populate()
		print("shot: demo buildings +%d (no room %d), residents +%d"
				% [int(dres.x), int(dres.y), int(dres.z)])
	# SHOT_RAID=<тип1,тип2,...>: враги у площади (v1.74, оценка арта)
	if OS.get_environment("SHOT_RAID") != "":
		if sim._enemies_cfg.is_empty():
			var ed: Variant = sim._read_json_file("res://data/enemies.json")
			sim._enemies_cfg = ed if ed is Array else []
		var kinds := OS.get_environment("SHOT_RAID").split(",")
		var spawned := 0
		var defs := {}
		for d in sim._enemies_cfg:
			defs[String(d["id"])] = d
		for k in kinds:
			var kt := String(k).strip_edges()
			if kt == "" or not defs.has(kt):
				continue
			var def: Dictionary = defs[kt]
			var ring := 4 + (spawned / 8) * 4      # кольца по 8 врагов
			var ang := float(spawned % 8) * TAU / 8.0 + float(spawned / 8) * 0.35
			var tile: Vector2i = map.spawn_tile + Vector2i(
					int(round(cos(ang) * ring)), int(round(sin(ang) * ring)))
			sim.raiders.append({
				"id": sim._next_id, "type": kt, "p": def,
				"hp": int(def["hp"]), "max_hp": int(def["hp"]),
				"pos": map.tile_center_px(tile),
				"target": Vector2i(-1, -1), "path": PackedVector2Array(),
				"atk_cd": 0.0, "mode": "advance",
			})
			sim._next_id += 1
			spawned += 1
		sim.raid_active = true
		print("shot: raid spawned %d/%d" % [spawned, kinds.size()])
	var cem: Dictionary = sim._cemetery()
	if not cem.is_empty():
		var c: Vector2i = cem["tile"]
		sim.necro_ghosts = [map.tile_center_px(c + Vector2i(1, 0)), map.tile_center_px(c + Vector2i(-1, 1))]
	# пара духов леса у лесопилки
	var spirit_def: Dictionary = {}
	for d: Dictionary in sim._enemies_cfg:
		if String(d["id"]) == "forest_spirit":
			spirit_def = d
	if spirit_def.is_empty():
		var ed: Variant = sim._read_json_file("res://data/enemies.json")
		sim._enemies_cfg = ed if ed is Array else []
		for d2: Dictionary in sim._enemies_cfg:
			if String(d2["id"]) == "forest_spirit":
				spirit_def = d2
	if not spirit_def.is_empty() and tree_tile != Vector2i(-1, -1):
		for i in 2:
			sim.raiders.append({
				"id": 900 + i, "type": "forest_spirit", "p": spirit_def,
				"hp": int(spirit_def["hp"]), "max_hp": int(spirit_def["hp"]),
				"pos": map.tile_center_px(tree_tile + Vector2i(1 + i, 1)),
				"target": Vector2i(-1, -1), "path": PackedVector2Array(),
				"atk_cd": 0.0, "mode": "hunt", "victim_id": -1, "ttl": 999.0,
			})
	sim.terrain_dirty = true
	if OS.get_environment("SHOT_NIGHT") != "":
		sim.time = float(sim.cfg["day_length"]) * 0.93   # ночь: видны скелеты кладбища
	elif OS.get_environment("SHOT_EVENING") != "":
		# вечер (M12): костёр горит, жители в досуге, разговоры-облачка
		sim.time = float(sim.cfg["day_length"]) * 0.65
	elif OS.get_environment("SHOT_CLEAR") != "":
		# v1.29.4: ясное утро — длинные тени деревьев/скал (проверка теней)
		# v1.78.6: время не трогаем, если задан SHOT_SEASON (сезон сильнее)
		_weather_override = "clear"
		if OS.get_environment("SHOT_SEASON") == "":
			sim.time = float(sim.cfg["day_length"]) * 0.18
	if OS.get_environment("SHOT_FOG") != "":
		_weather_override = "fog"
		sim.time = float(sim.cfg["day_length"]) * 0.4
	if OS.get_environment("SHOT_WATER") != "":
		# v1.29.4: камера у ближайшего водоёма — проверка формы воды/кромки
		_teleport_near(func(g: int) -> bool: return g == map.TILE_WATER)
	if OS.get_environment("SHOT_ROCK") != "":
		_teleport_near(func(g: int) -> bool: return g == map.TILE_ROCK or g == map.TILE_ORE)
	if OS.get_environment("SHOT_NOAMBIENT") != "" and _city.get("_ambience") != null:
		_city._ambience.visible = false
	if OS.get_environment("SHOT_NOTERRAIN") != "" and _city.get("_terrain") != null:
		_city._terrain.visible = false
	if OS.get_environment("SHOT_NODARK") != "" and _city.get("_modulate") != null:
		_city._modulate.color = Color.WHITE
	if OS.get_environment("SHOT_NOVIEW") != "" and _city.get("view") != null:
		_city.view.visible = false
	print("shot: город украшен")


## Телепорт героя к ближайшему тайлу-предикату (вода/скала — в кадр).
func _teleport_near(pred: Callable) -> void:
	var sim = _game.city_sim
	var map = sim.map
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for y2 in map.h:
		for x2 in map.w:
			if pred.call(int(map.grid[y2][x2])):
				var d: float = Vector2(x2, y2).distance_squared_to(Vector2(map.spawn_tile))
				if d < bd:
					bd = d
					best = Vector2i(x2, y2)
	if best != Vector2i(-1, -1):
		(_city as Node).hero.position = map.tile_center_px(best + Vector2i(3, 2))


func _on_frame() -> void:
	_frames += 1
	# v1.29.4: дневной ролл погоды на первых тиках перебивает заданную —
	# возвращаем её прямо перед снимком
	if _frames == 40 and _weather_override != "" and _game != null:
		_game.city_sim.weather = _weather_override
	# SHOT_RESIDENT=1: открыть летопись жителя (v1.89, оценка панели)
	if _frames == 40 and OS.get_environment("SHOT_RESIDENT") == "1" and _city != null:
		for c in _city.get_children():
			if c is CanvasLayer and c.has_method("toggle_residents"):
				c.toggle_residents()
				var rs: Array = _city.sim.residents
				if not rs.is_empty():
					c.open_resident(int(rs[1].get("uid", -1)))
				print("shot: летопись жителя открыта")
				break
	if _frames < 45:
		return
	if _frames == 44 and OS.get_environment("SHOT_SEASON") != "":
		var wcfg: Dictionary = _city.sim._weather_cfg()
		var seasons2: Array = wcfg.get("seasons", ["spring", "summer", "autumn", "winter"])
		var sidx2 := maxi(0, seasons2.find(OS.get_environment("SHOT_SEASON")))
		_city.sim.time = (float(sidx2) * float(wcfg.get("season_days", 12)) + 1.3) \
				* float(_city.sim.cfg["day_length"])
		_season = String(_city.sim.season())
		print("frame44: day=", _city.sim.day, " season=", _season, " time/dl=", _city.sim.time / float(_city.sim.cfg["day_length"]))
	if _frames == 45 and OS.get_environment("SHOT_SEASON") != "":
		print("frame45: day=", _city.sim.day, " season=", _city.sim.season())
	if OS.get_environment("SHOT_AB") != "":
		# A/B в одном прогоне (v1.21.5): кадр с запечённым ландшафтом,
		# затем та же сцена с прямой отрисовкой тайлов — один мир, одна камера
		if _frames == 45:
			root.get_texture().get_image().save_png("res://tools/shot_ab_baked.png")
			print("shot: A (запечённый) сохранён")
			OS.set_environment("TERRAIN_DIRECT", "1")
			_find_terrain(root).queue_redraw()
			return
		if _frames >= 60:
			root.get_texture().get_image().save_png("res://tools/shot_ab_direct.png")
			print("shot: B (прямой) сохранён")
			quit(0)
		return
	if OS.get_environment("SHOT_SEASON") != "":
		print("frame45: day=", _city.sim.day, " season=", _city.sim.season())
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tools/shot_city.png")
	print("shot: сохранён tools/shot_city.png")
	quit(0)


func _find_terrain(node: Node) -> Node:
	if node.get_script() != null \
			and String((node.get_script() as Script).resource_path).ends_with("city_terrain.gd"):
		return node
	for child in node.get_children():
		var found := _find_terrain(child)
		if found != null:
			return found
	return null
