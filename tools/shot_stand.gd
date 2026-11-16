extends SceneTree
## Снимки тестового стенда (все ряды): godot --path . --script res://tools/shot_stand.gd
var _frames := 0
var _stage := 0
var _node: Node2D = null

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/stand.tscn")
	_node = scene.instantiate()
	_node.name = "Stand"
	root.add_child(_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1
	if _frames < 8:
		return
	var views := [Vector2(520, -120), Vector2(1100, 500), Vector2(2100, 900),
			Vector2(2600, 1750)]
	if _stage >= views.size():
		quit(0)
		return
	_node._cam = views[_stage]
	_node._zoom = 1.0
	if _frames % 12 == 0:
		var img: Image = root.get_texture().get_image()
		img.save_png("res://tools/shot_stand_%d.png" % _stage)
		print("shot: shot_stand_%d.png" % _stage)
		_stage += 1
		_node.queue_redraw()
