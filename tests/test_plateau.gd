extends "res://tests/test_base.gd"
## Многоуровневый рельеф города — этап «Многоуровневый рельеф» (v1.36,
## ответы №113–115): плато уровней 1/2, лестницы-проходы, отвес непроходим,
## A* ходит по уровням, стройка на плато разрешена (на лестнице — нет),
## оборонный бонус высоты, сейв/лоад высот.

const SEEDS := [11, 42, 1000, 77777, 424242]
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## Сим с ПЛАТО (в отличие от _make_sim, который глушит рельеф ради старых
## фиксированных координат): сид подобран так, что плато есть.
func _make_sim_relief(seed_value: int = 42) -> Object:
	var cfg: Variant = _read_json("res://data/city.json")
	var city_map = load("res://scripts/city_map.gd").new()
	var gen_cfg: Dictionary = (cfg as Dictionary).duplicate(true)
	gen_cfg["river"] = false
	gen_cfg["map_w"] = 80
	gen_cfg["map_h"] = 60
	city_map.generate(seed_value, gen_cfg)
	var sim = load("res://scripts/city_sim.gd").new()
	sim.setup(city_map, cfg, 6, "normal")
	sim._last_daily_day = 1
	sim._next_raid_at = 999999999.0
	return sim


func _test_plateau_gen() -> void:
	print("[Многоуровневый рельеф: генерация и пути]")
	var cfg: Dictionary = _read_json("res://data/city.json")

	# детерминизм: тот же сид — те же высоты и лестницы
	var a = load("res://scripts/city_map.gd").new()
	a.generate(424242, cfg)
	var b = load("res://scripts/city_map.gd").new()
	b.generate(424242, cfg)
	var same: bool = a.height.keys().size() == b.height.keys().size() \
			and a.stairs.keys().size() == b.stairs.keys().size()
	for t: Vector2i in a.height:
		if a.height_at(t) != b.height_at(t):
			same = false
	for t2: Vector2i in a.stairs:
		if not b.stairs.has(t2):
			same = false
	_check(same, "генерация плато детерминирована по сиду")

	var any_terrace := false
	for seed_value in SEEDS:
		var map = load("res://scripts/city_map.gd").new()
		map.generate(seed_value, cfg)
		var label := "сид %d" % seed_value

		# плато есть; уровни только 1 и 2; терраса 2 встречается
		var n1 := 0
		var n2 := 0
		var bad_lvl := false
		for t: Vector2i in map.height:
			match map.height_at(t):
				1: n1 += 1
				2:
					n2 += 1
					any_terrace = true
				_: bad_lvl = true
		_check(n1 >= 12 and not bad_lvl,
				label + ": есть плато уровня 1 (%d тайлов), лишних уровней нет" % n1)

		# плато не залезает на воду/скалы/руду (только трава/деревья)
		var clean := true
		for t: Vector2i in map.height:
			var g: int = map.grid[t.y][t.x]
			if g != map.TILE_GRASS and g != map.TILE_TREE:
				clean = false
		_check(clean, label + ": плато лежит только на траве и лесе")

		# лестницы: хотя бы одна на плато; каждая — уровень>0 с соседом
		# уровнем ниже (проходимым), ведёт наверх
		var stairs_ok: bool = map.stairs.size() > 0
		for s: Vector2i in map.stairs:
			var lvl: int = map.height_at(s)
			var lower := false
			for d in DIRS:
				var n: Vector2i = s + d
				if map.in_bounds(n) and map.height_at(n) == lvl - 1 \
						and map.is_nature_walkable(n):
					lower = true
			if lvl <= 0 or not lower:
				stairs_ok = false
		_check(stairs_ok, label + ": лестницы на кромке соединяют уровни (%d шт)"
				% map.stairs.keys().size())

		# связность по уровням: каждый тайл плато достижим от старта
		# (путь обязан пройти через лестницу) — отвес не режет карту
		var all_reach := true
		var through_stair := true
		for t: Vector2i in map.height:
			var path: Array = map.astar.get_id_path(map.spawn_tile, t)
			if path.is_empty():
				all_reach = false
				continue
			var has_stair := false
			for step in path:
				if map.stairs.has(step):
					has_stair = true
			if not has_stair and map.height_at(t) > 0:
				through_stair = false
		_check(all_reach, label + ": все тайлы плато достижимы от старта")
		_check(through_stair, label + ": путь наверх проходит только через лестницу")

		# прямого шага через отвес нет: сосед равнина↔плато без лестницы —
		# путь между ними длиннее одного шага
		var no_climb := true
		var checked := 0
		for t: Vector2i in map.height:
			if checked >= 8:
				break
			for d in DIRS:
				var n: Vector2i = t + d
				if not map.in_bounds(n):
					continue
				var la: int = map.height_at(t)
				var lb: int = map.height_at(n)
				if la == lb or map.stairs.has(t) or map.stairs.has(n):
					continue
				if not map.is_nature_walkable(t) or not map.is_nature_walkable(n):
					continue
				var path: Array = map.astar.get_id_path(n, t)
				if path.size() <= 2:
					no_climb = false   # шагнули через отвес напрямую
				checked += 1
				if checked >= 8:
					break
		_check(no_climb and checked > 0,
				label + ": через отвес напрямую не пройти (%d кромок)" % checked)

		# сетка мутантов уважает уровни так же (лестница — общий проход)
		var raider_ok := true
		for t: Vector2i in map.stairs:
			if map.astar_raider.get_id_path(map.spawn_tile, t).is_empty():
				raider_ok = false
			break
		_check(raider_ok, label + ": мутанты тоже ходят по лестницам (№113)")
	_check(any_terrace, "терраса уровня 2 встречается (схема Hills, 2–3 уровня)")


