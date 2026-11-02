extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Отрисовка тайлов данжа. «Данжи v2» (v1.42, этап 4 «Мир v2», материалы по
## референсам «для Z.ai/данж, биомы и мир»): пол — плиты пака заказчика
## (d2_floor_*, нормализованный серый + тинт биома), стены — КИРПИЧНАЯ ГРАНЬ
## (d2_wall_face, если под стеной виден пол) и верхний КАП кладки
## (d2_wall_top), мягкая тень под гранью (d2_shadow). Спрайты статичны —
## перерисовка один раз на забег. Вне коридоров и комнат — непроглядная
## чернота (правка v1.29.1).

var gen: Object = null
var ts := 32
var biome: Dictionary = {}
var _near_floor: Array = []      # маска w*h: тайл стены рядом с полом
var _face_mask: Array = []       # стена, под которой (юг) пол — рисуем грань
var _void_col := Color(0.012, 0.012, 0.02)


func setup(dungeon_gen: Object, tile_size: int, biome_data: Dictionary) -> void:
	gen = dungeon_gen
	ts = tile_size
	biome = biome_data
	_build_void_mask()
	queue_redraw()


## Маски стен: «стена видна» (в 8 соседях есть пол) и «стена-грань» (пол
## сразу на юге — классическая читаемость рельефа top-down).
func _build_void_mask() -> void:
	_near_floor.clear()
	_face_mask.clear()
	for y in gen.h:
		var row := []
		var frow := []
		row.resize(gen.w)
		frow.resize(gen.w)
		row.fill(false)
		frow.fill(false)
		_near_floor.append(row)
		_face_mask.append(frow)
	for y in gen.h:
		for x in gen.w:
			if gen.grid[y][x] != gen.TILE_FLOOR:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and ny >= 0 and nx < gen.w and ny < gen.h:
						_near_floor[ny][nx] = true
			var sx: int = x
			var sy: int = y - 1
			if sx >= 0 and sy >= 0 and sx < gen.w and sy < gen.h:
				_face_mask[sy][sx] = true


func _draw() -> void:
	if gen == null:
		return
	# Материалы биома (v1.33): цвета заданы в data/dungeon.json нормальной
	# яркости; тинт ложится на нормализованные текстуры пака. Что скрыто
	# туманом войны — решает dungeon_fog.gd поверх этого слоя.
	var wall_col := Color(String(biome["wall_color"]))
	var floor_col := Color(String(biome["floor_color"]))
	var decor := Color(String(biome.get("decor_color", "#555048")))
	draw_rect(Rect2(0, 0, gen.w * ts, gen.h * ts), _void_col)
	# биом без пака (старый/модовый): откат на плоские цвета
	var use_pack: bool = bool(biome.get("v2_pack", true))
	var half := Vector2(ts, ts) * 0.5
	for y in gen.h:
		for x in gen.w:
			var tile: int = gen.grid[y][x]
			var pos := Vector2(x, y) * ts
			var h := _hash(x, y)
			if tile == gen.TILE_FLOOR:
				var col := floor_col if (x + y) % 2 == 0 else floor_col.darkened(0.06)
				if use_pack:
					# v1.42.4: пол пака с АВТОКРОМКАМИ у стен (тень пола,
					# как в демо-карте пака); в центре — чистая кладка
					var ref := ""
					if gen.tile_at(Vector2i(x, y - 1)) != gen.TILE_FLOOR:
						ref = "e:d2_edge_n"
					elif gen.tile_at(Vector2i(x, y + 1)) != gen.TILE_FLOOR:
						ref = "e:d2_edge_s"
					elif gen.tile_at(Vector2i(x - 1, y)) != gen.TILE_FLOOR:
						ref = "e:d2_edge_w"
					elif gen.tile_at(Vector2i(x + 1, y)) != gen.TILE_FLOOR:
						ref = "e:d2_edge_e"
					else:
						match h % 7:
							0, 3: ref = "e:d2_floor_b"
							5: ref = "e:d2_floor_c"
							_: ref = "e:d2_floor_a"
					Assets.draw_ref(self, ref, pos + half, float(ts), false, col)
				else:
					draw_rect(Rect2(pos, Vector2(ts, ts)), col)
				# декали пола: крошка/трещина на каждом шестом тайле (v1.28)
				if h % 6 == 0 and not use_pack:
					var dp := pos + Vector2(6.0 + float(h % (ts - 12)),
							6.0 + float((h / 3) % (ts - 12)))
					if h % 12 == 0:
						draw_line(dp, dp + Vector2(5.0, 3.0), Color(decor.r, decor.g, decor.b, 0.7), 1.2)
						draw_line(dp + Vector2(5.0, 3.0), dp + Vector2(8.0, 2.0),
								Color(decor.r, decor.g, decor.b, 0.55), 1.0)
					else:
						draw_circle(dp, 1.6 + float(h % 2), Color(decor.r, decor.g, decor.b, 0.5))
						draw_circle(dp + Vector2(3.0, -2.0), 1.0, Color(decor.r, decor.g, decor.b, 0.4))
			elif _near_floor[y][x]:
				if _face_mask[y][x]:
					# грань: кирпич + светлая кромка верха; тень кладём на пол ниже
					if use_pack:
						Assets.draw_ref(self, "e:d2_wall_face", pos + half, float(ts),
								false, wall_col)
					else:
						draw_rect(Rect2(pos, Vector2(ts, ts)), wall_col.darkened(0.18))
					if y + 1 < gen.h and gen.grid[y + 1][x] == gen.TILE_FLOOR:
						Assets.draw_ref(self, "e:d2_shadow", pos + Vector2(ts, ts * 1.5),
								float(ts), false, Color(0.0, 0.0, 0.0, 0.55))
				else:
					# верх стены: кап кладки
					if use_pack:
						Assets.draw_ref(self, "e:d2_wall_top", pos + half, float(ts),
								h % 5 == 0, wall_col.darkened(0.08))
					else:
						draw_rect(Rect2(pos, Vector2(ts, ts)), wall_col.darkened(0.18))
						Assets.draw_ref(self, String(biome.get("wall_sprite", "")),
								pos + half, float(ts), false, wall_col)
			else:
				# глубинная порода вне коридоров и комнат — чернота без спрайта
				draw_rect(Rect2(pos, Vector2(ts, ts)), _void_col)
			# угольки огненных биомов (v1.33): редкие, жарко-яркие
			var ember_hex := String(biome.get("ember_color", ""))
			if ember_hex != "" and tile == gen.TILE_FLOOR and h % 7 == 3:
				var ember := Color(ember_hex)
				var ep := pos + Vector2(5.0 + float(h % (ts - 10)),
						5.0 + float((h / 5) % (ts - 10)))
				draw_circle(ep, 3.2, Color(ember.r, ember.g, ember.b, 0.22))
				draw_circle(ep, 1.3, Color(ember.r, ember.g, ember.b, 0.9))
				draw_circle(ep + Vector2(-0.8, -0.8), 0.6,
						Color(ember.r, ember.g, ember.b).lightened(0.5))


static func _hash(x: int, y: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, 1000)
