# Часть: отрисовка города — пропсы города/кладбища (v1.63, нарезка заказчика,
# 118 шт в assets/sprites/props_city/, ASSETS.md): фонари и указатели у дорог,
# декор площади/рынка/ремесленных дворов, стоги пастбищ, надгробия кладбища,
# спрайтовые кучи ресурсов и брёвна.
# Один класс (цепочка base -> nature -> props -> view). Вся расстановка
# ДЕТЕРМИНИРОВАНА хэшем тайла/id — новой симуляции пропсы не добавляют.
extends "res://scripts/city_view_nature.gd"

# --- справочники ------------------------------------------------------------

## Надгробия готовых могил (обряд «закопать»): выбор по хэшу тайла.
const GRAVE_REFS := [
	"pc:надгробие_арочное", "pc:надгробие_круглое_1", "pc:надгробие_круглое_2",
	"pc:надгробие_с_крестом", "pc:надгробие_со_шпилем", "pc:крест_большой",
	"pc:крест_каменный", "pc:крест_кельтский", "pc:кресты_пара",
]

## Фонари у дорог: 6 видов, тёплое пятно света ночью («свет-якори»,
# РЕФЕРЕНСЫ-СТИЛЬ.md).
const LANTERN_REFS := [
	"pc:фонарь_столб_большой", "pc:фонарь_столб_двойной",
	"pc:фонарь_столб_двойной_растяжка", "pc:фонарь_столб_крестовина",
	"pc:фонарь_столб_на_камне", "pc:фонарь_столб_одинарный",
]

## Статуи-вариации здания «статуя» (по хэшу id здания).
const STATUE_REFS := [
	"pc:статуя_рыцарь", "pc:статуя_рыцарь_в_шлеме", "pc:статуя_в_плаще",
	"pc:статуя_молящийся", "pc:статуя_ангел_большая",
]

## Кучи ресурсов у зданий (v1.63: пропсы вместо тайлов Kenney).
const PROP_PILE := {
	"wood": "pc:ящик_средний", "stone": "pc:бочка_пустая", "food": "pc:мешок_малый",
	"iron": "pc:бочка_широкая", "metal": "pc:ящик_большой", "tools": "pc:бочка_с_краном",
	"kits": "pc:ящик_малый", "crystal": "pc:горшок_кристалл", "seeds": "pc:мешок_малый",
	"gems": "pc:горшок_монеты", "coins": "pc:слитки_золота", "gold": "pc:слитки_золота",
	"silver": "pc:слитки_золота", "copper": "pc:слитки_золота", "pearls": "pc:амфора_2",
	"amber": "pc:горшок_ягоды", "alcohol": "pc:бочка_зелье", "lux": "pc:горшок_розовый",
	"saplings": "pc:горшок_цветок", "fish": "pc:кадка_вода",
}

# кэш статики пропсов: пересборка при смене рельефа/числа зданий/дорог/зон
var _props_cache: Array = []
var _props_key := ""


