extends "res://tests/test_base.gd"
## «Данжи v2» (v1.42.0, этап 4 «Мир v2»): споты генератора (жаровни/лужи/
## руны/порченые комнаты) валидны и детерминированы, ассеты пака на месте,
## рунный круг даёт награду и одноразов, конфиг v2 (цвета/числа) корректен.
## Рендер (_draw) в headless не вызывается (грабли автозагрузок) — чистая
## логика и данные.

const SEED := 4242


func _params() -> Dictionary:
	return _read_json("res://data/dungeon.json")


func _make_gen(seed_value: int = SEED):
	var gen = load("res://scripts/dungeon_gen.gd").new()
	return gen.generate(seed_value, _params())


func _test_dungeon2_assets() -> void:
	print("[Данжи v2: ассеты]")
	for p in ["res://assets/sprites/env/d2_floor_a.png",
			"res://assets/sprites/env/d2_floor_b.png",
			"res://assets/sprites/env/d2_floor_c.png",
			"res://assets/sprites/env/d2_floor_crack.png",
			"res://assets/sprites/env/d2_wall_face.png",
			"res://assets/sprites/env/d2_wall_top.png",
			"res://assets/sprites/env/d2_shadow.png",
			"res://assets/sprites/env/d2_crack_a.png",
			"res://assets/sprites/env/d2_crack_b.png",
			"res://assets/sprites/env/d2_crack_c.png",
			"res://assets/sprites/env/d2_wall_crack_a.png",
			"res://assets/sprites/env/d2_wall_crack_b.png",
			"res://assets/sprites/env/d2_water_1.png",
			"res://assets/sprites/env/d2_water_2.png",
			"res://assets/sprites/env/d2_water_3.png",
			"res://assets/sprites/env/d2_foam.png",
			"res://assets/sprites/env/d2_fire_1.png",
			"res://assets/sprites/env/d2_fire_2.png",
			"res://assets/sprites/env/d2_fire_3.png",
			"res://assets/sprites/env/d2_fire_s1.png",
			"res://assets/sprites/env/d2_fire_s2.png",
			"res://assets/sprites/env/d2_fire_s3.png",
			"res://assets/sprites/env/d2_brazier.png",
			"res://assets/sprites/env/d2_moss_a.png",
			"res://assets/sprites/env/d2_moss_b.png",
			"res://assets/sprites/env/d2_rune.png",
			"res://assets/sprites/props/d2_prop_crystal1.png",
			"res://assets/sprites/props/d2_prop_crystal2.png",
			"res://assets/sprites/props/d2_prop_crystal3.png",
			"res://assets/sprites/props/d2_prop_skull.png",
			"res://assets/sprites/props/d2_prop_bones.png",
			"res://assets/sprites/props/d2_prop_rubble1.png",
			"res://assets/sprites/props/d2_prop_rubble2.png",
			"res://assets/sprites/props/d2_prop_web.png"]:
		_check(ResourceLoader.exists(p), "ассет на месте: " + p)
	# огонь — полоса 32×96 (3 тайла высотой), не одиночный квадрат
	var fire: Image = load("res://assets/sprites/env/d2_fire_1.png").get_image()
	_check(fire.get_width() == 32 and fire.get_height() == 96,
			"огонь — полоса 32×96 (верх/тело/основание)")
	# рунный круг — больше тайла (46-48 px), с прозрачностью
	var rune: Image = load("res://assets/sprites/env/d2_rune.png").get_image()
	_check(rune.get_width() == 48, "рунный круг 48×48")


