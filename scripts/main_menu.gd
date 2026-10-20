extends Control
## Главное меню: новая игра с настройками старта (вопрос 11: жители и ресурсы
## настраиваются до старта), продолжить город, выход.

const VERSION_PATH := "res://data/version.json"
const CITY_CFG_PATH := "res://data/city.json"
const LEVELS := ["low", "normal", "high"]

@onready var title_label: Label = %TitleLabel
@onready var version_label: Label = %VersionLabel
@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var exit_button: Button = %ExitButton

var _city_cfg: Dictionary = {}
var _setup_box: VBoxContainer
var _residents_spin: SpinBox
var _level_option: OptionButton
var _test_check: CheckButton
var _conflicts_check: CheckButton


func _ready() -> void:
	_city_cfg = _read_json(CITY_CFG_PATH)
	title_label.text = Loc.t("menu.title")
	version_label.text = Loc.t("menu.version") % _read_version()
	new_game_button.text = Loc.t("menu.new_game")
	continue_button.text = Loc.t("menu.continue_city")
	exit_button.text = Loc.t("menu.exit")
	# «Продолжить» виден, если игра идёт ИЛИ есть файл сейва (M14-A)
	continue_button.visible = Game.city_sim != null or Game.has_save()
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	_build_save_button()
	_build_fullscreen_check()


## Галочка полноэкранного режима (M9): F11 работает в любой сцене,
## выбор запоминается в user://settings.cfg.
func _build_fullscreen_check() -> void:
	var check := CheckButton.new()
	check.text = Loc.t("menu.fullscreen")
	check.button_pressed = Game.fullscreen
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void: Game.set_fullscreen(on))
	($VBox as VBoxContainer).add_child(check)


func _read_version() -> String:
	var data: Variant = _read_json(VERSION_PATH)
	if data is Dictionary and data.has("version"):
		return str(data["version"])
	return "?"


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _on_continue_pressed() -> void:
	# M14-A: сессии нет — пробуем файл сейва (город и мир целиком из user://)
	if Game.city_sim == null:
		var err: String = Game.load_game()
		if err != "":
			# честный отказ: битый/чужой сейв не грузим, игра не начата
			continue_button.disabled = true
			var warn := Label.new()
			warn.text = Loc.t(err)
			warn.add_theme_font_size_override("font_size", 16)
			warn.add_theme_color_override("font_color", Color("#ff8a80"))
			($VBox as VBoxContainer).add_child(warn)
			return
	# возвращаем туда, где игрок был: карта мира или город (M8)
	if Game.world_active and Game.world_map != null:
		get_tree().change_scene_to_file("res://scenes/world.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/city.tscn")


## Кнопка «Сохранить игру» в меню (фидбек заказчика 2026-10-20: Esc снова
## выходит в меню, сохранение переехало сюда). Видна, пока идёт сессия.
func _build_save_button() -> void:
	if Game.city_sim == null:
		return
	var save := Button.new()
	save.text = Loc.t("menu.save_game")
	save.add_theme_font_size_override("font_size", 22)
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(func() -> void: _on_save_pressed(save))
	($VBox as VBoxContainer).add_child(save)


func _on_save_pressed(save: Button) -> void:
	var err: String = Game.menu_save()
	save.text = Loc.t("menu.save_done") if err == "" else Loc.t(err)


func _on_new_game_pressed() -> void:
	if _setup_box != null:
		_setup_box.visible = not _setup_box.visible
		return
	_build_setup()
	_setup_box.visible = true


func _on_exit_pressed() -> void:
	get_tree().quit()


## Esc в меню (фидбек заказчика 2026-10-20): возвращаемся в игру — меню
## работает как пауза. Без сессии Esc ничего не делает.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if Game.city_sim == null:
		return
	# панель настроек новой игры открыта — сначала закрываем её
	if _setup_box != null and _setup_box.visible:
		_setup_box.visible = false
		return
	if Game.world_active and Game.world_map != null:
		get_tree().change_scene_to_file("res://scenes/world.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/city.tscn")


## Панель настроек старта (вопрос 11): число жителей и запас ресурсов.
func _build_setup() -> void:
	var start: Dictionary = _city_cfg.get("start", {})
	_setup_box = VBoxContainer.new()
	_setup_box.add_theme_constant_override("separation", 10)
	($VBox as VBoxContainer).add_child(_setup_box)
	_setup_box.visible = false

	var title := Label.new()
	title.text = Loc.t("menu.setup_title")
	title.add_theme_font_size_override("font_size", 24)
	_setup_box.add_child(title)

	var res_row := HBoxContainer.new()
	_setup_box.add_child(res_row)
	var res_label := Label.new()
	res_label.text = Loc.t("menu.residents") + ": "
	res_label.add_theme_font_size_override("font_size", 20)
	res_row.add_child(res_label)
	_residents_spin = SpinBox.new()
	_residents_spin.min_value = int(start.get("residents_min", 1))
	_residents_spin.max_value = int(start.get("residents_max", 12))
	_residents_spin.value = int(start.get("residents_default", 5))
	_residents_spin.custom_minimum_size = Vector2(90, 0)
	res_row.add_child(_residents_spin)

	var lvl_row := HBoxContainer.new()
	_setup_box.add_child(lvl_row)
	var lvl_label := Label.new()
	lvl_label.text = Loc.t("menu.start_level") + ": "
	lvl_label.add_theme_font_size_override("font_size", 20)
	lvl_row.add_child(lvl_label)
	_level_option = OptionButton.new()
	for key in LEVELS:
		_level_option.add_item(Loc.t("menu.level." + key))
	_level_option.selected = 1
	_level_option.add_theme_font_size_override("font_size", 20)
	lvl_row.add_child(_level_option)

	var test_check := CheckButton.new()
	test_check.text = Loc.t("menu.test_mode")
	test_check.add_theme_font_size_override("font_size", 18)
	test_check.focus_mode = Control.FOCUS_NONE
	_setup_box.add_child(test_check)
	_test_check = test_check

	var conflicts_check := CheckButton.new()
	conflicts_check.text = Loc.t("menu.conflicts")
	conflicts_check.button_pressed = true
	conflicts_check.add_theme_font_size_override("font_size", 18)
	conflicts_check.focus_mode = Control.FOCUS_NONE
	_setup_box.add_child(conflicts_check)
	_conflicts_check = conflicts_check

	# идёт игра — предупреждаем, что новая её затрёт (фидбек приёмки M8)
	if Game.city_sim != null:
		var warn := Label.new()
		warn.text = Loc.t("menu.new_game_warn")
		warn.add_theme_font_size_override("font_size", 16)
		warn.add_theme_color_override("font_color", Color("#ff8a80"))
		_setup_box.add_child(warn)

	var begin := Button.new()
	begin.text = Loc.t("menu.begin")
	begin.add_theme_font_size_override("font_size", 24)
	begin.pressed.connect(_on_begin_pressed)
	_setup_box.add_child(begin)

	var back := Button.new()
	back.text = Loc.t("menu.back")
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(func() -> void: _setup_box.visible = false)
	_setup_box.add_child(back)


func _on_begin_pressed() -> void:
	Game.start_residents = int(_residents_spin.value)
	Game.start_level = LEVELS[_level_option.selected]
	Game.test_mode = _test_check.button_pressed
	Game.conflicts_enabled = _conflicts_check.button_pressed
	Game.new_city()
	get_tree().change_scene_to_file("res://scenes/city.tscn")
