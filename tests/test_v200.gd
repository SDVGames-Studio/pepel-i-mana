extends "res://tests/test_base.gd"
## v2.0 «Проводка задела» (релиз 2.4.0): лут-иконки -> предметы,
## деревья пакета B в пулы, текстурные пни/брёвна, варианты мельницы,
## кадры фауны B. Биомы НЕ входят (приказ заказчика).

const AssetsScript := preload("res://scripts/assets.gd")


func _test_loot_icons() -> void:
	print("[v2.0: лут-иконки]")
	_check(AssetsScript.item_tex("rusty_blade") != null, "ржавый клинок — своя иконка")
	_check(AssetsScript.item_tex("dragon_blade") != null, "драконий клинок — своя иконка")
	_check(AssetsScript.item_tex("potion_heal") != null, "зелье лечения — своя иконка")
	_check(AssetsScript.item_tex("crystal_amulet") != null, "кристалл-амулет — своя иконка")
	_check(AssetsScript.item_tex("boat") == null, "лодка не в пакете лута — Kenney остаётся")
	_check(AssetsScript.item_tex("horse") == null, "конь не в пакете — Kenney остаётся")
	_check(AssetsScript.item_tex("неизвестный_предмет") == null, "нет mapping — нет иконки")


func _test_trees_b() -> void:
	print("[v2.0: деревья пакета B]")
	var VB = load("res://scripts/city_view_base.gd")
	var pool: Array = VB.WAVE24_TREES
	_check(pool.size() == 16, "пул деревьев B — 16 стволов")
	var ok := true
	for ref in pool:
		if AssetsScript.sprite(String(ref)) == null:
			ok = false
	_check(ok, "все 16 деревьев B на месте (env/tree3_*)")
	# пни и брёвна B (семантические имена из кода отрисовки)
	var VN = load("res://scripts/city_view_nature.gd")
	var stump3: Array = VN.STUMP3_REFS
	var log3: Array = VN.LOG3_REFS
	_check(stump3.size() == 8, "пул пней B — 8 вариантов")
	_check(log3.size() == 8, "пул брёвен B — 8 вариантов")
	var ok2 := true
	for ref2 in stump3 + log3:
		if AssetsScript.sprite(String(ref2)) == null:
			ok2 = false
	_check(ok2, "все пни/брёвна B на месте (env/stump3_*, log3_*)")


func _test_fauna_b() -> void:
	print("[v2.0: кадры фауны B]")
	var f: Dictionary = _read_json("res://data/fauna.json")
	var counts := {}
	for s in (f["species"] as Array):
		counts[String(s["id"])] = ((s.get("art", {}) as Dictionary).get("frames", []) as Array).size()
	_check(int(counts.get("wolf", 0)) == 12, "волк: 6 старых + 6 кадров B")
	_check(int(counts.get("fox", 0)) == 12, "лиса: 6 + 6 B")
	_check(int(counts.get("hare", 0)) == 12, "заяц: 6 + 6 B")
	_check(int(counts.get("bird", 0)) == 12, "ворон: 6 + 6 B")
	_check(int(counts.get("fish", 0)) == 10, "рыба: 4 + 6 B")
	_check(int(counts.get("toad", 0)) == 10, "жаба: 4 + 6 B")
	var ok := true
	for s2 in (f["species"] as Array):
		for ref in ((s2.get("art", {}) as Dictionary).get("frames", []) as Array):
			if String(ref).begins_with("e:an_") and "_b_" in String(ref):
				if AssetsScript.sprite(String(ref)) == null:
					ok = false
	_check(ok, "все кадры B существуют в env/")


func _test_mill_variants() -> void:
	print("[v2.0: мельница A/B/C]")
	var CV = load("res://scripts/city_view.gd")
	var refs: Array = CV.MILL_REFS
	_check(refs.size() == 3, "три варианта мельницы")
	var ok := true
	for ref in refs:
		if AssetsScript.sprite(String(ref)) == null:
			ok = false
	_check(ok, "мельница A/B/C — все спрайты на месте")


func _test_items_integrity() -> void:
	print("[v2.0: целостность предметов]")
	var items: Dictionary = _read_json("res://data/items.json")
	var mapped := 0
	for it in (items["items"] as Array):
		if AssetsScript.item_tex(String(it["id"])) != null:
			mapped += 1
	_check(mapped == 32, "ровно 32 предмета получили иконки (получили %d)" % mapped)
