# Магия-просто (v1.66, программа «Оживление» аспект 2): XP-модель,
# гарантия первого заклинания, целостность рецептов, привязки в панелях.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_magic_simple() -> void:
	print("[Магия-просто v1.66]")
	var mg: Dictionary = _read_json("res://data/magic.json")
	_check(mg is Dictionary and not mg.is_empty(), "magic.json валиден")
	var recipes: Array = mg.get("recipes", [])
	_check(recipes.size() == 20, "рецептов 20 (%d)" % recipes.size())
	# 1) каждый рецепт ведёт на существующее заклинание
	for r in recipes:
		var sid := String(r["spell"])
		_check(_spell_exists(mg, sid), "рецепт -> заклинание: %s" % sid)
	# 2) XP-модель: уровень за 10 кастов, потолок 10
	_check(MagicLogic.level_from_uses(0) == 0, "0 кастов — уровень 0")
	_check(MagicLogic.level_from_uses(10) == 1, "10 кастов — уровень 1")
	_check(MagicLogic.level_from_uses(25) == 2, "25 кастов — уровень 2")
	_check(MagicLogic.level_from_uses(150) == 10, "150 кастов — потолок 10")
	_check(absf(MagicLogic.power_from_level(0) - 1.0) < 0.001, "уровень 0 — сила ×1.0")
	_check(absf(MagicLogic.power_from_level(1) - 1.1) < 0.001, "уровень 1 — сила ×1.1")
	_check(absf(MagicLogic.power_from_level(10) - 2.0) < 0.001, "уровень 10 — сила ×2.0")
	# 3) гарантия первого заклинания (первый рецепт — Огненная вспышка)
	var first: Dictionary = recipes[0]
	_check(MagicLogic.FIRST_SPELL_RUNES.has(String(first["a"])),
			"первый рецепт — из гарантированного набора")
	var g0: Array = MagicLogic.first_gift_runes([], [])
	_check(g0.size() == MagicLogic.FIRST_SPELL_RUNES.size(),
			"пустой спеллбук без рун — дар всех рун первого заклинания")
	var g1: Array = MagicLogic.first_gift_runes(["fire_flash"], [])
	_check(g1.is_empty(), "заклинание изучено — дара нет")
	var g2: Array = MagicLogic.first_gift_runes([],
			[{"id": "rune_sparks", "count": 1}, {"id": "rune_chaos", "count": 1}])
	_check(g2.is_empty(), "руны уже в рюкзаке — дара нет")
	# 4) привязки в коде: Z/X в городе, XP и звук при касте, дар в зачистке
	var ci := _source("res://scripts/city_input.gd")
	_check(ci.find("KEY_Z") >= 0 and ci.find("Game.spellbook[slot_idx]") >= 0,
			"Z/X в городе кастуют первые изученные")
	var cb := _source("res://scripts/city.gd")
	_check(cb.find("Game.spell_cast(spell_id)") >= 0
			and cb.find("Game.spell_power(spell_id)") >= 0,
			"город: каст качает и усиливается (прокачка)")
	_check(cb.find("SfxLib.play(\"spell_\"") >= 0, "город: звук школы при касте")
	var db := _source("res://scripts/dungeon_build.gd")
	_check(db.find("Game.spell_cast(spell_id)") >= 0
			and db.find("Game.spell_power(spell_id)") >= 0,
			"данж: каст качает и усиливается")
	var dn := _source("res://scripts/dungeon.gd")
	_check(dn.find("Game.first_spell_gift()") >= 0,
			"зачистка данжа дарит руны первого заклинания")
	var hud_src := _source("res://scripts/city_hud_build.gd")
	_check(hud_src.find("_spell_craft_rows") >= 0 and hud_src.find("magic.craft_ready") >= 0,
			"панель R — список рецептов со статусами (магия-просто)")
	print("[Магия-просто] готово")


func _spell_exists(mg: Dictionary, sid: String) -> bool:
	for sp in mg.get("spells", []):
		if String((sp as Dictionary).get("id", "")) == sid:
			return true
	return false


func _source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text() if f != null else ""
	f = null
	return txt
