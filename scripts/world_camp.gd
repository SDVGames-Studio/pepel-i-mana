extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Лагерь торговцев «гуляй-город» (M10): телеги по кругу, костёр, торговцы.
## Герой ходит WASD, у костра/торговцев — E: торговля по ценам каравана
## (скидка лагеря). Уход за нижний край или Esc — назад на карту мира.

const WORLD_SCENE := "res://scenes/world.tscn"
const W := 900.0
const H := 640.0
const EXIT_Y := H - 36.0

var hero_px := Vector2(W / 2.0, H - 80.0)
var hero_dir := "front"
var _t := 0.0
var _poi := {}                       # точка интереса, из которой вошли
var _traders: Array = []             # {pos, target, dir, moving, variant}
var _wagons: Array = []              # {pos, flip}
var _near_trader := false
var _panel: PanelContainer = null
var _panel_box: VBoxContainer = null
var _coins_label: Label = null
var _hint: Label = null
var _toast: Label = null
var _toast_t := 0.0


func _ready() -> void:
	var poi_id := Game.poi_id
	if Game.world_map != null:
		_poi = Game.world_map.poi_by_id(poi_id)
	_random_camp()
	_build_ui()


## Постановка лагеря (гуляй-город): телеги кругом, дырка на юг (вход),
## костёр в центре, палатка, ящики и мешки у телег.
func _random_camp() -> void:
	var center := Vector2(W / 2.0, H / 2.0 - 20.0)
	var radius := 190.0
	for i in 7:
		var angle := TAU * float(i) / 7.0 + PI / 2.0
		var pos := center + Vector2(sin(angle), -cos(angle)) * radius
		if pos.y > H - 110.0:
			continue   # вход с юга свободен
		_wagons.append({"pos": pos, "flip": cos(angle) < 0.0})
	_traders = []
	for i in 4:
		_traders.append({
			"pos": center + Vector2(randf_range(-120, 120), randf_range(-60, 120)),
			"target": center + Vector2(randf_range(-140, 140), randf_range(-80, 140)),
			"dir": "front", "moving": false, "variant": 1 + i % 4,
		})


func _process(delta: float) -> void:
	_t += delta
	_toast_t = maxf(0.0, _toast_t - delta)
	if _toast_t <= 0.0:
		_toast.text = ""
	# герой
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if not _trade_open():
		hero_px += dir * 150.0 * delta
		hero_px = hero_px.clamp(Vector2(30, 40), Vector2(W - 30, H - 24))
		if dir != Vector2.ZERO:
			hero_dir = Assets.dir_of(dir)
	# торговцы бродят между телегами
	for tr in _traders:
		var to_t: Vector2 = tr["target"] - tr["pos"]
		if to_t.length() < 6.0:
			tr["moving"] = false
			if randf() < delta * 0.5:
				tr["target"] = Vector2(W / 2.0, H / 2.0 - 20.0) + Vector2(randf_range(-160, 160), randf_range(-100, 140))
		else:
			tr["moving"] = true
			var step: Vector2 = to_t.normalized() * 42.0 * delta
			tr["dir"] = Assets.dir_of(to_t)
			tr["pos"] += step
	_near_trader = _nearest_trader() != null or hero_px.distance_to(Vector2(W / 2.0, H / 2.0 - 20.0)) < 70.0
	var hint_key := "camp.hint_trade" if _near_trader else "camp.hint_walk"
	if hero_px.y > EXIT_Y:
		hint_key = "camp.hint_exit"
	_hint.text = Loc.t(hint_key)
	if hero_px.y > H - 16.0:
		_leave()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _trade_open():
			_close_trade()
		elif _near_trader:
			_open_trade()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		if _trade_open():
			_close_trade()
		else:
			_leave()


