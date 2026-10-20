extends CharacterBody2D
const Assets := preload("res://scripts/assets.gd")
## Враг данжа (M1): преследует героя в радиусе агро, бьёт в упор по кулдауну.
## M3: магические уязвимости (weak_school — урон школы ×2), антимаги immune
## (magic_immune — магия не действует), стан от корней.
## M14-B (анти-кайт, issue #3 T06): пока герой бьёт безнаказанно, копится
## счётчик «удары без ответа»; на пороге — телеграф (враг вспыхивает красным,
## замирает) и рывок с атакой. Порог/тайминги/кулдаун — balance.json.
## Параметры — из data/enemies.json, без цифр в коде.

signal died(enemy: Node)

static var _ak: Dictionary = {}   # кэш balance.json -> anti_kite (тесты подменяют)

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
var _base_sheet_scale := Vector2.ONE   # масштаб кадра полного листа (M12: подмена листа)
var _bob_time := 0.0
var _anim_time := 0.0      # кадры листа (M10)
var _dir := "front"        # направление анимации листа (M10)
var patrol: PackedVector2Array = PackedVector2Array()  # точки патруля стражи гнезда (M12)
var _patrol_i := 0
# --- анти-кайт (M14-B) ---
var _unanswered := 0        # удары героя без ответа
var _telegraph_left := 0.0  # замер перед рывком (враг вспыхивает)
var _dash_left := 0.0       # длительность рывка
var _dash_cd := 0.0
var _dash_dir := Vector2.ZERO
var _heal_flash := 0.0      # вспышка лечения (вампир пьёт жизнь, M14-D)


## Вызвать до add_child: строка из data/enemies.json.
func setup(data: Dictionary) -> void:
	p = data
	hp = int(p["hp"])


## Конфиг анти-кайта (balance.json -> anti_kite); читается один раз.
static func anti_kite_cfg() -> Dictionary:
	if _ak.is_empty():
		var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_ak = parsed.get("anti_kite", {})
	return _ak


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
		_base_sheet_scale = _sprite.scale
		_sprite.position = Vector2(0, -h * 0.12)
		var col := Color(String(p["color"]))
		_base_tint = Color.WHITE.lerp(col, 0.25)
		_sprite.modulate = _base_tint
	add_child(_sprite)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_heal_flash = maxf(0.0, _heal_flash - delta)
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
			# M12: кадр переключается frame_coords на ПОЛНОМ листе. Прежний вариант
			# клал AtlasTexture-кадр в спрайт с сеткой hframes×vframes — Sprite2D
			# делил и без того вырезанный кадр, рисуя пустой угол («невидимые
			# бандиты»). Лист walk/idle — разные PNG: подмена texture целиком
			# с сеткой этого листа, масштаб кадра не меняется.
			var info: Array = Assets.SHEETS[sheet + "_" + anim]
			var full: Texture2D = Assets.tex(String(info[0]))
			if _sprite.texture != full:
				_sprite.texture = full
				_sprite.hframes = int(info[3])
				_sprite.vframes = int(info[4])
				_sprite.scale = _base_sheet_scale
			_sprite.frame_coords = Vector2i(int(_anim_time * 8.0) % cols, row)
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
	_tick_anti_kite(delta, dist)
	if _telegraph_left > 0.0 or _dash_left > 0.0:
		move_and_slide()
		return
	if dist <= float(p["attack_range"]) + float(hero.p["radius"]):
		velocity = Vector2.ZERO
		if _attack_timer <= 0.0:
			_attack_timer = float(p["attack_cooldown"])
			_attack_hero()
	elif dist <= float(p["aggro"]):
		if float(p.get("projectile_speed", 0.0)) > 0.0:
			# стрелок (лич/скелет-маг, M14-D): стоит и стреляет
			velocity = Vector2.ZERO
			if _attack_timer <= 0.0:
				_attack_timer = float(p["attack_cooldown"])
				_shoot_hero()
		else:
			velocity = to_hero.normalized() * float(p["speed"])
	elif not patrol.is_empty():
		# стража гнезда патрулирует (M12): ходит по точкам, пока герой далеко
		var goal: Vector2 = patrol[_patrol_i]
		if global_position.distance_to(goal) < 12.0:
			_patrol_i = (_patrol_i + 1) % patrol.size()
			goal = patrol[_patrol_i]
		velocity = (goal - global_position).normalized() * float(p["speed"]) * 0.5
	else:
		velocity = Vector2.ZERO
	if _slow_left > 0.0:
		velocity *= _slow_mult
	move_and_slide()


## --- анти-кайт (M14-B, T06): телеграф и рывок с атакой ---------------------

