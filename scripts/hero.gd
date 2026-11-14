extends CharacterBody2D
const Assets := preload("res://scripts/assets.gd")
## Герой (M1): движение WASD/стрелки, уворот-отпрыг на Space,
## удар ближнего боя ЛКМ в сторону курсора. Примитивы вместо спрайтов — арт в M8.

signal died

var p: Dictionary = {}            # параметры из data/dungeon.json -> "hero"
var hp := 1
var mana := 0
var mana_max := 10                # переопределяется сценой данжа (алтарь с зачарованием)
var mana_regen_period := 8.0      # сек на +1 ману (ответ №65: регенерирует, если не тратится)
var facing := Vector2.RIGHT
var dead := false
var city_mode := false            # в городе: только ходьба, без боя и рывка
var bonus_damage := 0             # боевые комплекты героя из оружейки (M5.1)
var bonus_armor := 0              # плоское снижение входящего урона

var _dash_left := 0.0
var _dash_cd := 0.0
var _attack_cd := 0.0
var _invuln := 0.0
var _shield_left := 0.0           # щит света: поглощает урон
var _mana_regen_acc := 0.0
var _spell_cd := {}               # id заклинания -> остаток кулдауна, сек
var _lantern: PointLight2D = null
var lantern_on := true          # v1.46: фонарь можно погасить (скрытность)
var _track_acc := 0.0           # накопитель скрытности (тёмное подкрадывание)
var _flicker_time := 0.0
var _sprite: AnimatedSprite2D = null   # рыцарь FreeKnight: idle/run/attack/roll/death
var _bob_time := 0.0              # фаза бобинга ходьбы / дыхания в покое
var projectile_solid_check := Callable()   # сцена передаёт проверку стены (M14-B)
var city_speed_mult := 1.0        # вязкая земля у воды в городе (M14-I)
var _sk: Dictionary = {}          # постоянные бонусы дерева навыков (M7)
var _eq: Dictionary = {}          # бонусы экипировки (M14-B): броня/аксессуар
var resource_spell_mult := 1.0    # v1.57: кристалл лича — заклинания ×1.15
var resource_hp := 0              # v1.57: кровь вампира — +15 к здоровью
var _temp_dmg_left := 0.0         # временное усиление (заклинание «Перегрузка», M7)
var _temp_dmg := 0
var _temp_armor_left := 0.0       # каменная кожа (M7)
var _temp_armor := 0

# --- статы героя (v1.24): сила/ловкость/выносливость/интеллект/мудрость ------
static var _ha: Dictionary = {}   # кэш balance.json -> hero_attributes (тесты подменяют)

const LANTERN_ENERGY := 1.5   # v1.33.3: тёплый фонарь заметнее на тёмной базе данжа

# --- рыцарь FreeKnight_v1 (листы 120×80, персонаж ~37px высотой, ноги у низа) ---
const KNIGHT_FRAME := 120       # ширина кадра листа
const KNIGHT_FRAME_H := 80.0    # высота кадра
const KNIGHT_CHAR_H := 37.0     # высота персонажа в кадре (альфа-бокс)
const KNIGHT_FEET_Y := 79.5     # ноги персонажа от верха кадра
## v1.67.2: целевой ВИДИМЫЙ рост героя на экране. Единообразие персонажей
## (замечание приёмки): жители 27px, герой чуть выше — 31px (было ~32-45
## в зависимости от радиуса; фактически 1.4-2x крупнее жителей).
const KNIGHT_TARGET_H := 31.0


