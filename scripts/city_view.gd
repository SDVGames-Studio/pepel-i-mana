extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Отрисовка города (M2): тайлы ландшафта, аномалия, здания/стройплощадки,
## жители, призрак стройки. Цветные примитивы — пиксель-арт в M8.
## M6: дороги, зоны с прогрессом обустройства, кучи ресурсов у зданий,
## груз носильщика, предпросмотр выделения зоны.

var map = null
var sim = null
var colors: Dictionary = {}
var build_mode := ""            # выбранный тип здания (призрак под мышью)
var enchant_mode := ""          # выбранное зачарование (подсветка здания)
var enchant_colors: Dictionary = {}
var zone_mode := ""             # инструмент зоны (M6): выделение областью
var road_mode := false          # инструмент дороги (M6): рисование мышью
var dragging := false           # ЛКМ зажата — идёт выделение/рисование
var drag_from := Vector2i(-1, -1)
var drag_to := Vector2i(-1, -1)

var _prof_colors: Dictionary = {}
var _prof_sprites: Dictionary = {}
var _bld_colors: Dictionary = {}
var _bld_sprites: Dictionary = {}
var _zone_colors: Dictionary = {}
var city = null                 # сцена города — для проверки цели зачарования (неглубокая ссылка)

# цвета куч по ресурсу (M6)
var _pile_colors := {
	"wood": Color("#8d6e63"), "stone": Color("#9e9e9e"), "food": Color("#8bc34a"),
	"iron": Color("#b0684a"), "metal": Color("#cfd8dc"), "tools": Color("#78909c"),
	"kits": Color("#ffb74d"), "crystal": Color("#b46ee0"),
}
# спрайты куч (M9): мешок/брёвна/камень — по главному ресурсу
const PILE_SPRITES := {
	"wood": "k:75", "stone": "k:102", "food": "k:126", "iron": "k:102",
	"metal": "k:102", "tools": "k:104", "kits": "k:103", "crystal": "k:116",
}


func setup(city_map, city_sim, city_cfg: Dictionary) -> void:
	map = city_map
	sim = city_sim
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		colors[key] = Color(String(c[key]))
	for prof in city_cfg["professions"]:
		_prof_colors[String(prof["id"])] = Color(String(prof["color"]))
		_prof_sprites[String(prof["id"])] = String(prof.get("sprite", ""))
	for b in city_cfg["buildings"]:
		_bld_colors[String(b["id"])] = Color(String(b["color"]))
		_bld_sprites[String(b["id"])] = String(b.get("sprite", ""))
	for t in city_cfg.get("zones", {}).get("types", {}):
		_zone_colors[String(t)] = Color(String(city_cfg["zones"]["types"][t]["color"]))
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	# ландшафт рисует отдельный статический слой city_terrain.gd (M9)
	_draw_zones()
	_draw_roads()
	_draw_anomaly()
	_draw_world_exit()
	_draw_buildings()
	_draw_piles()
	_draw_animals()
	_draw_raiders()
	_draw_residents()
	_draw_ghost()


## Дикие животные (M5.1): цель охотника — спрайт грызуна (M9).
func _draw_animals() -> void:
	for a in sim.animals:
		var pos: Vector2 = a["pos"]
		var phase := float(pos.x * 1.1 + pos.y * 0.7) + Time.get_ticks_msec() / 110.0
		Assets.draw_ref(self, "k:123", pos + Vector2(0, -absf(sin(phase)) * 1.5), 18.0)


