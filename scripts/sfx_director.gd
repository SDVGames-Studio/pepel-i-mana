extends Node
## Музыкальный директор (v1.65): тикает SfxLib.director_tick, собирая
## состояние игры из текущей сцены. Автозагрузка — вся тяжёлая логика
## в SfxLib (статическая, headless-безопасная).

var _t := 0.0


func _ready() -> void:
	SfxLib.ensure()


## Диагностика звука (v1.65.1): вызывается из godot-mcp/runtime.
func debug_music() -> Dictionary:
	return {"ready": SfxLib._ready, "pool": SfxLib._sfx_pool.size(),
			"layers": SfxLib._layers.size(), "track": SfxLib._music_track,
			"playing": SfxLib._music_active != null and SfxLib._music_active.playing}


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.4:
		return
	_t = 0.0
	SfxLib.director_tick(_t, _compute_state())


func _compute_state() -> Dictionary:
	var st := {"scene": "menu", "amb": "", "night": false, "raid": false,
			"boss": false, "dark_biome": false, "busy": false, "festival": false}
	var cs := get_tree().current_scene
	if cs == null:
		return st
	var path := ""
	var scr: Script = cs.get_script()
	if scr != null:
		path = String(scr.resource_path)
	if path.ends_with("city.gd"):
		st["scene"] = "city"
		var sim: Variant = cs.get("sim")
		if sim != null:
			st["night"] = bool(sim.is_night())
			st["raid"] = bool(sim.raid_active) or bool(sim._raid_warned)
			st["festival"] = bool(sim._festival_today())
			st["busy"] = sim.residents.size() >= 10
			st["amb"] = "storm" if sim.storm_state != "" else ""
	elif path.ends_with("dungeon.gd"):
		st["scene"] = "dungeon"
		st["amb"] = "dungeon"
		var biome: Variant = cs.get("biome")
		if biome is Dictionary:
			var bid := String((biome as Dictionary).get("id", ""))
			st["dark_biome"] = bid in ["cursed", "demon_lair", "dead_forest", "crypt"]
		# босс рядом с героем — музыкальный слой босса
		var hero: Variant = cs.get("hero")
		var enemies: Variant = cs.get("enemies")
		if hero != null and enemies is Array:
			for e in enemies:
				if not is_instance_valid(e):
					continue
				if bool((e.p as Dictionary).get("boss", false)) \
						and hero.global_position.distance_to(e.global_position) < 460.0:
					st["boss"] = true
					break
	elif path.ends_with("world.gd"):
		st["scene"] = "world"
		st["amb"] = "day"
	elif path.ends_with("main_menu.gd"):
		st["scene"] = "menu"
		st["amb"] = "day"
	return st
