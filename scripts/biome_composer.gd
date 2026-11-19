extends Control
## КОМПОЗИТОР-РИСОВАЛКА БИОМОВ v4 (v1.78.8, поручение заказчика:
## «я должен рисовать сам, каждый тайл»):
## 1) сверху кнопки биомов; У КАЖДОЙ ВКЛАДКИ — СВОЙ БИОМ И СВОЁ СОХРАНЕНИЕ
##    (открыл «лето» — нарисовал — сохранил; потом «осень» — своя);
## 2) клик по тайлу библиотеки берёт его КИСТЬЮ; рисуешь мышью по холсту
##    20×20 — КАЖДЫЙ ТАЙЛ на карте ставишь САМ; ПКМ/«Ластик» — стереть;
## 3) сохранение пишет НАРИСОВАННУЮ КАРТУ (grid 20×20) в biome.json —
##    город рисует ровно твой рисунок (тайлится по миру), а не алгоритм.
## Библиотека читает исходные листы напрямую (мимо импорта), шашечка
## вместо альфы снимается сама, вода — полоса из листа (перекраска берега —
## в цвет биома). Патчи печатаются в user://biomes_composed/<имя>/ —
## биом работает СРАЗУ, без переимпорта редактора и в экспорте.

const TILES := 20
const TS := 32
const MAX_TREES := 5
const TREE_SPOTS: Array = [Vector2i(3, 3), Vector2i(15, 4), Vector2i(4, 15),
		Vector2i(15, 15), Vector2i(9, 17)]

# Сезон вкладки проставляется сам: сохранённый биом вкладки сразу
# становится обликом города в этот сезон.
const SHEET_SEASON := {"лето": "summer", "весна": "spring",
	"осень": "autumn", "зима": "winter"}

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
const SUMMER_TREES := ["e:tree2_summer_oak", "e:tree2_summer_pine",
	"e:tree2_summer_birch", "e:tree2_summer_willow", "e:tree2_summer_dead"]

var _sources: Array = []        # [{label, sheet, trees[]}]
var _active := 0
var _sheet_cache := {}          # путь листа -> Image
var _analysis := {}             # путь листа -> {cells[], water{}, found}
var _clean_cache := {}          # "лист|cx,cy" -> Image (шашечка снята)
var _workspaces := {}           # путь листа -> рисование ЭТОЙ вкладки
var _active_sheet := ""

# --- рисование ---
var _grid: Array = []           # TILES*TILES int: индекс палитры или -1 (фон)
var _brush := -1                # индекс палитры; -1 = ластик
var _painting := false          # ЛКМ зажата — рисуем при движении
var _sel_grass: Array = []      # палитра: [{"sheet", "cx", "cy"}]
var _palette_texs: Array = []   # обработанные текстуры палитры (городские)
var _fill_color := Color(0.35, 0.4, 0.25)
var _canvas_tex: ImageTexture = null
var _sel_water := {}            # {"sheet", "cells": [Vector2i]} или {}
var _sel_trees: Array = []      # спрайт-рефы деревьев
var _season := ""
var _t := 0.0

var _preview: Control = null
var _water_cells: Array = []
var _water_frame_texs: Array = []
var _status: Label = null
var _name_edit: LineEdit = null
var _season_btn: OptionButton = null
var _lib_box: VBoxContainer = null
var _lib_scroll: ScrollContainer = null
var _tray: HBoxContainer = null
var _tray_btns: Array = []      # кнопки палитры (подсветка кисти)
var _cell_btns: Array = []      # кнопки библиотеки (подсветка кисти)
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

	_lib_scroll = ScrollContainer.new()
	_lib_scroll.custom_minimum_size = Vector2(520, 330)
	_lib_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lib_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	lv.add_child(_lib_scroll)
	_lib_box = VBoxContainer.new()
	_lib_box.add_theme_constant_override("separation", 6)
	_lib_scroll.add_child(_lib_box)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
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
	# --- правая зона: холст рисования (клик/драг мышью)
	_preview = Control.new()
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview.offset_left = 580.0
	_preview.offset_top = 72.0
	_preview.offset_right = -20.0
	_preview.offset_bottom = -40.0
	_preview.draw.connect(_draw_preview)
	_preview.gui_input.connect(_on_canvas_input)
	add_child(_preview)
	set_process(true)
	_open_biome(0)   # ПОСЛЕ всех полей UI (_status/_tray нужны рисовалке)


