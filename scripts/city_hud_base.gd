# Часть: HUD города — переменные-лейблы, init/refresh/toast/подсказки, тогглы
# панелей, рынок и выбор культуры.
# Структура v1.62.0: бывший city_hud.gd (1344 строки) разрезан на
# extends-цепочку CanvasLayer (city_hud_base -> city_hud_build -> city_hud.gd) —
# это один класс, city.gd создаёт его по-прежнему через city_hud.gd.
extends CanvasLayer

## v1.68: единая тема интерфейса (панели/кнопки/тосты)
const UITheme := preload("res://scripts/ui_theme.gd")

## HUD города (M2): пул ресурсов, жители, день/ночь, скорость/пауза,
## панель зданий, список жителей (Tab). Узлы собираются из кода.

var sim = null
var city = null                # сцена города: set_build_mode / toggle_pause / set_speed
var cfg: Dictionary = {}
var guest := false             # v1.41: герой в поселении НПС — стройкой город
                               # управляет сам, панель стройки спрятана

var _res_counts: Dictionary = {}      # res id -> Label числа (v1.53: иконки)
var _res_name: Label = null           # v1.54: мгновенная подпись под курсором
var _res_icons: Dictionary = {}       # res id -> ImageTexture (кэш)
var _pop_label: Label
var _day_label: Label
var _weather_label: Label
var _hungry_label: Label
var _pollution_label: Label
var _threat_label: Label
var _hint_label: Label
var _toast_label: Label
var _toast_time := 0.0
var _toast_stack: VBoxContainer = null   # v1.68: стек тостов
var _toast_slots: Array = []             # PanelContainer x3
var _toast_times: Array = [0.0, 0.0, 0.0]
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
var _hud_res_fold: Button = null   # v1.97: свернуть ресурсы в полоску
var _hud_res_strip: Label = null   # v1.97.1: полоска цифр в свёрнутом виде
var _hud_res_open := true          # v1.97.1: панель поселения развёрнута?
var _hud_bld_fold: Button = null   # v1.97: свернуть панель построек
var _chron_panel: PanelContainer
var _chron_text: RichTextLabel
var _hover_panel: PanelContainer
var _hover_label: Label
var _magic_panel: PanelContainer
var _magic_scroll: ScrollContainer
var _magic_box: VBoxContainer
var _pollution_big: Label
var _spell_craft_rows: Array = []
var _slot_hint: Label = null
var _rune_slot_a: OptionButton
var _rune_slot_b: OptionButton
var _craft_result: Label
var _craft_btn: Button
var _city_spell_btns: Array = []   # [{btn, spell_id}]
var _hero_spell_btns: Array = []   # [{btn, spell_id}] — боевые заклинания героя (v1.49)
var _enchant_btns: Array = []      # [{btn, ench_id}]
var _enchant_hint_label: Label
var _enchant_colors: Dictionary = {}
var _research_panel: PanelContainer
var _research_box: VBoxContainer


## Вызвать до add_child. guest — режим гостя в поселении НПС («Мир v2», 3).
func init(sim_ref, city_ref, city_cfg: Dictionary, guest_mode := false) -> void:
	sim = sim_ref
	city = city_ref
	cfg = city_cfg
	guest = guest_mode


func _ready() -> void:
	_build()
	# v1.68: единая тема кнопок HUD после сборки дерева
	UITheme.apply_tree(self)


func _process(delta: float) -> void:
	# v1.68: тик стека тостов — плавное затухание каждой плашки
	for i in _toast_slots.size():
		if not _toast_slots[i].visible:
			continue
		_toast_times[i] -= delta
		if float(_toast_times[i]) < 0.5:
			_toast_slots[i].modulate.a = maxf(0.0, float(_toast_times[i]) / 0.5)
		if float(_toast_times[i]) <= 0.0:
			_toast_slots[i].visible = false
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast_label.text = ""


func refresh() -> void:
	if sim == null:
		return
	# v1.53: ресурсы — ИКОНКИ с числами (вместо двух текстовых строк);
	# названия — во всплывающей подсказке у иконки
	for id in _res_counts:
		var val := int(Game.coins) if id == "coins" else int(sim.res.get(id, 0))
		var lbl: Label = _res_counts[id]
		var txt := str(val)
		if lbl.text != txt:
			lbl.text = txt
	_pop_label.text = Loc.t("city.pop") % [sim.residents.size(), sim.pop_cap()]
	# v1.97.1: полоска свёрнутой панели — ключевые цифры + таймер волны
	if _hud_res_strip != null and not _hud_res_open:
		var wave_d := 999
		var nxt: Variant = sim.get("_next_raid_at")
		if nxt != null:
			wave_d = int(maxf(0.0, (float(nxt) - float(sim.time)) / maxf(1.0, float(sim.cfg.get("day_length", 300.0)))))
		_hud_res_strip.text = "День %d · еда %d · брёвна %d · камень %d · волна через %dд" % [
			sim.day_number(), int(sim.res.get("food", 0)), int(sim.res.get("wood", 0)),
			int(sim.res.get("stone", 0)), wave_d]
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


