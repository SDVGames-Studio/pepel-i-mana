extends CanvasLayer
## Кодекс и статистика (M14-K, клавиша K): открытые враги, биомы данжей,
## заклинания, руны, божества и фракции + счётчики дней, боссов, построек,
## заказов, охот и сторона сюжета (M14-L).

const SECTIONS := [
	{"cat": "enemies", "loc": "codex.enemies", "prefix": "enemy."},
	{"cat": "biomes", "loc": "codex.biomes", "prefix": "biome."},
	{"cat": "spells", "loc": "codex.spells", "prefix": "spell."},
	{"cat": "items", "loc": "codex.runes", "prefix": "item."},
	{"cat": "gods", "loc": "codex.gods", "prefix": "god."},
	{"cat": "factions", "loc": "codex.factions", "prefix": "world.faction."},
]

const TOTALS := {"enemies": 37, "biomes": 11, "spells": 14, "items": 16, "gods": 3, "factions": 6}

var _panel: PanelContainer
var _content: VBoxContainer


func _ready() -> void:
	layer = 60
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.11, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
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
	l.add_theme_color_override("font_color", Color("#90caf9"))
	return l


func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = Loc.t("codex.title")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#90caf9"))
	_content.add_child(title)
	var codex: Dictionary = Game.codex
	for section in SECTIONS:
		var cat := String(section["cat"])
		var entries: Dictionary = codex.get(cat, {})
		var total := int(TOTALS.get(cat, 0))
		var head := "%s — %d/%d" % [Loc.t(String(section["loc"])), entries.size(), total]
		_content.add_child(_header(head))
		var ids := entries.keys()
		ids.sort()
		for id in ids:
			var name_text := Loc.t(String(section["prefix"]) + String(id))
			if name_text.begins_with("[") or name_text == String(section["prefix"]) + String(id):
				name_text = id
			var l := Label.new()
			l.text = "  • " + name_text
			l.add_theme_font_size_override("font_size", 15)
			_content.add_child(l)
	_content.add_child(_spacer(8))
	_content.add_child(_header(Loc.t("stats.title")))
	var stats: Dictionary = Game.stats
	for pair in [["days", "stats.days"], ["bosses", "stats.bosses"], ["buildings", "stats.buildings"],
			["quests", "stats.quests"], ["hunts", "stats.hunts"]]:
		var l2 := Label.new()
		l2.text = "%s: %d" % [Loc.t(String(pair[1])), int(stats.get(pair[0], 0))]
		_content.add_child(l2)
	if String(Game.city_sim.story_side) != "":
		var l3 := Label.new()
		l3.text = Loc.t("stats.story") % Loc.t("story.side." + String(Game.city_sim.story_side))
		l3.add_theme_color_override("font_color", Color("#ce93d8"))
		_content.add_child(l3)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