## Источники: 15 листов заказчика. Деревья — нарезанные манифестные.
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


## Анализ листа (кэш): полные клетки (альфа>200, сэмпл шаг 2), вода —
## длиннейшая горизонтальная серия синих клеток. Шашечка-фон отсеивается.
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
			var is_light_px := 0
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
				var light_spread := lum_hi - lum_lo
				if is_light_px * 4 > n * 3 and light_spread > 12.0:
					continue   # клетка-фон листа (шашечка)
				cells.append({
					"cx": cx, "cy": cy, "mean": m, "lum": lum,
					"water": m.z > m.x + 10.0 and m.z > m.y + 10.0,
				})
	var ground := []
	for c in cells:
		if not bool(c["water"]):
			ground.append(c)
	ground.sort_custom(func(a, b) -> bool:
		if int(a["cy"]) != int(b["cy"]):
			return int(a["cy"]) < int(b["cy"])
		return int(a["cx"]) < int(b["cx"]))
	res["cells"] = ground
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


## Чистка клетки: шашечка-вместо-альфы (светлый нейтральный пиксель, чья
## пара на ±8px — светлый нейтральный другого тона) снимается заливкой
## от краёв; цветы внутри травы заливка не достигает. >80% шашечки — фон.
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
	if holes * 10 > W * H * 8:
		out = null
	_clean_cache[key] = out
	return out


func _cell_tex(path: String, cx: int, cy: int) -> ImageTexture:
	var im := _clean_cell(path, cx, cy)
	return ImageTexture.create_from_image(im) if im != null else null


## ---------- workspace: у каждой вкладки свой рисунок ----------

func _store_workspace() -> void:
	if _active_sheet == "":
		return
	_workspaces[_active_sheet] = {
		"grass": _sel_grass.duplicate(true),
		"water": _sel_water.duplicate(true),
		"trees": _sel_trees.duplicate(true),
		"grid": _grid.duplicate(),
		"name": _name_edit.text,
		"season": _season,
	}


## Загрузить рисование вкладки: из workspace сессии или из сохранённого
## biome.json (клетки и grid восстановятся — рисунок продолжается).
func _load_workspace(sheet: String) -> void:
	var label := String(_sources[_active].get("label", ""))
	_grid = []
	_grid.resize(TILES * TILES)
	for k in range(_grid.size()):
		_grid[k] = -1
	_sel_grass = []
	_sel_water = {}
	_sel_trees = []
	_season = ""
	_name_edit.text = ""
	var ws: Dictionary = _workspaces.get(sheet, {})
	if ws.is_empty():
		var bf := FileAccess.open(
				"user://biomes_composed/%s/biome.json" % label, FileAccess.READ)
		if bf != null:
			var parsed: Variant = JSON.parse_string(bf.get_as_text())
			if parsed is Dictionary:
				var d: Dictionary = parsed
				for c in d.get("cells", []):
					_sel_grass.append({
						"sheet": String(c.get("sheet", sheet)),
						"cx": int(c.get("cx", 0)),
						"cy": int(c.get("cy", 0)),
					})
				for k2 in range(_grid.size()):
					_grid[k2] = -1
				var gd: Array = d.get("grid", [])
				for k3 in range(mini(gd.size(), _grid.size())):
					_grid[k3] = int(gd[k3])
				var wc: Dictionary = d.get("water_cells", {})
				if not (wc.get("cells", []) as Array).is_empty():
					var wlist: Array = []
					for c2 in wc.get("cells", []):
						var cc: Variant = c2
						if cc is Dictionary:
							wlist.append(Vector2i(int(cc.get("x", 0)),
									int(cc.get("y", 0))))
						elif cc is Vector2i:
							wlist.append(cc)
					_sel_water = {"sheet": String(wc.get("sheet", sheet)),
							"cells": wlist}
				_sel_trees = d.get("trees", [])
				_season = String(d.get("season", ""))
				_season_btn.select(maxi(0, ["", "spring", "summer",
						"autumn", "winter"].find(_season)))
				_name_edit.text = String(d.get("label", ""))
				_store_workspace()
		return
	_sel_grass = (ws.get("grass", []) as Array).duplicate(true)
	_sel_water = (ws.get("water", {}) as Dictionary).duplicate(true)
	_sel_trees = (ws.get("trees", []) as Array).duplicate(true)
	_grid = (ws.get("grid", []) as Array).duplicate()
	_name_edit.text = String(ws.get("name", ""))
	_season = String(ws.get("season", ""))
	var sidx := ["", "spring", "summer", "autumn", "winter"].find(_season) \
			if _season != "" else 0
	_season_btn.select(maxi(0, sidx))