## Зоны (M6): заливка по типу, прогресс обустройства в незаполненных клетках.
func _draw_zones() -> void:
	var fill_work: float = float(sim.cfg.get("zones", {}).get("fill_work", 4.0))
	for z in sim.zones:
		var col: Color = _zone_colors.get(String(z["type"]), Color(0.7, 0.7, 0.4))
		for i in (z["cells"] as Array).size():
			var tile: Vector2i = z["cells"][i]
			var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
			var filled: bool = float(z["progress"][i]) >= fill_work
			draw_rect(rect, Color(col.r, col.g, col.b, 0.42 if filled else 0.18))
			if filled:
				draw_rect(rect.grow(-2), col.darkened(0.15), false, 1.5)
				match String(z["type"]):
					"field":
						# борозды поля
						for k: int in 3:
							var y: float = rect.position.y + map.ts * (0.25 + 0.25 * k)
							draw_line(Vector2(rect.position.x + 4, y),
									Vector2(rect.position.x + map.ts - 4, y), col.darkened(0.3), 1.5)
					"pasture":
						draw_circle(rect.position + Vector2(10, 20), 3.0, col.darkened(0.35))
						draw_circle(rect.position + Vector2(22, 12), 3.0, col.darkened(0.35))
					"living":
						# шалаш: треугольник
						var p := rect.position
						draw_colored_polygon(PackedVector2Array([
							Vector2(p.x + 6, p.y + 26), Vector2(p.x + 16, p.y + 8),
							Vector2(p.x + 26, p.y + 26)]), col.darkened(0.3))
			else:
				var frac := clampf(float(z["progress"][i]) / maxf(0.1, fill_work), 0.0, 1.0)
				draw_rect(Rect2(rect.position + Vector2(4, map.ts - 8), Vector2((map.ts - 8) * frac, 4)),
						Color("#ffe082"))


## Дороги (M6): тёплые плитки с камешками.
func _draw_roads() -> void:
	var col: Color = colors.get("road", Color("#6e5f4a"))
	for tile: Vector2i in map.road:
		var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
		draw_rect(rect, col)
		draw_circle(rect.position + Vector2(map.ts * 0.3, map.ts * 0.4), 2.0, col.lightened(0.2))
		draw_circle(rect.position + Vector2(map.ts * 0.65, map.ts * 0.65), 1.6, col.lightened(0.15))


## Кучи ресурсов у зданий (M6): добычу видно глазами — спрайт главного ресурса.
func _draw_piles() -> void:
	for b in sim.buildings:
		if not bool(b["done"]) or not (b as Dictionary).has("pile"):
			continue
		var pile: Dictionary = b["pile"]
		var total := 0.0
		var key := ""
		var best := 0.0
		for k in pile:
			total += float(pile[k])
			if float(pile[k]) > best:
				best = float(pile[k])
				key = String(k)
		if total < 0.5:
			continue
		var corner: Vector2 = Vector2(b["tile"]) * map.ts + Vector2(map.ts * 0.78, map.ts * 0.88)
		var size := 8.0 + minf(10.0, total / 3.0)
		var tint: Color = _pile_colors.get(key, Color(0.8, 0.8, 0.8)).lightened(0.25)
		Assets.draw_ref(self, PILE_SPRITES.get(key, "k:73"), corner, size, false, tint)


func _draw_anomaly() -> void:
	var c: Color = colors["anomaly"]
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 300.0)
	var center: Vector2 = map.tile_center_px(map.anomaly_tile)
	draw_circle(center, map.ts * 0.55 * pulse, Color(c.r, c.g, c.b, 0.35))
	draw_circle(center, map.ts * 0.32, c)
	draw_circle(center, map.ts * 0.14, c.lightened(0.4))


