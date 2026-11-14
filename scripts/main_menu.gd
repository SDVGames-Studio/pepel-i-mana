extends Control

## v1.68: единая тема интерфейса (панели/кнопки/тосты)
const UITheme := preload("res://scripts/ui_theme.gd")
## Главное меню: новая игра с настройками старта (вопрос 11: жители всегда
## с одного — правки v1.12.0; ресурсы настраиваются до старта), продолжить, выход.

const VERSION_PATH := "res://data/version.json"
const LEVELS := ["low", "normal", "high"]

@onready var title_label: Label = %TitleLabel
@onready var version_label: Label = %VersionLabel
@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var exit_button: Button = %ExitButton



func _ready() -> void:
	title_label.text = Loc.t("menu.title")
	version_label.text = Loc.t("menu.version") % _read_version()
	new_game_button.text = Loc.t("menu.new_game")
	continue_button.text = Loc.t("menu.continue_city")
	exit_button.text = Loc.t("menu.exit")
	# «Продолжить» виден, если игра идёт ИЛИ есть файл сейва (M14-A)
	continue_button.visible = Game.city_sim != null or Game.has_save()
	for b in [new_game_button, continue_button, exit_button]:
		UITheme.apply_button(b)   # v1.68: единая тема
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
	# v1.54: меню открыто ОВЕРЛЕЕМ над городом — «продолжить» просто
	# закрывает меню (сцена города не пересоздаётся)
	if Game.menu_overlay:
		Game.menu_overlay = false
		queue_free()
		return
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


func _close_overlay_if_any() -> bool:
	if Game.menu_overlay:
		Game.menu_overlay = false
		queue_free()
		return true
	return false


## v1.53: «Новая игра» — сразу экран места города (основание города =
## новая игра; настройки старта — циклическими кнопками на нём).
func _on_new_game_pressed() -> void:
	Game.menu_overlay = false   # v1.54: из оверлея — чистый переход
	get_tree().change_scene_to_file("res://scenes/start_found.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()


## Esc в меню (фидбек заказчика 2026-10-20): возвращаемся в игру — меню
## работает как пауза. Без сессии Esc ничего не делает.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# v1.54: оверлей-меню — Esc просто закрывает его (город под ним жив)
	if _close_overlay_if_any():
		return
	if Game.city_sim == null:
		return
	if Game.world_active and Game.world_map != null:
		get_tree().change_scene_to_file("res://scenes/world.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/city.tscn")


