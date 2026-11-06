extends Control
## Основание города — выбор места НА КАРТЕ ГОРОДА (v1.52, замена мирового
## пикера v1.51): сцена показывает сгенерированную локацию целиком — лес,
## скалы, воду, реку — игрок ставит город там, где хочет («ближе к лесу
## или горам»). ЛКМ — выбрать клетку, Enter/кнопка — основать (создаётся
## симуляция с жителями у выбранного места), Esc — назад в меню.
## Ресурсы на карте: тёмно-зелёный лес (древесина), серые массивы — камень,
## оранжевые жилы — руда, вода — рыба и мосты.

const TILE_COLS := {
	0: Color(0.42, 0.60, 0.32),   # трава
	1: Color(0.22, 0.42, 0.62),   # вода
	2: Color(0.55, 0.55, 0.58),   # скала
	3: Color(0.16, 0.34, 0.16),   # лес
	4: Color(0.85, 0.55, 0.25),   # руда
	5: Color(0.40, 0.40, 0.43),   # выработанная
	6: Color(0.62, 0.58, 0.50),   # руины
}

const LEVELS := ["low", "normal", "high"]   # настройки старта (v1.53)

var _level_idx := 1
var _test_on := false
var _conflicts_on := true
var _level_btn: Button = null
var _test_btn: Button = null
var _conf_btn: Button = null

var map = null                 # pending_city_map
var _map_rect: Control = null
var _status: Label = null
var _confirm: Button = null
var _img: ImageTexture = null
var _picked := Vector2i(-1, -1)
var _hover := Vector2i(-1, -1)
var _font: Font = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if Game.pending_city_map == null:
		Game.prepare_city_map()
	map = Game.pending_city_map
	_font = ThemeDB.fallback_font
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var title := Label.new()
	title.text = Loc.t("pick.title")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_map_rect = Control.new()
	_map_rect.custom_minimum_size = Vector2(1120, 740)
	_map_rect.draw.connect(_draw_map)
	_map_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_rect.gui_input.connect(_on_map_input)
	box.add_child(_map_rect)
	_status = Label.new()
	_status.text = Loc.t("pick.hint")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1120, 0)
	_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	box.add_child(_status)
	# настройки старта (v1.53): три циклические кнопки — щелчок меняет
	# вариант, значение видно на самой кнопке (вместо бывшей панели в меню)
	var opts := HBoxContainer.new()
	opts.alignment = BoxContainer.ALIGNMENT_CENTER
	opts.add_theme_constant_override("separation", 10)
	box.add_child(opts)
	_level_btn = _cycle_button(opts, func() -> String:
		return Loc.t("menu.start_level") + ": " + Loc.t("menu.level." + LEVELS[_level_idx]),
		func() -> void:
			_level_idx = (_level_idx + 1) % LEVELS.size())
	_test_btn = _cycle_button(opts, func() -> String:
		return Loc.t("menu.test_mode") + (": ВКЛ" if _test_on else ": выкл"),
		func() -> void: _test_on = not _test_on)
	_conf_btn = _cycle_button(opts, func() -> String:
		return Loc.t("menu.conflicts") + (": ВКЛ" if _conflicts_on else ": выкл"),
		func() -> void: _conflicts_on = not _conflicts_on)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_confirm = Button.new()
	_confirm.text = Loc.t("pick.confirm")
	_confirm.disabled = true
	_confirm.pressed.connect(_found)
	_confirm.add_theme_font_size_override("font_size", 18)
	row.add_child(_confirm)
	var back := Button.new()
	back.text = Loc.t("menu.back")
	back.pressed.connect(_back)
	back.add_theme_font_size_override("font_size", 18)
	row.add_child(back)
	# стартовый выбор — ванильный центр карты (всегда годный: ядро чистилось)
	_picked = map.spawn_tile
	_update_status()
	_rebake()