## Выход на карту мира (M8): вся рамка карты — зона перехода (лёгкая зелёная
## полоса по периметру), на западе — каменная арка с яркого свечением и
## стрелкой: главные ворота на запад, видно издалека.
func _draw_world_exit() -> void:
	var ts: float = float(map.ts)
	# рамка-зона перехода по всему периметру
	var band := Color(0.45, 0.9, 0.5, 0.10)
	draw_rect(Rect2(0, 0, map.w * ts, ts), band)
	draw_rect(Rect2(0, (map.h - 1) * ts, map.w * ts, ts), band)
	draw_rect(Rect2(0, 0, ts, map.h * ts), band)
	draw_rect(Rect2((map.w - 1) * ts, 0, ts, map.h * ts), band)
	var center: Vector2 = map.tile_center_px(map.world_exit_tile)
	var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 350.0)
	var glow := Color(0.45, 0.9, 0.5)
	# свечение-дорога: на запад, за край
	draw_rect(Rect2(center + Vector2(-ts * 0.5, -ts * 0.12), Vector2(ts * 0.5, ts * 0.24)),
			Color(glow.r, glow.g, glow.b, 0.25 + 0.15 * pulse))
	# арка: две опоры и перекладина
	draw_rect(Rect2(center + Vector2(-ts * 0.34, -ts * 0.42), Vector2(ts * 0.16, ts * 0.84)), Color("#8a8a82"))
	draw_rect(Rect2(center + Vector2(ts * 0.18, -ts * 0.42), Vector2(ts * 0.16, ts * 0.84)), Color("#8a8a82"))
	draw_rect(Rect2(center + Vector2(-ts * 0.38, -ts * 0.56), Vector2(ts * 0.76, ts * 0.18)), Color("#7a7a72"))
	# зелёное свечение в проёме
	draw_rect(Rect2(center + Vector2(-ts * 0.18, -ts * 0.36), Vector2(ts * 0.36, ts * 0.78)),
			Color(glow.r, glow.g, glow.b, 0.3 + 0.2 * pulse))
	# стрелка влево — «мир там»
	var y := center.y - ts * 0.08
	draw_line(center + Vector2(ts * 0.05, y), center + Vector2(-ts * 0.2, y),
			Color(glow.r, glow.g, glow.b, 0.6 + 0.3 * pulse), 2.5)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-ts * 0.2, y), center + Vector2(-ts * 0.1, y - 4.5),
		center + Vector2(-ts * 0.1, y + 4.5)]),
		Color(glow.r, glow.g, glow.b, 0.6 + 0.3 * pulse))


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
		else:
			# спрайт здания (M9): ссылка b:<id> из city.json -> buildings
			var ref: String = _bld_sprites.get(String(b["type"]), "")
			if ref != "":
				Assets.draw_ref(self, ref, rect.get_center(), float(map.ts))
			else:
				draw_rect(rect, col)
				draw_rect(rect.grow(-4), col.darkened(0.25))
			# точка-работник: занятое здание подсвечено
			if int(b["worker"]) > 0:
				draw_circle(rect.get_center() + Vector2(0, -map.ts * 0.38), 2.5, Color(1, 1, 1, 0.9))
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
		# прочность (M5): повреждённое здание показывает полоску
		if bool(b["done"]) and float(b.get("hp", 999.0)) < float(_bld_max_hp(String(b["type"]))):
			var frac2 := clampf(float(b["hp"]) / float(_bld_max_hp(String(b["type"]))), 0.0, 1.0)
			draw_rect(Rect2(rect.position + Vector2(4, -7), Vector2(map.ts - 8, 4)), Color(0.15, 0.1, 0.1))
			draw_rect(Rect2(rect.position + Vector2(4, -7), Vector2((map.ts - 8) * frac2, 4)), Color("#8bc34a"))


## Мутанты-рейдеры (M5): спрайты данжевых мутантов (M9), полоска здоровья.
func _draw_raiders() -> void:
	var refs := {"mutant": "k:108", "brute": "k:109", "spitter": "k:110"}
	for r in sim.raiders:
		var pos: Vector2 = r["pos"]
		var rad := float(r["p"]["radius"])
		var ref: String = refs.get(String(r["type"]), "k:108")
		var size := rad * 2.8
		var phase := pos.x * 0.9 + Time.get_ticks_msec() / 100.0
		var vx := 0.0
		var pth: PackedVector2Array = r.get("path", PackedVector2Array())
		if not pth.is_empty():
			vx = (pth[0] - pos).x
		Assets.draw_ref(self, ref, pos + Vector2(0, -absf(sin(phase)) * 1.5), size, vx < -1.0, Color.WHITE)
		if int(r["hp"]) < int(r["max_hp"]):
			var frac := clampf(float(r["hp"]) / float(r["max_hp"]), 0.0, 1.0)
			draw_rect(Rect2(pos + Vector2(-12, -rad - 8), Vector2(24, 4)), Color(0.15, 0.1, 0.1))
			draw_rect(Rect2(pos + Vector2(-12, -rad - 8), Vector2(24.0 * frac, 4)), Color(0.9, 0.25, 0.25))
		# осадный мутант выделен — игрок видит, кто ломает стены
		if String(r["type"]) == "brute":
			draw_arc(pos, rad + 3.0, 0.0, TAU, 20, Color(0.9, 0.3, 0.2, 0.6), 2.0)


