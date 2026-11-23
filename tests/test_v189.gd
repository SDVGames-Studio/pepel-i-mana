# v1.89: дневник и мысли жителей.
# Житель получает uid + дневник (кольцо 24 записи), события пишутся в
# хуках жизни; мысли — данные (ключ локали + аргументы), голос по черте.
extends "res://tests/test_base.gd"

func _test_diary_thoughts() -> void:
	print("[v1.89: дневник и мысли жителей]")
	var sim := _make_sim()
	_check(not sim.residents.is_empty(), "в городе есть жители")
	var r: Dictionary = sim.residents[0]
	_check(int(r.get("uid", -1)) >= 0, "у жителя есть uid")
	_check(not (r.get("log", []) as Array).is_empty(),
			"у новорождённого/пришедшего есть первая запись дневника")
	# поиск по uid
	_check(not sim.resident_by_uid(int(r["uid"])).is_empty(), "resident_by_uid находит жителя")
	# кольцо дневника: не растёт бесконечно
	for i in 30:
		sim.res_log(r, "dlog.sick")
	_check((r["log"] as Array).size() <= 24, "дневник — кольцо до 24 записей")
	# события жизни пишутся в дневник: болезнь через _make_ail
	var sick_one: Dictionary = sim.residents[2]
	sim._make_ail(sick_one, "sick", "chron.sick")
	var keys: Array = []
	for e in (sick_one["log"] as Array):
		keys.append(String(e["k"]))
	_check("dlog.sick" in keys, "хворь попадает в дневник")
	# мысли: у голодного первая мысль — про голод, формат {k, a}
	var hungry: Dictionary = sim.residents[1]
	hungry["state"] = "hungry"
	var th: Array = sim.resident_thoughts(hungry)
	_check(not th.is_empty() and String(th[0]["k"]).begins_with("thought.hungry."),
			"голодный думает о еде (ключ thought.hungry.*)")
	_check((th[0] as Dictionary).has("k") and (th[0] as Dictionary).has("a"),
			"мысль — данные: {k, a} без локализации в симуляции")
	# сытый житель хоть о чём-то да думает
	var calm: Dictionary = sim.residents[3]
	calm["state"] = "idle"
	var th2: Array = sim.resident_thoughts(calm)
	_check(not th2.is_empty(), "у спокойного жителя есть мысли")


func _test_bio() -> void:
	print("[v1.90: биография жителя]")
	var sim := _make_sim()
	var r: Dictionary = sim.residents[0]
	_check(String(r.get("origin", "")) != "", "у жителя есть происхождение")
	_check(String(r.get("fear", "")) != "", "у жителя есть страх")
	_check(String(r.get("past_prof", "")) != "", "у жителя есть прошлое ремесло")
	# локали биографии существуют (файл ru.json читается напрямую)
	var locs: Dictionary = _read_json("res://loc/ru.json")
	_check(locs.has("origin." + String(r["origin"])), "локаль происхождения есть")
	_check(locs.has("fear." + String(r["fear"])), "локаль страха есть")
	_check(locs.has("past." + String(r["past_prof"])), "локаль прошлого есть")


func _test_bio_facets() -> void:
	print("[v1.91: грани души]")
	var sim := _make_sim()
	var r: Dictionary = sim.residents[0]
	_check(String(r.get("like", "")) != "", "у жителя есть «любит»")
	_check(String(r.get("dislike", "")) != "", "у жителя есть «не выносит»")
	_check(String(r.get("habit", "")) != "", "у жителя есть привычка")
	var locs: Dictionary = _read_json("res://loc/ru.json")
	_check(locs.has("like." + String(r["like"])), "локаль «любит» есть")
	_check(locs.has("dislike." + String(r["dislike"])), "локаль «не выносит» есть")
	_check(locs.has("habit." + String(r["habit"])), "локаль привычки есть")


func _test_diary_matrix() -> void:
	print("[v1.92: дневник — голоса по чертам]")
	var locs: Dictionary = _read_json("res://loc/ru.json")
	var events := ["came", "born", "job", "conscript", "wounded", "sick",
			"married", "child_born", "rank3", "rank5", "quarrel", "gift",
			"friend", "goal_set", "tavern", "winter", "lost", "note"]
	var voices := ["plain", "grumpy", "cheerful", "lazy", "dreamer", "stoic"]
	var missing := 0
	for ev in events:
		for v in voices:
			if not locs.has("diary.%s.%s" % [ev, v]):
				missing += 1
	for g in ["become_master", "build_garden", "feast_tavern", "store_food"]:
		for v in voices:
			if not locs.has("diary.goal_done.%s.%s" % [g, v]):
				missing += 1
	_check(missing == 0, "матрица дневника полна: 18 событий × 6 голосов (нет %d)" % missing)
	var sim := _make_sim()
	var r: Dictionary = sim.residents[0]
	_check(sim.res_voice(r) in ["plain", "grumpy", "cheerful", "lazy", "dreamer", "stoic"],
			"голос жителя — из шести")
	# заметки-размышления: раз в 5 дней (день 5 — кратен)
	sim.day = 5
	sim._daily_notes()
	var has_note := false
	for e in (r["log"] as Array):
		if String(e["k"]) == "dlog.note":
			has_note = true
	_check(has_note, "размышление о жизни записано")


func _test_goal_done() -> void:
	print("[v1.93: выполнение цели — в дневник]")
	var sim := _make_sim()
	var r: Dictionary = sim.residents[0]
	r["goal"] = "feast_tavern"
	r["tavern_visited"] = true
	sim._roll_goals()   # ежедневная проверка целей
	var keys: Array = []
	for e in (r["log"] as Array):
		keys.append(String(e["k"]))
	_check("dlog.goal_done" in keys, "выполнение цели — запись в дневнике")
	var locs: Dictionary = _read_json("res://loc/ru.json")
	_check(locs.has("diary.goal_done.feast_tavern." + sim.res_voice(r)),
			"абзац «мечта сбылась» в голосе жителя есть")


func _test_secrets() -> void:
	print("[v1.94: тайные роли]")
	var sim := _make_sim()
	var r: Dictionary = sim.residents[0]
	r["secret"] = "thief"
	r["secret_revealed"] = false
	# скрытый: мысли — маскировка или прокол, никакой души
	var th: Array = sim.resident_thoughts(r)
	var k := String(th[0]["k"])
	_check(k.begins_with("thought.masked.") or k.begins_with("thought.slip.thief"),
			"скрытый вор думает нейтрально или прокалывается")
	# 3 улики -> раскрытие
	for i in 3:
		sim.res_log(r, "dlog.slip", ["thief"])
	_check(sim._secret_slips(r) >= 3, "улики копятся")
	var locs: Dictionary = _read_json("res://loc/ru.json")
	_check(locs.has("diary.slip.thief"), "локаль прокола вора есть")
	_check(locs.has("diary.slip.demonologist"), "локаль прокола демонолога есть")
	_check(locs.has("thought.masked.1"), "локаль маскировки есть")
