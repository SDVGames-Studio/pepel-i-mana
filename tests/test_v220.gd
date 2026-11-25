extends "res://tests/test_base.gd"
## v2.2 «Следы, алтарь благодати, тайные лагеря»: следы всех ходячих,
## ищейка улья и волны «в точку» (не по воздуху), алтарь благодати с духом-
## работником, тайные лагеря и путники-лазутчики, странствующие охотники.
## День в тестах выставляется явно (грабли сессии).

const Tracks := preload("res://scripts/city_tracks.gd")


func _test_tracks() -> void:
	print("[v2.2: следы — хелпер]")
	var tr: Array = []
	tr = Tracks.push(tr, Vector2(0, 0), 0.0, "res", Vector2(1, 0))
	tr = Tracks.push(tr, Vector2(5, 0), 1.0, "res", Vector2(1, 0))
	_check(tr.size() == 1, "близкий след того же кто — не пишется (шаг)")
	tr = Tracks.push(tr, Vector2(60, 0), 2.0, "res", Vector2(1, 0))
	_check(tr.size() == 2, "дальний след пишется")
	tr = Tracks.push(tr, Vector2(70, 0), 3.0, "raider", Vector2(1, 0))
	_check(tr.size() == 3, "чужой след рядом пишется (другой who)")
	var near: Dictionary = Tracks.near(tr, Vector2(61, 0), 10.0, 3.0, 100.0, "res")
	_check(not near.is_empty() and String(near["who"]) == "res",
			"near: свежий след по фильтру who")
	var gone: Dictionary = Tracks.near(tr, Vector2(0, 0), 10.0, 100.0, 1.0)
	_check(gone.is_empty(), "протухший след не читается")
	var chain: Array = Tracks.chain(tr, Vector2(59, 0), 30.0, 3.0, 100.0, "res")
	_check(chain.size() == 2, "цепочка собирается по времени")
	var wiped := Tracks.prune(tr, 1000.0, 10.0)
	_check(wiped == 3 and tr.is_empty(), "prune стирает протухшие")


