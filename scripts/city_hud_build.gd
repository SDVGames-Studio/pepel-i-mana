# Часть: HUD города — панель магии (руны/крафт/заклинания), статическая
# раскладка всех панелей (_build) и категории построек.
# Один класс, поведение не меняется.
extends "res://scripts/city_hud_base.gd"


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

	# боевые заклинания героя (v1.49: паритет с данжем) — маной героя,
	# каст по курсору/на себя; видны только изученные (spellbook)
	var hero_title := _label(20)
	hero_title.text = Loc.t("magic.hero_spells")
	_magic_box.add_child(hero_title)
	for def in Game.magic.spells():
		if String(def["where"]) != "dungeon" or String(def["id"]) == "light_beacon":
			continue
		var sid := String(def["id"])
		var hbtn := Button.new()
		hbtn.custom_minimum_size = Vector2(0, 40)
		hbtn.add_theme_font_size_override("font_size", 17)
		hbtn.focus_mode = Control.FOCUS_NONE
		hbtn.tooltip_text = "%s\n%s: %d" % [Loc.t(String(def["desc"])), Loc.t("magic.mana"), int(def.get("mana_cost", 0))]
		hbtn.pressed.connect(func() -> void: city.cast_combat_spell(sid))
		_magic_box.add_child(hbtn)
		_hero_spell_btns.append({"btn": hbtn, "spell_id": sid})

	# v1.66 (магия-просто): список ВСЕХ рецептов с наличием рун —
	# никакой «угадайки» парами; кнопка Крафт у каждой строки
	var craft_title := _label(20)
	craft_title.text = Loc.t("magic.craft")
	_magic_box.add_child(craft_title)
	var craft_scroll := ScrollContainer.new()
	craft_scroll.custom_minimum_size = Vector2(0, 240)
	_magic_box.add_child(craft_scroll)
	var craft_box := VBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 6)
	craft_scroll.add_child(craft_box)
	_spell_craft_rows = []
	for r in Game.magic.cfg.get("recipes", []):
		var spell_id := String(r["spell"])
		var cdef: Dictionary = Game.magic.spell(spell_id)
		if cdef.is_empty():
			continue
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _panel_style(true))
		var vbox := VBoxContainer.new()
		row.add_child(vbox)
		var name_label := _label(15)
		name_label.text = Loc.t(String(cdef["loc"]))
		vbox.add_child(name_label)
		var need_label := _label(13)
		need_label.modulate = Color(1, 1, 1, 0.72)
		vbox.add_child(need_label)
		var btn := Button.new()
		btn.text = Loc.t("magic.craft_make")
		btn.custom_minimum_size = Vector2(0, 30)
		btn.focus_mode = Control.FOCUS_NONE
		var ra := String(r["a"])
		var rb := String(r["b"])
		btn.pressed.connect(func() -> void:
			city.craft_spell(ra, rb)
			_rebuild_craft_rows())
		vbox.add_child(btn)
		craft_box.add_child(row)
		_spell_craft_rows.append({"spell_id": spell_id, "a": ra, "b": rb,
				"need": need_label, "btn": btn})
	# v1.66: подсказка быстрого каста Z/X — первые два изученных
	_slot_hint = _label(14)
	_slot_hint.modulate = Color(1, 1, 1, 0.7)
	_magic_box.add_child(_slot_hint)

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
func _rebuild_craft_rows() -> void:
	_update_craft_preview()