## SpriteFrames из горизонтальных полос assets/sprites/hero/knight_*.png
## (кадры режутся AtlasTexture-регионами — без предварительной нарезки).
static func build_knight_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if not sf.has_animation("default"):
		sf.add_animation("default")
	var defs := {
		"idle": ["knight_Idle", 8.0, true],
		"run": ["knight_Run", 12.0, true],
		"attack": ["knight_Attack", 12.0, false],
		"roll": ["knight_Roll", 14.0, false],
		"death": ["knight_Death", 8.0, false],
	}
	for anim: String in defs:
		var d: Array = defs[anim]
		var tex: Texture2D = Assets.tex("res://assets/sprites/hero/%s.png" % d[0])
		if tex == null:
			continue
		if sf.has_animation(anim):
			sf.remove_animation(anim)
		sf.add_animation(anim)
		sf.set_animation_speed(anim, float(d[1]))
		sf.set_animation_loop(anim, bool(d[2]))
		var n := int(tex.get_width()) / KNIGHT_FRAME
		for i in n:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * KNIGHT_FRAME, 0, KNIGHT_FRAME, KNIGHT_FRAME_H)
			sf.add_frame(anim, at)
	return sf


## Масштаб спрайта: высота персонажа в кадре → целевая (3.2 радиуса).
func knight_scale() -> float:
	return KNIGHT_TARGET_H / KNIGHT_CHAR_H


## Конфиг статов героя (balance.json -> hero_attributes); читается один раз.
static func attrs_cfg() -> Dictionary:
	if _ha.is_empty():
		var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_ha = parsed.get("hero_attributes", {})
	return _ha


## Текущий стат героя (рост хранится в Game и переживает забеги).
func stat(id: String) -> float:
	return Game.hero_stat(id)


## Сила — урон в ближнем бою (за очко str_dmg).
static func stat_melee_bonus(cfg: Dictionary, str_v: float) -> int:
	return int(round(str_v * float(cfg.get("str_dmg", 0.5))))


## Выносливость — запас здоровья (за очко end_hp).
static func stat_hp_bonus(cfg: Dictionary, end_v: float) -> int:
	return int(round(end_v * float(cfg.get("end_hp", 2.0))))


## Ловкость — плоская защита (за очко agi_armor).
static func stat_armor_bonus(cfg: Dictionary, agi_v: float) -> int:
	return int(round(agi_v * float(cfg.get("agi_armor", 0.25))))


## Интеллект — множитель силы заклинаний (за очко int_spell).
static func stat_spell_mult(cfg: Dictionary, int_v: float) -> float:
	return 1.0 + float(cfg.get("int_spell", 0.04)) * int_v


## Вызвать до add_child: параметры героя и стартовая мана.
func setup(hero_params: Dictionary, start_mana: int) -> void:
	p = hero_params
	hp = int(p["hp"])
	mana_max = int(p["mana"])
	mana = mini(start_mana, mana_cap())


## Постоянные бонусы узла дерева навыков (M7): damage/hp/mana/armor/speed/множители.
func apply_skill_bonuses(bonus: Dictionary) -> void:
	for key in bonus:
		_sk[key] = float(_sk.get(key, 0.0)) + float(bonus[key])
	hp = mini(hp_max(), hp + int(bonus.get("hp", 0)))
	mana_max += int(bonus.get("mana", 0))
	mana = mini(mana_cap(), mana + int(bonus.get("mana", 0)))
	queue_redraw()


func skill_bonus(key: String) -> int:
	return int(_sk.get(key, 0.0))


func skill_mult(key: String, fallback: float) -> float:
	return fallback if not _sk.has(key) else float(_sk[key])


## Бонусы экипировки (M14-B): полный словарь заменяется при каждом надевании.
func set_equipment_bonuses(bonus: Dictionary) -> void:
	_eq = bonus
	hp = mini(hp, hp_max())
	queue_redraw()


func eq_bonus(key: String) -> int:
	return int(_eq.get(key, 0.0))


func eq_mult(key: String, fallback: float) -> float:
	return fallback if not _eq.has(key) else float(_eq[key])


func hp_max() -> int:
	return int(p["hp"]) + skill_bonus("hp") + eq_bonus("hp") + resource_hp \
			+ stat_hp_bonus(attrs_cfg(), stat("end"))   # выносливость — здоровье (v1.24)