func _test_tracks_sampler() -> void:
	print("[v2.2: сэмплер следов в тике]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var day_len := float(sim.cfg["day_length"])
	sim.time = float(sim.day) * day_len
	var r: Dictionary = sim.residents[0]
	r["inside"] = 0
	r["pos"] = Vector2(100, 100)
	sim._track_accum = 0.9
	sim._update_tracks(1.0, day_len)   # первый сэмпл — точка отсчёта
	r["pos"] = Vector2(140, 100)       # житель шагнул — появляется след
	sim._track_accum = 0.9
	sim._update_tracks(1.0, day_len)
	_check(not sim.city_tracks.is_empty(), "сэмплер пишет следы идущих")
	var has_res := false
	for tr in sim.city_tracks:
		if String(tr["who"]) == "res":
			has_res = true
	_check(has_res, "житель оставил след who=res")
	# дождь укорачивает жизнь следов (константа)
	_check(Tracks.RAIN_MULT < 1.0, "дождь ускоряет таяние следов")


func _test_seeker_and_hive_waves() -> void:
	print("[v2.2: ищейка улья и волны «в точку»]")
	OS.set_environment("PEPEL_HIVE_ON", "1")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var day_len := float(sim.cfg["day_length"])
	var hive_tile: Vector2i = (sim.map.spawn_tile as Vector2i) + Vector2i(14, 8)
	sim.hive = {
		"active": true, "pos": sim.map.tile_center_px(hive_tile),
		"tile": hive_tile, "hp": 150.0, "level": 1, "stock": 50,
		"gathered": 0, "waves": 0,
		"next_wave_day": float(sim.day) + 2.0, "city_known": {}, "respawn_day": 0.0,
	}
	sim._update_hive(0.016, day_len)
	var has_seeker := false
	for r in sim.raiders:
		if String(r.get("role", "")) == "seeker":
			has_seeker = true
	_check(has_seeker, "улей высылает ищейку, пока не знает город")
	# без знания города волны из улья заблокированы («не по воздуху»)
	var rc: int = sim.raid_count
	sim.day = int(float(sim.hive["next_wave_day"])) + 1
	sim._update_hive(0.016, day_len)
	_check(sim.raid_count == rc, "без знания города волн из улья нет")
	# ищейка дошла до города: точная метка — волна идёт
	sim.hive["city_known"] = {
		"pos": sim.map.tile_center_px(sim.map.spawn_tile), "r": 0.0, "exact": true,
	}
	sim.day += 6   # гейтинг при блоке перенёс next_wave_day — догоняем
	sim._update_hive(0.016, day_len)
	_check(sim.raid_count > rc, "после находки ищейки волна из улья идёт")
	var wave_units := 0
	for r2 in sim.raiders:
		if String(r2.get("role", "")) == "" and not bool(r2.get("ambush", false)):
			wave_units += 1
	_check(wave_units > 0, "волна заспавнилась у логова и идёт в точку")
	# грязная метка (ищейка испугалась) тоже открывает волны
	var rc2: int = sim.raid_count
	sim.raiders.clear()
	sim.raid_active = false
	sim.hive["city_known"] = {"pos": Vector2.ZERO, "r": 400.0, "exact": false}
	sim.day += 6
	sim._update_hive(0.016, day_len)
	_check(sim.raid_count > rc2, "грязная метка «примерно здесь» тоже ведёт к волне")
	OS.set_environment("PEPEL_HIVE_ON", "")


func _test_altar_and_spirit() -> void:
	print("[v2.2: алтарь благодати и дух]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var t: Vector2i = sim.map.spawn_tile + Vector2i(4, 2)
	var b: Dictionary = {
		"id": 901, "type": "grace_altar", "tile": t, "done": false,
		"worker": -1, "progress": 0.0, "hp": 1.0, "spirit_respawn_day": -1,
	}
	sim.buildings.append(b)
	sim._complete_site(b)
	_check(bool(b["done"]), "алтарь благодати достроен (30-й тип)")
	_check(sim.spirits.size() == 1, "алтарь призвал духа-работника")
	sim.acolyte_skill = 0.0
	var eff0: float = sim.spirit_eff()
	sim.acolyte_skill = 20.0
	var eff1: float = sim.spirit_eff()
	_check(eff0 <= 0.5 + 0.01 and eff1 >= 1.19,
			"эффективность духа 50..120%% от мастерства аколита (%.2f..%.2f)" % [eff0, eff1])
	# дневной тик: аколит растёт, алтарь фонит загрязнением (тянет плесень)
	sim.acolyte_skill = 0.0
	b["worker"] = 5
	var pol0: float = sim.pollution
	sim.altar_daily()
	_check(sim.pollution > pol0, "алтарь фонит магическим загрязнением")
	_check(sim.acolyte_skill > 0.0, "аколит-контролёр растёт в мастерстве")
	# дух работает на добычу: сажаем дерево рядом — дух принесёт брёвна
	var g: Vector2i = sim.map.spawn_tile + Vector2i(3, 1)
	sim.map.grid[g.y][g.x] = sim.map.TILE_TREE
	sim.spirits[0]["mode"] = "gather"
	var sp: Dictionary = sim.spirits[0]
	sp["pos"] = sim.map.tile_center_px(g)   # дух уже у дерева
	sp["res_tile"] = g
	var w0: float = float(sim.res["wood"])
	sim._update_spirits(0.5)
	_check(float(sim.res["wood"]) > w0, "дух добывает с эффективностью духа")
	# дух гибнет — алтарь назначает перезов
	sim.spirits[0]["hp"] = 0.0
	sim._update_spirits(0.016)
	_check(sim.spirits.is_empty(), "павший дух уходит")
	_check(int(b["spirit_respawn_day"]) > int(sim.day), "алтарь назначил перезов духа")
	sim.day = int(b["spirit_respawn_day"])
	sim.altar_daily()
	_check(sim.spirits.size() == 1, "дух перозван через N дней")


func _test_camps_and_spies() -> void:
	print("[v2.2: тайные лагеря и путники-лазутчики]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var ccfg: Dictionary = sim.cfg.get("camps", {})
	# дневной ролл: лагерь появляется на дикой окраине
	for i in 40:
		sim.day = 10 + i
		sim.secret_camp_daily()
		if not sim.secret_camps.is_empty():
			break
	_check(not sim.secret_camps.is_empty(), "тайный лагерь основан (скрытая POI)")
	var camp: Dictionary = sim.secret_camps[0]
	_check(not bool(camp["found"]), "лагерь не виден, пока не найден")
	# преступление: кража со склада растит подозрение
	camp["kind"] = "bandit"   # кража — бандитский сценарий
	sim.res["food"] = 30.0
	var f0: float = float(sim.res["food"])
	camp["last_crime"] = int(sim.day) - 99
	sim._camp_crimes(ccfg)
	_check(float(sim.res["food"]) < f0, "кража со склада (бандиты)")
	_check(int(camp["suspicion"]) >= 1, "пропажа растит подозрение")
	# улика/раскрытие
	sim.reveal_camp()
	_check(bool(camp["found"]), "лагерь раскрыт уликой/допросом")
	# штурм стражей без стражей — отказ
	var err: String = sim.assault_camp(false)
	_check(err == "city.camp_need_guards", "штурм требует стражи")
	# штурм героем — успех на низкой угрозе
	sim.raid_count = 0
	err = sim.assault_camp(true)
	_check(err == "", "герой громит лагерь")
	_check(sim.secret_camps.is_empty(), "лагерь снесён")
	# лазутчик: визит окончен — кража и подсчёт визитов
	var w: Dictionary = {
		"id": 777, "pos": Vector2.ZERO, "path": PackedVector2Array(),
		"target": Vector2i(-1, -1), "mode": "leave", "tent": -1,
		"left": 0.0, "edge": Vector2i(0, 0), "spy": true,
		"spy_name": "Горий", "spy_camp": 1,
	}
	sim.res["food"] = 30.0
	sim.spy_known.clear()
	sim._spy_depart(w)
	_check(not (sim.spy_known.get("Горий", {"visits": 0}) as Dictionary).is_empty(),
			"жители считают визиты лазутчика")


func _test_hunt_squad() -> void:
	print("[v2.2: странствующие охотники на чудовищ]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var hive_tile: Vector2i = (sim.map.spawn_tile as Vector2i) + Vector2i(14, 8)
	sim.hive = {
		"active": true, "pos": sim.map.tile_center_px(hive_tile),
		"tile": hive_tile, "hp": 4.0, "level": 1, "stock": 50,
		"gathered": 0, "waves": 0,
		"next_wave_day": float(sim.day) + 9.0, "city_known": {}, "respawn_day": 0.0,
	}
	# отряд приходит после отбонной волны (шанс 1.0 в конфиге теста)
	(sim.cfg["hunt_squad"] as Dictionary)["chance"] = 1.0
	sim._try_spawn_hunt_squad()
	_check(not sim.hunter_squad.is_empty(), "отряд охотников в пути")
	sim.day = int(sim.hunter_squad["eta_day"])
	sim.hunt_squad_daily()
	var allies := 0
	for r in sim.raiders:
		if String(r.get("role", "")) == "hunt_ally":
			allies += 1
	_check(allies >= 1, "охотники пришли и идут на логово")
	# бой у логова: улей с малым hp падает, городу — доля добычи
	var u: Dictionary = {}
	for r2 in sim.raiders:
		if String(r2.get("role", "")) == "hunt_ally":
			u = r2
			break
	u["pos"] = (sim.hive["pos"] as Vector2) + Vector2(10, 0)
	var food0: float = float(sim.res["food"])
	sim._hunt_ally_update(u, 1.0)
	_check(not bool(sim.hive.get("active", false)), "охотники разорили логово")
	_check(float(sim.res["food"]) > food0, "городу досталась доля добычи")
	_check(bool(u.get("ha_win", false)), "охотник зафиксировал победу")


func _test_save_v22() -> void:
	print("[v2.2: сейв нового состояния]")
	var sim := _make_sim()
	sim._next_raid_at = 999999999.0
	var t: Vector2i = sim.map.spawn_tile + Vector2i(4, 2)
	var b: Dictionary = {"id": 901, "type": "grace_altar", "tile": t, "done": false,
			"worker": -1, "progress": 0.0, "hp": 1.0, "spirit_respawn_day": -1}
	sim.buildings.append(b)
	sim._complete_site(b)
	sim.secret_camps.append({"id": 1, "tile": sim.map.spawn_tile + Vector2i(20, 5),
			"kind": "bandit", "found": false, "suspicion": 1, "visits": 0,
			"spies": ["Горий", "Влада"], "last_crime": -99})
	var sv: Script = load("res://scripts/save_game.gd")
	var block: Dictionary = sv._city_block(sim)
	var simblk: Dictionary = block.get("sim", {}) as Dictionary
	_check((simblk.get("spirits", []) as Array).size() == 1, "дух сохраняется")
	_check((simblk.get("secret_camps", []) as Array).size() == 1, "тайный лагерь сохраняется")
	var sim2 := _make_sim()
	sim2._next_raid_at = 999999999.0
	sv._apply_city_sim(sim2, block)
	_check(sim2.spirits.size() == 1, "дух восстанавливается")
	_check(sim2.secret_camps.size() == 1
			and (sim2.secret_camps[0]["tile"] as Vector2i) == sim.map.spawn_tile + Vector2i(20, 5),
			"лагерь восстанавливается с тайлом")