## Тосты (v1.68): стек до 3 плашек — события города больше не затирают
## друг друга; повтор того же текста продлевает свою плашку.
func toast(msg: String) -> void:
	for i in _toast_slots.size():
		var slot: PanelContainer = _toast_slots[i]
		if slot.visible and (slot.get_child(0) as Label).text == msg:
			_toast_times[i] = 3.0
			slot.modulate.a = 1.0
			return
	var idx := -1
	for i in _toast_slots.size():
		if not _toast_slots[i].visible:
			idx = i
			break
	if idx < 0:
		idx = _oldest_toast()
	var slot: PanelContainer = _toast_slots[idx]
	(slot.get_child(0) as Label).text = msg
	slot.visible = true
	slot.modulate = Color.WHITE
	_toast_times[idx] = 3.0
	SfxLib.play("toast")   # v1.65

func _oldest_toast() -> int:
	var best := 0
	for i in _toast_times.size():
		if float(_toast_times[i]) < float(_toast_times[best]):
			best = i
	return best


## Подсказка под панелью зданий. Правка v1.21: одинаковый текст не перезаписываем —
## присвоение text каждый кадр форсит переразметку лейбла и режет FPS.
func set_hint(msg: String) -> void:
	if _hint_label.text == msg:
		return
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
## Правка v1.21: тот же текст не пересобираем — reset_size() каждый кадр дорог.
func set_hover_info(text: String, screen_pos: Vector2) -> void:
	if text == "":
		if _hover_panel.visible:
			_hover_panel.visible = false
		return
	if _hover_label.text != text:
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



# --- заглушки для парсера (структура v1.62.0) ------------------------------
# Часть выше зовёт функции, живущие ниже; реальные тела — в city_hud_build.gd
# и city_hud.gd. Сигнатуры держите в синхроне.
func _build() -> void:
	pass

func _rebuild_rune_slots() -> void:
	pass

func _refresh_magic() -> void:
	pass

func _refresh_pollution() -> void:
	pass

func _refresh_threat() -> void:
	pass

func _refresh_forest_necro() -> void:
	pass

func _build_research_panel(root: Control) -> void:
	pass

func _bld_tooltip(b: Dictionary) -> String:
	return ""

func _residents_bbcode() -> String:
	return ""

func _chronicle_bbcode() -> String:
	return ""

func _label(size: int) -> Label:
	return null

func _toggle_btn(text: String, on_press: Callable) -> Button:
	return null

func _panel_style(compact := false) -> StyleBoxFlat:
	return null

func _set_rect(control: Control, pos: Vector2, size: Vector2) -> void:
	pass

func res_icon(id: String) -> ImageTexture:
	return null

func _prof_loc(prof: String) -> String:
	return prof   # заглушка base; настоящая локализация — в city_hud.gd


# --- диалог выбора (v1.81: староста «Память мира», док 18) ------------------
# Ленивая конструкция: панель строится при первом открытии, порядок сборки
# UI не трогаем.
var _choice_panel: PanelContainer = null
var _choice_title: Label = null
var _choice_info: RichTextLabel = null
var _choice_box: VBoxContainer = null


func open_choice(title: String, lines: Array, choices: Array) -> void:
	if _choice_panel == null:
		_choice_panel = PanelContainer.new()
		_choice_panel.position = Vector2(1150, 90)
		_choice_panel.custom_minimum_size = Vector2(540, 0)
		_choice_panel.visible = false
		add_child(_choice_panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		_choice_panel.add_child(col)
		_choice_title = _label(22)
		_choice_title.add_theme_color_override("font_color", Color("#ffe082"))
		col.add_child(_choice_title)
		_choice_info = RichTextLabel.new()
		_choice_info.fit_content = true
		_choice_info.bbcode_enabled = true
		_choice_info.custom_minimum_size = Vector2(560, 40)
		col.add_child(_choice_info)
		_choice_box = VBoxContainer.new()
		_choice_box.add_theme_constant_override("separation", 4)
		col.add_child(_choice_box)
	_choice_title.text = title
	_choice_info.text = "\n".join(PackedStringArray(lines))
	for child in _choice_box.get_children():
		child.queue_free()
	for c in choices:
		var btn := Button.new()
		btn.text = String(c["text"])
		btn.disabled = bool(c.get("disabled", false))
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void:
			close_choice()
			(c["action"] as Callable).call())
		_choice_box.add_child(btn)
	_choice_panel.visible = true


