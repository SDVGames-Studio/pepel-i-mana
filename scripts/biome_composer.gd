extends Control
## КОМПОЗИТОР БИОМОВ v2 (v1.78.5, спецификация заказчика):
## 1) библиотека читает ИСХОДНЫЕ листы заказчика НАПРЯМУЮ (Image.load_from_file,
##    мимо импорт-системы редактора) — в кнопках ВСЕ тайлы листа (до 48 клеток),
##    никакой выборки и никаких «куцых» библиотек;
## 2) сверху КНОПКИ БИОМОВ — клик открывает тайлы/воду/деревья этого листа;
##    клик по тайлу добавляет его в сборку (повторный — убирает), мешать
##    можно из разных листов;
## 3) разные тайлы СРАСТАЮТСЯ КРАЯМИ: единый тон набора + детерминированный
##    дизеринг кромки (Assets.uniform_ground_imgs) — границы растворяются.
##
## Сохранение: печатает grass_N.png + water.png в
## user://biomes_composed/<имя>/ и пишет biome.json — город грузит патчи
## напрямую с диска (Assets.tex умеет user://), биом работает СРАЗУ после
## сохранения: без переимпорта редактора и в экспорте тоже.
## Превью 20×20 справа — что видишь, то и в игре.

const TILES := 20
const TS := 32
const MAX_GRASS := 24
const MAX_TREES := 5
const TREE_SPOTS: Array = [Vector2i(3, 3), Vector2i(15, 4), Vector2i(4, 15),
		Vector2i(15, 15), Vector2i(9, 17)]

# v1.78.7: КАЖДАЯ ВКЛАДКА — СВОЙ БИОМ И СВОЁ СОХРАНЕНИЕ (поручение
# заказчика: «тыкаю на лето — составляю — сохраняю; тыкаю на осень —
# составляю — сохраняю; и так для каждого биома, а не одно сохранение
# для всего»). Сезон вкладки проставляется сам: лето → summer и т.д.
# — сохранённый биом вкладки СРАЗУ становится обликом города в этот сезон.
const SHEET_SEASON := {"лето": "summer", "весна": "spring",
	"осень": "autumn", "зима": "winter"}

# Исходные листы заказчика: (метка, папка, файл). v1.78.5: композитор
# сам нарезает клетки из листов — слайсеры нужны только для вшитых биомов.
const SHEET_BASE := "F:/востановление кхорно юнитов/assets/ассеты домов/новые ассеты монстров"
const SHEETS := [
	["лето", "Биомы лето", "Пиксельный атлас лесных и водных тайловета.png"],
	["весна", "биом весна", "Пиксельный атлас весеннего леса и водоёмов.png"],
	["осень", "БИОМ ОСЕНЬ", "Осенний пиксельный тайлсет для RPG.png"],
	["зима", "биомы зима", "Зимний пиксельный атлас тайлов и объектов.png"],
	["болота", "биом болота", "Пиксельный атлас болотных тайлов.png"],
	["берёзовая роща", "биом березовая роща", "Осенний берёзовый лес — тайлсет sprites.png"],
	["древний лес", "биом древний лес", "Пиксельный атлас мрачного леса.png"],
	["мёртвый лес", "биом мертвый лес", "Пиксельный атлас мёртвого леса.png"],
	["мистический лес", "биом мистический лес", "Пиксельный атлас зачарованного леса.png"],
	["огненные земли", "биом огненый", "Пиксельный атлас вулканических земель.png"],
	["проклятый лес", "биом проклетый лес", "Атлас пиксельных спрайтов проклятого леса.png"],
	["пустыня", "биом пустыня", "Пиксельный атлас пустынных тайлов и руин.png"],
	["степи", "биом степи", "Пиксельный атлас степных тайлов и декораций.png"],
	["скалы", "биомы скалы", "Фэнтезийный атлас горных и водных тайлов.png"],
	["цветущий край", "биомы цветуший край и речной", "Пиксельный атлас фантастического мира-1.png"],
]
# Летние деревья — принятые нарезки (город их уже показывает).
const SUMMER_TREES := ["e:tree2_summer_oak", "e:tree2_summer_pine",
	"e:tree2_summer_birch", "e:tree2_summer_willow", "e:tree2_summer_dead"]

