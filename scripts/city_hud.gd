extends CanvasLayer
## HUD города (M2): пул ресурсов, жители, день/ночь, скорость/пауза,
## панель зданий, список жителей (Tab). Узлы собираются из кода.

var sim = null
var city = null                # сцена города: set_build_mode / toggle_pause / set_speed
var cfg: Dictionary = {}

var _res_label: Label
var _pop_label: Label
var _day_label: Label
var _weather_label: Label
var _hungry_label: Label
var _pollution_label: Label
var _threat_label: Label
var _hint_label: Label
var _toast_label: Label
var _toast_time := 0.0
var _pause_btn: Button
var _speed_btns: Array = []
var _autonomy_btn: Button = null   # автономная деревня (правки v1.12.0)
var _bld_btns: Array = []
var _cat_btns: Array = []          # [{btn, cat_id}] — категории построек (M11)
var _cat_popup: PopupPanel = null  # выпадающий список мастерских/ресурсных и т.д.
var _forest_label: Label = null    # гнев леса (M11)
var _necro_label: Label = null     # тьма кладбища (M11)
var _residents_panel: PanelContainer
var _residents_text: RichTextLabel
var _chron_panel: PanelContainer
var _chron_text: RichTextLabel
var _hover_panel: PanelContainer
var _hover_label: Label
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
var _research_panel: PanelContainer
var _research_box: VBoxContainer


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
	_res_label.text = "%s %d/%d   %s %d/%d   %s %d   %s %d   %s %d\n%s %d/%d   %s %d   %s %d   %s %d   %s %d" % [
		Loc.t("res.wood"), int(sim.res["wood"]), cap,
		Loc.t("res.stone"), int(sim.res["stone"]), cap,
		Loc.t("res.food"), int(sim.res["food"]),
		Loc.t("res.crystal"), int(sim.res["crystal"]),
		Loc.t("res.tools"), int(sim.res.get("tools", 0)),
		Loc.t("res.iron"), int(sim.res.get("iron", 0)), cap,
		Loc.t("res.metal"), int(sim.res.get("metal", 0)),
		Loc.t("res.kits"), int(sim.res.get("kits", 0)),
		Loc.t("res.seeds"), int(sim.res.get("seeds", 0)),
		Loc.t("res.coins"), Game.coins,
	]
	_pop_label.text = Loc.t("city.pop") % [sim.residents.size(), sim.pop_cap()]
	var day_text: String = Loc.t("city.day") % sim.day_number()
	if sim.is_night():
		_day_label.text = day_text + " · " + Loc.t("city.night")
		_day_label.add_theme_color_override("font_color", Color("#9fb8ff"))
	else:
		_day_label.text = day_text
		_day_label.add_theme_color_override("font_color", Color("#ffe9b0"))
	# погода и сезон (M14-J)
	if _weather_label != null:
		_weather_label.text = "%s · %s" % [Loc.t("weather." + String(sim.weather)),
				Loc.t("season." + String(sim.season()))]
	_hungry_label.visible = float(sim.res["food"]) <= 0.0
	_refresh_pollution()
	_refresh_threat()
	_refresh_forest_necro()
	_pause_btn.set_pressed_no_signal(bool(sim.paused))
	for i in _speed_btns.size():
		_speed_btns[i].set_pressed_no_signal(int(sim.speed) == int(cfg["speeds"][i]))
	if _autonomy_btn != null:
		if sim.autonomous:
			_autonomy_btn.text = Loc.t("city.autonomy_done_btn")
			_autonomy_btn.disabled = true
			_autonomy_btn.tooltip_text = Loc.t("city.autonomy_tip")
		else:
			_autonomy_btn.text = Loc.t("city.autonomy_btn")
			_autonomy_btn.disabled = false
			_autonomy_btn.tooltip_text = "%s\n%s" % [Loc.t("city.autonomy_tip"),
					Loc.t("city.autonomy_need") % sim.autonomy_pop()]
	if _residents_panel.visible:
		_residents_text.text = _residents_bbcode()
	if _chron_panel.visible:
		_chron_text.text = _chronicle_bbcode()
	if _magic_panel.visible:
		_refresh_magic()
	if market_visible() and int(sim.caravan_here) != _market_caravan_state:
		_market_caravan_state = int(sim.caravan_here)
		_rebuild_market()


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


