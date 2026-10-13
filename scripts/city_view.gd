extends Node2D
## Отрисовка города (M2): тайлы ландшафта, аномалия, здания/стройплощадки,
## жители, призрак стройки. Цветные примитивы — пиксель-арт в M8.

var map = null
var sim = null
var colors: Dictionary = {}
var build_mode := ""            # выбранный тип здания (призрак под мышью)
var enchant_mode := ""          # выбранное зачарование (подсветка здания)
var enchant_colors: Dictionary = {}

var _prof_colors: Dictionary = {}
var _bld_colors: Dictionary = {}
var city = null                 # сцена города — для проверки цели зачарования (неглубокая ссылка)


func setup(city_map, city_sim, city_cfg: Dictionary) -> void:
	map = city_map
	sim = city_sim
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		colors[key] = Color(String(c[key]))
	for prof in city_cfg["professions"]:
		_prof_colors[String(prof["id"])] = Color(String(prof["color"]))
	for b in city_cfg["buildings"]:
		_bld_colors[String(b["id"])] = Color(String(b["color"]))
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	_draw_terrain()
	_draw_anomaly()
	_draw_buildings()
	_draw_residents()
	_draw_ghost()


func _draw_terrain() -> void:
	var grass: Color = colors["grass"]
	var grass_alt: Color = colors["grass_alt"]
	for y in map.h:
		for x in map.w:
			var tile: int = map.grid[y][x]
			var rect := Rect2(x * map.ts, y * map.ts, map.ts, map.ts)
			match tile:
				map.TILE_GRASS:
					draw_rect(rect, grass if (x + y) % 2 == 0 else grass_alt)
				map.TILE_WATER:
					draw_rect(rect, colors["water"])
				map.TILE_ROCK:
					draw_rect(rect, colors["rock"])
					draw_circle(_center(x, y), map.ts * 0.3, colors["rock"].lightened(0.15))
				map.TILE_TREE:
					draw_rect(rect, grass if (x + y) % 2 == 0 else grass_alt)
					draw_circle(_center(x, y) + Vector2(0, 3), map.ts * 0.38, colors["tree"])
					draw_circle(_center(x, y) + Vector2(-3, -1), map.ts * 0.18, colors["tree"].lightened(0.12))


func _draw_anomaly() -> void:
	var c: Color = colors["anomaly"]
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 300.0)
	var center: Vector2 = map.tile_center_px(map.anomaly_tile)
	draw_circle(center, map.ts * 0.55 * pulse, Color(c.r, c.g, c.b, 0.35))
	draw_circle(center, map.ts * 0.32, c)
	draw_circle(center, map.ts * 0.14, c.lightened(0.4))


func _draw_buildings() -> void:
	for b in sim.buildings:
		var rect := Rect2(Vector2(b["tile"]) * map.ts, Vector2(map.ts, map.ts))
		var col: Color = _bld_colors.get(String(b["type"]), Color(0.91, 0.85, 0.62))
		if not b["done"]:
			# стройплощадка: каркас и полоса прогресса
			draw_rect(rect.grow(-3), Color(col.r, col.g, col.b, 0.25))
			draw_rect(rect.grow(-3), col.darkened(0.2), false, 2.0)
			var work: float = _build_work(String(b["type"]))
			var frac := clampf(float(b["progress"]) / work, 0.0, 1.0) if work > 0.0 else 0.0
			draw_rect(Rect2(rect.position + Vector2(4, map.ts - 9), Vector2((map.ts - 8) * frac, 5)), Color("#ffe082"))
		elif String(b["type"]) == "wall":
			draw_rect(rect, col.darkened(0.25))
			draw_rect(rect.grow(-2), col, false, 2.0)
		else:
			draw_rect(rect, col)
			draw_rect(rect.grow(-4), col.darkened(0.25))
			# точка-работник: занятое здание подсвечено
			if int(b["worker"]) > 0:
				draw_circle(rect.get_center(), 3.0, Color(1, 1, 1, 0.85))
		# зачарование: рамка цветом эффекта (M3)
		if String(b.get("enchant", "")) != "":
			var ecol: Color = enchant_colors.get(String(b["enchant"]), Color(0.8, 0.8, 1.0))
			draw_rect(rect.grow(-1), ecol, false, 2.0)
			draw_circle(rect.position + Vector2(5, 5), 3.0, ecol)
		# дикая вспышка: здание оглушено
		if float(b.get("stun_left", 0.0)) > 0.0:
			draw_rect(rect, Color(0.1, 0.05, 0.15, 0.55))
			var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
			draw_arc(rect.get_center(), map.ts * 0.4, 0.0, TAU, 20,
					Color(0.9, 0.4, 1.0, 0.4 + 0.4 * flash), 2.0)


func _draw_residents() -> void:
	for r in sim.residents:
		var pos: Vector2 = r["pos"]
		var col: Color = _prof_colors.get(String(r["prof"]), Color.WHITE)
		var child := String(r["prof"]) == ""
		var radius := 4.0 if child else 6.0
		var ail := String(r.get("ail", ""))
		if ail == "sick":
			col = Color("#9ccc65").darkened(0.25)
		elif ail == "wounded":
			col = col.lerp(Color("#c62828"), 0.55)
		var sleeping: bool = r["state"] == "sleep" or r["state"] == "rest"
		draw_circle(pos + Vector2(1, 2), radius, Color(0, 0, 0, 0.3))
		draw_circle(pos, radius, col.darkened(0.35) if sleeping else col)
		draw_circle(pos + Vector2(-1.5, -1.5), radius * 0.33, Color(1, 1, 1, 0.5))


func _draw_ghost() -> void:
	if enchant_mode != "":
		# режим зачарования: подсветка тайла под мышью
		var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if not map.in_bounds(tile):
			return
		var col := Color(0.7, 0.5, 1.0, 0.45)
		if city != null and not city.enchant_target_valid(tile):
			col = Color(1.0, 0.3, 0.3, 0.4)
		draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts)), col)
		return
	if build_mode == "":
		return
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	var ok: bool = sim.is_buildable_tile(tile) and sim.can_afford(_cost_of(build_mode))
	var col := Color(0.5, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts)), col)


func _center(x: int, y: int) -> Vector2:
	return Vector2(x * map.ts + map.ts / 2.0, y * map.ts + map.ts / 2.0)


func _build_work(type_id: String) -> float:
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			return float(d["build_work"])
	return 1.0


func _cost_of(type_id: String) -> Dictionary:
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			return d["cost"]
	return {}
