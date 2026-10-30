extends RefCounted
## БОЛОТО — рендер и настройка (v1.34.2, выделено из city_terrain.gd).
## Один тип воды — один файл (правило заказчика), тюнинг без кода.
##
## Тюнинг: data/city.json → colors → "water_tune" → "swamp":
##   color   — цвет топи (мутная зелёно-бурая жижа)
##   edge    — затемнение кромки плитки (0…0.5)
##   puddle  — цвет лужи-оконца
##   tussock — цвет кочек
## Болото рисуется ЧЕСТНЫМИ квадратными тайлами — сглаживанию мелкие
## кляксы не идут (замечание заказчика 2026-10-28).

var t   # city_terrain — контекст (drawer, map, цвета, геометрия блобов)


func setup(terrain: Node) -> void:
	t = terrain


func opt(key: String, def: String) -> Color:
	return Color(String(t.colors.get("water_tune", {}).get("swamp", {}).get(key, def)))


## Топь: тёмная трясина без синевы (v1.30.1), лужи-оконца, кочки, камыши.
func draw_blobs(ts: float) -> void:
	var fill_c := opt("color", "#46523a")
	var puddle_c := opt("puddle", "#28322a")
	var tussock_c := opt("tussock", "#6a7548")
	var edge := float(t.colors.get("water_tune", {}).get("swamp", {}).get("edge", 0.25))
	for entry in t._water_cached:
		if String(entry["kind"]) != "swamp":
			continue
		for tk: Vector2i in entry["tiles"]:
			var rect := Rect2(Vector2(tk) * ts, Vector2(ts, ts))
			var tone := 0.05 * float(t._hash(tk.x, tk.y, 5) - 2)
			var fill := fill_c.lightened(tone)
			t._drawer.draw_rect(rect, fill)
			t._drawer.draw_rect(rect, fill.darkened(edge), false, 1.5)
			var hx: int = t._hash(tk.x * 3, tk.y * 7, 100)
			if hx % 3 == 0:
				# лужа-оконце: тёмная стоячая вода с бликом
				var pc := rect.position + Vector2(6.0 + float(hx % int(ts - 14.0)),
						6.0 + float((hx / 5) % int(ts - 14.0)))
				t._drawer.draw_circle(pc, ts * 0.16, puddle_c)
				t._drawer.draw_circle(pc + Vector2(-1.0, -1.0), ts * 0.07, puddle_c.lightened(0.35))
			for i in 1 + hx % 2:
				var h2: int = t._hash(tk.x * 7 + i, tk.y * 13 + i, 100)
				var c := rect.position + Vector2(6.0 + float(h2 % int(ts - 12.0)),
						6.0 + float((h2 / 5) % int(ts - 12.0)))
				t._drawer.draw_circle(c, 2.6 + float(h2 % 2), tussock_c)
				t._drawer.draw_circle(c + Vector2(-0.8, -0.8), 1.2, tussock_c.lightened(0.15))
			if t._hash(tk.x, tk.y * 3, 4) == 0:
				t._draw_reeds(rect.position, ts, tk.x, tk.y)
