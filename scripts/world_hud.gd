extends CanvasLayer
## HUD карты мира (M8): день и монеты, подсказка, тосты, панель точки
## интереса (путь в днях) и торговая панель (монеты + живой обмен).
## Узлы собираются из кода — как в city_hud.gd.

var world = null                # сцена world.gd: map/sim/start_travel_to/_use_poi

var _day_label: Label
var _coins_label: Label
var _hint_label: Label
var _toast_label: Label
var _toast_time := 0.0
var _poi_panel: PanelContainer
var _poi_title: Label
var _poi_info: RichTextLabel
var _poi_travel_btn: Button
var _poi_picked: Dictionary = {}
var _poi_days := 0
var _trade_panel: PanelContainer
var _trade_poi: Dictionary = {}
var _trade_coins: Label
var _trade_box: VBoxContainer
var _loot_items: Array = []


func init(world_ref) -> void:
	world = world_ref


func _ready() -> void:
	var loot: Variant = _read_json("res://data/loot.json")
	_loot_items = loot.get("items", []) if loot is Dictionary else []
	_build()


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast_label.text = ""


func refresh() -> void:
	var day := 0
	if Game.city_sim != null:
		day = Game.city_sim.day_number()
	else:
		day = world.sim.day
	_day_label.text = Loc.t("world.day") % day
	_coins_label.text = Loc.t("res.coins") + ": %d" % Game.coins
	if _trade_panel.visible:
		_trade_coins.text = Loc.t("res.coins") + ": %d" % Game.coins


func toast(msg: String) -> void:
	_toast_label.text = msg
	_toast_time = 3.5


func set_hint(msg: String) -> void:
	_hint_label.text = msg


# --- панель точки интереса -------------------------------------------------

func open_poi_panel(poi: Dictionary, days: int) -> void:
	_poi_picked = poi
	_poi_days = days
	_poi_panel.visible = true
	_refresh_poi()


func close_poi_panel() -> void:
	_poi_panel.visible = false
	_poi_picked = {}


func poi_panel_visible() -> bool:
	return _poi_panel.visible


func _refresh_poi() -> void:
	if _poi_picked.is_empty():
		return
	var poi: Dictionary = _poi_picked
	var kind := String(poi["kind"])
	var title := Loc.t("world.poi." + kind)
	if String(poi.get("faction", "")) != "":
		title += " — " + Loc.t("world.faction." + String(poi["faction"]))
	_poi_title.text = title
	var lines := PackedStringArray()
	match kind:
		"camp", "settlement":
			lines.append(Loc.t("world.strength") % int(poi["strength"]))
			if kind == "settlement":
				lines.append(Loc.t("world.status_" + String(poi["state"])))
			if _in_siege(poi):
				lines.append("[color=#ff8a80]" + Loc.t("world.under_siege") + "[/color]")
		"dungeon", "ruins", "dragon_castle":
			if String(poi["biome"]) != "":
				lines.append(Loc.t(String(_biome_loc(String(poi["biome"])))))
		"obelisk":
			lines.append(Loc.t("world.obelisk_desc"))
	var here: bool = poi["tile"] == world.hero_tile
	if here:
		lines.append(Loc.t("world.you_here"))
	else:
		lines.append(Loc.t("world.days_away") % _poi_days)
	if int(poi.get("cleared_day", -1)) >= 0 and kind != "city" and kind != "settlement":
		lines.append("[color=#b0b0b0]" + Loc.t("world.cleared_short") + "[/color]")
	_poi_info.text = "\n".join(lines)
	_poi_travel_btn.visible = not here and world.travel.is_empty()
	if _poi_travel_btn.visible:
		_poi_travel_btn.text = Loc.t("world.travel_btn") % _poi_days


func _in_siege(poi: Dictionary) -> bool:
	for s: Dictionary in world.sim.sieges:
		if int(s["settlement_id"]) == int(poi["id"]):
			return true
	return false


func _biome_loc(biome_id: String) -> String:
	var dungeon: Dictionary = _read_json("res://data/dungeon.json")
	return String(dungeon.get("biomes", {}).get(biome_id, {}).get("loc", ""))


# --- торговля (ответ №40): монеты + живой обмен -----------------------------

