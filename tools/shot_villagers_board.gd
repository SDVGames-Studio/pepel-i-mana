extends Node2D
## Доска профессий для shot_villagers.gd: сетка 4×4, каждая ячейка —
## профессия в трёх позах (покой/шаг/работа), подпись — id профессии.

const PROFS := [
	"builder", "lumberjack", "farmer", "miner",
	"smith", "smelter", "armorer", "hunter",
	"porter", "bartender", "trader", "healer",
	"acolyte", "guard", "crafter", "fisher",
	"elder",
]

const CELL := Vector2(190.0, 150.0)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in range(PROFS.size()):
		var prof: String = PROFS[i]
		var org := Vector2(30.0, 60.0) + Vector2(
				float(i % 4) * CELL.x, float(i / 4) * CELL.y)
		draw_string(font, org + Vector2(0.0, -8.0), prof,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.85, 0.7))
		draw_line(org + Vector2(-6.0, 0.0), org + Vector2(CELL.x - 40.0, 0.0),
				Color(1.0, 1.0, 1.0, 0.15), 1.0)
		var poses := [[false, false], [true, false], [false, true]]
		for p in range(poses.size()):
			var pos: Vector2 = org + Vector2(26.0 + 38.0 * float(p), 34.0)
			Assets.draw_villager(self, prof, "right", poses[p][0],
					poses[p][1], pos, 0.35 + 0.21 * float(p))
