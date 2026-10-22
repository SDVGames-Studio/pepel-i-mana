extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Отрисовка города (M2): тайлы ландшафта, аномалия, здания/стройплощадки,
## жители, призрак стройки. Цветные примитивы — пиксель-арт в M8.
## M6: дороги, зоны с прогрессом обустройства, кучи ресурсов у зданий,
## груз носильщика, предпросмотр выделения зоны.

var map = null
var sim = null
var fauna_cfg: Dictionary = {}   # data/fauna.json — виды дикой фауны города
var colors: Dictionary = {}
var build_mode := ""            # выбранный тип здания (призрак под мышью)
var enchant_mode := ""          # выбранное зачарование (подсветка здания)
var enchant_colors: Dictionary = {}
var zone_mode := ""             # инструмент зоны (M6): выделение областью
var road_mode := false          # инструмент дороги (M6): рисование мышью
var plant_mode := false         # инструмент посадки леса (M11)
var move_mode := false          # инструмент переноса зданий (этап 2, аспект 5)
var move_bld_id := -1           # здание, снятое для переноса (id), -1 — не выбрано
var plaza_mode := false         # перенос главной площади (правки v1.20)


## Призрак площади 2×2 под курсором: зелёный — годное место, красный — нет.
func _draw_plaza_ghost() -> void:
	var ts := float(map.ts)
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	# проверка без переноса: границы + здания на клетках
	var ok := true
	for dy in 2:
		for dx in 2:
			var c: Vector2i = tile + Vector2i(dx, dy)
			if not map.in_bounds(c) or c == map.anomaly_tile \
					or not sim.building_at(c).is_empty():
				ok = false
	var col := Color(0.6, 0.9, 1.0, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	var rect := Rect2(Vector2(tile) * ts, Vector2(ts * 2.0, ts * 2.0))
	draw_rect(rect, col)
	draw_rect(rect.grow(-2), Color(col.r, col.g, col.b, 0.9), false, 2.0)
var dragging := false           # ЛКМ зажата — идёт выделение/рисование
var drag_from := Vector2i(-1, -1)
var drag_to := Vector2i(-1, -1)

var _prof_colors: Dictionary = {}
var _prof_sprites: Dictionary = {}
var _bld_fill: Dictionary = {}      # тип здания → цвет категории (схематичный режим)
var _bld_short: Dictionary = {}     # тип здания → ключ краткой подписи (bld.short.*)
var _bld_loc: Dictionary = {}       # тип здания → ключ полного названия (bld.*)
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
	# виды дикой фауны (M14-C правка): цвета и размеры из data/fauna.json
	var f := FileAccess.open("res://data/fauna.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		fauna_cfg = parsed if parsed is Dictionary else {}
	var c: Dictionary = city_cfg["colors"]
	for key in c:
		colors[key] = Color(String(c[key]))
	for prof in city_cfg["professions"]:
		_prof_colors[String(prof["id"])] = Color(String(prof["color"]))
		_prof_sprites[String(prof["id"])] = String(prof.get("sprite", ""))
	# схематичный режим (этап 2, аспект 1): цвет здания — цвет его категории
	var cat_colors: Dictionary = {}
	for cid in city_cfg.get("cats", {}):
		cat_colors[String(cid)] = Color(String(city_cfg["cats"][cid]["color"]))
	for b in city_cfg["buildings"]:
		_bld_fill[String(b["id"])] = cat_colors.get(String(b.get("cat", "")), Color(0.91, 0.85, 0.62))
		_bld_short[String(b["id"])] = String(b.get("short", ""))
		_bld_loc[String(b["id"])] = String(b.get("loc", ""))
	for t in city_cfg.get("zones", {}).get("types", {}):
		_zone_colors[String(t)] = Color(String(city_cfg["zones"]["types"][t]["color"]))
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	# ландшафт рисует отдельный статический слой city_terrain.gd (M9)
	_draw_plaza()
	_draw_zones()
	_draw_roads()
	_draw_anomaly()
	_draw_world_exit()
	_draw_world_sorted()
	_draw_ghost()


## Главная площадь 2×2 (правки v1.20): каменные плиты, место сбора и планёрки.
func _draw_plaza() -> void:
	if sim.plaza == Vector2i(-1, -1):
		return
	var ts := float(map.ts)
	var origin := Vector2(sim.plaza) * ts
	var rect := Rect2(origin, Vector2(ts * 2.0, ts * 2.0))
	var stone := Color("#9aa0a8")
	var stone2 := Color("#8a9098")
	draw_rect(rect, stone)
	for i in 4:
		var cx := origin.x + ts * (0.5 + float(i % 2))
		var cy := origin.y + ts * (0.5 + float(i / 2))
		draw_rect(Rect2(cx - ts * 0.42, cy - ts * 0.42, ts * 0.84, ts * 0.84), stone2)
	draw_rect(rect, Color("#5d6470"), false, 2.0)
	# центральный круг — «место сбора», пульсирует утром
	var center := origin + Vector2(ts, ts)
	var pulse := 0.5 + 0.5 * sin(_anim_time * 2.0)
	draw_circle(center, ts * 0.34, Color(0.98, 0.95, 0.85, 0.25 + 0.2 * pulse))
	draw_circle(center, ts * 0.16, Color("#e8e2d0"))


var _anim_time := 0.0

# кэш тайлов деревьев/пней/саженцев (M12): ландшафт меняется редко —
# список пересобирается по флагу, который ставит сцена при sim.terrain_dirty
var _trees_dirty := true
var _trees_cache: Array = []

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()


## Пересобрать кэш деревьев (вызывает city.gd при sim.terrain_dirty).
func mark_trees_dirty() -> void:
	_trees_dirty = true


## Единый Y-сортированный слой (M12): деревья, пни, саженцы, здания, кучи,
## животные, скот, рейдеры, жители и герой рисуются в порядке «линии ног» —
## нижние объекты перекрывают верхние, никто не проваливается сквозь текстуры.
func _draw_world_sorted() -> void:
	var ts := float(map.ts)
	var entries: Array = []   # [y_px, kind, payload]
	# обитатели внутри домов (этап 2, аспект 2): для светящихся окон
	_inside_homes.clear()
	for r in sim.residents:
		if int(r.get("inside", 0)) > 0 and r.get("home") != null and not (r["home"] as Dictionary).is_empty():
			_inside_homes[int((r["home"] as Dictionary)["id"])] = true
	if _trees_dirty:
		_trees_dirty = false
		_trees_cache = []
		for y in map.h:
			for x in map.w:
				var t: int = map.grid[y][x]
				if t == map.TILE_TREE or map.stumps.has(Vector2i(x, y)) or map.saplings.has(Vector2i(x, y)):
					_trees_cache.append(Vector2i(x, y))
	for tile: Vector2i in _trees_cache:
		entries.append([float(tile.y) * ts + ts * 0.92, "tree", tile])
	for b in sim.buildings:
		# Y-якорь — нижняя линия прямоугольника здания (2×2: tile.y + 1)
		var bw: int = sim.bld_w(b)
		entries.append([float(Vector2(b["tile"]).y + bw - 1) * ts + ts - 2.0, "bld", b])
		if bool(b["done"]) and (b as Dictionary).has("pile"):
			var corner: Vector2 = Vector2(b["tile"]) * ts + Vector2(ts * (0.78 + float(bw - 1)), ts * (0.88 + float(bw - 1)))
			if _pile_total(b) >= 0.5:
				entries.append([corner.y, "pile", b])
	for a in sim.animals:
		entries.append([Vector2(a["pos"]).y, "animal", a])
	for a in sim.livestock:
		entries.append([Vector2(a["pos"]).y, "stock", a])
	for w in sim.wanderers:
		entries.append([Vector2(w["pos"]).y, "wanderer", w])
	for r in sim.raiders:
		entries.append([Vector2(r["pos"]).y, "raider", r])
	for r in sim.residents:
		if int(r.get("inside", 0)) > 0:
			continue   # спит/лежит/прячется внутри дома — с карты не виден
		entries.append([Vector2(r["pos"]).y, "res", r])
	if city != null and city.hero != null and not city.hero.dead:
		entries.append([city.hero.global_position.y, "hero", city.hero])
	entries.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	_draw_campfire()
	for e in entries:
		match String(e[1]):
			"tree":
				_draw_tree_at(e[2])
			"bld":
				_draw_building(e[2])
			"pile":
				_draw_pile(e[2])
			"animal":
				_draw_animal(e[2])
			"stock":
				_draw_stock(e[2])
			"wanderer":
				_draw_wanderer(e[2])
			"raider":
				_draw_raider(e[2])
			"res":
				_draw_resident(e[2])
			"hero":
				_draw_hero(e[2])


## Городской костёр (M12): горит вечером, ночью и при тревоге — точка сбора
## жителей и вечерних посиделок (рисуется под сортированным слоем).
func _draw_campfire() -> void:
	var fire := _fire_tile()
	var evening := false
	var day_len := float(sim.cfg["day_length"])
	var life: Dictionary = sim.cfg.get("life", {})
	var t := fmod(sim.time, day_len) / day_len
	var nf := float(sim.cfg["night_fraction"])
	evening = t >= maxf(0.0, 1.0 - nf - float(life.get("evening_len", 0.14)))
	if not evening and not sim.is_night() and not sim._raid_warned:
		return
	var pos: Vector2 = map.tile_center_px(fire) + Vector2(0, 4)
	var glow := 0.14 + 0.05 * sin(Time.get_ticks_msec() / 180.0)
	draw_circle(pos, map.ts * 1.6, Color(1.0, 0.6, 0.25, glow))
	Assets.draw_sheet(self, "fire", int(_anim_time * 9.0) % 5, pos, map.ts * 0.9)


## Точка костра: у колодца, если он есть, иначе в центре (как в симуляции).
func _fire_tile() -> Vector2i:
	for b in sim.buildings:
		if sim._active(b) and String(b["type"]) == "well":
			return Vector2i(b["tile"]) + Vector2i(1, 0)
	return map.spawn_tile


## Могилки вокруг кладбища (M12): маленькие кресты, появляются после похорон.
func _draw_graves(anchor: Vector2) -> void:
	for g in sim.graves:
		if not bool(g.get("ready", false)):
			continue
		var pos: Vector2 = map.tile_center_px(Vector2i(g["tile"]))
		if pos.distance_to(anchor) > map.ts * 5.0:
			continue
		draw_line(pos + Vector2(-3, -8), pos + Vector2(3, -8), Color(0.86, 0.84, 0.78), 2.0)
		draw_line(pos + Vector2(0, -11), pos + Vector2(0, -2), Color(0.86, 0.84, 0.78), 2.0)
		draw_line(pos + Vector2(-3, 0), pos + Vector2(3, 0), Color(0.55, 0.52, 0.45), 2.0)


## Дерево/пень/саженец в тайле (переехали из статического слоя в M12).
## Пень подбирается под тип дерева (замечание 2026-10-20): тот же хеш,
## что выбрал спрайт дерева, выбирает вариант пня.
func _draw_tree_at(tile: Vector2i) -> void:
	var ts := float(map.ts)
	var bottom := Vector2(tile.x * ts + ts / 2.0, tile.y * ts + ts * 0.92)
	var key := Vector2i(tile)
	if map.saplings.has(key):
		_draw_sapling(key, bottom, ts)
	elif map.grid[tile.y][tile.x] == map.TILE_TREE:
		_draw_shadow(bottom + Vector2(0, 2), ts * 0.6)
		Assets.draw_ref(self, TREE_REFS[_hash(tile.x, tile.y, TREE_REFS.size())],
				bottom + Vector2(0, -2), ts * 2.6)
	else:
		_draw_stump(bottom, ts, _hash(tile.x, tile.y, STUMP_PALS.size()))


## Пень: срез с годовыми кольцами и кора в палитре своего дерева.
const STUMP_PALS := [
	{"side": Color("#6d4c33"), "top": Color("#a1887f"), "ring": Color("#7d6045")},   # дуб
	{"side": Color("#5a4030"), "top": Color("#8d6e63"), "ring": Color("#6b5140")},   # сосна
	{"side": Color("#d7ccc8"), "top": Color("#efebe9"), "ring": Color("#a1887f")},   # берёза
	{"side": Color("#7a5a3a"), "top": Color("#bcaaa4"), "ring": Color("#8d6e63")},   # осеннее
	{"side": Color("#6d4c33"), "top": Color("#a1887f"), "ring": Color("#7d6045")},   # дуб 2
	{"side": Color("#5a4030"), "top": Color("#8d6e63"), "ring": Color("#6b5140")},   # сосна 2
	{"side": Color("#77503a"), "top": Color("#c9b0a5"), "ring": Color("#9a7462")},   # плодовое
	{"side": Color("#d7ccc8"), "top": Color("#efebe9"), "ring": Color("#a1887f")},   # берёза 2
]


func _draw_stump(bottom: Vector2, ts: float, variant: int) -> void:
	var pal: Dictionary = STUMP_PALS[variant % STUMP_PALS.size()]
	_draw_shadow(bottom, ts * 0.3)
	var w := ts * 0.46
	var h := ts * 0.26
	# кора (боковина) и светлый срез сверху
	draw_rect(Rect2(bottom + Vector2(-w / 2.0, -h), Vector2(w, h)), pal["side"])
	draw_rect(Rect2(bottom + Vector2(-w / 2.0, -h * 1.7), Vector2(w, h * 0.9)), pal["top"])
	draw_arc(bottom + Vector2(0, -h * 1.25), w * 0.26, 0.0, TAU, 14, pal["ring"], 1.2)
	draw_circle(bottom + Vector2(0, -h * 1.25), w * 0.08, pal["ring"])
	# детали по типу: у берёзы — тёмные чёрточки, у плодового — живой побег,
	# у старого/осеннего — трещина
	var birch := variant == 2 or variant == 7
	var fruit := variant == 6
	var autumn := variant == 3
	if birch:
		draw_rect(Rect2(bottom + Vector2(-w * 0.36, -h * 0.75), Vector2(w * 0.18, h * 0.22)), Color("#424242"))
		draw_rect(Rect2(bottom + Vector2(w * 0.14, -h * 0.4), Vector2(w * 0.16, h * 0.2)), Color("#424242"))
	elif fruit:
		draw_line(bottom + Vector2(0, -h * 1.6), bottom + Vector2(3, -h * 2.4), Color("#7cb342"), 1.4)
		draw_circle(bottom + Vector2(3.6, -h * 2.5), 1.4, Color("#8bc34a"))
	elif autumn:
		draw_line(bottom + Vector2(-w * 0.2, -h * 1.6), bottom + Vector2(w * 0.1, -h * 0.3), Color("#4e342e"), 1.1)


const TREE_REFS := ["e:tree_oak", "e:tree_pine", "e:tree_birch", "e:tree_autumn",
		"e:tree_oak", "e:tree_pine", "e:tree_fruit2", "e:tree_birch"]


static func _hash(x: int, y: int, n: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, n)


func _draw_shadow(pos: Vector2, radius: float) -> void:
	draw_circle(pos, radius * 0.5, Color(0, 0, 0, 0.18))


## Саженец: две стадии роста (малый росток, кустик).
func _draw_sapling(key: Vector2i, bottom: Vector2, ts: float) -> void:
	var s: Dictionary = map.saplings[key]
	var frac: float = clampf(float(s.get("t", 0.0)) / maxf(0.1, float(s.get("grow_days", 1.2))), 0.0, 1.0)
	var ref := "e:sap1" if frac < 0.5 else "e:sap2"
	_draw_shadow(bottom, ts * 0.2)
	Assets.draw_ref(self, ref, bottom, ts * (0.5 if frac < 0.5 else 0.85))


func _pile_total(b: Dictionary) -> float:
	var total := 0.0
	for k in b.get("pile", {}):
		total += float(b["pile"][k])
	return total


## Куча ресурса у здания (M6 → M12 сортированный слой).
func _draw_pile(b: Dictionary) -> void:
	var ts := float(map.ts)
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
		return
	var corner: Vector2 = Vector2(b["tile"]) * ts + Vector2(ts * 0.78, ts * 0.88)
	var size := 8.0 + minf(10.0, total / 3.0)
	var tint: Color = _pile_colors.get(key, Color(0.8, 0.8, 0.8)).lightened(0.25)
	Assets.draw_ref(self, PILE_SPRITES.get(key, "k:73"), corner, size, false, tint)


## Дикие животные (M5.1 → M14-C правка): виды из data/fauna.json — индюк
## остался, добавились олени, кабаны, птицы и волки (векторные, в стиле мира).
func _draw_animal(a: Dictionary) -> void:
	var pos: Vector2 = a["pos"]
	var vel := Vector2.ZERO
	var pth: PackedVector2Array = a.get("path", PackedVector2Array())
	if not pth.is_empty():
		vel = pth[0] - pos
	var kind := String(a.get("kind", "turkey"))
	if kind == "deer" or kind == "boar" or kind == "wolf" or kind == "bird":
		_draw_fauna_animal(a, kind, pos, vel)
		return
	Assets.draw_animal(self, "turkey", Assets.dir_of(vel), not pth.is_empty(),
			pos + Vector2(0, -4), 20.0, _anim_time + float(a["id"]) * 0.37)


## Зверь из fauna.json: тело/голова/детали вида, цвет и размер из данных.
func _draw_fauna_animal(a: Dictionary, kind: String, pos: Vector2, vel: Vector2) -> void:
	var def: Dictionary = {}
	for s in fauna_cfg.get("species", []):
		if String(s["id"]) == kind:
			def = s
			break
	if def.is_empty():
		Assets.draw_animal(self, "turkey", Assets.dir_of(vel), not vel.is_zero_approx(),
				pos + Vector2(0, -4), 20.0, _anim_time + float(a["id"]) * 0.37)
		return
	var col := Color(String(def.get("color", "#cccccc")))
	var size := float(def.get("size", 1.0))
	var moving := not vel.is_zero_approx()
	var bob := absf(sin(_anim_time * 4.0 + float(a["id"]))) * (1.5 if moving else 0.4)
	draw_circle(pos + Vector2(0, 2), 5.0 * size, Color(0, 0, 0, 0.2))
	draw_circle(pos + Vector2(0, -2.0 * size - bob * 0.2), 4.6 * size, col)
	draw_circle(pos + Vector2(4.0 * size, -4.5 * size - bob * 0.3), 2.6 * size, col.lightened(0.12))
	match kind:
		"deer":
			draw_line(pos + Vector2(3.5 * size, -6.5 * size), pos + Vector2(2.2 * size, -10.5 * size), Color("#6d4c33"), 1.2)
			draw_line(pos + Vector2(4.8 * size, -6.2 * size), pos + Vector2(5.8 * size, -10.0 * size), Color("#6d4c33"), 1.2)
			draw_circle(pos + Vector2(5.6 * size, -4.0 * size), 0.9 * size, Color.WHITE)
		"boar":
			draw_circle(pos + Vector2(6.2 * size, -3.6 * size), 1.1 * size, Color("#e8b0a0"))
			draw_line(pos + Vector2(-4.5 * size, -2.0 * size), pos + Vector2(-6.5 * size, -2.8 * size), col.darkened(0.3), 1.5)
		"wolf":
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(3.0 * size, -6.2 * size), pos + Vector2(3.8 * size, -8.8 * size),
				pos + Vector2(4.9 * size, -6.4 * size)]), col.darkened(0.15))
			draw_line(pos + Vector2(-4.5 * size, -3.0 * size), pos + Vector2(-7.2 * size, -4.6 * size), col.darkened(0.25), 1.6)
		"bird":
			draw_circle(pos + Vector2(4.2 * size, -5.2 * size), 1.7 * size, Color("#3a3a3a"))
			draw_line(pos + Vector2(-3.0 * size, -2.4 * size), pos + Vector2(-6.0 * size, -4.4 * size), col.darkened(0.2), 1.2)


