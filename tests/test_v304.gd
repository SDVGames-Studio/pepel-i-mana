extends "res://tests/test_base.gd"
## v3.0.4 «Музыка v3» (релиз): принятые заказчиком треки синтезатора
## tools/make_music_v3.py вживлены — меню, город по сезонам, бой.
## Директор музыки выбирает сезонный трек по state.season.

const SfxLib := preload("res://scripts/sfx.gd")


func _test_manifest_wiring() -> void:
	print("[v3.0.4: манифест музыки]")
	var w: Dictionary = _read_json("res://data/music.json")
	var st: Dictionary = w["states"]
	_check(String((st["menu"] as Dictionary)["music"]) == "mus_menu_v3",
			"меню — mus_menu_v3")
	_check(String((st["raid"] as Dictionary)["music"]) == "mus_battle_v3",
			"рейд — mus_battle_v3")
	var cd: Dictionary = st["city_day"]
	var ss: Dictionary = cd.get("seasons", {})
	_check(int(ss.size()) == 4, "у city_day 4 сезона")
	for ssn in ["spring", "summer", "autumn", "winter"]:
		var f := "assets/audio/music/%s.wav" % String(ss.get(ssn, ""))
		_check(FileAccess.file_exists(f), "трек %s на месте" % String(ss.get(ssn, "")))
	_check((st["city_night"] as Dictionary).get("seasons", {}).has("winter"),
			"city_night тоже сезонный")


func _test_track_for() -> void:
	print("[v3.0.4: директор выбирает трек]")
	SfxLib.ensure()
	_check(SfxLib.track_for({"scene": "menu"}) == "mus_menu_v3",
			"состояние меню -> mus_menu_v3")
	_check(SfxLib.track_for({"scene": "city", "night": false, "season": "spring"})
			== "mus_city_spring_v3", "город весной -> mus_city_spring_v3")
	_check(SfxLib.track_for({"scene": "city", "night": false, "season": "winter"})
			== "mus_city_winter_v3", "город зимой -> mus_city_winter_v3")
	_check(SfxLib.track_for({"scene": "city", "raid": true}) == "mus_battle_v3",
			"рейд -> mus_battle_v3")
	# без сезона (старые вызовы) — фолбэк на прежний трек
	_check(SfxLib.track_for({"scene": "city", "night": false}) == "mus_city_day_v3",
			"без сезона — прежний mus_city_day")
