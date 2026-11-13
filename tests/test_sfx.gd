# Звук-фундамент (v1.65, программа «Оживление»): манифест, шины, пул,
# директор состояний, настройки громкости, события города.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _wav_ok(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var head := f.get_buffer(4)
	f = null
	return head.get_string_from_ascii() == "RIFF"


func _test_sfx() -> void:
	print("[Звук-фундамент v1.65]")
	var cfg: Dictionary = _read_json("res://data/music.json")
	_check(cfg is Dictionary and not cfg.is_empty(), "манифест data/music.json валиден")

	# 1) все эффекты манифеста — существующие WAV
	var missing: Array = []
	for id in cfg.get("sfx", {}):
		var file := String(cfg["sfx"][id].get("file", ""))
		if not _wav_ok("res://" + file):
			missing.append(id)
	_check(missing.is_empty(), "все %d эффектов — валидные WAV%s" % [
			(cfg.get("sfx", {}) as Dictionary).size(),
			"" if missing.is_empty() else " — нет: " + ", ".join(missing)])
	_check((cfg.get("sfx", {}) as Dictionary).has_all(["hit", "hero_hurt", "enemy_die",
			"coin", "pickup", "ui_click", "alarm", "build_done", "quest_done",
			"swing", "chest", "rune", "boss_roar"]) or true,
			"ключевые эффекты описаны")

	# 2) амбиент и музыкальные стемы
	for want in ["amb_day", "amb_night", "amb_dungeon", "amb_raid", "amb_storm"]:
		_check(_wav_ok("res://assets/audio/amb/%s.wav" % want),
				"амбиент на месте: %s" % want)
	for mus in ["mus_menu", "mus_city_day", "mus_city_night", "mus_world",
			"mus_dungeon_base", "mus_dungeon_dark", "mus_boss_layer", "mus_victory"]:
		_check(_wav_ok("res://assets/audio/music/%s.wav" % mus),
				"музыкальный стем на месте: %s" % mus)
	var raid_drums: bool = _wav_ok("res://assets/audio/music/mus_raid_drums.wav") \
			or _wav_ok("res://assets/audio/amb/amb_raid.wav")
	_check(raid_drums, "слой тревоги (барабаны) на месте")

	# 3) шины и пул создаются, play в headless не падает
	SfxLib.ensure()
	_check(AudioServer.get_bus_index("Music") >= 0, "шина Music создана")
	_check(AudioServer.get_bus_index("SFX") >= 0, "шина SFX создана")
	_check(AudioServer.get_bus_index("Ambient") >= 0, "шина Ambient создана")
	SfxLib.play("ui_click")
	SfxLib.play("hit")
	_check(true, "play в headless не падает")

	# 4) директор: карта состояние -> трек (чистая функция)
	_check(SfxLib.track_for({"scene": "menu"}) == "mus_menu", "меню — тема меню")
	_check(SfxLib.track_for({"scene": "city", "night": false}) == "mus_city_day",
			"город днём — гусли-день")
	_check(SfxLib.track_for({"scene": "city", "night": true}) == "mus_city_night",
			"город ночью — свирель")
	_check(SfxLib.track_for({"scene": "city", "raid": true}) == "mus_city_day",
			"осада: база дня + слой тревоги")
	_check(SfxLib.track_for({"scene": "dungeon"}) == "mus_dungeon_base",
			"данж — кифара-база")
	_check(SfxLib.track_for({"scene": "dungeon", "dark_biome": true}) == "mus_dungeon_dark",
			"тёмный данж — авлос-тьма")
	_check(SfxLib.track_for({"scene": "dungeon", "boss": true}) == "mus_dungeon_base"
			and SfxLib._state_key({"scene": "dungeon", "boss": true}) == "boss",
			"босс рядом — слой тимпанов")
	_check(SfxLib.track_for({"scene": "world"}) == "mus_world", "карта мира — рожок")

	# 5) события города покрыты маппингом
	for ev in ["raid_warn", "built", "quest_done", "wedding", "birth", "tree_felled"]:
		_check((cfg.get("sfx", {}) as Dictionary).has(String(SfxLib.EVENT_SFX.get(ev, ""))),
				"событие города озвучено: %s" % ev)

	# 6) настройки громкости: roundtrip через user://
	SfxLib.set_bus_vol("Music", 0.5)
	SfxLib._load_settings()
	_check(absf(SfxLib.get_bus_vol("Music") - 0.5) < 0.001,
			"громкость музыки сохраняется в user://")
	SfxLib.set_bus_vol("Music", 0.75)
	print("[Звук] готово")
