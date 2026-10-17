extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Лестница-выход из данжа (M1): спрайт-лестница Kenney (M9) с лёгким свечением.
## Выход доступен всегда.

var marker_color := Color("#d8c27a")


func _ready() -> void:
	var sprite := Sprite2D.new()
	var tex: Texture2D = Assets.sprite("k:65")
	sprite.texture = tex
	sprite.scale = Vector2.ONE * (30.0 / 16.0)
	sprite.position = Vector2(0, -4)
	add_child(sprite)


func _draw() -> void:
	# тёплое пятно под лестницей — выход видно в темноте
	var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 400.0)
	draw_circle(Vector2.ZERO, 15.0, Color(marker_color.r, marker_color.g, marker_color.b, 0.12 + 0.08 * pulse))
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 20, Color(marker_color.r, marker_color.g, marker_color.b, 0.5 * pulse), 1.5)
