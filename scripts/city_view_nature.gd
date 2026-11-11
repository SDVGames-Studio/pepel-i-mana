# Часть: отрисовка города — сортированный проход мира и статика-объекты
# (костёр, могилы, трупы, брёвна, кучи, звери, скот, странники, улей, аномалия).
# Один класс, поведение не меняется.
extends "res://scripts/city_view_base.gd"

func _draw_world_sorted() -> void:
	var ts := float(map.ts)
	# v1.50: позиция героя — деревья у него полупрозрачные
	_hero_px = city.hero.global_position if city != null and city.hero != null \
			and not city.hero.dead else Vector2.INF
	# обитатели внутри домов (этап 2, аспект 2): для светящихся окон
	_inside_homes.clear()
	for r in sim.residents:
		if int(r.get("inside", 0)) > 0 and r.get("home") != null and not (r["home"] as Dictionary).is_empty():
			_inside_homes[int((r["home"] as Dictionary)["id"])] = true
	if _trees_dirty:
		_trees_dirty = false
		_trees_cache = []
		for y in map.h:
			for x in map.w:
				var t: int = map.grid[y][x]
				if t == map.TILE_TREE or map.stumps.has(Vector2i(x, y)) or map.saplings.has(Vector2i(x, y)):
					_trees_cache.append(_build_tree_desc(Vector2i(x, y), ts))
		_trees_cache.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	# статичный набор (деревья + здания) пересобирается только когда ландшафт
	# или список зданий меняются; в кадре он готов к слиянию
	if _static_sorted_blds != sim.buildings.size():
		_static_sorted_blds = sim.buildings.size()
		_static_sorted = _trees_cache.duplicate(false)
		for b in sim.buildings:
			# Y-якорь — нижняя линия прямоугольника здания (2×2: tile.y + 1);
			# v1.36.1: здание на плато приподнято вместе с плоскостью плато
			var bw: int = sim.bld_w(b)
			_static_sorted.append([float(Vector2(b["tile"]).y + bw - 1) * ts + ts - 2.0
					- _bld_lift(b), "bld", b])
		_static_sorted.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	# динамический набор — короткий: брёвна, останки, кучи, звери, скот, люди, герой
	var dyn: Array = []
	# поваленные брёвна (v1.21.2): герой валит — лесопилка унесёт и распилит
	for tile: Vector2i in map.logs.keys():
		dyn.append([float(tile.y) * ts + ts * 0.78 - _static_lift(tile), "log", tile])
	# останки павших врагов (v1.23): лежат, пока кто-то не снесёт на кладбище
	for c in sim.corpses:
		var ct: Vector2i = c["tile"]
		dyn.append([float(ct.y) * ts + ts * 0.7 - _static_lift(ct), "corpse", c])
	for b in sim.buildings:
		if bool(b["done"]) and (b as Dictionary).has("pile") and _pile_total(b) >= 0.5:
			dyn.append([float(Vector2(b["tile"]).y + sim.bld_w(b) - 1) * ts + ts * 0.88
					- _bld_lift(b), "pile", b])
	for a in sim.animals:
		dyn.append([Vector2(a["pos"]).y, "animal", a])
	for a in sim.livestock:
		dyn.append([Vector2(a["pos"]).y, "stock", a])
	for w in sim.wanderers:
		dyn.append([Vector2(w["pos"]).y, "wanderer", w])
	for r in sim.raiders:
		dyn.append([Vector2(r["pos"]).y, "raider", r])
	for r in sim.residents:
		if int(r.get("inside", 0)) > 0:
			continue   # спит/лежит/прячется внутри дома — с карты не виден
		dyn.append([Vector2(r["pos"]).y, "res", r])
	if city != null and city.hero != null and not city.hero.dead:
		dyn.append([city.hero.global_position.y, "hero", city.hero])
	dyn.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	_draw_campfire()
	_draw_founded_cemetery()   # могилы кладбища без здания (v1.23)
	# слияние двух отсортированных списков: O(n+m) вместо sort всей карты.
	# v1.50 (FPS): статика отсортирована по y — стартуем двоичным поиском
	# с первой видимой строки и выходим, как только ушли ниже экрана
	var si := _static_window_start()
	var di := 0
	var y_max := _vis.end.y + float(map.ts) * 3.0
	while true:
		var take_dyn := false
		if di >= dyn.size():
			if si >= _static_sorted.size() or float(_static_sorted[si][0]) > y_max:
				break
		elif si >= _static_sorted.size():
			take_dyn = true
		elif float(dyn[di][0]) < float(_static_sorted[si][0]):
			take_dyn = true
		var e: Array
		if take_dyn:
			e = dyn[di]
			di += 1
		else:
			e = _static_sorted[si]
			si += 1
		match String(e[1]):
			"tree":
				# v1.21.5: дескриптор из кэша; v1.22: тень впечена в текстуру.
				# v1.50: дерево рядом с героем — полупрозрачное (видно, что
				# за ним), плавный спад от 2.4 тайла до 1.2
				if not _vis.intersects(e[5]):
					continue   # за экраном — дерево целиком пропускаем
				var mod := Color(1.0, 1.0, 1.0, 1.0)
				if _hero_px != Vector2.INF:
					var d: float = (e[6] as Vector2).distance_to(_hero_px)
					var ts_f := float(map.ts)
					var a := clampf((d - ts_f * 1.2) / (ts_f * 1.2), 0.0, 1.0)
					if a < 1.0:
						mod.a = lerpf(0.18, 1.0, a)
				draw_texture_rect_region(e[3], e[5], e[4], mod)
			"sapling":
				if not _vis.has_point(e[6]):
					continue
				_draw_sapling(e[2], e[6], ts)
			"stump":
				if not _vis.has_point(e[6]):
					continue
				_draw_stump(e[6], ts, _hash(e[2].x, e[2].y, STUMP_PALS.size()))
			"log":
				_draw_log_at(e[2])
			"corpse":
				_draw_corpse(e[2])
			"bld":
				_draw_building(e[2])
			"pile":
				_draw_pile(e[2])
			"animal":
				_draw_animal(e[2])
			"stock":
				_draw_stock(e[2])
			"wanderer":
				_draw_wanderer(e[2])
			"raider":
				_draw_raider(e[2])
			"res":
				_draw_resident(e[2])
			"hero":
				_draw_hero(e[2])


