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
	var hero_bot := OS.get_environment("HERO_BOT") == "1"
	var hero_hp := 80.0
	var bot_cd := 0.0
	if hero_bot:
		sim.hero_alive = true
		sim.hero_pos = city_map.tile_center_px(city_map.spawn_tile)
		print("=== герой-бот: меч 12, хп 80, лечение +25 между волнами ===")
	sim._last_daily_day = 1
	# GOALFOOD=1: полный погреб — цели «запасти еды» сбываются (демо)
	if OS.get_environment("GOALFOOD") != "":
		sim.res["food"] = 500.0

	# 30 дней жизни города, шаг 1 сек
	var steps := int(float(days) * float(cfg["day_length"]))
	var hero_dead_day := -1
	var hero_kills := 0
	for i in steps:
		sim.tick(1.0)
		if hero_bot and sim.hero_alive:
			# урон герою из событий (мутанты бьют героя в симуляции)
			var ev_i: int = sim.events.size() - 1
			while ev_i >= 0:
				var ev: Dictionary = sim.events[ev_i]
				if String(ev["type"]) == "hero_hit":
					hero_hp -= float(ev["dmg"])
				ev_i -= 1
			if hero_hp <= 0.0:
				sim.hero_alive = false
				sim.hero_fell()   # v2.1: город зовёт чемпиона
				hero_dead_day = sim.day
				print("!!! ГЕРОЙ ПАЛ на день %d" % sim.day)
				continue
			# бот: телепорт в гущу и удар с кулдауном меча
			if sim.raiders.size() > 0:
				var nearest: Dictionary = sim.raiders[0]
				for rr in sim.raiders:
					if (rr["pos"] as Vector2).distance_to(sim.hero_pos) < (nearest["pos"] as Vector2).distance_to(sim.hero_pos):
						nearest = rr
				sim.hero_pos = nearest["pos"]
				bot_cd -= 1.0
				if bot_cd <= 0.0:
					bot_cd = 0.5
					nearest["hp"] = int(nearest["hp"]) - 12
					if int(nearest["hp"]) <= 0:
						sim.raiders.erase(nearest)
						hero_kills += 1
			else:
				sim.hero_pos = city_map.tile_center_px(city_map.spawn_tile)
				hero_hp = minf(80.0, hero_hp + 25.0)   # лечение между волнами

	print("=== город «%s»: %d дней, жителей %d, построек %d ===" % [
		"Пепел и Благодать", sim.day, sim.residents.size(), sim.buildings.size()])
	if hero_bot:
		var hstate := "жив (хп %d)" % int(maxf(0.0, hero_hp))
		if hero_dead_day > 0:
			hstate = "ПАЛ на день %d" % hero_dead_day
		print("=== герой: %s, убито мутантов: %d ===" % [hstate, hero_kills])

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
		print("  [День %d] %s" % [int(e["d"]), _diary(r, e)])


func _thoughts(r: Dictionary) -> Array:
	var out: Array = []
	for th in sim.resident_thoughts(r):
		out.append(_fmt(String(th["k"]), th.get("a", [])))
	return out


func _voice(r: Dictionary) -> String:
	for v in ["grumpy", "cheerful", "lazy", "dreamer", "stoic"]:
		if v in (r.get("traits", []) as Array):
			return v
	return "plain"


func _diary(r: Dictionary, e: Dictionary) -> String:
	var base := String(e["k"]).substr(5)
	var goal_id := ""
	if base == "goal_done":
		var ga: Array = e.get("a", [])
		goal_id = String(ga[0]) if not (ga as Array).is_empty() else ""
	var key := "diary.%s.%s.%s" % [base, goal_id, _voice(r)] if goal_id != "" 			else "diary.%s.%s" % [base, _voice(r)]
	var fmt := _t(key)
	if fmt == key:
		return _dlog(e)
	var args: Array = []
	for a in (e.get("a", []) as Array):
		var s := String(a)
		if base in ["job", "conscript"]:
			args.append(_prof(s))
		elif base == "goal_set":
			args.append(_t("goal." + s))
		elif base == "goal_done":
			pass   # имя цели вшито в текст абзаца
		elif base == "note":
			args.append(_t("season.word." + s))
		else:
			args.append(s)
	return _fmt(key, args)


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
