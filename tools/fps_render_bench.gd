extends SceneTree
## Живой бенчмарк отрисовки города (правки v1.21.5): окно с реальным рендером,
## фазы день/ночь/дождь/без подписей, счётчики FPS и draw-коллов.
## Запуск: godot --path . --script res://tools/fps_render_bench.gd
## (без --headless!) ; рендерер сравнивается ключом --rendering-method.

var sim = null
var map_b = null
var view = null
var terrain = null
var weather_fx = null
var ambience = null


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


class FakeHero extends Node2D:
	var dead := false
	func draw_body(_canvas: CanvasItem, _pos: Vector2) -> void:
		pass


class FakeCity extends RefCounted:
	var hero = null
	func enchant_target_valid(_t: Vector2i) -> bool:
		return true


## Драйвер фаз: обычная нода в дереве, двигает сценарий и завершает прогон.
class Driver extends Node:
	var t := 0.0
	var phase := 0
	var bench = null
	var label_snapshot: Dictionary = {}
	var report: Array = []

	func _process(delta: float) -> void:
		t += delta
		if t < 2.5:
			return   # прогрев: шейдеры/кэши
		if t >= 6.0:
			var fps := Engine.get_frames_per_second()
			var draws := RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			report.append([phase_name(phase), fps, draws, proc_ms])
			phase += 1
			t = 0.0
			apply_phase()
			if phase > 4:
				finish()

	func apply_phase() -> void:
		match phase:
			1:
				bench.ambience.night = 1.0
			2:
				bench.ambience.night = 0.0
				bench.weather_fx.weather = "rain"
			3:
				bench.weather_fx.weather = "clear"
				if bench.view != null:
					label_snapshot = bench.view._bld_short.duplicate()
					bench.view._bld_short = {}
			4:
				if bench.view != null:
					bench.view._bld_short = label_snapshot

	func phase_name(p: int) -> String:
		return ["день (база)", "ночь (6 светов)", "дождь", "без подписей зданий", "финал"][mini(p, 4)]

	func finish() -> void:
		print("=== РЕНДЕР-БЕНЧМАРК ГОРОДА (день ~20, %d жителей, %d зданий, %d деревьев) ===" % [
				bench.sim.residents.size(), bench.sim.buildings.size(), bench._tree_count()])
		print("рендерер: %s" % ProjectSettings.get_setting_with_override(
				"rendering/renderer/rendering_method"))
		for row in report:
			print("%-20s | %3d FPS | %5d draw-коллов | процесс %.1f мс" % [row[0], row[1], row[2], row[3]])
		bench.quit(0)


func _tree_count() -> int:
	var n := 0
	for y in map_b.h:
		for x in map_b.w:
			if int(map_b.grid[y][x]) == map_b.TILE_TREE:
				n += 1
	return n


func _init() -> void:
	pass


func _initialize() -> void:
	root.mode = Window.MODE_WINDOWED
	var cfg: Dictionary = _read_json("res://data/city.json")
	map_b = load("res://scripts/city_map.gd").new()
	map_b.generate(7, cfg)
	sim = load("res://scripts/city_sim.gd").new()
	sim.setup(map_b, cfg, 10, "normal")
	sim.paused = false
	sim.hero_alive = true
	sim.hero_pos = map_b.tile_center_px(map_b.spawn_tile)
	sim.coins_sink = func(_n: int) -> void: pass
	sim.coins_source = func() -> int: return 20
	sim._enemies_cfg = _read_json("res://data/enemies.json")
	var day_len: float = float(cfg["day_length"])
	while sim.time < 20.0 * day_len:
		sim.tick(1.0)
		sim.events.clear()
	# мир: статичный ландшафт + динамический вид + погода + амбиент
	# BENCH_PART: both | terrain | view — изоляция стоимости слоёв
	var part := OS.get_environment("BENCH_PART")
	if part != "view":
		terrain = load("res://scripts/city_terrain.gd").new()
		terrain.setup(map_b, cfg)
		root.add_child(terrain)
	if part != "terrain":
		view = load("res://scripts/city_view.gd").new()
		view.setup(map_b, sim, cfg)
		var fc := FakeCity.new()
		var hero := FakeHero.new()
		hero.position = map_b.tile_center_px(map_b.spawn_tile)
		root.add_child(hero)
		fc.hero = hero
		view.city = fc
		root.add_child(view)
	weather_fx = load("res://scripts/city_weather.gd").new()
	root.add_child(weather_fx)
	ambience = load("res://scripts/city_ambience.gd").new()
	ambience.setup(map_b)
	root.add_child(ambience)
	var d := Driver.new()
	d.bench = self
	if view != null:
		d.label_snapshot = view._bld_short.duplicate()
	root.add_child(d)