func close_choice() -> void:
	if _choice_panel != null:
		_choice_panel.visible = false


func choice_visible() -> bool:
	return _choice_panel != null and _choice_panel.visible


# --- Дневник жителя (v1.89): клик по имени в списке (Tab) -------------------
var _res_detail_panel: PanelContainer = null
var _res_detail_text: RichTextLabel = null


func open_resident(uid: int) -> void:
	var r: Dictionary = sim.resident_by_uid(uid)
	if r.is_empty():
		return
	if _res_detail_panel == null:
		_res_detail_panel = PanelContainer.new()
		_res_detail_panel.add_theme_stylebox_override("panel", _panel_style())
		_res_detail_panel.visible = false
		_set_rect(_res_detail_panel, Vector2(250, 90), Vector2(410, 700))
		add_child(_res_detail_panel)
		var box := VBoxContainer.new()
		_res_detail_panel.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var title := _label(20)
		title.text = Loc.t("city.resident_panel")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var close := _toggle_btn("×", func() -> void: close_resident())
		close.text = "×"
		head.add_child(close)
		_res_detail_text = RichTextLabel.new()
		_res_detail_text.bbcode_enabled = true
		_res_detail_text.fit_content = true
		box.add_child(_res_detail_text)
	var b := PackedStringArray()
	b.append("[b][color=#ffe082]%s[/color][/b]" % String(r["name"]))
	if String(r["prof"]) == "":
		b.append("[color=#fff59d]%s[/color]" % Loc.t("city.state.child"))
	else:
		b.append(_prof_loc(String(r["prof"])))
	var trait_names := PackedStringArray()
	for t_id in r.get("traits", []):
		trait_names.append(Loc.t("trait." + String(t_id)))
	if not trait_names.is_empty():
		b.append("[color=#9fa8da]%s[/color]" % ", ".join(trait_names))
	b.append("[color=#c8c8c8]%s[/color]" % Loc.t("city.state." + String(r["state"])))
	b.append("%s: %d%%" % [Loc.t("city.mood_label"), int(r.get("mood", 50.0))])
	if int(r.get("partner", -1)) >= 0:
		var sp: Dictionary = sim._resident_by_id(int(r["partner"]))
		if not sp.is_empty():
			b.append("[color=#f48fb1]%s %s[/color]" % [Loc.t("city.spouse"), String(sp["name"])])
	if String(r.get("goal", "")) != "":
		b.append("[color=#ce93d8]%s: %s[/color]" % [Loc.t("city.goal_label"), Loc.t("goal." + String(r["goal"]))])
	var best: Dictionary = sim.rel_best(r)
	if not best.is_empty():
		b.append("[color=#80cbc4]%s %s[/color]" % [Loc.t("city.rel_friend"), String(best["other"]["name"])])
	var worst: Dictionary = sim.rel_worst(r)
	if not worst.is_empty():
		b.append("[color=#ef9a9a]%s %s[/color]" % [Loc.t("city.rel_foe"), String(worst["other"]["name"])])
	# v1.90: биография — проза из происхождения, прошлого и страха
	var bio: PackedStringArray = _resident_bio_lines(r)
	if not bio.is_empty():
		b.append("")
		b.append("[b][color=#ffe082]%s[/color][/b]" % Loc.t("city.bio"))
		for line in bio:
			b.append(line)
	b.append("")
	b.append("[b][color=#ffe082]%s[/color][/b]" % Loc.t("city.thoughts"))
	for th in sim.resident_thoughts(r):
		var tk := String(th["k"])
		var ta: Array = th.get("a", [])
		var tl: String = Loc.t(tk) if (ta as Array).is_empty() else String(Loc.t(tk)) % ta
		if tk == "thought.goal":
			tl = Loc.t("thought.goal") % Loc.t("goal." + String(ta[0]))
		b.append("[i][color=#c5cae9]«%s»[/color][/i]" % tl)
	b.append("")
	b.append("[b][color=#ffe082]%s[/color][/b]" % Loc.t("city.diary"))
	var log: Array = r.get("log", [])
	for i in range(log.size() - 1, -1, -1):
		var e: Dictionary = log[i]
		b.append("[color=#8d8d8d][%s %d][/color] %s" % [Loc.t("city.day_word"), int(e["d"]), _diary_paragraph(r, e)])
	_res_detail_text.text = "\n".join(b)
	_res_detail_panel.visible = true


func close_resident() -> void:
	if _res_detail_panel != null:
		_res_detail_panel.visible = false


