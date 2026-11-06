# v1.54 (правки приёмки): письма-закладки, мгновенная подпись ресурса,
# ленивые npc-города на старте, меню-оверлей по Esc, тень скалы от подошвы,
# статичная обзорная карта.
extends "res://tests/test_base.gd"


func _test_v154_letters_tabs() -> void:
	print("[v1.54: письма сворачиваются в закладки]")
	var feed: Script = load("res://scripts/notice_feed.gd")
	var src: String = feed.source_code
	_check(src.find("OPEN_SECONDS") >= 0, "письмо живёт развёрнутым N секунд")
	_check(src.find("_arm_collapse") >= 0 and src.find("_expand_letter") >= 0,
			"сворачивание в закладку и разворот по клику есть")
	_check(src.find("custom_minimum_size = Vector2(26, 46)") >= 0,
			"закладка — узкая полоска у края")


func _test_v154_start_and_menu() -> void:
	print("[v1.54: быстрый старт и Esc-оверлей]")
	var game: Script = load("res://scripts/game.gd")
	_check(game.source_code.find("npc_cities.ensure(0, 3)") >= 0,
			"старт создаёт только 3 ближайших города НПС")
	var npc: Script = load("res://scripts/npc_cities.gd")
	var nsrc: String = npc.source_code
	_check(nsrc.find("func ensure(mature_days := 0, limit := 0)") >= 0,
			"ensure умеет лимит (остальные — на карте мира)")
	_check(nsrc.find("distance_squared_to") >= 0, "лимит берёт БЛИЖАЙШИЕ к городу")
	var city: Script = load("res://scripts/city.gd")
	var csrc: String = city.source_code
	_check(csrc.find("_open_menu_overlay") >= 0, "Esc открывает меню-оверлей (без смены сцены)")
	_check(csrc.find("_exit_to_menu()") != csrc.find("_open_menu_overlay()") - 1,
			"возврат в игру больше не пересоздаёт сцену города")
	var menu: Script = load("res://scripts/main_menu.gd")
	var msrc: String = menu.source_code
	_check(msrc.find("_close_overlay_if_any") >= 0, "Esc в меню-оверлее закрывает его на месте")


func _test_v154_shadow_and_map() -> void:
	print("[v1.54: тень скалы и статичная карта]")
	var sky: Script = load("res://scripts/city_sky.gd")
	var ssrc: String = sky.source_code
	_check(ssrc.find("bl, br, br + off, bl + off") >= 0,
			"тень скалы кладётся от южной подошвы (не накрывает скалу сверху)")
	var ov: Script = load("res://scripts/city_overview.gd")
	var osrc: String = ov.source_code
	_check(osrc.find("_baked_day") >= 0, "карта печётся раз в день")
	_check(osrc.find("_refresh_accum") < 0, "непрерывных обновлений карты нет")
	_check(osrc.find("residents") < 0 or osrc.find("for r in sim.residents") < 0,
			"жители по карте не бегают")
	_check(osrc.find("hero_cb") >= 0, "живая метка одна — герой")
	var hud: Script = load("res://scripts/city_hud.gd")
	var hsrc: String = hud.source_code
	_check(hsrc.find("mouse_entered.connect") >= 0 and hsrc.find("_res_name") >= 0,
			"наведение на ресурс показывает название мгновенно")