var _sources: Array = []        # [{label, sheet, trees[]}]
var _active := 0
var _sheet_cache := {}          # путь листа -> Image (загружен с диска)
var _analysis := {}             # путь листа -> {cells[], water{}, found}
var _clean_cache := {}          # "лист|cx,cy" -> Image (шашечка снята)
var _workspaces := {}           # v1.78.7: путь листа -> сборка ЭТОЙ вкладки
var _active_sheet := ""         # лист открытой вкладки
var _sel_grass: Array = []      # [{"sheet", "cx", "cy"}]
var _sel_water := {}            # {"sheet", "cells": [Vector2i]} или {}
var _sel_trees: Array = []      # спрайт-рефы деревьев
var _season := ""
var _t := 0.0

var _preview: Control = null
var _preview_tex: ImageTexture = null
var _water_cells: Array = []
var _water_frame_texs: Array = []   # v1.78.5: кадры воды — ТЕКСТУРЫ вне draw
                                    # (создание ImageTexture внутри _draw
                                    # рисует белым — данные не успевают)
var _status: Label = null
var _name_edit: LineEdit = null
var _season_btn: OptionButton = null
var _lib_box: VBoxContainer = null
var _lib_scroll: ScrollContainer = null
var _tray: HBoxContainer = null
var _ver := "?"


func _ready() -> void:
	const UITheme = preload("res://scripts/ui_theme.gd")
	var vf := FileAccess.open("res://data/version.json", FileAccess.READ)
	if vf != null:
		var vd: Variant = JSON.parse_string(vf.get_as_text())
		if vd is Dictionary:
			_ver = String(vd.get("version", "?"))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.12, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# --- верх: КНОПКИ БИОМОВ (спецификация п.2)
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 64.0
	add_child(top)
	var tscroll := ScrollContainer.new()
	tscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	top.add_child(tscroll)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tscroll.add_child(tabs)
	_load_sources()
	for i in range(_sources.size()):
		var e: Dictionary = _sources[i]
		var b := Button.new()
		b.text = String(e.get("label", "?"))
		b.toggle_mode = true
		b.button_pressed = i == 0
		b.custom_minimum_size = Vector2(120, 40)
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE
		UITheme.apply_button(b)
		var ci := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_open_biome(ci))
		tabs.add_child(b)

	# --- левая колонка: библиотека открытого листа + выбор + кнопки
	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_top = 72.0
	left.offset_right = 560.0
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Loc.t("composer.name_ph")
	_name_edit.custom_minimum_size = Vector2(320, 36)
	lv.add_child(_name_edit)
	_season_btn = OptionButton.new()
	for s in ["—", "весна", "лето", "осень", "зима"]:
		_season_btn.add_item(s)
	_season_btn.custom_minimum_size = Vector2(150, 36)
	_season_btn.item_selected.connect(func(i: int) -> void:
		_season = ["", "spring", "summer", "autumn", "winter"][i])
	lv.add_child(_season_btn)

	# v1.78.5: библиотека листа до 48 клеток — скролл
	_lib_scroll = ScrollContainer.new()
	_lib_scroll.custom_minimum_size = Vector2(520, 360)
	_lib_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lib_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	lv.add_child(_lib_scroll)
	_lib_box = VBoxContainer.new()
	_lib_box.add_theme_constant_override("separation", 6)
	_lib_scroll.add_child(_lib_box)
	_open_biome(0)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	_status.text = Loc.t("composer.picked") % [0, MAX_GRASS, 0, MAX_TREES]
	lv.add_child(_status)

	var tray_cap := Label.new()
	tray_cap.text = Loc.t("composer.tray")
	tray_cap.add_theme_font_size_override("font_size", 13)
	lv.add_child(tray_cap)
	var tray_scroll := ScrollContainer.new()
	tray_scroll.custom_minimum_size = Vector2(520, 70)
	tray_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tray_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(tray_scroll)
	_tray = HBoxContainer.new()
	_tray.add_theme_constant_override("separation", 6)
	tray_scroll.add_child(_tray)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	lv.add_child(btns)
	for pair in [["composer.save", "_on_save"], ["composer.clear", "_on_clear"],
			["composer.back", "_on_back"]]:
		var b2 := Button.new()
		b2.text = Loc.t(String(pair[0]))
		b2.custom_minimum_size = Vector2(150, 40)
		b2.add_theme_font_size_override("font_size", 15)
		b2.focus_mode = Control.FOCUS_NONE
		UITheme.apply_button(b2)
		b2.pressed.connect(Callable(self, String(pair[1])))
		btns.add_child(b2)

	var vlbl := Label.new()
	vlbl.text = "v" + _ver
	vlbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	vlbl.offset_left = -120.0
	vlbl.offset_top = -30.0
	vlbl.add_theme_font_size_override("font_size", 14)
	vlbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6))
	add_child(vlbl)
	# --- правая зона: живой превью (FULL_RECT + offsets: RIGHT_WIDE с
	# offset_left=580 уезжал за правый край окна — превью не рисовалось)
	_preview = Control.new()
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview.offset_left = 580.0
	_preview.offset_top = 72.0
	_preview.offset_right = -20.0
	_preview.offset_bottom = -40.0
	_preview.draw.connect(_draw_preview)
	add_child(_preview)
	set_process(true)


