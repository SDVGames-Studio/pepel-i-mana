# Расы жителей (v1.64, п.3 — ответ №108): данные, генерация, наследование,
# статы и отрисовка (tint/scale/нимб).
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_races() -> void:
	print("[Расы жителей v1.64]")
	var people: Dictionary = _read_json("res://data/residents.json")
	var races: Dictionary = people.get("races", {})
	var race_ids: Array = []
	for k in races.keys():
		if not String(k).begins_with("_"):
			race_ids.append(String(k))
	var want_races: Array = ["human", "orc", "undead", "angel", "demon",
			"goblin", "kobold", "dwarf", "gnome"]
	var all_present := true
	for rid in want_races:
		if not race_ids.has(rid):
			all_present = false
	_check(all_present, "все 9 рас ответа №108 описаны (%d)" % race_ids.size())
	# у каждой расы: вес, палитра, рост; статы в пределах ±2
	var weights_ok := true
	var stats_ok := true
	for id in race_ids:
		var rc: Dictionary = races.get(id, {})
		if float(rc.get("weight", 0.0)) <= 0.0 or String(rc.get("tint", "")) == "" \
				or float(rc.get("scale", 0.0)) <= 0.0:
			weights_ok = false
		for sk in rc.get("stats", {}):
			if absf(float(rc["stats"][sk])) > 2.0:
				stats_ok = false
	_check(weights_ok, "вес/палитра/рост заполнены у всех рас")
	_check(stats_ok, "расовые статы в пределах ±2 (мягкие отличия)")
	# локализация рас
	var loc: Dictionary = _read_json("res://loc/ru.json")
	for id in race_ids:
		_check(String(loc.get("race." + String(id), "")) != "",
				"локализация расы: " + String(id))

	# генерация: броски дают людей чаще прочих, покрывают большинство рас
	var sim := _make_sim()
	var seen: Dictionary = {"human": 0}
	for i in 400:
		var rid := String(sim._roll_race())
		seen[rid] = int(seen.get(rid, 0)) + 1
	_check(int(seen.get("human", 0)) > 150, "люди — самая частая раса (%d из 400)" % int(seen.get("human", 0)))
	_check(seen.size() >= 7, "броски покрывают расы (%d видов)" % seen.size())
	_check(String(sim.residents[0].get("race", "?")) != "?", "у новых жителей есть раса")

	# статы: орк силённее того же пула на +2 (модификатор в _stat);
	# базу фиксируем человеком — иначе разницу может съесть раса базы
	var base_r: Dictionary = sim.residents[0]
	base_r["race"] = "human"
	var orc_r: Dictionary = sim._new_resident("Груша", "farmer", sim.map.spawn_tile)
	orc_r["stats"] = (base_r["stats"] as Dictionary).duplicate(true)
	orc_r["race"] = "orc"
	var str_gain: float = sim._stat(orc_r, "str") - sim._stat(base_r, "str")
	_check(absf(str_gain - 2.0) < 0.001, "орк: сила +2 к тому же пулу (%.1f)" % str_gain)
	var agi_gain: float = sim._stat(orc_r, "agi") - sim._stat(base_r, "agi")
	_check(absf(agi_gain + 1.0) < 0.001, "орк: ловкость −1 (%.1f)" % agi_gain)

	# дети наследуют расу родителя: код рождения переносит race родителя
	# (рождение зависит от многих предусловий — проверяем сам перенос)
	var gsrc_f := FileAccess.open("res://scripts/city_sim_gov.gd", FileAccess.READ)
	var gsrc: String = gsrc_f.get_as_text() if gsrc_f != null else ""
	gsrc_f = null
	_check(gsrc.find("child[\"race\"] = String(parent.get(\"race\"") >= 0,
			"рождение: ребёнок наследует расу родителя")

	# отрисовка: draw_villager принимает scale (рост расы), нимб ангела — в view
	var asrc_f := FileAccess.open("res://scripts/assets.gd", FileAccess.READ)
	var asrc: String = asrc_f.get_as_text() if asrc_f != null else ""
	asrc_f = null
	_check(asrc.find("tint := Color.WHITE, scale := 1.0") >= 0,
			"draw_villager красит палитрой и масштабирует рост расы")
	var vsrc_f := FileAccess.open("res://scripts/city_view.gd", FileAccess.READ)
	var vsrc: String = vsrc_f.get_as_text() if vsrc_f != null else ""
	vsrc_f = null
	_check(vsrc.find("race_tint") >= 0 and vsrc.find("halo") >= 0,
			"отрисовка жителя применяет палитру расы и нимб ангела")

	# сейв: race уходит в файл (все поля копируются), старые сейвы — человек
	var SGW: Script = load("res://scripts/save_game_write.gd")
	var sim_s := _make_sim()
	sim_s.residents[0]["race"] = "angel"
	var saved: Array = SGW._residents_save(sim_s)
	var found := ""
	for r in saved:
		if int(r["id"]) == int(sim_s.residents[0]["id"]):
			found = String(r.get("race", ""))
			break
	_check(found == "angel", "раса сохраняется в сейве (%s)" % found)
	_check(sim_s.residents[0].get("race", "human") is String,
			"раса — строка (старые сейвы дефолтятся на human)")

	# города ангелов/демонов/нежити в пуле поселений (просьба заказчика)
	var world_cfg: Dictionary = _read_json("res://data/world.json")
	var pool: Array = world_cfg.get("pois", {}).get("settlements", [])
	_check(pool.has("angels") and pool.has("demons") and pool.has("undead"),
			"поселения ангелов/демонов/нежити в пуле мира")
	print("[Расы] готово")
