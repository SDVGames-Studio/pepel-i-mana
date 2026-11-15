extends SceneTree
## Снимок всех жителей-профессий листами кита (v1.72). Запуск С ГРАФИКОЙ:
## godot --path . --script res://tools/shot_villagers.gd
## Рисует каждую профессию Assets.draw_villager (idle/шаг/работа) в сетку
## 4×4, сохраняет tools/shot_villagers.png и выходит.

var _frames := 0


func _initialize() -> void:
	var root_node := Node2D.new()
	root_node.name = "Villagers"
	root.add_child(root_node)
	root_node.set_script(load("res://tools/shot_villagers_board.gd"))
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames < 6:
		return
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tools/shot_villagers.png")
	print("shot: сохранён tools/shot_villagers.png")
	quit(0)
