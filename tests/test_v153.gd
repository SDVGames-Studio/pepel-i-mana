# v1.53 «Письма и чистое меню»: новая игра — сразу экран места города,
# ресурсы — иконки в HUD, крупные события — донесения-письма справа.
extends "res://tests/test_base.gd"


func _test_v153_menu() -> void:
	print("[v1.53: меню — новая игра сразу к месту города]")
	var menu: Script = load("res://scripts/main_menu.gd")
	var src: String = menu.source_code
	_check(src.find("start_found.tscn") >= 0, "«Новая игра» ведёт на экран места города")
	_check(src.find("_build_setup") < 0, "панель настроек из меню убрана (без цикла)")
	var found: Script = load("res://scripts/start_found.gd")
	var fsrc: String = found.source_code
	_check(fsrc.find("start_level = LEVELS") >= 0, "настройки старта применяются на экране места")
	_check(fsrc.find("test_mode = _test_on") >= 0 and fsrc.find("conflicts_enabled = _conflicts_on") >= 0,
			"тест-режим и конфликты — там же циклическими кнопками")


func _test_v153_letters() -> void:
	print("[v1.53: донесения-письма]")
	var feed: Script = load("res://scripts/notice_feed.gd")
	_check(feed != null and feed.can_instantiate(), "notice_feed.gd компилируется")
	# крупные события — письма, с группой-заголовком
	for t in ["raid_warn", "raid_start", "raid_breached", "raid_repelled",
			"razed", "storm_warn", "storm_start", "storm_end",
			"hive_wave", "hive_destroyed", "forest_warn", "forest_boss",
			"necro_revealed", "undead_rising", "caravan_arrived",
			"wanderer", "refugee", "legend_joined", "winter_soon"]:
		_check(bool(feed.call("is_letter", t)), "тип «%s» приходит письмом" % t)
		_check(String(feed.call("group_of", t)) != "", "у «%s» есть группа-заголовок" % t)
	# мелочь осталась тостами
	for t in ["built", "hauled", "morning_plan", "skill_up"]:
		_check(not bool(feed.call("is_letter", t)), "тип «%s» остаётся тостом (без письма)" % t)
	# строки групп
	var ru: Dictionary = _read_json("res://loc/ru.json")
	for g in ["threat", "storm", "hive", "forest", "necro", "trade", "people", "world"]:
		_check(not String(ru.get("letter." + g, "")).is_empty(), "заголовок письма «%s» есть" % g)
	# city.gd шлёт письма вместо тостов
	# (v1.62: city.gd — корень цепочки city_base -> city_events -> city_input;
	#  вызовы _letter живут в city_events — считаем по всей цепочке)
	var csrc := ""
	for city_part in ["city_base", "city_events", "city_input", "city"]:
		var cf := FileAccess.open("res://scripts/%s.gd" % city_part, FileAccess.READ)
		csrc += cf.get_as_text() if cf != null else ""
	_check(csrc.count("_letter(\"") >= 20, "крупные события уходят в письма (%d веток)" % csrc.count("_letter(\""))


func _test_v153_icons() -> void:
	print("[v1.53: иконки ресурсов]")
	var hud: Script = load("res://scripts/city_hud.gd")
	var hsrc: String = hud.source_code
	_check(hsrc.find("res_icon") >= 0, "HUD рисует ресурсы иконками")
	_check(hsrc.find("_res_label.text =") < 0, "текстовая строка ресурсов убрана")
	# у всех ресурсов есть стиль иконки и перевод
	var ru: Dictionary = _read_json("res://loc/ru.json")
	for rid in ["wood", "stone", "food", "crystal", "tools", "gems",
			"iron", "metal", "kits", "seeds", "saplings", "coins"]:
		_check(hsrc.find('"%s": [' % rid) >= 0, "иконка для «%s» описана" % rid)
		_check(not String(ru.get("res." + rid, "")).is_empty(), "название «%s» есть (подсказка)" % rid)