## Скот на пастбищах (M10): коровы/овцы/свиньи/куры, детёныши мельче.
func _draw_stock(a: Dictionary) -> void:
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


## Бродячий торговец (этап 2, аспект 4): гражданин с тюком и жёлтой одеждой;
## у палатки периодически выкрикивает зазывку-облачко.
func _draw_wanderer(w: Dictionary) -> void:
	var pos: Vector2 = w["pos"]
	var pth: PackedVector2Array = w.get("path", PackedVector2Array())
	var moving := not pth.is_empty() and pos.distance_to(pth[pth.size() - 1]) > 2.0
	var dir := String(w.get("dir", "front"))
	var tint := Color("#ffd54f").lerp(Color.WHITE, 0.35)
	Assets.draw_citizen(self, 1 + int(w["id"]) % 4, dir, moving, pos, 50.0,
			_anim_time + float(w["id"]) * 0.47, tint)
	# тюк с товаром за спиной
	draw_circle(pos + Vector2(-11.0, -8.0), 5.0, Color("#8d6e63"))
	draw_circle(pos + Vector2(-10.0, -10.0), 2.5, Color("#a1887f"))
	if String(w.get("mode", "")) == "trade" and fmod(sim.time, 14.0) < 3.0:
		var key := "wshop.%d" % (int(w["id"]) % 4 + 1)
		_draw_speech_bubble(pos, Loc.t(key))