func _bld_max_hp(type_id: String) -> float:
	var hp_cfg: Dictionary = sim.cfg.get("threat", {}).get("bld_hp", {})
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			return float(hp_cfg.get(String(d.get("effect", "default")), hp_cfg.get("default", 20)))
	return float(hp_cfg.get("default", 20))


func _draw_residents() -> void:
	var child_ref := "k:88"  # рыжий мальчик — дети
	for r in sim.residents:
		var pos: Vector2 = r["pos"]
		var prof := String(r["prof"])
		var ref: String = _prof_sprites.get(prof, child_ref)
		var child := prof == ""
		var size := 20.0 if child else 26.0
		var tint := Color.WHITE
		var ail := String(r.get("ail", ""))
		if ail == "sick":
			tint = Color(0.75, 0.95, 0.65)
		elif ail == "wounded":
			tint = Color(1.0, 0.6, 0.6)
		var sleeping: bool = r["state"] == "sleep" or r["state"] == "rest"
		if sleeping:
			tint = tint.darkened(0.35)
		# бобинг ходьбы (M9): фаза от индекса, амплитуда только в движении
		var moving: bool = bool(r.get("moving", true))
		var phase := float(pos.x * 0.7 + pos.y * 1.3)
		var bob := absf(sin(phase + Time.get_ticks_msec() / (1000.0 / 9.0))) * (2.0 if moving else 0.4)
		Assets.draw_ref(self, ref, pos + Vector2(0, -bob), size,
				String(r.get("dir", "")) == "left", tint)
		# груз носильщика (M6): узел цвета ресурса
		if float(r.get("carry", 0.0)) > 0.0:
			var bag: Color = _pile_colors.get(String(r.get("carry_res", "")), Color(0.8, 0.7, 0.5))
			draw_circle(pos + Vector2(11.0, -6.0 - bob), 4.0, bag.darkened(0.1))
			draw_circle(pos + Vector2(10.0, -7.0 - bob), 2.0, bag.lightened(0.15))


func _draw_ghost() -> void:
	if dragging and zone_mode != "":
		_draw_zone_preview()
		return
	if road_mode:
		# режим дороги: подсветка тайла под мышью и уже проложенных дорог
		var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if map.in_bounds(tile):
			var ok: bool = sim._zone_cell_ok(tile) and int(sim.res.get("stone", 0)) >= int(sim.cfg.get("roads", {}).get("cost_stone", 1))
			draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts)),
					Color(0.5, 1.0, 0.5, 0.35) if ok else Color(1.0, 0.3, 0.3, 0.35))
		return
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
	var ok: bool = sim.is_buildable_tile(tile, build_mode) and sim.can_afford(_cost_of(build_mode))
	var col := Color(0.5, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts)), col)


## Выделение зоны (M6): прямоугольник от первой точки до курсора,
## негодные клетки — красным.
func _draw_zone_preview() -> void:
	var col: Color = _zone_colors.get(zone_mode, Color(0.7, 0.7, 0.4))
	var x0 := mini(drag_from.x, drag_to.x)
	var x1 := maxi(drag_from.x, drag_to.x)
	var y0 := mini(drag_from.y, drag_to.y)
	var y1 := maxi(drag_from.y, drag_to.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var tile := Vector2i(x, y)
			if not map.in_bounds(tile):
				continue
			var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
			if sim._zone_cell_ok(tile):
				draw_rect(rect, Color(col.r, col.g, col.b, 0.35))
			else:
				draw_rect(rect, Color(1.0, 0.3, 0.3, 0.3))


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
