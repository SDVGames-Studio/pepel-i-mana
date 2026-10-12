extends Node
## Автозагрузчик локализации: читает loc/<язык>.json, доступ к строкам через Loc.t("ключ").

const LOCALE := "ru"

var _strings: Dictionary = {}


func _ready() -> void:
	load_locale(LOCALE)


## Загружает файл loc/<code>.json. Возвращает true при успехе.
func load_locale(code: String) -> bool:
	var path := "res://loc/%s.json" % code
	if not FileAccess.file_exists(path):
		push_error("Нет файла локализации: %s" % path)
		return false
	var data: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	if not (data is Dictionary):
		push_error("Битый JSON локализации: %s" % path)
		return false
	_strings = data
	return true


## Текст по ключу; при отсутствии ключа возвращает сам ключ и пишет предупреждение.
func t(key: String) -> String:
	if _strings.has(key):
		return _strings[key]
	push_warning("Нет перевода для ключа: %s" % key)
	return key
