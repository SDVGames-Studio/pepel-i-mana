# Тесты v1.24: пять статов у всех (жители с врождённым пулом 20–30, герой
# с ростом от дел, существа с производными статами и боссами сверх капа),
# мудрость противится зову; кладбищенское здание гасит тьму, восстания только
# от ритуалов (кроме тёмной бури), некроманта разоблачить можно только на
# кладбище и не видно с дальнего расстояния.
extends "res://tests/test_base.gd"

const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")


# --- врождённый пул статов жителей (v1.24) ------------------------------------

func _test_v124_pools() -> void:
	var sim = _make_sim()
	print("[v1.24: пул статов жителей]")
	for r in sim.residents:
		var st: Dictionary = r.get("stats", {})
		_check(st.has("wis"), "у жителя есть мудрость (%s)" % String(r["name"]))
		var total := 0.0
		for k in ["str", "agi", "end", "int", "wis"]:
			total += float(st.get(k, 0.0))
		_check(total >= 19.0 and total <= 31.0,
				"пул в 20–30 очков (%s: %.0f)" % [String(r["name"]), total])
		for k in ["str", "agi", "end", "int", "wis"]:
			_check(float(st.get(k, 0.0)) <= 12.5,
					"%s: статка %s не выше капы старта (%.0f)" % [String(r["name"]), k, float(st.get(k, 0.0))])
	# жители разные: пулы не identical
	var sums := {}
	for r in sim.residents:
		var t := 0.0
		for k in ["str", "agi", "end", "int", "wis"]:
			t += float((r.get("stats", {}) as Dictionary).get(k, 0.0))
		sums["%.0f" % t] = true
	_check(sums.size() >= 2, "жители рождаются разными (пулы различаются)")
	# мудрость в карте деятельности: алтарь качает интеллект и мудрость
	# (обнуляем оба стата — врождённый пул не должен упираться в кап)
	var aco: Dictionary = _resident_by_prof(sim, "acolyte")
	if aco.is_empty():
		aco = sim.residents[0]
	aco["traits"] = []
	(aco.get("stats", {}) as Dictionary)["int"] = 0.0
	(aco.get("stats", {}) as Dictionary)["wis"] = 0.0
	var before_int: float = float((aco.get("stats", {}) as Dictionary).get("int", 0.0))
	var before_wis: float = float((aco.get("stats", {}) as Dictionary).get("wis", 0.0))
	sim._grow_skill(aco, float(sim.cfg["day_length"]) * 4.0, "acolyte")
	_check(float((aco.get("stats", {}) as Dictionary).get("int", 0.0)) > before_int,
			"служба алтарю качает интеллект")
	_check(float((aco.get("stats", {}) as Dictionary).get("wis", 0.0)) > before_wis,
			"…и мудрость")


# --- зов тьмы идёт к наименее мудрым (v1.24) -----------------------------------

func _test_v124_wis_call() -> void:
	var sim = _make_sim()
	print("[v1.24: мудрость противится зову]")
	sim.cemetery_tile = sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(12, 3))
	sim.graves.append({"tile": sim.cemetery_tile, "name": "Старик", "ready": true, "rite": "bury"})
	var foolish: Dictionary = sim.residents[0]
	var wise: Dictionary = sim.residents[3]
	for r in sim.residents:
		(r["stats"] as Dictionary)["wis"] = 10.0
	# трое наименее мудрых — все с нулём: кого бы из трёх зов ни взял,
	# мудрые (10) точно не услышат — тест детерминирован
	(sim.residents[0]["stats"] as Dictionary)["wis"] = 0.0
	(sim.residents[1]["stats"] as Dictionary)["wis"] = 0.0
	(sim.residents[2]["stats"] as Dictionary)["wis"] = 0.0
	sim.cfg["necro"]["call_chance"] = 1.0
	sim._roll_necro()
	var chosen_wis := -1.0
	for r in sim.residents:
		if String(r.get("secret", "")) == "necromancer":
			chosen_wis = float((r.get("stats", {}) as Dictionary).get("wis", 0.0))
	_check(chosen_wis == 0.0, "зов взял наименее мудрого (мудрость %.0f)" % chosen_wis)
	_check(float((wise.get("stats", {}) as Dictionary).get("wis", 0.0)) == 10.0
			and String(wise.get("secret", "")) != "necromancer",
			"мудрый не услышал зов")


