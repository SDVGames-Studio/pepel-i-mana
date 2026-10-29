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
var _flicker_time := 0.0
var _sprite: Sprite2D = null      # спрайт воина 32×32 (M9)
var _bob_time := 0.0              # фаза бобинга ходьбы / дыхания в покое
var projectile_solid_check := Callable()   # сцена передаёт проверку стены (M14-B)
var city_speed_mult := 1.0        # вязкая земля у воды в городе (M14-I)
var _sk: Dictionary = {}          # постоянные бонусы дерева навыков (M7)
var _eq: Dictionary = {}          # бонусы экипировки (M14-B): броня/аксессуар
var _temp_dmg_left := 0.0         # временное усиление (заклинание «Перегрузка», M7)
var _temp_dmg := 0
var _temp_armor_left := 0.0       # каменная кожа (M7)
var _temp_armor := 0

# --- статы героя (v1.24): сила/ловкость/выносливость/интеллект/мудрость ------
static var _ha: Dictionary = {}   # кэш balance.json -> hero_attributes (тесты подменяют)

const LANTERN_ENERGY := 1.5   # v1.33.3: тёплый фонарь заметнее на тёмной базе данжа


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
	return int(p["hp"]) + skill_bonus("hp") + eq_bonus("hp") \
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
	return stat_spell_mult(attrs_cfg(), stat("int"))


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
	# спрайт воина (M9): высота ~3.2 радиуса, ноги чуть ниже центра коллизии
	_sprite = Sprite2D.new()
	var hero_tex: Texture2D = Assets.sprite("img:knight")
	_sprite.texture = hero_tex
	var h := float(p["radius"]) * 3.2
	_sprite.scale = Vector2.ONE * (h / float(hero_tex.get_height()))
	_sprite.position = Vector2(0, -h * 0.15)
	add_child(_sprite)
	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.zoom = Vector2(2, 2)
	add_child(cam)
	cam.make_current()
	# в городе героя рисует общий Y-сортированный слой сцены (M12):
	# спрайт-нода скрыта, тело и меч выводит draw_body в city_view
	if city_mode and _sprite != null:
		_sprite.visible = false
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
	# v1.33.3: движковые тени (shadow_enabled) ОТКЛЮЧЕНЫ — экструзия тени
	# больших окклюдеров нестабильна (в узких местах глохла вся лужа света,
	# замерено серией прогонов). Тени от стен теперь рисует слой тумана
	# войны (dungeon_fog.gd) по линии взгляда: за стеной — приглушение,
	# с плавным градиентным краем. Фонарь — чистый тёплый свет.
	light.shadow_enabled = false
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
	if not city_mode:
		_regen_mana(delta)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var agi_speed := stat("agi") * float(attrs_cfg().get("agi_speed", 1.5))   # ловкость — бег (v1.24)
	if city_mode:
		velocity = dir * (float(p["speed"]) + agi_speed) * city_speed_mult
		move_and_slide()
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
		queue_redraw()
		get_tree().create_timer(0.15).timeout.connect(queue_redraw)
		return
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
	queue_redraw()
	get_tree().create_timer(0.15).timeout.connect(queue_redraw)
	return hits


func take_damage(dmg: int) -> void:
	if _invuln > 0.0 or dead or _shield_left > 0.0:
		return
	hp = maxi(0, hp - maxi(0, dmg - eff_armor()))
	_invuln = 0.5
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


## Тело и меч в переданный canvas (данж: свой canvas, город: city_view, M12).
func draw_body(canvas: CanvasItem, pos: Vector2) -> void:
	var h := float(p["radius"]) * 3.2
	var moving := velocity.length() > 5.0
	var amp := 1.6 if moving else 0.5
	var body_y := -h * 0.15 - absf(sin(_bob_time)) * amp
	var flip := facing.x < 0.0
	# шаг виден и при движении вверх/вниз (M10): лёгкое покачивание корпусом
	var rot := 0.0
	if moving and absf(facing.y) >= absf(facing.x):
		rot = sin(_bob_time) * 0.09
	if _sprite != null and _sprite.texture != null:
		canvas.draw_set_transform(pos, rot, Vector2.ONE)
		var dst := Rect2(Vector2(-h / 2.0, body_y - h / 2.0), Vector2(h, h))
		if flip:
			dst.size.x = -dst.size.x
		canvas.draw_texture_rect(_sprite.texture, dst, false)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_sword(canvas, pos, flip)


## Меч героя (M11): виден в руке, при ударе — дуга замаха в сторону курсора.
func _draw_sword(canvas: CanvasItem, pos: Vector2, flip := false) -> void:
	var tex: Texture2D = Assets.sprite("e:sword")
	if tex == null:
		return
	var h := float(p["radius"]) * 1.7
	var s := h / float(tex.get_height())
	var w := float(tex.get_width()) * s
	var cd_full := float(p["attack_cooldown"])
	var attacking := _attack_cd > cd_full - 0.18
	var hand: Vector2
	var ang: float
	if attacking:
		# замах: от заноса за спиной (-2.2 рад) к завершению дуги (+1.4)
		var swing := 1.0 - (_attack_cd - (cd_full - 0.18)) / 0.18   # 0..1
		var arc := lerpf(-2.2, 1.4, clampf(swing, 0.0, 1.0))
		ang = facing.angle() + arc
		hand = facing.rotated(arc) * (float(p["radius"]) * 0.8) + Vector2(0, -float(p["radius"]) * 0.6)
	else:
		# в покое меч опущен по боку, отражается вместе с корпусом
		var side := 1.0 if not flip else -1.0
		ang = facing.angle() + 1.25 * side
		hand = Vector2(side * float(p["radius"]) * 0.55, float(p["radius"]) * 0.15)
	canvas.draw_set_transform(pos + hand, ang + PI / 2.0, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(Vector2(-w / 2.0, -h / 2.0), Vector2(w, h)), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
