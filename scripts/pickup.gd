extends Area2D
## Подбираемый объект (M1): кристалл маны или выпавший предмет.
## Подбор автоматический при касании героя.

signal collected(pickup: Node)

var kind := "mana"    # "mana" | "item"
var item_id := ""


func setup(new_kind: String, new_item_id: String) -> void:
	kind = new_kind
	item_id = new_item_id


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("hero"):
		return
	collected.emit(self)
	queue_free()


func _draw() -> void:
	if kind == "mana":
		draw_circle(Vector2.ZERO, 7.0, Color("#5aa0ff"))
		draw_circle(Vector2.ZERO, 3.0, Color("#a8ccff"))
	else:
		draw_rect(Rect2(-6, -6, 12, 12), Color("#d0a040"))
		draw_rect(Rect2(-6, -6, 12, 12), Color(0, 0, 0, 0.4), false, 1.5)
