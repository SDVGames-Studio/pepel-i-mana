extends Control
## Главное меню (этап M0): «Новая игра» → пустой город, «Выход».

const VERSION_PATH := "res://data/version.json"

@onready var title_label: Label = %TitleLabel
@onready var version_label: Label = %VersionLabel
@onready var new_game_button: Button = %NewGameButton
@onready var exit_button: Button = %ExitButton


func _ready() -> void:
	title_label.text = Loc.t("menu.title")
	version_label.text = Loc.t("menu.version") % _read_version()
	new_game_button.text = Loc.t("menu.new_game")
	exit_button.text = Loc.t("menu.exit")
	new_game_button.pressed.connect(_on_new_game_pressed)
	exit_button.pressed.connect(_on_exit_pressed)


func _read_version() -> String:
	var f := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if f == null:
		return "?"
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary and data.has("version"):
		return str(data["version"])
	return "?"


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/city.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