## Зоны (M6): заливка по типу (Поле/Пастбище), прогресс обустройства
## в незаполненных клетках (правки v1.20: слои и жилая убраны).
func _draw_zones() -> void:
	var fill_work: float = float(sim.cfg.get("zones", {}).get("fill_work", 4.0))
	for z in sim.zones:
		var col: Color = _zone_colors.get(String(z["type"]), Color(0.7, 0.7, 0.4))
		for i in (z["cells"] as Array).size():
			var tile: Vector2i = z["cells"][i]
			var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
			var filled: bool = float(z["progress"][i]) >= fill_work
			# невыделенные клетки заметны сразу (замечание 2026-10-21:
			# «ставлю поле — ничего нет»): заливка плотнее, у поля — борозды
			draw_rect(rect, Color(col.r, col.g, col.b, 0.42 if filled else 0.32))
			if String(z["type"]) == "field":
				for k: int in 3:
					var y: float = rect.position.y + map.ts * (0.25 + 0.25 * k)
					draw_line(Vector2(rect.position.x + 4, y),
							Vector2(rect.position.x + map.ts - 4, y),
							col.darkened(0.3 if filled else 0.15),
							1.5 if filled else 1.0)
				if filled:
					draw_rect(rect.grow(-2), col.darkened(0.15), false, 1.5)
					match String(z["type"]):
						"field":
							# посев (M10): стадия роста культуры. Правки v1.20.1:
							# готовые спрайты растений — крошечные точки в углу
							# листа (не видно вовсе), поэтому рисуем растения
							# сами: куст зелени, спелый — с плодом цвета культуры
							var crops: Array = z.get("crops", [])
							var crop_vis: int = int(sim.crop_def(String(z.get("crop", "turnip"))).get("sprite", 0))
							if i < crops.size() and not (crops[i] as Dictionary).is_empty():
								var crop: Dictionary = crops[i]
								var stage := int(crop.get("stage", 0)) + (1 if bool(crop.get("ripe", false)) else 0)
								var ripe := bool(crop.get("ripe", false))
								_draw_crop_plant(rect.get_center(), clampi(stage, 0, 4), ripe, crop_vis)
						"pasture":
							draw_circle(rect.position + Vector2(10, 20), 3.0, col.darkened(0.35))
							draw_circle(rect.position + Vector2(22, 12), 3.0, col.darkened(0.35))
			else:
				var frac := clampf(float(z["progress"][i]) / maxf(0.1, fill_work), 0.0, 1.0)
				draw_rect(Rect2(rect.position + Vector2(4, map.ts - 8), Vector2((map.ts - 8) * frac, 4)),
						Color("#ffe082"))
		# пастбище — забор по периметру зоны (2026-10-21): цветное обозначение
		# читается с одного взгляда, скот внутри как за забором
		if String(z["type"]) == "pasture":
			_draw_zone_fence(z)


