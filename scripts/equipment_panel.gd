extends CanvasLayer
## Панель экипировки (M14-B, issue #3 B.1/T04/T05): клавиша I в городе и данже.
## Слоты (оружие/броня/аксессуар/маунт-заглушка), рюкзак с кнопками
## «Надеть»/«Использовать», в городе — крафт у оружейки и мастерской.
## Тултипы: редкость (цвет), характеристики, эффект, сравнение «надето vs в руках».

const LOOT_CFG_PATH := "res://data/loot.json"

var hero_cb := Callable()          # func() -> герой (зелья применяются к живому)
var toast_cb := Callable()         # func(msg) — тосты сцены
var on_change := Callable()        # сцена переприменяет бонусы экипировки
var cast_scroll_cb := Callable()   # данж: func(item_id) -> err (свитки)
var craft_cb := Callable()         # город: func(item_id) -> err (крафт)

var _panel: PanelContainer
var _content: VBoxContainer
var _tooltip: RichTextLabel


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
	style.bg_color = Color(0.08, 0.07, 0.1, 0.94)
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


## Строка заголовка раздела.
func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color("#ffd766"))
	return l


func _slot_row(slot: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = Loc.t("eq.slot." + slot) + ":"
	name_label.custom_minimum_size = Vector2(96, 0)
	row.add_child(name_label)
	var item_id := String(Game.equipment.get(slot, ""))
	var item_label := Label.new()
	item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if item_id == "":
		item_label.text = "— %s —" % Loc.t("eq.empty")
		item_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		var item: Dictionary = Game.item_def(item_id)
		item_label.text = Loc.t(String(item["loc"]))
		item_label.add_theme_color_override("font_color", Game.rarity_color(String(item["rarity"])))
		_hover(item_label, item_id)
	row.add_child(item_label)
	if slot == "mount":
		var note := Label.new()
		note.text = "(M14-I)"
		note.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		row.add_child(note)
	elif item_id != "":
		var btn := Button.new()
		btn.text = Loc.t("eq.unequip")
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void: _act(Game.unequip_slot(slot)))
		row.add_child(btn)
	return row


func _stack_row(stack: Dictionary) -> Control:
	var item_id := String(stack["id"])
	var item: Dictionary = Game.item_def(item_id)
	if item.is_empty():
		return Control.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "%s ×%d" % [Loc.t(String(item["loc"])), int(stack["count"])]
	label.add_theme_color_override("font_color", Game.rarity_color(String(item["rarity"])))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	_hover(label, item_id)
	row.add_child(label)
	var kind := String(item["kind"])
	if kind in Game.EQUIP_SLOTS:
		var btn := Button.new()
		btn.text = Loc.t("eq.equip")
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void: _act(Game.equip_item(item_id)))
		row.add_child(btn)
	elif kind == "potion" or kind == "scroll":
		var btn := Button.new()
		btn.text = Loc.t("eq.use")
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void: _use(item_id, kind))
		row.add_child(btn)
	return row


func _craft_row(item: Dictionary) -> Control:
	var item_id := String(item["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "%s — %s" % [Loc.t(String(item["loc"])), _cost_text(item["craft"].get("cost", {}))]
	label.add_theme_color_override("font_color", Game.rarity_color(String(item["rarity"])))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	_hover(label, item_id)
	row.add_child(label)
	var btn := Button.new()
	btn.text = Loc.t("eq.craft")
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void:
		if craft_cb.is_valid():
			_act(craft_cb.call(item_id)))
	row.add_child(btn)
	return row


## Пересобрать панель целиком (списки короткие — дёшево и всегда актуально).
func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	_content.add_child(_header(Loc.t("eq.title")))
	for slot in Game.EQUIP_SLOTS:
		_content.add_child(_slot_row(slot))
	_content.add_child(_spacer(8))
	_content.add_child(_header(Loc.t("eq.bag")))
	var any := false
	for stack in Game.inventory:
		var item: Dictionary = Game.item_def(String(stack["id"]))
		if item.is_empty() or not String(item.get("kind", "")) in ["weapon", "armor", "accessory", "scroll", "potion"]:
			continue
		_content.add_child(_stack_row(stack))
		any = true
	if not any:
		var empty := Label.new()
		empty.text = Loc.t("hud.empty")
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_content.add_child(empty)
	# крафт — только в городе (сцена передаёт колбэк)
	if craft_cb.is_valid():
		_content.add_child(_spacer(8))
		_content.add_child(_header(Loc.t("eq.craft_title")))
		var hint := Label.new()
		hint.text = Loc.t("eq.craft_hint")
		hint.add_theme_font_size_override("font_size", 14)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_content.add_child(hint)
		for item in Game.items_cfg.get("items", []):
			if item.has("craft"):
				_content.add_child(_craft_row(item))
	_content.add_child(_spacer(6))
	_tooltip = RichTextLabel.new()
	_tooltip.bbcode_enabled = true
	_tooltip.fit_content = true
	_tooltip.custom_minimum_size = Vector2(430, 0)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_tooltip)
	_set_tooltip("")


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Действие с ошибкой-ключом: тост об ошибке или тихий успех с перерисовкой.
func _act(err: String) -> void:
	if err != "":
		if toast_cb.is_valid():
			toast_cb.call(Loc.t(err))
		return
	if on_change.is_valid():
		on_change.call()
	_rebuild()


