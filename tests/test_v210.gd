extends "res://tests/test_base.gd"
## v2.1 «Мозг старосты» (релиз 2.3.0): оборонный рывок до волны (кузня +
## стены, не дожидаясь полной застройки), таверна по письму мечтателя,
## странствующий чемпион после гибели героя. День выставляется явно.


func _res_rich(sim) -> void:
	sim.res["wood"] = 200.0
	sim.res["stone"] = 200.0
	sim.res["food"] = 60.0
	sim.res["tools"] = 10.0


func _test_defence_rush() -> void:
	print("[v2.1: оборонный рывок]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	_res_rich(sim)
	var day_len := float(sim.cfg["day_length"])
	# далеко до волны — рывка нет
	sim._next_raid_at = float(sim.time) + 9.0 * day_len
	var before: int = sim.buildings.size()
	sim.defence_rush_daily()
	_check(sim.buildings.size() == before, "до волны далеко — староста не суетится")
	# волна близко (ETA <= 5 дней) — рывок: кузня и стены
	sim._next_raid_at = float(sim.time) + 2.0 * day_len
	sim.defence_rush_daily()
	var types := {}
	for b in sim.buildings:
		types[String(b["type"])] = true
	_check(types.has("forge"), "рывок ставит кузню (стражи с железом)")
	_check(types.has("wall"), "рывок ведёт стены сегментами вокруг жилья")
	var rushed := false
	for ev in sim.events:
		if String(ev.get("type", "")) == "defence_rush":
			rushed = true
	_check(rushed, "летопись знает про оборонный рывок")
	# готовность: кольцо замкнуто было бы долго — проверяем логику на false
	_check(not sim._defence_ready(), "город ещё не готов: стены не замкнуты")


func _test_tavern_request() -> void:
	print("[v2.1: таверна по мечте]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	_res_rich(sim)
	# город мал — письма нет
	var dreamer: Dictionary = sim.residents[0]
	dreamer["goal"] = "feast_tavern"
	sim.tavern_request_daily()
	var asked := false
	for ev in sim.events:
		if String(ev.get("type", "")) == "tavern_request":
			asked = true
	_check(not asked, "в малом городе староста таверну не строит")
	# город подрос (>= 8) — мечтатель пишет, таверна вне очереди
	while sim.residents.size() < 8:
		var extra: Dictionary = {
			"id": 900 + sim.residents.size(), "name": "Гость %d" % sim.residents.size(),
			"prof": "", "goal": "", "tavern_asked": false, "log": [],
			"pos": Vector2.ZERO, "bld": null, "site": null, "ail": "",
			"mood": 60.0, "skill": 0.0, "rank": 0, "age_days": 100.0,
		}
		sim.residents.append(extra)
	sim.tavern_request_daily()
	var asked2 := false
	var tavern := false
	for ev2 in sim.events:
		if String(ev2.get("type", "")) == "tavern_request":
			asked2 = true
	for b2 in sim.buildings:
		if String(b2["type"]) == "tavern":
			tavern = true
	_check(asked2, "житель с мечтой пишет старосте письмо")
	_check(tavern, "староста ставит таверну вне очереди")
	_check(bool(dreamer.get("tavern_asked", false)), "письмо отправлено однажды")


func _test_champion() -> void:
	print("[v2.1: странствующий чемпион]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var day_len := float(sim.cfg["day_length"])
	_check(sim.champion.is_empty(), "чемпиона нет, пока герой жив")
	# герой пал — город ждёт чемпиона 3-5 дней
	sim.hero_fell()
	_check(sim.champion_due_day > int(sim.day), "после гибели героя назначен день прихода")
	var due: int = sim.champion_due_day
	sim.hero_fell()   # повторно — без изменений
	_check(sim.champion_due_day == due, "повторный вызов не сдвигает приход")
	# раньше срока — не пришёл
	sim.day = due - 1
	sim._champion_daily()
	_check(sim.champion.is_empty(), "чемпион не приходит раньше срока")
	# пришёл
	sim.day = due
	sim._champion_daily()
	_check(not sim.champion.is_empty(), "странствующий чемпион пришёл")
	_check(float(sim.champion["hp"]) > 0.0 and float(sim.champion["atk"]) > 0.0,
			"чемпион боеспособен")
	# в волне чемпион рубит мутантов
	sim._spawn_raid(2, false)
	_check(sim.raiders.size() == 2, "волна для проверки чемпиона")
	var foe: Dictionary = sim.raiders[0]
	var hp0: int = int(foe["hp"])
	sim.champion["pos"] = (foe["pos"] as Vector2) + Vector2(12, 0)
	sim._update_champion(0.5)
	_check(int(foe["hp"]) < hp0, "чемпион рубит мутанта у стен")
	# мутант бьёт в ответ (отвлечение в _raider_update); подлечим цель —
	# чемпион мог уложить её с одного удара (тогда _raider_update выйдет сразу)
	var tcfg: Dictionary = sim.cfg.get("threat", {})
	var chp0: float = float(sim.champion["hp"])
	foe["hp"] = int(foe["max_hp"])
	foe["pos"] = (sim.champion["pos"] as Vector2) + Vector2(10, 0)
	foe["atk_cd"] = 0.0
	sim._raider_update(foe, 0.05, tcfg)
	_check(float(sim.champion["hp"]) < chp0, "мутанты отвлекаются на чемпиона")
	# пал — не заменяется
	sim.champion["hp"] = 0.0
	sim._update_champion(0.016)
	_check(sim.champion.is_empty(), "павший чемпион не заменяется")
	var fell := false
	for ev3 in sim.events:
		if String(ev3.get("type", "")) == "champion_fell":
			fell = true
	_check(fell, "летопись знает о гибели чемпиона")


func _test_save_v21() -> void:
	print("[v2.1: сейв чемпиона]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	sim.champion = {"name": "Ратмир", "hp": 55.0, "hp_max": 60.0, "atk": 9.0,
			"speed": 80.0, "pos": Vector2(120, 90), "target": Vector2i(-1, -1),
			"cd": 0.0, "alive": true}
	sim.champion_due_day = -1
	var sv: Script = load("res://scripts/save_game.gd")
	var block: Dictionary = sv._city_block(sim)
	var simblk: Dictionary = block.get("sim", {}) as Dictionary
	_check(not (simblk.get("champion", {}) as Dictionary).is_empty(), "чемпион уходит в сейв")
	var sim2 := _make_sim()
	sim2._next_raid_at = 999999999.0
	sv._apply_city_sim(sim2, block)
	_check(not sim2.champion.is_empty() and String(sim2.champion["name"]) == "Ратмир",
			"чемпион восстанавливается из сейва")
	_check(Vector2(sim2.champion["pos"]) == Vector2(120, 90), "позиция чемпиона восстанавливается")