## Подсказка у курсора: название здания под мышью (пустой текст — скрыть).
func set_hover_info(text: String, screen_pos: Vector2) -> void:
	if text == "":
		_hover_panel.visible = false
		return
	_hover_label.text = text
	_hover_panel.reset_size()
	var viewport_size: Vector2 = _hover_panel.get_viewport_rect().size
	var pos: Vector2 = screen_pos + Vector2(14, 18)
	pos = pos.min(viewport_size - _hover_panel.size - Vector2(4, 4))
	_hover_panel.position = pos
	_hover_panel.visible = true


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


## --- Панель рынка (M10, клавиша M): караваны и торговля мэра --------------

var _market_panel: PanelContainer = null
var _market_box: VBoxContainer = null
var _market_caravan_state := -1


func toggle_market() -> void:
	if _market_panel == null:
		return
	_market_panel.visible = not _market_panel.visible
	if _market_panel.visible:
		_rebuild_market()


func market_visible() -> bool:
	return _market_panel != null and _market_panel.visible


func _build_market_panel(root: Control) -> void:
	_market_panel = PanelContainer.new()
	_market_panel.add_theme_stylebox_override("panel", _panel_style())
	_market_panel.set_anchors_preset(Control.PRESET_CENTER)
	_market_panel.visible = false
	root.add_child(_market_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_market_panel.add_child(scroll)
	_market_box = VBoxContainer.new()
	_market_box.add_theme_constant_override("separation", 6)
	_market_box.custom_minimum_size = Vector2(540, 0)
	scroll.add_child(_market_box)


func _rebuild_market() -> void:
	for child in _market_box.get_children():
		child.queue_free()
	var mcfg: Dictionary = cfg.get("market", {})
	var title := _label(26)
	title.text = Loc.t("market.title")
	_market_box.add_child(title)
	if not sim.market_ready():
		var no := _label(18)
		no.text = Loc.t("market.need_building")
		_market_box.add_child(no)
		return
	# пришедший караван: купить/продать
	var caravan_title := _label(20)
	caravan_title.text = Loc.t("market.caravan_here" if sim.caravan_here else "market.caravan_wait")
	_market_box.add_child(caravan_title)
	if sim.caravan_here:
		for key in mcfg.get("caravan_buy", {}):
			var k := String(key)
			var price := int(ceilf(sim.caravan_price(k)))
			var sell_price := int(floorf(float(price) * float(mcfg.get("caravan_sell_mult", 0.5))))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var name_label := _label(16)
			name_label.text = "%s — %d/%d %s" % [Loc.t("res." + k), price, sell_price, Loc.t("res.coins_short")]
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			row.add_child(_m_btn(Loc.t("market.buy_btn") % 10, func() -> void: _market_deal(func() -> String: return sim.market_buy(k, 10))))
			row.add_child(_m_btn(Loc.t("market.sell_btn") % 10, func() -> void: _market_deal(func() -> String: return sim.market_sell(k, 10))))
			_market_box.add_child(row)
	# организовать караван (сделки из конфига)
	var deals_title := _label(20)
	deals_title.text = Loc.t("market.deals_title")
	_market_box.add_child(deals_title)
	for i in (mcfg.get("deals", []) as Array).size():
		var deal: Dictionary = mcfg["deals"][i]
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		var deal_label := _label(16)
		deal_label.text = Loc.t("market.deal") % [int(deal["amount"]), Loc.t("res." + String(deal["res"])),
				int(deal["days"]), int(deal["coins"])]
		deal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(deal_label)
		var idx := i
		row2.add_child(_m_btn(Loc.t("market.send_btn"), func() -> void:
			var err: String = sim.send_caravan(mcfg["deals"][idx])
			if err != "":
				toast(Loc.t("market.err_" + err))
			_rebuild_market()))
		_market_box.add_child(row2)
	# в пути
	if not sim.caravans_out.is_empty():
		var out_title := _label(18)
		out_title.text = Loc.t("market.out_title")
		_market_box.add_child(out_title)
		for c: Dictionary in sim.caravans_out:
			var line := _label(16)
			line.text = Loc.t("market.out_line") % [int(c["amount"]), Loc.t("res." + String(c["res"])), int(c["left"])]
			_market_box.add_child(line)
	var note := _label(14)
	note.text = Loc.t("market.note") % int(float(mcfg.get("loss_chance", 0.15)) * 100.0)
	note.modulate = Color(1, 1, 1, 0.7)
	_market_box.add_child(note)


func _market_deal(action: Callable) -> void:
	var err: String = action.call()
	if err != "":
		toast(Loc.t("market.err_" + err))
	_rebuild_market()


func _m_btn(text: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(action)
	return btn


## Пикер культур поля (этап 2, аспект 3): кнопки культур внизу поверх подсказки.
## defs: [{id, loc, desc}], cb(crop_id) вызывается при выборе.
var _crop_panel: PanelContainer = null
var _crop_cb: Callable = Callable()


func show_crop_pick(defs: Array, title: String, cb: Callable) -> void:
	if _crop_panel == null:
		_crop_panel = PanelContainer.new()
		_crop_panel.add_theme_stylebox_override("panel", _panel_style())
		_crop_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_crop_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_crop_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_crop_panel.position.y = -64.0
		add_child(_crop_panel)
	_crop_cb = cb
	for c in _crop_panel.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_crop_panel.add_child(box)
	var lbl := _label(16)
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for d: Dictionary in defs:
		var cid := String(d["id"])
		var btn := _m_btn(Loc.t(String(d.get("loc", cid))),
				func() -> void: _crop_picked(cid))
		btn.tooltip_text = Loc.t(String(d.get("desc", "")))
		row.add_child(btn)
	_crop_panel.visible = true


func _crop_picked(crop: String) -> void:
	hide_crop_pick()
	if _crop_cb.is_valid():
		_crop_cb.call(crop)


func hide_crop_pick() -> void:
	if _crop_panel != null:
		_crop_panel.visible = false
	_crop_cb = Callable()


func crop_pick_visible() -> bool:
	return _crop_panel != null and _crop_panel.visible


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


## Индикатор угрозы (M5): стадия и время до волны; поверх — буря и атака.
func _refresh_threat() -> void:
	if sim.raid_active:
		_threat_label.text = Loc.t("city.threat_raid") % sim.raiders.size()
		_threat_label.add_theme_color_override("font_color", Color("#ff5252"))
		return
	if sim.storm_state == "active":
		_threat_label.text = Loc.t("city.threat_storm")
		_threat_label.add_theme_color_override("font_color", Color("#b041c0"))
		return
	if sim.storm_state == "warn":
		_threat_label.text = Loc.t("city.threat_storm_warn")
		_threat_label.add_theme_color_override("font_color", Color("#ba68c8"))
		return
	var eta: float = sim.raid_eta_days()
	if sim._raid_warned:
		_threat_label.text = Loc.t("city.threat_warn") % "%.1f" % eta
		_threat_label.add_theme_color_override("font_color", Color("#ffb74d"))
		return
	var stage := String(sim.threat_stage())
	_threat_label.text = "%s · %s" % [Loc.t("city.threat_line") % Loc.t("city.threat_stage." + stage),
			Loc.t("city.threat_eta") % "%.1f" % eta]
	match stage:
		"unease":
			_threat_label.add_theme_color_override("font_color", Color("#ffe082"))
		"danger", "siege":
			_threat_label.add_theme_color_override("font_color", Color("#ffab91"))
		_:
			_threat_label.add_theme_color_override("font_color", Color("#a5d6a7"))


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


## Индикаторы вишлиста (M11): гнев леса и тьма кладбища.
func _refresh_forest_necro() -> void:
	var fcfg: Dictionary = cfg.get("forest", {})
	if _forest_label != null:
		if fcfg.is_empty() or float(sim.forest_anger) < 0.5:
			_forest_label.visible = false
		else:
			_forest_label.visible = true
			_forest_label.text = Loc.t("city.forest_anger") % int(sim.forest_anger)
			var col := "#a5d6a7"
			if float(sim.forest_anger) >= float(fcfg.get("boss_anger", 26.0)):
				col = "#ff5252"
			elif float(sim.forest_anger) >= float(fcfg.get("spirit_anger", 14.0)):
				col = "#ffb74d"
			_forest_label.add_theme_color_override("font_color", Color(col))
	if _necro_label != null:
		var has_cem := false
		for b in sim.buildings:
			if String(b["type"]) == "cemetery" and bool(b["done"]):
				has_cem = true
				break
		if not has_cem:
			_necro_label.visible = false
			return
		_necro_label.visible = true
		var text := Loc.t("city.necro_label") % int(round(float(sim.necro_dark) * 100.0))
		if bool(sim.necro_known):
			text += " · " + Loc.t("city.necro_army") % int(sim.necro_army)
		_necro_label.text = text
		var ncol := "#b0bec5"
		if sim.necro_army >= int(cfg.get("necro", {}).get("rise_at", 8)):
			ncol = "#ce93d8"
		elif bool(sim.necro_known):
			ncol = "#9fa8da"
		_necro_label.add_theme_color_override("font_color", Color(ncol))


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
	_weather_label = _label(16)
	_weather_label.add_theme_color_override("font_color", Color("#90caf9"))
	tl_box.add_child(_weather_label)
	_hungry_label = _label(20)
	_hungry_label.add_theme_color_override("font_color", Color("#ff6b57"))
	tl_box.add_child(_hungry_label)
	_pollution_label = _label(20)
	tl_box.add_child(_pollution_label)
	_threat_label = _label(20)
	tl_box.add_child(_threat_label)
	# гнев леса (M11): показывается, когда лес хоть немного тронули
	_forest_label = _label(18)
	tl_box.add_child(_forest_label)
	# тьма кладбища (M11): после постройки кладбища
	_necro_label = _label(18)
	tl_box.add_child(_necro_label)

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
	# автономная деревня (правки v1.12.0): кнопка справа от скоростей
	_autonomy_btn = Button.new()
	_autonomy_btn.text = Loc.t("city.autonomy_btn")
	_autonomy_btn.tooltip_text = Loc.t("city.autonomy_tip")
	_autonomy_btn.custom_minimum_size = Vector2(96, 40)
	_autonomy_btn.add_theme_font_size_override("font_size", 15)
	_autonomy_btn.focus_mode = Control.FOCUS_NONE
	_autonomy_btn.pressed.connect(func() -> void: city.go_autonomous())
	tr_box.add_child(_autonomy_btn)

	# --- тост по центру сверху
	_toast_label = _label(24)
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.position = Vector2(0, 70)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_toast_label)

	# --- тултип у курсора: название здания под мышью
	_hover_panel = PanelContainer.new()
	_hover_panel.add_theme_stylebox_override("panel", _panel_style())
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.visible = false
	root.add_child(_hover_panel)
	_hover_label = _label(16)
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_child(_hover_label)

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

	# --- низ: подсказка, панель категорий постройки (M11), кей-бар -------------
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
	# кей-бар: горячие клавиши всегда перед глазами (M11)
	var keybar := PanelContainer.new()
	keybar.add_theme_stylebox_override("panel", _panel_style(true))
	var keylabel := _label(14)
	keylabel.text = Loc.t("city.keys_bar")
	keylabel.modulate = Color(1, 1, 1, 0.75)
	keybar.add_child(keylabel)
	bottom.add_child(keybar)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	bottom.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	# категории построек (M11): «навёлся или нажал — выпал список мастерских»
	_cat_popup = PopupPanel.new()
	_cat_popup.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_cat_popup)
	var cat_list: Array = ["living", "resource", "craft", "defence", "magic", "special"]
	for cat_id in cat_list:
		if not (cfg.get("cats", {}) as Dictionary).has(cat_id):
			continue
		var cid := String(cat_id)
		var btn := Button.new()
		btn.text = Loc.t("cat." + cid)
		btn.tooltip_text = Loc.t("cat." + cid + "_tip")
		btn.custom_minimum_size = Vector2(128, 52)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(String(cfg["cats"][cid]["color"])))
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void: _open_cat(cid, btn))
		row.add_child(btn)
		_cat_btns.append({"btn": btn, "cat_id": cid})
	var sep := VSeparator.new()
	row.add_child(sep)

	# --- инструменты зон, дорог и посадки (M6/M11) ---
	var tools := [["field", func() -> void: city.set_zone_mode("field")],
			["pasture", func() -> void: city.set_zone_mode("pasture")],
			["living", func() -> void: city.set_zone_mode("living")]]
	for t in tools:
		var zone_type: String = t[0]
		var zbtn := Button.new()
		zbtn.text = Loc.t("zone." + zone_type)
		zbtn.tooltip_text = Loc.t("city.zone_tooltip") % Loc.t("zone." + zone_type)
		zbtn.custom_minimum_size = Vector2(104, 52)
		zbtn.add_theme_font_size_override("font_size", 17)
		zbtn.focus_mode = Control.FOCUS_NONE
		zbtn.pressed.connect(t[1])
		row.add_child(zbtn)
	var road_btn := Button.new()
	road_btn.text = Loc.t("city.road")
	road_btn.tooltip_text = Loc.t("city.road_tooltip")
	road_btn.custom_minimum_size = Vector2(104, 52)
	road_btn.add_theme_font_size_override("font_size", 17)
	road_btn.focus_mode = Control.FOCUS_NONE
	road_btn.pressed.connect(func() -> void: city.set_road_mode(not city.road_mode))
	row.add_child(road_btn)
	var plant_btn := Button.new()
	plant_btn.text = Loc.t("city.plant")
	plant_btn.tooltip_text = Loc.t("city.plant_tooltip")
	plant_btn.custom_minimum_size = Vector2(104, 52)
	plant_btn.add_theme_font_size_override("font_size", 17)
	plant_btn.focus_mode = Control.FOCUS_NONE
	plant_btn.pressed.connect(func() -> void: city.set_plant_mode(not city.plant_mode))
	row.add_child(plant_btn)

	_build_magic_panel(root)
	_build_research_panel(root)
	_build_market_panel(root)


