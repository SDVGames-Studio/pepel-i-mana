extends SceneTree
## Диагностика анимаций героя (headless).
func _initialize() -> void:
	var HeroScript: Script = load("res://scripts/hero.gd")
	var hero: CharacterBody2D = HeroScript.new()
	var f := FileAccess.open("res://data/dungeon.json", FileAccess.READ)
	var cfg: Dictionary = JSON.parse_string(f.get_as_text())
	var hp: Dictionary = cfg.get("hero", {})
	hp["radius"] = 9.0
	hp["speed"] = 120.0
	hero.setup(hp, 10)
	root.add_child(hero)
	await process_frame
	var sf: SpriteFrames = hero._sprite.sprite_frames
	print("анимации: ", sf.get_animation_names())
	print("idle: ", sf.get_frame_count("idle"), " кадров, ", sf.get_animation_speed("idle"), " fps")
	hero.velocity = Vector2(120, 0)
	hero._drive_anim()
	print("бег вбок -> ", hero._sprite.animation)
	hero.velocity = Vector2(0, -120)
	hero._drive_anim()
	print("бег вверх -> ", hero._sprite.animation)
	hero.velocity = Vector2(0, 120)
	hero._drive_anim()
	print("бег вниз -> ", hero._sprite.animation)
	hero.velocity = Vector2.ZERO
	hero._attack_cd = 0.0
	hero.try_attack()
	print("атака -> ", hero._sprite.animation, "| стойка до ", hero._combat_until)
	hero._sprite.play("idle")
	hero._combat_until = 0.0
	hero._crouch = true
	hero._drive_anim()
	print("присед -> ", hero._sprite.animation)
	quit(0)