func trade_visible() -> bool:
	return _trade_panel.visible


func open_trade(poi: Dictionary) -> void:
	_trade_poi = poi
	_rebuild_trade()
	_trade_panel.visible = true


func close_trade() -> void:
	_trade_panel.visible = false
	_trade_poi = {}


func _rebuild_trade() -> void:
	for child in _trade_box.get_children():
		child.queue_free()
	var tcfg: Dictionary = world.cfg.get("trade", {})
	var pool: Dictionary = Game.city_sim.res if Game.city_sim != null else {}
	var cult := String(_trade_poi.get("faction", "")) == "cult"
	# покупка за монеты (в пул города — караван доставит)
	_trade_box.add_child(_label(Loc.t("world.buy_title"), 18))
	for key in tcfg.get("buy", {}):
		var price := int(ceilf(world.sim.buy_price(String(key), _trade_poi)))
		var row := HBoxContainer.new()
		var name_label := _label("%s — %d %s" % [Loc.t("res." + String(key)), price, Loc.t("res.coins_short")], 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_trade_btn(Loc.t("world.buy_btn") % 5, func() -> void: _buy(String(key), 5)))
		_trade_box.add_child(row)
	# продажа за монеты
	_trade_box.add_child(_label(Loc.t("world.sell_title"), 18))
	for key in tcfg.get("buy", {}):
		var price := int(floorf(world.sim.sell_price(String(key), _trade_poi)))
		var row2 := HBoxContainer.new()
		var name2 := _label("%s — %d %s" % [Loc.t("res." + String(key)), price, Loc.t("res.coins_short")], 16)
		name2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(name2)
		row2.add_child(_trade_btn(Loc.t("world.sell_btn") % 5, func() -> void: _sell(String(key), 5)))
		_trade_box.add_child(row2)
	# живой обмен: ресурс на ресурс
	_trade_box.add_child(_label(Loc.t("world.barter_title"), 18))
	for deal: Dictionary in tcfg.get("barter", []):
		var row3 := HBoxContainer.new()
		var text := "%d %s → %d %s" % [int(deal["give_n"]), Loc.t("res." + String(deal["give"])),
				int(deal["get_n"]), Loc.t("res." + String(deal["get"]))]
		var name3 := _label(text, 16)
		name3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row3.add_child(name3)
		row3.add_child(_trade_btn(Loc.t("world.barter_btn"), func() -> void: _barter(deal)))
		_trade_box.add_child(row3)
	# культ продаёт руну за монеты
	if cult:
		_trade_box.add_child(_label(Loc.t("world.rune_title"), 18))
		var rune_id: String = world.sim.cult_rune_offer()
		var row4 := HBoxContainer.new()
		var rune_name := _rune_name(rune_id)
		var price_rune := int(tcfg.get("rune_price", 25))
		var name4 := _label("%s — %d %s" % [rune_name, price_rune, Loc.t("res.coins_short")], 16)
		name4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row4.add_child(name4)
		row4.add_child(_trade_btn(Loc.t("world.rune_btn"), func() -> void: _buy_rune(rune_id)))
		_trade_box.add_child(row4)
	var note := _label(Loc.t("world.trade_note"), 14)
	note.modulate = Color(1, 1, 1, 0.7)
	_trade_box.add_child(note)


func _buy(key: String, count: int) -> void:
	var cap: int = Game.city_sim.storage_cap() if Game.city_sim != null else 999999
	var out: Dictionary = world.sim.trade_buy(Game.city_sim.res, Game.coins, key, count, _trade_poi, cap)
	Game.coins = int(out["coins"])
	if String(out["err"]) == "":
		var cost := int(ceilf(world.sim.buy_price(key, _trade_poi) * count))
		toast(Loc.t("world.bought") % [count, Loc.t("res." + key), cost])
	else:
		toast(Loc.t("world." + String(out["err"])))
	_rebuild_trade()


func _sell(key: String, count: int) -> void:
	var out: Dictionary = world.sim.trade_sell(Game.city_sim.res, Game.coins, key, count, _trade_poi)
	Game.coins = int(out["coins"])
	if String(out["err"]) == "":
		var earned := int(floorf(world.sim.sell_price(key, _trade_poi) * count))
		toast(Loc.t("world.sold") % [count, Loc.t("res." + key), earned])
	else:
		toast(Loc.t("world." + String(out["err"])))
	_rebuild_trade()