## Выпадающий список построек категории (M11).
func _open_cat(cat_id: String, btn: Button) -> void:
	for child in _cat_popup.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_cat_popup.add_child(box)
	for b in cfg["buildings"]:
		if String(b.get("cat", "")) != cat_id:
			continue
		var type_id := String(b["id"])
		var bbtn := Button.new()
		bbtn.text = Loc.t(String(b["loc"]))
		bbtn.tooltip_text = _bld_tooltip(b)
		bbtn.custom_minimum_size = Vector2(240, 44)
		bbtn.add_theme_font_size_override("font_size", 17)
		bbtn.focus_mode = Control.FOCUS_NONE
		bbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bbtn.pressed.connect(func() -> void:
			city.set_build_mode(type_id)
			_cat_popup.hide())
		box.add_child(bbtn)
	_bld_btns = []
	_cat_popup.reset_size()
	var gs: Vector2 = btn.get_screen_position()
	_cat_popup.position = Vector2(gs.x, maxf(8.0, gs.y - _cat_popup.size.y - 8.0))
	_cat_popup.popup()


## --- Панель дисциплин города (M7, клавиша U) -------------------------------

func toggle_research() -> void:
	_research_panel.visible = not _research_panel.visible
	if _research_panel.visible:
		_rebuild_research()


