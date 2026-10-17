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
var _sk: Dictionary = {}          # постоянные бонусы дерева навыков (M7)
var _temp_dmg_left := 0.0         # временное усиление (заклинание «Перегрузка», M7)
var _temp_dmg := 0
var _temp_armor_left := 0.0       # каменная кожа (M7)
var _temp_armor := 0

const LANTERN_ENERGY := 1.15


## Вызвать до add_child: параметры героя и стартовая мана.
func setup(hero_params: Dictionary, start_mana: int) -> void:
	p = hero_params
	hp = int(p["hp"])
	mana_max = int(p["mana"])
	mana = mini(start_mana, mana_max)


## Постоянные бонусы узла дерева навыков (M7): damage/hp/mana/armor/speed/множители.
func apply_skill_bonuses(bonus: Dictionary) -> void:
	for key in bonus:
		_sk[key] = float(_sk.get(key, 0.0)) + float(bonus[key])
	hp = mini(hp_max(), hp + int(bonus.get("hp", 0)))
	mana_max += int(bonus.get("mana", 0))
	mana = mini(mana_max, mana + int(bonus.get("mana", 0)))
	queue_redraw()


func skill_bonus(key: String) -> int:
	return int(_sk.get(key, 0.0))


func skill_mult(key: String, fallback: float) -> float:
	return fallback if not _sk.has(key) else float(_sk[key])


func hp_max() -> int:
	return int(p["hp"]) + skill_bonus("hp")


## Эффективный урон: база + комплекты + навыки + «Перегрузка».
func eff_damage() -> int:
	return int(p["damage"]) + bonus_damage + skill_bonus("damage") + _temp_dmg


## Эффективная броня: комплекты + навыки + «Каменная кожа».
func eff_armor() -> int:
	return bonus_armor + skill_bonus("armor") + _temp_armor


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
	# бобинг (M9): частый в движении, медленный «дыхание» в покое
	var moving := velocity.length() > 5.0
	_bob_time += delta * (11.0 if moving else 2.2)
	if _sprite != null:
		var amp := 1.6 if moving else 0.5
		_sprite.position.y = -float(p["radius"]) * 0.48 - absf(sin(_bob_time)) * amp
		if absf(facing.x) > 0.05:
			_sprite.flip_h = facing.x < 0.0
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
	if city_mode:
		velocity = dir * float(p["speed"])
		move_and_slide()
		return
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0 and dir != Vector2.ZERO:
		_dash_left = float(p["dash_time"])
		_dash_cd = float(p["dash_cooldown"]) * skill_mult("dash_cd_mult", 1.0)
	if _dash_left > 0.0:
		_dash_left -= delta
		# отпрыг на фиксированную дистанцию от точки старта (об стену останавливается)
		var dash_speed := float(p["dash_distance"]) / float(p["dash_time"])
		velocity = facing * dash_speed
	else:
		velocity = dir * (float(p["speed"]) + float(_sk.get("speed", 0.0)))
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
	_attack_cd = float(p["attack_cooldown"]) * skill_mult("attack_cd_mult", 1.0)
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		facing = to_mouse.normalized()
	var reach := float(p["attack_range"]) * skill_mult("range_mult", 1.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > reach + float(enemy.p["radius"]):
			continue
		if absf(facing.angle_to(to_enemy)) > deg_to_rad(float(p["attack_arc"])) / 2.0:
			continue
		enemy.take_damage(eff_damage())
	queue_redraw()
	get_tree().create_timer(0.15).timeout.connect(queue_redraw)


## Удар в городе (M5): урон мутантам считает симуляция — герой только целится
## и показывает замах. Возвращает, скольких мутантов задел.
func city_attack(sim) -> int:
	if _attack_cd > 0.0 or dead:
		return 0
	_attack_cd = float(p["attack_cooldown"])
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		facing = to_mouse.normalized()
	var hits: int = sim.hero_slash(global_position, facing,
			float(p["attack_range"]), float(p["attack_arc"]), eff_damage())
	queue_redraw()
	get_tree().create_timer(0.15).timeout.connect(queue_redraw)
	return hits


func take_damage(dmg: int) -> void:
	if _invuln > 0.0 or dead or _shield_left > 0.0:
		return
	hp = maxi(0, hp - maxi(0, dmg - eff_armor()))
	_invuln = 0.5
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


## Медленная регенерация маны сама по себе (ответ №65).
func _regen_mana(delta: float) -> void:
	if mana >= mana_max:
		_mana_regen_acc = 0.0
		return
	_mana_regen_acc += delta
	if _mana_regen_acc >= mana_regen_period:
		_mana_regen_acc = 0.0
		mana = mini(mana_max, mana + 1)
		queue_redraw()


## Тик мана-голода: true — мана была и утекла, false — мана уже на нуле.
func drain_mana() -> bool:
	if mana <= 0:
		return false
	mana -= 1
	return true


func add_mana(v: int) -> void:
	mana = mini(mana_max, mana + v)


## Доля восстановления рывка 0..1 — для полосы HUD.
func dash_ready_fraction() -> float:
	if _dash_cd <= 0.0:
		return 1.0
	return 1.0 - _dash_cd / (float(p["dash_cooldown"]) * skill_mult("dash_cd_mult", 1.0))


func _draw() -> void:
	# тело героя — спрайт воина (M9); здесь только боевые индикаторы
	if _attack_cd > float(p["attack_cooldown"]) - 0.15:
		draw_line(Vector2.ZERO, facing * float(p["attack_range"]), Color(1.0, 0.9, 0.6, 0.8), 3.0)
	if _invuln > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 3.0, 0.0, TAU, 24, Color(1, 1, 1, 0.4), 1.5)
	if _shield_left > 0.0:
		draw_arc(Vector2.ZERO, float(p["radius"]) + 6.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.35, 0.85), 2.5)