# --- статы героя: рост от дел и эффекты (v1.24) ---------------------------------

func _test_v124_hero_stats() -> void:
	print("[v1.24: статы героя]")
	var game = load("res://scripts/game.gd").new()
	# старт: пять статов по 2
	for k in ["str", "agi", "end", "int", "wis"]:
		_check(absf(game.hero_stat(k) - 2.0) < 0.001, "старт героя: %s = 2" % k)
	# рост от дел: рубил сто деревьев — сила выросла, кап держит
	game.hero_train("str", 0.1 * 100.0)
	_check(game.hero_stat("str") > 10.0, "сто трудов качают силу (%.1f)" % game.hero_stat("str"))
	game.hero_train("str", 1000.0)
	_check(absf(game.hero_stat("str") - float(game._hero_attrs_cfg().get("hero_cap", 20.0))) < 0.001,
			"кап статов героя держит (%.1f)" % game.hero_stat("str"))
	# эффекты: сила — урон, выносливость — хп, ловкость — броня, интеллект — магия
	var save_cfg: Dictionary = HeroScript._ha
	HeroScript._ha = {"str_dmg": 0.5, "end_hp": 2.0, "agi_armor": 0.25, "int_spell": 0.04}
	_check(HeroScript.stat_melee_bonus(HeroScript.attrs_cfg(), 10.0) == 5, "сила 10 → +5 урона")
	_check(HeroScript.stat_hp_bonus(HeroScript.attrs_cfg(), 10.0) == 20, "выносливость 10 → +20 здоровья")
	_check(HeroScript.stat_armor_bonus(HeroScript.attrs_cfg(), 8.0) == 2, "ловкость 8 → +2 защиты")
	_check(absf(HeroScript.stat_spell_mult(HeroScript.attrs_cfg(), 10.0) - 1.4) < 0.001,
			"интеллект 10 → магия ×1.4")
	HeroScript._ha = save_cfg


# --- статы существ: боссы сверх капа (v1.24) ------------------------------------

func _test_v124_enemy_stats() -> void:
	print("[v1.24: статы существ и боссы]")
	var rat := {"id": "rat", "hp": 3, "damage": 1, "speed": 90, "mana_chance": 0.3}
	var brute := {"id": "brute", "hp": 26, "damage": 4, "speed": 70, "mana_chance": 0.2}
	var boss := {"id": "demon_lord", "hp": 90, "damage": 6, "speed": 85, "mana_chance": 0.5, "boss": true}
	var s_rat: Dictionary = EnemyScript.derive_stats(rat)
	var s_boss: Dictionary = EnemyScript.derive_stats(boss)
	for k in ["str", "agi", "end", "int", "wis"]:
		_check(s_rat.has(k), "у крысы есть стат %s" % k)
	_check(float(s_boss["str"]) > float(s_rat["str"]) * 2.0,
			"босс силой сверх капы обычных (%.0f против %.0f)" % [float(s_boss["str"]), float(s_rat["str"])])
	# урон существа масштабируется силой; босс бьёт больнее базы
	_check(EnemyScript.melee_damage(brute) > int(brute["damage"]),
			"сила существа утяжеляет удар (%d > %d)" % [EnemyScript.melee_damage(brute), int(brute["damage"])])
	_check(EnemyScript.melee_damage(boss) > EnemyScript.melee_damage(brute),
			"босс бьёт сильнее бродяги")
	# маг-стрелок: интеллект утяжеляет снаряд
	var mage := {"id": "skeleton_mage", "hp": 12, "damage": 3, "speed": 60,
			"mana_chance": 0.4, "projectile_speed": 240.0}
	_check(EnemyScript.spell_damage(mage) > int(mage["damage"]),
			"интеллект существа питает его магию (%d > %d)" % [EnemyScript.spell_damage(mage), int(mage["damage"])])


# --- кладбищенское здание гасит тьму (v1.24) -------------------------------------

func _test_v124_cemetery_building() -> void:
	var sim = _make_sim()
	print("[v1.24: здание кладбища против тьмы]")
	var day_len: float = float(sim.cfg["day_length"])
	# без здания тьма стоит (никто её не ест)
	sim.cemetery_tile = sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(12, 3))
	sim.necro_dark = 0.5
	sim._update_cemetery(day_len, day_len)
	_check(absf(sim.necro_dark - 0.5) < 0.001, "без здания тьма не тает сама")
	# здание освящает землю: тьма спадает день за днём
	var cem := _build_now(sim, "cemetery")
	_check(bool(cem["done"]), "кладбище построено")
	sim._update_cemetery(day_len, day_len)
	var decay: float = float(sim.cfg.get("cemetery", {}).get("building_decay_per_day", 0.08))
	_check(sim.necro_dark < 0.5 - decay * 0.5,
			"здание кладбища гасит тьму (%.2f → %.2f)" % [0.5, sim.necro_dark])


