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
var _hint_label: Label
var _toast_label: Label
var _toast_time := 0.0
var _pause_btn: Button
var _speed_btns: Array = []
var _bld_btns: Array = []
var _residents_panel: PanelContainer
var _residents_text: RichTextLabel


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
	var cap := sim.storage_cap()
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
	_pause_btn.set_pressed_no_signal(bool(sim.paused))
	for i in _speed_btns.size():
		_speed_btns[i].set_pressed_no_signal(int(sim.speed) == int(cfg["speeds"][i]))
	if _residents_panel.visible:
		_residents_text.text = _residents_bbcode()


func toast(msg: String) -> void:
	_toast_label.text = msg
	_toast_time = 3.0


func set_hint(msg: String) -> void:
	_hint_label.text = msg


func toggle_residents() -> void:
	_residents_panel.visible = not _residents_panel.visible


func residents_visible() -> bool:
	return _residents_panel.visible


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
	_residents_text = RichTextLabel.new()
	_residents_text.bbcode_enabled = true
	_residents_text.fit_content = true
	_residents_text.custom_minimum_size = Vector2(390, 0)
	rp_box.add_child(_residents_text)

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
		btn.pressed.connect(func() -> void: city.set_build_mode(type_id))
		bld_box.add_child(btn)
		_bld_btns.append(btn)


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
		var col := "#ff6b57" if String(r["state"]) == "hungry" else "#c8c8c8"
		lines.append("%s — %s — [color=%s]%s[/color]" % [
			String(r["name"]), _prof_loc(String(r["prof"])), col, Loc.t(state_key)])
	return "\n".join(lines)


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
