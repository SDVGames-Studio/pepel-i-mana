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
# --- нечисть v1.30 (док 14) ---
var _boost := 1.0           # ночной множитель (ночь города + тьма данжа)
var _sneak_left := false    # кикимора: удар из тени ещё не израсходован
var _gaze_t := 0.0          # Вий: таймер проклятия «веки»
var _gaze_pulse_left := 0.0
var _yaga_dash_left := 0.0  # Яга: фаза ступы — наезды
var _yaga_dash_cd := 0.0
var _yaga_dash_dir := Vector2.ZERO
var _yaga_dash_hit := false


## Вызвать до add_child: строка из data/enemies.json.
func setup(data: Dictionary) -> void:
	p = data
	hp = int(p["hp"])
	if not p.has("stats"):
		p["stats"] = derive_stats(data)


## Конфиг анти-кайта (balance.json -> anti_kite); читается один раз.
static func anti_kite_cfg() -> Dictionary:
	if _ak.is_empty():
		var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_ak = parsed.get("anti_kite", {})
	return _ak


# --- статы существ (v1.24) -----------------------------------------------------
## Конфиг статов (balance.json -> hero_attributes), с кэшем.
static var _ha: Dictionary = {}


static func _attrs_cfg() -> Dictionary:
	if _ha.is_empty():
		var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_ha = parsed.get("hero_attributes", {})
	return _ha


## Статы существа выводятся из его параметров: урон — сила, здоровье —
## выносливость, резвость — ловкость, колдовство — интеллект/мудрость.
## Боссы (boss: true) идут с множителем boss_mult — СВЕРХ капы обычных
## жителей: мощь выливается в статы, а не упирается в лимит.
static func derive_stats(data: Dictionary) -> Dictionary:
	var m := float(_attrs_cfg().get("boss_mult", 2.2)) if bool(data.get("boss", false)) else 1.0
	var caster := float(data.get("projectile_speed", 0.0)) > 0.0
	return {
		"str": int(round(float(data.get("damage", 1)) * m)),
		"end": int(round(float(data.get("hp", 5)) / 6.0 * m)),
		"agi": int(round(float(data.get("speed", 80)) / 25.0 * m)),
		"int": int(round(float(data.get("damage", 1)) * (1.4 if caster else 0.4) * m)),
		"wis": int(round(float(data.get("mana_chance", 0.2)) * 10.0 * m)),
	}


## Урон существа по герою: база × сила (v1.24).
static func melee_damage(data: Dictionary) -> int:
	var s: Dictionary = data.get("stats", {}) if data.has("stats") else derive_stats(data)
	var per := float(_attrs_cfg().get("enemy_dmg_per_str", 0.04))
	return maxi(1, int(round(float(data.get("damage", 1)) * (1.0 + per * float(s.get("str", 0.0))))))


## Урон магического снаряда существа: база × интеллект (v1.24).
static func spell_damage(data: Dictionary) -> int:
	var s: Dictionary = data.get("stats", {}) if data.has("stats") else derive_stats(data)
	var per := float(_attrs_cfg().get("enemy_dmg_per_int", 0.05))
	return maxi(1, int(round(float(data.get("damage", 1)) * (1.0 + per * float(s.get("int", 0.0))))))


## Расчёт магического урона: уязвимая школа ×2, антимаг — 0. Статика — для headless-тестов.
static func calc_spell_damage(data: Dictionary, base: int, school: String) -> int:
	if bool(data.get("magic_immune", false)):
		return 0
	if school != "" and String(data.get("weak_school", "")) == school:
		return base * 2
	return base


# --- нечисть v1.30 (док 14): чистые функции — headless-тесты -----------------

## Ночной множитель нечисти: ночь города (+0.3) и тьма данжа до зачистки
## (+0.2 на старте, тает к зачистке). Заказчик: «всё и сразу».
static func night_mult(is_night: bool, dark_frac: float) -> float:
	return minf(1.5, 1.0 + (0.3 if is_night else 0.0) + 0.2 * clampf(dark_frac, 0.0, 1.0))