## Городской костёр (M12): горит вечером, ночью и при тревоге — точка сбора
## жителей и вечерних посиделок (рисуется под сортированным слоем).
func _draw_campfire() -> void:
	var fire := _fire_tile()
	var evening := false
	var day_len := float(sim.cfg["day_length"])
	var life: Dictionary = sim.cfg.get("life", {})
	var t := fmod(sim.time, day_len) / day_len
	var nf := float(sim.cfg["night_fraction"])
	evening = t >= maxf(0.0, 1.0 - nf - float(life.get("evening_len", 0.14)))
	if not evening and not sim.is_night() and not sim._raid_warned:
		return
	var pos: Vector2 = map.tile_center_px(fire) + Vector2(0, 4)
	var glow := 0.14 + 0.05 * sin(Time.get_ticks_msec() / 180.0)
	draw_circle(pos, map.ts * 1.6, Color(1.0, 0.6, 0.25, glow))
	Assets.draw_sheet(self, "fire", int(_anim_time * 9.0) % 5, pos, map.ts * 0.9)


## Точка костра: у колодца, если он есть, иначе в центре (как в симуляции).
func _fire_tile() -> Vector2i:
	for b in sim.buildings:
		if sim._active(b) and String(b["type"]) == "well":
			return Vector2i(b["tile"]) + Vector2i(1, 0)
	return map.spawn_tile


## Могилки вокруг кладбища (M12): маленькие кресты, появляются после похорон.
## v1.23: погребальный костёр горит два дня (обряд «предать огню»), прах
## после сожжения — тёмный курган; могилы растут до grow_radius клеток.
func _draw_graves(anchor: Vector2) -> void:
	var radius_px: float = float(sim.cfg.get("cemetery", {}).get("grow_radius", 5)) * float(map.ts) + float(map.ts)
	for g in sim.graves:
		var pos: Vector2 = map.tile_center_px(Vector2i(g["tile"]))
		if pos.distance_to(anchor) > radius_px:
			continue
		if String(g.get("rite", "bury")) == "burn" and not bool(g.get("ready", false)):
			# погребальный костёр: столб и живое пламя
			draw_line(pos + Vector2(0, 2), pos + Vector2(0, -14), Color("#5d4037"), 3.0)
			var flame := 0.6 + 0.4 * sin(_anim_time * 8.0 + pos.x)
			draw_circle(pos + Vector2(0, -12), 5.0 * flame, Color(1.0, 0.55, 0.2, 0.8))
			draw_circle(pos + Vector2(0, -16), 3.0 * flame, Color(1.0, 0.75, 0.3, 0.7))
			continue
		if bool(g.get("ready", false)):
			if String(g.get("rite", "bury")) == "burn":
				# прах под тёмным курганом-плитой
				draw_circle(pos + Vector2(0, 1), 5.0, Color("#7a6a5a"))
				draw_circle(pos + Vector2(0, -1), 4.0, Color("#8d7d6d"))
				continue
			draw_line(pos + Vector2(-3, -8), pos + Vector2(3, -8), Color(0.86, 0.84, 0.78), 2.0)
			draw_line(pos + Vector2(0, -11), pos + Vector2(0, -2), Color(0.86, 0.84, 0.78), 2.0)
			draw_line(pos + Vector2(-3, 0), pos + Vector2(3, 0), Color(0.55, 0.52, 0.45), 2.0)


