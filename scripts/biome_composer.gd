extends Control
## КОМПОЗИТОР БИОМОВ (v1.78.0): собираем биом прямо в игре.
## Слева — библиотека нарезанных ассетов (все биомы + лето): клик по тайлу
## травы/воды/дереву добавляет его в свой биом (повторный клик убирает).
## Справа — живой превью 20×20 (земля единым рецептом + река + деревья).
## Сохранение: user://biomes_composed/<имя>/biome.json — биом сразу
## появляется в городе (season), на стенде и в превью SHOT_BIOME.

const TILES := 20
const TS := 32
const MAX_GRASS := 6
const MAX_TREES := 5

var _sel_grass: Array = []    # res:// пути травы
var _sel_water := ""          # res:// полоса воды
var _sel_trees: Array = []    # спрайт-рефы деревьев (img:/e:)
var _season := ""
var _t := 0.0

var _preview: Control = null
var _preview_tex: ImageTexture = null
var _water_cells: Array = []
var _status: Label = null
var _name_edit: LineEdit = null
var _season_btn: OptionButton = null
const TREE_SPOTS: Array = [Vector2i(3, 3), Vector2i(15, 4), Vector2i(4, 15),
		Vector2i(15, 15), Vector2i(9, 17)]


func _ready() -> void:
	const UITheme = preload("res://scripts/ui_theme.gd")
	var root := self
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.12, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# --- левая панель: имя/сезон/библиотека/кнопки
	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = 560.0
	left.offset_bottom = 0.0
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)

	var title := Label.new()
	title.text = Loc.t("composer.title")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	lv.add_child(title)

	var hint := Label.new()
	hint.text = Loc.t("composer.hint")
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(hint)

	var name_row := HBoxContainer.new()
	lv.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Loc.t("composer.name_ph")
	_name_edit.custom_minimum_size = Vector2(320, 36)
	name_row.add_child(_name_edit)
	_season_btn = OptionButton.new()
	for s in ["—", "весна", "лето", "осень", "зима"]:
		_season_btn.add_item(s)
	_season_btn.custom_minimum_size = Vector2(150, 36)
	_season_btn.item_selected.connect(func(i: int) -> void:
		_season = [ "", "spring", "summer", "autumn", "winter" ][i])
	name_row.add_child(_season_btn)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	_status.text = " "
	lv.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 560)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(scroll)
	var lib := VBoxContainer.new()
	lib.add_theme_constant_override("separation", 6)
	scroll.add_child(lib)
	_build_library(lib)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	lv.add_child(btns)
	for pair in [["composer.save", "_on_save"], ["composer.clear", "_on_clear"],
			["composer.back", "_on_back"]]:
		var b := Button.new()
		b.text = Loc.t(String(pair[0]))
		b.custom_minimum_size = Vector2(150, 40)
		b.add_theme_font_size_override("font_size", 15)
		b.focus_mode = Control.FOCUS_NONE
		UITheme.apply_button(b)
		b.pressed.connect(Callable(self, String(pair[1])))
		btns.add_child(b)

	# --- правая зона: живой превью
	_preview = Control.new()
	_preview.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_preview.offset_left = 580.0
	_preview.draw.connect(_draw_preview)
	root.add_child(_preview)
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _preview != null:
		_preview.queue_redraw()


## Библиотека: каждый биом — строка с кнопками травы/воды/деревьев.
func _build_library(lib: VBoxContainer) -> void:
	var sources: Array = []
	var summer := {
		"tag": "лето",
		"grass": [], "water": "res://assets/sprites/env/summer/fm_water_summer.png",
		"trees": ["e:tree2_summer_oak", "e:tree2_summer_pine",
			"e:tree2_summer_birch", "e:tree2_summer_willow",
			"e:tree2_summer_dead"],
	}
	for i in range(MAX_GRASS):
		summer["grass"].append(
				"res://assets/sprites/env/summer/grass_S%d.png" % (i + 1))
	sources.append(summer)
	var mf := Assets.biome_manifest()
	for tag in mf.keys():
		sources.append(mf[tag])
	for src in sources:
		var e: Dictionary = src
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		lib.add_child(row)
		var cap := Label.new()
		cap.text = String(e.get("label", String(e.get("tag", "?"))))
		cap.custom_minimum_size = Vector2(120, 40)
		cap.add_theme_font_size_override("font_size", 13)
		row.add_child(cap)
		for gp in e.get("grass", []):
			_add_pick(row, String(gp), "grass", Vector2(40, 40))
		var wp := String(e.get("water", ""))
		if wp != "":
			_add_pick(row, wp, "water", Vector2(40, 40))
		for tr in e.get("trees", []):
			_add_pick(row, String(tr), "tree", Vector2(48, 56))


func _add_pick(row: HBoxContainer, ref: String, kind: String, sizev: Vector2) -> void:
	var tex: Texture2D = null
	if ref.begins_with("res://"):
		tex = Assets.tex(ref)
	else:
		tex = Assets.sprite(ref)
	if tex == null:
		return
	var b := Button.new()
	b.custom_minimum_size = sizev
	b.icon = ImageTexture.create_from_image(tex.get_image())
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = kind
	b.pressed.connect(func() -> void: _toggle(ref, kind))
	row.add_child(b)


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
						Rect2(ox + float(c.x * TS), oy + float(c.y * TS),
								TS, TS),
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
	_status.text = " "


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
