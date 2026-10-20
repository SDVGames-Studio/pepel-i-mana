extends CanvasLayer
## Доска объявлений (M14-K, клавиша Q): заказы жителей и фракций.
## bring — сдать предметы кнопкой; hunt — счётчик охоты героя; build —
## закрывается постройкой. Награда — монеты герою, радость заказчику.

var _panel: PanelContainer
var _content: VBoxContainer


func _ready() -> void:
	layer = 60
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.06, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_rebuild()


func is_open() -> bool:
	return _panel.visible


func close() -> void:
	_panel.visible = false


func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = Loc.t("quest.title")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd766"))
	_content.add_child(title)
	_content.add_child(_hint(Loc.t("quest.hint")))
	if Game.city_sim == null or Game.city_sim.quests.is_empty():
		var empty := Label.new()
		empty.text = Loc.t("quest.empty")
		_content.add_child(empty)
		return
	for q in Game.city_sim.quests:
		_content.add_child(_quest_row(q))


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	return l


func _quest_row(q: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var kind_text := ""
	var can_deliver := false
	match String(q["kind"]):
		"bring":
			var have: int = Game.count_item(String(q["item"]))
			kind_text = Loc.t("quest.bring") % [int(q["need"]), Loc.t("item." + String(q["item"])), have]
			can_deliver = have >= int(q["need"])
		"hunt":
			kind_text = Loc.t("quest.hunt") % [int(q["progress"]), int(q["need"])]
		"build":
			kind_text = Loc.t("quest.build") % Loc.t("bld." + String(q["type"]))
	label.text = kind_text
	row.add_child(line1)
	var line2 := HBoxContainer.new()
	line2.add_theme_constant_override("separation", 8)
	var sub := Label.new()
	sub.text = "%s · %s · %d ⛃" % [String(q["customer"]), Loc.t("quest.days") % int(q["days"]), int(q["reward"])]
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line2.add_child(sub)
	if String(q["kind"]) == "bring":
		var btn := Button.new()
		btn.text = Loc.t("quest.deliver")
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = not can_deliver
		btn.pressed.connect(func() -> void:
			var err: String = Game.city_sim.quest_deliver(int(q["id"]), Game.inventory)
			if err == "":
				Game.stat("quests")
			_rebuild())
		line2.add_child(btn)
	row.add_child(line2)
	return row
