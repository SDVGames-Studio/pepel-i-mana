extends SceneTree
## Замер памяти длинного прогона: 200 дней симуляции города, сэмпл
## физической RAM каждые 25 дней. Запуск: PEPEL_TEST_MAPS=1 godot --headless
## --path . --script res://tools/probe_mem.gd
const DAYS := 100

func _initialize() -> void:
	var g: Node = load("res://scripts/game.gd").new()
	g.test_mode = true
	g.new_city()
	var sim = g.city_sim
	var dt := 0.5
	var ticks_per_day := int(float(sim.cfg["day_length"]) / dt)
	var base := int(OS.get_memory_info()["physical"])
	for day in DAYS:
		for t in ticks_per_day:
			sim.tick(dt)
		if (day + 1) % 10 == 0:
			var st := int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576
			var dyn := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576
			var ms := int(Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX)) / 1024
			var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
			var phys := st + dyn
			var ev: int = (sim.events as Array).size()
			var zc: int = (sim.zones as Array).size()
			var ch: int = 0
			if sim.get("chron") != null:
				ch = (sim.chron as Array).size()
			var lg: int = 0
			if sim.get("log") != null:
				lg = (sim.log as Array).size()
			var f := FileAccess.open("res://tools/mem_curve.txt", FileAccess.READ_WRITE)
			if f == null:
				f = FileAccess.open("res://tools/mem_curve.txt", FileAccess.WRITE)
			else:
				f.seek_end()
			f.store_line("day=%d static=%dMB dyn=%dMB objs=%d msgKB=%d events=%d chron=%d log=%d bld=%d res=%d"
					% [day + 1, st, dyn, objs, ms, ev, ch, lg,
					(sim.buildings as Array).size(), (sim.residents as Array).size()])
			f.close()
	g.free()
	print("MEM_PROBE_DONE")
	quit(0)