## Ночница стайная: +15% урона за союзника рядом, кап ×1.6.
static func pack_mult(allies: int) -> float:
	return minf(1.6, 1.0 + 0.15 * maxi(0, allies))


## Взгляд Вия: пульс накрывает радиус; ближе — больнее (спад до половины у края).
static func gaze_hit(dist: float, range_px: float) -> bool:
	return dist <= range_px


static func gaze_damage(base: int, dist: float, range_px: float) -> int:
	if dist > range_px:
		return 0
	var k := 1.0 - 0.5 * dist / maxf(1.0, range_px)
	return maxi(1, int(round(float(base) * k)))


## Баба-яга: фаза по здоровью — 0 метла (>66%), 1 ступа, 2 печь.
static func yaga_phase(hp_frac: float) -> int:
	return 0 if hp_frac > 0.66 else (1 if hp_frac > 0.33 else 2)


## Смерть Кощея — на конце иглы: пока игла жива, удар не опускает hp ниже 1.
static func koshchei_holds(perk: String, needle_alive: bool) -> bool:
	return perk == "koshchei" and needle_alive


## Кикимора: удар из тени — первый удар с множителем.
static func sneak_damage(perk: String, sneak_left: bool, mult: float, base: int) -> int:
	if perk == "sneak" and sneak_left:
		return maxi(1, int(round(float(base) * mult)))
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
	if p.has("group"):
		add_to_group(String(p["group"]))   # игла смерти Кощея и пр.
	collision_layer = 4
	collision_mask = 1 | 2
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = float(p["radius"])
	shape.shape = circle
	add_child(shape)
	_sneak_left = String(p.get("perk", "")) == "sneak"
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
		if _sneak_left:
			_sprite.modulate.a = 0.4   # кикимора в тени, пока не получит удар
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
	# нечисть v1.30: ночной множитель (ночь города + тьма данжа)
	var perk := String(p.get("perk", ""))
	_boost = 1.0
	if bool(p.get("nocturnal", false)) and get_parent() != null \
			and get_parent().has_method("night_boost"):
		_boost = get_parent().night_boost()
	_tick_anti_kite(delta, dist)
	# волколак: сам идёт в рывок, если герой в средней дистанции
	if perk == "dash_run" and _dash_cd <= 0.0 and _telegraph_left <= 0.0 \
			and dist > float(p["attack_range"]) + 10.0 and dist < 260.0:
		_telegraph_left = 0.35
	# Баба-яга: фазы метла/ступа/печь
	if perk == "yaga":
		var handled := _tick_yaga(delta, dist, to_hero)
		if handled:
			move_and_slide()
			return
	# Вий: таймер проклятия «веки»
	if perk == "gaze":
		_tick_gaze(delta, dist)
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
			velocity = to_hero.normalized() * float(p["speed"]) * _boost
	elif not patrol.is_empty():
		# стража гнезда патрулирует (M12): ходит по точкам, пока герой далеко
		var goal: Vector2 = patrol[_patrol_i]
		if global_position.distance_to(goal) < 12.0:
			_patrol_i = (_patrol_i + 1) % patrol.size()
			goal = patrol[_patrol_i]
		velocity = (goal - global_position).normalized() * float(p["speed"]) * 0.5 * _boost
	else:
		velocity = Vector2.ZERO
	if _slow_left > 0.0:
		velocity *= _slow_mult
	move_and_slide()


## --- анти-кайт (M14-B, T06): телеграф и рывок с атакой ---------------------

