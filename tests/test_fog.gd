# Туман войны данжа + материалы биомов (v1.33): LOS, конфиг цветов.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_fog() -> void:
	print("[Туман войны v1.33: LOS, материалы биомов]")
	var DS: Script = load("res://scripts/dungeon.gd")
	var DG: Script = load("res://scripts/dungeon_gen.gd")
	var dungeon: Dictionary = _read_json("res://data/dungeon.json")
	_check(DS != null and DG != null and not dungeon.is_empty(),
			"скрипты и конфиг читаются")
	if DS == null or DG == null or dungeon.is_empty():
		return
	var W: int = DG.TILE_WALL
	var F: int = DG.TILE_FLOOR
	# сетка 9×9: полы, стена-перегородка по x=4 (кроме прохода y=7)
	var grid: Array = []
	for y in 9:
		var row: Array = []
		row.resize(9)
		row.fill(F)
		grid.append(row)
	for y in 9:
		grid[y][4] = W
	grid[7][4] = F   # дверной проём
	# 1) прямой коридор: видно
	_check(DS.los_clear_grid(grid, Vector2i(1, 1), Vector2i(3, 1), W),
			"LOS: вдоль коридора видно")
	# 2) за глухой стеной: не видно
	_check(not DS.los_clear_grid(grid, Vector2i(3, 1), Vector2i(5, 1), W),
			"LOS: за стеной не видно")
	# 3) через дверной проём по прямой: видно
	_check(DS.los_clear_grid(grid, Vector2i(3, 7), Vector2i(5, 7), W),
			"LOS: через проём видно")
	# 4) за стеной по диагонали (мимо проёма): не видно
	_check(not DS.los_clear_grid(grid, Vector2i(3, 5), Vector2i(5, 6), W),
			"LOS: диагональ в стену не проходит")
	# 5) соседний тайл: всегда видно (шаг <= 1)
	_check(DS.los_clear_grid(grid, Vector2i(5, 2), Vector2i(6, 2), W),
			"LOS: соседний тайл виден")
	# 6) материалы: полы и стены биомов НЕ «чёрные» (заказчик v1.33:
	#    камень/кирпич/земля/кристалл/огонь) — яркость пола > 0.35
	var floors_ok := true
	var walls_ok := true
	for bid in dungeon["biomes"]:
		var b: Dictionary = dungeon["biomes"][bid]
		if Color(String(b["floor_color"])).get_luminance() <= 0.35:
			floors_ok = false
		if Color(String(b["wall_color"])).get_luminance() <= 0.25:
			walls_ok = false
	_check(floors_ok, "полы всех биомов — материал, не чёрное (lum > 0.35)")
	_check(walls_ok, "стены всех биомов читаются (lum > 0.25)")
	# 7) огненные биомы с угольками
	_check(String(dungeon["biomes"]["demon_lair"].get("ember_color", "")).length() > 0
			and String(dungeon["biomes"]["dragon_lair"].get("ember_color", "")).length() > 0,
			"огненные биомы тлеют угольками (ember_color)")
	# 8) скрипт тумана войны на месте и подключён в сцену данжа
	var fog_src := FileAccess.file_exists("res://scripts/dungeon_fog.gd")
	var dsrc := FileAccess.open("res://scripts/dungeon.gd", FileAccess.READ)
	var wired: bool = dsrc != null and dsrc.get_as_text().find("dungeon_fog.gd") >= 0
	_check(fog_src and wired, "слой тумана войны существует и подключён")
	# 9) туман различает память и живой обзор
	var fog_f := FileAccess.open("res://scripts/dungeon_fog.gd", FileAccess.READ)
	var fog_has_memory: bool = fog_f != null \
			and fog_f.get_as_text().find("MEMORY_ALPHA") >= 0
	var dgn_f := FileAccess.open("res://scripts/dungeon.gd", FileAccess.READ)
	var dgn_has_vis: bool = dgn_f != null \
			and dgn_f.get_as_text().find("_visible_now") >= 0
	_check(fog_has_memory and dgn_has_vis,
			"живой обзор отделён от памяти (visible_now + альфа памяти)")
