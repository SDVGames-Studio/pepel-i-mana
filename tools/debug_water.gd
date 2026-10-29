extends SceneTree
## Отладка воды v1.30: компоненты воды по сидам — размеры, типы, свamps.

func _init() -> void:
	var cfg: Dictionary = _read_json("res://data/city.json")
	for seed_i in 8:
		var m = load("res://scripts/city_map.gd").new()
		m.generate(1000 + seed_i * 37, cfg)
		var seen := {}
		var kinds := {"lake": 0, "river": 0, "swamp": 0}
		var sizes := []
		for y in m.h:
			for x in m.w:
				var t := Vector2i(x, y)
				if m.grid[t.y][t.x] != m.TILE_WATER or seen.has(t):
					continue
				var comp: Array = [t]
				seen[t] = true
				var mn: Vector2i = t
				var mx: Vector2i = t
				var qi := 0
				while qi < comp.size():
					var c: Vector2i = comp[qi]
					qi += 1
					mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
					mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var n: Vector2i = c + d
						if m.in_bounds(n) and m.grid[n.y][n.x] == m.TILE_WATER and not seen.has(n):
							seen[n] = true
							comp.append(n)
				var kind: String = m.water_kind_at(t)
				kinds[kind] = int(kinds[kind]) + 1
				sizes.append("%s(%d)" % [kind.substr(0, 1), comp.size()])
		print("seed ", 1000 + seed_i * 37, ": ", kinds, " ", sizes)
	quit()


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else null
