extends Node
## СТРАЖ ПАМЯТИ (v3.0.2, заказчик: «сделай уловитель, почему и куда
## утекает память и роняет компьютер»).
##
## Живёт в каждой сцене (автозагрузка), стоит копейки:
## - каждые SAMPLE_SEC сэмпл: мониторы Godot (статик-память/объекты/
##   ресурсы/узлы/СИРОТЫ) + свободная RAM системы (OS.get_memory_info);
## - каждые LOG_SEC — строка в user://mem_watchdog.log (файл ≤1МБ,
##   при переполнении подрезается до хвоста);
## - смена сцены — отдельная строка (течения ищем на переходах
##   меню↔город↔мир: запека/кэши умирают вместе со сценой);
## - ТРИГГЕР: свободной RAM < RAM_LOW_MB ИЛИ статик вырос от baseline
##   больше STATIC_JUMP_MB ИЛИ сирот-узлов > ORPHANS_MAX — полная
##   отчётная строка (окно сэмплов + размеры статик-кэшей полотен),
##   один и тот же триггер не чаще раза в 30 с.
##
## Вместе с freeze_dump.log (страж зависаний v2.6.7) это полный
## «уловитель»: RAM-давление — здесь, контекст зависания — там.

const SAMPLE_SEC := 5.0
const LOG_SEC := 60.0
const LOG_PATH := "user://mem_watchdog.log"
const LOG_MAX_BYTES := 1_000_000
const LOG_TAIL_BYTES := 200_000
const RAM_LOW_MB := 2048
const STATIC_JUMP_MB := 300
const ORPHANS_MAX := 400
const WINDOW := 120   # сэмплов в кольце (10 минут)

var _t_sample := 0.0
var _t_log := 0.0
var _base_static := -1
var _window: Array = []
var _scene := ""
var _trig := {}
var _godot_ver := ""


func _ready() -> void:
	_godot_ver = Engine.get_version_info().get("string", "?")
	_log_line("watch_on ver=%s ram_total=%dMB" % [_godot_ver, _ram_total_mb()])


func _process(delta: float) -> void:
	_t_sample += delta
	_t_log += delta
	if _t_sample >= SAMPLE_SEC:
		_t_sample = 0.0
		_sample()
	if _t_log >= LOG_SEC:
		_t_log = 0.0
		_log_line("tick " + _line_core())


func _sample() -> void:
	var s := _monitors()
	_window.append(s)
	if _window.size() > WINDOW:
		_window.pop_front()
	if _base_static < 0:
		_base_static = int(s["static_mb"])
	# смена сцены — строка (переходы — главные подозреваемые течений)
	var cur := _scene_name()
	if cur != _scene:
		_log_line("scene %s -> %s | %s" % [_scene, cur, _line_core()])
		_scene = cur
	# триггеры
	var why := ""
	if int(s["avail_mb"]) < RAM_LOW_MB:
		why += "ram_low(%dMB) " % int(s["avail_mb"])
	if (int(s["static_mb"]) - _base_static) > STATIC_JUMP_MB:
		why += "static_jump(+%dMB) " % (int(s["static_mb"]) - _base_static)
	if int(s["orphans"]) > ORPHANS_MAX:
		why += "orphans(%d) " % int(s["orphans"])
	var now := Time.get_ticks_msec() / 1000.0
	if why != "" and (not _trig.has(why) or now - float(_trig[why]) > 30.0):
		_trig[why] = now
		var tail := []
		for i in range(maxi(0, _window.size() - 6), _window.size()):
			tail.append(_window[i])
		_log_line("TRIGGER %s| caches[%s] | window=%s"
				% [why, _cache_report(), str(tail)])


func _monitors() -> Dictionary:
	var mi := OS.get_memory_info()
	return {
		"t": Time.get_ticks_msec() / 1000.0,
		"scene": _scene_name(),
		"static_mb": int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576,
		"static_max_mb": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576,
		"objs": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"res": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"avail_mb": int(mi.get("available", 0)) / 1048576,
		"total_mb": int(mi.get("physical", 0)) / 1048576,
	}


func _line_core() -> String:
	var s := _monitors()
	return ("static=%dMB max=%d objs=%d res=%d nodes=%d orphans=%d free=%dMB/%dMB"
			% [int(s["static_mb"]), int(s["static_max_mb"]), int(s["objs"]),
			int(s["res"]), int(s["nodes"]), int(s["orphans"]),
			int(s["avail_mb"]), int(s["total_mb"])])


func _scene_name() -> String:
	var cs := get_tree().current_scene
	return String(cs.name) if cs != null else "none"


## Статик-кэши полотен биомов (города и мира) — сколько набрано.
func _cache_report() -> String:
	var parts := []
	var ct := load("res://scripts/city_terrain_base.gd")
	if ct != null and ct.get("_canvas_proc_cache") != null:
		parts.append("city_canvas=%d" % (ct._canvas_proc_cache as Dictionary).size())
	var wv := load("res://scripts/world_view.gd")
	if wv != null and wv.get("_canvas_cache") != null:
		parts.append("world_canvas=%d" % (wv._canvas_cache as Dictionary).size())
	return " ".join(parts) if not parts.is_empty() else "n/a"


func _ram_total_mb() -> int:
	return int(OS.get_memory_info().get("physical", 0)) / 1048576


## Строка в журнал с подрезкой хвоста при переполнении.
func _log_line(line: String) -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	var old := ""
	if f != null:
		old = f.get_as_text()
		f.close()
	if old.length() > LOG_MAX_BYTES:
		old = old.substr(old.length() - LOG_TAIL_BYTES)
	var w := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if w != null:
		w.store_string(old + line + "\n")
		w.close()
