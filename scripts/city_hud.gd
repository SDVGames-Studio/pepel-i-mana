# Часть: HUD города — панель дисциплин (исследования), bbcode жителей и
# летописи, стили/иконки/кнопки.
# Корень цепочки: city.gd создаёт HUD через этот файл.
extends "res://scripts/city_hud_build.gd"


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
			# статы и прикладные навыки (v1.23): чем занимается — то и растёт
			var attrs: Dictionary = r.get("stats", {})
			if not attrs.is_empty():
				var attr_parts := PackedStringArray()
				for st_id in ["str", "agi", "end", "int", "wis"]:
					attr_parts.append("%s %.1f" % [Loc.t("stat." + st_id), float(attrs.get(st_id, 0.0))])
				parts.append("[color=#b0bec5]%s[/color]" % " · ".join(attr_parts))
			var sk_map: Dictionary = r.get("skills", {})
			if not sk_map.is_empty():
				var top_ids: Array = sk_map.keys()
				top_ids.sort_custom(func(a, b) -> bool:
					return float(sk_map[a]) > float(sk_map[b]))
				var top_parts := PackedStringArray()
				for k in top_ids.slice(0, 2):
					if float(sk_map[k]) < 0.5:
						continue   # совсем зелёных не показываем
					top_parts.append("%s %d" % [_skill_kind_name(String(k)), int(floor(float(sk_map[k])))])
				if not top_parts.is_empty():
					parts.append("[color=#a5d6a7]%s[/color]" % ", ".join(top_parts))
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


## Название прикладного навыка (v1.23): виды совпадают с профессиями,
## кроме «воина» — боевого навыка стражей.
func _skill_kind_name(kind_id: String) -> String:
	if kind_id == "warrior":
		return Loc.t("skill.warrior")
	return _prof_loc(kind_id)


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
	# v1.68: единая тема (UITheme) — зола/дерево с охристой каймой
	var style := UITheme.panel(compact)
	return style


func _set_rect(control: Control, pos: Vector2, size: Vector2) -> void:
	if pos.x < 0:
		control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		control.position = pos
	else:
		control.position = pos
	control.custom_minimum_size = size


## ---------- иконки ресурсов (v1.53): процедурные 16×16, свой стиль ------

const RES_ICON_STYLE := {
	"wood": ["log", Color("#8d6e63")],
	"stone": ["rock", Color("#9e9e9e")],
	"food": ["leaf", Color("#8bc34a")],
	"crystal": ["gem", Color("#b46ee0")],
	"tools": ["gear", Color("#78909c")],
	"gems": ["gem", Color("#e0b13e")],
	"iron": ["nugget", Color("#b0684a")],
	"metal": ["bar", Color("#cfd8dc")],
	"kits": ["box", Color("#ffb74d")],
	"seeds": ["dots", Color("#c9b458")],
	"saplings": ["sprout", Color("#66aa50")],
	"coins": ["coin", Color("#ffd54f")],
	"copper": ["nugget", Color("#c87941")],
	"silver": ["bar", Color("#d7dde3")],
	"gold": ["coin", Color("#e8b923")],
	"amber": ["gem", Color("#e8963c")],
	"pearls": ["pearl", Color("#ead9e8")],
	"lux": ["box", Color("#ce93d8")],
	"dragon_bone": ["bone", Color("#e8e2d0")],
	"dragon_hide": ["hide", Color("#7a8a4a")],
	"hops": ["leaf", Color("#a8c860")],
	"grapes": ["gem", Color("#9a5ab0")],
	"alcohol": ["bar", Color("#d4a24d")],
	"lich_crystal": ["gem", Color("#7a5a9a")],
	"vampire_blood": ["coin", Color("#c05a5a")],
}