## Растение на грядке (правки v1.20.1): рисуем сами — росток → куст →
## спелый куст с плодом. crop_vis: 1 — репа (белый плод), 2 — тыква
## (оранжевый), прочее — зелень без плода.
func _draw_crop_plant(center: Vector2, stage: int, ripe: bool, crop_vis: int) -> void:
	var leaf := Color("#5fae4a")
	var leaf_dark := Color("#3f7a33")
	var stem := Color("#4c8a3c")
	var fruit := Color("#c9a8e8")   # репа — бледно-фиолетовая
	if crop_vis == 2:
		fruit = Color("#e8892c")   # тыква — оранжевая
	var base := center + Vector2(0.0, map.ts * 0.22)
	match clampi(stage, 0, 4):
		0:   # росток: росток-«вилка»
			draw_line(base, base + Vector2(0, -4), stem, 1.5)
			draw_circle(base + Vector2(-2, -4), 1.6, leaf)
			draw_circle(base + Vector2(2, -4), 1.6, leaf)
		1:   # зелень растёт
			draw_line(base, base + Vector2(0, -7), stem, 2.0)
			draw_circle(base + Vector2(-3, -7), 2.4, leaf)
			draw_circle(base + Vector2(3, -7), 2.4, leaf)
			draw_circle(base + Vector2(0, -10), 2.0, leaf_dark)
		2:   # куст
			draw_line(base, base + Vector2(0, -9), stem, 2.2)
			draw_circle(base + Vector2(-4, -9), 3.2, leaf)
			draw_circle(base + Vector2(4, -9), 3.2, leaf)
			draw_circle(base + Vector2(0, -12), 3.0, leaf_dark)
			draw_circle(base + Vector2(0, -6), 2.2, leaf)
		_:   # 3-4: спелый куст с плодом
			draw_line(base, base + Vector2(0, -9), stem, 2.2)
			draw_circle(base + Vector2(-4, -9), 3.0, leaf)
			draw_circle(base + Vector2(4, -9), 3.0, leaf)
			draw_circle(base + Vector2(0, -5), 4.2 if crop_vis == 2 else 3.4, fruit)
			draw_circle(base + Vector2(-1, -6), 1.2, fruit.lightened(0.35))
			if ripe:
				# спелость: тёплое свечение — видно с первого взгляда
				var glow := Color(1.0, 0.95, 0.6, 0.25 + 0.12 * sin(_anim_time * 3.0))
				draw_circle(base + Vector2(0, -6), 7.5, glow)


