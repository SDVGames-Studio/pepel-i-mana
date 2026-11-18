# Тест композитора биомов v2 (v1.78.5): нарезка клеток из исходных листов
# заказчика, сохранение патчей в user://, загрузка их через Assets.tex.
extends "res://tests/test_base.gd"

const COMPOSER := "res://scripts/biome_composer.gd"

# Тесты роняют раннер на машинах без исходных листов заказчика — тогда
# проверяем только программную часть (рецепт/печать на синтетике).
func _summer_path() -> String:
	var comp = load(COMPOSER).new()
	return String(comp.SHEET_BASE) + "/" + "Биомы лето" + "/" \
			+ "Пиксельный атлас лесных и водных тайловета.png"


func _make_comp() -> Object:
	# фейковый автозагрузчик Loc (в headless-раннере autoload не живут)
	if tree.root.get_node_or_null("Loc") == null:
		var loc: Node = load("res://scripts/loc.gd").new()
		loc.name = "Loc"
		tree.root.add_child(loc)
	# UI композитора в headless не строим (root раннера до старта цикла)
	# — нужные для логики поля подставляем вручную
	var comp: Object = load(COMPOSER).new()
	comp._load_sources()
	comp._name_edit = LineEdit.new()
	comp._status = Label.new()
	return comp


func _test_composer_sheets() -> void:
	var comp: Object = _make_comp()
	_check(comp._sources.size() == 15, "композитор: 15 листов (лето + 14 биомов)")
	var sp := String(comp._sources[0]["sheet"])
	_check(sp.contains("Биомы лето"), "первый лист — лето")
	var an: Dictionary = comp._analyze_sheet(sp)
	if not bool(an["found"]):
		print("  skip: исходные листы заказчика недоступны на этой машине")
		comp.queue_free()
		return
	_check(int((an["cells"] as Array).size()) >= 150,
			"лето: в библиотеке ВСЕ клетки листа (%d)" % int((an["cells"] as Array).size()))
	_check(int((an["cells"] as Array).size()) <= 400,
			"лето: клеток разумно много (без мусора пустых)")
	_check(not (an["water"] as Dictionary).get("cells", []).is_empty(),
			"лето: вода листа найдена автоматически")
	var water_cells: Array = an["water"]["cells"]
	var first: Vector2i = water_cells[0]
	var im: Image = comp._cell_img(sp, first.x, first.y)
	_check(im != null and im.get_size() == Vector2i(32, 32),
			"клетка листа нарезается 32×32")
	var tex: ImageTexture = comp._cell_tex(sp, first.x, first.y)
	_check(tex != null, "клетка листа превращается в текстуру кнопки")
	comp.queue_free()


func _test_composer_save() -> void:
	var comp: Object = _make_comp()
	var sp := String(comp._sources[0]["sheet"])
	var an: Dictionary = comp._analyze_sheet(sp)
	var tag := "СмоукЛето"
	var dir := "user://biomes_composed/%s" % tag
	if not bool(an["found"]):
		print("  skip: сохранение биома проверяется только при наличии листов")
		return
	# сборка: 6 клеток земли + авто-вода
	var cells: Array = an["cells"]
	comp._sel_grass = []
	for i in range(6):
		comp._sel_grass.append({"sheet": sp, "cx": int(cells[i]["cx"]),
				"cy": int(cells[i]["cy"])})
	comp._sel_water = an["water"]
	comp._sel_trees = ["e:tree2_summer_oak"]
	comp._season = "summer"
	comp._name_edit.text = tag
	comp._rebuild_preview()
	_check(comp._preview_tex != null, "превью собирается из клеток листа")
	comp._on_save()
	_check(FileAccess.file_exists(dir + "/grass_1.png"), "grass_1.png напечатан в user://")
	_check(FileAccess.file_exists(dir + "/water.png"), "water.png (полоса 6×3) напечатан")
	_check(FileAccess.file_exists(dir + "/biome.json"), "biome.json записан")
	var bf := FileAccess.open(dir + "/biome.json", FileAccess.READ)
	var data: Variant = JSON.parse_string(bf.get_as_text())
	bf.close()   # Windows: открытый read-хэндл блокирует удаление ниже
	_check(data is Dictionary and bool(data["composed"]),
			"biome.json помечен composed")
	_check((data["grass"] as Array).size() >= 4
			and String(data["grass"][0]).begins_with("user://"),
			"пути травы в biome.json — user://")
	# город-ветка: рецепт по сохранённым патчам
	var mf: Dictionary = Assets.biome_manifest()
	_check(mf.has(tag), "биом появился в манифесте сразу после сохранения")
	var uni := Assets.uniform_ground((mf[tag] as Dictionary).get("grass", []))
	var texs: Array = uni[0]
	_check(texs.size() >= 4 and texs[0] != null,
			"город: трава user:// загружается (текстуры %d)" % texs.size())
	if texs.size() > 0 and texs[0] != null:
		var gimg: Image = (texs[0] as Texture2D).get_image()
		var mid: Color = gimg.get_pixel(16, 16)
		_check(gimg.get_size() == Vector2i(32, 32) and mid.a > 0.99,
				"трава user:// — 32×32, кромка дизерится к общему тону")
	var wt: Texture2D = Assets.tex(String(mf[tag].get("water", "")))
	_check(wt != null and wt.get_size() == Vector2(192, 96),
			"вода user:// — полоса 192×96 (кадры города)")
	# стенд-ветка: подложки для composed не нужны — recipe-тайлы непрозрачны
	# уборка за собой (манифест перечитывается)
	var d2 := DirAccess.open(dir)
	for f in d2.get_files():
		d2.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	Assets.reload_biome_manifest()
	_check(not Assets.biome_manifest().has(tag), "тестовый биом убран из манифеста")
	comp.queue_free()
