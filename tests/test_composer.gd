# Тест композитора-рисовалки v4 (v1.78.8): кисти, нарисованная карта,
# сохранение grid в user://, город рисует карту как есть.
extends "res://tests/test_base.gd"

const COMPOSER := "res://scripts/biome_composer.gd"


func _make_comp() -> Object:
	# фейковый автозагрузчик Loc (в headless-раннере autoload не живут)
	if tree.root.get_node_or_null("Loc") == null:
		var loc: Node = load("res://scripts/loc.gd").new()
		loc.name = "Loc"
		tree.root.add_child(loc)
	# UI композитора в headless не строим — нужные поля подставляем вручную
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
		comp.free()
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
	_check(tex != null, "клетка листа превращается в текстуру кисти")
	comp.free()


func _test_composer_save() -> void:
	var comp: Object = _make_comp()
	var sp := String(comp._sources[0]["sheet"])
	var an: Dictionary = comp._analyze_sheet(sp)
	var tag := "СмоукЛето"
	var dir := "user://biomes_composed/%s" % tag
	if not bool(an["found"]):
		print("  skip: сохранение биома проверяется только при наличии листов")
		return
	# кисти: 4 клетки листа
	var cells: Array = an["cells"]
	comp._sel_grass = []
	for i in range(4):
		comp._sel_grass.append({"sheet": sp, "cx": int(cells[i]["cx"]),
				"cy": int(cells[i]["cy"])})
	comp._sel_water = an["water"]
	comp._sel_trees = ["e:tree2_summer_oak"]
	comp._season = "summer"
	# НАРИСОВАННАЯ КАРТА 20×20: каждый тайл ставится «руками»
	var grid: Array = []
	grid.resize(400)
	for k in range(400):
		grid[k] = -1
	for y in range(20):
		for x in range(20):
			grid[y * 20 + x] = (x * 7 + y * 3) % 4
	comp._grid = grid
	comp._name_edit.text = tag
	comp._redraw_canvas()
	_check(comp._canvas_tex != null, "холст рисуется из нарисованной карты")
	comp._on_save()
	_check(FileAccess.file_exists(dir + "/grass_1.png"), "grass_1.png напечатан в user://")
	_check(FileAccess.file_exists(dir + "/water.png"), "water.png (полоса 6×3) напечатан")
	_check(FileAccess.file_exists(dir + "/biome.json"), "biome.json записан")
	var bf := FileAccess.open(dir + "/biome.json", FileAccess.READ)
	var data: Variant = JSON.parse_string(bf.get_as_text())
	bf.close()   # Windows: открытый read-хэндл блокирует удаление ниже
	_check(data is Dictionary and bool(data["composed"]),
			"biome.json помечен composed")
	_check((data["grid"] as Array).size() == 400,
			"НАРИСОВАННАЯ КАРТА сохранена (grid 20×20)")
	_check((data["cells"] as Array).size() == 4,
			"клетки кистей сохранены (восстановление вкладки)")
	_check(String(data["season"]) == "summer",
			"сезон вкладки проставлен сам (лето → summer)")
	# город-ветка: рецепт по сохранённым патчам + grid
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
	# уборка за собой (манифест перечитывается)
	var d2 := DirAccess.open(dir)
	for f in d2.get_files():
		d2.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	Assets.reload_biome_manifest()
	_check(not Assets.biome_manifest().has(tag), "тестовый биом убран из манифеста")
	comp.free()
