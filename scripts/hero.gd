extends CharacterBody2D
## Герой (M1): движение WASD/стрелки, уворот-отпрыг на Space,
## удар ближнего боя ЛКМ в сторону курсора. Примитивы вместо спрайтов — арт в M8.

signal died

var p: Dictionary = {}            # параметры из data/dungeon.json -> "hero"
var hp := 1
var mana := 0
var facing := Vector2.RIGHT
var dead := false
var city_mode := false            # в городе: только ходьба, без боя и рывка

var _dash_left := 0.0
var _dash_cd := 0.0
var _attack_cd := 0.0
var _invuln := 0.0
var _lantern: PointLight2D = null
var _flicker_time := 0.0

const LANTERN_ENERGY := 1.15


## Вызвать до add_child: параметры героя и стартовая мана.
func setup(hero_params: Dictionary, start_mana: int) -> void:
	p = hero_params
	hp = int(p["hp"])
	mana = start_mana


func _ready() -> void:
	add_to_group("hero")
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = float(p["radius"])
	shape.shape = circle
	add_child(shape)
	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.zoom = Vector2(2, 2)
	add_child(cam)
	cam.make_current()
	queue_redraw()


## Границы карты, чтобы камера не показывала пустоту за краем.
func set_camera_limits(rect: Rect2) -> void:
	var cam: Camera2D = get_node("Camera")
	cam.limit_left = int(rect.position.x)
	cam.limit_top = int(rect.position.y)
	cam.limit_right = int(rect.end.x)
	cam.limit_bottom = int(rect.end.y)


## Фонарь героя: данж погашен (CanvasModulate в сцене данжа).
## Тёплый «факельный» свет с резким спадом и тенями от стен:
## за стенами (соседние комнаты, коридоры) света не видно.
func make_light(radius_px: float) -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.85),
		Color(0.95, 0.85, 0.68),
		Color(0.35, 0.28, 0.2),
		Color(0, 0, 0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	var light := PointLight2D.new()
	light.name = "Lantern"
	light.texture = tex
	light.texture_scale = radius_px * 2.0 / 256.0
	light.color = Color(1.0, 0.87, 0.68)
	light.energy = LANTERN_ENERGY
	light.shadow_enabled = true
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	add_child(light)
	_lantern = light


func _physics_process(delta: float) -> void:
	if dead:
		return
	_flicker_time += delta
	if _lantern != null:
		# дыхание факела: лёгкое неровное мерцание яркости
		_lantern.energy = LANTERN_ENERGY * (0.94
				+ 0.045 * absf(sin(_flicker_time * 8.0))
				+ 0.03 * absf(sin(_flicker_time * 21.7)))
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if city_mode:
		velocity = dir * float(p["speed"])
		move_and_slide()
		return
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0 and dir != Vector2.ZERO:
		_dash_left = float(p["dash_time"])
		_dash_cd = float(p["dash_cooldown"])
	if _dash_left > 0.0:
		_dash_left -= delta
		# отпрыг на фиксированную дистанцию от точки старта (об стену останавливается)
		var dash_speed := float(p["dash_distance"]) / float(p["dash_time"])
		velocity = facing * dash_speed
	else:
		velocity = dir * float(p["speed"])
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if city_mode:
		return
	if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
		try_attack()


## Удар ближнего боя: дуга перед героем в сторону курсора мыши.
func try_attack() -> void:
	if _attack_cd > 0.0 or dead:
		return
	_attack_cd = float(p["attack_cooldown"])
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		facing = to_mouse.normalized()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > float(p["attack_range"]) + float(enemy.p["radius"]):
			continue
		if absf(facing.angle_to(to_enemy)) > deg_to_rad(float(p["attack_arc"])) / 2.0:
			continue
		enemy.take_damage(int(p["damage"]))
	queue_redraw()
	get_tree().create_timer(0.15).timeout.connect(queue_redraw)


func take_damage(dmg: int) -> void:
	if _invuln > 0.0 or dead:
		return
	hp = maxi(0, hp - dmg)
	_invuln = 0.5
	queue_redraw()
	if hp <= 0:
		dead = true
		died.emit()


## Тик мана-голода: true — мана была и утекла, false — мана уже на нуле.
func drain_mana() -> bool:
	if mana <= 0:
		return false
	mana -= 1
	return true


func add_mana(v: int) -> void:
	mana = mini(int(p["mana"]), mana + v)


## Доля восстановления рывка 0..1 — для полосы HUD.
func dash_ready_fraction() -> float:
	if _dash_cd <= 0.0:
		return 1.0
	return 1.0 - _dash_cd / float(p["dash_cooldown"])


func _draw() -> void:
	draw_circle(Vector2.ZERO, float(p["radius"]), Color("#e0b060"))
	draw_circle(Vector2.ZERO, float(p["radius"]) * 0.5, Color("#b5884a"))
	# короткий взмах сразу после удара
	if _attack_cd > float(p["attack_cooldown"]) - 0.15:
		draw_line(Vector2.ZERO, facing * float(p["attack_range"]), Color(1.0, 0.9, 0.6, 0.8), 3.0)
	if _invuln > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 3.0, 0.0, TAU, 24, Color(1, 1, 1, 0.4), 1.5)