## Урон оружия: надетый предмет (паттерн × множитель) или кулаки из dungeon.json.
func base_damage() -> int:
	var wpn: Dictionary = Game.weapon_params()
	if wpn.is_empty():
		return int(p["damage"])
	return int(wpn["damage"])


## Эффективный урон: оружие + комплекты + навыки + экипировка + «Перегрузка»
## + сила героя (v1.24).
func eff_damage() -> int:
	return base_damage() + bonus_damage + skill_bonus("damage") + eq_bonus("damage") + _temp_dmg \
			+ stat_melee_bonus(attrs_cfg(), stat("str"))


## Эффективная броня: комплекты + навыки + экипировка + «Каменная кожа»
## + ловкость героя (v1.24).
func eff_armor() -> int:
	return bonus_armor + skill_bonus("armor") + eq_bonus("armor") + _temp_armor \
			+ stat_armor_bonus(attrs_cfg(), stat("agi"))


## Множитель силы заклинаний от интеллекта (v1.24).
func spell_mult() -> float:
	return stat_spell_mult(attrs_cfg(), stat("int")) * resource_spell_mult


## Мана: мудрость расширяет запас (v1.24) — кап считается на лету.
func mana_cap() -> int:
	return mana_max + int(round(stat("wis") * float(attrs_cfg().get("wis_mana", 1.0))))


## Временное усиление урона (заклинание, M7).
func temp_damage_bonus(duration: float, amount: int) -> void:
	_temp_dmg_left = duration
	_temp_dmg = amount


## Временная прибавка брони (заклинание, M7).
func temp_armor_bonus(duration: float, amount: int) -> void:
	_temp_armor_left = duration
	_temp_armor = amount


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
	# спрайт рыцаря (FreeKnight): анимации idle/run/attack/roll/death;
	# высота персонажа ~3.2 радиуса, ноги у нижнего края коллизии
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = build_knight_frames()
	var ks := knight_scale()
	_sprite.scale = Vector2.ONE * ks
	_sprite.position = Vector2(0, float(p["radius"]) - (KNIGHT_FRAME_H * 0.5 - KNIGHT_FEET_Y) * ks)
	_sprite.play("idle")
	# v1.58.1: нода-спрайт — ТОЛЬКО источник кадров/тайминга анимации; она
	# всегда скрыта, иначе в данже тело рисовалось дважды (сам _draw +
	# видимый AnimatedSprite2D — «два персонажа»). В городе тело и меч
	# выводит draw_body в общий Y-сортированный слой city_view (M12).
	_sprite.visible = false
	add_child(_sprite)
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
	# v1.33.3 (заказчик: «свет тёплый и тени от света должны быть»):
	# ярче центр, длиннее тёплый спад — факел заметен на тёмной базе
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.82),
		Color(0.98, 0.84, 0.58),
		Color(0.52, 0.36, 0.20),
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
	light.color = Color(1.0, 0.82, 0.55)   # v1.33.3: теплее
	light.energy = LANTERN_ENERGY
	# v1.42.1 (фидбек приёмки: «свет должен упираться в стены, а не
	# просвечивать сквозь»): движковые тени ВКЛЮЧЕНЫ — окклюдеры данжа
	# теперь ПОШТУЧНЫЕ (по тайлу стены, dungeon.gd::_build_walls, v1.33.3),
	# с ними экструзия стабильна (в v1.33.3 глючили слитые «полосы» на
	# всю ширину — из-за них тени и выключали). Туман войны (dungeon_fog)
	# переведён в light_mask=0 — тьму подсветки не разъедают вовсе.
	light.shadow_enabled = true
	light.shadow_filter_smooth = 2.0
	add_child(light)
	_lantern = light