## Источники: 15 листов заказчика (лето + 14 папок «биом/биомы»).
## Деревья — нарезанные манифестные (res://, надёжны в экспорте).
func _load_sources() -> void:
	_sources = []
	var mf := Assets.biome_manifest()
	for s in SHEETS:
		var label := String(s[0])
		var trees: Array = []
		if label == "лето":
			trees = SUMMER_TREES.duplicate()
		elif mf.has(label):
			trees = (mf[label] as Dictionary).get("trees", [])
		_sources.append({
			"label": label,
			"sheet": SHEET_BASE + "/" + String(s[1]) + "/" + String(s[2]),
			"trees": trees,
		})


func _sheet_img(path: String) -> Image:
	if _sheet_cache.has(path):
		return _sheet_cache[path]
	var im := Image.load_from_file(path)
	if im != null and im.is_empty():
		im = null
	_sheet_cache[path] = im
	return im


## Анализ листа (кэш): полные клетки (альфа>200 по всей 32×32, сэмпл шаг 2),
## средний цвет, вода/не-вода + длиннейшая горизонтальная серия воды.
func _analyze_sheet(path: String) -> Dictionary:
	if _analysis.has(path):
		return _analysis[path]
	var res := {"cells": [], "water": {}, "found": false}
	var img := _sheet_img(path)
	if img == null:
		_analysis[path] = res
		return res
	res["found"] = true
	var W := img.get_width()
	var H := img.get_height()
	var data := img.get_data()
	var cells: Array = []
	for cy in range(H / TS):
		for cx in range(W / TS):
			var amin := 255
			var sm := Vector3(0, 0, 0)
			var n := 0
			var is_light_px := 0        # светлые нейтральные (шашечка/белое)
			var lum_lo := 999.0
			var lum_hi := -1.0
			for y in range(0, TS, 2):
				var row := (cy * TS + y) * W * 4
				for x in range(0, TS, 2):
					var i := row + (cx * TS + x) * 4
					var a: int = data[i + 3]
					if a < amin:
						amin = a
					var r: int = data[i]
					var g: int = data[i + 1]
					var b: int = data[i + 2]
					sm.x += r
					sm.y += g
					sm.z += b
					n += 1
					var mx := maxi(r, maxi(g, b))
					var mn := mini(r, mini(g, b))
					if mx > 170 and mx - mn < 14:
						is_light_px += 1
						var pl := float(mx)
						lum_lo = minf(lum_lo, pl)
						lum_hi = maxf(lum_hi, pl)
			if amin > 200:
				var m := sm / float(n)
				var lum := m.x * 0.299 + m.y * 0.587 + m.z * 0.114
				# v1.78.5: клетки с НАРИСОВАННОЙ шашечкой вместо альфы
				# (весенний лист): почти вся клетка — светлые нейтральные
				# пиксели ДВУХ тонов (шахматное чередование) — это фон
				# листа, а не тайл; в библиотеку не попадает
				var light_spread := lum_hi - lum_lo
				if is_light_px * 4 > n * 3 and light_spread > 12.0:
					continue
				cells.append({
					"cx": cx, "cy": cy, "mean": m, "lum": lum,
					"water": m.z > m.x + 10.0 and m.z > m.y + 10.0,
				})
	# земля: сортировка по (ряд, колонка) — заказ листа; БЕЗ лимита —
	# в библиотеке композитора все тайлы листа (пожелание заказчика)
	var ground := []
	for c in cells:
		if not bool(c["water"]):
			ground.append(c)
	ground.sort_custom(func(a, b) -> bool:
		if int(a["cy"]) != int(b["cy"]):
			return int(a["cy"]) < int(b["cy"])
		return int(a["cx"]) < int(b["cx"]))
	res["cells"] = ground
	# вода: длиннейшая серия синих клеток в строке. Светлотный порог 70
	# (осенние листы с запечённой тёмной рамкой) душит тёмную воду лета —
	# v1.78.5: порог 42 (тёмный фон листа почти чёрный, lum < 30)
	var rows := {}
	for c in cells:
		if bool(c["water"]) and float(c["lum"]) > 42.0:
			if not rows.has(int(c["cy"])):
				rows[int(c["cy"])] = []
			(rows[int(c["cy"])] as Array).append(int(c["cx"]))
	var best: Array = []
	var best_y := -1
	for cy in rows:
		var xs: Array = rows[cy]
		xs.sort()
		var run: Array = [xs[0]]
		for k in range(1, xs.size()):
			if int(xs[k]) == int(xs[k - 1]) + 1:
				run.append(xs[k])
			else:
				if run.size() > best.size():
					best_y = cy
					best = run
				run = [xs[k]]
		if run.size() > best.size():
			best_y = cy
			best = run
	if best_y >= 0 and best.size() >= 3:
		var wc: Array = []
		for cx in best:
			wc.append(Vector2i(cx, best_y))
		res["water"] = {"sheet": path, "cells": wc}
	_analysis[path] = res
	return res