func _test_dungeon2_spots() -> void:
	print("[Данжи v2: споты генератора]")
	var gen = _make_gen()
	var p := _params()
	var v2: Dictionary = p.get("v2", {})
	_check(not v2.is_empty(), "конфиг v2 в dungeon.json есть")
	# жаровни: на полу, в границах, не в порченых комнатах
	var ok_braz: bool = not gen.brazier_spawns.is_empty()
	for t in gen.brazier_spawns:
		if not gen.is_floor(t):
			ok_braz = false
	_check(ok_braz, "жаровни стоят на полу (%d шт)" % gen.brazier_spawns.size())
	var braz_in_corrupt := false
	for t in gen.brazier_spawns:
		if _in_rooms(gen, t, gen.corrupt_rooms):
			braz_in_corrupt = true
	_check(not braz_in_corrupt, "в порченых комнатах огня нет")
	# порча: не задевает стартовую комнату
	_check(not gen.corrupt_rooms.is_empty() and not gen.corrupt_rooms.has(0),
			"порченые комнаты есть и это не стартовая (%d шт)" % gen.corrupt_rooms.size())
	# руны: на полу, не старт/выход, не в порче
	var ok_runes: bool = gen.rune_spawns.size() >= 1
	for t in gen.rune_spawns:
		if not gen.is_floor(t) or t == gen.start_tile or t == gen.exit_tile \
				or _in_rooms(gen, t, gen.corrupt_rooms):
			ok_runes = false
	_check(ok_runes, "руны на полу, не старт/выход/порча (%d шт)" % gen.rune_spawns.size())
	# лужи: кластеры от 2 тайлов, весь пол, не у старта
	var ok_pud: bool = not gen.puddle_zones.is_empty()
	for zone in gen.puddle_zones:
		if zone.size() < 2:
			ok_pud = false
		for t in zone:
			if not gen.is_floor(t) or t.distance_to(gen.start_tile) < 4:
				ok_pud = false
	_check(ok_pud, "лужи — кластеры пола вдали от старта (%d шт)" % gen.puddle_zones.size())
	# детерминизм: тот же сид = те же споты
	var gen2 = _make_gen()
	_check(str(gen2.brazier_spawns) == str(gen.brazier_spawns)
			and str(gen2.rune_spawns) == str(gen.rune_spawns)
			and str(gen2.puddle_zones) == str(gen.puddle_zones)
			and str(gen2.corrupt_rooms) == str(gen.corrupt_rooms),
			"споты детерминированы по сиду")


func _in_rooms(gen, tile: Vector2i, room_ids: Array) -> bool:
	for ri in room_ids:
		var r: Dictionary = gen.rooms[ri]
		if tile.x >= int(r["x"]) and tile.x < int(r["x"]) + int(r["w"]) \
				and tile.y >= int(r["y"]) and tile.y < int(r["y"]) + int(r["h"]):
			return true
	return false


func _test_dungeon2_rune() -> void:
	print("[Данжи v2: рунный круг]")
	var rune_script: Script = load("res://scripts/dungeon_rune.gd")
	var rune = rune_script.new()
	rune.setup(Color(0.6, 0.8, 1.0), 48.0)
	var hero := FakeHero.new()
	hero.mana = 2
	var rune_cfg: Dictionary = _params()["v2"]["rune"]
	var res: Dictionary = rune.activate(hero, rune_cfg)
	_check(int(res.get("mana", 0)) == hero.mana_cap(),
			"мана восстановлена до капа (%d)" % int(res.get("mana", 0)))
	_check(int(res.get("buff", 0)) == int(_params()["v2"]["rune"]["buff_damage"]),
			"боевой запал выдан (+%d)" % int(res.get("buff", 0)))
	_check(hero.bonus == int(_params()["v2"]["rune"]["buff_damage"]),
			"запал применён к герою")
	_check(rune.used, "круг погас после использования")
	_check(rune.activate(hero, _params()["v2"]["rune"]).is_empty(),
			"повторная активация ничего не даёт")
	_check(not rune.hero_in_range(Vector2(9999, 9999)), "дальняя точка вне радиуса")
	rune.used = false
	_check(rune.hero_in_range(rune.position + Vector2(40, 0)), "герой рядом — E доступен")


func _test_dungeon2_config() -> void:
	print("[Данжи v2: конфиг]")
	var v2: Dictionary = _params().get("v2", {})
	for key in ["torch_color", "cold_color", "corrupt_glow", "corrupt_color", "moss_color"]:
		var c := Color(String(v2.get(key, "")))
		_check(absf(c.r) >= 0.0 and (c.r > 0.0 or c.g > 0.0 or c.b > 0.0),
				"цвет %s парсится" % key)
	for key in ["braziers", "corrupt_rooms", "runes", "puddles"]:
		var box: Dictionary = v2.get(key, {})
		_check(int(box.get("min", 0)) >= 1 and int(box.get("max", 0)) >= int(box.get("min", 0)),
				"диапазон %s корректен" % key)
	_check(float(v2.get("torch_radius", 0)) >= 1.5 and float(v2.get("cold_radius", 0)) >= 1.5,
			"радиусы света >= 1.5 тайла")
	# флаги биомов: мох/кристаллы/гуманоиды булевы
	var biomes: Dictionary = _params()["biomes"]
	var moss_count := 0
	var humanoid_count := 0
	for bid in biomes:
		if bool(biomes[bid].get("moss", false)):
			moss_count += 1
		if bool(biomes[bid].get("humanoids", false)):
			humanoid_count += 1
	_check(moss_count >= 3, "мшистых биомов >= 3 (мох на камне): %d" % moss_count)
	_check(bool(biomes.get("bandit_camp", {}).get("humanoids", false)),
			"бандитский лагерь — гуманоиды (факелы горят)")
	_check(humanoid_count >= 1 and humanoid_count <= 3,
			"гуманоидных биомов немного (факелы только живым): %d" % humanoid_count)
	# строки локализации
	for key in ["dungeon.hint_rune", "dungeon.rune_mana", "dungeon.rune_buff"]:
		var loc: Dictionary = _read_json("res://loc/ru.json")
		_check(loc.has(key) and String(loc[key]) != "", "строка %s есть" % key)


