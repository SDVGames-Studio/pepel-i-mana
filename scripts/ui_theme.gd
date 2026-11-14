## Единый визуальный стиль интерфейса «Пепел и Мана» (v1.68, волна C):
## тёмные панели «зола и дерево» с охристой каймой, янтарные акценты —
## славянское тёмное фэнтези. Все панели/кнопки интерфейса берут стили
## отсюда; правка вида = правка одного файла.

const PANEL_BG := Color(0.09, 0.08, 0.06, 0.93)      # зола/тёмное дерево
const PANEL_EDGE := Color(0.72, 0.58, 0.35, 0.9)     # охра/медь
const PANEL_EDGE_DIM := Color(0.55, 0.45, 0.3, 0.8)
const ACCENT := Color("#e8c94d")                     # янтарь
const TEXT := Color(0.94, 0.9, 0.8)                  # тёплый пергамент
const TEXT_DIM := Color(0.72, 0.67, 0.57)
const DANGER := Color("#ff8a80")

const BTN_BG := Color(0.17, 0.14, 0.1, 0.96)
const BTN_BG_HOVER := Color(0.24, 0.19, 0.12, 1.0)
const BTN_BG_PRESSED := Color(0.3, 0.23, 0.13, 1.0)
const BTN_BG_DISABLED := Color(0.12, 0.11, 0.09, 0.7)


## Панель интерфейса: тёмный фон, охристая кайма, скругления.
static func panel(compact := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	if compact:
		sb.content_margin_left = 10.0
		sb.content_margin_right = 10.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
	else:
		sb.set_content_margin_all(12)
	return sb


## Тост-плашка: панель пошире, чтобы текст читался на любом фоне.
static func toast_panel() -> StyleBoxFlat:
	var sb := panel(true)
	sb.bg_color = Color(0.07, 0.06, 0.045, 0.88)
	return sb


static func _btn_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


## Тема кнопки: норма/наведение/нажатие/недоступна + цвет текста.
## Вызывать сразу после Button.new() в местах создания интерфейса.
static func apply_button(b: Button, accent := false) -> void:
	var edge := ACCENT if accent else PANEL_EDGE_DIM
	b.add_theme_stylebox_override("normal", _btn_style(BTN_BG, edge))
	b.add_theme_stylebox_override("hover", _btn_style(BTN_BG_HOVER, ACCENT))
	b.add_theme_stylebox_override("pressed", _btn_style(BTN_BG_PRESSED, ACCENT))
	b.add_theme_stylebox_override("disabled", _btn_style(BTN_BG_DISABLED, PANEL_EDGE_DIM))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# цвет текста: только если у кнопки нет СВОЕЙ смысловой окраски
	# (категории построек и т.п. красят шрифт при сборке)
	if not b.has_theme_color_override("font_color"):
		b.add_theme_color_override("font_color", TEXT if not accent else ACCENT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.86))
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Тема чекбокса/флажка-кнопки переключателя (панели HUD).
static func apply_toggle(b: Button) -> void:
	apply_button(b)
	b.toggle_mode = false


## Тематизировать все кнопки под узлом (кроме CheckButton — у них своя метка).
## Вызывается после сборки дерева интерфейса.
static func apply_tree(node: Node) -> void:
	if node is Button and not node is CheckButton:
		apply_button(node)
	for c in node.get_children():
		apply_tree(c)
