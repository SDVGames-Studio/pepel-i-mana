extends CanvasLayer
## Обзорная карта города (v1.51, клавиша N): вся локация одним взглядом —
## земля, ресурсы (лес/скалы/руда/вода), постройки, жители, герой, аномалия
## и выход на карту мира. Карта местности печётся в Image (1px = тайл) и
## растягивается NEAREST-фильтром; поверх — значки зданий и метки. Легенда
## справа поясняет цвета. N или Esc — закрыть.


var map = null    # city_map
var sim = null    # city_sim
var hero_cb := Callable()   # () -> hero (узел с global_position)
var open := false

var _panel: PanelContainer = null
var _map_rect: Control = null      # куда рисуем карту (custom _draw)
var _tex: ImageTexture = null      # земля+ресурсы, 1px/тайл
var _refresh_accum := 0.0
var _legend: RichTextLabel = null


func setup(city_map, city_sim) -> void:
	map = city_map
	sim = city_sim
	visible = false
	layer = 60
	_build_ui()
	_rebake_map()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.12, 0.96)
	style.border_color = Color(0.35, 0.30, 0.20)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	_panel.add_child(root)
	# карта: фиксированный вьюпорт-контрол, скейл подбирается под размер
	_map_rect = Control.new()
	_map_rect.custom_minimum_size = Vector2(880, 660)
	_map_rect.draw.connect(_draw_map)
	root.add_child(_map_rect)
	# легенда + заголовок
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	root.add_child(side)
	var title := Label.new()
	title.text = Loc.t("city.overview_title")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	side.add_child(title)
	_legend = RichTextLabel.new()
	_legend.bbcode_enabled = true
	_legend.fit_content = true
	_legend.custom_minimum_size = Vector2(240, 0)
	_legend.text = _legend_bbcode()
	_map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	side.add_child(_legend)
	var hint := Label.new()
	hint.text = Loc.t("city.overview_hint")
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(240, 0)
	side.add_child(hint)
	add_child(_panel)
	_center_panel()


func _center_panel() -> void:
	await get_tree().process_frame
	var vp := _panel.get_viewport_rect().size
	_panel.position = (Vector2(vp) - _panel.get_minimum_size()) * 0.5


## Ключ легенды: цвет → подпись (и тестовый контракт).
static func legend_entries() -> Array:
	return [
		[Color(0.35, 0.62, 0.28), "legend.grass"],
		[Color(0.16, 0.34, 0.16), "legend.forest"],
		[Color(0.55, 0.55, 0.58), "legend.rock"],
		[Color(0.85, 0.55, 0.25), "legend.ore"],
		[Color(0.25, 0.47, 0.68), "legend.water"],
		[Color(0.78, 0.68, 0.42), "legend.road"],
		[Color(0.85, 0.80, 0.55), "legend.building"],
		[Color(0.95, 0.60, 0.25), "legend.anomaly"],
		[Color(0.45, 0.85, 0.45), "legend.exit"],
		[Color(1.0, 1.0, 1.0), "legend.hero"],
	]


func _legend_bbcode() -> String:
	var out := ""
	for e in legend_entries():
		var hex: String = (e[0] as Color).to_html(false)
		out += "[color=#%s]■[/color] %s\n" % [hex, Loc.t(String(e[1]))]
	return out


func toggle() -> void:
	open = not open
	visible = open
	if open:
		_rebake_map()
		_map_rect.queue_redraw()
		_center_panel()


func _process(delta: float) -> void:
	if not open:
		return
	# здания/жители меняются — обновлять значки не чаще раза в 2 сек
	_refresh_accum += delta
	if _refresh_accum >= 2.0:
		_refresh_accum = 0.0
		_rebake_map()
		_map_rect.queue_redraw()


## Запечь землю и ресурсы в Image 1px/тайл (детерминировано по сетке).
func _rebake_map() -> void:
	if map == null:
		return
	var img := Image.create(map.w, map.h, false, Image.FORMAT_RGBA8)
	for y in map.h:
		for x in map.w:
			img.set_pixel(x, y, _tile_color(Vector2i(x, y)))
	_tex = ImageTexture.create_from_image(img)


