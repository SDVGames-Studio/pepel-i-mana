extends Control
## Оверлей паузы (M9): тёмная вуаль + «Пауза» + продолжить/в меню.
## process_mode ALWAYS — работает, пока дерево сцены на паузе.

var _scene_path := "res://scenes/main_menu.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.55)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = Loc.t("menu.paused")
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = Loc.t("menu.resume")
	resume.add_theme_font_size_override("font_size", 24)
	resume.pressed.connect(close)
	box.add_child(resume)
	var quit := Button.new()
	quit.text = Loc.t("menu.quit_to_menu")
	quit.add_theme_font_size_override("font_size", 20)
	quit.pressed.connect(_to_menu)
	box.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _to_menu() -> void:
	close()
	get_tree().change_scene_to_file(_scene_path)
