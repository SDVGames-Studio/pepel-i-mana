extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Рунный круг на полу («Данжи v2», этап 4 «Мир v2»): интерактивная точка
## по поручению заказчика 2026-10-29. Пульсирует цветом школы магии героя,
## по E (через dungeon.gd) — вспышка: полное восстановление маны + боевой
## запал (временный бонус урона), одноразово. Параметры — dungeon.json →
## v2.rune. Логика активации вынесена в статический grant() для тестов.

signal activated(rune)

var used := false
var color := Color(0.62, 0.78, 1.0)
var radius_px := 30.0
var _time := 0.0


func setup(col: Color, interact_radius_px: float) -> void:
	color = col
	radius_px = interact_radius_px
	z_index = 5


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	# круг дышит: масштаб и свечение пульсом; использованный — тусклый серый
	var pulse := 1.0 + 0.05 * sin(_time * 2.2)
	var col := color if not used else Color(0.45, 0.45, 0.48)
	var alpha := 1.0 if not used else 0.55
	var size := 44.0 * pulse
	draw_circle(Vector2.ZERO, size * 0.62, Color(col.r, col.g, col.b, 0.10 * alpha))
	Assets.draw_ref(self, "e:d2_rune", Vector2.ZERO, size, false,
			Color(col.r, col.g, col.b, alpha))
	if not used:
		var glow := 0.5 + 0.5 * sin(_time * 2.2)
		draw_circle(Vector2.ZERO, 8.0 + 3.0 * glow,
				Color(col.r, col.g, col.b, 0.25 + 0.35 * glow))


## Активация: мана полностью + боевой запал (урон на N секунд). Чистая
## математика для тестов: hero — узел героя с mana/mana_max/bonus_damage.
static func grant(hero, cfg: Dictionary) -> Dictionary:
	var out := {"mana": 0, "buff": 0, "seconds": 0.0}
	if hero == null:
		return out
	var restore := int(cfg.get("mana_restore", 1))
	var buff := int(cfg.get("buff_damage", 2))
	var seconds := float(cfg.get("buff_seconds", 20.0))
	if restore > 0:
		hero.mana = hero.mana_cap()
		out["mana"] = hero.mana
	if buff > 0 and hero.has_method("temp_damage_bonus"):
		hero.temp_damage_bonus(seconds, buff)
		out["buff"] = buff
		out["seconds"] = seconds
	return out


## Герой рядом (E): тап по кругу радиусом ~1.5 тайла.
func hero_in_range(hero_pos: Vector2) -> bool:
	return not used and hero_pos.distance_to(global_position) <= radius_px


func activate(hero, cfg: Dictionary) -> Dictionary:
	if used:
		return {}
	used = true
	var res := grant(hero, cfg)
	activated.emit(self)
	return res