## Удар в упор (M14-D): урон герою (с силой существа, v1.24); вампир лечится
## на долю урона (lifesteal). v1.30: перки нечисти — стая, пар, удар из тени,
## тяга водяного, очарование русалки, пыль полевика. Отдельный метод — для
## headless-тестов.
func _attack_hero() -> void:
	var perk := String(p.get("perk", ""))
	var dmg := maxi(1, int(round(float(melee_damage(p)) * _boost)))
	if perk == "pack":
		var allies := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if e != self and is_instance_valid(e) \
					and global_position.distance_to(e.global_position) < 110.0:
				allies += 1
		dmg = maxi(1, int(round(float(dmg) * pack_mult(allies))))
	if perk == "steam":
		dmg = maxi(1, int(round(float(dmg) * float(p.get("steam_mult", 1.3)))))
	dmg = sneak_damage(perk, _sneak_left, float(p.get("sneak_mult", 1.5)), dmg)
	if perk == "sneak" and _sneak_left:
		_sneak_left = false
		if _sprite != null:
			_sprite.modulate = _base_tint   # тень израсходована — проявляется
	hero.take_damage(dmg)
	# враг ответил — счётчик безнаказанных ударов обнуляется (T06)
	_unanswered = 0
	# перки касания
	if perk == "pull":
		hero.global_position += (global_position - hero.global_position).normalized() \
				* float(p.get("pull_px", 44.0))
	elif perk == "charm":
		hero.velocity = (global_position - hero.global_position).normalized() * 280.0
	elif perk == "dust":
		hero.velocity *= 0.35
	var ls := float(p.get("lifesteal", 0.0))
	if ls > 0.0 and hp > 0:
		var max_hp := int(p["hp"])
		if hp < max_hp:
			hp = mini(max_hp, hp + maxi(1, int(round(float(dmg) * ls))))
			_heal_flash = 0.4
			queue_redraw()


## Выстрел по герою (лич/скелет-маг, M14-D): снаряд летит в текущую позицию.
func _make_hero_projectile() -> Node:
	var proj = load("res://scripts/projectile.gd").new()
	proj.setup(global_position,
			(hero.global_position - global_position).normalized(),
			float(p.get("projectile_speed", 240.0)), float(p.get("projectile_range", 200.0)),
			spell_damage(p), Color(String(p.get("color", "#b39ddb"))), float(p["radius"]))
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
			hero.take_damage(maxi(1, int(round(float(melee_damage(p)) * float(ak.get("damage_mult", 1.0))))))
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
	# Кощей: смерть на конце иглы — пока игла цела, hp не опускается ниже 1
	var perk := String(p.get("perk", ""))
	if koshchei_holds(perk, get_tree() != null
			and get_tree().get_first_node_in_group("death_needle") != null):
		hp = maxi(1, hp)
		_hit_flash = 0.35
	# леший: подмена — с шансом шагает в тень
	if perk == "shift" and randf() < float(p.get("shift_chance", 0.25)):
		_shift_blink()
	_hit_flash = 0.2
	queue_redraw()
	note_player_hit()
	if hp <= 0:
		died.emit(self)
		queue_free()


## Леший: подмена — мгновенный шаг в тень (3 радиуса в сторону).
func _shift_blink() -> void:
	var parent := get_parent()
	if parent == null or not parent.has_method("_solid_at"):
		return
	for i in 8:
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / 8.0)
		var px := global_position + dir * float(p["radius"]) * 3.0
		if not parent._solid_at(px):
			global_position = px
			_hit_flash = 0.3
			return


## Баба-яга: фазы по здоровью (статика yaga_phase). Метла — веер снарядов
## со средней дистанции; ступа — наезды по кулдауну; печь — обычные удары
## сильнее (× _boost не даёт — усиление в данных фазы не нужно: печь и так
## добивает), возврат false — обычное движение.
func _tick_yaga(delta: float, dist: float, to_hero: Vector2) -> bool:
	_yaga_dash_cd = maxf(0.0, _yaga_dash_cd - delta)
	var phase := yaga_phase(float(hp) / float(p["hp"]))
	if phase == 0:
		if _attack_timer <= 0.0 and dist < 250.0 and dist > float(p["attack_range"]):
			_attack_timer = float(p["attack_cooldown"]) * 0.9
			_broom_fan()
		return false
	if phase == 1:
		if _yaga_dash_left > 0.0:
			_yaga_dash_left = maxf(0.0, _yaga_dash_left - delta)
			velocity = _yaga_dash_dir * float(p["speed"]) * 2.6
			if not _yaga_dash_hit and hero != null and is_instance_valid(hero) \
					and not hero.dead \
					and dist <= float(p["attack_range"]) + float(hero.p["radius"]) + 8.0:
				hero.take_damage(maxi(1, int(round(float(melee_damage(p)) * 1.25))))
				_yaga_dash_hit = true
			if _yaga_dash_left <= 0.0:
				_yaga_dash_hit = false
				_yaga_dash_cd = 2.4
			return true
		if _yaga_dash_cd <= 0.0 and dist > float(p["attack_range"]) + 14.0:
			_yaga_dash_left = 0.55
			_yaga_dash_dir = to_hero.normalized()
			return true
	return false