## Забор пастбища: по внешним рёбрам клеток зоны — перекладина и столбики.
func _draw_zone_fence(z: Dictionary) -> void:
	var ts := float(map.ts)
	var inside := {}
	for c in z["cells"]:
		inside[Vector2i(c)] = true
	var wood := Color("#7a5a3a")
	var dark := Color("#5d4030")
	for c: Vector2i in inside.keys():
		var p := Vector2(c) * ts
		var edges := []
		if not inside.has(c + Vector2i(1, 0)):
			edges.append([p + Vector2(ts, 0), p + Vector2(ts, ts), p + Vector2(ts, ts * 0.5)])
		if not inside.has(c + Vector2i(-1, 0)):
			edges.append([p, p + Vector2(0, ts), p + Vector2(0, ts * 0.5)])
		if not inside.has(c + Vector2i(0, 1)):
			edges.append([p + Vector2(0, ts), p + Vector2(ts, ts), p + Vector2(ts * 0.5, ts)])
		if not inside.has(c + Vector2i(0, -1)):
			edges.append([p, p + Vector2(ts, 0), p + Vector2(ts * 0.5, 0)])
		for e in edges:
			draw_line(e[0], e[1], wood, 2.5)
			draw_line(e[2], e[2] + Vector2(0, -8), dark, 2.5)
			draw_circle(e[2] + Vector2(0, -8), 1.6, dark)


## Дороги (M6): тёплые плитки с камешками.
func _draw_roads() -> void:
	var col: Color = colors.get("road", Color("#6e5f4a"))
	for tile: Vector2i in map.road:
		var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
		draw_rect(rect, col)
		draw_circle(rect.position + Vector2(map.ts * 0.3, map.ts * 0.4), 2.0, col.lightened(0.2))
		draw_circle(rect.position + Vector2(map.ts * 0.65, map.ts * 0.65), 1.6, col.lightened(0.15))


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


