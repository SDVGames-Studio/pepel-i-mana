extends CharacterBody2D
## Враг данжа (M1): преследует героя в радиусе агро, бьёт в упор по кулдауну.
## Параметры — из data/enemies.json, без цифр в коде.

signal died(enemy: Node)

var p: Dictionary = {}
var hp := 1
var hero = null            # ссылка на героя — динамическая (свойства задаёт hero.gd)

var _attack_timer := 0.0


## Вызвать до add_child: строка из data/enemies.json.
func setup(data: Dictionary) -> void:
	p = data
	hp = int(p["hp"])


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 2
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = float(p["radius"])
	shape.shape = circle
	add_child(shape)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if hero == null or not is_instance_valid(hero) or hero.dead:
		velocity = Vector2.ZERO
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	var to_hero: Vector2 = hero.global_position - global_position
	var dist: float = to_hero.length()
	if dist <= float(p["attack_range"]) + float(hero.p["radius"]):
		velocity = Vector2.ZERO
		if _attack_timer <= 0.0:
			_attack_timer = float(p["attack_cooldown"])
			hero.take_damage(int(p["damage"]))
	elif dist <= float(p["aggro"]):
		velocity = to_hero.normalized() * float(p["speed"])
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func take_damage(dmg: int) -> void:
	if hp <= 0:
		return
	hp -= dmg
	queue_redraw()
	if hp <= 0:
		died.emit(self)
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, float(p["radius"]), Color(String(p["color"])))
	if hp < int(p["hp"]):
		var frac := clampf(float(hp) / float(p["hp"]), 0.0, 1.0)
		var bar_y := -float(p["radius"]) - 8.0
		draw_rect(Rect2(-12, bar_y, 24, 4), Color(0.15, 0.1, 0.1))
		draw_rect(Rect2(-12, bar_y, 24.0 * frac, 4), Color(0.9, 0.25, 0.25))