func _physics_process(delta: float) -> void:
	if dead:
		return
	_flicker_time += delta
	# бобинг (M9): частый в движении, медленный «дыхание» в покое
	var moving := velocity.length() > 5.0
	_bob_time += delta * (11.0 if moving else 2.2)
	if _sprite != null:
		var amp := 1.6 if moving else 0.5
		_sprite.position.y = -float(p["radius"]) * 0.48 - absf(sin(_bob_time)) * amp
		if absf(facing.x) > 0.05:
			_sprite.flip_h = facing.x < 0.0
		# шаг виден и при движении вверх/вниз (M10): лёгкое покачивание корпусом
		if moving and absf(facing.y) >= absf(facing.x):
			_sprite.rotation = sin(_bob_time) * 0.09
		else:
			_sprite.rotation = lerpf(_sprite.rotation, 0.0, 0.3)
	if _lantern != null:
		# дыхание факела: лёгкое неровное мерцание яркости
		_lantern.energy = LANTERN_ENERGY * (0.94
				+ 0.045 * absf(sin(_flicker_time * 8.0))
				+ 0.03 * absf(sin(_flicker_time * 21.7)))
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_shield_left = maxf(0.0, _shield_left - delta)
	if _temp_dmg_left > 0.0:
		_temp_dmg_left = maxf(0.0, _temp_dmg_left - delta)
		if _temp_dmg_left <= 0.0:
			_temp_dmg = 0
	if _temp_armor_left > 0.0:
		_temp_armor_left = maxf(0.0, _temp_armor_left - delta)
		if _temp_armor_left <= 0.0:
			_temp_armor = 0
	_tick_spell_cooldowns(delta)
	# мана регенерирует и в городе (городской герой — все возможности данжа)
	_regen_mana(delta)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var agi_speed := stat("agi") * float(attrs_cfg().get("agi_speed", 1.5))   # ловкость — бег (v1.24)
	if city_mode:
		# v1.50: facing по движению — герой смотрит, куда бежит (в покое
		# сохраняет последний взгляд; раньше в городе был всегда вправо)
		if dir != Vector2.ZERO:
			facing = dir.normalized()
		# рывок в городе тоже (паритет с данжем): отпрыг в сторону движения
		if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0 and dir != Vector2.ZERO:
			facing = dir.normalized()
			_dash_left = float(p["dash_time"])
			_dash_cd = float(p["dash_cooldown"]) * skill_mult("dash_cd_mult", 1.0) * eq_mult("dash_cd_mult", 1.0)
		if _dash_left > 0.0:
			_dash_left -= delta
			var dash_speed_c := float(p["dash_distance"]) / float(p["dash_time"])
			velocity = facing * dash_speed_c * city_speed_mult
		else:
			velocity = dir * (float(p["speed"]) + agi_speed) * city_speed_mult
		move_and_slide()
		_play_step(delta, true)
		_drive_anim()
		return
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0 and dir != Vector2.ZERO:
		_dash_left = float(p["dash_time"])
		_dash_cd = float(p["dash_cooldown"]) * skill_mult("dash_cd_mult", 1.0) * eq_mult("dash_cd_mult", 1.0)
	if _dash_left > 0.0:
		_dash_left -= delta
		# отпрыг на фиксированную дистанцию от точки старта (об стену останавливается)
		var dash_speed := float(p["dash_distance"]) / float(p["dash_time"])
		velocity = facing * dash_speed
	else:
		velocity = dir * (float(p["speed"]) + float(_sk.get("speed", 0.0)) \
				+ float(_eq.get("speed", 0.0)) + agi_speed)
	move_and_slide()
	_play_step(delta, velocity.length() > 5.0)
	_drive_anim()


## Выбор анимации рыцаря по состоянию: смерть → рывок → замах (доигрывается)
## → бег → покой. Вызывается из физики в обоих режимах.
func _drive_anim() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var want := "idle"
	if dead:
		want = "death"
	elif _dash_left > 0.0:
		want = "roll"
	elif _sprite.animation == "attack" and _sprite.is_playing():
		want = "attack"          # замах не перебивается ходьбой до конца кадра
	elif velocity.length() > 5.0:
		want = "run"
	if _sprite.animation != want:
		_sprite.play(want)
	elif not _sprite.is_playing() and want in ["idle", "run"]:
		_sprite.play(want)