func _cell_img(path: String, cx: int, cy: int) -> Image:
	var img := _sheet_img(path)
	if img == null:
		return null
	return img.get_region(Rect2i(cx * TS, cy * TS, TS, TS))


## Чистка клетки (v1.78.5): у части листов заказчика вместо альфы НАРИСОВАНА
## шашечка (светло-серый/белый шахматный фон). Пиксель считается шашечным,
## если он светлый нейтральный (max>170, разброс каналов<14) И его пара на
## ±8px — светлый нейтральный ДРУГОГО тона (шахматное чередование; снег и
## цветы пар не имеют — не затрагиваются). Шашечка снимается ЗАЛИВКОЙ ОТ
## КРАЁВ клетки — белые цветы внутри травы заливка не достигает.
func _clean_cell(path: String, cx: int, cy: int) -> Image:
	var key := "%s|%d,%d" % [path, cx, cy]
	if _clean_cache.has(key):
		return _clean_cache[key]
	var im := _cell_img(path, cx, cy)
	if im == null:
		_clean_cache[key] = null
		return null
	var W := im.get_width()
	var H := im.get_height()
	var data := im.get_data()
	var mask := PackedByteArray()
	mask.resize(W * H)
	for y in range(H):
		var row := y * W
		for x in range(W):
			var i := (row + x) * 4
			var r: int = data[i]
			var g: int = data[i + 1]
			var b: int = data[i + 2]
			var mx := maxi(r, maxi(g, b))
			var mn := mini(r, mini(g, b))
			if mx <= 170 or mx - mn >= 14:
				continue
			var sum1 := r + g + b
			for d in [[8, 0], [-8, 0], [0, 8], [0, -8]]:
				var nx := x + int(d[0])
				var ny := y + int(d[1])
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := (ny * W + nx) * 4
				var r2: int = data[j]
				var g2: int = data[j + 1]
				var b2: int = data[j + 2]
				var mx2 := maxi(r2, maxi(g2, b2))
				var mn2 := mini(r2, mini(g2, b2))
				if mx2 > 170 and mx2 - mn2 < 14 \
						and absi(sum1 - (r2 + g2 + b2)) >= 36:
					mask[row + x] = 1
					break
	# заливка от краёв клетки по шашечным пикселям
	var queue: Array = []
	for x in range(W):
		for ye in [0, H - 1]:
			if mask[ye * W + x] == 1:
				mask[ye * W + x] = 2
				queue.append(Vector2i(x, ye))
	for y in range(H):
		for xe in [0, W - 1]:
			if mask[y * W + xe] == 1:
				mask[y * W + xe] = 2
				queue.append(Vector2i(xe, y))
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		for d2 in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx2 := p.x + int(d2[0])
			var ny2 := p.y + int(d2[1])
			if nx2 < 0 or ny2 < 0 or nx2 >= W or ny2 >= H:
				continue
			var idx2 := ny2 * W + nx2
			if mask[idx2] == 1:
				mask[idx2] = 2
				queue.append(Vector2i(nx2, ny2))
	# шашечка -> прозрачная; остальное — как в листе
	var holes := 0
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y2 in range(H):
		for x2 in range(W):
			var idx3 := y2 * W + x2
			var i3 := idx3 * 4
			if mask[idx3] == 2:
				out.set_pixel(x2, y2, Color(0, 0, 0, 0))
				holes += 1
			else:
				out.set_pixel(x2, y2, Color8(data[i3], data[i3 + 1],
						data[i3 + 2], data[i3 + 3]))
	# клетка почти целиком была шашечкой — пометить как «фон»
	if holes * 10 > W * H * 8:
		out = null
	_clean_cache[key] = out
	return out


func _cell_tex(path: String, cx: int, cy: int) -> ImageTexture:
	var im := _clean_cell(path, cx, cy)
	return ImageTexture.create_from_image(im) if im != null else null


