extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Сундук (M1): спрайт Kenney (M9), при открытии — крышка сдвигается (бобинг-приём).
## Открытие через сцену данжа (E рядом).

var open := false
var _sprite: Sprite2D = null


func _ready() -> void:
	_sprite = Sprite2D.new()
	var tex: Texture2D = Assets.sprite("k:90")
	_sprite.texture = tex
	_sprite.scale = Vector2.ONE * (30.0 / 16.0)
	_sprite.position = Vector2(0, -5)
	add_child(_sprite)


func _draw() -> void:
	if open and _sprite != null:
		# «открыто»: спрайт серого сундука приподнят и пригашен
		_sprite.texture = Assets.sprite("k:91")
		_sprite.position.y = -9.0
		_sprite.modulate = Color(0.85, 0.8, 0.7)
