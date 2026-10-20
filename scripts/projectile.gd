extends Node2D
## Снаряд (M14-B герой / M14-D враги): стрела лука, заряд посоха, болт лича.
## Летит по прямой, первая цель из target_group на пути получает урон;
## стена (solid_check от сцены) гасит снаряд.

var vel := Vector2.ZERO
var damage := 1
var range_left := 200.0
var col := Color(1.0, 0.9, 0.55)
var solid_check := Callable()     # сцена передаёт func(pos: Vector2) -> bool (стена?)
var hero_radius := 10.0
var target_group := "enemies"     # чьих целей задеваем (враги → "enemies", герой → "hero")

var _life := 3.0


func setup(from: Vector2, dir: Vector2, speed: float, max_range: float,
		dmg: int, color: Color, from_radius := 10.0) -> void:
	position = from
	vel = dir.normalized() * speed
	range_left = max_range
	damage = dmg
	col = color
	hero_radius = from_radius


func _physics_process(delta: float) -> void:
	var step := vel * delta
	position += step
	range_left -= step.length()
	_life -= delta
	if range_left <= 0.0 or _life <= 0.0:
		queue_free()
		return
	if solid_check.is_valid() and bool(solid_check.call(global_position)):
		queue_free()
		return
	for target in get_tree().get_nodes_in_group(target_group):
		if global_position.distance_to(target.global_position) <= float(target.p["radius"]) + 6.0:
			target.take_damage(damage)
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	draw_line(Vector2.ZERO - vel.normalized() * 8.0, Vector2.ZERO, col, 2.5)
	draw_circle(Vector2.ZERO, 2.5, col)