## v1.66: статусы строк крафта — руны рюкзака против каждого рецепта.
func _update_craft_preview() -> void:
	var known_lines: Array = []
	for row in _spell_craft_rows:
		var spell_id := String(row["spell_id"])
		var ra := int(Game.count_item(String(row["a"])))
		var rb := int(Game.count_item(String(row["b"])))
		var need_pair := 2 if String(row["a"]) == String(row["b"]) else 1
		var need_label: Label = row["need"]
		var btn: Button = row["btn"]
		if Game.has_spell(spell_id):
			var lvl := Game.spell_level(spell_id)
			need_label.text = "%s — %s" % [Loc.t("magic.craft_known"),
					Loc.t("magic.level") % lvl]
			btn.visible = false
			known_lines.append("%s (ур. %d)" % [Loc.t("spell." + spell_id), lvl])
			continue
		btn.visible = true
		var have_a := ra >= (2 if String(row["a"]) == String(row["b"]) else 1)
		var have_b := rb >= (2 if String(row["b"]) == String(row["a"]) else 1)
		var names := "%s + %s" % [Loc.t(_rune_loc(String(row["a"]))),
				Loc.t(_rune_loc(String(row["b"])))]
		if have_a and have_b:
			need_label.text = "%s — %s" % [names, Loc.t("magic.craft_ready")]
			btn.disabled = false
		else:
			var miss_arr: Array = []
			if not have_a:
				miss_arr.append(Loc.t(_rune_loc(String(row["a"]))))
			if not have_b:
				miss_arr.append(Loc.t(_rune_loc(String(row["b"]))))
			need_label.text = "%s — %s %s" % [names, Loc.t("magic.craft_need"),
					" + ".join(miss_arr)]
			btn.disabled = true
	# подсказка быстрого каста: первые два изученных (Z/X в городе)
	if _slot_hint != null:
		var parts: Array = []
		for i in mini(2, Game.spellbook.size()):
			parts.append("%s — %s" % ["ZX"[i], Loc.t("spell." + String(Game.spellbook[i]))])
		_slot_hint.text = Loc.t("magic.slots_hint") % (" + ".join(parts) if not parts.is_empty() else Loc.t("magic.slots_none"))


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



func _selected_rune(_slot: OptionButton) -> String:
	return ""   # v1.66: дропдауны рун заменены списком рецептов


## Обновление панели: шкала, кнопки (активны только у работающего алтаря).
func _refresh_magic() -> void:
	_update_craft_preview()   # v1.66: статусы крафта всегда свежие
	_pollution_big.text = _pollution_text()
	var altar_ok: bool = sim.altar_ready()
	for entry in _city_spell_btns:
		var def: Dictionary = Game.magic.spell(String(entry["spell_id"]))
		entry["btn"].text = "%s (%d %s)" % [
			Loc.t(String(def["loc"])), int(def.get("crystals_cost", 0)), Loc.t("res.crystal")]
		entry["btn"].disabled = not altar_ok
	# боевые заклинания героя: видны только изученные; недоступны без маны/на кулдауне
	var hero_mana: int = city.hero.mana
	for entry in _hero_spell_btns:
		var def: Dictionary = Game.magic.spell(String(entry["spell_id"]))
		var learned: bool = Game.has_spell(String(entry["spell_id"]))
		entry["btn"].visible = learned
		if not learned:
			continue
		var cd_left: float = city.hero.spell_cd_left(String(entry["spell_id"]))
		entry["btn"].text = "%s (%d %s%s)" % [
			Loc.t(String(def["loc"])), int(def.get("mana_cost", 0)), Loc.t("magic.mana"),
			("" if cd_left <= 0.0 else " | %dс" % ceili(cd_left))]
		entry["btn"].disabled = hero_mana < int(def.get("mana_cost", 0)) or cd_left > 0.0
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