## Циклическая кнопка: текст по колбеку-геттеру, клик — по колбеку-сеттеру.
func _cycle_button(parent: Control, getter: Callable, on_click: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	var refresh := func() -> void: b.text = String(getter.call())
	refresh.call()
	b.pressed.connect(func() -> void:
		on_click.call()
		refresh.call())
	parent.add_child(b)
	return b


func _rebake() -> void:
	var img := Image.create(map.w, map.h, false, Image.FORMAT_RGBA8)
	for y in map.h:
		for x in map.w:
			img.set_pixel(x, y, _tile_color(Vector2i(x, y)))
	_img = ImageTexture.create_from_image(img)
	_map_rect.queue_redraw()


func _tile_color(t: Vector2i) -> Color:
	var c: Color = TILE_COLS.get(int(map.grid[t.y][t.x]), Color(0.4, 0.6, 0.3))
	if t == map.anomaly_tile:
		return Color(0.95, 0.60, 0.25)
	if t == map.world_exit_tile:
		return Color(0.45, 0.85, 0.45)
	return c


func _cell_from_mouse() -> Vector2i:
	var size := _map_rect.size
	var s := maxf(1.0, minf(size.x / float(map.w), size.y / float(map.h)))
	var origin := (size - Vector2(map.w, map.h) * s) * 0.5
	var local := _map_rect.get_local_mouse_position() - origin
	if local.x < 0.0 or local.y < 0.0:
		return Vector2i(-1, -1)
	var t := Vector2i(int(local.x / s), int(local.y / s))
	return t if map.in_bounds(t) else Vector2i(-1, -1)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _cell_from_mouse()
		_map_rect.queue_redraw()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var t := _cell_from_mouse()
		if t.x >= 0:
			_picked = t
			_update_status()
			_map_rect.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
	elif event.is_action_pressed("ui_accept") and not _confirm.disabled:
		_found()


func _update_status() -> void:
	if _picked.x < 0:
		_status.text = Loc.t("pick.hint")
		_confirm.disabled = true
		return
	var err: String = map.can_found_at(_picked)
	if err == "":
		_status.text = Loc.t("pick.ok")
		_status.add_theme_color_override("font_color", Color(0.65, 0.9, 0.6))
		_confirm.disabled = false
	else:
		_status.text = Loc.t(err)
		_status.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
		_confirm.disabled = true


func _draw_map() -> void:
	if _map_rect == null or map == null:
		return
	var size := _map_rect.size
	var s := maxf(1.0, minf(size.x / float(map.w), size.y / float(map.h)))
	var origin := (size - Vector2(map.w, map.h) * s) * 0.5
	if _img != null:
		_map_rect.draw_texture_rect(_img, Rect2(origin, Vector2(map.w, map.h) * s), false)
	# сетка кварталов
	var gx := 16
	while gx <= map.w:
		var px := origin.x + float(gx) * s
		_map_rect.draw_line(Vector2(px, origin.y), Vector2(px, origin.y + float(map.h) * s),
				Color(1, 1, 1, 0.05), 1.0)
		gx += 16
	var gy := 16
	while gy <= map.h:
		var py := origin.y + float(gy) * s
		_map_rect.draw_line(Vector2(origin.x, py), Vector2(origin.x + float(map.w) * s, py),
				Color(1, 1, 1, 0.05), 1.0)
		gy += 16
	# курсор/выбор: годная клетка — зелёная, нет — красная; кольцо города
	if _hover.x >= 0:
		var hv: Vector2i = _hover
		_map_rect.draw_rect(Rect2(origin + Vector2(hv) * s, Vector2.ONE * s),
				Color(1, 1, 1, 0.3), false, 1.0)
	if _picked.x >= 0:
		var ok: bool = map.can_found_at(_picked) == ""
		var col := Color(0.4, 0.95, 0.5) if ok else Color(0.95, 0.4, 0.35)
		# ореол города — кольцо радиуса 3 (зона расчистки)
		_map_rect.draw_arc(origin + (Vector2(_picked) + Vector2(0.5, 0.5)) * s,
				3.5 * s, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.5), 1.5)
		var pc: Vector2i = _picked
		_map_rect.draw_rect(Rect2(origin + Vector2(pc) * s, Vector2.ONE * s).grow(1.0),
				col, false, 2.0)
	if _font != null and _hover.x >= 0:
		_map_rect.draw_string(_font, origin + Vector2(4, -6),
				"%d, %d" % [_hover.x, _hover.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(1, 1, 1, 0.7))


func _found() -> void:
	if _picked.x < 0:
		return
	Game.start_level = LEVELS[_level_idx]
	Game.test_mode = _test_on
	Game.conflicts_enabled = _conflicts_on
	var err: String = Game.found_city(_picked)
	if err != "":
		_update_status()
		return
	get_tree().change_scene_to_file("res://scenes/city.tscn")


func _back() -> void:
	Game.pending_city_map = null
	Game.world_map = null
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
