extends "res://tests/test_base.gd"
## v3.0.0 «Масштаб и стройка» (приказ заказчика): здания НЕ строятся на
## деревьях и на клетках зон (поля/пастбища неприкосновенны), у фермы
## старосты — максимум свободной земли под грядки, жители 34px, герой 40px,
## полотно земли мельче (÷6), площадь зданий 3×3 (стены/ворота/шатёр/
## мост/башня — прежние).

const HERO := preload("res://scripts/hero.gd")
const AssetsScript := preload("res://scripts/assets.gd")
const TERRAIN := preload("res://scripts/city_terrain_base.gd")


func _test_no_build_on_trees_and_zones() -> void:
	print("[v3.0: стройка — деревья и поля]")
	var g: Node = load("res://scripts/game.gd").new()
	g.test_mode = true
	g.new_city()
	var sim = g.city_sim
	var m = sim.map
	# дерево подальше от площади
	var tree := Vector2i(-1, -1)
	for y in m.h:
		for x in m.w:
			var t := Vector2i(x, y)
			if int(m.grid[y][x]) == m.TILE_TREE and t.distance_to(m.spawn_tile) > 8.0:
				tree = t
				break
		if tree.x >= 0:
			break
	_check(tree.x >= 0, "на карте есть лес вдали от площади")
	if tree.x >= 0:
		_check(sim.is_buildable_tile(tree) == false, "на дереве строить нельзя")
	# поле: строить нельзя, зоны не перекрываются
	var spot := Vector2i(-1, -1)
	for y in m.h:
		for x in m.w:
			var t := Vector2i(x, y)
			if t.distance_to(m.spawn_tile) > 8.0 and sim._zone_cell_ok(t):
				spot = t
				break
		if spot.x >= 0:
			break
	_check(spot.x >= 0, "есть чистая клетка вдали от площади")
	if spot.x >= 0:
		var added: int = sim.add_zone("field", [spot])
		_check(added == 1, "поле красится на чистой клетке")
		_check(sim.is_buildable_tile(spot) == false, "здание на поле строить нельзя")
		_check(sim._zone_cell_ok(spot) == false, "второе поле на занятую клетку не ляжет")
		_check(sim.add_zone("field", [spot]) == 0, "add_zone не дублирует клетку")
	g.free()


func _test_scales() -> void:
	print("[v3.0: масштабы и площадь]")
	_check(float(HERO.KNIGHT_TARGET_H) == 40.0, "герой 40px")
	_check(float(AssetsScript.VILLAGER_VISIBLE_H) == 34.0, "житель 34px")
	_check(int(TERRAIN.CANVAS_DENSITY) == 6, "полотно земли ÷6 (детали мельче фигур)")
	var g: Node = load("res://scripts/game.gd").new()
	g.test_mode = true
	g.new_city()
	var sim = g.city_sim
	_check(sim.bld_w_of_type("house") == 3, "дом — площадь 3×3")
	_check(sim.bld_w_of_type("farm") == 3, "ферма — площадь 3×3")
	_check(sim.bld_w_of_type("sawmill") == 3, "лесопилка — 3×3")
	_check(sim.bld_w_of_type("tavern") == 3, "таверна — 3×3")
	_check(sim.bld_w_of_type("wall") == 1, "стена — 1×1 (как была)")
	_check(sim.bld_w_of_type("tower") == 2, "башня — 2×2 (в линии стен)")
	# ферма: свободная земля считается
	var t0 := Vector2i(-1, -1)
	var m = sim.map
	for y in m.h:
		for x in m.w:
			var t := Vector2i(x, y)
			if t.distance_to(m.spawn_tile) > 9.0 and int(m.grid[y][x]) == m.TILE_GRASS:
				t0 = t
				break
		if t0.x >= 0:
			break
	_check(t0.x >= 0, "есть трава вдали от площади")
	if t0.x >= 0:
		_check(sim._free_farmland(t0, 3) >= 0, "счётчик свободной земли у фермы работает")
	g.free()