## Здание в общем сортированном слое (M12). Схематичный режим (этап 2,
## аспект 1) + прямоугольник 2×2 с входом (этап 2, аспект 2): заливка
## цвета категории, тёмная кайма, дверной проём у входа, окно светится,
## если кто-то спит внутри. Игровые метки сохранены.
func _draw_building(b: Dictionary) -> void:
	var ts := float(map.ts)
	var bw: int = sim.bld_w(b)
	var rect := Rect2(Vector2(b["tile"]) * ts, Vector2(ts * float(bw), ts * float(bw)))
	var type_id := String(b["type"])
	var col: Color = _bld_fill.get(type_id, Color(0.91, 0.85, 0.62))
	var anchor: Vector2 = Vector2(rect.get_center().x, rect.end.y - 2.0)
	if not b["done"]:
		# стройплощадка: призрачная заливка, каркас и полоса прогресса
		draw_rect(rect.grow(-3), Color(col.r, col.g, col.b, 0.22))
		draw_rect(rect.grow(-3), col.darkened(0.2), false, 2.0)
		var work: float = _build_work(type_id)
		var frac := clampf(float(b["progress"]) / work, 0.0, 1.0) if work > 0.0 else 0.0
		draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 9),
				Vector2((rect.size.x - 8) * frac, 5)), Color("#ffe082"))
		_draw_bld_label(b, rect)
	elif bool(b.get("razed", false)):
		# руины (этап 2, аспект 5): тёмные обломки цвета категории, трещины
		# и метка «разрушено» — чинится героем за 40% стоимости (E)
		var ruin := col.darkened(0.62)
		draw_rect(rect, ruin)
		draw_rect(rect.grow(-2), col.darkened(0.78), false, 2.0)
		draw_line(rect.position + Vector2(ts * 0.25, ts * 0.2),
				rect.position + Vector2(ts * 0.45, ts * 0.55), Color(0.05, 0.04, 0.03), 2.0)
		draw_line(rect.position + Vector2(ts * 0.7, ts * 0.15),
				rect.position + Vector2(ts * 0.5, ts * 0.6), Color(0.05, 0.04, 0.03), 2.0)
		_draw_bld_label(b, rect)
		var font := ThemeDB.fallback_font
		var tag := Loc.t("city.razed_tag")
		var tag_pos := rect.position + Vector2(
				(rect.size.x - font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x) * 0.5, -3.0)
		draw_string_outline(font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3,
				Color(0.2, 0.03, 0.03, 0.9))
		draw_string(font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(1.0, 0.45, 0.4, 0.95))
	else:
		# схематичное здание: заливка категории, тёмная кайма по контуру
		draw_rect(rect, col)
		draw_rect(rect.grow(-2), col.darkened(0.3), false, 2.0)
		if type_id == "tent":
			_draw_tent_awning(rect)   # полосатый навес — торговая читаемость (этап 2)
		_draw_bld_door(b, rect)
		# точка-работник: занятое здание подсвечено
		if int(b["worker"]) > 0:
			draw_circle(rect.position + Vector2(rect.size.x - 6.0, 6.0), 2.5, Color(1, 1, 1, 0.95))
		# яблоневый сад (M10): растёт — полоска стадии, зелёная при спелости
		if type_id == "orchard":
			var stages := float(sim.cfg.get("orchard", {}).get("stages", 3))
			var stage := clampf(float(b.get("apple_stage", 0)) / maxf(1.0, stages), 0.0, 1.0)
			draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 8),
					Vector2((rect.size.x - 8) * stage, 4)),
					Color("#8bc34a") if stage >= 1.0 else Color("#ffe082"))
		_draw_bld_label(b, rect)
	# окно: кто-то спит/лежит внутри — тёплый свет у входа (ночью особенно видно)
	if sim._active(b) and _inside_homes.has(int(b["id"])):
		var door: Vector2 = _bld_door_pos(b, rect)
		var glow := 0.5 + 0.2 * sin(Time.get_ticks_msec() / 350.0)
		draw_circle(door + Vector2(0, -ts * 0.2), ts * 0.28, Color(1.0, 0.85, 0.45, 0.55 + 0.25 * glow))
		draw_circle(door + Vector2(0, -ts * 0.2), ts * 0.12, Color(1.0, 0.93, 0.7, 0.9))
	# кладбище темнеет (M11): тьма ползёт с кладбища, пока некромант работает
	if String(b["type"]) == "cemetery" and bool(b["done"]):
		_draw_graves(anchor - Vector2(0, 0))
		var dark := clampf(float(sim.necro_dark), 0.0, 1.0)
		if dark > 0.02:
			var rings := 4
			for i in rings:
				var rr: float = ts * (0.8 + dark * 2.2) * (float(i + 1) / float(rings))
				draw_circle(anchor - Vector2(0, 4), rr,
						Color(0.08, 0.05, 0.14, 0.05 + 0.1 * dark))
			if sim.necro_known:
				var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 500.0)
				draw_arc(anchor - Vector2(0, 4), ts * (0.9 + dark * 2.0),
						0.0, TAU, 24, Color(0.5, 0.3, 0.7, 0.12 + 0.1 * pulse), 2.0)
		# ночные призывы (M11): скелеты видны у кладбища только ночью
		if sim.is_night() and int(sim.necro_army) > 0:
			var shown: int = mini(3, sim.necro_ghosts.size())
			for g in shown:
				var gpx: Vector2 = sim.necro_ghosts[g]
				var bob := absf(sin(Time.get_ticks_msec() / 320.0 + float(g) * 2.1)) * 2.0
				Assets.draw_ref(self, "k:121", gpx + Vector2(0, -bob),
						ts * 1.1, false, Color(0.75, 0.7, 0.9))
	# зачарование: рамка цветом эффекта (M3)
	if String(b.get("enchant", "")) != "":
		var ecol: Color = enchant_colors.get(String(b["enchant"]), Color(0.8, 0.8, 1.0))
		draw_rect(rect.grow(-1), ecol, false, 2.0)
		draw_circle(rect.position + Vector2(5, 5), 3.0, ecol)
	# дикая вспышка: здание оглушено
	if float(b.get("stun_left", 0.0)) > 0.0:
		draw_rect(rect, Color(0.1, 0.05, 0.15, 0.55))
		var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		draw_arc(rect.get_center(), ts * 0.4, 0.0, TAU, 20,
				Color(0.9, 0.4, 1.0, 0.4 + 0.4 * flash), 2.0)
	# прочность (M5): повреждённое здание показывает полоску (руины — без неё)
	if sim._active(b) and float(b.get("hp", 999.0)) < float(_bld_max_hp(String(b["type"]))):
		var frac2 := clampf(float(b["hp"]) / float(_bld_max_hp(String(b["type"]))), 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(4, -7), Vector2(ts - 8, 4)), Color(0.15, 0.1, 0.1))
		draw_rect(Rect2(rect.position + Vector2(4, -7), Vector2((ts - 8) * frac2, 4)), Color("#8bc34a"))