func _unhandled_input(event: InputEvent) -> void:
	if city_mode:
		return
	if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
		try_attack()


## Удар ближнего боя: дуга/тычок/снаряд — паттерн надетого оружия (M14-B).
func try_attack() -> void:
	if _attack_cd > 0.0 or dead:
		return
	var wpn: Dictionary = Game.weapon_params()
	var cd := float(wpn.get("attack_cooldown", p["attack_cooldown"]))
	_attack_cd = cd * skill_mult("attack_cd_mult", 1.0)
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		facing = to_mouse.normalized()
	var reach := float(wpn.get("range", p["attack_range"])) * skill_mult("range_mult", 1.0)
	if String(wpn.get("pattern", "")) == "projectile":
		_fire_projectile(wpn, reach)
		SfxLib.play("swing")   # v1.65: выстрел
		queue_redraw()
		get_tree().create_timer(0.15).timeout.connect(queue_redraw)
		return
	SfxLib.play("swing")   # v1.65: взмах оружия
	var arc := float(wpn.get("arc", p["attack_arc"]))
	var hits := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > reach + float(enemy.p["radius"]):
			continue
		if absf(facing.angle_to(to_enemy)) > deg_to_rad(arc) / 2.0:
			continue
		enemy.take_damage(eff_damage())
		Game.codex_seen("enemies", String(enemy.p.get("id", enemy.p.get("type", ""))))   # кодекс (M14-K)
		hits += 1
	# дело качает стат (v1.24): ближний бой — сила
	if hits > 0:
		Game.hero_train("str", float(attrs_cfg().get("train_swing", 0.06)) * float(hits))
	# мирная фауна данжа (замечание 2026-10-20): попадает той же дугой
	for creature in get_tree().get_nodes_in_group("dungeon_fauna"):
		if not is_instance_valid(creature) or bool(creature.dead):
			continue
		var to_c: Vector2 = creature.global_position - global_position
		if to_c.length() > reach + float(creature.p["radius"]):
			continue
		if absf(facing.angle_to(to_c)) > deg_to_rad(arc) / 2.0:
			continue
		creature.take_damage(1)
	queue_redraw()
	get_tree().create_timer(0.15).timeout.connect(queue_redraw)


## Выстрел (лук/посох, M14-B): снаряд летит в сторону курсора. Посоху нужна
## мана — на пустой герой бьёт древком (короткий замах в упор).
func _fire_projectile(wpn: Dictionary, reach: float) -> void:
	var mana_cost := int(wpn.get("mana_cost", 0))
	if mana_cost > 0:
		if mana < mana_cost:
			_attack_cd = 0.2
			return
		mana -= mana_cost
		# посох пьёт ману — качает мудрость (v1.24)
		Game.hero_train("wis", float(attrs_cfg().get("train_mana_wis", 0.04)) * float(mana_cost))
	else:
		Game.hero_train("agi", float(attrs_cfg().get("train_swing", 0.06)))   # лук — ловкость
	var proj = load("res://scripts/projectile.gd").new()
	var col := Color(1.0, 0.9, 0.55) if mana_cost <= 0 else Color(0.5, 0.7, 1.0)
	proj.setup(global_position + facing * float(p["radius"]), facing,
			float(wpn.get("projectile_speed", 400.0)), reach, eff_damage(), col,
			float(p["radius"]))
	if projectile_solid_check.is_valid():
		proj.solid_check = projectile_solid_check
	get_parent().add_child(proj)


