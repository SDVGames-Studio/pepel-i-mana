extends Control
## Выбор места города на старте (v1.51): после «Начать» игрок видит карту
## мира, ЛКМ выбирает клетку (годится — суша вдали от поселений НПС и края),
## Enter/кнопка основывает город. Esc — назад в меню.

var _map: Control = null
var _status: Label = null
var _confirm: Button = null
var _img: ImageTexture = null
var _picked := Vector2i(-1, -1)
var _hover := Vector2i(-1, -1)
var _occupancy: Array = []   # тайлы поселений НПС (рядом с ними нельзя)
var _font: Font = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game.new_world()
	for poi in Game.world_map.pois:
		if String(poi["kind"]) == "settlement":
			_occupancy.append(Vector2i(poi["tile"]))
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
	_map = Control.new()
	_map.custom_minimum_size = Vector2(1020, 700)
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map.draw.connect(_draw_map)
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.gui_input.connect(_on_map_input)
	box.add_child(_map)
	_status = Label.new()
	_status.text = Loc.t("pick.hint")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1020, 0)
	_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	box.add_child(_status)
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
	_rebake()
	# курсор сразу на дефолтной клетке города — можно подтвердить сразу
	_picked = Game.world_map.city_tile
	_update_status()


func _rebake() -> void:
	var wm = Game.world_map
	var img := Image.create(wm.w, wm.h, false, Image.FORMAT_RGBA8)
	for y in wm.h:
		for x in wm.w:
			img.set_pixel(x, y, _tile_color(Vector2i(x, y), wm))
	_img = ImageTexture.create_from_image(img)
	_map.queue_redraw()


static func _tile_color(t: Vector2i, wm) -> Color:
	match int(wm.grid[t.y][t.x]):
		wm.TILE_WATER:
			return Color(0.22, 0.42, 0.62)
		wm.TILE_FOREST:
			return Color(0.18, 0.36, 0.20)
		wm.TILE_HILL:
			return Color(0.52, 0.50, 0.44)
		wm.TILE_WASTE:
			return Color(0.55, 0.48, 0.38)
		wm.TILE_SWAMP:
			return Color(0.36, 0.42, 0.34)
		wm.TILE_ROAD:
			return Color(0.72, 0.63, 0.44)
	if wm.river.has(t):
		return Color(0.30, 0.52, 0.72)
	return Color(0.42, 0.60, 0.32)


func _cell_from_mouse() -> Vector2i:
	var wm = Game.world_map
	var size := _map.size
	var s := maxf(1.0, minf(size.x / float(wm.w), size.y / float(wm.h)))
	var origin := (size - Vector2(wm.w, wm.h) * s) * 0.5
	var local := _map.get_local_mouse_position() - origin
	if local.x < 0.0 or local.y < 0.0:
		return Vector2i(-1, -1)
	var t := Vector2i(int(local.x / s), int(local.y / s))
	return t if wm.in_bounds(t) else Vector2i(-1, -1)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _cell_from_mouse()
		_map.queue_redraw()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var t := _cell_from_mouse()
		if t.x >= 0:
			_picked = t
			_update_status()
			_map.queue_redraw()


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
	var err: String = Game.world_map.can_found_city_at(_picked, _occupancy)
	if err == "":
		_status.text = Loc.t("pick.ok")
		_status.add_theme_color_override("font_color", Color(0.65, 0.9, 0.6))
		_confirm.disabled = false
	else:
		_status.text = Loc.t(err)
		_status.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
		_confirm.disabled = true


func _draw_map() -> void:
	if _map == null or Game.world_map == null:
		return
	var wm = Game.world_map
	var size := _map.size
	var s := maxf(1.0, minf(size.x / float(wm.w), size.y / float(wm.h)))
	var origin := (size - Vector2(wm.w, wm.h) * s) * 0.5
	if _img != null:
		_map.draw_texture_rect(_img, Rect2(origin, Vector2(wm.w, wm.h) * s), false)
	# поселения НПС — метки
	for o: Vector2i in _occupancy:
		var c := origin + (Vector2(o) + Vector2(0.5, 0.5)) * s
		_map.draw_circle(c, maxf(3.0, s * 0.5), Color(0.9, 0.5, 0.4))
		_map.draw_arc(c, maxf(4.0, s * 0.8), 0, TAU, 16, Color(1, 0.7, 0.6, 0.7), 1.2)
	# выброс эпицентра (если есть) — фиолетовый контур
	for poi in wm.pois:
		if String(poi["kind"]) == "epicenter":
			var pt: Vector2i = poi["tile"]
			var e := origin + (Vector2(pt) + Vector2(0.5, 0.5)) * s
			_map.draw_arc(e, maxf(5.0, s), 0, TAU, 20, Color(0.8, 0.5, 0.95, 0.8), 1.6)
	# курсор: клетка под мышью — тонкая рамка, выбранная — яркая
	if _hover.x >= 0:
		_map.draw_rect(Rect2(origin + Vector2(_hover) * s, Vector2.ONE * s),
				Color(1, 1, 1, 0.35), false, 1.0)
	if _picked.x >= 0:
		var ok: bool = Game.world_map.can_found_city_at(_picked, _occupancy) == ""
		var col := Color(0.4, 0.95, 0.5) if ok else Color(0.95, 0.4, 0.35)
		var pc2: Vector2i = _picked
		_map.draw_rect(Rect2(origin + Vector2(pc2) * s, Vector2.ONE * s).grow(1.0),
				col, false, 2.0)
		# знак города на выбранной клетке
		var pc: Vector2i = _picked
		var c := origin + (Vector2(pc) + Vector2(0.5, 0.5)) * s
		_map.draw_circle(c, maxf(3.0, s * 0.45), col)
	# подпись масштаба/мыши
	if _font != null and _hover.x >= 0:
		_map.draw_string(_font, origin + Vector2(4, -6),
				"%d, %d" % [_hover.x, _hover.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(1, 1, 1, 0.7))


func _found() -> void:
	if _picked.x < 0 or Game.world_map.can_found_city_at(_picked, _occupancy) != "":
		return
	Game.new_city(_picked)
	get_tree().change_scene_to_file("res://scenes/city.tscn")


func _back() -> void:
	Game.world_map = null   # мир недоигран — при новом «Начать» создаётся заново
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
