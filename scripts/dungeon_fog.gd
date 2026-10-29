extends Node2D
## Туман войны данжа (v1.33): неисследованное — ЧЁРНОЕ, изученное —
## приглушённая «память», видимое сейчас (свет героя) — без затемнения.
## Рисуется поверх мира (после всех узлов данжа, до HUD) прямоугольниками:
## пол — по словарям visited/visible_now; стена — открыта, если открыт
## соседний пол; глубинный войд уже чёрный в dungeon_view — не трогаем.
## Порядок инициализации: dungeon.gd создаёт после _build_fauna() и
## обновляет словари из _update_fog() (перерисовка только по изменению).

var gen = null
var ts := 32
var visited: Dictionary = {}      # изученные полы (накопительно)
var visible_now: Dictionary = {}  # полы в поле зрения героя сейчас
# «память»: изученное вне света темнее живого обзора, но читается
# (v1.33.1: 0.45 — на тёмной реалистичной базе память не проваливается
# в черноту, силуэты коридоров остаются ориентиром)
const MEMORY_ALPHA := 0.45


func setup(dungeon_gen: Object, tile_size: int) -> void:
	gen = dungeon_gen
	ts = tile_size
	z_index = 40


func _draw() -> void:
	if gen == null:
		return
	var black := Color(0.008, 0.008, 0.014)
	var mem := Color(black.r, black.g, black.b, MEMORY_ALPHA)
	for y in gen.h:
		for x in gen.w:
			var t := Vector2i(x, y)
			var pos := Vector2(x, y) * ts
			var rect := Rect2(pos, Vector2(ts, ts))
			if gen.is_floor(t):
				if visible_now.has(t):
					continue
				if visited.has(t):
					draw_rect(rect, mem)
				else:
					draw_rect(rect, black)
				continue
			# стена/войд: интересны только стены при полу (глубинная порода
			# уже нарисована чёрной — сверху ничего не нужно)
			if not _near_floor(t):
				continue
			if _any_neighbor(t, visible_now):
				continue
			if _any_neighbor(t, visited):
				draw_rect(rect, mem)
			else:
				draw_rect(rect, black)


func _near_floor(t: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if gen.is_floor(t + Vector2i(dx, dy)):
				return true
	return false


func _any_neighbor(t: Vector2i, set: Dictionary) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if set.has(t + Vector2i(dx, dy)):
				return true
	return false