## Спрятать сборку текущей вкладки в workspace (v1.78.7: у каждой
## вкладки свой набор тайлов — не одно общее сохранение).
func _store_workspace() -> void:
	if _active_sheet == "":
		return
	_workspaces[_active_sheet] = {
		"grass": _sel_grass.duplicate(true),
		"water": _sel_water.duplicate(true),
		"trees": _sel_trees.duplicate(true),
		"name": _name_edit.text,
		"season": _season,
	}


## Загрузить сборку вкладки: из workspace этой сессии или из сохранённого
## biome.json (клетки листа восстановятся — выбор продолжается с того же
## места).
func _load_workspace(sheet: String) -> void:
	var label := String(_sources[_active].get("label", ""))
	var ws: Dictionary = _workspaces.get(sheet, {})
	if ws.is_empty():
		var bf := FileAccess.open(
				"user://biomes_composed/%s/biome.json" % label, FileAccess.READ)
		if bf != null:
			var parsed: Variant = JSON.parse_string(bf.get_as_text())
			if parsed is Dictionary:
				var cells: Array = (parsed as Dictionary).get("cells", [])
				for c in cells:
					_sel_grass.append({
						"sheet": String(c.get("sheet", sheet)),
						"cx": int(c.get("cx", 0)),
						"cy": int(c.get("cy", 0)),
					})
				var wc: Dictionary = (parsed as Dictionary).get("water_cells", {})
				if not (wc.get("cells", []) as Array).is_empty():
					var wlist: Array = []
					for c2 in wc.get("cells", []):
						# JSON: Vector2i -> {"x": .., "y": ..}
						var cc: Variant = c2
						if cc is Dictionary:
							wlist.append(Vector2i(int(cc.get("x", 0)),
									int(cc.get("y", 0))))
						elif cc is Vector2i:
							wlist.append(cc)
					_sel_water = {"sheet": String(wc.get("sheet", sheet)),
							"cells": wlist}
				_sel_trees = (parsed as Dictionary).get("trees", [])
				var ssn: String = String((parsed as Dictionary).get("season", ""))
				_season = ssn
				_season_btn.select(maxi(0, ["", "spring", "summer",
						"autumn", "winter"].find(_season)))
				_name_edit.text = String((parsed as Dictionary).get("label", ""))
				_workspaces[sheet] = {
					"grass": _sel_grass.duplicate(true),
					"water": _sel_water.duplicate(true),
					"trees": _sel_trees.duplicate(true),
					"name": _name_edit.text,
					"season": _season,
				}
		return
	_sel_grass = (ws.get("grass", []) as Array).duplicate(true)
	_sel_water = (ws.get("water", {}) as Dictionary).duplicate(true)
	_sel_trees = (ws.get("trees", []) as Array).duplicate(true)
	_name_edit.text = String(ws.get("name", ""))
	_season = String(ws.get("season", ""))
	var sidx := ["", "spring", "summer", "autumn", "winter"].find(_season) \
			if _season != "" else 0
	_season_btn.select(maxi(0, sidx))


## Открыть вкладку-биом: своя сборка у каждой (v1.78.7). Перед
## переключением состояние текущей вкладки прячется в workspace,
## открываемая — восстанавливается (или подгружается из сохранённого).
func _open_biome(i: int) -> void:
	_store_workspace()
	_active = clampi(i, 0, _sources.size() - 1)
	for ch in _lib_box.get_children():
		ch.queue_free()
	var e: Dictionary = _sources[_active]
	var sheet := String(e.get("sheet", ""))
	_active_sheet = sheet
	_load_workspace(sheet)
	var an := _analyze_sheet(sheet)
	var label := String(e.get("label", "?"))
	var saved := FileAccess.file_exists(
			"user://biomes_composed/%s/biome.json" % label)
	var cap := Label.new()
	cap.text = Loc.t("composer.biome_header") % label \
			+ ("  · сохранён" if saved else "")
	cap.add_theme_font_size_override("font_size", 18)
	cap.add_theme_color_override("font_color",
			Color(0.7, 0.95, 0.7) if saved else Color(0.95, 0.85, 0.6))
	_lib_box.add_child(cap)

	if not bool(an["found"]):
		var miss := Label.new()
		miss.text = "лист не найден:\n" + sheet
		miss.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
		miss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lib_box.add_child(miss)

	var cells: Array = an["cells"]
	if not cells.is_empty():
		var gcap := Label.new()
		gcap.text = Loc.t("composer.grass_cap") + "  (%d)" % cells.size()
		gcap.add_theme_font_size_override("font_size", 13)
		_lib_box.add_child(gcap)
		var grid := GridContainer.new()
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		_lib_box.add_child(grid)
		for c in cells:
			_add_cell_pick(grid, sheet, int(c["cx"]), int(c["cy"]))

	var water: Dictionary = an["water"]
	if not (water.get("cells", []) as Array).is_empty():
		var wcap := Label.new()
		wcap.text = Loc.t("composer.water_cap")
		wcap.add_theme_font_size_override("font_size", 13)
		_lib_box.add_child(wcap)
		var wrow := HBoxContainer.new()
		_lib_box.add_child(wrow)
		_add_water_pick(wrow, water)

	var trees: Array = e.get("trees", [])
	if not trees.is_empty():
		var tcap := Label.new()
		tcap.text = Loc.t("composer.trees_cap")
		tcap.add_theme_font_size_override("font_size", 13)
		_lib_box.add_child(tcap)
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		_lib_box.add_child(trow)
		for tr in trees:
			_add_ref_pick(trow, String(tr), "tree", Vector2(64, 80))


