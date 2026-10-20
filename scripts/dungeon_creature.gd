extends Node2D
## Мирное существо данжа (M14-C правка по фидбеку 2026-10-20): олени, кабаны
## и птицы живут и в подземельях. Убегает от героя; удар героя (дуга/тычок)
## убивает — дроп уходит в рюкзак (слышит сцена через сигнал slain).
## Волк в лесу — отдельный враг (enemies.json), не отсюда.

signal slain(creature)

var kind := "bird"
var def := {}
var p := {"radius": 6}          # совместимость с hero.try_attack (радиус хитбокса)
var dead := false
var hero = null
var gen = null                  # dungeon_gen.gd — для проверки пола под ногами
var ts := 32.0

var _wander_t := 0.0
var _dir := Vector2.ZERO


func setup(k: String, d: Dictionary, hero_ref, dungeon_gen, tile_size: float) -> void:
	kind = k
	def = d
	hero = hero_ref
	gen = dungeon_gen
	ts = tile_size
	p = {"radius": 6.0 * float(d.get("size", 1.0))}
	_wander_t = randf_range(0.5, 2.0)


func _process(delta: float) -> void:
	if dead or hero == null or not is_instance_valid(hero) or hero.dead:
		return
	var to_hero: Vector2 = hero.global_position - global_position
	var speed := float(def.get("speed", 60.0))
	if to_hero.length() < 75.0:
		# страх сильнее любопытства: прочь от героя
		_dir = -to_hero.normalized()
		_step(_dir, speed * delta)
		return
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(1.2, 3.0)
		_dir = Vector2.ZERO if randf() < 0.4 else \
				Vector2.from_angle(randf_range(0.0, TAU))
	if _dir != Vector2.ZERO:
		_step(_dir, speed * 0.35 * delta)


func _step(dir: Vector2, dist: float) -> void:
	var next := global_position + dir * dist
	var tile := Vector2i((next / ts).floor())
	if gen != null and gen.is_floor(tile):
		global_position = next
		queue_redraw()


func take_damage(_dmg: int) -> void:
	if dead:
		return
	dead = true
	slain.emit(self)
	queue_free()


func _draw() -> void:
	var col := Color(String(def.get("color", "#cccccc")))
	var size := float(def.get("size", 1.0))
	var moving := _dir != Vector2.ZERO
	var bob := absf(sin(Time.get_ticks_msec() / 90.0)) * (1.6 if moving else 0.5)
	draw_circle(Vector2(0, 2), 5.0 * size, Color(0, 0, 0, 0.25))
	# тело и голова
	draw_circle(Vector2(0, -2.0 * size - bob * 0.2), 4.6 * size, col)
	draw_circle(Vector2(4.0 * size, -4.5 * size - bob * 0.3), 2.6 * size, col.lightened(0.12))
	match kind:
		"deer":
			# рога
			draw_line(Vector2(3.5 * size, -6.5 * size), Vector2(2.2 * size, -10.0 * size), Color("#6d4c33"), 1.2)
			draw_line(Vector2(4.8 * size, -6.2 * size), Vector2(5.6 * size, -9.6 * size), Color("#6d4c33"), 1.2)
			draw_circle(Vector2(5.6 * size, -4.0 * size), 0.9 * size, Color.WHITE)
		"boar":
			draw_circle(Vector2(6.2 * size, -3.6 * size), 1.1 * size, Color("#e8b0a0"))
			draw_line(Vector2(-4.5 * size, -2.0 * size), Vector2(-6.0 * size, -2.6 * size), col.darkened(0.3), 1.4)
		"wolf":
			draw_colored_polygon(PackedVector2Array([
				Vector2(3.0 * size, -6.2 * size), Vector2(3.8 * size, -8.6 * size),
				Vector2(4.8 * size, -6.4 * size)]), col.darkened(0.15))
			draw_line(Vector2(-4.5 * size, -3.0 * size), Vector2(-7.0 * size, -4.5 * size), col.darkened(0.25), 1.6)
		"bird":
			draw_circle(Vector2(4.2 * size, -5.0 * size), 1.8 * size, Color("#3a3a3a"))
			draw_line(Vector2(-3.0 * size, -2.5 * size), Vector2(-6.0 * size, -4.5 * size), col.darkened(0.2), 1.2)
		_:
			pass