## Цвет тайла на обзорной карте (чистая функция — тестируется headless).
func _tile_color(t: Vector2i) -> Color:
	var g: int = map.grid[t.y][t.x]
	match g:
		map.TILE_WATER:
			return Color(0.25, 0.47, 0.68)
		map.TILE_ROCK:
			return Color(0.55, 0.55, 0.58)
		map.TILE_ORE:
			return Color(0.85, 0.55, 0.25)
		map.TILE_DEADROCK:
			return Color(0.42, 0.42, 0.45)
		map.TILE_RUIN:
			return Color(0.62, 0.58, 0.50)
		map.TILE_TREE:
			return Color(0.16, 0.34, 0.16)
	var road: bool = map.road.has(t)
	var bld: Dictionary = sim.building_at(t) if sim != null else {}
	if not bld.is_empty() and bool(bld.get("done", false)):
		return Color(0.85, 0.80, 0.55)
	if road:
		return Color(0.78, 0.68, 0.42)
	# зоны: поля чуть светлее луга, пастбище теплее
	if sim != null and sim.zone_at(t) != null and not (sim.zone_at(t) as Dictionary).is_empty():
		return Color(0.55, 0.72, 0.35)
	return Color(0.35, 0.62, 0.28)


func _draw_map() -> void:
	if _map_rect == null or map == null:
		return
	var size := _map_rect.size
	var s := maxf(1.0, minf(size.x / float(map.w), size.y / float(map.h)))
	var origin := (size - Vector2(map.w, map.h) * s) * 0.5
	if _tex != null:
		_map_rect.draw_texture_rect(_tex, Rect2(origin, Vector2(map.w, map.h) * s), false)
	# сетка кварталов — лёгкая, чтобы «карта» читалась картой
	var step := 8
	var gx := 0
	while gx <= map.w:
		var px := origin.x + float(gx) * s
		_map_rect.draw_line(Vector2(px, origin.y), Vector2(px, origin.y + float(map.h) * s),
				Color(1, 1, 1, 0.05), 1.0)
		gx += step
	var gy := 0
	while gy <= map.h:
		var py := origin.y + float(gy) * s
		_map_rect.draw_line(Vector2(origin.x, py), Vector2(origin.x + float(map.w) * s, py),
				Color(1, 1, 1, 0.05), 1.0)
		gy += step
	# anomaly + выход на карту мира
	_dot(origin, s, map.anomaly_tile, Color(0.95, 0.60, 0.25), 3.0)
	_dot(origin, s, map.world_exit_tile, Color(0.45, 0.85, 0.45), 3.0)
	# здания: значок + подпись производств
	if sim != null:
		var font := ThemeDB.fallback_font
		for b in sim.buildings:
			if not bool(b.get("done", false)):
				continue
			var bt: Vector2i = Vector2i(b["tile"])
			var bw: int = sim.bld_w(b)
			var c := origin + (Vector2(bt) + Vector2(bw, bw) * 0.5) * s
			var razed := bool(b.get("razed", false))
			var col := Color(0.5, 0.5, 0.5) if razed else Color(0.98, 0.92, 0.55)
			_map_rect.draw_circle(c, maxf(2.5, s * 0.45), col)
			var label: String = Loc.t(String(_bld_loc(b)))
			if label != "" and not razed and s > 1.5:
				_map_rect.draw_string(font, c + Vector2(4, -4), label,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))
		# жители — серые точки, герой — белая
		for r in sim.residents:
			if int(r.get("inside", 0)) > 0:
				continue
			var rp: Vector2 = r["pos"]
			var rpp: Vector2 = rp / float(map.ts)
			_map_rect.draw_circle(origin + rpp * s, maxf(1.5, s * 0.22), Color(0.85, 0.85, 0.9, 0.8))
	if hero_cb.is_valid():
		var hero: Node2D = hero_cb.call()
		if hero != null and is_instance_valid(hero):
			var hpx: Vector2 = origin + (hero.global_position / float(map.ts)) * s
			_map_rect.draw_circle(hpx, maxf(2.5, s * 0.4), Color.WHITE)
			_map_rect.draw_circle(hpx, maxf(1.2, s * 0.2), Color(0.2, 0.6, 1.0))


func _bld_loc(b: Dictionary) -> String:
	var t: String = String(b.get("type", ""))
	for d in sim.cfg.get("buildings", []):
		if String(d.get("id", "")) == t:
			return String(d.get("loc", ""))
	return ""


func _dot(origin: Vector2, s: float, tile: Vector2i, col: Color, r: float) -> void:
	_map_rect.draw_circle(origin + (Vector2(tile) + Vector2(0.5, 0.5)) * s, r, col)

