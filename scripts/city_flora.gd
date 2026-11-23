extends Node2D
## Живая флора города (v1.80.2, фидбек: «не хватает живой травы и цветов,
## которые развевались бы на ветру, и всякой живности»): редкие травинки
## и цветы качаются на ветру, порхают мотыльки. Рисуются РЕДКО (хэш —
## каждый 9-й травяной тайл, 1-2 штриха) — акценты полотна, не «второй
## слой». Слойterrain-порядка: над землёй, под жителями и деревьями.

var map = null
var sim = null               # v1.84: серая плесень рисуется в этом же слое
var _time := 0.0
var _seed := 20261121
var _butterflies: Array = []   # {base: Vector2, phase: float}


func setup(city_map, sim_ref = null) -> void:
	map = city_map
	sim = sim_ref
	_butterflies = []
	for i in 3:
		var t: Vector2i = city_map.spawn_tile + Vector2i(_wr(50) - 25, _wr(50) - 25)
		if not city_map.in_bounds(t):
			t = city_map.spawn_tile
		_butterflies.append({
			"base": city_map.tile_center_px(t) + Vector2(_wr(30) - 15, _wr(20) - 10),
			"phase": float(i) * 2.1,
		})


func _wr(n: int) -> int:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return _seed % maxi(1, n)


func _wr_hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16)) % 100000


func _process(delta: float) -> void:
	_time += delta
	# v1.80.3 (FPS): 15 fps достаточно для покачивания (было: каждый кадр)
	_anim_accum += delta
	if _anim_accum >= 1.0 / 15.0:
		_anim_accum = 0.0
		queue_redraw()

var _anim_accum := 0.0


func _draw() -> void:
	if map == null:
		return
	var ts := float(map.ts)
	var xf := get_viewport_transform()
	var vis: Rect2 = (xf.affine_inverse() * get_viewport_rect()).grow(ts)
	var x0 := maxi(0, int(floor(vis.position.x / ts)))
	var y0 := maxi(0, int(floor(vis.position.y / ts)))
	var x1 := mini(map.w, int(ceil(vis.end.x / ts)))
	var y1 := mini(map.h, int(ceil(vis.end.y / ts)))
	# v1.80.1 (FPS): вдали акценты неразличимы — не рисуем
	if (x1 - x0) * (y1 - y0) > 1500:
		return
	for y in range(y0, y1):
		for x in range(x0, x1):
			if int(map.grid[y][x]) != map.TILE_GRASS:
				continue
			var h := _wr_hash(x, y)
			if h % 9 != 0:
				continue
			var base: Vector2 = Vector2(x, y) * ts \
					+ Vector2(6.0 + float(h % 18), 8.0 + float((h / 7) % 16))
			var sway := sin(_time * 1.9 + float(h % 7)) * 1.8
			var h2 := (h / 31) % 4
			if h2 == 0:
				# цветок: стебель качается, венчик над ним
				draw_line(base, base + Vector2(sway * 0.6, -7.0),
						Color(0.36, 0.5, 0.26, 0.9), 1.2)
				var fc: Color = [Color(0.92, 0.88, 0.55), Color(0.9, 0.55, 0.5),
						Color(0.85, 0.85, 0.95)][(h / 53) % 3]
				draw_circle(base + Vector2(sway * 0.6, -8.0), 1.8, fc)
			else:
				# 1-2 травинки на ветру
				draw_line(base, base + Vector2(sway, -6.0 - float(h % 3)),
						Color(0.42, 0.58, 0.3, 0.85), 1.2)
				if h2 == 2:
					draw_line(base + Vector2(2.5, 0), base + Vector2(2.5 - sway, -5.0),
							Color(0.5, 0.62, 0.34, 0.8), 1.1)
	# v1.84: СЕРАЯ ПЛЕСЕНЬ — с v1.88 спрайты листа «грибной улей и пепел»
	# (4 стадии по возрасту клетки), выжженное магией — отдельный тайл;
	# процедурные кляксы — запасной путь, если текстуры не нарезаны
	if sim != null and sim.get("mold") != null:
		var mold: Dictionary = sim.mold
		if not mold.is_empty():
			var pulse: float = 0.5 + 0.5 * sin(_time * 1.1)
			for t2: Vector2i in mold.keys():
				var c2: Vector2 = map.tile_center_px(t2)
				if not vis.has_point(c2):
					continue
				var age: float = float(mold[t2])
				var mtex: Texture2D = Assets.tex("res://assets/sprites/env/mold_%d.png"
						% clampi(int(age), 1, 4))
				if mtex != null:
					draw_texture_rect(mtex, Rect2(c2 - Vector2(ts, ts) * 0.62,
							Vector2(ts, ts) * 1.24), false)
					if age > 2.0:
						draw_circle(c2 + Vector2(0, -ts * 0.3), 1.4,
								Color(0.72, 0.74, 0.6, 0.5 + 0.3 * pulse))
					continue
				for i2 in 4:
					var ang := TAU * (float(i2) / 4.0 + 0.2 * pulse)
					var r2: float = ts * (0.16 + 0.07 * float(i2 % 2))
					var cc: Vector2 = c2 + Vector2(cos(ang), sin(ang)) * ts * (0.14 + 0.05 * float(i2 % 3))
					draw_circle(cc, r2, Color(0.545, 0.565, 0.515, 0.55))
				draw_circle(c2, ts * (0.10 + 0.03 * pulse), Color(0.62, 0.60, 0.48, 0.6))
				if age > 2.0:
					# старая плесень выпускает споры-точки
					draw_circle(c2 + Vector2(0, -ts * 0.3), 1.4,
							Color(0.72, 0.74, 0.6, 0.5 + 0.3 * pulse))
		# v1.88: след магии героя — выжженная земля на месте плесени
		var burned_v: Variant = sim.get("mold_burned")
		if burned_v is Dictionary:
			for t3: Vector2i in (burned_v as Dictionary).keys():
				var c3: Vector2 = map.tile_center_px(t3)
				if not vis.has_point(c3):
					continue
				var btex: Texture2D = Assets.tex("res://assets/sprites/env/mold_burned_1.png")
				if btex != null:
					draw_texture_rect(btex, Rect2(c3 - Vector2(ts, ts) * 0.62,
							Vector2(ts, ts) * 1.24), false)
	# мотыльки: порхают у земли (ночью читаются как мотыльки у фонарей)
	for b in _butterflies:
		var pos: Vector2 = (b["base"] as Vector2) + Vector2(
				sin(_time * 0.7 + float(b["phase"])) * 26.0,
				cos(_time * 1.1 + float(b["phase"]) * 1.3) * 10.0)
		var flap := absf(sin(_time * 9.0 + float(b["phase"])))
		draw_circle(pos, 1.6, Color(0.95, 0.85, 0.5, 0.9))
		draw_line(pos + Vector2(-2.5 * flap, -1.0), pos + Vector2(2.5 * flap, -1.0),
				Color(0.9, 0.8, 0.45, 0.8), 1.0)