# --- тёмная буря: мёртвые встают сами (v1.24) ------------------------------------

func _test_v124_dark_storm() -> void:
	var sim = _make_sim()
	print("[v1.24: тёмная буря]")
	sim.cemetery_tile = sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(12, 3))
	for gi in 3:
		sim.graves.append({"tile": sim.cemetery_tile + Vector2i(1 + gi, 1),
				"name": "Павший", "ready": true, "rite": "bury"})
	sim.necro_dark = 0.6
	sim.cfg["necro"]["storm_chance"] = 1.0
	sim.cfg["necro"]["summon_chance"] = 0.0
	sim._roll_necro()
	_check(sim.raid_active and String(sim._raid_kind) == "undead",
			"буря подняла мёртвых без некроманта")
	var storm_event := false
	for ev in sim.events:
		if String(ev["type"]) == "dark_storm":
			storm_event = true
	_check(storm_event, "тёмная буря объявлена городу")
	var skels := 0
	for r in sim.raiders:
		if String(r["type"]) == "skeleton":
			skels += 1
	_check(skels >= 2, "восстали по числу могил (%d скелетов)" % skels)
	_check(sim.necro_dark < 0.6, "буря спустила накопленную тьму (%.2f)" % sim.necro_dark)
	_check(int(sim.necro_army) == 0, "тайная армия при буре не тратится")


# --- некромант: разоблачение только на кладбище, невидимость (v1.24) ------------

func _test_v124_necro_stealth() -> void:
	var sim = _make_sim()
	print("[v1.24: тень на кладбище]")
	var day_len: float = float(sim.cfg["day_length"])
	sim.cemetery_tile = sim.map.nearest_walkable(sim.map.spawn_tile + Vector2i(12, 3))
	var necro: Dictionary = sim.residents[0]
	necro["secret"] = "necromancer"
	necro["fatigue"] = 0.0
	necro["bld"] = null
	necro["site"] = null
	var witness: Dictionary = sim.residents[1]
	witness["state"] = "idle"
	witness["inside"] = 0
	# 1) в пути свидетели не считаются: разоблачить можно только на кладбище
	_teleport(sim, necro, sim.map.nearest_walkable(Vector2i(sim.cemetery_tile) + Vector2i(6, 0)))
	_teleport(sim, witness, sim.map.nearest_walkable(Vector2i(sim.cemetery_tile) + Vector2i(6, 1)))
	for i in 20:
		if not sim._necro_night_walk(necro, 1.0):
			break
		if String(necro.get("necro_phase", "")) == "rite":
			break
	_check(not sim.necro_known, "в пути некроманта не разоблачить")
	# 2) у самых могил — можно увидеть: свидетель в 4 клетках
	_teleport(sim, necro, sim.cemetery_tile)
	_teleport(sim, witness, sim.map.nearest_walkable(Vector2i(sim.cemetery_tile) + Vector2i(1, 0)))
	necro["necro_phase"] = "rite"
	sim._necro_night_walk(necro, 0.1)
	_check(sim.necro_known, "у могил свидетели разоблачили некроманта")
	# 3) невидимость: на кладбище не видно с дальнего расстояния
	sim.necro_known = false
	var far_px: Vector2 = sim.map.tile_center_px(sim.cemetery_tile) + Vector2(32 * 10, 0)
	var near_px: Vector2 = sim.map.tile_center_px(sim.map.nearest_walkable(Vector2i(sim.cemetery_tile) + Vector2i(1, 0)))
	_check(sim.necro_hidden_from(necro, far_px), "издалека некроманта на кладбище не видно")
	_check(not sim.necro_hidden_from(necro, near_px), "в 4 клетках тьма расступается")
	_check(not sim.necro_hidden_from(witness, near_px), "обычный житель виден всегда")
	_teleport(sim, necro, sim.map.nearest_walkable(sim.map.spawn_tile))
	_check(not sim.necro_hidden_from(necro, far_px), "вне кладбища некромант видим")