## Кладбище без здания (v1.23): первая могила основала место — кресты
## и оградка из колышков, пока горожане не поставят настоящее кладбище.
func _draw_founded_cemetery() -> void:
	if sim.cemetery_tile == Vector2i(-1, -1):
		return
	for b in sim.buildings:
		if sim._active(b) and String(b["type"]) == "cemetery":
			return   # есть настоящее кладбище — могилки рисует оно
	var anchor: Vector2 = map.tile_center_px(sim.cemetery_tile)
	var ts := float(map.ts)
	for n in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var p: Vector2 = map.tile_center_px(sim.cemetery_tile + n) + Vector2(0, ts * 0.3)
		draw_line(p - Vector2(3, 5), p + Vector2(3, 5), Color("#5d4037"), 2.0)
		draw_line(p + Vector2(3, -5), p - Vector2(3, 5), Color("#5d4037"), 2.0)
	_draw_graves(anchor)


## Останки павшего врага (v1.23): тёмный остов и кости — контраст с травой,
## чтобы игрок видел, что городу есть что унести на кладбище.
func _draw_corpse(c: Dictionary) -> void:
	var ts := float(map.ts)
	var pos: Vector2 = map.tile_center_px(Vector2i(c["tile"])) + Vector2(0, ts * 0.15)
	pos.y -= _static_lift(Vector2i(c["tile"]))   # v1.36.1: плоскость плато
	var rot := clampf(float(c.get("rot", 0.0)) / 3.0, 0.0, 1.0)
	var col := Color(0.24, 0.2, 0.18).lerp(Color(0.42, 0.4, 0.34), rot)
	_draw_shadow(pos + Vector2(0, 4), ts * 0.34)
	draw_circle(pos, ts * 0.26, col)
	draw_line(pos + Vector2(-5, -2), pos + Vector2(5, -2), Color(0.85, 0.82, 0.75), 1.5)
	draw_circle(pos + Vector2(-6, -2), 2.0, Color(0.85, 0.82, 0.75))
	draw_circle(pos + Vector2(6, -2), 2.0, Color(0.85, 0.82, 0.75))


## Дерево/пень/саженец (M12 — из статического слоя; v1.21.5 — деревья
## выдаются готовыми дескрипторами из _trees_cache, пень и саженец —
## редкие, рисуются как раньше). Пень подбирается под тип дерева тем же
## хешом, что выбрал спрайт. Правки v1.21: три размера дерева.


## Поваленное бревно на земле (v1.21.2): толщина по размеру дерева —
## малое/среднее/большое; лесоруб унесёт его на лесопилку.
func _draw_log_at(tile: Vector2i) -> void:
	var ts := float(map.ts)
	var c: Vector2 = map.tile_center_px(tile) + Vector2(0, ts * 0.2)
	c.y -= _static_lift(tile)   # v1.36.1: плоскость плато
	var size: int = int((map.logs[tile] as Dictionary).get("size", 1))
	var w := ts * 0.55 + ts * 0.18 * float(size)
	var col := Color("#8d6e63") if size < 3 else Color("#6d4c33")
	_draw_shadow(c + Vector2(0, 5), ts * 0.42)
	draw_rect(Rect2(c.x - w * 0.5, c.y - 5.0, w, 10.0), col)
	draw_circle(Vector2(c.x - w * 0.5, c.y), 5.0, col.lightened(0.15))
	draw_circle(Vector2(c.x + w * 0.5, c.y), 5.0, col.lightened(0.15))
	draw_line(Vector2(c.x - w * 0.5 + 2.0, c.y), Vector2(c.x + w * 0.5 - 2.0, c.y),
			col.darkened(0.25), 1.5)


