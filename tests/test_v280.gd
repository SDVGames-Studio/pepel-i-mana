extends "res://tests/test_base.gd"
## v2.8 «Биомы мира» (релиз 2.8.0): суша биом-регионов карты мира рисуется
## канвасами манифеста (полотна заказчика); 6 новых регионов (степи/берёзовая
## роща/цветущий край/древний лес/мистический лес/проклятый лес) дописаны
## В КОНЕЦ каталога — буквы сейва a–d не сдвигались.

const AssetsScript := preload("res://scripts/assets.gd")


func _test_catalog() -> void:
	print("[v2.8: каталог регионов]")
	var w: Dictionary = _read_json("res://data/world.json")
	var lst: Array = (w["regions"] as Dictionary)["list"]
	var ids := []
	for e in lst:
		ids.append(String((e as Dictionary)["id"]))
	for base_id in ["snow", "volcanic", "desert", "dead"]:
		_check(ids.has(base_id), "старый регион %s на месте (сейв-совместимость)" % base_id)
	for new_id in ["steppe", "birch", "bloom", "ancient", "mystic", "cursed"]:
		_check(ids.has(new_id), "новый регион %s в каталоге" % new_id)
	var sb = load("res://scripts/save_game_base.gd")
	var rid: Dictionary = sb.REGION_IDS
	for pair in [["a", "snow"], ["b", "volcanic"], ["c", "desert"], ["d", "dead"]]:
		_check(String(rid.get(pair[0], "")) == String(pair[1]),
				"буква сейва %s = %s не сдвинулась" % [pair[0], pair[1]])
	_check(int(rid.size()) == 10, "REGIONS сейва — 10 (4 старых + 6 новых)")
	var mf: Dictionary = AssetsScript.biome_manifest()
	var ok := true
	for e2 in lst:
		var bt := String((e2 as Dictionary).get("biome", ""))
		if bt == "":
			ok = false
		elif not (mf.has(bt) and String((mf[bt] as Dictionary).get("canvas", "")) != ""):
			ok = false
	_check(ok, "все %d регионов несут биом манифеста с канвасом" % int(lst.size()))


func _test_world_gen() -> void:
	print("[v2.8: генерация мира с регионами]")
	var WM = load("res://scripts/world_map.gd")
	var cfg: Dictionary = _read_json("res://data/world.json")
	cfg["map_w"] = 64
	cfg["map_h"] = 48
	var m = WM.new()
	m.generate(424242, cfg)
	var seen := {}
	for y in m.h:
		for x in m.w:
			var r: String = m.region_at(Vector2i(x, y))
			if r != "":
				seen[r] = true
	_check(int(seen.size()) >= 6, "биом-регионов на карте %d (>= 6)" % int(seen.size()))
	var known := ["snow", "volcanic", "desert", "dead", "steppe", "birch",
			"bloom", "ancient", "mystic", "cursed"]
	var ok := true
	for r2 in (seen.keys() as Array):
		if not known.has(String(r2)):
			ok = false
	_check(ok, "все регионы карты из каталога, посторонних нет")
	var m2 = WM.new()
	m2.generate(424242, cfg)
	var seen2 := {}
	for y2 in m2.h:
		for x2 in m2.w:
			var r3: String = m2.region_at(Vector2i(x2, y2))
			if r3 != "":
				seen2[r3] = true
	var same := true
	if int(seen2.size()) != int(seen.size()):
		same = false
	else:
		for k in (seen.keys() as Array):
			if not seen2.has(String(k)):
				same = false
	_check(same, "тот же сид — те же регионы")


func _test_bake() -> void:
	print("[v2.8: запека мира с полотнами]")
	var WM = load("res://scripts/world_map.gd")
	var cfg: Dictionary = _read_json("res://data/world.json")
	cfg["map_w"] = 48
	cfg["map_h"] = 36
	var m = WM.new()
	m.generate(777, cfg)
	var WV = load("res://scripts/world_view.gd")
	var v = WV.new()
	v.map = m
	v._bake_terrain()
	_check(m._terrain_bake != null, "запека мира с полотнами собирается")