func research_visible() -> bool:
	return _research_panel.visible


func _build_research_panel(root: Control) -> void:
	_research_panel = PanelContainer.new()
	_research_panel.add_theme_stylebox_override("panel", _panel_style())
	_research_panel.set_anchors_preset(Control.PRESET_CENTER)
	_research_panel.visible = false
	root.add_child(_research_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 560)
	_research_panel.add_child(scroll)
	_research_box = VBoxContainer.new()
	_research_box.add_theme_constant_override("separation", 8)
	_research_box.custom_minimum_size = Vector2(540, 0)
	scroll.add_child(_research_box)


## Пересобрать список дисциплин: заголовок ветки + кнопки её тиров.
func _rebuild_research() -> void:
	for child in _research_box.get_children():
		child.queue_free()
	var title := _label(26)
	title.text = Loc.t("research.title")
	_research_box.add_child(title)
	for branch in sim.research_cfg.get("branches", []):
		var head := _label(20)
		head.text = Loc.t(String(branch["loc"]))
		head.add_theme_color_override("font_color", Color(String(branch.get("color", "#ffffff"))))
		_research_box.add_child(head)
		var prev_researched := true
		for tier in branch.get("tiers", []):
			var tier_id := String(tier["id"])
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 44)
			btn.add_theme_font_size_override("font_size", 16)
			btn.focus_mode = Control.FOCUS_NONE
			btn.tooltip_text = Loc.t(String(tier["desc"]))
			var done: bool = sim.researched.has(tier_id)
			var parts := PackedStringArray()
			for res_key in tier.get("cost", {}):
				parts.append("%d %s" % [int(tier["cost"][res_key]), Loc.t("res." + res_key)])
			if done:
				btn.text = "✔ %s" % Loc.t(String(tier["loc"]))
				btn.disabled = true
			elif not prev_researched:
				btn.text = "🔒 %s" % Loc.t(String(tier["loc"]))
				btn.disabled = true
			else:
				btn.text = "%s (%s)" % [Loc.t(String(tier["loc"])), " + ".join(parts)]
			var captured := tier_id
			btn.pressed.connect(func() -> void: _on_research_pressed(captured))
			_research_box.add_child(btn)
			prev_researched = done


