extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Отрисовка тайлов данжа (M1→M9): спрайты Kenney Tiny Dungeon 16×16 (×2),
## подкрашенные цветами биома. Спрайты статичны — перерисовка один раз на забег.
## v1.29.1 (правки приёмки): вне коридоров и комнат — НЕПРОГЛЯДНАЯ чернота:
## фон залит чёрным, спрайт стены остался только на первом кольце вокруг
## пола, глубинная порода не рисуется вовсе.

var gen: Object = null
var ts := 32
var biome: Dictionary = {}
var _near_floor: Array = []      # маска w*h: тайл стены рядом с полом
var _void_col := Color(0.012, 0.012, 0.02)


func setup(dungeon_gen: Object, tile_size: int, biome_data: Dictionary) -> void:
	gen = dungeon_gen
	ts = tile_size
	biome = biome_data
	_build_void_mask()
	queue_redraw()


## Маска «стена видна»: тайл не-пол, у которого в 8 соседях есть пол.
func _build_void_mask() -> void:
	_near_floor.clear()
	for y in gen.h:
		var row := []
		row.resize(gen.w)
		row.fill(false)
		_near_floor.append(row)
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


func _draw() -> void:
	if gen == null:
		return
	# v1.32.1 (заказчик): стены и пол — ТЁМНЫЕ, НО НЕ ЧЁРНЫЕ. Авторские
	# цвета биомов (#4d4340/#2b2220) очень тёмные — под амбиентом данжа
	# стены выходили rgb(29,23,22), «почти чёрные». Поднимаем каналы
	# цвето-сохраняющим умножением: пол ×1.2, стена ×2.2 (оттенок биома
	# остаётся, читаемость появляется). ВНЕ комнат — по-прежнему чёрный войд.
	var wall_col := _scaled(String(biome["wall_color"]), 2.2)
	draw_rect(Rect2(0, 0, gen.w * ts, gen.h * ts), _void_col)
	var floor_ref := String(biome.get("floor_sprite", ""))
	var wall_ref := String(biome.get("wall_sprite", ""))
	# v1.28: альтернативная плита пола и декали (трещины/крошка) — полы и
	# стены различаются между биомами (заказчик)
	var floor_alt := String(biome.get("floor_sprite_alt", floor_ref))
	var decor := Color(String(biome.get("decor_color", "#555048")))
	var floor_color := _scaled(String(biome["floor_color"]), 1.2)
	var floor_color_alt := floor_color.darkened(0.07)
	for y in gen.h:
		for x in gen.w:
			var tile: int = gen.grid[y][x]
			var pos := Vector2(x, y) * ts
			var h := _hash(x, y)
			if tile == gen.TILE_FLOOR:
				var col := floor_color if (x + y) % 2 == 0 else floor_color_alt
				var ref := floor_alt if (h % 5 == 0 and floor_alt != "") else floor_ref
				if ref == "":
					draw_rect(Rect2(pos, Vector2(ts, ts)), col)
				else:
					Assets.draw_ref(self, ref, pos + Vector2(ts, ts) * 0.5, float(ts),
							h % 7 == 0, col)
				# декали пола: крошка/трещина на каждом шестом тайле
				if h % 6 == 0:
					var dp := pos + Vector2(6.0 + float(h % (ts - 12)),
							6.0 + float((h / 3) % (ts - 12)))
					if h % 12 == 0:
						# трещина: пара коротких штрихов
						draw_line(dp, dp + Vector2(5.0, 3.0), Color(decor.r, decor.g, decor.b, 0.7), 1.2)
						draw_line(dp + Vector2(5.0, 3.0), dp + Vector2(8.0, 2.0),
								Color(decor.r, decor.g, decor.b, 0.55), 1.0)
					else:
						draw_circle(dp, 1.6 + float(h % 2), Color(decor.r, decor.g, decor.b, 0.5))
						draw_circle(dp + Vector2(3.0, -2.0), 1.0, Color(decor.r, decor.g, decor.b, 0.4))
			elif _near_floor[y][x]:
				# стена рядом с полом — видна (по ней читаются коридоры)
				draw_rect(Rect2(pos, Vector2(ts, ts)), wall_col.darkened(0.18))
				Assets.draw_ref(self, wall_ref, pos + Vector2(ts, ts) * 0.5, float(ts), false, wall_col)
			else:
				# глубинная порода вне коридоров и комнат — чернота без спрайта
				draw_rect(Rect2(pos, Vector2(ts, ts)), _void_col)


## Цвет hex, умноженный на k с сохранением пропорций каналов (кламп):
## светлее/темнее без увода в серый, как у lightened/darkened.
static func _scaled(hex: String, k: float) -> Color:
	var c := Color(hex)
	return Color(minf(1.0, c.r * k), minf(1.0, c.g * k), minf(1.0, c.b * k))


static func _hash(x: int, y: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, 1000)
