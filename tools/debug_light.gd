extends SceneTree
## Репро: освещаются ли PointLight2D разные СПОСОБЫ отрисовки тайлов?
## A: draw_rect цвета | B: draw_texture_rect_region (атлас Kenney, как Assets)
## C: draw_texture_rect белой ImageTexture | D: спрайт-нод Sprite2D
## Запуск: godot --path . --script res://tools/debug_light.gd

var _frames := 0


class Paint:
	extends Node2D
	var atlas: Texture2D = null
	var white: Texture2D = null
	func _draw() -> void:
		# A: чистые прямоугольники
		draw_rect(Rect2(60, 200, 300, 300), Color(0.61, 0.58, 0.54))
		# B: атлас-регион (тайл k:13)
		if atlas != null:
			@warning_ignore("integer_division")
			var src := Rect2((13 % 12) * 16, 13 / 12 * 16, 16, 16)
			for ty in 4:
				for tx in 4:
					draw_texture_rect_region(atlas,
							Rect2(420 + tx * 32, 200 + ty * 32, 32, 32), src,
							Color("#9c948a"))
		# C: белая текстура
		if white != null:
			draw_texture_rect(white, Rect2(780, 200, 300, 300), false,
					Color(0.61, 0.58, 0.54))
		# E: белый ImageTexture ЧЕРЕЗ region-команду (как B)
		if white != null:
			draw_texture_rect_region(white, Rect2(420, 560, 300, 300),
					Rect2(0, 0, 64, 64), Color(0.61, 0.58, 0.54))
		# F: атлас ЦЕЛИКОМ через простую команду (как C)
		if atlas != null:
			draw_texture_rect(atlas, Rect2(780, 560, 192, 176), false,
					Color(0.61, 0.58, 0.54))


func _initialize() -> void:
	var p := Paint.new()
	p.atlas = load("res://assets/sprites/kenney.png")
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	p.white = ImageTexture.create_from_image(img)
	root.add_child(p)
	# D: спрайт-нод
	var sp := Sprite2D.new()
	sp.texture = p.white
	sp.modulate = Color(0.61, 0.58, 0.54)
	sp.scale = Vector2(300.0 / 64.0, 300.0 / 64.0)
	sp.position = Vector2(1140 + 150, 200 + 150)
	root.add_child(sp)
	# свет с центром между зонами
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.9, 0.7), Color(0.7, 0.5, 0.3), Color(0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	var light := PointLight2D.new()
	light.texture = tex
	light.texture_scale = 600.0 * 2.0 / 256.0
	light.color = Color(1.0, 0.85, 0.6)
	light.energy = 1.4
	light.position = Vector2(700, 350)
	root.add_child(light)
	var cm := CanvasModulate.new()
	cm.color = Color(0.5, 0.5, 0.57)
	root.add_child(cm)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 30:
		root.get_texture().get_image().save_png("res://tools/light_on.png")
		# выключить свет и снять контрольный кадр
		for c in root.get_children():
			if c is PointLight2D:
				c.visible = false
		_light_off = true
	elif _frames == 50 and _light_off:
		root.get_texture().get_image().save_png("res://tools/light_off.png")
		quit(0)

var _light_off := false