func _on_research_pressed(tier_id: String) -> void:
	var err := String(sim.study_research(tier_id))
	if err != "":
		toast(Loc.t("research." + err))
		return
	var tier: Dictionary = sim._research_tier(tier_id)
	toast(Loc.t("research.done_toast") % Loc.t(String(tier["loc"])))
	_rebuild_research()


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
	elif String(b.get("effect", "")) == "tavern":
		var tcfg: Dictionary = cfg.get("tavern", {})
		desc = desc % int(float(tcfg.get("food_per_day", 8.0)))
	elif String(b.get("effect", "")) == "decor":
		desc = desc % int(b.get("mood", 0))
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
		var name_line := String(r["name"])
		if int(r.get("partner", -1)) >= 0:
			name_line += " [color=#f48fb1]♥[/color]"   # состоит в паре (M13)
		parts.append("[b]%s[/b]" % name_line)
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
			# тайный некромант (M11): после раскрытия виден в списке жителей
			if String(r.get("secret", "")) == "necromancer" and bool(sim.necro_known):
				prof_text += " [color=#ba68c8](%s)[/color]" % Loc.t("city.necro_tag")
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
		# жизнь v3 (M14-F): личная цель и отношения
		if String(r.get("goal", "")) != "":
			parts.append("[color=#ce93d8]Цель: %s[/color]" % Loc.t("goal." + String(r["goal"])))
		var best: Dictionary = sim.rel_best(r)
		if not best.is_empty():
			parts.append("[color=#80cbc4]%s %s[/color]" % [Loc.t("city.rel_friend"), String(best["other"]["name"])])
		var worst: Dictionary = sim.rel_worst(r)
		if not worst.is_empty():
			parts.append("[color=#ef9a9a]%s %s[/color]" % [Loc.t("city.rel_foe"), String(worst["other"]["name"])])
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
	if v.begins_with("goal."):
		return Loc.t(v)
	if v in ["wood", "stone", "food", "crystal", "tools", "iron", "metal", "kits", "seeds"]:
		return Loc.t("res." + v)
	if v in ["sheep", "cow", "pig", "chicken", "chick", "turkey"]:
		return Loc.t("animal." + v)
	for prof in cfg["professions"]:
		if String(prof["id"]) == v:
			return Loc.t(String(prof["loc"]))
	for b in cfg["buildings"]:
		if String(b["id"]) == v:
			return Loc.t(String(b["loc"]))
	return v


func _prof_loc(prof_id: String) -> String:
	if prof_id == "elder":
		# в большом городе староста становится мэром
		var title := "prof.mayor" if sim.residents.size() >= int(cfg.get("mayor_pop", 15)) else "prof.elder"
		return Loc.t(title)
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


## Рамочный стиль панелей (M11): тёмный фон, светлая окантовка, скругления.
func _panel_style(compact := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.9)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.42, 0.36, 0.24, 0.9)
	if compact:
		style.content_margin_left = 10.0
		style.content_margin_right = 10.0
		style.content_margin_top = 4.0
		style.content_margin_bottom = 4.0
	else:
		style.set_content_margin_all(12)
	return style


func _set_rect(control: Control, pos: Vector2, size: Vector2) -> void:
	if pos.x < 0:
		control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		control.position = pos
	else:
		control.position = pos
	control.custom_minimum_size = size