## Статичные записи пропсов для сортированного слоя (звено nature зовёт
## через _props_static()). Каждая запись: [y_px, "prop", {ref, tile, h, flip, light}].
func _props_static() -> Array:
	var key := "%d:%d:%d:%d" % [int(map.grid_ver), sim.buildings.size(),
			map.road.size(), sim.zones.size()]
	if key == _props_key:
		return _props_cache
	_props_key = key
	_props_cache = []
	var ts := float(map.ts)
	# 1) улицы: фонари на дорогах (каждый lantern_every-N тайл по хэшу)
	for t: Vector2i in map.road.keys():
		if _hash(t.x, t.y, 6) != 0:
			continue
		var ref: String = LANTERN_REFS[_hash(t.x, t.y, LANTERN_REFS.size(), 7)]
		_props_rec(t, ref, ts * 2.3, _hash(t.x, t.y, 2, 3) == 0, true)
	# 2) площадь: скамейки и столбы у главной площади, знак у выхода в мир
	if sim.plaza != Vector2i(-1, -1):
		_props_place(sim.plaza + Vector2i(-1, 1), "pc:скамейка_длинная", ts * 0.85)
		_props_place(sim.plaza + Vector2i(2, 1), "pc:скамейка_со_спинкой", ts * 0.85)
		_props_place(sim.plaza + Vector2i(-1, -1), "pc:столб_декоративный", ts * 1.1)
		_props_place(sim.plaza + Vector2i(2, -1), "pc:горшки_цветы_ярус", ts * 0.7)
		_props_place(sim.plaza + Vector2i(3, 1), "pc:знак_двойной", ts * 0.9)
		_props_place(map.world_exit_tile + Vector2i(0, 1), "pc:указатель", ts * 1.0)
	# 3) декор строений: вход + смещение влево/вправо (по хэшу зеркалится)
	for b in sim.buildings:
		if not bool(b["done"]):
			# стройплощадка: козлы плотника у входа
			_props_place(sim.bld_spot(b) + Vector2i(_hash(int(b["id"]), 0, 2) * 2 - 1, 0),
					"pc:козлы_плотницкие", ts * 0.7)
			continue
		if bool(b.get("razed", false)):
			continue
		var type_id := String(b["type"])
		var spot: Vector2i = sim.bld_spot(b)
		var left := spot + Vector2i(-1, 0)
		var right := spot + Vector2i(1, 0)
		match type_id:
			"market":
				_props_place(right, "pc:прилавок_двойной", ts * 1.0)
				_props_place(left, "pc:мешки_штабель", ts * 0.85)
				_props_place(spot + Vector2i(0, 1), "pc:телега_с_мешками", ts * 1.1)
			"tent":
				_props_place(right, "pc:ларь", ts * 0.8)
				_props_place(left, "pc:ящик_малый", ts * 0.55)
			"tavern":
				_props_place(right, "pc:вывеска_с_плащом", ts * 1.1)
			"well":
				_props_place(left, "pc:лавка_бревно", ts * 0.6)
				_props_place(right, "pc:горшок_розовый", ts * 0.55)
			"forge":
				_props_place(left, "pc:горн_печь", ts * 0.95)
				_props_place(right, "pc:наковальня_на_колоде", ts * 0.7)
			"armory":
				_props_place(left, "pc:стойка_с_оружием", ts * 1.0)
				_props_place(right, "pc:мишень_1", ts * 0.9)
			"workshop":
				_props_place(left, "pc:верстак", ts * 0.8)
				_props_place(right, "pc:ящик_бутыли", ts * 0.7)
			"sawmill":
				_props_place(left, "pc:колода_с_топором", ts * 0.6)
				_props_place(right, "pc:козлы_плотницкие", ts * 0.7)
			"cemetery":
				# стражи кладбища: ангел и рыцарь по нижним углам
				var bw: int = sim.bld_w(b)
				_props_place(Vector2i(b["tile"]) + Vector2i(-1, bw - 1),
						"pc:статуя_ангел_крылья", ts * 1.2)
				_props_place(Vector2i(b["tile"]) + Vector2i(bw, bw - 1),
						"pc:статуя_рыцарь_в_шлеме", ts * 1.2)
			"garden":
				_props_place(left, "pc:грядка_жёлтые_цветы", ts * 0.55)
				_props_place(right, "pc:грядка_красные_цветы", ts * 0.55)
	# 4) село: стоги на пастбищах (каждая 6-я клетка по хэшу, 4 вида)
	for z in sim.zones:
		if String(z["type"]) != "pasture":
			continue
		for c: Vector2i in z["cells"]:
			if _hash(c.x, c.y, 6) != 0:
				continue
			var pick: int = _hash(c.x, c.y, 4, 11)
			var ref: String = "pc:стог"
			if pick == 1:
				ref = "pc:стог_большой"
			elif pick == 2:
				ref = "pc:стог_малый"
			elif pick == 3:
				ref = "pc:стенд_на_стоге"
			_props_rec(c, ref, ts * (1.1 if pick == 1 else 0.9), false, false)
	_props_cache.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	return _props_cache


## Запись пропса на тайл (без проверки занятости — декор). Свет — фонарь.
func _props_rec(tile: Vector2i, ref: String, h: float, flip := false, light := false) -> void:
	var y := float(tile.y) * float(map.ts) + float(map.ts) * 0.92 - _static_lift(tile)
	_props_cache.append([y, "prop", {"ref": ref, "tile": tile, "h": h,
			"flip": flip, "light": light}])


## Запись с проверкой: тайл в границах и не внутри чужого здания.
func _props_place(tile: Vector2i, ref: String, h: float) -> void:
	if not map.in_bounds(tile) or not sim.building_at(tile).is_empty():
		return
	_props_rec(tile, ref, h, _hash(tile.x, tile.y, 2, 5) == 0, false)


## Отрисовка пропса: контактная тень у «ног» + спрайт; фонарь ночью льёт
## тёплое пятно света (плавное затухание к рассвету).
func _draw_prop(p: Dictionary) -> void:
	var tile: Vector2i = p["tile"]
	var bottom: Vector2 = map.tile_center_px(tile) + Vector2(0, float(map.ts) * 0.42)
	if not _vis.grow(float(map.ts)).has_point(bottom):
		return   # за экраном
	var w := Assets.ref_size(String(p["ref"]), float(p["h"])).x
	_draw_shadow(bottom, w * 0.55)
	Assets.draw_ref(self, String(p["ref"]), bottom - Vector2(0, float(p["h"]) * 0.5),
			float(p["h"]), bool(p["flip"]))
	if bool(p.get("light", false)) and night > 0.03:
		var flick := 0.9 + 0.1 * sin(_anim_time * 6.0 + float(tile.x))
		var head := bottom - Vector2(0, float(p["h"]) * 0.86)
		draw_circle(head, float(map.ts) * 1.35 * flick,
				Color(1.0, 0.82, 0.5, 0.12 * night))
		draw_circle(head, float(map.ts) * 0.55,
				Color(1.0, 0.9, 0.65, 0.22 * night))