## Удар в упор (M14-D): урон герою; вампир лечится на долю урона (lifesteal).
## Отдельный метод — для headless-тестов.
func _attack_hero() -> void:
	hero.take_damage(int(p["damage"]))
	# враг ответил — счётчик безнаказанных ударов обнуляется (T06)
	_unanswered = 0
	var ls := float(p.get("lifesteal", 0.0))
	if ls > 0.0 and hp > 0:
		var max_hp := int(p["hp"])
		if hp < max_hp:
			hp = mini(max_hp, hp + maxi(1, int(round(float(p["damage"]) * ls))))
			_heal_flash = 0.4
			queue_redraw()


## Выстрел по герою (лич/скелет-маг, M14-D): снаряд летит в текущую позицию.
func _make_hero_projectile() -> Node:
	var proj = load("res://scripts/projectile.gd").new()
	proj.setup(global_position,
			(hero.global_position - global_position).normalized(),
			float(p.get("projectile_speed", 240.0)), float(p.get("projectile_range", 200.0)),
			int(p["damage"]), Color(String(p.get("color", "#b39ddb"))), float(p["radius"]))
	proj.target_group = "hero"
	return proj


func _shoot_hero() -> void:
	if hero == null or not is_instance_valid(hero) or hero.dead:
		return
	var parent := get_parent()
	if parent == null:
		return
	var proj := _make_hero_projectile()
	if parent.has_method("_solid_at"):
		proj.solid_check = Callable(parent, "_solid_at")
	parent.add_child(proj)

## Тик состояния: замер (враг замирает и вспыхивает) → рывок по герою.
## Отделено от _physics_process для headless-тестов.
func _tick_anti_kite(delta: float, dist_to_hero: float) -> void:
	_dash_cd = maxf(0.0, _dash_cd - delta)
	var ak := anti_kite_cfg()
	if _telegraph_left > 0.0:
		_telegraph_left = maxf(0.0, _telegraph_left - delta)
		velocity = Vector2.ZERO
		if _sprite != null:
			var pulse := 0.5 + 0.5 * sin(_telegraph_left * 40.0)
			_sprite.modulate = _base_tint.lerp(Color(2.5, 0.3, 0.3), 0.4 + 0.5 * pulse)
		if _telegraph_left <= 0.0:
			if hero != null and is_instance_valid(hero) and not hero.dead:
				_dash_left = float(ak.get("dash_time", 0.35))
				_dash_dir = (hero.global_position - global_position).normalized()
			_unanswered = 0
			if _sprite != null:
				_sprite.modulate = _base_tint
			queue_redraw()
		return
	if _dash_left > 0.0:
		_dash_left = maxf(0.0, _dash_left - delta)
		velocity = _dash_dir * float(p["speed"]) * float(ak.get("dash_speed_mult", 3.0))
		if hero != null and is_instance_valid(hero) and not hero.dead \
				and dist_to_hero <= float(p["attack_range"]) + float(hero.p["radius"]) + 6.0:
			hero.take_damage(maxi(1, int(round(float(p["damage"]) * float(ak.get("damage_mult", 1.0))))))
			_dash_left = 0.0
		if _dash_left <= 0.0:
			_dash_cd = float(ak.get("cooldown", 4.0))
			queue_redraw()
		return
	if _sprite != null:
		_sprite.modulate = _base_tint


## Герой ударил врага: копим безнаказанность, на пороге — телеграф.
func note_player_hit() -> void:
	_unanswered += 1
	var ak := anti_kite_cfg()
	if _unanswered >= int(ak.get("hits_threshold", 2)) and _dash_cd <= 0.0 \
			and _telegraph_left <= 0.0 and _dash_left <= 0.0:
		_telegraph_left = float(ak.get("telegraph_time", 0.45))
		_unanswered = 0
		queue_redraw()


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
	note_player_hit()
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
	# анти-кайт (M14-B): телеграф рывка — красный «!»-кольцо, рывок — жёлтый след
	if _telegraph_left > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 7.0, 0.0, TAU, 24, Color(1.0, 0.2, 0.2, 0.9), 3.0)
	elif _dash_left > 0.0:
		draw_line(Vector2.ZERO, -_dash_dir * 18.0, Color(1.0, 0.85, 0.3, 0.7), 3.0)
	# вампир пьёт жизнь (M14-D): зелёная дуга-вспышка
	if _heal_flash > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 5.0, 0.0, TAU, 20,
				Color(0.35, 0.9, 0.4, clampf(_heal_flash * 2.0, 0.0, 0.9)), 2.0)