func _use(item_id: String, kind: String) -> void:
	if kind == "potion":
		var hero = hero_cb.call() if hero_cb.is_valid() else null
		_act(Game.use_potion(item_id, hero))
		if toast_cb.is_valid() and Game.item_def(item_id).is_empty() == false:
			pass
		return
	# свиток — только в данже (сцена кастует заклинание)
	if not cast_scroll_cb.is_valid():
		if toast_cb.is_valid():
			toast_cb.call(Loc.t("eq.only_dungeon"))
		return
	var err: String = cast_scroll_cb.call(item_id)
	if err != "":
		if toast_cb.is_valid():
			toast_cb.call(Loc.t(err))
		return
	if toast_cb.is_valid():
		toast_cb.call(Loc.t("eq.scroll_used"))
	_rebuild()


func _hover(control: Control, item_id: String) -> void:
	control.mouse_entered.connect(func() -> void: _set_tooltip(item_id))
	control.mouse_exited.connect(func() -> void: _set_tooltip(""))


## Тултип предмета (T04): имя, редкость, характеристики, эффект, источник,
## для оружия — сравнение с надетым («надето vs в руках»).
func _set_tooltip(item_id: String) -> void:
	if _tooltip == null:
		return
	if item_id == "":
		_tooltip.text = ""
		return
	var item: Dictionary = Game.item_def(item_id)
	if item.is_empty():
		_tooltip.text = ""
		return
	var lines := PackedStringArray()
	var col := Game.rarity_color(String(item["rarity"])).to_html(false)
	lines.append("[color=%s]%s[/color] — %s" % [col, Loc.t(String(item["loc"])), Loc.t("rarity." + String(item["rarity"]))])
	var kind := String(item["kind"])
	match kind:
		"weapon":
			var w: Dictionary = Game.weapon_def(String(item["weapon"]))
			if not w.is_empty():
				lines.append("%s: %d • %s: %.2fс • %s: %d" % [
					Loc.t("eq.stat.damage"), int(round(float(w["damage"]) * float(item.get("damage_mult", 1.0)))),
					Loc.t("eq.stat.cd"), float(w["attack_cooldown"]),
					Loc.t("eq.stat.range"), int(float(w["range"]))])
				lines.append("[color=#bbbbbb]%s[/color]" % Loc.t(String(w["desc"])))
			var equipped := String(Game.equipment.get("weapon", ""))
			if equipped != "" and equipped != item_id:
				var cur: Dictionary = Game.item_def(equipped)
				if not cur.is_empty():
					var cw: Dictionary = Game.weapon_def(String(cur["weapon"]))
					lines.append("%s [color=%s]%s[/color] (%s %d)" % [Loc.t("eq.comparison"),
							Game.rarity_color(String(cur["rarity"])).to_html(false), Loc.t(String(cur["loc"])),
							Loc.t("eq.stat.damage"),
							int(round(float(cw.get("damage", 0)) * float(cur.get("damage_mult", 1.0))))])
		"armor", "accessory":
			var parts := PackedStringArray()
			for key in item.get("bonuses", {}):
				parts.append("%s %+d" % [Loc.t("eq.bonus." + key), int(item["bonuses"][key])])
			if not parts.is_empty():
				lines.append(" / ".join(parts))
		"scroll":
			var spell: Dictionary = Game.magic.spell(String(item.get("spell_id", "")))
			if not spell.is_empty():
				lines.append("%s: %s (%s)" % [Loc.t("eq.stat.spell"),
						Loc.t(String(spell["loc"])), Loc.t("school." + String(spell["school"]))])
			lines.append("[color=#bbbbbb]%s[/color]" % Loc.t("eq.scroll_hint"))
		"potion":
			var fx: Dictionary = item.get("use", {})
			var key := "eq.potion." + String(fx.get("effect", ""))
			if Loc.t(key) != key:
				lines.append(Loc.t(key) % int(fx.get("amount", 0)))
	var desc := Loc.t(String(item.get("desc", "")))
	if desc != "":
		lines.append("[color=#999988]%s[/color]" % desc)
	_tooltip.text = "\n".join(lines)


## «2 металл, 1 дерево» — стоимость крафта строкой.
func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in cost:
		var name: String = Loc.t("item." + key) if String(key).begins_with("rune_") else Loc.t("res." + key)
		parts.append("%d %s" % [int(cost[key]), name])
	return ", ".join(parts)
