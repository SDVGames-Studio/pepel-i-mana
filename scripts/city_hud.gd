extends CanvasLayer
## HUD города (M2): пул ресурсов, жители, день/ночь, скорость/пауза,
## панель зданий, список жителей (Tab). Узлы собираются из кода.

var sim = null
var city = null                # сцена города: set_build_mode / toggle_pause / set_speed
var cfg: Dictionary = {}

var _res_label: Label
var _pop_label: Label
var _day_label: Label
var _hungry_label: Label
var _pollution_label: Label
var _hint_label: Label
var _toast_label: Label
var _toast_time := 0.0
var _pause_btn: Button
var _speed_btns: Array = []
var _bld_btns: Array = []
var _residents_panel: PanelContainer
var _residents_text: RichTextLabel
var _chron_panel: PanelContainer
var _chron_text: RichTextLabel
var _magic_panel: PanelContainer
var _magic_scroll: ScrollContainer
var _magic_box: VBoxContainer
var _pollution_big: Label
var _rune_slot_a: OptionButton
var _rune_slot_b: OptionButton
var _craft_result: Label
var _craft_btn: Button
var _city_spell_btns: Array = []   # [{btn, spell_id}]
var _enchant_btns: Array = []      # [{btn, ench_id}]
var _enchant_hint_label: Label
var _enchant_colors: Dictionary = {}


## Вызвать до add_child.
func init(sim_ref, city_ref, city_cfg: Dictionary) -> void:
	sim = sim_ref
	city = city_ref
	cfg = city_cfg


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast_label.text = ""


func refresh() -> void:
	if sim == null:
		return
	var cap: int = sim.storage_cap()
	_res_label.text = "%s %d/%d   %s %d/%d   %s %d   %s %d" % [
		Loc.t("res.wood"), int(sim.res["wood"]), cap,
		Loc.t("res.stone"), int(sim.res["stone"]), cap,
		Loc.t("res.food"), int(sim.res["food"]),
		Loc.t("res.crystal"), int(sim.res["crystal"]),
	]
	_pop_label.text = Loc.t("city.pop") % [sim.residents.size(), sim.pop_cap()]
	var day_text: String = Loc.t("city.day") % sim.day_number()
	if sim.is_night():
		_day_label.text = day_text + " · " + Loc.t("city.night")
		_day_label.add_theme_color_override("font_color", Color("#9fb8ff"))
	else:
		_day_label.text = day_text
		_day_label.add_theme_color_override("font_color", Color("#ffe9b0"))
	_hungry_label.visible = float(sim.res["food"]) <= 0.0
	_refresh_pollution()
	_pause_btn.set_pressed_no_signal(bool(sim.paused))
	for i in _speed_btns.size():
		_speed_btns[i].set_pressed_no_signal(int(sim.speed) == int(cfg["speeds"][i]))
	if _residents_panel.visible:
		_residents_text.text = _residents_bbcode()
	if _chron_panel.visible:
		_chron_text.text = _chronicle_bbcode()
	if _magic_panel.visible:
		_refresh_magic()


func toast(msg: String) -> void:
	_toast_label.text = msg
	_toast_time = 3.0


func set_hint(msg: String) -> void:
	_hint_label.text = msg


func toggle_residents() -> void:
	_residents_panel.visible = not _residents_panel.visible


func residents_visible() -> bool:
	return _residents_panel.visible


func toggle_chronicle() -> void:
	_chron_panel.visible = not _chron_panel.visible


func chronicle_visible() -> bool:
	return _chron_panel.visible


func set_enchant_colors(colors: Dictionary) -> void:
	_enchant_colors = colors


## Подсказка под панелью зданий: что выбрано для зачарования.
func set_enchant_hint(text: String) -> void:
	_enchant_hint_label.text = text


## --- Панель магии (M3, клавиша R) ---------------------------------------

func toggle_magic() -> void:
	_magic_panel.visible = not _magic_panel.visible
	if _magic_panel.visible:
		_rebuild_rune_slots()


func magic_visible() -> bool:
	return _magic_panel.visible