## Удар в городе (M5): урон мутантам считает симуляция — герой только целится
## и показывает замах. Оружие (M14-B) меняет дугу/дальность: снарядное — выстрел.
func city_attack(sim) -> int:
	if _attack_cd > 0.0 or dead:
		return 0
	var wpn: Dictionary = Game.weapon_params()
	_attack_cd = float(wpn.get("attack_cooldown", p["attack_cooldown"]))
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		facing = to_mouse.normalized()
	var reach := float(wpn.get("range", p["attack_range"]))
	var hits: int
	if String(wpn.get("pattern", "")) == "projectile":
		hits = sim.hero_shoot(global_position, facing, reach, eff_damage())
	else:
		hits = sim.hero_slash(global_position, facing, reach,
				float(wpn.get("arc", p["attack_arc"])), eff_damage())
	# бой в городе качает статы как в данже (v1.49): сила — ближний бой,
	# ловкость — лук (посох в городе ману не пьёт — стреляем древком-лучом)
	if hits > 0:
		var ha: Dictionary = attrs_cfg()
		if String(wpn.get("pattern", "")) == "projectile":
			Game.hero_train("agi", float(ha.get("train_swing", 0.06)))
		else:
			Game.hero_train("str", float(ha.get("train_swing", 0.06)) * float(hits))
	queue_redraw()
	get_tree().create_timer(0.15).timeout.connect(queue_redraw)
	return hits


## v1.46: фонарь — включён/выключен (клавиша T). Выключенный фонарь —
## основа скрытного передвижения: враги замечают хуже, темнота качает навык.
func toggle_lantern() -> void:
	lantern_on = not lantern_on
	if _lantern != null:
		_lantern.energy = LANTERN_ENERGY if lantern_on else 0.0
	queue_redraw()


## Освещённость героя 0..1 для ИИ врагов (1 — фонарь горит).
func lantern_lit() -> float:
	return 1.0 if lantern_on else 0.0


## Множитель агро врагов: скрытность (навык, качается в темноте) +
## погашенный фонарь — враги замечают с меньшей дистанции.
func stealth_aggro_mult() -> float:
	var st: float = Game.hero_stat("stealth")
	var dark := 0.0 if lantern_on else 0.45
	return maxf(0.3, 1.0 - dark - 0.03 * st)


## Скрытность качается: двигался в темноте рядом с врагом (в данже).
func train_stealth_if_dark(enemies_near: bool, moving: bool, delta: float) -> void:
	if not lantern_on and moving and enemies_near:
		_track_acc += delta
		if _track_acc >= 1.0:
			_track_acc = 0.0
			Game.hero_train("stealth", 0.12)


func take_damage(dmg: int) -> void:
	if _invuln > 0.0 or dead or _shield_left > 0.0:
		return
	hp = maxi(0, hp - maxi(0, dmg - eff_armor()))
	_invuln = 0.5
	SfxLib.play("hero_hurt")   # v1.65
	# раны закаляют (v1.24): полученный урон качает выносливость
	if dmg > 0:
		Game.hero_train("end", float(attrs_cfg().get("train_hurt_end", 0.1)))
	queue_redraw()
	if hp <= 0:
		dead = true
		died.emit()


## Лечение (заклинание «Свет исцеления»).
func heal(amount: int) -> void:
	hp = mini(hp_max(), hp + amount)
	queue_redraw()


## Щит света: на duration сек поглощает весь входящий урон.
func cast_shield(duration: float) -> void:
	_shield_left = duration
	queue_redraw()


func shield_left() -> float:
	return _shield_left


## Кулдауны заклинаний (M3): герой хранит, сцена ставит/читает.
func set_spell_cd(spell_id: String, seconds: float) -> void:
	_spell_cd[spell_id] = seconds


func spell_cd_left(spell_id: String) -> float:
	return float(_spell_cd.get(spell_id, 0.0))


func _tick_spell_cooldowns(delta: float) -> void:
	for id in _spell_cd.keys():
		var left: float = maxf(0.0, float(_spell_cd[id]) - delta)
		_spell_cd[id] = left
		if left <= 0.0:
			_spell_cd.erase(id)


