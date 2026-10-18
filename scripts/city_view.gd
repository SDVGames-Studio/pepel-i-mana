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
var plant_mode := false         # инструмент посадки леса (M11)
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
	"kits": Color("#ffb74d"), "crystal": Color("#b46ee0"), "seeds": Color("#c9b458"),
}
# спрайты куч (M9): мешок/брёвна/камень — по главному ресурсу
const PILE_SPRITES := {
	"wood": "k:75", "stone": "k:102", "food": "k:126", "iron": "k:102",
	"metal": "k:102", "tools": "k:104", "kits": "k:103", "crystal": "k:116",
	"seeds": "k:126",
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
	_draw_livestock()
	_draw_raiders()
	_draw_residents()
	_draw_ghost()


var _anim_time := 0.0

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()


## Дикие животные (M5.1): цель охотника — индюк (M10, craftpix, 4 направления).
func _draw_animals() -> void:
	for a in sim.animals:
		var pos: Vector2 = a["pos"]
		var vel := Vector2.ZERO
		var pth: PackedVector2Array = a.get("path", PackedVector2Array())
		if not pth.is_empty():
			vel = pth[0] - pos
		Assets.draw_animal(self, "turkey", Assets.dir_of(vel), not pth.is_empty(),
				pos + Vector2(0, -4), 20.0, _anim_time + float(a["id"]) * 0.37)


## Скот на пастбищах (M10): коровы/овцы/свиньи/куры, детёныши мельче.
func _draw_livestock() -> void:
	for a in sim.livestock:
		var pos: Vector2 = a["pos"]
		var kind := String(a["kind"])
		var adult := bool(a["adult"])
		var size := 26.0 if adult else 16.0
		if kind == "chicken" or kind == "chick":
			size *= 0.7
		var moving := bool(a.get("moving", false))
		Assets.draw_animal(self, {"chick": "chicken"}.get(kind, kind),
				String(a.get("dir", "front")), moving, pos + Vector2(0, -4),
				size, _anim_time + float(a["id"]) * 0.53)


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
						# посев (M10): стадия роста культуры — спрайт растения
						var crops: Array = z.get("crops", [])
						if i < crops.size() and not (crops[i] as Dictionary).is_empty():
							var crop: Dictionary = crops[i]
							var stage := int(crop.get("stage", 0)) + (1 if bool(crop.get("ripe", false)) else 0)
							var ripe := bool(crop.get("ripe", false))
							var crop_id := int(z["id"]) % 3
							var ctint := Color.WHITE if not ripe else Color(1.15, 1.15, 0.95)
							Assets.draw_ref(self, "e:crop%d_%d" % [crop_id, clampi(stage, 0, 3)],
									rect.get_center() + Vector2(0, -2), map.ts * 0.9, false, ctint)
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
	# M10: здания крупнее (×1.55 тайла, якорь по низу) — город выглядит плотнее;
	# рисуем с сортировкой по Y, чтобы нижние здания перекрывали верхние
	var sorted: Array = sim.buildings.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (Vector2(a["tile"]).y) < (Vector2(b["tile"]).y))
	var bld_size := float(map.ts) * 1.55
	for b in sorted:
		var rect := Rect2(Vector2(b["tile"]) * map.ts, Vector2(map.ts, map.ts))
		var col: Color = _bld_colors.get(String(b["type"]), Color(0.91, 0.85, 0.62))
		var anchor: Vector2 = Vector2(rect.get_center().x, rect.end.y - 2.0)
		if not b["done"]:
			# стройплощадка: каркас и полоса прогресса
			draw_rect(rect.grow(-3), Color(col.r, col.g, col.b, 0.25))
			draw_rect(rect.grow(-3), col.darkened(0.2), false, 2.0)
			var work: float = _build_work(String(b["type"]))
			var frac := clampf(float(b["progress"]) / work, 0.0, 1.0) if work > 0.0 else 0.0
			draw_rect(Rect2(rect.position + Vector2(4, map.ts - 9), Vector2((map.ts - 8) * frac, 5)), Color("#ffe082"))
		else:
			# спрайт здания (M9): ссылка b:<id>/e:<имя> из city.json -> buildings
			var ref: String = _bld_sprites.get(String(b["type"]), "")
			if ref == "dom_house":
				# дома разные (M11): 7 вариантов dom-пака по номеру здания
				var variants := ["b:dom2", "b:dom3", "b:dom5", "b:dom7", "b:dom10", "b:dom16", "b:dom18"]
				ref = variants[absi(int(b["id"])) % variants.size()]
			if ref != "":
				var sref := ref
				if String(b["type"]) == "orchard":
					# яблоневый сад (M10): растёт — молодое дерево, зрелое — с яблоками
					var stage := int(b.get("apple_stage", 0))
					sref = "e:tree_oak" if stage < 2 else "e:tree_fruit2"
				var h := bld_size
				if String(b["type"]) == "wall" or String(b["type"]) == "gate":
					h = float(map.ts) * 1.15   # стены не должны нависать над рядом
				draw_circle(anchor + Vector2(0, -2), bld_size * 0.22, Color(0, 0, 0, 0.16))
				Assets.draw_ref(self, sref, anchor - Vector2(0, h * 0.5), h)
			else:
				draw_rect(rect, col)
				draw_rect(rect.grow(-4), col.darkened(0.25))
			# точка-работник: занятое здание подсвечено
			if int(b["worker"]) > 0:
				draw_circle(anchor + Vector2(0, -bld_size + 2.0), 2.5, Color(1, 1, 1, 0.9))
		# кладбище темнеет (M11): тьма ползёт с кладбища, пока некромант работает
		if String(b["type"]) == "cemetery" and bool(b["done"]):
			var dark := clampf(float(sim.necro_dark), 0.0, 1.0)
			if dark > 0.02:
				var rings := 4
				for i in rings:
					var rr: float = map.ts * (0.8 + dark * 2.2) * (float(i + 1) / float(rings))
					draw_circle(anchor - Vector2(0, 4), rr,
							Color(0.08, 0.05, 0.14, 0.05 + 0.1 * dark))
				if sim.necro_known:
					var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 500.0)
					draw_arc(anchor - Vector2(0, 4), map.ts * (0.9 + dark * 2.0),
							0.0, TAU, 24, Color(0.5, 0.3, 0.7, 0.12 + 0.1 * pulse), 2.0)
			# ночные призывы (M11): скелеты видны у кладбища только ночью
			if sim.is_night() and int(sim.necro_army) > 0:
				var shown: int = mini(3, sim.necro_ghosts.size())
				for g in shown:
					var gpx: Vector2 = sim.necro_ghosts[g]
					var bob := absf(sin(Time.get_ticks_msec() / 320.0 + float(g) * 2.1)) * 2.0
					Assets.draw_ref(self, "k:121", gpx + Vector2(0, -bob),
							map.ts * 1.1, false, Color(0.75, 0.7, 0.9))
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