func _leave() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _nearest_trader() -> Dictionary:
	var best: Dictionary = {}
	var best_d := 60.0
	for tr in _traders:
		var d: float = (tr["pos"] as Vector2).distance_to(hero_px)
		if d < best_d:
			best_d = d
			best = tr
	return best


# --- торговля ---------------------------------------------------------------

func _trade_open() -> bool:
	return _panel != null and _panel.visible


func _open_trade() -> void:
	_rebuild_trade()
	_panel.visible = true


func _close_trade() -> void:
	_panel.visible = false


func _rebuild_trade() -> void:
	for child in _panel_box.get_children():
		child.queue_free()
	var sim = Game.world_sim
	var tcfg: Dictionary = {}
	var world_cfg: Dictionary = {}
	if Game.world_map != null:
		world_cfg = Game.world_map.cfg
	tcfg = world_cfg.get("trade", {})
	var poi := _poi
	if poi.is_empty():
		poi = {"kind": "trade_camp"}
	_coins_label.text = Loc.t("res.coins") + ": %d" % Game.coins
	var title := _label(Loc.t("camp.trade_title"), 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_box.add_child(title)
	_panel_box.add_child(_label(Loc.t("camp.trade_note"), 14))
	# покупка (в пул города — караван доставит)
	_panel_box.add_child(_label(Loc.t("world.buy_title"), 18))
	for key in tcfg.get("buy", {}):
		var price := int(ceilf(sim.buy_price(String(key), poi)))
		var row := HBoxContainer.new()
		var name_label := _label("%s — %d %s" % [Loc.t("res." + String(key)), price, Loc.t("res.coins_short")], 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var btn := Button.new()
		btn.text = Loc.t("world.buy_btn") % 5
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void: _buy(String(key), 5))
		row.add_child(btn)
		_panel_box.add_child(row)
	# продажа
	_panel_box.add_child(_label(Loc.t("world.sell_title"), 18))
	for key in tcfg.get("buy", {}):
		var sprice := int(floorf(sim.sell_price(String(key), poi)))
		var row2 := HBoxContainer.new()
		var name2 := _label("%s — %d %s" % [Loc.t("res." + String(key)), sprice, Loc.t("res.coins_short")], 16)
		name2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(name2)
		var btn2 := Button.new()
		btn2.text = Loc.t("world.sell_btn") % 5
		btn2.focus_mode = Control.FOCUS_NONE
		btn2.pressed.connect(func() -> void: _sell(String(key), 5))
		row2.add_child(btn2)
		_panel_box.add_child(row2)
	var note := _label(Loc.t("world.trade_note"), 14)
	note.modulate = Color(1, 1, 1, 0.7)
	_panel_box.add_child(note)


func _buy(key: String, count: int) -> void:
	var sim = Game.world_sim
	var poi := _poi if not _poi.is_empty() else {"kind": "trade_camp"}
	var cap: int = Game.city_sim.storage_cap() if Game.city_sim != null else 999999
	var out: Dictionary = sim.trade_buy(Game.city_sim.res, Game.coins, key, count, poi, cap)
	Game.coins = int(out["coins"])
	_toast.text = Loc.t("world.bought" if String(out["err"]) == "" else "world." + String(out["err"]))
	_toast_t = 2.5
	_rebuild_trade()


func _sell(key: String, count: int) -> void:
	var sim = Game.world_sim
	var poi := _poi if not _poi.is_empty() else {"kind": "trade_camp"}
	var out: Dictionary = sim.trade_sell(Game.city_sim.res, Game.coins, key, count, poi)
	Game.coins = int(out["coins"])
	_toast.text = Loc.t("world.sold" if String(out["err"]) == "" else "world." + String(out["err"]))
	_toast_t = 2.5
	_rebuild_trade()


# --- отрисовка ----------------------------------------------------------------

func _draw() -> void:
	# поляна: трава по краям, утоптанная земля в круге лагеря
	draw_rect(Rect2(0, 0, W, H), Color("#57703a"))
	draw_circle(Vector2(W / 2.0, H / 2.0 - 20.0), 260.0, Color("#6b5b40"))
	draw_circle(Vector2(W / 2.0, H / 2.0 - 20.0), 240.0, Color("#75644a"))
	# тропинки от входа к костру
	draw_rect(Rect2(W / 2.0 - 26, H / 2.0, 52, H - H / 2.0), Color("#6e5f4a"))
	# костёр в центре
	var fire_pos := Vector2(W / 2.0, H / 2.0 - 20.0)
	draw_circle(fire_pos + Vector2(0, 8), 22.0, Color(0.2, 0.15, 0.1))
	draw_rect(Rect2(fire_pos + Vector2(-14, 2), Vector2(28, 8)), Color("#5d4037"))
	var frame := int(_t * 10.0) % 5
	Assets.draw_sheet(self, "fire", frame, fire_pos - Vector2(0, 10), 36.0)
	var flicker := 0.35 + 0.15 * sin(_t * 9.0)
	draw_circle(fire_pos - Vector2(0, 12), 60.0 + 6.0 * sin(_t * 7.0), Color(1.0, 0.7, 0.3, flicker * 0.25))
	# телеги по кругу (гуляй-город)
	for w in _wagons:
		var pos: Vector2 = w["pos"]
		draw_circle(pos + Vector2(0, 20), 34.0, Color(0, 0, 0, 0.15))
		Assets.draw_ref(self, "e:cart", pos, 64.0, bool(w["flip"]))
		# ящики и мешки у части телег
		if int(w["pos"].x) % 3 == 0:
			Assets.draw_ref(self, "e:crate", pos + Vector2(38, 14), 22.0)
		elif int(w["pos"].x) % 3 == 1:
			Assets.draw_ref(self, "e:sack", pos + Vector2(-40, 16), 20.0)
	# палатка на краю
	Assets.draw_ref(self, "e:tent", Vector2(W - 110, H / 2.0 - 130.0), 96.0)
	# торговцы (4 направления, кадры)
	for tr in _traders:
		var pos: Vector2 = tr["pos"]
		draw_circle(pos + Vector2(0, 4), 9.0, Color(0, 0, 0, 0.2))
		Assets.draw_citizen(self, int(tr["variant"]), String(tr["dir"]), bool(tr["moving"]),
				pos + Vector2(0, -6), 34.0, _t + float(tr["variant"]), Color.WHITE)
	# герой
	draw_circle(hero_px + Vector2(0, 4), 8.0, Color(0, 0, 0, 0.25))
	Assets.draw_ref(self, "img:knight", hero_px - Vector2(0, 8), 30.0, hero_dir == "left")
	# зона выхода вниз
	draw_rect(Rect2(0, H - 18, W, 18), Color(0.45, 0.9, 0.5, 0.18))
	var arr := Color(0.45, 0.9, 0.5, 0.55 + 0.25 * sin(_t * 3.0))
	draw_colored_polygon(PackedVector2Array([
		Vector2(W / 2.0 - 10, H - 16), Vector2(W / 2.0 + 10, H - 16), Vector2(W / 2.0, H - 4)]), arr)


# --- UI ------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position.y = -46
	_hint.add_theme_font_size_override("font_size", 18)
	layer.add_child(_hint)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y = 54
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", Color("#ffe9b0"))
	layer.add_child(_toast)
	_panel = PanelContainer.new()
	_panel.position = Vector2(280, 80)
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.visible = false
	layer.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_panel_box)
	var head := HBoxContainer.new()
	_coins_label = _label("", 18)
	_coins_label.add_theme_color_override("font_color", Color("#ffe082"))
	head.add_child(_coins_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = Loc.t("world.close_btn")
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_trade)
	head.add_child(close_btn)
	_panel_box.add_child(head)
	_coins_label.text = Loc.t("res.coins") + ": %d" % Game.coins


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label
