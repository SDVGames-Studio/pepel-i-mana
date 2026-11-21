extends SceneTree
## ПОСЛОЙНАЯ АТРИБУЦИЯ FPS (v1.80.3): город целиком → по очереди гасим
## слои и смотрим, кто съедает кадр. Печать каждые 120 кадров.

var _frames := 0
var _city: Node = null
var _phase := -1
var _layers := ["view", "_water", "_flora", "_ambience", "_terrain", "_sky_shadows", "_weather_fx", "_sky"]


func _initialize() -> void:
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		game = load("res://scripts/game.gd").new()
		game.name = "Game"
		root.add_child(game)
	var loc: Node = root.get_node_or_null("Loc")
	if loc == null:
		loc = load("res://scripts/loc.gd").new()
		loc.name = "Loc"
		root.add_child(loc)
	game.test_mode = true
	game.new_city()
	_city = load("res://scenes/city.tscn").instantiate()
	root.add_child(_city)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames < 90:
		return
	if (_frames - 90) % 120 == 0:
		_phase += 1
		# гасим накопительно: фаза 0 = всё видно, дальше +1 слой скрыт
		for i in _layers.size():
			var n = _city.get(_layers[i])
			if n != null and is_instance_valid(n):
				n.visible = i >= _phase
		var hidden := "все видны" if _phase == 0 else "скрыты: " + ", ".join(_layers.slice(0, _phase))
		print("ФАЗА %d: %s" % [_phase, hidden])
	if (_frames - 90) % 120 == 119:
		var fps := Engine.get_frames_per_second()
		print("  FPS за фазу: ", fps)
	if _phase >= _layers.size():
		quit()
