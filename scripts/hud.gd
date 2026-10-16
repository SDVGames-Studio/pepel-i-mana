extends CanvasLayer
## HUD данжа (M1): полосы здоровья/маны/рывка, добыча, рюкзак (Tab),
## подсказки взаимодействия и миникарта. Узлы собираются из кода.

const BAR_W := 240.0
const BAR_H := 18.0

var hero = null           # герой — динамическая ссылка (свойства задаёт hero.gd)
var gen = null
var loot_data: Dictionary = {}
var minimap = null

var _hp_fill: ColorRect
var _mana_fill: ColorRect
var _dash_fill: ColorRect
var _xp_fill: ColorRect
var _hp_label: Label
var _mana_label: Label
var _xp_label: Label
var _loot_label: Label
var _hint_label: Label
var _toast_label: Label
var _warning_label: Label
var _inv_panel: PanelContainer
var _inv_text: RichTextLabel
var _skill_panel: PanelContainer
var _skill_box: VBoxContainer
var _spell_slots: Array = []      # [{panel, label}] — панель заклинаний 1–6
var _toast_time := 0.0


## Вызвать до add_child: ссылки на героя, генерацию и данные лута.
func init(hero_ref, gen_ref, loot: Dictionary) -> void:
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
	var hp_max: int = hero.hp_max()
	_hp_fill.size = Vector2(BAR_W * clampf(float(hero.hp) / hp_max, 0.0, 1.0), BAR_H)
	_hp_label.text = "%s %d/%d" % [Loc.t("hud.hp"), hero.hp, hp_max]
	var mana_max := int(hero.mana_max)
	_mana_fill.size = Vector2(BAR_W * clampf(float(hero.mana) / mana_max, 0.0, 1.0), BAR_H)
	_mana_label.text = "%s %d/%d" % [Loc.t("hud.mana"), hero.mana, mana_max]
	_dash_fill.size = Vector2(BAR_W * hero.dash_ready_fraction(), BAR_H)
	# XP героя (M7): полоса до следующего уровня
	if Game.skills != null:
		_xp_fill.size = Vector2(BAR_W * clampf(float(Game.skills.xp) / float(Game.skills.xp_next()), 0.0, 1.0), BAR_H)
		_xp_label.text = "%s %d" % [Loc.t("hud.level"), Game.skills.level]
	_loot_label.text = Loc.t("hud.loot_total") % Game.loot_total()
	_warning_label.visible = hero.mana <= 0 and not hero.dead
	_refresh_spell_slots()
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

	var xp_row := _make_bar(Color("#2a2438"), Color("#9c6ade"))
	_xp_fill = xp_row["fill"]
	_xp_label = xp_row["label"]
	bars.add_child(xp_row["panel"])

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

	# тост выше подсказки: полосы на разной высоте, не накладываются
	_toast_label = _make_screen_label(Color("#ffd766"), 22, VERTICAL_ALIGNMENT_BOTTOM, -118.0)
	root.add_child(_toast_label)

	_hint_label = _make_screen_label(Color(1, 1, 1, 0.85), 22, VERTICAL_ALIGNMENT_BOTTOM, -58.0)
	root.add_child(_hint_label)

	_build_spell_bar(root)
	_build_inventory_panel(root)
	_build_skill_panel(root)


## Панель выбора навыка при левелапе (M7): по следующему узлу каждой ветки.
func _build_skill_panel(root: Control) -> void:
	_skill_panel = PanelContainer.new()
	_skill_panel.set_anchors_preset(Control.PRESET_CENTER)
	_skill_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.12, 0.92)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_skill_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_skill_panel)
	_skill_box = VBoxContainer.new()
	_skill_box.add_theme_constant_override("separation", 8)
	_skill_panel.add_child(_skill_box)


## Открыть/обновить выбор навыка; вызывается сценой при левелапе.
func open_skill_choice() -> void:
	if Game.skills == null or Game.skills.pending <= 0:
		_skill_panel.visible = false
		return
	for child in _skill_box.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = Loc.t("hud.skill_choice") % Game.skills.level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	_skill_box.add_child(title)
	for branch in Game.skills.cfg.get("branches", []):
		var node: Dictionary = Game.skills.next_node(String(branch["id"]))
		if node.is_empty():
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(360, 52)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 16)
		btn.text = "%s — %s\n%s" % [Loc.t(String(branch["loc"])), Loc.t(String(node["loc"])), Loc.t(String(node["desc"]))]
		var node_id := String(node["id"])
		btn.pressed.connect(func() -> void: _pick_skill(node_id))
		_skill_box.add_child(btn)
	_skill_panel.visible = true


## Выбран узел: применить бонусы герою; если уровни остались — показать выбор снова.
func _pick_skill(node_id: String) -> void:
	if Game.skills == null or hero == null:
		return
	var node: Dictionary = Game.skills.choose(node_id)
	if node.is_empty():
		return
	hero.apply_skill_bonuses(Game.skills.node_bonuses(node))
	_apply_mana_regen()
	if Game.skills.pending > 0:
		open_skill_choice()
	else:
		_skill_panel.visible = false


## Мана-кап зависит от навыка «Резерв» — сцена данжа знает формулу.
func _apply_mana_regen() -> void:
	var scene: Node = hero.get_parent()
	if scene != null and scene.has_method("_apply_mana_params"):
		scene._apply_mana_params()
		hero.mana = mini(hero.mana, hero.mana_max)


## Панель заклинаний (M3): до 9 слотов спеллбука, клавиши 1–9 (M5).
func _build_spell_bar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y = -54.0
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	for i in 9:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.07, 0.06, 0.85)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(6)
		panel.add_theme_stylebox_override("panel", style)
		panel.visible = false
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 15)
		panel.add_child(label)
		bar.add_child(panel)
		_spell_slots.append({"panel": panel, "label": label, "style": style})


func _refresh_spell_slots() -> void:
	for i in _spell_slots.size():
		var slot: Dictionary = _spell_slots[i]
		var panel: PanelContainer = slot["panel"]
		if i >= Game.spellbook.size():
			panel.visible = false
			continue
		var spell_id := String(Game.spellbook[i])
		var def: Dictionary = Game.magic.spell(spell_id)
		if def.is_empty():
			panel.visible = false
			continue
		panel.visible = true
		var cd: float = hero.spell_cd_left(spell_id)
		var ready_state: bool = cd <= 0.0 and hero.mana >= int(def.get("mana_cost", 0))
		var cd_text := " (%.1f)" % cd if cd > 0.0 else ""
		slot["label"].text = "%d. %s\n%d мана%s" % [i + 1, Loc.t(String(def["loc"])),
				int(def.get("mana_cost", 0)), cd_text]
		var school_col: Color = Game.magic.school_color(String(def["school"]))
		slot["style"].border_color = school_col
		if ready_state:
			slot["style"].set_border_width_all(2)
		else:
			slot["style"].set_border_width_all(0)
		panel.modulate = Color.WHITE if ready_state else Color(0.55, 0.55, 0.55)


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


## Подпись на весь экран: warning — по центру; hint/toast — полосы над нижним
## краем (bottom_offset — высота текста над краем, у каждой полосы свой).
func _make_screen_label(color: Color, font_size: int, v_align: int, bottom_offset := 0.0) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_top = 0.0
	label.offset_bottom = 0.0
	label.offset_left = 0.0
	label.offset_right = 0.0
	if v_align == VERTICAL_ALIGNMENT_BOTTOM:
		label.offset_top = bottom_offset - 34.0
		label.offset_bottom = bottom_offset
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
