extends CharacterBody2D
const Assets := preload("res://scripts/assets.gd")
## Враг данжа (M1): преследует героя в радиусе агро, бьёт в упор по кулдауну.
## M3: магические уязвимости (weak_school — урон школы ×2), антимаги immune
## (magic_immune — магия не действует), стан от корней.
## Параметры — из data/enemies.json, без цифр в коде.

signal died(enemy: Node)

var p: Dictionary = {}
var hp := 1
var hero = null            # ссылка на героя — динамическая (свойства задаёт hero.gd)
var stun_left := 0.0

var _attack_timer := 0.0
var _hit_flash := 0.0
var _slow_left := 0.0      # маяк света (M7): враг ползёт медленнее
var _slow_mult := 1.0
var _sprite: Sprite2D = null
var _base_tint := Color.WHITE
var _bob_time := 0.0
var _anim_time := 0.0      # кадры листа (M10)
var _dir := "front"        # направление анимации листа (M10)


## Вызвать до add_child: строка из data/enemies.json.
func setup(data: Dictionary) -> void:
	p = data
	hp = int(p["hp"])


## Расчёт магического урона: уязвимая школа ×2, антимаг — 0. Статика — для headless-тестов.
static func calc_spell_damage(data: Dictionary, base: int, school: String) -> int:
	if bool(data.get("magic_immune", false)):
		return 0
	if school != "" and String(data.get("weak_school", "")) == school:
		return base * 2
	return base


func stun_for(seconds: float) -> void:
	stun_left = seconds
	queue_redraw()


## Замедление (маяк света, M7): mult < 1 — во столько раз медленнее.
func slow_for(seconds: float, mult: float) -> void:
	_slow_left = seconds
	_slow_mult = mult
	queue_redraw()


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
	# спрайт врага (M9): ссылка из data/enemies.json, лёгкая подкраска цветом врага
	_sprite = Sprite2D.new()
	var sheet: String = String(p.get("sheet", ""))
	var tex: Texture2D
	if sheet != "":
		# лист анимаций (M10): полный PNG + hframes/vframes, кадр выбираем в апдейте
		var info: Array = Assets.SHEETS[sheet + "_walk"]
		tex = Assets.tex(String(info[0]))
		_sprite.hframes = int(info[3])
		_sprite.vframes = int(info[4])
	else:
		tex = Assets.sprite(String(p.get("sprite", "")))
	if tex != null:
		var h := float(p["radius"]) * 2.8
		_sprite.texture = tex
		_sprite.scale = Vector2.ONE * (h / float(tex.get_height()) * float(_sprite.vframes))
		_sprite.position = Vector2(0, -h * 0.12)
		var col := Color(String(p["color"]))
		_base_tint = Color.WHITE.lerp(col, 0.25)
		_sprite.modulate = _base_tint
	add_child(_sprite)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
	# вспышка урона (M9): спрайт светлеет и гаснет без перерисовки _draw
	if _sprite != null:
		var k := clampf(_hit_flash / 0.2, 0.0, 1.0)
		_sprite.modulate = _base_tint.lerp(Color(3, 3, 3), k * 0.8)
		var moving := velocity.length() > 5.0
		_bob_time += delta * (10.0 if moving else 2.5)
		_sprite.position.y = -float(p["radius"]) * 0.34 - absf(sin(_bob_time)) * (1.4 if moving else 0.6)
		var sheet: String = String(p.get("sheet", ""))
		if sheet != "":
			# покадровая анимация (M10): кадры walk/idle, ряд по направлению
			_anim_time += delta
			if absf(velocity.x) >= absf(velocity.y) and absf(velocity.x) > 1.0:
				_dir = "left" if velocity.x < 0.0 else "right"
			elif absf(velocity.y) > 1.0:
				_dir = "back" if velocity.y < 0.0 else "front"
			var row := 0
			match _dir:
				"back": row = 1
				"left": row = 2
				"right": row = 3
			var anim := "walk" if moving else "idle"
			var cols := 6 if moving else 4
			_sprite.texture = Assets.sheet_frame(sheet + "_" + anim, row * cols + int(_anim_time * 8.0) % cols)
		elif absf(velocity.x) > 1.0:
			_sprite.flip_h = velocity.x < 0.0
	if stun_left > 0.0:
		stun_left = maxf(0.0, stun_left - delta)
		velocity = Vector2.ZERO
		move_and_slide()
		if stun_left <= 0.0:
			queue_redraw()
		return
	if hero == null or not is_instance_valid(hero) or hero.dead:
		velocity = Vector2.ZERO
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	var was_slow := _slow_left > 0.0
	_slow_left = maxf(0.0, _slow_left - delta)
	if was_slow and _slow_left <= 0.0:
		queue_redraw()
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
	if _slow_left > 0.0:
		velocity *= _slow_mult
	move_and_slide()


func take_damage(dmg: int, school := "") -> void:
	if hp <= 0:
		return
	if school != "":
		dmg = calc_spell_damage(p, dmg, school)
		if dmg <= 0:
			# антимаг: магия не действует, короткая вспышка-подсказка
			_hit_flash = 0.25
			queue_redraw()
			return
	hp -= dmg
	_hit_flash = 0.2
	queue_redraw()
	if hp <= 0:
		died.emit(self)
		queue_free()


func _draw() -> void:
	# тело врага — спрайт (M9); здесь только hp-бар и статусные дуги
	if hp < int(p["hp"]):
		var frac := clampf(float(hp) / float(p["hp"]), 0.0, 1.0)
		var bar_y := -float(p["radius"]) - 8.0
		draw_rect(Rect2(-12, bar_y, 24, 4), Color(0.15, 0.1, 0.1))
		draw_rect(Rect2(-12, bar_y, 24.0 * frac, 4), Color(0.9, 0.25, 0.25))
	if stun_left > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 4.0, 0.0, TAU, 20, Color(0.4, 0.85, 0.4, 0.8), 2.0)
	elif _slow_left > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 4.0, 0.0, TAU, 20, Color(1.0, 0.9, 0.4, 0.7), 2.0)
