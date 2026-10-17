extends Area2D
const Assets := preload("res://scripts/assets.gd")
## Подбираемый объект (M1): кристалл маны или выпавший предмет.
## Подбор автоматический при касании героя.

signal collected(pickup: Node)

var kind := "mana"    # "mana" | "item"
var item_id := ""
var sprite_ref := ""  # ссылка Kenney "k:N" (M9) — задаётся при создании
var _sprite: Sprite2D = null
var _bob := 0.0


func setup(new_kind: String, new_item_id: String, new_sprite := "") -> void:
	kind = new_kind
	item_id = new_item_id
	sprite_ref = new_sprite


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	if sprite_ref != "":
		var tex: Texture2D = Assets.sprite(sprite_ref)
		if tex != null:
			_sprite = Sprite2D.new()
			_sprite.texture = tex
			_sprite.scale = Vector2.ONE * (22.0 / 16.0)
			_sprite.position = Vector2(0, -6)
			add_child(_sprite)
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("hero"):
		return
	collected.emit(self)
	queue_free()


func _process(delta: float) -> void:
	# бобинг лута (M9): предмет слегка парит
	if _sprite != null:
		_bob += delta * 3.0
		_sprite.position.y = -6.0 - sin(_bob) * 2.0


func _draw() -> void:
	if _sprite != null:
		return  # тело — спрайт
	if kind == "mana":
		draw_circle(Vector2.ZERO, 7.0, Color("#5aa0ff"))
		draw_circle(Vector2.ZERO, 3.0, Color("#a8ccff"))
	else:
		draw_rect(Rect2(-6, -6, 12, 12), Color("#d0a040"))
		draw_rect(Rect2(-6, -6, 12, 12), Color(0, 0, 0, 0.4), false, 1.5)
