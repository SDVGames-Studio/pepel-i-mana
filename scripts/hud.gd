extends CanvasLayer
## HUD данжа (M1): полосы здоровья/маны/рывка, добыча, рюкзак (Tab),
## подсказки взаимодействия и миникарта. Узлы собираются из кода.

const BAR_W := 240.0
const BAR_H := 18.0

var hero: Node2D = null
var gen: Object = null
var loot_data: Dictionary = {}
var minimap: Control = null

var _hp_fill: ColorRect
var _mana_fill: ColorRect
var _dash_fill: ColorRect
var _hp_label: Label
var _mana_label: Label
var _loot_label: Label
var _hint_label: Label
var _toast_label: Label
var _warning_label: Label
var _inv_panel: PanelContainer
var _inv_text: RichTextLabel
var _toast_time := 0.0


## Вызвать до add_child: ссылки на героя, генерацию и данные лута.
func init(hero_ref: Node2D, gen_ref: Object, loot: Dictionary) -> void:
	hero = hero_ref
	gen = gen_ref
	loot_data = loot


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast_label.text = ""


## Обновление показателей; вызывается каждый кадр из сцены данжа.
func refresh() -> void:
	if hero == null:
		return
	var hp_max := int(hero.p["hp"])
	_hp_fill.size = Vector2(BAR_W * clampf(float(hero.hp) / hp_max, 0.0, 1.0), BAR_H)
	_hp_label.text = "%s %d/%d" % [Loc.t("hud.hp"), hero.hp, hp_max]
	var mana_max := int(hero.p["mana"])
	_mana_fill.size = Vector2(BAR_W * clampf(float(hero.mana) / mana_max, 0.0, 1.0), BAR_H)
	_mana_label.text = "%s %d/%d" % [Loc.t("hud.mana"), hero.mana, mana_max]
	_dash_fill.size = Vector2(BAR_W * hero.dash_ready_fraction(), BAR_H)
	_loot_label.text = Loc.t("hud.loot_total") % Game.loot_total()
	_warning_label.visible = hero.mana <= 0 and not hero.dead
	if _inv_panel.visible:
		_inv_text.text = _inventory_bbcode()


func toast(msg: String) -> void:
	_toast_label.text = msg
	_toast_time = 2.0


func set_hint(msg: String) -> void:
	_hint_label.text = msg


func toggle_inventory() -> void:
	_inv_panel.visible = not _inv_panel.visible


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bars := VBoxContainer.new()
	bars.position = Vector2(16, 16)
	bars.add_theme_constant_override("separation", 6)
	root.add_child(bars)

	var hp_row := _make_bar(Color("#5a1f1f"), Color("#cc4444"))
	_hp_fill = hp_row["fill"]
	_hp_label = hp_row["label"]
	bars.add_child(hp_row["panel"])

	var mana_row := _make_bar(Color("#1f2f5a"), Color("#4477cc"))
	_mana_fill = mana_row["fill"]
	_mana_label = mana_row["label"]
	bars.add_child(mana_row["panel"])

	var dash_row := _make_bar(Color("#3d3a20"), Color("#ccaa44"))
	_dash_fill = dash_row["fill"]
	_dash_row_label(dash_row["label"])
	bars.add_child(dash_row["panel"])

	_loot_label = Label.new()
	_loot_label.add_theme_font_size_override("font_size", 18)
	bars.add_child(_loot_label)

	minimap = preload("res://scripts/minimap.gd").new()
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -208.0
	minimap.offset_top = 16.0
	minimap.offset_right = -16.0
	minimap.offset_bottom = 208.0
	root.add_child(minimap)

	_warning_label = _make_screen_label(Color("#ff5555"), 30, VERTICAL_ALIGNMENT_CENTER)
	root.add_child(_warning_label)

	_toast_label = _make_screen_label(Color("#ffd766"), 22, VERTICAL_ALIGNMENT_BOTTOM)
	_toast_label.offset_top = -170.0
	root.add_child(_toast_label)

	_hint_label = _make_screen_label(Color(1, 1, 1, 0.85), 22, VERTICAL_ALIGNMENT_BOTTOM)
	_hint_label.offset_top = -120.0
	root.add_child(_hint_label)

	_build_inventory_panel(root)


func _dash_row_label(label: Label) -> void:
	label.text = Loc.t("hud.dash")


func _make_bar(bg: Color, fill_color: Color) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(BAR_W + 4.0, BAR_H + 4.0)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg
	panel.add_theme_stylebox_override("panel", bg_style)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(0, BAR_H)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fill)
	var label := Label.new()
	label.position = Vector2(8, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return {"panel": panel, "fill": fill, "label": label}


## Подпись на весь экран: warning — по центру, hint/toast — снизу по центру.
func _make_screen_label(color: Color, font_size: int, v_align: int) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_top = 0.0
	label.offset_bottom = 0.0
	label.offset_left = 0.0
	label.offset_right = 0.0
	if v_align == VERTICAL_ALIGNMENT_BOTTOM:
		label.offset_top = -140.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = v_align
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_inventory_panel(root: Control) -> void:
	_inv_panel = PanelContainer.new()
	_inv_panel.set_anchors_preset(Control.PRESET_CENTER)
	_inv_panel.custom_minimum_size = Vector2(420, 320)
	_inv_panel.visible = false
	root.add_child(_inv_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_inv_panel.add_child(box)
	var title := Label.new()
	title.text = Loc.t("hud.inventory")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	_inv_text = RichTextLabel.new()
	_inv_text.bbcode_enabled = true
	_inv_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_inv_text)


func _inventory_bbcode() -> String:
	if Game.inventory.is_empty():
		return "[color=#999999]%s[/color]" % Loc.t("hud.empty")
	var lines: PackedStringArray = []
	for stack in Game.inventory:
		var item := _item_by_id(String(stack["id"]))
		if item.is_empty():
			continue
		var rarity := _rarity_by_id(String(item.get("rarity", "")))
		var rarity_text := ""
		if not rarity.is_empty():
			var color := String(rarity.get("color", "#ffffff"))
			rarity_text = " — [color=%s]%s[/color]" % [color, Loc.t(String(rarity["loc"]))]
		lines.append("%s ×%d%s" % [Loc.t(String(item["loc"])), int(stack["count"]), rarity_text])
	return "\n".join(lines)


func _item_by_id(item_id: String) -> Dictionary:
	for item in loot_data.get("items", []):
		if item["id"] == item_id:
			return item
	return {}


func _rarity_by_id(rarity_id: String) -> Dictionary:
	for rarity in loot_data.get("rarities", []):
		if rarity["id"] == rarity_id:
			return rarity
	return {}
