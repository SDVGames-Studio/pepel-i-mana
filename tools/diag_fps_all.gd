extends SceneTree
## FPS-аудит «проверь всё» (v3.0.5): город в ДЕНЬ / НОЧЬ (со всеми огнями)
## / РЕЙД (волна) / x10, плюс мир. Сценарий — env DIAG_MODE.
##   godot --path . --script res://tools/diag_fps_all.gd   (оконно!)
## 240 кадров на сценарий, печать среднего FPS.

var _frames := 0
var _city: Node = null
var _sim = null
var _t480 := 0


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
	_sim = game.city_sim
	var mode := OS.get_environment("DIAG_MODE")
	if mode == "night":
		# глубокая ночь: 23:00 — все огни + светлячки + амбиент
		_sim.time = float(_sim.cfg["day_length"]) * 0.96
	elif mode == "raid":
		_sim.time = float(_sim.cfg["day_length"]) * 0.55
		# волна: 8 мутантов у окраины + тревога
		_sim._spawn_raid(8, false)
	var hide := OS.get_environment("DIAG_HIDE")
	if hide != "":
		var n: Node = _city.get(hide)
		if n != null and is_instance_valid(n):
			n.visible = false
			print("скрыт слой: ", hide)
	print("DIAG_MODE=", mode)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	# время закреплено: иначе сим тикает и уходит из сценария
	var mode := OS.get_environment("DIAG_MODE")
	var dl := float(_sim.cfg["day_length"])
	if mode == "night":
		_sim.time = dl * 0.96
	elif mode == "raid":
		_sim.time = dl * 0.55
	elif mode == "day":
		_sim.time = dl * 0.3
	if _frames == 480:
		_t480 = Time.get_ticks_msec()
	if _frames % 240 == 0:
		var fps := 0
		if _frames >= 720 and _t480 > 0:
			fps = int(240.0 * 1000.0 / float(Time.get_ticks_msec() - _t480))
		var amb: Node = _city.get("_ambience")
		var lights_on := -1
		if amb != null:
			lights_on = 0
			for ch in (amb as Node).get_children():
				if ch is PointLight2D and (ch as PointLight2D).enabled:
					lights_on += 1
		print("frames=%d FPS=%d night=%s raid=%s res=%d lights_on=%d" % [
				_frames, fps, str(_sim.is_night()), str(_sim.raid_active),
				(_sim.residents as Array).size(), lights_on])
	if _frames >= 720:
		quit()