## Пень: срез с годовыми кольцами и кора в палитре своего дерева.
## Порядок — по индексам TREE_REFS (v1.32: под стволы новых деревьев).


func _draw_stump(bottom: Vector2, ts: float, variant: int) -> void:
	var pal: Dictionary = STUMP_PALS[variant % STUMP_PALS.size()]
	_draw_shadow(bottom, ts * 0.3)
	var w := ts * 0.46
	var h := ts * 0.26
	# кора (боковина) и светлый срез сверху
	draw_rect(Rect2(bottom + Vector2(-w / 2.0, -h), Vector2(w, h)), pal["side"])
	draw_rect(Rect2(bottom + Vector2(-w / 2.0, -h * 1.7), Vector2(w, h * 0.9)), pal["top"])
	draw_arc(bottom + Vector2(0, -h * 1.25), w * 0.26, 0.0, TAU, 14, pal["ring"], 1.2)
	draw_circle(bottom + Vector2(0, -h * 1.25), w * 0.08, pal["ring"])
	# детали по типу: у берёзы — тёмные чёрточки, у плодового — живой побег,
	# у старого/осеннего — трещина
	var birch := variant == 2 or variant == 7
	var fruit := variant == 6
	var autumn := variant == 3
	if birch:
		draw_rect(Rect2(bottom + Vector2(-w * 0.36, -h * 0.75), Vector2(w * 0.18, h * 0.22)), Color("#424242"))
		draw_rect(Rect2(bottom + Vector2(w * 0.14, -h * 0.4), Vector2(w * 0.16, h * 0.2)), Color("#424242"))
	elif fruit:
		draw_line(bottom + Vector2(0, -h * 1.6), bottom + Vector2(3, -h * 2.4), Color("#7cb342"), 1.4)
		draw_circle(bottom + Vector2(3.6, -h * 2.5), 1.4, Color("#8bc34a"))
	elif autumn:
		draw_line(bottom + Vector2(-w * 0.2, -h * 1.6), bottom + Vector2(w * 0.1, -h * 0.3), Color("#4e342e"), 1.1)


# «Природа 2.0» (v1.39.0): деревья ForgottenMemories (пак заказчика,
# tools/make_nature2.py, приглушены под гамму): клён, мана-дерево,
# берёза, сосна, ива. Индекс = вариант пня в STUMP_PALS (по палитре).
## Тёмные деревья болот (v1.39.2): мрачная ива и хвоя — для деревьев,
## растущих в кольце тёмной земли вокруг болот.


## Вода болота в радиусе 2 тайлов (для тёмного леса).
func _near_swamp(tile: Vector2i) -> bool:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var n := tile + Vector2i(dx, dy)
			if map.in_bounds(n) and map.grid[n.y][n.x] == map.TILE_WATER \
					and map.water_kind_at(n) == "swamp":
				return true
	return false



func _draw_shadow(pos: Vector2, radius: float) -> void:
	draw_circle(pos, radius * 0.5, Color(0, 0, 0, 0.18))


## Саженец: две стадии роста (малый росток, кустик).
func _draw_sapling(key: Vector2i, bottom: Vector2, ts: float) -> void:
	var s: Dictionary = map.saplings[key]
	var frac: float = clampf(float(s.get("t", 0.0)) / maxf(0.1, float(s.get("grow_days", 1.2))), 0.0, 1.0)
	var ref := "e:sap1" if frac < 0.5 else "e:sap2"
	_draw_shadow(bottom, ts * 0.2)
	Assets.draw_ref(self, ref, bottom, ts * (0.5 if frac < 0.5 else 0.85))


func _pile_total(b: Dictionary) -> float:
	var total := 0.0
	for k in b.get("pile", {}):
		total += float(b["pile"][k])
	return total