func _add_autonomy_btn(tr_box: HBoxContainer) -> void:
	_autonomy_btn = Button.new()
	_autonomy_btn.text = Loc.t("city.autonomy_btn")
	_autonomy_btn.tooltip_text = Loc.t("city.autonomy_tip")
	_autonomy_btn.custom_minimum_size = Vector2(96, 40)
	_autonomy_btn.add_theme_font_size_override("font_size", 15)
	_autonomy_btn.focus_mode = Control.FOCUS_NONE
	_autonomy_btn.pressed.connect(func() -> void: city.go_autonomous())
	tr_box.add_child(_autonomy_btn)


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
	# v1.53: панель ресурсов — сетка ИКОНОК 6×2 (число рядом с картинкой,
	# название ресурса — всплывающая подсказка)
	var res_grid := GridContainer.new()
	res_grid.columns = 6
	res_grid.add_theme_constant_override("h_separation", 8)
	res_grid.add_theme_constant_override("v_separation", 2)
	tl_box.add_child(res_grid)
	for rid in ["wood", "stone", "food", "copper", "silver", "gold",
			"iron", "metal", "crystal", "gems", "tools", "kits",
			"amber", "pearls", "lux", "seeds", "saplings", "coins"]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var icon := TextureRect.new()
		icon.texture = res_icon(rid)
		icon.custom_minimum_size = Vector2(18, 18)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = Loc.t("res." + rid)
		cell.add_child(icon)
		var num := _label(19)
		num.text = "0"
		num.tooltip_text = icon.tooltip_text
		cell.add_child(num)
		res_grid.add_child(cell)
		_res_counts[rid] = num
		# v1.54: наведение показывает название СРАЗУ (тултип Godot тянется
		# ~секунду — заказчик просил быстрее) — подпись под сеткой
		var rid_cap: String = rid
		cell.mouse_entered.connect(func() -> void:
			_res_name.text = Loc.t("res." + rid_cap))
		cell.mouse_exited.connect(func() -> void:
			_res_name.text = "")
	# строка мгновенной подписи
	_res_name = _label(15)
	_res_name.add_theme_color_override("font_color", Color("#e8d9a8"))
	tl_box.add_child(_res_name)
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
	# автономная деревня (правки v1.12.0): кнопка справа от скоростей;
	# в поселении НПС кнопки нет — он уже автономен (№120)
	if not guest:
		_add_autonomy_btn(tr_box)

	# --- тост по центру сверху
	# v1.68: стек тостов — до 3 событий видны одновременно, каждое в
	# тематической плашке (раньше сообщения затирали друг друга)
	_toast_stack = VBoxContainer.new()
	_toast_stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_stack.position = Vector2(0, 64)
	_toast_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_stack.add_theme_constant_override("separation", 4)
	_toast_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_toast_stack)
	for i in 3:
		var slot := PanelContainer.new()
		var sb := UITheme.toast_panel()
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		slot.add_theme_stylebox_override("panel", sb)
		var lb := _label(22)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(lb)
		slot.visible = false
		_toast_stack.add_child(slot)
		_toast_slots.append(slot)
	_toast_label = (_toast_slots[0].get_child(0) as Label)

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
	# v1.37.1: версия игры в правом нижнем углу города — сразу видно,
	# какая сборка запущена (путаница «правки не поменялись» приёмки)
	var ver := _label(12)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.position = Vector2(-52.0, -22.0)
	ver.modulate = Color(1, 1, 1, 0.45)
	var vf := FileAccess.open("res://data/version.json", FileAccess.READ)
	if vf != null:
		var vd: Variant = JSON.parse_string(vf.get_as_text())
		vf.close()
		ver.text = "v" + String((vd as Dictionary).get("version", "?"))
	root.add_child(ver)
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
	panel.visible = not guest   # гость не строит: панели инструментов нет (№120)
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

	# --- инструменты зон, дорог и посадки (M6/M11; правки v1.21: поле
	# распахивает ферма, инструмент «Поле» остался для смены культуры кликом
	# по готовой грядке; размечается вручную только пастбище) ---
	var tools := [["field", func() -> void: city.set_zone_mode("field")],
			["pasture", func() -> void: city.set_zone_mode("pasture")]]
	for t in tools:
		var zone_type: String = t[0]
		var zbtn := Button.new()
		zbtn.text = Loc.t("zone." + zone_type)
		zbtn.tooltip_text = Loc.t("city.zone_tooltip_field" if zone_type == "field" else "city.zone_tooltip") \
				% Loc.t("zone." + zone_type)
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
	# перенос зданий (этап 2, аспект 5): бесплатно, клик по зданию и месту
	var move_btn := Button.new()
	move_btn.text = Loc.t("city.move")
	move_btn.tooltip_text = Loc.t("city.move_tooltip")
	move_btn.custom_minimum_size = Vector2(104, 52)
	move_btn.add_theme_font_size_override("font_size", 17)
	move_btn.focus_mode = Control.FOCUS_NONE
	move_btn.pressed.connect(func() -> void: city.set_move_mode(not city.move_mode))
	row.add_child(move_btn)
	# перенос главной площади (правки v1.20): клик по новому месту
	var plaza_btn := Button.new()
	plaza_btn.text = Loc.t("city.plaza_move")
	plaza_btn.tooltip_text = Loc.t("city.plaza_move_tooltip")
	plaza_btn.custom_minimum_size = Vector2(104, 52)
	plaza_btn.add_theme_font_size_override("font_size", 17)
	plaza_btn.focus_mode = Control.FOCUS_NONE
	plaza_btn.pressed.connect(func() -> void: city.set_plaza_mode(not city.plaza_mode))
	row.add_child(plaza_btn)

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

