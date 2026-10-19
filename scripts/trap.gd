extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Ловушка данжа (M7): шипы, дарты, руна-мина. Параметры — из data/dungeon.json.
## Шипы: периодическая активация, жгут героя на тайле. Дарты: выстрел по герою
## в прямой видимости. Руна-мина: невидимая, взрывается при подходе — бьёт и
## героя, и врагов (можно подвести монстров).

var kind := "spikes"
var cfg: Dictionary = {}      # параметры своего типа из dungeon.json -> "traps"
var gen = null                # dungeon_gen.gd — для проверки стены на линии дартов
var hero = null               # hero.gd — динамическая ссылка

var _phase := 0.0             # фаза цикла шипов
var _dart_cd := 0.0
var _armed := false           # мина встала на боевой взвод
var _arm_left := -1.0         # отсчёт до взвода (в setup дерево ещё недоступно)
var _boom := false            # мина сработала
var _flash := 0.0
var disarmed := false         # разминирована героем (E рядом, issue #2)

const TS := 32.0


func setup(trap_kind: String, type_cfg: Dictionary, gen_ref, hero_ref) -> void:
	kind = trap_kind
	cfg = type_cfg
	gen = gen_ref
	hero = hero_ref
	if kind == "spikes":
		_phase = randf() * float(cfg.get("period", 1.2))
	if kind == "rune_mine":
		# мина взводится через мгновение после появления, чтобы не рвануть на спавне
		_armed = false
		_arm_left = 0.6


## Разминирование (issue #2): ловушка любого типа перестаёт работать.
## Без новой графики — тот же спрайт сильно тускнеет.
func disarm() -> void:
	if disarmed:
		return
	disarmed = true
	modulate.a = 0.3
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if disarmed or hero == null or hero.dead:
		return
	if _arm_left >= 0.0:
		_arm_left -= delta
		if _arm_left < 0.0:
			_armed = true
	_flash = maxf(0.0, _flash - delta)
	match kind:
		"spikes":
			_tick_spikes(delta)
		"darts":
			_tick_darts(delta)
		"rune_mine":
			_tick_mine()
	queue_redraw()


## Шипы: цикл «спрятаны — вышли»; в активной фазе жгут стоящего на них героя.
func _tick_spikes(delta: float) -> void:
	var period := float(cfg.get("period", 1.2))
	var active := float(cfg.get("active_fraction", 0.45))
	_phase = fmod(_phase + delta, period)
	if _phase <= period * active and _hit_hero():
		hero.take_damage(int(cfg.get("damage", 1)))


## Дарты: раз в cooldown стреляют в героя, если он в радиусе и не за стеной.
func _tick_darts(delta: float) -> void:
	_dart_cd = maxf(0.0, _dart_cd - delta)
	if _dart_cd > 0.0 or not _hit_hero_range(float(cfg.get("range", 160.0))):
		return
	_dart_cd = float(cfg.get("cooldown", 2.0))
	_flash = 0.2
	hero.take_damage(int(cfg.get("damage", 1)))


## Мина: взрыв при подходе героя или врага; урон по площади всем.
func _tick_mine() -> void:
	if not _armed or _boom:
		return
	var trigger := float(cfg.get("trigger_dist", 26.0))
	var victims: Array = []
	if hero.global_position.distance_to(global_position) <= trigger:
		victims.append(hero)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) <= trigger:
			victims.append(enemy)
	if victims.is_empty():
		return
	_boom = true
	_flash = 0.4
	var radius := float(cfg.get("radius", 56.0))
	for v in victims:
		if v == hero:
			hero.take_damage(int(cfg.get("damage", 3)))
		else:
			v.take_damage(int(cfg.get("damage", 3)), "wild")


func _hit_hero() -> bool:
	return hero.global_position.distance_to(global_position) <= TS * 0.6


func _hit_hero_range(range_px: float) -> bool:
	if hero.global_position.distance_to(global_position) > range_px:
		return false
	return _line_clear(global_position, hero.global_position)


## По тайлам: на линии от ловушки до героя нет стены (дарты не стреляют сквозь стены).
func _line_clear(from: Vector2, to: Vector2) -> bool:
	var steps := int(from.distance_to(to) / (TS / 2.0))
	for i in steps + 1:
		var p := from.lerp(to, float(i) / float(maxi(1, steps)))
		if gen != null and not gen.is_floor(Vector2i((p / TS).floor())):
			return false
	return true


func _draw() -> void:
	match kind:
		"spikes":
			var period := float(cfg.get("period", 1.2))
			var active := float(cfg.get("active_fraction", 0.45))
			var out := _phase > period * active
			# спрайт зубчатой плиты (M9): вышедшие шипы — ярко, спрятанные — призрак
			Assets.draw_ref(self, "k:41", Vector2.ZERO, 26.0, false,
					Color(1, 1, 1, 0.95) if out else Color(0.75, 0.75, 0.8, 0.28))
		"darts":
			draw_circle(Vector2.ZERO, 5.0, Color(0.45, 0.4, 0.35, 0.9))
			draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 12, Color(0.8, 0.7, 0.4, 0.5), 1.5)
			if _flash > 0.0:
				draw_line(Vector2.ZERO, (hero.global_position - global_position).normalized() * 14.0,
						Color(1.0, 0.9, 0.5, _flash * 4.0), 2.0)
		"rune_mine":
			if _boom:
				draw_circle(Vector2.ZERO, 14.0, Color(0.7, 0.3, 1.0, _flash * 2.0))
			else:
				# слабый пульс — внимательный игрок заметит и обойдёт
				var pulse := 0.25 + 0.15 * absf(sin(Time.get_ticks_msec() / 300.0))
				draw_circle(Vector2.ZERO, 5.0, Color(0.7, 0.3, 1.0, pulse))
				draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 16, Color(0.7, 0.3, 1.0, pulse * 0.6), 1.5)