## Медленная регенерация маны сама по себе (ответ №65); мудрость ускоряет (v1.24).
func _regen_mana(delta: float) -> void:
	if mana >= mana_cap():
		_mana_regen_acc = 0.0
		return
	_mana_regen_acc += delta
	var period := mana_regen_period / (1.0 + float(attrs_cfg().get("wis_regen", 0.02)) * stat("wis"))
	if _mana_regen_acc >= period:
		_mana_regen_acc = 0.0
		mana = mini(mana_cap(), mana + 1)
		queue_redraw()


## Тик мана-голода: true — мана была и утекла, false — мана уже на нуле.
func drain_mana() -> bool:
	if mana <= 0:
		return false
	mana -= 1
	return true


func add_mana(v: int) -> void:
	mana = mini(mana_cap(), mana + v)


## Доля восстановления рывка 0..1 — для полосы HUD.
func dash_ready_fraction() -> float:
	if _dash_cd <= 0.0:
		return 1.0
	var full := float(p["dash_cooldown"]) * skill_mult("dash_cd_mult", 1.0) * eq_mult("dash_cd_mult", 1.0)
	return 1.0 - _dash_cd / maxf(0.01, full)


func _draw() -> void:
	if city_mode:
		return   # в городе тело и меч рисует общий сортированный слой (city_view)
	# тело героя — спрайт воина (M9); здесь оружие и боевые индикаторы
	draw_body(self, Vector2.ZERO)
	if _attack_cd > float(p["attack_cooldown"]) - 0.15:
		draw_line(Vector2.ZERO, facing * float(p["attack_range"]), Color(1.0, 0.9, 0.6, 0.8), 3.0)
	if _invuln > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 3.0, 0.0, TAU, 24, Color(1, 1, 1, 0.4), 1.5)
	if _shield_left > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 6.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.35, 0.85), 2.5)