## Куча ресурса у здания (M6 → M12 сортированный слой).
func _draw_pile(b: Dictionary) -> void:
	var ts := float(map.ts)
	var pile: Dictionary = b["pile"]
	var total := 0.0
	var key := ""
	var best := 0.0
	for k in pile:
		total += float(pile[k])
		if float(pile[k]) > best:
			best = float(pile[k])
			key = String(k)
	if total < 0.5:
		return
	var corner: Vector2 = Vector2(b["tile"]) * ts + Vector2(ts * 0.78, ts * 0.88)
	corner.y -= _bld_lift(b)   # v1.36.1: куча стоит на плоскости плато
	var size := 8.0 + minf(10.0, total / 3.0)
	var tint: Color = _pile_colors.get(key, Color(0.8, 0.8, 0.8)).lightened(0.25)
	Assets.draw_ref(self, PILE_SPRITES.get(key, "k:73"), corner, size, false, tint)


## Дикие животные (M5.1 → M14-C правка): виды из data/fauna.json — индюк
## остался, добавились олени, кабаны, птицы и волки (векторные, в стиле мира).
func _draw_animal(a: Dictionary) -> void:
	var pos: Vector2 = a["pos"]
	# v1.36.1: зверь на плато стоит выше равнины (подъём сглаживается)
	pos.y -= _entity_lift("an%d" % int(a["id"]), a["pos"])
	var vel := Vector2.ZERO
	var pth: PackedVector2Array = a.get("path", PackedVector2Array())
	if not pth.is_empty():
		vel = pth[0] - pos
	var kind := String(a.get("kind", "turkey"))
	if kind == "deer" or kind == "boar" or kind == "wolf" or kind == "bird" \
			or kind == "hare" or kind == "fox":
		_draw_fauna_animal(a, kind, pos, vel)
		return
	Assets.draw_animal(self, "turkey", Assets.dir_of(vel), not pth.is_empty(),
			pos + Vector2(0, -4), 20.0, _anim_time + float(a["id"]) * 0.37)


## Зверь из fauna.json: тело/голова/детали вида, цвет и размер из данных.
func _draw_fauna_animal(a: Dictionary, kind: String, pos: Vector2, vel: Vector2) -> void:
	var def: Dictionary = {}
	for s in fauna_cfg.get("species", []):
		if String(s["id"]) == kind:
			def = s
			break
	if def.is_empty():
		Assets.draw_animal(self, "turkey", Assets.dir_of(vel), not vel.is_zero_approx(),
				pos + Vector2(0, -4), 20.0, _anim_time + float(a["id"]) * 0.37)
		return
	var col := Color(String(def.get("color", "#cccccc")))
	var size := float(def.get("size", 1.0))
	var moving := not vel.is_zero_approx()
	var bob := absf(sin(_anim_time * 4.0 + float(a["id"]))) * (1.5 if moving else 0.4)
	draw_circle(pos + Vector2(0, 2), 5.0 * size, Color(0, 0, 0, 0.2))
	draw_circle(pos + Vector2(0, -2.0 * size - bob * 0.2), 4.6 * size, col)
	draw_circle(pos + Vector2(4.0 * size, -4.5 * size - bob * 0.3), 2.6 * size, col.lightened(0.12))
	match kind:
		"deer":
			draw_line(pos + Vector2(3.5 * size, -6.5 * size), pos + Vector2(2.2 * size, -10.5 * size), Color("#6d4c33"), 1.2)
			draw_line(pos + Vector2(4.8 * size, -6.2 * size), pos + Vector2(5.8 * size, -10.0 * size), Color("#6d4c33"), 1.2)
			draw_circle(pos + Vector2(5.6 * size, -4.0 * size), 0.9 * size, Color.WHITE)
		"boar":
			draw_circle(pos + Vector2(6.2 * size, -3.6 * size), 1.1 * size, Color("#e8b0a0"))
			draw_line(pos + Vector2(-4.5 * size, -2.0 * size), pos + Vector2(-6.5 * size, -2.8 * size), col.darkened(0.3), 1.5)
		"wolf":
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(3.0 * size, -6.2 * size), pos + Vector2(3.8 * size, -8.8 * size),
				pos + Vector2(4.9 * size, -6.4 * size)]), col.darkened(0.15))
			draw_line(pos + Vector2(-4.5 * size, -3.0 * size), pos + Vector2(-7.2 * size, -4.6 * size), col.darkened(0.25), 1.6)
		"bird":
			draw_circle(pos + Vector2(4.2 * size, -5.2 * size), 1.7 * size, Color("#3a3a3a"))
			draw_line(pos + Vector2(-3.0 * size, -2.4 * size), pos + Vector2(-6.0 * size, -4.4 * size), col.darkened(0.2), 1.2)
		"hare":
			# v1.50: заяц — мелкий, уши торчком, скачет (усиленный бобинг)
			draw_line(pos + Vector2(3.2 * size, -6.6 * size - bob), pos + Vector2(4.2 * size, -11.5 * size - bob), col.darkened(0.25), 1.4)
			draw_line(pos + Vector2(5.0 * size, -6.4 * size - bob), pos + Vector2(6.6 * size, -10.8 * size - bob), col.darkened(0.25), 1.4)
			draw_circle(pos + Vector2(5.8 * size, -4.2 * size - bob * 0.4), 0.8 * size, Color.WHITE)
		"fox":
			# v1.50: лиса — рыжая, острая морда и пушистый хвост
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(-4.0 * size, -3.0 * size), pos + Vector2(-8.5 * size, -5.0 * size),
				pos + Vector2(-7.5 * size, -1.5 * size)]), col.lightened(0.15))
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(4.6 * size, -6.0 * size), pos + Vector2(5.8 * size, -9.0 * size),
				pos + Vector2(6.8 * size, -5.8 * size)]), col.darkened(0.1))
			draw_circle(pos + Vector2(6.4 * size, -4.2 * size), 0.8 * size, Color("#e8e2d0"))