## Открыть вкладку-биом: свой рисунок у каждой. Перед переключением
## текущее рисование прячется в workspace, вкладка восстанавливается.
func _open_biome(i: int) -> void:
	_store_workspace()
	_active = clampi(i, 0, _sources.size() - 1)
	for ch in _lib_box.get_children():
		ch.queue_free()
	var e: Dictionary = _sources[_active]
	var sheet := String(e.get("sheet", ""))
	_active_sheet = sheet
	_cell_btns = []   # кнопки прошлой вкладки освобождены вместе с lib_box
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
	_rebuild_palette()
	_rebuild_water()
	_redraw_canvas()


## Клик по клетке библиотеки = ВЗЯТЬ КИСТЬ (рисовать этим тайлом).
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
	b.tooltip_text = "кисть: клетка %d,%d" % [cx, cy]
	_cell_btns.append({"btn": b, "sheet": sheet, "cx": cx, "cy": cy})
	b.pressed.connect(func() -> void:
		_pick_brush_cell(sheet, cx, cy))
	parent.add_child(b)


func _pick_brush_cell(sheet: String, cx: int, cy: int) -> void:
	# тайл уже в палитре?
	for k in range(_sel_grass.size()):
		var g: Dictionary = _sel_grass[k]
		if String(g["sheet"]) == sheet and int(g["cx"]) == cx \
				and int(g["cy"]) == cy:
			_brush = k
			_refresh_brush_ui()
			return
	if _sel_grass.size() >= 24:
		return
	_sel_grass.append({"sheet": sheet, "cx": cx, "cy": cy})
	_brush = _sel_grass.size() - 1
	_rebuild_palette()
	_rebuild_water()


## Кнопка воды листа: полоса биома.
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
		_rebuild_water())
	parent.add_child(b)


## Деревья остаются выбором (клик — добавить/убрать).
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
	b.modulate = Color(1, 1, 1, 0.45) if not _sel_trees.has(ref) else Color.WHITE
	b.pressed.connect(func() -> void:
		if _sel_trees.has(ref):
			_sel_trees.erase(ref)
		elif _sel_trees.size() < MAX_TREES:
			_sel_trees.append(ref)
		b.modulate = Color(1, 1, 1, 0.45) if not _sel_trees.has(ref) else Color.WHITE
		_rebuild_water())
	parent.add_child(b)


## ---------- холст: рисование мышью ----------