# --- оверрайды примитивов (виртуальная диспетчеризация из nature/view) --------

## Могилы (v1.63): закопанные — надгробия/кресты из пака, идёт похоронная
## процессия — открытый гроб, сожжённый — крышка саркофага; погребальный
## костёр до готовности остаётся живым пламенем.
func _draw_graves(anchor: Vector2) -> void:
	var radius_px: float = float(sim.cfg.get("cemetery", {}).get("grow_radius", 5)) * float(map.ts) + float(map.ts)
	var ts := float(map.ts)
	for g in sim.graves:
		var tile: Vector2i = Vector2i(g["tile"])
		var pos: Vector2 = map.tile_center_px(tile)
		if pos.distance_to(anchor) > radius_px:
			continue
		var bottom := pos + Vector2(0, ts * 0.42)
		if String(g.get("rite", "bury")) == "burn" and not bool(g.get("ready", false)):
			# погребальный костёр: столб и живое пламя
			draw_line(pos + Vector2(0, 2), pos + Vector2(0, -14), Color("#5d4037"), 3.0)
			var flame := 0.6 + 0.4 * sin(_anim_time * 8.0 + pos.x)
			draw_circle(pos + Vector2(0, -12), 5.0 * flame, Color(1.0, 0.55, 0.2, 0.8))
			draw_circle(pos + Vector2(0, -16), 3.0 * flame, Color(1.0, 0.75, 0.3, 0.7))
			continue
		var ref: String = ""
		var h := ts * 0.8
		if String(g.get("rite", "bury")) == "burn":
			if bool(g.get("ready", false)):
				ref = "pc:крышка_гроба"   # прах под каменной крышкой
				h = ts * 0.5
		elif bool(g.get("ready", false)):
			ref = GRAVE_REFS[_hash(tile.x, tile.y, GRAVE_REFS.size(), 13)]
		else:
			ref = "pc:гроб"   # похороны идут — гроб у могилы
			h = ts * 0.5
		_draw_shadow(bottom, ts * 0.3)
		Assets.draw_ref(self, ref, bottom - Vector2(0, h * 0.5), h,
				_hash(tile.x, tile.y, 2, 17) == 0)


## Кладбище без здания (v1.23 → v1.63): деревянные кресты по углам и
## ограда-секции по бокам, пока горожане не поставят настоящее кладбище.
func _draw_founded_cemetery() -> void:
	if sim.cemetery_tile == Vector2i(-1, -1):
		return
	for b in sim.buildings:
		if sim._active(b) and String(b["type"]) == "cemetery":
			return
	var ts := float(map.ts)
	var c: Vector2i = sim.cemetery_tile
	for n: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var t: Vector2i = c + n
		var bottom: Vector2 = map.tile_center_px(t) + Vector2(0, ts * 0.42)
		var ref := "pc:крест_деревянный_малый" if (n.x + n.y) % 2 == 0 else "pc:крест_деревянный_высокий"
		_draw_shadow(bottom, ts * 0.26)
		Assets.draw_ref(self, ref, bottom - Vector2(0, ts * 0.4), ts * 0.8,
				_hash(t.x, t.y, 2, 19) == 0)
	_draw_graves(map.tile_center_px(c))


## Поваленное бревно (v1.21.2 → v1.63): связка/стопка/штабель по размеру
## дерева; тень у «ног» сохранена.
func _draw_log_at(tile: Vector2i) -> void:
	var ts := float(map.ts)
	var bottom: Vector2 = map.tile_center_px(tile) + Vector2(0, ts * 0.24)
	bottom.y -= _static_lift(tile)
	var size: int = int((map.logs[tile] as Dictionary).get("size", 1))
	var ref := "pc:брёвна_связка"
	var h := ts * 0.5
	if size == 2:
		ref = "pc:брёвна_стопка"
		h = ts * 0.6
	elif size >= 3:
		ref = "pc:штабель_брёвен"
		h = ts * 0.75
	var w := Assets.ref_size(ref, h).x
	_draw_shadow(bottom + Vector2(0, 2), w * 0.6)
	Assets.draw_ref(self, ref, bottom - Vector2(0, h * 0.5), h)


## Куча ресурса у здания (M6 → v1.63): пропс по типу ресурса, размер растёт
## с объёмом; тайлы Kenney остались фолбэком.
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
	corner.y -= _bld_lift(b)
	var size := 11.0 + minf(11.0, total / 3.0)
	var ref := String(PROP_PILE.get(key, ""))
	if ref == "":
		var tint: Color = _pile_colors.get(key, Color(0.8, 0.8, 0.8)).lightened(0.25)
		Assets.draw_ref(self, PILE_SPRITES.get(key, "k:73"), corner, size, false, tint)
		return
	_draw_shadow(corner + Vector2(0, 3), ts * 0.24)
	Assets.draw_ref(self, ref, corner - Vector2(0, size * 0.5), size)
