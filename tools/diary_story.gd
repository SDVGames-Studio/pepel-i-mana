extends SceneTree
## Истории жителей: 30 дней настоящей симуляции → дневники + мысли.
## Запуск: godot --headless --path . --script res://tools/diary_story.gd
## Сид и длительность — env SEED / DAYS (по умолчанию 20261123 / 30).

const LOCS := "res://loc/ru.json"

var _loc: Dictionary = {}
var sim = null


func _initialize() -> void:
	var f := FileAccess.open(LOCS, FileAccess.READ)
	_loc = JSON.parse_string(f.get_as_text())

	var seed_v := 20261123
	if OS.get_environment("SEED") != "":
		seed(int(OS.get_environment("SEED")))
	var days := 31
	if OS.get_environment("DAYS") != "":
		days = int(OS.get_environment("DAYS")) + 1

	var cfg: Dictionary = _read_json("res://data/city.json")
	var city_map = load("res://scripts/city_map.gd").new()
	city_map.generate(seed_v, cfg)
	sim = load("res://scripts/city_sim.gd").new()
	sim.setup(city_map, cfg, 12, "normal")
	sim._last_daily_day = 1

	# 30 дней жизни города, шаг 1 сек
	var steps := int(float(days) * float(cfg["day_length"]))
	for i in steps:
		sim.tick(1.0)
	print("=== город «%s»: %d дней, жителей %d, построек %d ===" % [
		"Пепел и Благодать", sim.day, sim.residents.size(), sim.buildings.size()])

	# самые «событийные» взрослые жители
	var scored: Array = []
	for r in sim.residents:
		var keys := {}
		for e in (r.get("log", []) as Array):
			keys[String(e["k"])] = true
		var score := keys.size() * 10 + (r.get("log", []) as Array).size()
		if String(r["prof"]) != "" and not bool(r.get("golem", false)):
			score += 5
		scored.append([score, r])
	scored.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	var top := mini(4, scored.size())
	for i in top:
		_print_resident(scored[i][1])
	quit(0)


func _print_resident(r: Dictionary) -> void:
	var traits := PackedStringArray()
	for t in (r.get("traits", []) as Array):
		traits.append(_t("trait." + String(t)))
	print("\n--- %s, %s%s ---" % [String(r["name"]), _prof(String(r["prof"])),
			(" (" + ", ".join(traits) + ")") if not traits.is_empty() else ""])
	# биография (v1.90)
	var origin := String(r.get("origin", ""))
	if origin != "":
		if origin == "lost_forest":
			print(_t("origin.lost_forest") % int(r.get("origin_arg", 5)))
		else:
			print(_t("origin." + origin))
		past_print(r, self)
	if String(r.get("fear", "")) != "":
		print(_t("city.bio.fear") % _t("fear." + String(r["fear"])))
	if String(r.get("like", "")) != "":
		print(_t("city.bio.like") % _t("like." + String(r["like"])))
	if String(r.get("dislike", "")) != "":
		print(_t("city.bio.dislike") % _t("dislike." + String(r["dislike"])))
	if String(r.get("habit", "")) != "":
		print(_t("city.bio.habit") % _t("habit." + String(r["habit"])))
	if String(r.get("goal", "")) != "":
		print(_t("city.bio.dream") % _t("goal." + String(r["goal"])))
	print("Думает сейчас:")
	for th in _thoughts(r):
		print("  «%s»" % th)
	var log: Array = r.get("log", [])
	print("Дневник (%d):" % log.size())
	for e in log:
		print("  [День %d] %s" % [int(e["d"]), _dlog(e)])


func _thoughts(r: Dictionary) -> Array:
	var out: Array = []
	for th in sim.resident_thoughts(r):
		out.append(_fmt(String(th["k"]), th.get("a", [])))
	return out


func _dlog(e: Dictionary) -> String:
	var key := String(e["k"])
	var args: Array = []
	for a in (e.get("a", []) as Array):
		var s := String(a)
		args.append(_prof(s) if key in ["dlog.job", "dlog.conscript"] else s)
	return _fmt(key, args)


func _fmt(key: String, args: Array) -> String:
	var fmt := _t(key)
	if args.is_empty():
		return fmt
	var safe: Array = []
	for a in args:
		safe.append(str(a).replace("%", "%%"))
	return str(fmt % safe) if fmt.contains("%") else fmt


func _prof(prof: String) -> String:
	return _t("prof." + prof)


func _t(key: String) -> String:
	return String(_loc.get(key, key))


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


## Прошлое ремесло против нынешнего (для печатной биографии).
static func past_print(r: Dictionary, ctx) -> void:
	var past := String(r.get("past_prof", ""))
	var prof := String(r["prof"])
	if past == "":
		return
	var past_l: String = ctx._t("past." + past)
	var same := (past == "axemaster" and prof == "lumberjack") 		or (past == "hunter_past" and prof == "hunter") 		or (past == "peasant" and prof == "farmer") 		or (past == "herbalist" and prof == "healer") 		or (past == "smith_past" and prof in ["smith", "smelter", "armorer"]) 		or (past == "laborer" and prof == "porter")
	if same:
		print(ctx._t("city.bio.same_craft") % past_l)
	else:
		print(ctx._t("city.bio.past_and_new") % [past_l, ctx._prof(prof)])