func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			_paint_at(mb.position, mb.pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_erase_at(mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _painting and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_paint_at(mm.position, true)


## Ставит/стирает тайл по координате мыши на холсте 20×20.
func _paint_at(local: Vector2, on: bool) -> void:
	var tx := int(floorf((local.x - 20.0) / float(TS)))
	var ty := int(floorf((local.y - 20.0) / float(TS)))
	if tx < 0 or ty < 0 or tx >= TILES or ty >= TILES:
		return
	var idx := ty * TILES + tx
	var brush := _brush
	if brush < 0 or brush >= _sel_grass.size():
		brush = -1   # кисть не выбрана — рисовать нечем (стирание ПКМ)
	var v := brush if (on and brush >= 0) else -1
	if v < 0 and brush >= 0 and not on:
		v = -1
	if _grid[idx] == v:
		return
	_grid[idx] = v
	_redraw_canvas()


func _erase_at(local: Vector2) -> void:
	var tx := int(floorf((local.x - 20.0) / float(TS)))
	var ty := int(floorf((local.y - 20.0) / float(TS)))
	if tx < 0 or ty < 0 or tx >= TILES or ty >= TILES:
		return
	var idx := ty * TILES + tx
	if _grid[idx] == -1:
		return
	_grid[idx] = -1
	_redraw_canvas()


## Перестроить холст: фон (общий тон биома) + тайлы по grid.
func _redraw_canvas() -> void:
	_canvas_tex = null
	var imgs: Array = []
	for g in _sel_grass:
		var im := _clean_cell(String(g["sheet"]), int(g["cx"]), int(g["cy"]))
		if im != null:
			imgs.append(im)
	var uni := Assets.uniform_ground_imgs(imgs)
	var texs: Array = uni[0]
	_palette_texs = texs
	if (uni[1] as Array).size() > 0 and uni[1][0] != null:
		var fim: Image = (uni[1][0] as Texture2D).get_image()
		_fill_color = fim.get_pixel(16, 16)
	var img := Image.create(TILES * TS, TILES * TS, false, Image.FORMAT_RGBA8)
	img.fill(_fill_color)
	for ty in range(TILES):
		for tx in range(TILES):
			var fi: int = int(_grid[ty * TILES + tx])
			if fi < 0 or fi >= texs.size():
				continue
			var gim: Image = (texs[fi] as Texture2D).get_image()
			img.blend_rect(gim, Rect2i(0, 0, TS, TS), Vector2i(tx * TS, ty * TS))
	_canvas_tex = ImageTexture.create_from_image(img)
	# живая вода поверх холста
	_water_cells = []
	_water_frame_texs = []
	if not _sel_water.is_empty():
		var wcells: Array = _sel_water.get("cells", [])
		for tx2 in range(TILES):
			var yc := 8 + int(round(2.0 * sin(tx2 / 3.0)))
			for dy in 3:
				_water_cells.append(Vector2i(tx2, yc + dy))
		var sheet := String(_sel_water.get("sheet", ""))
		for k in range(wcells.size()):
			var cc: Vector2i = wcells[k]
			var wim := _clean_cell(sheet, cc.x, cc.y)
			_water_frame_texs.append(
					ImageTexture.create_from_image(wim) if wim != null else null)
	_refresh_brush_ui()
	if _preview != null:
		_preview.queue_redraw()


## Подсветка кисти: в библиотеке и в палитре.
func _refresh_brush_ui() -> void:
	for e in _cell_btns:
		var b: Button = e["btn"]
		if b == null or not is_instance_valid(b):
			continue
		b.modulate = Color(1, 1, 1, 0.45)
	for e2 in _cell_btns:
		var b2: Button = e2["btn"]
		if b2 == null or not is_instance_valid(b2):
			continue
		if _brush >= 0 and _brush < _sel_grass.size():
			var g: Dictionary = _sel_grass[_brush]
			if String(e2["sheet"]) == String(g["sheet"]) \
					and int(e2["cx"]) == int(g["cx"]) \
					and int(e2["cy"]) == int(g["cy"]):
				b2.modulate = Color.WHITE
	for k in range(_tray_btns.size()):
		var tb: Button = _tray_btns[k]
		if tb == null or not is_instance_valid(tb):
			continue
		tb.modulate = Color.WHITE if k == _brush else Color(1, 1, 1, 0.45)
	var drawn := 0
	for v in _grid:
		if int(v) >= 0:
			drawn += 1
	_status.text = "кисть: %s  ·  нарисовано клеток: %d  ·  деревья %d/%d" % [
			"ластик" if _brush < 0 else "#%d" % (_brush + 1),
			drawn, _sel_trees.size(), MAX_TREES]


## Палитра: тайлы, взятые кистью (клик — кисть), + «Ластик».
func _rebuild_palette() -> void:
	for ch in _tray.get_children():
		ch.queue_free()
	_tray_btns = []
	# ластик
	var er := Button.new()
	er.text = "Ластик"
	er.custom_minimum_size = Vector2(64, 56)
	er.add_theme_font_size_override("font_size", 13)
	er.focus_mode = Control.FOCUS_NONE
	er.pressed.connect(func() -> void:
		_brush = -1
		_refresh_brush_ui())
	_tray.add_child(er)
	_tray_btns.append(er)
	for k in range(_sel_grass.size()):
		var g: Dictionary = _sel_grass[k]
		var tex := _cell_tex(String(g["sheet"]), int(g["cx"]), int(g["cy"]))
		if tex == null:
			_tray_btns.append(null)
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 56)
		b.icon = tex
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.expand_icon = true
		b.focus_mode = Control.FOCUS_NONE
		var kk := k
		b.pressed.connect(func() -> void:
			_brush = kk
			_refresh_brush_ui())
		_tray.add_child(b)
		_tray_btns.append(b)


func _rebuild_water() -> void:
	_redraw_canvas()


func _process(delta: float) -> void:
	_t += delta
	if _preview != null:
		_preview.queue_redraw()


func _draw_preview() -> void:
	var ox := 20.0
	var oy := 20.0
	if _canvas_tex != null:
		_preview.draw_texture_rect(_canvas_tex,
				Rect2(ox, oy, TILES * TS, TILES * TS), false)
	else:
		_preview.draw_rect(Rect2(ox, oy, TILES * TS, TILES * TS), Color(0.2, 0.2, 0.2))
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
	# рамка кисти: клетка под курсором (визуально)
	if _brush >= 0:
		_preview.draw_rect(Rect2(ox, oy, TILES * TS, TILES * TS),
				Color(1, 1, 0.6, 0.12), false, 2.0)
	_preview.draw_string(ThemeDB.fallback_font, Vector2(ox, oy + 670),
			Loc.t("composer.preview"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.7, 0.75, 0.7))


func _on_save() -> void:
	var label := String(_sources[_active].get("label", ""))
	var nm := _name_edit.text.strip_edges()
	if nm == "":
		nm = label   # имя вкладки по умолчанию: сохраняешь биом этой вкладки
	var drawn := 0
	for v in _grid:
		if int(v) >= 0:
			drawn += 1
	if _sel_grass.is_empty() or drawn == 0:
		_status.text = Loc.t("composer.need_draw")
		return
	var ssn := _season
	if ssn == "":
		ssn = String(SHEET_SEASON.get(label, ""))   # сезон вкладки — сам
	var tag := nm.replace("/", "_").replace("\\", "_").replace(":", "_")
	var dir := "user://biomes_composed/%s" % tag
	DirAccess.make_dir_recursive_absolute(dir)
	# печатаются тайлы ПАЛИТРЫ в порядке индексов (grid ссылается на них)
	var imgs: Array = []
	for g in _sel_grass:
		var im := _clean_cell(String(g["sheet"]), int(g["cx"]), int(g["cy"]))
		if im != null:
			imgs.append(im)
	var uni := Assets.uniform_ground_imgs(imgs)
	var texs: Array = uni[0]
	if texs.is_empty():
		_status.text = Loc.t("composer.need_draw")
		return
	var grass_paths := []
	var cells_json := []
	for i in range(_sel_grass.size()):
		if i >= texs.size():
			break
		var out: Image = (texs[i] as Texture2D).get_image()
		out.save_png("%s/grass_%d.png" % [dir, i + 1])
		grass_paths.append("user://biomes_composed/%s/grass_%d.png" % [tag, i + 1])
		var g: Dictionary = _sel_grass[i]
		cells_json.append({"sheet": String(g["sheet"]),
				"cx": int(g["cx"]), "cy": int(g["cy"])})
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
		# НАРИСОВАННАЯ КАРТА: город рисует ровно её (тайлится 20×20)
		"grid": _grid,
		"cells": cells_json,
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
	# очистка ТОЛЬКО активной вкладки (рисование и палитра)
	_sel_grass = []
	_sel_water = {}
	_sel_trees = []
	_season = ""
	_brush = -1
	_name_edit.text = ""
	if _active_sheet != "":
		_workspaces.erase(_active_sheet)
	_season_btn.select(0)
	_rebuild_palette()
	_redraw_canvas()
	_status.text = Loc.t("composer.cleared")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