func res_icon(id: String) -> ImageTexture:
	if _res_icons.has(id):
		return _res_icons[id]
	var st: Array = RES_ICON_STYLE.get(id, ["rock", Color.GRAY])
	var kind := String(st[0])
	var col: Color = st[1]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var px := func(x: int, y: int, c: Color) -> void:
		if x >= 0 and y >= 0 and x < 16 and y < 16:
			img.set_pixel(x, y, c)
	var rectf := func(x0: int, y0: int, w: int, h: int, c: Color) -> void:
		for yy in range(y0, y0 + h):
			for xx in range(x0, x0 + w):
				px.call(xx, yy, c)
	match kind:
		"log":
			rectf.call(1, 6, 14, 5, col)
			rectf.call(1, 6, 14, 1, col.lightened(0.25))
			rectf.call(12, 5, 3, 7, col.darkened(0.3))
		"rock":
			rectf.call(4, 6, 8, 6, col)
			rectf.call(3, 8, 10, 4, col)
			rectf.call(5, 6, 4, 2, col.lightened(0.25))
		"leaf":
			rectf.call(6, 3, 4, 9, col)
			rectf.call(4, 5, 8, 5, col)
			rectf.call(7, 12, 2, 2, Color("#5d4037"))
		"gem":
			for yy in 16:
				for xx in 16:
					var d := absi(xx - 8) + absi(yy - 8)
					if d <= 6:
						px.call(xx, yy, col if (xx + yy) % 7 != 0 else col.lightened(0.35))
		"gear":
			rectf.call(5, 2, 6, 12, col)
			rectf.call(2, 5, 12, 6, col)
			rectf.call(6, 6, 4, 4, col.darkened(0.4))
		"nugget":
			rectf.call(4, 6, 8, 6, col)
			rectf.call(6, 4, 5, 4, col)
			rectf.call(5, 5, 3, 2, col.lightened(0.2))
		"bar":
			rectf.call(2, 6, 12, 6, col)
			rectf.call(2, 6, 12, 1, Color.WHITE.lerp(col, 0.4))
		"box":
			rectf.call(3, 4, 10, 9, col)
			rectf.call(3, 4, 10, 2, col.lightened(0.2))
			rectf.call(7, 4, 2, 9, col.darkened(0.25))
		"dots":
			for c in [Vector2i(4, 5), Vector2i(9, 4), Vector2i(6, 9), Vector2i(11, 9), Vector2i(3, 12), Vector2i(9, 12)]:
				rectf.call(c.x, c.y, 3, 3, col)
		"sprout":
			rectf.call(7, 8, 2, 6, Color("#5d4037"))
			rectf.call(3, 4, 4, 4, col)
			rectf.call(9, 3, 4, 4, col)
			rectf.call(6, 6, 4, 3, col.darkened(0.15))
		"coin":
			for yy in 16:
				for xx in 16:
					var dd := Vector2(xx - 8, yy - 8).length()
					if dd <= 6.0:
						px.call(xx, yy, col if dd > 4.5 else col.lightened(0.3))
		"pearl":
			for c in [Vector2i(4, 6), Vector2i(9, 5), Vector2i(6, 10)]:
				for yy in range(c.y, c.y + 4):
					for xx in range(c.x, c.x + 4):
						if Vector2(xx - c.x - 1.5, yy - c.y - 1.5).length() <= 2.0:
							px.call(xx, yy, col if (xx + yy) % 5 != 0 else col.lightened(0.4))
		"bone":
			rectf.call(4, 7, 8, 3, col)
			rectf.call(2, 5, 3, 4, col)
			rectf.call(2, 8, 3, 4, col)
			rectf.call(11, 5, 3, 4, col)
			rectf.call(11, 8, 3, 4, col)
		"hide":
			rectf.call(3, 4, 10, 9, col)
			rectf.call(2, 3, 3, 3, col.darkened(0.2))
			rectf.call(11, 3, 3, 3, col.darkened(0.2))
			rectf.call(6, 8, 4, 3, col.lightened(0.25))
	var tex := ImageTexture.create_from_image(img)
	_res_icons[id] = tex
	return tex
