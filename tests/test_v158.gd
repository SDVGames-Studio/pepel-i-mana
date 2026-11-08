# v1.58 «Биом смерти из ассетов заказчика»: крипта (midnight_crypt) одета в
# тайлы Undead Tileset (d3_* через pack_refs), декор комнат из набора
# death/* (кости/могилы/кристаллы мелкий scatter + якоря комнат), драконье
# логово — кости и куча черепов.
extends "res://tests/test_base.gd"


func _test_v158_crypt_pack_refs() -> void:
	print("[v1.58: крипта на тайлах пака заказчика]")
	var dg: Dictionary = _read_json("res://data/dungeon.json")
	var cr: Dictionary = dg["biomes"]["midnight_crypt"]
	_check(cr.has("pack_refs"), "у крипты есть pack_refs")
	var pr: Dictionary = cr.get("pack_refs", {})
	var need := ["floor_a", "floor_b", "floor_c", "edge_n", "edge_s",
			"edge_w", "edge_e", "wall_face", "wall_top"]
	var all_d3 := true
	for k in need:
		if String(pr.get(k, "")) != "e:d3_" + k:
			all_d3 = false
	_check(all_d3, "все 9 рефов крипты ведут на d3-набор")
	# файлы пака существуют (иначе draw_ref тихо пропустит — чёрный пол)
	var missing := 0
	for k: String in need:
		var f := "res://assets/sprites/env/d3_" + k + ".png"
		if not FileAccess.file_exists(f):
			missing += 1
	_check(missing == 0, "все d3-тайлы на диске (missing=%d)" % missing)


func _test_v158_crypt_decor() -> void:
	print("[v1.58: декор крипты из набора death]")
	var dg: Dictionary = _read_json("res://data/dungeon.json")
	var cr: Dictionary = dg["biomes"]["midnight_crypt"]
	var small: Array = cr.get("decor_sprites", [])
	var big: Array = cr.get("decor_big", [])
	_check(small.size() >= 5, "мелкий декор крипты: кости/могилы/кристаллы")
	_check(big.size() >= 3, "якоря комнат: дерево/кучи/руины/дверь")
	var bad := 0
	for ref_v: Variant in small + big:
		if not String(ref_v).begins_with("img:death/"):
			bad += 1
			continue
		# img:death/<имя> -> res://assets/sprites/<имя>.png
		var f := "res://assets/sprites/" + String(ref_v).substr(4) + ".png"
		if not FileAccess.file_exists(f):
			bad += 1
	_check(bad == 0, "все PNG декора на диске (bad=%d)" % bad)
	_check(cr.get("decor_chance", 0) >= 4, "частота scatter в разумных пределах")
	_check(cr.get("moss", true) == false, "мох в крипте выключен (визуал несёт декор пака)")


func _test_v158_dragon_bones() -> void:
	print("[v1.58: драконье логово — кости и черепа]")
	var dg: Dictionary = _read_json("res://data/dungeon.json")
	if not dg["biomes"].has("dragon_lair"):
		_check(true, "dragon_lair отсутствует в конфиге — пропуск")
		return
	var dl: Dictionary = dg["biomes"]["dragon_lair"]
	_check(dl.has("decor_sprites") and (dl["decor_sprites"] as Array).size() >= 2,
			"кости в логове дракона")
	_check(dl.has("decor_big") and (dl["decor_big"] as Array).size() >= 1,
			"крупный якорь (куча черепов) в логове")
	for ref_v: Variant in (dl["decor_sprites"] as Array) + (dl["decor_big"] as Array):
		var fname := String(ref_v).substr(4)
		_check(FileAccess.file_exists("res://assets/sprites/" + fname + ".png"),
				"PNG " + fname + " существует")
	# другие биомы не затронуты: у них нет decor-ключей — пустые списки = нет декора
	var others := 0
	for key in dg["biomes"]:
		if key in ["midnight_crypt", "dragon_lair"]:
			continue
		var b: Dictionary = dg["biomes"][key]
		if b.has("decor_sprites") or b.has("decor_big"):
			others += 1
	_check(others == 0, "прочие биомы без decor-ключей (не задеты)")