func _test_plateau_combat() -> void:
	print("[Многоуровневый рельеф: стройка, бой, сейв]")
	var sim = _make_sim_relief(42)
	var map = sim.map
	_check(map.height.size() > 0, "карта сима с плато (сид 42)")

	# лестница+её нижний сосед и плато-тайл для проверок
	var stair := Vector2i(-1, -1)
	var ground := Vector2i(-1, -1)
	var flat := Vector2i(-1, -1)
	for s: Vector2i in map.stairs:
		for d in DIRS:
			var n: Vector2i = s + d
			if map.in_bounds(n) and map.height_at(n) == map.height_at(s) - 1:
				stair = s
				ground = n
				break
		if stair.x >= 0:
			break
	for t: Vector2i in map.height:
		if not map.stairs.has(t) and sim.is_buildable_tile(t):
			flat = t
			break
	_check(stair.x >= 0 and flat.x >= 0, "найдены лестница и свободный тайл плато")

	# стройка: на плато МОЖНО (№115), на лестнице НЕЛЬЗЯ (единственный проход)
	_check(sim.is_buildable_tile(flat), "стройка на плато разрешена (№115)")
	_check(not sim.is_buildable_tile(stair), "стройка на лестнице запрещена")

	# оборонный бонус высоты (№113): защитник сверху — атака снизу слабее,
	# атакующий сверху бьёт больнее, равные уровни — как есть
	var cfg_bal: Dictionary = _read_json("res://data/balance.json")
	var def_b := float(cfg_bal["plateau"]["def_bonus"])
	var atk_b := float(cfg_bal["plateau"]["atk_bonus"])
	_check(is_equal_approx(map.plateau_def_mult(ground, stair), 1.0 - def_b),
			"удар снизу по защитнику на плато ослаблен (−%d%%)" % int(round(def_b * 100)))
	_check(is_equal_approx(map.plateau_def_mult(stair, ground), 1.0 + atk_b),
			"удар с плато вниз усилен (+%d%%)" % int(round(atk_b * 100)))
	_check(map.plateau_def_mult(ground, ground) == 1.0,
			"равные уровни — множителя нет")

	# бой в городе: герой на плато бьёт мутанта внизу сильнее обычного
	# (здоровый «громила» переживёт удар и сохранит hp для сверки)
	var raider := _spawn_one_raider(sim, "brute", ground)
	var hp0: int = int(raider["hp"])
	var facing: Vector2 = map.tile_center_px(ground) - map.tile_center_px(stair)
	var dmg_flat: int = hp0 - _raider_hp_after(sim, raider, stair, facing, 6)
	_check(dmg_flat == int(round(6.0 * (1.0 + atk_b))),
			"hero_slash с плато вниз бьёт с бонусом высоты (%d урона)" % dmg_flat)

	# сейв: высоты и лестницы переживают сохранение (каркас сида 0 перекрыт)
	var SG: Script = load("res://scripts/save_game.gd")
	var block: Dictionary = SG._city_block(sim)
	_check((block["map"]["height"] as Array).size() == map.height.size(),
			"высоты пишутся в сейв (%d записей)" % map.height.size())
	_check((block["map"]["stairs"] as Array).size() == map.stairs.size(),
			"лестницы пишутся в сейв (%d записей)" % map.stairs.size())
	var map2 = load("res://scripts/city_map.gd").new()
	map2.generate(0, sim.cfg)
	SG._apply_city_map(map2, block["map"], sim.cfg)
	var restored: bool = map2.height.size() == map.height.size()
	for t: Vector2i in map.height:
		if map2.height_at(t) != map.height_at(t):
			restored = false
	_check(restored and map2.stairs.size() == map.stairs.size(),
			"карта из сейва восстанавливает высоты и лестницы (пути живы)")
	var path_after: Array = map2.astar.get_id_path(map2.spawn_tile, stair)
	_check(not path_after.is_empty(), "после загрузки путь на плато работает")


## Урон по мутанту после hero_slash (возвращает его hp ПОСЛЕ удара).
func _raider_hp_after(sim, raider: Dictionary, from_tile: Vector2i,
		facing: Vector2, dmg: int) -> int:
	sim.hero_alive = true
	var n: int = sim.hero_slash(sim.map.tile_center_px(from_tile), facing,
			float(sim.map.ts) * 2.0, 90.0, dmg)
	return int(raider.get("hp", -1)) if n > 0 else -1