## Метла Яги: три снаряда веером в текущую позицию героя.
func _broom_fan() -> void:
	var parent := get_parent()
	if parent == null or hero == null or not is_instance_valid(hero) or hero.dead:
		return
	var base: Vector2 = (hero.global_position - global_position).normalized()
	for i in 3:
		var dir := base.rotated((float(i) - 1.0) * 0.38)
		var proj = load("res://scripts/projectile.gd").new()
		proj.setup(global_position, dir, 230.0, 260.0,
				spell_damage(p), Color(String(p.get("color", "#e0a04a"))), float(p["radius"]))
		proj.target_group = "hero"
		if parent.has_method("_solid_at"):
			proj.solid_check = Callable(parent, "_solid_at")
		parent.add_child(proj)


## Вий: таймер проклятия «веки» (заказчик — таймер): раз в период Вий замирает,
## веки поднимаются (телеграф), затем пульс — урон по радиусу с спадом и
## оцепенение (герой обездвижен на время пульса).
func _tick_gaze(delta: float, dist: float) -> void:
	_gaze_t += delta
	var period := float(p.get("gaze_period", 6.0))
	var tele := float(p.get("gaze_telegraph", 1.4))
	if _gaze_pulse_left > 0.0:
		_gaze_pulse_left = maxf(0.0, _gaze_pulse_left - delta)
		if hero != null and is_instance_valid(hero) and not hero.dead \
				and gaze_hit(dist, float(p.get("gaze_range", 150.0))):
			hero.velocity = Vector2.ZERO   # оцепенение на время пульса
		return
	if _gaze_t >= period:
		_gaze_t = 0.0
		_gaze_pulse_left = 0.6
		if hero != null and is_instance_valid(hero) and not hero.dead \
				and gaze_hit(dist, float(p.get("gaze_range", 150.0))):
			hero.take_damage(gaze_damage(int(p.get("gaze_damage", 10)),
					dist, float(p.get("gaze_range", 150.0))))
	elif _gaze_t >= period - tele:
		velocity = Vector2.ZERO   # веки поднимаются — Вий замирает
	queue_redraw()


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
	# нечисть v1.30: Вий — телеграф «век» (сиреневое кольцо растёт), пульс;
	# Кощей — золотая аура, пока смерть на игле
	var perk := String(p.get("perk", ""))
	if perk == "gaze":
		var tele := float(p.get("gaze_telegraph", 1.4))
		var period := float(p.get("gaze_period", 6.0))
		var grange := float(p.get("gaze_range", 150.0))
		if _gaze_pulse_left > 0.0:
			draw_arc(Vector2.ZERO, grange, 0.0, TAU, 40,
					Color(0.7, 0.5, 1.0, clampf(_gaze_pulse_left * 1.4, 0.0, 0.9)), 3.0)
		elif _gaze_t >= period - tele:
			var k := (_gaze_t - (period - tele)) / tele
			draw_arc(Vector2.ZERO, grange * clampf(k, 0.05, 1.0), 0.0, TAU, 40,
					Color(0.6, 0.4, 0.9, 0.5), 2.0)
	elif perk == "koshchei" and get_tree() != null \
			and get_tree().get_first_node_in_group("death_needle") != null:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 6.0, 0.0, TAU, 24,
				Color(0.8, 0.65, 0.25, 0.5), 2.0)
