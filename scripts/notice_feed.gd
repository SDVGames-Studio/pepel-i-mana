extends CanvasLayer
## Донесения (v1.53): крупные события города — не тосты, а «письма»
## в правом верхнем углу: штурмы, бури, улей, лес, некромант, торговцы,
## беженцы, странники… Письмо можно прочитать и оставить (висит, максимум
## 5 старших вытесняются новыми) или закрыть крестиком, если неважно.

const MAX_LETTERS := 5

## Тип события -> группа (заголовок письма и цвет полоски). Тестовый контракт.
const LETTER_KINDS := {
	"raid_warn": "threat", "raid_start": "threat", "raid_breached": "threat",
	"raid_repelled": "threat", "raid_panic": "threat", "razed": "threat",
	"twisted_attack": "threat", "twisted_fell": "threat",
	"storm_warn": "storm", "storm_start": "storm", "storm_end": "storm",
	"storm_strike": "storm", "dark_storm": "storm", "eruption": "storm",
	"hive_built": "hive", "hive_grew": "hive", "hive_wave": "hive",
	"hive_destroyed": "hive", "dungeon_calm": "hive",
	"forest_warn": "forest", "forest_boss": "forest",
	"necro_revealed": "necro", "undead_rising": "necro",
	"caravan_arrived": "trade", "caravan_left": "trade",
	"caravan_returned": "trade", "caravan_lost": "trade",
	"wanderer": "people", "refugee": "people", "legend_joined": "people",
	"winter_soon": "world",
}

const GROUP_COLORS := {
	"threat": Color("#c05a3a"),
	"storm": Color("#6a8ab0"),
	"hive": Color("#8a6ab0"),
	"forest": Color("#5a8a4a"),
	"necro": Color("#7a5a9a"),
	"trade": Color("#b89a4a"),
	"people": Color("#5a9a8a"),
	"world": Color("#8a94a0"),
}

var _box: VBoxContainer = null


func _ready() -> void:
	layer = 40
	visible = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_box.anchor_left = 1.0
	_box.anchor_right = 1.0
	_box.offset_left = -330.0
	_box.offset_right = -10.0
	_box.offset_top = 44.0
	_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_box.add_theme_constant_override("separation", 6)
	_box.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_box)


## Является ли тип события «письменным» (для тестов и city.gd).
static func is_letter(type: String) -> bool:
	return LETTER_KINDS.has(type)


## Группа письма по типу события (для тестов).
static func group_of(type: String) -> String:
	return String(LETTER_KINDS.get(type, ""))


## Новое донесение: заголовок по группе, текст события, кнопка закрытия.
func push(ev_type: String, text: String) -> void:
	if _box == null or not is_letter(ev_type):
		return
	var group := group_of(ev_type)
	var col: Color = GROUP_COLORS.get(group, Color.GRAY)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#f4e9cf").darkened(0.05)
	st.border_color = col
	st.set_border_width_all(1)
	st.border_width_left = 4
	st.set_corner_radius_all(3)
	st.content_margin_left = 8
	st.content_margin_right = 6
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	row.add_child(vbox)
	var head := Label.new()
	head.text = "✉ " + Loc.t("letter." + group)
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", col.darkened(0.35))
	vbox.add_child(head)
	var body := Label.new()
	body.text = text
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color("#3a3226"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(260, 0)
	vbox.add_child(body)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(24, 24)
	close.pressed.connect(func() -> void:
		panel.queue_free())
	row.add_child(close)
	_box.add_child(panel)
	# лимит: старейшие вытесняются новыми донесениями
	while _box.get_child_count() > MAX_LETTERS:
		_box.get_child(0).queue_free()
	# лёгкое проявление письма
	var tw := panel.create_tween()
	panel.modulate.a = 0.0
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
