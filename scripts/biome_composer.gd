extends Control
## КОМПОЗИТОР БИОМОВ v2 (v1.78.1, спецификация заказчика):
## 1) внутри ВСЕ ассеты из папок «биом/биомы» (+ лето);
## 2) сверху КНОПКИ БИОМОВ — клик открывает тайлы/воду/деревья этого биома;
##    клик по тайлу добавляет его в сборку (повторный — убирает), мешать
##    можно из разных биомов;
## 3) разные тайлы СРАСТАЮТСЯ КРАЯМИ: единая база-тон + детерминированный
##    дизеринг кромки (Assets.uniform_ground) — границы растворяются
##    пиксельным переливом, без швов и зазоров.
## Превью 20×20 справа — что видишь, то и в игре; имя+сезон+Сохранить.

const TILES := 20
const TS := 32
const MAX_GRASS := 6
const MAX_TREES := 5
const TREE_SPOTS: Array = [Vector2i(3, 3), Vector2i(15, 4), Vector2i(4, 15),
		Vector2i(15, 15), Vector2i(9, 17)]

var _sources: Array = []        # [{label, grass[], water, trees[]}]
var _active := 0                # индекс открытого биома
var _sel_grass: Array = []      # res:// пути травы
var _sel_water := ""
var _sel_trees: Array = []      # спрайт-рефы деревьев
var _season := ""
var _t := 0.0

var _preview: Control = null
var _preview_tex: ImageTexture = null
var _water_cells: Array = []
var _status: Label = null
var _name_edit: LineEdit = null
var _season_btn: OptionButton = null
var _lib_box: VBoxContainer = null
var _tray: HBoxContainer = null
var _biome_btns: Array = []


func _ready() -> void:
	const UITheme = preload("res://scripts/ui_theme.gd")
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
		_biome_btns.append(b)

	# --- левая колонка: библиотека открытого биома + выбор + кнопки
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

	_lib_box = VBoxContainer.new()
	_lib_box.add_theme_constant_override("separation", 6)
	lv.add_child(_lib_box)
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

	# --- правая зона: живой превью
	_preview = Control.new()
	_preview.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_preview.offset_left = 580.0
	_preview.offset_top = 72.0
	_preview.draw.connect(_draw_preview)
	add_child(_preview)
	set_process(true)


## Все источники: лето + все биомы манифеста (папки «биом/биомы»).
func _load_sources() -> void:
	_sources = []
	var summer := {
		"label": "лето",
		"grass": [], "water": "res://assets/sprites/env/summer/fm_water_summer.png",
		"trees": ["e:tree2_summer_oak", "e:tree2_summer_pine",
			"e:tree2_summer_birch", "e:tree2_summer_willow",
			"e:tree2_summer_dead"],
	}
	for i in range(MAX_GRASS):
		summer["grass"].append(
				"res://assets/sprites/env/summer/grass_S%d.png" % (i + 1))
	_sources.append(summer)
	var mf := Assets.biome_manifest()
	for tag in mf.keys():
		var e: Dictionary = mf[tag]
		_sources.append({
			"label": String(e.get("label", String(tag))),
			"grass": e.get("grass", []),
			"water": String(e.get("water", "")),
			"trees": e.get("trees", []),
		})


## Открыть биом: его тайлы/вода/деревья (клик = добавить/убрать).
func _open_biome(i: int) -> void:
	_active = clampi(i, 0, _sources.size() - 1)
	for ch in _lib_box.get_children():
		ch.queue_free()
	var e: Dictionary = _sources[_active]
	var cap := Label.new()
	cap.text = Loc.t("composer.biome_header") % String(e.get("label", "?"))
	cap.add_theme_font_size_override("font_size", 18)
	cap.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	_lib_box.add_child(cap)

	var gcap := Label.new()
	gcap.text = Loc.t("composer.grass_cap")
	gcap.add_theme_font_size_override("font_size", 13)
	_lib_box.add_child(gcap)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_lib_box.add_child(grid)
	for gp in e.get("grass", []):
		_add_pick(grid, String(gp), "grass", Vector2(64, 64))

	if String(e.get("water", "")) != "":
		var wcap := Label.new()
		wcap.text = Loc.t("composer.water_cap")
		wcap.add_theme_font_size_override("font_size", 13)
		_lib_box.add_child(wcap)
		var wrow := HBoxContainer.new()
		_lib_box.add_child(wrow)
		_add_pick(wrow, String(e["water"]), "water", Vector2(64, 64))

	if not (e.get("trees", []) as Array).is_empty():
		var tcap := Label.new()
		tcap.text = Loc.t("composer.trees_cap")
		tcap.add_theme_font_size_override("font_size", 13)
		_lib_box.add_child(tcap)
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		_lib_box.add_child(trow)
		for tr in e.get("trees", []):
			_add_pick(trow, String(tr), "tree", Vector2(64, 80))