## Скот на пастбищах (M10): коровы/овцы/свиньи/куры, детёныши мельче.
func _draw_stock(a: Dictionary) -> void:
	var pos: Vector2 = a["pos"]
	pos.y -= _entity_lift("stk%d" % int(a["id"]), a["pos"])   # v1.36.1: высота плато
	var kind := String(a["kind"])
	var adult := bool(a["adult"])
	var size := 26.0 if adult else 16.0
	if kind == "chicken" or kind == "chick":
		size *= 0.7
	var moving := bool(a.get("moving", false))
	Assets.draw_animal(self, {"chick": "chicken"}.get(kind, kind),
			String(a.get("dir", "front")), moving, pos + Vector2(0, -4),
			size, _anim_time + float(a["id"]) * 0.53)


## Бродячий торговец (этап 2, аспект 4): гражданин с тюком и жёлтой одеждой;
## у палатки периодически выкрикивает зазывку-облачко.
func _draw_wanderer(w: Dictionary) -> void:
	var pos: Vector2 = w["pos"]
	pos.y -= _entity_lift("wand%d" % int(w["id"]), w["pos"])   # v1.36.1: высота плато
	var pth: PackedVector2Array = w.get("path", PackedVector2Array())
	var moving := not pth.is_empty() and pos.distance_to(pth[pth.size() - 1]) > 2.0
	var dir := String(w.get("dir", "front"))
	var tint := Color("#ffd54f").lerp(Color.WHITE, 0.35)
	Assets.draw_citizen(self, 1 + int(w["id"]) % 4, dir, moving, pos, 50.0,
			_anim_time + float(w["id"]) * 0.47, tint)
	# тюк с товаром за спиной
	draw_circle(pos + Vector2(-11.0, -8.0), 5.0, Color("#8d6e63"))
	draw_circle(pos + Vector2(-10.0, -10.0), 2.5, Color("#a1887f"))
	if String(w.get("mode", "")) == "trade" and fmod(sim.time, 14.0) < 3.0:
		var key := "wshop.%d" % (int(w["id"]) % 4 + 1)
		_draw_speech_bubble(pos, Loc.t(key))


# Зоны, растения грядок, заборы пастбищ и дороги (M6): заливки/борозды/заборы
# запечены в духовку ландшафта city_terrain.gd (v1.22), растения и полосы
# обустройства остались живыми (_draw_field_live) вместе с пульсом площади.