## Кнопка клетки листа: иконка = сам регион листа; клик — в сборку.
func _add_cell_pick(parent: Control, sheet: String, cx: int, cy: int) -> void:
	var tex := _cell_tex(sheet, cx, cy)
	if tex == null:
		var nb := Button.new()
		nb.custom_minimum_size = Vector2(64, 64)
		nb.text = "!"
		nb.modulate = Color(1, 0.3, 0.3)
		nb.disabled = true
		parent.add_child(nb)
		return
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 64)
	b.icon = tex
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "клетка %d,%d" % [cx, cy]
	var picked := func() -> bool:
		for g in _sel_grass:
			if String(g["sheet"]) == sheet and int(g["cx"]) == cx and int(g["cy"]) == cy:
				return true
		return false
	b.modulate = Color.WHITE if picked.call() else Color(1, 1, 1, 0.45)
	b.pressed.connect(func() -> void:
		var cur := false
		for g in _sel_grass:
			if String(g["sheet"]) == sheet and int(g["cx"]) == cx and int(g["cy"]) == cy:
				_sel_grass.erase(g)
				cur = true
				break
		if not cur and _sel_grass.size() < MAX_GRASS:
			_sel_grass.append({"sheet": sheet, "cx": cx, "cy": cy})
		_after_toggle())
	parent.add_child(b)


## Кнопка воды листа: иконка — первый кадр авто-полосы.
func _add_water_pick(parent: Control, water: Dictionary) -> void:
	var cells: Array = water.get("cells", [])
	var sheet := String(water.get("sheet", ""))
	var tex: ImageTexture = null
	if not cells.is_empty():
		var c0: Vector2i = cells[0]
		tex = _cell_tex(sheet, c0.x, c0.y)
	if tex == null:
		return
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 64)
	b.icon = tex
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.modulate = Color.WHITE if not _sel_water.is_empty() else Color(1, 1, 1, 0.45)
	b.pressed.connect(func() -> void:
		if _sel_water.get("sheet", "") == sheet:
			_sel_water = {}
		else:
			_sel_water = {"sheet": sheet, "cells": cells.duplicate()}
		_after_toggle())
	parent.add_child(b)


func _add_ref_pick(parent: Control, ref: String, kind: String, sizev: Vector2) -> void:
	var tex: Texture2D = Assets.sprite(ref) if not ref.begins_with("res://") else Assets.tex(ref)
	if tex == null:
		var nb := Button.new()
		nb.custom_minimum_size = sizev
		nb.text = "!"
		nb.modulate = Color(1, 0.3, 0.3)
		nb.disabled = true
		nb.tooltip_text = ref
		parent.add_child(nb)
		return
	var b := Button.new()
	b.custom_minimum_size = sizev
	b.icon = ImageTexture.create_from_image(tex.get_image())
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.modulate = Color(1, 1, 1, 0.45) if not _is_picked(ref) else Color.WHITE
	b.pressed.connect(func() -> void:
		_toggle(ref, kind)
		b.modulate = Color(1, 1, 1, 0.45) if not _is_picked(ref) else Color.WHITE)
	parent.add_child(b)


func _is_picked(ref: String) -> bool:
	return _sel_trees.has(ref)


func _toggle(ref: String, kind: String) -> void:
	if _sel_trees.has(ref):
		_sel_trees.erase(ref)
	elif _sel_trees.size() < MAX_TREES:
		_sel_trees.append(ref)
	_after_toggle()


func _after_toggle() -> void:
	_rebuild_preview()
	_status.text = Loc.t("composer.picked") % [
			_sel_grass.size(), MAX_GRASS, _sel_trees.size(), MAX_TREES]
	_rebuild_tray()