## Подпись схематичного здания (этап 2, аспект 1): краткое название
## поверх заливки, обводка для читаемости на любом цвете. Стена —
## сплошное кольцо, её тайлы подписями не метятся (шум); ворота подписаны.
const BLD_NO_LABEL := {"wall": true}


## Полосатый навес палатки (этап 2, аспект 4): жёлто-светлые полосы
## поверх заливки категории — «торговое место» читается с одного взгляда.
func _draw_tent_awning(rect: Rect2) -> void:
	var stripe := rect.size.y * 0.28
	var h := rect.size.y * 0.16
	for i in 2:
		var col := Color("#ffd54f") if i % 2 == 0 else Color("#fff3c4")
		draw_rect(Rect2(rect.position.x + 2.0, rect.position.y + stripe * float(i),
				rect.size.x - 4.0, h), col)


func _draw_bld_label(b: Dictionary, rect: Rect2) -> void:
	var type_id := String(b["type"])
	if bool(BLD_NO_LABEL.get(type_id, false)):
		return
	var key: String = _bld_short.get(type_id, "")
	if key == "":
		return
	var text := Loc.t(key)
	if text == key:
		# краткой подписи нет — падаем на полное название, затем на id
		var full_key: String = _bld_loc.get(type_id, "")
		var full := Loc.t(full_key) if full_key != "" else ""
		text = full if full != full_key and full != "" else type_id
	var font := ThemeDB.fallback_font
	var fsize := 8
	var pos := rect.get_center() - Vector2(
			font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x * 0.5, -3.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3,
			Color(0.12, 0.09, 0.05, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 0.96, 0.97))


## Дверной проём (этап 2, аспект 2): тёмная метка на кайме со стороны входа.
func _draw_bld_door(b: Dictionary, rect: Rect2) -> void:
	var door := _bld_door_pos(b, rect)
	var w := rect.size.x * 0.16
	var h := rect.size.y * 0.12
	var horizontal: bool = absf(door.x - rect.get_center().x) > rect.size.x * 0.25
	var r := Rect2(door - Vector2(w if horizontal else h * 0.5, h if horizontal else w * 0.5),
			Vector2(h if horizontal else w, w if horizontal else h))
	draw_rect(r, Color(0.18, 0.13, 0.09, 0.85))


## Точка входа: середина общего ребра между входной клеткой и прямоугольником.
func _bld_door_pos(b: Dictionary, rect: Rect2) -> Vector2:
	var ts := float(map.ts)
	var e: Vector2i = sim.bld_entrance(b)
	if e == Vector2i(-1, -1):
		return Vector2(rect.get_center().x, rect.end.y)
	var t := Vector2i(b["tile"])
	var bw: int = sim.bld_w(b)
	var cx := clampi(e.x, t.x, t.x + bw - 1)
	var cy := clampi(e.y, t.y, t.y + bw - 1)
	var cell_center := Vector2(t) * ts + (Vector2(cx, cy) + Vector2(0.5, 0.5)) * ts
	var e_center := Vector2(e) * ts + Vector2(ts, ts) * 0.5
	return (cell_center + e_center) * 0.5


## Дома с обитателями внутри (спят/лежат/прячутся): id здания → true.
## Собирается один раз за кадр в _draw_world_sorted.
var _inside_homes: Dictionary = {}


## Атакующие (M5 мутанты; M11 духи леса, Древень, скелеты некроманта).
func _draw_raider(r: Dictionary) -> void:
	var refs := {"mutant": "e:mutant", "brute": "e:brute", "spitter": "e:spitter",
			"forest_spirit": "e:spirit", "forest_boss": "e:treant", "skeleton": "k:121"}
	var pos: Vector2 = r["pos"]
	var rad := float(r["p"]["radius"])
	var kind := String(r["type"])
	var ref: String = refs.get(kind, "e:mutant")
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


