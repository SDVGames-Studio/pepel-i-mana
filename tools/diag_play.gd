extends SceneTree
## ПЛЕЙТЕСТ-ЧАС (v1.79.13): автономный город на скорости ×10, сэмпл
## состояния каждые ~10 сек реала + скрины. Отчёт: tools/_play_report.txt.
## Запуск С ГРАФИКОЙ: godot --path . --script res://tools/diag_play.gd

var _frames := 0
var _city: Node = null
var _game: Node = null
var _shots := 0
var _started := false
var _start_ms := 0
var _prev_day := -1


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
	seed(20261121)
	game.new_city()
	_city = load("res://scenes/city.tscn").instantiate()
	root.add_child(_city)
	_game = game
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 30 and not _started:
		_started = true
		_start_ms = Time.get_ticks_msec()
		var sim = _city.sim
		sim.call("go_autonomous")
		_city.set_speed(4)   # ×10
		var f := FileAccess.open("res://tools/_play_report.txt", FileAccess.WRITE)
		if f != null:
			f.store_line("ПЛЕЙТЕСТ ×10, старт день=%s" % str(sim.day))
			f.close()
		return
	if not _started or _frames % 60 != 0:
		return
	var sim = _city.sim
	var day := int(sim.day)
	if day == _prev_day:
		return
	_prev_day = day
	var f := FileAccess.open("res://tools/_play_report.txt", FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	var rs: Dictionary = sim.res
	var pop: int = (sim.residents as Array).size()
	var evs: Array = sim.get("events") if sim.get("events") != null else []
	var ev_txt := ""
	if evs.size() > 0:
		var last: Dictionary = evs[evs.size() - 1]
		ev_txt = "%s %s" % [String(last.get("type", "")), String(last.get("msg", ""))]
	f.store_line("день %3d | %s | еда %4d дров %4d камень %4d | жителей %d | %s"
			% [day, String(sim.season()), int(rs.get("food", 0)),
			int(rs.get("wood", 0)), int(rs.get("stone", 0)), pop, ev_txt])
	f.close()
	# скрин каждые 10 игровых дней (максимум 12)
	if day % 10 == 0 and _shots < 12:
		_shots += 1
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://tools/_play_%02d.png" % _shots)
	# ~55 минут реала — стоп
	if Time.get_ticks_msec() - _start_ms > 55 * 60 * 1000:
		var f2 := FileAccess.open("res://tools/_play_report.txt", FileAccess.READ_WRITE)
		if f2 != null:
			f2.seek_end()
			f2.store_line("СТОП по времени, день=%d, летопись (последние 40):" % day)
			for e in (sim.get("events") as Array).slice(maxi(0, evs.size() - 40)):
				f2.store_line("  %s %s" % [String(e.get("type", "")), String(e.get("msg", ""))])
			f2.close()
		quit()