## Лоток выбора: что уже в биоме (клик — убрать).
func _rebuild_tray() -> void:
	for ch in _tray.get_children():
		ch.queue_free()
	for g in _sel_grass:
		var tex := _cell_tex(String(g["sheet"]), int(g["cx"]), int(g["cy"]))
		if tex == null:
			continue
		_tray_add(tex, func() -> void:
			_sel_grass.erase(g)
			_after_toggle())
	if not _sel_water.is_empty():
		var cells: Array = _sel_water.get("cells", [])
		if not cells.is_empty():
			var c0: Vector2i = cells[0]
			var wtex := _cell_tex(String(_sel_water["sheet"]), c0.x, c0.y)
			if wtex != null:
				_tray_add(wtex, func() -> void:
					_sel_water = {}
					_after_toggle())
	for ref in _sel_trees:
		var tex: Texture2D = Assets.sprite(String(ref)) if not String(ref).begins_with("res://") else Assets.tex(String(ref))
		if tex == null:
			continue
		var r := String(ref)
		_tray_add(ImageTexture.create_from_image(tex.get_image()), func() -> void:
			_sel_trees.erase(r)
			_after_toggle())


func _tray_add(icon: Texture2D, on_press: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(56, 56)
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	_tray.add_child(b)


func _rebuild_preview() -> void:
	_preview_tex = null
	_water_cells = []
	_water_frame_texs = []
	var imgs: Array = []
	for g in _sel_grass:
		var im := _clean_cell(String(g["sheet"]), int(g["cx"]), int(g["cy"]))
		if im != null:
			imgs.append(im)
	if imgs.is_empty():
		return
	var uni := Assets.uniform_ground_imgs(imgs)
	var texs: Array = uni[0]
	if texs.is_empty():
		return
	var img := Image.create(TILES * TS, TILES * TS, false, Image.FORMAT_RGBA8)
	for ty in range(TILES):
		for tx in range(TILES):
			# v1.78.6: тайлы пятнами (крупный шум — «род», хэш — вариант),
			# как город рисует: периодический узор выглядел «одним тайлом»
			var fi := _pv_tile_index(tx, ty, texs.size())
			var gim: Image = (texs[fi] as Texture2D).get_image()
			img.blend_rect(gim, Rect2i(0, 0, TS, TS), Vector2i(tx * TS, ty * TS))
	_preview_tex = ImageTexture.create_from_image(img)
	if not _sel_water.is_empty():
		var wcells: Array = _sel_water.get("cells", [])
		for tx in range(TILES):
			var yc := 8 + int(round(2.0 * sin(tx / 3.0)))
			for dy in 3:
				_water_cells.append(Vector2i(tx, yc + dy))
		# кадры воды текстурами заранее (в draw белели)
		var sheet := String(_sel_water.get("sheet", ""))
		for k in range(wcells.size()):
			var cc: Vector2i = wcells[k]
			var im := _clean_cell(sheet, cc.x, cc.y)
			_water_frame_texs.append(
					ImageTexture.create_from_image(im) if im != null else null)


## Превью-шум: билинейный хэш-шум как в городе (city_terrain._noise2) —
## тайлы раскладываются пятнами, а не шахматкой.
func _pv_hash(x: int, y: int, n: int) -> int:
	return absi(int((x * 73856093) ^ (y * 19349663) ^ (n * 83492791))) % 97


func _pv_noise(xf: float, yf: float, n: int) -> float:
	var x0 := int(floorf(xf))
	var y0 := int(floorf(yf))
	var fx := xf - float(x0)
	var fy := yf - float(y0)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := float(_pv_hash(x0, y0, n))
	var b := float(_pv_hash(x0 + 1, y0, n))
	var c := float(_pv_hash(x0, y0 + 1, n))
	var d := float(_pv_hash(x0 + 1, y0 + 1, n))
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


func _pv_tile_index(tx: int, ty: int, size: int) -> int:
	var fams := maxi(2, size / 4)
	var per := maxi(1, size / fams)
	var fam: int = absi(int(_pv_noise(tx / 6.0, ty / 6.0, 71))) % fams
	return mini(size - 1, fam * per + _pv_hash(tx, ty, 97) % per)


func _process(delta: float) -> void:
	_t += delta
	if _preview != null:
		_preview.queue_redraw()


func _draw_preview() -> void:
	var ox := 20.0
	var oy := 20.0
	if _preview_tex != null:
		_preview.draw_texture_rect(_preview_tex, Rect2(ox, oy, 640, 640), false)
	else:
		_preview.draw_rect(Rect2(ox, oy, 640, 640), Color(0.2, 0.2, 0.2))
		_preview.draw_string(ThemeDB.fallback_font, Vector2(ox + 30, oy + 320),
				Loc.t("composer.empty"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
				Color(0.8, 0.8, 0.75))
	if not _sel_water.is_empty() and not _water_frame_texs.is_empty():
		var frame := int(_t * 3.0) % 6
		var n := _water_frame_texs.size()
		for c in _water_cells:
			var tex: ImageTexture = _water_frame_texs[(c.x + frame) % n]
			if tex != null:
				_preview.draw_texture_rect(tex,
						Rect2(ox + float(c.x * TS), oy + float(c.y * TS), TS, TS), false)
	for k in range(_sel_trees.size()):
		var tp: Vector2i = TREE_SPOTS[k % TREE_SPOTS.size()]
		Assets.draw_ref(_preview, String(_sel_trees[k]),
				Vector2(ox + float(tp.x * TS + 16), oy + float(tp.y * TS - 8)), 100.0)
	_preview.draw_string(ThemeDB.fallback_font, Vector2(ox, oy + 670),
			Loc.t("composer.preview"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.7, 0.75, 0.7))


func _on_save() -> void:
	var label := String(_sources[_active].get("label", ""))
	var nm := _name_edit.text.strip_edges()
	if nm == "":
		nm = label   # v1.78.7: имя вкладки по умолчанию — сохраняешь биом
		             # этой вкладки (лето сохраняется как «лето»)
	if _sel_grass.is_empty():
		_status.text = Loc.t("composer.need_name")
		return
	var ssn := _season
	if ssn == "":
		ssn = String(SHEET_SEASON.get(label, ""))   # сезон вкладки — сам
	var tag := nm.replace("/", "_").replace("\\", "_").replace(":", "_")
	var dir := "user://biomes_composed/%s" % tag
	DirAccess.make_dir_recursive_absolute(dir)
	# ЕДИНЫЙ рецепт земли: чистые клетки листа -> обработанные тайлы + печать
	var imgs: Array = []
	for g in _sel_grass:
		var im := _clean_cell(String(g["sheet"]), int(g["cx"]), int(g["cy"]))
		if im != null:
			imgs.append(im)
	var uni := Assets.uniform_ground_imgs(imgs)
	var texs: Array = uni[0]
	if texs.is_empty():
		_status.text = Loc.t("composer.need_name")
		return
	var grass_paths := []
	for i in range(texs.size()):
		var out: Image = (texs[i] as Texture2D).get_image()
		out.save_png("%s/grass_%d.png" % [dir, i + 1])
		grass_paths.append("user://biomes_composed/%s/grass_%d.png" % [tag, i + 1])
	var water_path := ""
	if not _sel_water.is_empty():
		var cells: Array = _sel_water.get("cells", [])
		var strip := Image.create(TS * 6, TS * 3, false, Image.FORMAT_RGBA8)
		for f in range(6):
			var cc: Vector2i = cells[f % cells.size()]
			var cell := _clean_cell(String(_sel_water["sheet"]), cc.x, cc.y)
			if cell != null:
				for r in 3:
					strip.blend_rect(cell, Rect2i(0, 0, TS, TS),
							Vector2i(f * TS, r * TS))
		strip.save_png(dir + "/water.png")
		water_path = "user://biomes_composed/%s/water.png" % tag
	var data := {
		"composed": true,
		"grass": grass_paths,
		"water": water_path,
		"trees": _sel_trees,
		"label": nm,
		"season": ssn,
		# v1.78.7: клетки листа сохраняются — вкладка восстановит свой выбор
		"cells": _sel_grass,
		"water_cells": _sel_water,
		"sheet_label": label,
	}
	var f := FileAccess.open(dir + "/biome.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()
	_store_workspace()
	Assets.reload_biome_manifest()
	_status.text = Loc.t("composer.saved") % [nm,
			Loc.t("composer.season_" + ssn) if ssn != "" else Loc.t("composer.season_none")]


func _on_clear() -> void:
	# v1.78.7: очистка только АКТИВНОЙ вкладки (у каждой свой биом)
	_sel_grass = []
	_sel_water = {}
	_sel_trees = []
	_season = ""
	_name_edit.text = ""
	if _active_sheet != "":
		_workspaces.erase(_active_sheet)
	_season_btn.select(0)
	_rebuild_preview()
	_rebuild_tray()
	_status.text = Loc.t("composer.picked") % [0, MAX_GRASS, 0, MAX_TREES]


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
