extends Node2D
## Тестовый стенд (v1.75): все горожане, монстры, боссы, здания и герой —
## в ряд, на расстоянии, прогоняют idle-анимации (где они есть).
## Открытие — кнопка «Тестовый стенд» в главном меню; ESC — назад в меню.
## Управление: WASD/стрелки/перетаскивание ЛКМ — обзор, колесо — зум.

const UITheme := preload("res://scripts/ui_theme.gd")

const VILL_SPACING := 120.0
const MOB_SPACING := 170.0
const BOSS_SPACING := 300.0
const BLD_SPACING := 360.0
const ROW_GAP := 420.0

const VILL_HEIGHT := 64.0    # высота фигур в рядах (для читаемости)
const MOB_HEIGHT := 60.0
const BOSS_HEIGHT := 130.0
const BLD_HEIGHT := 180.0

var _t := 0.0
var _cam := Vector2(520.0, -120.0)   # старт вида — начало ряда горожан
var _zoom := 1.0
var _drag := false

var _villagers: Array = []       # [prof, подпись]
var _mobs: Array = []            # [ref, подпись]
var _bosses: Array = []          # [ref, подпись]
var _buildings: Array = []       # [ref, подпись]
var _hero_tex: Texture2D = null


func _ready() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var hint := Label.new()
	hint.text = Loc.t("stand.title") + "  ·  " + Loc.t("stand.hint")
	hint.position = Vector2(16, 12)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	ui.add_child(hint)
	var back := Button.new()
	back.text = Loc.t("stand.back")
	back.position = Vector2(16, 44)
	back.custom_minimum_size = Vector2(200, 40)
	back.add_theme_font_size_override("font_size", 16)
	back.focus_mode = Control.FOCUS_NONE
	UITheme.apply_button(back)
	back.pressed.connect(_back_to_menu)
	ui.add_child(back)

	var people: Dictionary = _read_json("res://data/residents.json")
	for prof: String in Assets.VILLAGER_PROF.keys():
		_villagers.append([prof, Loc.t("prof." + prof)])
	_villagers.append(["elder", Loc.t("prof.elder")])

	var enemies: Array = _read_json("res://data/enemies.json")
	for e in enemies:
		var row: Array = _bosses if bool(e.get("boss", false)) else _mobs
		row.append([String(e["sprite"]), Loc.t("enemy." + String(e["id"]))])

	var city: Dictionary = _read_json("res://data/city.json")
	for tier in [1, 2, 3]:
		_buildings.append(["b:дом_жителей_ур%d" % tier,
				Loc.t("bld.house") + " ур%d" % tier])
	for b in city["buildings"]:
		var ref := String(b.get("sprite", ""))
		if ref.begins_with("k:"):
			continue   # схематичные (стены сегментами и пр.) на стенд не идут
		_buildings.append([ref, Loc.t(String(b["loc"]))])

	_hero_tex = Assets.tex("res://assets/sprites/hero/knight_Idle.png")


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		_back_to_menu()
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(3.0, _zoom * 1.15)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(0.2, _zoom / 1.15)
	elif ev is InputEventMouseMotion and _drag:
		_cam -= ev.relative / _zoom


func _process(delta: float) -> void:
	_t += delta
	var v := 620.0 * delta / _zoom
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_cam.x -= v
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_cam.x += v
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_cam.y -= v
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_cam.y += v
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	# фон — тёмная земля «зола и дерево»
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.14, 0.13, 0.11))
	var to_screen := func(world: Vector2) -> Vector2:
		return (world - _cam) * _zoom + vp * 0.5

	# --- ряд 1: горожане (idle-анимация жителей) ---
	var row_y := 0.0
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 120.0),
			Loc.t("stand.row_villagers"))
	for i in range(_villagers.size()):
		var org := Vector2(i * VILL_SPACING, row_y)
		var pos: Vector2 = to_screen.call(org + Vector2(VILL_SPACING * 0.5, 40.0))
		Assets.draw_villager(self, String(_villagers[i][0]), "right",
				false, false, pos, _t + 0.13 * float(i), Color.WHITE, 2.0)
		_label(font, pos + Vector2(0, 46), String(_villagers[i][1]))

	# --- ряд 2: герой (idle-анимация рыцаря) ---
	row_y += ROW_GAP
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 150.0),
			Loc.t("stand.row_hero"))
	if _hero_tex != null:
		var f := int(_t * 8.0) % 10
		var hpos: Vector2 = to_screen.call(Vector2(140.0, row_y + 60.0))
		var s := 62.0 / 76.0   # фигура героя ~62px при жителе ~54 (2x игры)
		var dst := Rect2(hpos - Vector2(48.0, 80.0 * s),
				Vector2(120.0 * s, 80.0 * s))
		draw_texture_rect_region(_hero_tex, dst,
				Rect2(float(f) * 120.0, 0, 120, 80))
		_label(font, hpos + Vector2(0, 30), Loc.t("stand.hero"))

	# --- ряд 3: монстры (обычные) ---
	row_y += ROW_GAP
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 120.0),
			Loc.t("stand.row_mobs"))
	for i in range(_mobs.size()):
		var org := Vector2(i * MOB_SPACING, row_y)
		var pos: Vector2 = to_screen.call(org + Vector2(MOB_SPACING * 0.5, 60.0))
		Assets.draw_ref(self, String(_mobs[i][0]), pos, MOB_HEIGHT)
		_label(font, pos + Vector2(0, MOB_HEIGHT * 0.5 + 16.0),
				String(_mobs[i][1]))

	# --- ряд 4: боссы ---
	row_y += ROW_GAP
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 170.0),
			Loc.t("stand.row_bosses"))
	for i in range(_bosses.size()):
		var org := Vector2(i * BOSS_SPACING, row_y)
		var pos: Vector2 = to_screen.call(org + Vector2(BOSS_SPACING * 0.5, 90.0))
		Assets.draw_ref(self, String(_bosses[i][0]), pos, BOSS_HEIGHT)
		_label(font, pos + Vector2(0, BOSS_HEIGHT * 0.5 + 18.0),
				String(_bosses[i][1]))

	# --- ряд 5: здания ---
	row_y += ROW_GAP + 120.0
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 220.0),
			Loc.t("stand.row_buildings"))
	for i in range(_buildings.size()):
		var org := Vector2(i * BLD_SPACING, row_y)
		var pos: Vector2 = to_screen.call(org + Vector2(BLD_SPACING * 0.5, 130.0))
		Assets.draw_ref(self, String(_buildings[i][0]), pos, BLD_HEIGHT)
		_label(font, pos + Vector2(0, BLD_HEIGHT * 0.5 + 18.0),
				String(_buildings[i][1]))


func _row_caption(font: Font, to_screen: Callable, world: Vector2,
		text: String) -> void:
	var pos: Vector2 = to_screen.call(world)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(0.95, 0.8, 0.5))


func _label(font: Font, center: Vector2, text: String) -> void:
	var size := 12
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := center + Vector2(-w * 0.5, 0)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			Color(0.85, 0.85, 0.8))
