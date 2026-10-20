extends CanvasLayer
## Панель управления деревней (M14-H, клавиша L): законы с голосованием
## совета, выбор божества, дипломатия (репутация и дань).

const FACTIONS_CFG_PATH := "res://data/factions.json"

var _panel: PanelContainer
var _content: VBoxContainer
var _status: Label


func _ready() -> void:
	layer = 60
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(470, 0)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.08, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470, 500)
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


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color("#a5d6a7"))
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	_content.add_child(_header(Loc.t("gov.title")))
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color("#ffd766"))
	_content.add_child(_status)
	# --- законы ---
	_content.add_child(_spacer(6))
	_content.add_child(_header(Loc.t("gov.laws")))
	var councilors: Array = Game.city_sim.council()
	var names := PackedStringArray()
	for c in councilors:
		names.append(String(c["name"]))
	_content.add_child(_hint(Loc.t("gov.council") % ", ".join(names)))
	var laws_cfg: Dictionary = Game.city_sim._laws_cfg()
	for l: Dictionary in laws_cfg.get("laws", []):
		_content.add_child(_law_row(l))
	# --- вера ---
	_content.add_child(_spacer(8))
	_content.add_child(_header(Loc.t("gov.faith")))
	var staffed: bool = Game.city_sim.temple_staffed()
	_content.add_child(_hint(Loc.t("gov.temple_staffed") % (Loc.t("gov.yes") if staffed else Loc.t("gov.no"))))
	var gods: Dictionary = Game.city_sim._religion_cfg()
	for g: Dictionary in gods.get("gods", []):
		_content.add_child(_god_row(g, staffed))
	# --- дипломатия ---
	_content.add_child(_spacer(8))
	_content.add_child(_header(Loc.t("gov.diplomacy")))
	var fcfg: Dictionary = _read_json(FACTIONS_CFG_PATH)
	for f: Dictionary in fcfg.get("factions", []):
		_content.add_child(_faction_row(f, fcfg))
	_content.add_child(_spacer(6))
	_status.text = ""
	if _status.text == "" and Game.world_sim != null and Game.world_sim.bandits_peace():
		_status.text = Loc.t("gov.peace_bandits")


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	return l


func _law_row(l: Dictionary) -> Control:
	var id := String(l["id"])
	var active: bool = Game.city_sim.has_law(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	var state := " [color=#a5d6a7]•[/color]" if active else ""
	label.text = "%s%s — %s" % [Loc.t(String(l["loc"])), state, Loc.t(String(l["desc"]))]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var btn := Button.new()
	btn.text = Loc.t("gov.repeal") if active else Loc.t("gov.propose")
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void: _vote(id))
	row.add_child(btn)
	return row


func _god_row(g: Dictionary, staffed: bool) -> Control:
	var id := String(g["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var chosen: String = String(Game.city_sim.god)
	var label := Label.new()
	var mark := " [color=#a5d6a7]•[/color]" if chosen == id else ""
	label.text = "%s%s — %s" % [Loc.t(String(g["loc"])), mark, Loc.t(String(g["desc"]))]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var btn := Button.new()
	btn.text = Loc.t("gov.choose")
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not staffed
	btn.pressed.connect(func() -> void:
		var err: String = Game.city_sim.pray(id)
		_set_status(Loc.t(err) if err != "" else Loc.t("god.chosen") % Loc.t(String(g["loc"]))))
	row.add_child(btn)
	return row


func _faction_row(f: Dictionary, fcfg: Dictionary) -> Control:
	var id := String(f["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var rep: float = Game.world_sim.get_rep(id) if Game.world_sim != null else 0.0
	var col := "#a5d6a7" if rep > 0 else ("#ef9a9a" if rep < 0 else "#c8c8c8")
	var label := Label.new()
	label.text = "%s — [color=%s]%+d[/color]" % [Loc.t(String(f["loc"])), col, int(rep)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var btn := Button.new()
	btn.text = Loc.t("gov.tribute") % int(fcfg.get("tribute_cost", 20))
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = Game.coins < int(fcfg.get("tribute_cost", 20))
	btn.pressed.connect(func() -> void: _tribute(id, fcfg))
	row.add_child(btn)
	return row


func _tribute(faction: String, fcfg: Dictionary) -> void:
	var cost := int(fcfg.get("tribute_cost", 20))
	if Game.coins < cost:
		_set_status(Loc.t("gov.no_coins"))
		return
	Game.coins -= cost
	Game.world_sim.tribute(faction)
	Game.codex_seen("factions", faction)   # кодекс (M14-K)
	_set_status(Loc.t("gov.tribute_sent"))
	_rebuild()


func _vote(law_id: String) -> void:
	var result: Dictionary = Game.city_sim.propose_law(law_id)
	if result.get("err", "") != "":
		_set_status(Loc.t(String(result["err"])))
		return
	var verb: String = Loc.t("gov.law_passed") if bool(result["ok"]) else Loc.t("gov.law_rejected")
	_set_status("%s (%d/%d)" % [verb, int(result["yes"]), int(result["no"])])
	_rebuild()


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