func _test_dungeon2_lights_filter() -> void:
	print("[Данжи v2: факелы по гуманоидам]")
	var gen = _make_gen()
	var v2: Dictionary = _params()["v2"]
	var biomes: Dictionary = _params()["biomes"]
	var lights_script: Script = load("res://scripts/dungeon_lights.gd")
	# нежить/зверь: факелов нет, лужи и порча — есть
	var dark = lights_script.new()
	dark.setup(gen, 32, v2, biomes["ruins"])
	_check(dark._braziers.is_empty(),
			"в биоме без гуманоидов факелы не горят (ruins: нежить)")
	_check(not dark._puddles.is_empty() or not dark._corrupt_lights.is_empty(),
			"лужи/порча в тёмном биоме остались")
	# бандиты: факелы горят
	var lit = lights_script.new()
	lit.setup(gen, 32, v2, biomes["bandit_camp"])
	_check(not lit._braziers.is_empty(),
			"в биоме с гуманоидами факелы горят (bandit_camp): %d шт" % lit._braziers.size())
	# тень: все источники бросают тень от стен
	for l in lit._braziers:
		_check((l["light"] as PointLight2D).shadow_enabled,
				"факел бросает тень (свет упирается в стены)")
		break


func _test_dungeon2_fog_and_glow() -> void:
	print("[Данжи v2: туман и светящиеся монстры]")
	# туман: «память» только для изученного ПОЛА; стены — глухие (v1.42.2)
	var gen = _make_gen()
	var fog = load("res://scripts/dungeon_fog.gd").new()
	fog.gen = gen
	fog.ts = 32
	var floor_t: Vector2i = gen.start_tile
	var wall_t: Vector2i = Vector2i(floor_t.x + 1, floor_t.y)
	while gen.is_floor(wall_t):
		wall_t = Vector2i(wall_t.x + 1, wall_t.y)
	fog.visited = {floor_t: true}
	fog.visible_now = {}
	_check(absf(fog._tile_base(floor_t) - 1.0) < 0.01,
			"изученный пол вне света — глухая тьма (память убрана, v1.42.3)")
	_check(absf(fog._tile_base(wall_t) - 1.0) < 0.01,
			"стена вне поля зрения — глухая тьма (сквозь тень не видно)")
	# светящиеся монстры: у цендера и виспа есть свет в конфиге
	var enemies: Array = _read_json("res://data/enemies.json")
	var lit := {}
	for e in enemies:
		if e.has("light"):
			lit[String(e["id"])] = true
	_check(lit.has("cinder") and lit.has("wisp"),
			"огненные/магические монстры (cinder, wisp) светятся в конфиге")
	# дальние источники гасятся (FPS): у слоя света есть радиус отключения
	var lights2 = load("res://scripts/dungeon_lights.gd").new()
	_check(lights2.cull_px >= 10.0 * 32.0,
			"слой света гасит дальние источники (cull_px >= 10 тайлов)")
	# узел врага получает PointLight2D со включёнными тенями
	var enemy = load("res://scripts/enemy.gd").new()
	for e in enemies:
		if String(e["id"]) == "cinder":
			enemy.setup(e)
			break
	enemy._ready()
	var found_light := false
	for c in enemy.get_children():
		if c is PointLight2D:
			found_light = (c as PointLight2D).shadow_enabled
			break
	_check(found_light, "спрайт огненного монстра подсвечен (тени вкл)")
	enemy.free()


class FakeHero:
	var mana := 10
	var bonus := 0

	func mana_cap() -> int:
		return 12

	func temp_damage_bonus(_sec: float, dmg: int) -> void:
		bonus = dmg