## Запись дневника (v1.92): абзац от первого лица в голосе жителя
## (diary.<событие>.<голос>); нет ключа — телеграфный запасной стиль.
func _diary_paragraph(r: Dictionary, e: Dictionary) -> String:
	var base := String(e["k"]).substr(5)
	if String(e["k"]) == "dlog.slip":
		var srole := String((e.get("a", []) as Array)[0])
		return Loc.t("diary.slip." + srole)
	# v1.94: нераскрытый тайный житель пишет СУХО (нейтральный стиль) —
	# это само по себе улика внимательному читателю
	if _secret_hidden_public(r):
		return _dlog_text_of(e)
	var goal_id := ""
	if base == "goal_done":
		var ga: Array = e.get("a", [])
		goal_id = String(ga[0]) if not (ga as Array).is_empty() else ""
	var key := "diary.%s.%s.%s" % [base, goal_id, sim.res_voice(r)] if goal_id != "" 			else "diary.%s.%s" % [base, sim.res_voice(r)]
	var fmt := Loc.t(key)
	if fmt == key:
		return _dlog_text_of(e)
	var args: Array = []
	for a in (e.get("a", []) as Array):
		var s := String(a)
		if base in ["job", "conscript"]:
			args.append(_prof_loc(s))
		elif base == "goal_set":
			args.append(Loc.t("goal." + s))
		elif base == "note":
			args.append(Loc.t("season.word." + s))
		else:
			args.append(s)
	if args.is_empty():
		return fmt
	return fmt % args


## Тайный житель нераскрыт? (HUD не знает внутренностей сима —
## дублируем простое правило по данным жителя и флагам сима.)
func _secret_hidden_public(r: Dictionary) -> bool:
	var s := String(r.get("secret", ""))
	if s == "" or bool(r.get("secret_revealed", false)):
		return false
	if s == "necromancer":
		return not bool(sim.necro_known)
	return true


## Строка дневника: ключ dlog.* + аргументы локализуются здесь.
func _dlog_text_of(e: Dictionary) -> String:
	var fmt := Loc.t(String(e["k"]))
	var args: Array = []
	for a in (e.get("a", []) as Array):
		var s := String(a)
		if String(e["k"]) in ["dlog.job", "dlog.conscript"]:
			args.append(_prof_loc(s))
		elif String(e["k"]) == "dlog.goal_set":
			args.append(Loc.t("goal." + s))
		else:
			args.append(s)
	if args.is_empty():
		return fmt
	return fmt % args


## Биография жителя (v1.90): проза из происхождения, прежнего
## ремесла, страха и мечты. Старые сейвы без origin — общая строка.
func _resident_bio_lines(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var origin := String(r.get("origin", ""))
	if origin == "":
		out.append(Loc.t("city.bio.unknown"))
		return out
	if origin == "born_here" or origin == "golem":
		out.append(Loc.t("origin." + origin))
	elif origin == "lost_forest":
		out.append(String(Loc.t("origin." + origin)) % int(r.get("origin_arg", 5)))
	else:
		out.append(Loc.t("origin." + origin))
	var past := String(r.get("past_prof", ""))
	var prof := String(r["prof"])
	if past != "" and prof != "":
		var past_l: String = Loc.t("past." + past)
		if _past_matches(prof, past):
			out.append(String(Loc.t("city.bio.same_craft")) % past_l)
		else:
			out.append(String(Loc.t("city.bio.past_and_new")) % [past_l, _prof_loc(prof)])
	if String(r.get("fear", "")) != "":
		out.append(String(Loc.t("city.bio.fear")) % Loc.t("fear." + String(r["fear"])))
	if String(r.get("goal", "")) != "":
		out.append(String(Loc.t("city.bio.dream")) % Loc.t("goal." + String(r["goal"])))
	if String(r.get("like", "")) != "":
		out.append(String(Loc.t("city.bio.like")) % Loc.t("like." + String(r["like"])))
	if String(r.get("dislike", "")) != "":
		out.append(String(Loc.t("city.bio.dislike")) % Loc.t("dislike." + String(r["dislike"])))
	if String(r.get("habit", "")) != "":
		out.append(String(Loc.t("city.bio.habit")) % Loc.t("habit." + String(r["habit"])))
	return out


## Связь прошлого ремесла с нынешней профессией (v1.90).
func _past_matches(prof: String, past: String) -> bool:
	return (
		(past == "axemaster" and prof == "lumberjack")
		or (past == "hunter_past" and prof == "hunter")
		or (past == "peasant" and prof == "farmer")
		or (past == "herbalist" and prof == "healer")
		or (past == "smith_past" and prof in ["smith", "smelter", "armorer"])
		or (past == "laborer" and prof == "porter")
	)