func _barter(deal: Dictionary) -> void:
	var out: Dictionary = world.sim.trade_barter(Game.city_sim.res, deal)
	if String(out["err"]) == "":
		toast(Loc.t("world.bartered") % [int(deal["give_n"]), Loc.t("res." + String(deal["give"])),
				int(deal["get_n"]), Loc.t("res." + String(deal["get"]))])
	else:
		toast(Loc.t("world." + String(out["err"])))
	_rebuild_trade()


func _buy_rune(rune_id: String) -> void:
	var out: Dictionary = world.sim.trade_rune(Game.inventory, Game.coins, rune_id)
	Game.coins = int(out["coins"])
	if String(out["err"]) == "":
		toast(Loc.t("world.rune_bought") % _rune_name(rune_id))
	else:
		toast(Loc.t("world." + String(out["err"])))
	_rebuild_trade()


func _rune_name(rune_id: String) -> String:
	for item in _loot_items:
		if String(item["id"]) == rune_id:
			return Loc.t(String(item["loc"]))
	return rune_id


# --- построение узлов -------------------------------------------------------

func _build() -> void:
	var top := PanelContainer.new()
	top.position = Vector2(12, 10)
	add_child(top)
	var top_box := HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 24)
	top.add_child(top_box)
	_day_label = _label("", 20)
	top_box.add_child(_day_label)
	_coins_label = _label("", 20)
	_coins_label.add_theme_color_override("font_color", Color("#ffe082"))
	top_box.add_child(_coins_label)

	_hint_label = _label("", 18)
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.position.y = -46
	add_child(_hint_label)

	_toast_label = _label("", 20)
	_toast_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.position.y = 54
	_toast_label.add_theme_color_override("font_color", Color("#ffe9b0"))
	add_child(_toast_label)

	_poi_panel = PanelContainer.new()
	_poi_panel.position = Vector2(1580, 90)
	_poi_panel.custom_minimum_size = Vector2(320, 0)
	_poi_panel.visible = false
	add_child(_poi_panel)
	var poi_box := VBoxContainer.new()
	poi_box.add_theme_constant_override("separation", 8)
	_poi_panel.add_child(poi_box)
	_poi_title = _label("", 20)
	poi_box.add_child(_poi_title)
	_poi_info = RichTextLabel.new()
	_poi_info.fit_content = true
	_poi_info.bbcode_enabled = true
	_poi_info.custom_minimum_size = Vector2(300, 60)
	poi_box.add_child(_poi_info)
	_poi_travel_btn = Button.new()
	_poi_travel_btn.pressed.connect(func() -> void:
		world.start_travel_to(_poi_picked["tile"])
		close_poi_panel())
	poi_box.add_child(_poi_travel_btn)
	var close_btn := Button.new()
	close_btn.text = Loc.t("world.close_btn")
	close_btn.pressed.connect(close_poi_panel)
	poi_box.add_child(close_btn)

	_trade_panel = PanelContainer.new()
	_trade_panel.position = Vector2(560, 120)
	_trade_panel.custom_minimum_size = Vector2(800, 0)
	_trade_panel.visible = false
	add_child(_trade_panel)
	var trade_box := VBoxContainer.new()
	trade_box.add_theme_constant_override("separation", 6)
	_trade_panel.add_child(trade_box)
	var trade_head := HBoxContainer.new()
	trade_head.add_theme_constant_override("separation", 20)
	trade_box.add_child(trade_head)
	var trade_title := _label(Loc.t("world.trade_title"), 24)
	trade_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_head.add_child(trade_title)
	_trade_coins = _label("", 20)
	trade_head.add_child(_trade_coins)
	var trade_close := Button.new()
	trade_close.text = Loc.t("world.close_btn")
	trade_close.pressed.connect(close_trade)
	trade_head.add_child(trade_close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	trade_box.add_child(scroll)
	_trade_box = VBoxContainer.new()
	_trade_box.add_theme_constant_override("separation", 4)
	_trade_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_trade_box)


func _trade_btn(text: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(action)
	return btn


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
