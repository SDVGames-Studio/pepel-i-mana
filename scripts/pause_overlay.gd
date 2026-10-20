extends Control
## Оверлей паузы (M9): тёмная вуаль + «Пауза» + продолжить/сохранить/в меню.
## process_mode ALWAYS — работает, пока дерево сцены на паузе.
## M14-A: кнопка «Сохранить» (allow_save) — только там, где сейв разрешён
## (город и карта мира; в данже — заглушка-подсказка: данжи транзитны).

var allow_save := true
var hint := ""                      # пояснение под кнопками (напр., про транзитность данжа)
var save_cb := Callable()           # сцена передаёт: func() -> String ("" — успех)
var on_quit := Callable()           # сцена передаёт действие перед выходом в меню
var _status: Label = null


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
	if allow_save:
		var save := Button.new()
		save.text = Loc.t("menu.save_game")
		save.add_theme_font_size_override("font_size", 20)
		save.pressed.connect(_on_save_pressed)
		box.add_child(save)
	var quit := Button.new()
	quit.text = Loc.t("menu.quit_to_menu")
	quit.add_theme_font_size_override("font_size", 20)
	quit.pressed.connect(_to_menu)
	box.add_child(quit)
	if hint != "":
		var hint_label := Label.new()
		hint_label.text = hint
		hint_label.add_theme_font_size_override("font_size", 15)
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hint_label)
	_status = Label.new()
	_status.text = ""
	_status.add_theme_font_size_override("font_size", 17)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if _status != null:
		_status.text = ""
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _on_save_pressed() -> void:
	if _status == null:
		return
	if not save_cb.is_valid():
		_status.text = Loc.t("save.no_game")
		return
	var err: String = save_cb.call()
	_status.text = Loc.t("menu.save_done") if err == "" else Loc.t(err)


func _to_menu() -> void:
	close()
	if on_quit.is_valid():
		on_quit.call()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
