extends "res://tests/test_base.gd"
## v2.9 «Рыцарь-герой» (релиз 2.9.0): листы заказчика 26.11 («главный
## герой») нарезаны в полосы knight_*.png — айдл/бег вбок/вверх/ВНИЗ
## (анфас, был профиль)/удар с дугой/каст крови/падение/рывок; клетки 120x80.

const HERO := preload("res://scripts/hero.gd")
const AssetsScript := preload("res://scripts/assets.gd")


func _test_strips() -> void:
	print("[v2.9: полосы рыцаря]")
	for name in ["knight_Idle", "knight_Run", "knight_RunUp", "knight_RunDown",
			"knight_Attack", "knight_Cast", "knight_Death", "knight_Roll"]:
		var t: Texture2D = AssetsScript.tex("res://assets/sprites/hero/%s.png" % name)
		_check(t != null, "полоса %s на месте" % name)
		if t != null:
			_check(int(t.get_width()) % 120 == 0 and int(t.get_width()) >= 720,
					"полоса %s — %dpx, кратно 120 (>= 6 кадров)" % [name, int(t.get_width())])


func _test_frames() -> void:
	print("[v2.9: анимации героя]")
	var sf: SpriteFrames = HERO.build_knight_frames()
	for anim in ["idle", "run", "run_up", "run_down", "attack", "cast", "death", "roll"]:
		_check(sf.has_animation(anim), "анимация %s есть" % anim)
		if sf.has_animation(anim):
			_check(sf.get_frame_count(anim) >= 6,
					"анимация %s — %d кадров (>= 6)" % [anim, sf.get_frame_count(anim)])
	# run_down теперь анфас (knight_RunDown), не профиль knight_Run
	var down: Texture2D = AssetsScript.tex("res://assets/sprites/hero/knight_RunDown.png")
	var run: Texture2D = AssetsScript.tex("res://assets/sprites/hero/knight_Run.png")
	_check(down != null and run != null and down != run,
			"бег вниз — отдельная полоса knight_RunDown, не профиль")
