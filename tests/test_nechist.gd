# Нечисть v1.30 (док 14): данные, перки, боссы, лут, локализация.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_nechist() -> void:
	print("[Нечисть v1.30: 9 тварей + Вий/Яга/Кощей]")
	var enemies: Array = _read_json("res://data/enemies.json")
	var dungeon: Dictionary = _read_json("res://data/dungeon.json")
	var loc: Dictionary = _read_json("res://loc/ru.json")
	_check(enemies is Array and dungeon is Dictionary and loc is Dictionary,
			"конфиги читаются")
	if not (enemies is Array and dungeon is Dictionary and loc is Dictionary):
		return
	var by_id := {}
	for e: Dictionary in enemies:
		by_id[String(e["id"])] = e
	# --- состав: 9 младших + 3 босса + слуги ---
	var roster := ["leshy", "vodyanoy", "kikimora", "rusalka", "upyr", "volkolak",
			"bannik", "polevik", "nochnitsa"]
	var roster_ok := true
	for id in roster:
		if not by_id.has(id):
			roster_ok = false
	_check(roster_ok, "все 9 младших тварей в enemies.json")
	var bosses := ["viy", "baba_yaga", "koshchei"]
	var boss_ok := true
	for id in bosses:
		if not by_id.has(id) or not bool(by_id[id].get("boss", false)):
			boss_ok = false
	_check(boss_ok, "боссы Вий/Баба-яга/Кощей помечены boss: true")
	_check(by_id.has("black_hen") and by_id.has("death_needle"),
			"слуги: чёрная курица и игла смерти")
	# перки у каждой твари и школы уязвимости валидны
	var schools := ["wild", "light", "nature", "forbidden"]
	var perk_ok := true
	var school_ok := true
	var nocturnal := 0
	for id in roster:
		var e: Dictionary = by_id[id]
		if String(e.get("perk", "")) == "" and float(e.get("lifesteal", 0.0)) <= 0.0:
			perk_ok = false   # упырь: механика — вампиризм (lifesteal)
		if not (String(e.get("weak_school", "")) in schools):
			school_ok = false
		if bool(e.get("nocturnal", false)):
			nocturnal += 1
	_check(perk_ok, "у каждой младшей твари есть перк")
	_check(school_ok, "школы уязвимости валидны (wild/light/nature/forbidden)")
	_check(nocturnal >= 4, "ночные твари помечены (ночь города и тьма данжа)")
	_check(String(by_id["viy"].get("perk", "")) == "gaze",
			"Вий — таймер проклятия «веки» (решение №3)")
	_check(String(by_id["baba_yaga"].get("perk", "")) == "yaga",
			"Баба-яга — три фазы метла/ступа/печь")
	_check(String(by_id["koshchei"].get("perk", "")) == "koshchei",
			"Кощей — смерть на конце иглы (вместо лича)")
	# --- биомы: нечисть доминирует, слуги остались; новые арены ---
	var biomes: Dictionary = dungeon["biomes"]
	var all_ids := by_id.keys()
	var weights_ok := true
	for bname: String in biomes:
		var b: Dictionary = biomes[bname]
		for eid: String in b.get("enemy_weights", {}).keys():
			if not all_ids.has(eid):
				weights_ok = false
	_check(weights_ok, "все веса биомов ссылаются на существующих врагов")
	var mf: Dictionary = biomes["mutant_forest"]["enemy_weights"]
	var nech := float(mf.get("leshy", 0.0)) + float(mf.get("volkolak", 0.0)) \
			+ float(mf.get("nochnitsa", 0.0)) + float(mf.get("kikimora", 0.0))
	var total := 0.0
	for w: float in mf.values():
		total += w
	_check(nech / maxf(1.0, total) >= 0.5, "в лесу нечисть большинства (%.0f/%.0f)" % [nech, total])
	_check(String(biomes["lich_tower"]["boss"]) == "koshchei",
			"Кощей — босс башни вместо лича")
	_check(String(biomes["midnight_crypt"]["boss"]) == "viy"
			and String(biomes["yaga_hut"]["boss"]) == "baba_yaga",
			"Полуночная крипта (Вий) и Избушка (Яга) — новые арены")
	_check(biomes["yaga_hut"]["enemy_weights"].has("black_hen"),
			"в избушке чёрные курицы — слуга Яги")
	var world: Dictionary = _read_json("res://data/world.json")
	var db := _find_dungeon_biomes(world)
	_check(db.has("midnight_crypt") and db.has("yaga_hut"),
			"новые биомы выходят на карту мира")
	# --- чистая математика перков (headless) ---
	var E: Script = load("res://scripts/enemy.gd")
	_check(is_equal_approx(float(E.night_mult(false, 0.0)), 1.0),
			"днём в чистом данже нечисть без усиления")
	_check(is_equal_approx(float(E.night_mult(true, 1.0)), 1.5),
			"ночь города + тьма данжа = ×1.5")
	_check(float(E.night_mult(true, 0.0)) > float(E.night_mult(false, 0.5)),
			"ночь города усиливает сильнее, чем тьма")
	_check(is_equal_approx(float(E.pack_mult(0)), 1.0)
			and is_equal_approx(float(E.pack_mult(4)), 1.6),
			"ночница: стая усиливает до капа ×1.6")
	_check(bool(E.gaze_hit(140.0, 150.0)) and not bool(E.gaze_hit(160.0, 150.0)),
			"взгляд Вия: радиус работает")
	_check(int(E.gaze_damage(10, 0.0, 150.0)) == 10
			and int(E.gaze_damage(10, 150.0, 150.0)) == 5,
			"взгляд Вия: ближе — больнее (спад к краю)")
	_check(int(E.yaga_phase(0.9)) == 0 and int(E.yaga_phase(0.5)) == 1
			and int(E.yaga_phase(0.2)) == 2,
			"Яга: фазы 0/1/2 по здоровью")
	_check(bool(E.koshchei_holds("koshchei", true))
			and not bool(E.koshchei_holds("koshchei", false))
			and not bool(E.koshchei_holds("rat", true)),
			"Кощей: бессмертен только пока цела игла")
	_check(int(E.sneak_damage("sneak", true, 1.5, 4)) == 6
			and int(E.sneak_damage("sneak", false, 1.5, 4)) == 4,
			"кикимора: удар из тени ×1.5 один раз")
	# --- тематический лут и локализация ---
	var loot: Dictionary = _read_json("res://data/loot.json")
	var loot_ids := {}
	for it: Dictionary in loot["items"]:
		loot_ids[String(it["id"])] = it
	var th := ["volkolak_fang", "viy_eye", "yaga_knot", "koshchei_needle",
			"vodyanoy_pearl", "upyr_fang"]
	var th_ok := true
	var loc_ok := true
	for id in th:
		if not loot_ids.has(id):
			th_ok = false
		else:
			if not loc.has(String(loot_ids[id]["loc"])):
				loc_ok = false
	_check(th_ok, "тематический лут нечисти в loot.json")
	for id in roster + bosses + ["black_hen", "death_needle"]:
		if not loc.has(String(by_id[id]["loc"])):
			loc_ok = false
	_check(loc_ok, "имена нечисти и лута локализованы")
	for b in ["midnight_crypt", "yaga_hut"]:
		_check(loc.has("biome." + b), "имя биома локализовано: " + b)
	# спрайты сгенерированы и читаются
	var sprites_ok := true
	for id in roster + bosses + ["black_hen", "death_needle"]:
		var path: String = "res://assets/sprites/creatures/" + id + ".png"
		if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
			sprites_ok = false
	_check(sprites_ok, "спрайты нечисти сгенерированы (make_creatures.gd)")
	print("[Нечисть v1.30] готово")


## Найти dungeon_biomes в дереве world.json.
func _find_dungeon_biomes(o: Variant) -> Array:
	if o is Dictionary:
		if o.has("dungeon_biomes") and (o["dungeon_biomes"] as Array).size() > 0 \
				and String((o["dungeon_biomes"] as Array)[0]) == "ruins":
			return o["dungeon_biomes"]
		for v: Variant in o.values():
			var r := _find_dungeon_biomes(v)
			if not r.is_empty():
				return r
	elif o is Array:
		for v: Variant in o:
			var r := _find_dungeon_biomes(v)
			if not r.is_empty():
				return r
	return []