func _add_pick(parent: Control, ref: String, kind: String, sizev: Vector2) -> void:
	var tex: Texture2D = Assets.tex(ref) if ref.begins_with("res://") else Assets.sprite(ref)
	if tex == null:
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
	return _sel_grass.has(ref) or _sel_water == ref or _sel_trees.has(ref)


func _toggle(ref: String, kind: String) -> void:
	match kind:
		"grass":
			if _sel_grass.has(ref):
				_sel_grass.erase(ref)
			elif _sel_grass.size() < MAX_GRASS:
				_sel_grass.append(ref)
		"water":
			_sel_water = "" if _sel_water == ref else ref
		"tree":
			if _sel_trees.has(ref):
				_sel_trees.erase(ref)
			elif _sel_trees.size() < MAX_TREES:
				_sel_trees.append(ref)
	_rebuild_preview()
	_status.text = Loc.t("composer.picked") % [
			_sel_grass.size(), MAX_GRASS, _sel_trees.size(), MAX_TREES]
	_rebuild_tray()


## Лоток выбора: что уже в биоме (клик — убрать).
func _rebuild_tray() -> void:
	for ch in _tray.get_children():
		ch.queue_free()
	var all: Array = _sel_grass.duplicate()
	if _sel_water != "":
		all.append(_sel_water)
	all += _sel_trees
	for ref in all:
		var tex: Texture2D = Assets.tex(String(ref)) if String(ref).begins_with("res://") else Assets.sprite(String(ref))
		if tex == null:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 56)
		b.icon = ImageTexture.create_from_image(tex.get_image())
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.expand_icon = true
		b.focus_mode = Control.FOCUS_NONE
		var r := String(ref)
		b.pressed.connect(func() -> void:
			_sel_grass.erase(r)
			if _sel_water == r:
				_sel_water = ""
			_sel_trees.erase(r)
			_rebuild_preview()
			_rebuild_tray())
		_tray.add_child(b)


func _rebuild_preview() -> void:
	_preview_tex = null
	_water_cells = []
	if _sel_grass.is_empty():
		return
	var uni := Assets.uniform_ground(_sel_grass)
	var texs: Array = uni[0]
	if texs.is_empty():
		return
	var img := Image.create(TILES * TS, TILES * TS, false, Image.FORMAT_RGBA8)
	for ty in range(TILES):
		for tx in range(TILES):
			var fi := (tx * tx * 3 + ty * ty * 7 + tx * ty) % texs.size()
			var gim: Image = (texs[fi] as Texture2D).get_image()
			img.blend_rect(gim, Rect2i(0, 0, TS, TS), Vector2i(tx * TS, ty * TS))
	_preview_tex = ImageTexture.create_from_image(img)
	if _sel_water != "" and Assets.tex(_sel_water) != null:
		for tx in range(TILES):
			var yc := 8 + int(round(2.0 * sin(tx / 3.0)))
			for dy in 3:
				_water_cells.append(Vector2i(tx, yc + dy))


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
	if _sel_water != "":
		var wtex := Assets.tex(_sel_water)
		if wtex != null:
			var wf := int(_t * 3.0) % 6
			for c in _water_cells:
				_preview.draw_texture_rect_region(wtex,
						Rect2(ox + float(c.x * TS), oy + float(c.y * TS), TS, TS),
						Rect2(float(wf) * TS, float(c.y % 3) * TS, TS, TS))
	for k in range(_sel_trees.size()):
		var tp: Vector2i = TREE_SPOTS[k % TREE_SPOTS.size()]
		Assets.draw_ref(_preview, String(_sel_trees[k]),
				Vector2(ox + float(tp.x * TS + 16), oy + float(tp.y * TS - 8)), 100.0)
	_preview.draw_string(ThemeDB.fallback_font, Vector2(ox, oy + 670),
			Loc.t("composer.preview"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.7, 0.75, 0.7))


func _on_save() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm == "" or _sel_grass.is_empty():
		_status.text = Loc.t("composer.need_name")
		return
	var tag := nm.replace("/", "_").replace("\\", "_").replace(":", "_")
	var dir := "user://biomes_composed/%s" % tag
	DirAccess.make_dir_recursive_absolute(dir)
	var data := {
		"grass": _sel_grass, "water": _sel_water, "trees": _sel_trees,
		"label": nm, "season": _season, "composed": true,
	}
	var f := FileAccess.open(dir + "/biome.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false))
	Assets.reload_biome_manifest()
	_status.text = Loc.t("composer.saved") % [nm,
			Loc.t("composer.season_" + _season) if _season != "" else Loc.t("composer.season_none")]


func _on_clear() -> void:
	_sel_grass = []
	_sel_water = ""
	_sel_trees = []
	_season = ""
	_season_btn.select(0)
	_rebuild_preview()
	_rebuild_tray()
	_status.text = Loc.t("composer.picked") % [0, MAX_GRASS, 0, MAX_TREES]


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
