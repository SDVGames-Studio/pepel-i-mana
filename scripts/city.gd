extends Node2D
## Город — заглушка (этапы M0–M1): вход в данж по E, итог прошлого забега.
## Настоящий градострой — этап M2.

const DUNGEON_SCENE := "res://scenes/dungeon.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const LOOT_PATH := "res://data/loot.json"

@onready var hint_label: Label = %HintLabel


func _ready() -> void:
	var lines := PackedStringArray([
		Loc.t("city.stub_hint"),
		Loc.t("city.back_hint"),
		"",
		_last_run_line(),
	])
	hint_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		get_tree().change_scene_to_file(DUNGEON_SCENE)
	elif event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MENU_SCENE)


## Сообщение об итоге последнего забега: добыча доставлена или потеряна.
func _last_run_line() -> String:
	if Game.loot_total() == 0:
		return Loc.t("city.last_run_nothing")
	var described := _describe_loot()
	if Game.last_run_death:
		return Loc.t("city.last_run_death") % described
	return Loc.t("city.last_run_ok") % described


## Краткая опись рюкзака: до 3 наименований, дальше «+N».
func _describe_loot() -> String:
	var items: Array = _read_json(LOOT_PATH).get("items", [])
	var names := {}
	for item in items:
		names[String(item["id"])] = String(item["loc"])
	var parts := PackedStringArray()
	var shown := 0
	var extra := 0
	for stack in Game.inventory:
		if shown < 3:
			parts.append("%s ×%d" % [Loc.t(names[String(stack["id"])]), int(stack["count"])])
			shown += 1
		else:
			extra += 1
	if extra > 0:
		parts.append("+%d" % extra)
	return " ".join(parts)


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	return parsed if parsed is Dictionary else {}