## Улей мутантов (v1.44): тёмный органический блоб из «капсул», полоса HP
## и уровень; светится багровым, когда готовит волну.
func _draw_hive() -> void:
	var h: Dictionary = sim.hive
	if h.is_empty() or not bool(h.get("active", false)):
		return
	var pos: Vector2 = h["pos"]
	var level: int = int(h.get("level", 1))
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 2.4)
	var r := float(map.ts) * (0.9 + 0.12 * level)
	# тело улья: три тёмных «мешка»
	var body := Color("#2a1518")
	var rim := Color("#4d1f22")
	for k in 3:
		var ang := float(k) * TAU / 3.0 + _anim_time * 0.2
		var c := pos + Vector2(cos(ang), sin(ang)) * r * 0.35
		draw_circle(c, r * 0.55, body)
		draw_circle(c, r * 0.55, Color(rim.r, rim.g, rim.b, 0.35), false, 1.5)
	draw_circle(pos, r * 0.5, Color("#1a0d10"))
	# зев — багровое свечение при подготовке волны
	var hot := float(h.get("alert", 0.0))
	if float(h.get("stock", 0)) >= 10 or hot > 0.0:
		draw_circle(pos, r * (0.3 + 0.12 * pulse),
				Color(0.72, 0.18, 0.14, 0.35 + 0.35 * pulse))
	# полоса HP
	var w := float(map.ts) * 1.6
	draw_rect(Rect2(pos - Vector2(w / 2, r + 8), Vector2(w, 4)), Color(0, 0, 0, 0.5))
	var frac: float = clampf(float(h.get("hp", 0)) / float(HIVE_HP_MAX), 0.0, 1.0)
	draw_rect(Rect2(pos - Vector2(w / 2, r + 8), Vector2(w * frac, 4)),
			Color(0.75, 0.2, 0.16))


func _draw_anomaly() -> void:
	var c: Color = colors["anomaly"]
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 300.0)
	var center: Vector2 = map.tile_center_px(map.anomaly_tile)
	draw_circle(center, map.ts * 0.55 * pulse, Color(c.r, c.g, c.b, 0.35))
	draw_circle(center, map.ts * 0.32, c)
	draw_circle(center, map.ts * 0.14, c.lightened(0.4))


## Выход на карту мира (M8): вся рамка карты — зона перехода (лёгкая зелёная
## полоса по периметру), на западе — каменная арка с яркого свечением и
## стрелкой: главные ворота на запад, видно издалека.
func _draw_world_exit() -> void:
	var ts: float = float(map.ts)
	# рамка-зона перехода по всему периметру
	var band := Color(0.45, 0.9, 0.5, 0.10)
	draw_rect(Rect2(0, 0, map.w * ts, ts), band)
	draw_rect(Rect2(0, (map.h - 1) * ts, map.w * ts, ts), band)
	draw_rect(Rect2(0, 0, ts, map.h * ts), band)
	draw_rect(Rect2((map.w - 1) * ts, 0, ts, map.h * ts), band)
	var center: Vector2 = map.tile_center_px(map.world_exit_tile)
	var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 350.0)
	var glow := Color(0.45, 0.9, 0.5)
	# свечение-дорога: на запад, за край
	draw_rect(Rect2(center + Vector2(-ts * 0.5, -ts * 0.12), Vector2(ts * 0.5, ts * 0.24)),
			Color(glow.r, glow.g, glow.b, 0.25 + 0.15 * pulse))
	# арка: две опоры и перекладина
	draw_rect(Rect2(center + Vector2(-ts * 0.34, -ts * 0.42), Vector2(ts * 0.16, ts * 0.84)), Color("#8a8a82"))
	draw_rect(Rect2(center + Vector2(ts * 0.18, -ts * 0.42), Vector2(ts * 0.16, ts * 0.84)), Color("#8a8a82"))
	draw_rect(Rect2(center + Vector2(-ts * 0.38, -ts * 0.56), Vector2(ts * 0.76, ts * 0.18)), Color("#7a7a72"))
	# зелёное свечение в проёме
	draw_rect(Rect2(center + Vector2(-ts * 0.18, -ts * 0.36), Vector2(ts * 0.36, ts * 0.78)),
			Color(glow.r, glow.g, glow.b, 0.3 + 0.2 * pulse))
	# стрелка влево — «мир там»
	var y := center.y - ts * 0.08
	draw_line(center + Vector2(ts * 0.05, y), center + Vector2(-ts * 0.2, y),
			Color(glow.r, glow.g, glow.b, 0.6 + 0.3 * pulse), 2.5)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-ts * 0.2, y), center + Vector2(-ts * 0.1, y - 4.5),
		center + Vector2(-ts * 0.1, y + 4.5)]),
		Color(glow.r, glow.g, glow.b, 0.6 + 0.3 * pulse))


## Здание в общем сортированном слое (M12). Схематичный режим (этап 2,
## аспект 1) + прямоугольник 2×2 с входом (этап 2, аспект 2): заливка
## цвета категории, тёмная кайма, дверной проём у входа, окно светится,
## если кто-то спит внутри. Игровые метки сохранены.