func _build_magic_panel(root: Control) -> void:
	_magic_panel = PanelContainer.new()
	_magic_panel.add_theme_stylebox_override("panel", _panel_style())
	_magic_panel.set_anchors_preset(Control.PRESET_CENTER)
	_magic_panel.visible = false
	root.add_child(_magic_panel)
	_magic_scroll = ScrollContainer.new()
	_magic_scroll.custom_minimum_size = Vector2(520, 560)
	_magic_panel.add_child(_magic_scroll)
	_magic_box = VBoxContainer.new()
	_magic_box.add_theme_constant_override("separation", 8)
	_magic_box.custom_minimum_size = Vector2(500, 0)
	_magic_scroll.add_child(_magic_box)

	var title := _label(26)
	title.text = Loc.t("magic.title")
	_magic_box.add_child(title)

	_pollution_big = _label(20)
	_magic_box.add_child(_pollution_big)

	# городские заклинания (алтарь + кристаллы)
	var spells_title := _label(20)
	spells_title.text = Loc.t("magic.city_spells")
	_magic_box.add_child(spells_title)
	for def in Game.magic.spells():
		if String(def["where"]) != "city":
			continue
		var spell_id := String(def["id"])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_font_size_override("font_size", 17)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = Loc.t(String(def["desc"]))
		btn.pressed.connect(func() -> void: city.cast_city_spell(spell_id))
		_magic_box.add_child(btn)
		_city_spell_btns.append({"btn": btn, "spell_id": spell_id})

	# крафт: две руны -> заклинание (таблица рецептов, ответ №58)
	var craft_title := _label(20)
	craft_title.text = Loc.t("magic.craft")
	_magic_box.add_child(craft_title)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	_magic_box.add_child(slots)
	_rune_slot_a = OptionButton.new()
	_rune_slot_b = OptionButton.new()
	for slot in [_rune_slot_a, _rune_slot_b]:
		slot.custom_minimum_size = Vector2(240, 36)
		slot.focus_mode = Control.FOCUS_NONE
		slot.item_selected.connect(func(_idx: int) -> void: _update_craft_preview())
		slots.add_child(slot)
	_craft_result = _label(18)
	_magic_box.add_child(_craft_result)
	_craft_btn = Button.new()
	_craft_btn.text = Loc.t("magic.craft_make")
	_craft_btn.custom_minimum_size = Vector2(0, 40)
	_craft_btn.focus_mode = Control.FOCUS_NONE
	_craft_btn.pressed.connect(_on_craft_pressed)
	_magic_box.add_child(_craft_btn)

	# зачарование зданий: руна + кристалл, затем клик по зданию
	var ench_title := _label(20)
	ench_title.text = Loc.t("magic.enchant")
	_magic_box.add_child(ench_title)
	for def in Game.magic.enchantments():
		var ench_id := String(def["id"])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_font_size_override("font_size", 17)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = Loc.t(String(def["desc"]))
		btn.pressed.connect(func() -> void: city.set_enchant_mode(ench_id))
		_magic_box.add_child(btn)
		_enchant_btns.append({"btn": btn, "ench_id": ench_id})
	_enchant_hint_label = _label(18)
	_enchant_hint_label.add_theme_color_override("font_color", Color("#ffe082"))
	_magic_box.add_child(_enchant_hint_label)


## Выпадающие списки рун из рюкзака (перестраиваются при каждом открытии).
func _rebuild_rune_slots() -> void:
	for slot in [_rune_slot_a, _rune_slot_b]:
		slot.clear()
		for stack in Game.inventory:
			var item_id := String(stack["id"])
			if not item_id.begins_with("rune_"):
				continue
			var text := "%s ×%d" % [Loc.t(_rune_loc(item_id)), int(stack["count"])]
			slot.add_item(text)
			slot.set_item_metadata(slot.item_count - 1, item_id)
	_update_craft_preview()


func _rune_loc(item_id: String) -> String:
	for item in _loot_items():
		if String(item["id"]) == item_id:
			return String(item["loc"])
	return item_id