## Житель (M12: per-object для общего сортированного слоя). Айдл без «марша на
## месте»: движение читается из состояния и пути — раньше флаг moving,
## выставленный в дороге, не сбрасывался у стоящих, и они «маршировали».
## Житель — кружок (правки v1.20): убрали графику, цвет кружка = основная
## специальность; голем-староста — белый; дети — маленькие серо-бежевые.
func _draw_resident(r: Dictionary) -> void:
	var pos: Vector2 = r["pos"]
	var prof := String(r["prof"])
	var child := prof == ""
	var col: Color = sim.resident_color(r)
	var sleeping: bool = r["state"] == "sleep" or r["state"] == "rest"
	# лёгкое покачивание при движении — кружок «живой»
	var pth: PackedVector2Array = r.get("path", PackedVector2Array())
	var moving: bool = not sleeping and not pth.is_empty() \
			and pos.distance_to(pth[pth.size() - 1]) > 2.0
	var phase := float(r["id"]) * 1.7 + _anim_time * (7.0 if moving else 1.5)
	var bob := absf(sin(phase)) * (1.6 if moving else 0.4)
	var radius := 7.0 if child else 9.0
	var ail := String(r.get("ail", ""))
	if ail == "sick":
		col = col.lerp(Color(0.7, 0.95, 0.6), 0.5)
	elif ail == "wounded":
		col = col.lerp(Color(1.0, 0.45, 0.45), 0.5)
	if sleeping:
		col = col.darkened(0.4)
	var center := pos + Vector2(0, -3.0 - bob)
	# тень и кайма читаются на любом фоне
	draw_circle(center + Vector2(0.0, 2.5), radius, Color(0, 0, 0, 0.25))
	draw_circle(center, radius, col.darkened(0.55))
	draw_circle(center, radius - 1.5, col)
	# голем-староста: белое «лицо» камня; житель — тёмный центр-силуэт
	if _is_elder_golem(r):
		draw_circle(center, radius - 3.0, Color(1.0, 1.0, 1.0, 0.95))
		draw_circle(center + Vector2(-2.0, -1.5), 1.1, Color("#3a3f4a"))
		draw_circle(center + Vector2(2.0, -1.5), 1.1, Color("#3a3f4a"))
	else:
		draw_circle(center, radius * 0.42, col.darkened(0.5))
	# груз носильщика (M6): узел цвета ресурса
	if float(r.get("carry", 0.0)) > 0.0:
		var bag: Color = _pile_colors.get(String(r.get("carry_res", "")), Color(0.8, 0.7, 0.5))
		draw_circle(pos + Vector2(radius + 2.0, -4.0), 3.4, bag.darkened(0.1))
		draw_circle(pos + Vector2(radius + 1.2, -4.8), 1.6, bag.lightened(0.15))
	# разговор-облачко (M12): реплика над головой болтающих
	var chat_key := String(r.get("chat_key", ""))
	if chat_key != "" and String(r["state"]) == "chat":
		_draw_speech_bubble(pos, Loc.t(chat_key))


func _is_elder_golem(r: Dictionary) -> bool:
	return String(r.get("prof", "")) == "elder"


## Облачко реплики (M12, имитация жизни): плашка с текстом и хвостиком.
func _draw_speech_bubble(pos: Vector2, text: String) -> void:
	var font := ThemeDB.fallback_font
	var fsize := 10
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + 10.0
	var top := pos + Vector2(-width * 0.5, -58.0)
	var rect := Rect2(top, Vector2(width, 16.0))
	draw_rect(rect, Color(1, 1, 0.96, 0.92))
	draw_rect(rect, Color(0.35, 0.3, 0.25, 0.8), false, 1.0)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-3, -42), pos + Vector2(3, -42), pos + Vector2(0, -36)]),
		Color(1, 1, 0.96, 0.92))
	draw_string(font, top + Vector2(5, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize,
			Color(0.2, 0.16, 0.12))


## Герой в общем сортированном слое (M12): тело и меч рисует сам герой
## в переданный canvas, спрайт-нода в городе скрыта.
func _draw_hero(hero) -> void:
	hero.draw_body(self, hero.global_position)


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
	if move_mode:
		_draw_move_ghost()
		return
	if plaza_mode:
		_draw_plaza_ghost()
		return
	if build_mode == "":
		return
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	var ok: bool = sim.is_buildable_rect(build_mode, tile) and sim.can_afford(_cost_of(build_mode))
	var col := Color(0.5, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	# призрак всего прямоугольника здания (2×2; стены/ворота/мост — 1×1)
	var w := float(sim.bld_w_of_type(build_mode))
	draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts * w, map.ts * w)), col)
	draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts * w, map.ts * w)).grow(-2),
			Color(col.r, col.g, col.b, 0.9), false, 2.0)


## Призрак переноса (этап 2, аспект 5): пока здание не выбрано — подсветка
## здания под курсором (зелёная — годное); после выбора — рамка снимка
## и прямоугольник под мышью (зелёный/красный по правилам места).
func _draw_move_ghost() -> void:
	var ts := float(map.ts)
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	if move_bld_id < 0:
		var b: Dictionary = sim.building_at(tile)
		var ok_b: bool = sim._active(b)
		var hb := Rect2(Vector2(b["tile"]) * ts,
				Vector2(ts * float(sim.bld_w(b)), ts * float(sim.bld_w(b)))) if ok_b \
				else Rect2(Vector2(tile) * ts, Vector2(ts, ts))
		draw_rect(hb.grow(-1), Color(0.5, 1.0, 0.5, 0.8) if ok_b else Color(1.0, 0.3, 0.3, 0.5),
				false, 2.0)
		return
	var picked: Dictionary = {}
	for b2 in sim.buildings:
		if int(b2["id"]) == move_bld_id:
			picked = b2
			break
	if picked.is_empty():
		return
	# рамка выбранного здания пульсирует
	var pw := float(sim.bld_w(picked))
	var pr := Rect2(Vector2(picked["tile"]) * ts, Vector2(ts * pw, ts * pw))
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 220.0)
	draw_rect(pr.grow(-1), Color(1.0, 0.85, 0.3, pulse), false, 2.5)
	# прямоугольник под курсором — годен ли (собственные клетки не мешают)
	var w := float(sim.bld_w_of_type(String(picked["type"])))
	var ok: bool = sim.move_spot_ok(picked, tile)
	var col := Color(0.5, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	draw_rect(Rect2(Vector2(tile) * ts, Vector2(ts * w, ts * w)), col)
	draw_rect(Rect2(Vector2(tile) * ts, Vector2(ts * w, ts * w)).grow(-2),
			Color(col.r, col.g, col.b, 0.9), false, 2.0)


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
			var ok: bool = sim._zone_cell_ok(tile)
			if ok:
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