## Атакующие (M5 мутанты; M11 духи леса, Древень, скелеты некроманта).
func _draw_raiders() -> void:
	var refs := {"mutant": "k:108", "brute": "k:109", "spitter": "k:110",
			"forest_spirit": "e:spirit", "forest_boss": "e:treant", "skeleton": "k:121"}
	for r in sim.raiders:
		var pos: Vector2 = r["pos"]
		var rad := float(r["p"]["radius"])
		var kind := String(r["type"])
		var ref: String = refs.get(kind, "k:108")
		var size := rad * 2.8
		var lift := 0.0
		var tint := Color.WHITE
		if kind == "forest_spirit" or kind == "forest_boss":
			# духи парят: синус повыше и медленнее, свечение бирюзой
			lift = 4.0 + 2.5 * sin(Time.get_ticks_msec() / 260.0 + float(r["id"]))
			tint = Color(0.8, 1.05, 1.0) if kind == "forest_spirit" else Color(0.9, 1.1, 0.85)
		var phase := pos.x * 0.9 + Time.get_ticks_msec() / 100.0
		var vx := 0.0
		var pth: PackedVector2Array = r.get("path", PackedVector2Array())
		if not pth.is_empty():
			vx = (pth[0] - pos).x
		Assets.draw_ref(self, ref, pos + Vector2(0, -absf(sin(phase)) * 1.5 - lift), size, vx < -1.0, tint)
		if int(r["hp"]) < int(r["max_hp"]):
			var frac := clampf(float(r["hp"]) / float(r["max_hp"]), 0.0, 1.0)
			draw_rect(Rect2(pos + Vector2(-12, -rad - 8), Vector2(24, 4)), Color(0.15, 0.1, 0.1))
			draw_rect(Rect2(pos + Vector2(-12, -rad - 8), Vector2(24.0 * frac, 4)), Color(0.9, 0.25, 0.25))
		# осадный мутант и босс леса выделены — видно, кто главный
		if kind == "brute" or kind == "forest_boss":
			var ring := Color(0.9, 0.3, 0.2, 0.6) if kind == "brute" else Color(0.5, 0.9, 0.4, 0.7)
			draw_arc(pos, rad + 3.0, 0.0, TAU, 20, ring, 2.0)


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
		var child := prof == ""
		# M11 по замечанию заказчика: жители НЕ меньше героя-«великана» —
		# кадры граждан 48px с полями, видимое тело ~30px при высоте 50px
		var size := 26.0 if child else 50.0
		var tint := Color.WHITE
		var ail := String(r.get("ail", ""))
		if ail == "sick":
			tint = Color(0.75, 0.95, 0.65)
		elif ail == "wounded":
			tint = Color(1.0, 0.6, 0.6)
		# некромант (M11): тайный — после раскрытия читается по лиловой тени
		if String(r.get("secret", "")) == "necromancer" and sim.necro_known:
			tint = tint.lerp(Color(0.75, 0.6, 0.95), 0.45)
		var sleeping: bool = r["state"] == "sleep" or r["state"] == "rest"
		if sleeping:
			tint = tint.darkened(0.45)
		var moving: bool = bool(r.get("moving", true)) and not sleeping
		var dir := String(r.get("dir", "front"))
		if child:
			# дети — кеноувский спрайт с бобингом
			var phase := float(pos.x * 0.7 + pos.y * 1.3)
			var bob := absf(sin(phase + Time.get_ticks_msec() / (1000.0 / 9.0))) * (2.0 if moving else 0.4)
			Assets.draw_ref(self, child_ref, pos + Vector2(0, -bob), size, dir == "left", tint)
		else:
			# взрослые — craftpix-граждане (M10): 4 направления, кадры ходьбы/idle;
			# профессия читается по лёгкой подкраске одежды
			var prof_color: Color = _prof_colors.get(prof, Color.WHITE)
			var ctint := tint.lerp(prof_color, 0.22) if prof != "" else tint
			Assets.draw_citizen(self, 1 + int(r["id"]) % 4, dir, moving, pos, size,
					_anim_time + float(r["id"]) * 0.41, ctint)
		# груз носильщика (M6): узел цвета ресурса
		if float(r.get("carry", 0.0)) > 0.0:
			var bag: Color = _pile_colors.get(String(r.get("carry_res", "")), Color(0.8, 0.7, 0.5))
			draw_circle(pos + Vector2(11.0, -6.0), 4.0, bag.darkened(0.1))
			draw_circle(pos + Vector2(10.0, -7.0), 2.0, bag.lightened(0.15))


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
	if plant_mode:
		# посадка леса (M11): саженец под курсором, годность по траве и семенам
		var ptile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if map.in_bounds(ptile):
			var ok2: bool = sim.can_plant_at(ptile)
			draw_rect(Rect2(Vector2(ptile) * map.ts, Vector2(map.ts, map.ts)),
					Color(0.5, 1.0, 0.5, 0.35) if ok2 else Color(1.0, 0.3, 0.3, 0.35))
			var bottom: Vector2 = Vector2(ptile) * map.ts + Vector2(map.ts / 2.0, map.ts * 0.92)
			Assets.draw_ref(self, "e:sap2", bottom, map.ts * 0.9, false,
					Color(1, 1, 1, 0.6))
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