func _loot_items() -> Array:
	return _read_loot_json().get("items", [])


func _read_loot_json() -> Dictionary:
	var f := FileAccess.open("res://data/loot.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _selected_rune(slot: OptionButton) -> String:
	if slot.selected < 0:
		return ""
	return String(slot.get_item_metadata(slot.selected))


func _update_craft_preview() -> void:
	var a := _selected_rune(_rune_slot_a)
	var b := _selected_rune(_rune_slot_b)
	if a == "" or b == "":
		_craft_result.text = Loc.t("magic.craft_pick")
		_craft_btn.disabled = true
		return
	var spell_id: String = Game.magic.recipe_result(a, b)
	if spell_id == "":
		_craft_result.text = Loc.t("magic.craft_none")
		_craft_btn.disabled = true
		return
	var def: Dictionary = Game.magic.spell(spell_id)
	_craft_result.text = "%s — %s" % [Loc.t(String(def["loc"])), Loc.t(String(def["desc"]))]
	if Game.has_spell(spell_id):
		_craft_result.text += " " + Loc.t("magic.craft_known")
		_craft_btn.disabled = true
	else:
		_craft_btn.disabled = false


func _on_craft_pressed() -> void:
	city.craft_spell(_selected_rune(_rune_slot_a), _selected_rune(_rune_slot_b))
	_rebuild_rune_slots()


## Обновление панели: шкала, кнопки (активны только у работающего алтаря).
func _refresh_magic() -> void:
	_pollution_big.text = _pollution_text()
	var altar_ok: bool = sim.altar_ready()
	for entry in _city_spell_btns:
		var def: Dictionary = Game.magic.spell(String(entry["spell_id"]))
		entry["btn"].text = "%s (%d %s)" % [
			Loc.t(String(def["loc"])), int(def.get("crystals_cost", 0)), Loc.t("res.crystal")]
		entry["btn"].disabled = not altar_ok
	for entry in _enchant_btns:
		var def: Dictionary = Game.magic.enchantment(String(entry["ench_id"]))
		entry["btn"].text = "%s (%d %s + %s)" % [
			Loc.t(String(def["loc"])), int(def.get("crystals", 1)),
			Loc.t("res.crystal"), _rune_loc(String(def["rune"]))]
		entry["btn"].disabled = not altar_ok
		if _enchant_colors.has(String(entry["ench_id"])):
			entry["btn"].add_theme_color_override("font_color", _enchant_colors[String(entry["ench_id"])])


func _refresh_pollution() -> void:
	_pollution_label.text = _pollution_text()


func _pollution_text() -> String:
	var band := String(sim.pollution_band())
	var text := Loc.t("magic.pollution") % [int(sim.pollution), Loc.t("magic.p_" + band)]
	var col := "#c8c8c8"
	match band:
		"mild": col = "#a5d6a7"
		"heart": col = "#ba68c8"
		"wild": col = "#ff6b57"
	_pollution_label.add_theme_color_override("font_color", Color(col))
	return text


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- левый верх: ресурсы, жители, день
	var top_left := PanelContainer.new()
	top_left.add_theme_stylebox_override("panel", _panel_style())
	_set_rect(top_left, Vector2(12, 12), Vector2(560, 0))
	root.add_child(top_left)
	var tl_box := VBoxContainer.new()
	top_left.add_child(tl_box)
	_res_label = _label(22)
	tl_box.add_child(_res_label)
	_pop_label = _label(20)
	tl_box.add_child(_pop_label)
	_day_label = _label(20)
	tl_box.add_child(_day_label)
	_hungry_label = _label(20)
	_hungry_label.add_theme_color_override("font_color", Color("#ff6b57"))
	tl_box.add_child(_hungry_label)
	_pollution_label = _label(20)
	tl_box.add_child(_pollution_label)

	# --- правый верх: пауза и скорость
	var top_right := PanelContainer.new()
	top_right.add_theme_stylebox_override("panel", _panel_style())
	_set_rect(top_right, Vector2(-560, 12), Vector2(548, 0))
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(top_right)
	var tr_box := HBoxContainer.new()
	tr_box.add_theme_constant_override("separation", 8)
	top_right.add_child(tr_box)
	_pause_btn = _toggle_btn(Loc.t("city.paused"), func() -> void: city.toggle_pause())
	tr_box.add_child(_pause_btn)
	for s in cfg["speeds"]:
		var speed_value: int = int(s)
		var btn := _toggle_btn("x%d" % speed_value, func() -> void: city.set_speed(speed_value))
		tr_box.add_child(btn)
		_speed_btns.append(btn)

	# --- тост по центру сверху
	_toast_label = _label(24)
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.position = Vector2(0, 70)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_toast_label)

	# --- центр справа: список жителей (Tab)
	_residents_panel = PanelContainer.new()
	_residents_panel.add_theme_stylebox_override("panel", _panel_style())
	_residents_panel.visible = false
	_set_rect(_residents_panel, Vector2(-430, 90), Vector2(410, 700))
	_residents_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_residents_panel)
	var rp_box := VBoxContainer.new()
	_residents_panel.add_child(rp_box)
	var rp_title := _label(22)
	rp_title.text = Loc.t("city.residents_panel")
	rp_box.add_child(rp_title)
	var rp_scroll := ScrollContainer.new()
	rp_scroll.custom_minimum_size = Vector2(390, 640)
	rp_box.add_child(rp_scroll)
	_residents_text = RichTextLabel.new()
	_residents_text.bbcode_enabled = true
	_residents_text.fit_content = true
	_residents_text.custom_minimum_size = Vector2(370, 0)
	rp_scroll.add_child(_residents_text)

	# --- центр слева: летопись (C)
	_chron_panel = PanelContainer.new()
	_chron_panel.add_theme_stylebox_override("panel", _panel_style())
	_chron_panel.visible = false
	_set_rect(_chron_panel, Vector2(12, 210), Vector2(430, 480))
	root.add_child(_chron_panel)
	var ch_box := VBoxContainer.new()
	_chron_panel.add_child(ch_box)
	var ch_title := _label(22)
	ch_title.text = Loc.t("city.chronicle_panel")
	ch_box.add_child(ch_title)
	var ch_scroll := ScrollContainer.new()
	ch_scroll.custom_minimum_size = Vector2(410, 420)
	ch_box.add_child(ch_scroll)
	_chron_text = RichTextLabel.new()
	_chron_text.bbcode_enabled = true
	_chron_text.fit_content = true
	_chron_text.custom_minimum_size = Vector2(390, 0)
	ch_scroll.add_child(_chron_text)

	# --- низ: подсказка + панель зданий
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y = -12.0
	bottom.add_theme_constant_override("separation", 6)
	root.add_child(bottom)
	_hint_label = _label(20)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_hint_label)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	bottom.add_child(panel)
	var bld_box := HBoxContainer.new()
	bld_box.add_theme_constant_override("separation", 6)
	panel.add_child(bld_box)
	for b in cfg["buildings"]:
		var type_id := String(b["id"])
		var btn := Button.new()
		btn.text = Loc.t(String(b["loc"]))
		btn.tooltip_text = _bld_tooltip(b)
		btn.custom_minimum_size = Vector2(150, 52)
		btn.add_theme_font_size_override("font_size", 18)
		btn.focus_mode = Control.FOCUS_NONE   # Tab не должен гонять фокус по кнопкам
		btn.pressed.connect(func() -> void: city.set_build_mode(type_id))
		bld_box.add_child(btn)
		_bld_btns.append(btn)

	_build_magic_panel(root)


