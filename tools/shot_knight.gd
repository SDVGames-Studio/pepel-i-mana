extends SceneTree
## Снимок героя v2.9: 8 анимаций из build_knight_frames в ряд.
## Запуск ОКОННО: godot --path . --script res://tools/shot_knight.gd

var _f := 0


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.14)
	bg.size = Vector2(1360, 260)
	root.add_child(bg)
	var sf: SpriteFrames = load("res://scripts/hero.gd").build_knight_frames()
	var names := ["idle", "run", "run_up", "run_down", "attack", "cast", "death", "roll"]
	for i in names.size():
		var s := AnimatedSprite2D.new()
		s.sprite_frames = sf
		s.play(String(names[i]))
		s.position = Vector2(95 + i * 160, 130)
		s.scale = Vector2(1.7, 1.7)
		root.add_child(s)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	if _f == 40:
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png("res://tools/shot_knight.png")
			print("shot_knight: сохранён")
		quit(0)