## Тело героя в переданный canvas (данж: свой canvas, город: city_view, M12).
## Рыцарь FreeKnight: текущий кадр анимации, ноги у земли (y-сортировка).
func draw_body(canvas: CanvasItem, pos: Vector2) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	# AnimatedSprite2D в Godot 4 не Sprite2D — кадр берём из SpriteFrames
	var tex: Texture2D = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if tex == null:
		return
	var moving := velocity.length() > 5.0
	var amp := 1.2 if moving else 0.4
	var ks := knight_scale()
	var fw := KNIGHT_FRAME * ks
	var fh := KNIGHT_FRAME_H * ks
	# ноги персонажа — у самой точки сортировки (v1.49.1: раньше были на
	# +0.55 радиуса ниже и «тонули» под спрайтами зданий, у которых якорь —
	# низ footprint); лёгкий бобинг при ходьбе
	var feet_y := float(p["radius"]) * 0.2 - absf(sin(_bob_time)) * amp
	var rot := 0.0
	if moving and absf(facing.y) >= absf(facing.x):
		rot = sin(_bob_time) * 0.09
	canvas.draw_set_transform(pos, rot, Vector2.ONE)
	var dst := Rect2(Vector2(-fw / 2.0, feet_y - KNIGHT_FEET_Y * ks), Vector2(fw, fh))
	if facing.x < 0.0:
		dst.size.x = -dst.size.x
	canvas.draw_texture_rect(tex, dst, false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# v1.50: оружие в руке по надетому предмету — в покое и беге. В кадрах
	# атаки НЕ рисуем (меч вшит в knight_Attack — иначе двоится), в рывке
	# и смерти тоже: тело скручено/лежит.
	var anim := _sprite.animation
	if anim == "idle" or anim == "run":
		_draw_held_weapon(canvas, pos, facing.x < 0.0)


## Оружие в руке героя (v1.50, правка приёмки «оружие в руках»): FreeKnight
## без меча в idle/run — рисуем надетое оружие (меч/топор — спрайт env,
## копьё/лук/посох — вектор), опущенное по боку, зеркалится с корпусом.
func _draw_held_weapon(canvas: CanvasItem, pos: Vector2, flip := false) -> void:
	var wpn: Dictionary = Game.weapon_params()
	var wid := String(wpn.get("id", "sword"))
	var side := -1.0 if flip else 1.0
	var hand := pos + Vector2(side * float(p["radius"]) * 0.55, float(p["radius"]) * 0.15)
	var ang := facing.angle() + 1.25 * side
	var r := float(p["radius"])
	match wid:
		"sword", "axe":
			var tex: Texture2D = Assets.sprite("e:sword")
			if tex == null:
				return
			var h := r * 1.7
			var s := h / float(tex.get_height())
			var w := float(tex.get_width()) * s
			canvas.draw_set_transform(hand, ang + PI / 2.0, Vector2.ONE)
			canvas.draw_texture_rect(tex, Rect2(Vector2(-w / 2.0, -h / 2.0), Vector2(w, h)), false)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"spear":
			# древко с наконечником, длиннее меча
			canvas.draw_set_transform(hand, ang + PI / 2.0, Vector2.ONE)
			var hl := r * 2.3
			canvas.draw_rect(Rect2(Vector2(-1.0, -hl * 0.95), Vector2(2.0, hl)), Color("#7a5a3a"))
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(0, -hl * 1.12), Vector2(-2.2, -hl * 0.9), Vector2(2.2, -hl * 0.9)]),
				Color("#b8bcc4"))
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"bow":
			# дуга лука с тетивой, «открыта» вперёд
			canvas.draw_set_transform(hand, ang + PI / 2.0, Vector2.ONE)
			var br := r * 0.85
			canvas.draw_arc(Vector2(0, -br * 0.1), br, -PI / 2.0 - 1.05, -PI / 2.0 + 1.05, 14,
					Color("#8a6438"), 2.2)
			var a0 := -PI / 2.0 - 1.05
			var a1 := -PI / 2.0 + 1.05
			canvas.draw_line(Vector2(cos(a0), sin(a0)) * br, Vector2(cos(a1), sin(a1)) * br,
					Color("#d8d2c0", 0.9), 1.0)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"staff":
			# посох: древко и светящийся кристалл-навершие
			canvas.draw_set_transform(hand, ang + PI / 2.0, Vector2.ONE)
			var hl := r * 2.0
			canvas.draw_rect(Rect2(Vector2(-1.2, -hl * 0.9), Vector2(2.4, hl)), Color("#6d5238"))
			canvas.draw_circle(Vector2(0, -hl * 0.98), r * 0.28, Color("#6fb6e8"))
			canvas.draw_circle(Vector2(0, -hl * 0.98), r * 0.16, Color("#cfe8ff"))
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Шаги (v1.65.3, варианты v1.68): таймер в движении; поверхность —
## дорога/вода/камень/трава; внутри поверхности — случайный вариант тембра.
const STEP_POOLS := {
	"stone": ["step_stone", "step_stone_2"],
	"water": ["step_water", "step_water_2"],
	"road": ["step_road", "step_road_2"],
	"grass": ["step_grass", "step_grass_2", "step_grass_3"],
}
var _step_t := 0.0

func _play_step(delta: float, moving: bool) -> void:
	if _dash_left > 0.0 or not moving:
		_step_t = 0.12
		return
	_step_t -= delta
	if _step_t > 0.0:
		return
	_step_t = 0.34
	var par := get_parent()
	if par == null:
		return
	if par.has_method("night_boost"):
		_play_step_kind("stone")   # данж: камень
		return
	var m: Variant = par.get("map") if par != null else null
	if m == null:
		_play_step_kind("grass")
		return
	var tile: Vector2i = m.tile_of_px(global_position)
	if m.grid[tile.y][tile.x] == m.TILE_WATER:
		_play_step_kind("water")
	elif m.has_road(tile):
		_play_step_kind("road")
	else:
		_play_step_kind("grass")

func _play_step_kind(kind: String) -> void:
	var pool: Array = STEP_POOLS.get(kind, ["step_grass"])
	SfxLib.play(String(pool[randi() % pool.size()]))