## Описание здания для подсказки: название, цена, эффект.
func _bld_tooltip(b: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in b["cost"]:
		parts.append("%d %s" % [int(b["cost"][key]), Loc.t("res." + key)])
	var desc := Loc.t(String(b["desc"]))
	if b.has("produce"):
		desc = desc % int(b["produce"]["per_day"])
	elif String(b.get("effect", "")) == "storage":
		desc = desc % int(cfg["storage_per_warehouse"])
	return "%s\n%s\n%s" % [Loc.t(String(b["loc"])), " / ".join(parts), desc]


func _residents_bbcode() -> String:
	var lines := PackedStringArray()
	for r in sim.residents:
		var state_key := "city.state." + String(r["state"])
		var state_col := "#c8c8c8"
		match String(r["state"]):
			"hungry":
				state_col = "#ff6b57"
			"sick":
				state_col = "#ffb74d"
			"wounded":
				state_col = "#ff8a65"
			"child":
				state_col = "#fff59d"
		var parts := PackedStringArray()
		parts.append("[b]%s[/b]" % String(r["name"]))
		if String(r["prof"]) == "":
			parts.append("[color=#fff59d]%s[/color]" % Loc.t("city.state.child"))
		else:
			var prof_text := _prof_loc(String(r["prof"]))
			var extras: Array = r.get("prof_extra", [])
			if not (extras as Array).is_empty():
				var extra_names := PackedStringArray()
				for p_id in extras:
					extra_names.append(_prof_loc(String(p_id)))
				prof_text += " [color=#80cbc4](+%s)[/color]" % ", ".join(extra_names)
			parts.append(prof_text)
			var traits := PackedStringArray()
			for t_id in r.get("traits", []):
				traits.append(Loc.t("trait." + String(t_id)))
			if not traits.is_empty():
				parts.append("[color=#9fa8da]%s[/color]" % ", ".join(traits))
		parts.append("[color=%s]%s[/color]" % [state_col, Loc.t(state_key)])
		if String(r["prof"]) != "":
			var mood := int(r.get("mood", 50.0))
			var mood_col := "#c8c8c8"
			if mood >= 70:
				mood_col = "#a5d6a7"
			elif mood <= 30:
				mood_col = "#ff6b57"
			var skill_key := "skill.novice"
			if int(r.get("rank", 0)) >= 5:
				skill_key = "skill.master"
			elif int(r.get("rank", 0)) >= 3:
				skill_key = "skill.expert"
			parts.append("[color=%s]%d%%[/color]" % [mood_col, mood])
			parts.append(Loc.t(skill_key))
		lines.append(" — ".join(parts))
	# почему не идут беженцы и не рождаются дети (M4-фикс по фидбеку)
	var block: String = sim.growth_block()
	if block != "":
		lines.append("[color=#ffb74d]%s[/color]" % Loc.t(block))
	return "\n".join(lines)


## Строка летописи: ключ + аргументы локализуются здесь (в симуляции — только id).
func _chronicle_bbcode() -> String:
	var lines := PackedStringArray()
	var entries: Array = sim.chronicle
	var start := maxi(0, entries.size() - 60)
	for i in range(entries.size() - 1, start - 1, -1):
		var e: Dictionary = entries[i]
		lines.append("[color=#8d8d8d][День %d][/color] %s" % [int(e["day"]), _chron_text_of(e)])
	return "\n".join(lines)


func _chron_text_of(e: Dictionary) -> String:
	var fmt: String = Loc.t(String(e["key"]))
	var args: Array = []
	for k in ["a", "b"]:
		var v := String(e.get(k, ""))
		if v != "":
			args.append(_chron_arg(v))
	if args.is_empty():
		return fmt
	return fmt % args


func _chron_arg(v: String) -> String:
	if v in ["wood", "stone", "food", "crystal"]:
		return Loc.t("res." + v)
	for prof in cfg["professions"]:
		if String(prof["id"]) == v:
			return Loc.t(String(prof["loc"]))
	return v


func _prof_loc(prof_id: String) -> String:
	for prof in cfg["professions"]:
		if String(prof["id"]) == prof_id:
			return Loc.t(String(prof["loc"]))
	return prof_id


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	return l


func _toggle_btn(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(90, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.85)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	return style


func _set_rect(control: Control, pos: Vector2, size: Vector2) -> void:
	if pos.x < 0:
		control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		control.position = pos
	else:
		control.position = pos
	control.custom_minimum_size = size
