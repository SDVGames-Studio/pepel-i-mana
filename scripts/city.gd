extends Node2D
## Заглушка города (этап M0): пустая сцена, Esc возвращает в меню.

@onready var hint_label: Label = %HintLabel


func _ready() -> void:
	hint_label.text = "%s\n%s" % [Loc.t("city.stub_hint"), Loc.t("city.back_hint")]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
