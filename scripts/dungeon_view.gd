extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Отрисовка тайлов данжа (M1→M9): спрайты Kenney Tiny Dungeon 16×16 (×2),
## подкрашенные цветами биома. Спрайты статичны — перерисовка один раз на забег.

var gen: Object = null
var ts := 32
var biome: Dictionary = {}


func setup(dungeon_gen: Object, tile_size: int, biome_data: Dictionary) -> void:
	gen = dungeon_gen
	ts = tile_size
	biome = biome_data
	queue_redraw()


func _draw() -> void:
	if gen == null:
		return
	var wall_col := Color(String(biome["wall_color"]))
	draw_rect(Rect2(0, 0, gen.w * ts, gen.h * ts), Color(String(biome["bg_color"])))
	var floor_ref := String(biome.get("floor_sprite", ""))
	var wall_ref := String(biome.get("wall_sprite", ""))
	# v1.28: альтернативная плита пола и декали (трещины/крошка) — полы и
	# стены различаются между биомами (заказчик)
	var floor_alt := String(biome.get("floor_sprite_alt", floor_ref))
	var decor := Color(String(biome.get("decor_color", "#555048")))
	var floor_color := Color(String(biome["floor_color"]))
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
			else:
				draw_rect(Rect2(pos, Vector2(ts, ts)), wall_col.darkened(0.25))
				Assets.draw_ref(self, wall_ref, pos + Vector2(ts, ts) * 0.5, float(ts), false, wall_col)


static func _hash(x: int, y: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, 1000)
