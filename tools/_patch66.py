# -*- coding: utf-8 -*-
"""Патч v1.66 «Магия-просто»: алтарь-список, Z/X в городе, XP заклинаний,
гарантия первого заклинания, звуки школ. Все замены — против main."""
import os

ok, miss = [], []


def read(p):
    return open(p, encoding='utf-8').read()


def write(p, s):
    open(p, 'w', encoding='utf-8').write(s)


def rep(path, old, new, tag):
    global ok, miss
    s = read(path)
    if old in s:
        write(path, s.replace(old, new, 1))
        ok.append(tag)
    else:
        miss.append(tag)


# --- 1) magic.gd: class_name + статическая логика XP/гарантии ---------------
rep('scripts/magic.gd', 'extends RefCounted\n## Магия (M3):',
    'class_name MagicLogic\nextends RefCounted\n## Магия (M3):', 'magic-class')
rep('scripts/magic.gd',
    '''var cfg: Dictionary = {}''',
    '''var cfg: Dictionary = {}


# --- статическая логика v1.66 (магия-просто) — тестируется headless ---------

## Уровень заклинания за использованием: +1 уровень за 10 кастов, потолок 10.
static func level_from_uses(uses: int) -> int:
	return mini(10, int(uses / 10))


## Множитель силы заклинания от уровня: ×1.1 за уровень, потолок ×2.
static func power_from_level(level: int) -> float:
	return 1.0 + 0.1 * float(level)


## Руны первого заклинания (гарантия обучения, дизайн-док 15-ОЖИВЛЕНИЕ
## аспект 2): пока ничего не изучено и пары нет в рюкзаке — вернуть руну
## первого рецепта. Иначе [].
static func first_gift_runes(spellbook: Array, inventory: Array) -> Array:
	if not spellbook.is_empty():
		return []
	var have := {}
	for stack in inventory:
		var id := String(stack["id"])
		if id.begins_with("rune_"):
			have[id] = true
	var missing: Array = []
	for rune_id in FIRST_SPELL_RUNES:
		if not have.has(rune_id):
			missing.append(rune_id)
	return missing


## Первое заклинание: пара рун первого рецепта (Огненная вспышка).
const FIRST_SPELL_RUNES := ["rune_sparks", "rune_chaos"]''', 'magic-static')

# --- 2) game.gd: uses/slots/обёртки ------------------------------------------
rep('scripts/game.gd', '''var spellbook: Array = []        # изученные заклинания: [id: String]''',
    '''var spellbook: Array = []        # изученные заклинания: [id: String]
var spell_uses: Dictionary = {}  # v1.66: касты по заклинаниям — прокачка
var spell_uses_saved: Dictionary = {}''', 'game-vars')
rep('scripts/game.gd', '''func learn_spell(spell_id: String) -> void:
	if not spellbook.has(spell_id):
		spellbook.append(spell_id)
		codex_seen("spells", spell_id)''',
    '''func learn_spell(spell_id: String) -> void:
	if not spellbook.has(spell_id):
		spellbook.append(spell_id)
		codex_seen("spells", spell_id)


## v1.66 (магия-просто): каст учитывается — уровень растёт на 10 кастов.
func spell_cast(spell_id: String) -> int:
	spell_uses[spell_id] = int(spell_uses.get(spell_id, 0)) + 1
	return MagicLogic.level_from_uses(int(spell_uses[spell_id]))


func spell_level(spell_id: String) -> int:
	return MagicLogic.level_from_uses(int(spell_uses.get(spell_id, 0)))


func spell_power(spell_id: String) -> float:
	return MagicLogic.power_from_level(spell_level(spell_id))


## Руны гарантии первого заклинания (данж зачищен — см. dungeon.gd).
func first_spell_gift() -> Array:
	return MagicLogic.first_gift_runes(spellbook, inventory)''', 'game-funcs')

# --- 3) сейв: uses + (слот-массив не сохраняем — spellbook порядок) ---------
rep('scripts/save_game_write.gd', '''		"spellbook": game.spellbook,''',
    '''		"spellbook": game.spellbook,
		"spell_uses": game.spell_uses,''', 'save-uses')
rep('scripts/save_game.gd', '''	game.spellbook = []
	for s in g.get("spellbook", []):
		game.spellbook.append(String(s))''',
    '''	game.spellbook = []
	for s in g.get("spellbook", []):
		game.spellbook.append(String(s))
	game.spell_uses = {}
	var su: Variant = g.get("spell_uses", {})
	if su is Dictionary:
		for k in (su as Dictionary):
			game.spell_uses[String(k)] = int((su as Dictionary)[k])''', 'load-uses')

# --- 4) панель R: список рецептов вместо двух дропдаунов ---------------------
rep('scripts/city_hud_build.gd',
    '''	# крафт: две руны -> заклинание (таблица рецептов, ответ №58)
	var craft_title := _label(20)
	craft_title.text = Loc.t("magic.craft")
	_magic_box.add_child(craft_title)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	_magic_box.add_child(slots)
	_rune_slot_a = OptionButton.new()
	_rune_slot_b = OptionButton.new()
	for slot in [_rune_slot_a, _rune_slot_b]:
		slot.custom_minimum_size = Vector2(240, 36)
		slot.focus_mode = Control.FOCUS_NONE
		slot.item_selected.connect(func(_idx: int) -> void: _update_craft_preview())
		slots.add_child(slot)
	_craft_result = _label(18)
	_magic_box.add_child(_craft_result)
	_craft_btn = Button.new()
	_craft_btn.text = Loc.t("magic.craft_make")
	_craft_btn.custom_minimum_size = Vector2(0, 40)
	_craft_btn.focus_mode = Control.FOCUS_NONE
	_craft_btn.pressed.connect(_on_craft_pressed)
	_magic_box.add_child(_craft_btn)''',
    '''	# v1.66 (магия-просто): список ВСЕХ рецептов с наличием рун —
	# никакой «угадайки» парами; кнопка Крафт у каждой строки
	var craft_title := _label(20)
	craft_title.text = Loc.t("magic.craft")
	_magic_box.add_child(craft_title)
	var craft_scroll := ScrollContainer.new()
	craft_scroll.custom_minimum_size = Vector2(0, 240)
	_magic_box.add_child(craft_scroll)
	var craft_box := VBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 6)
	craft_scroll.add_child(craft_box)
	_spell_craft_rows = []
	for r in Game.magic.cfg.get("recipes", []):
		var spell_id := String(r["spell"])
		var cdef: Dictionary = Game.magic.spell(spell_id)
		if cdef.is_empty():
			continue
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _panel_style(true))
		var vbox := VBoxContainer.new()
		row.add_child(vbox)
		var name_label := _label(15)
		name_label.text = Loc.t(String(cdef["loc"]))
		vbox.add_child(name_label)
		var need_label := _label(13)
		need_label.modulate = Color(1, 1, 1, 0.72)
		vbox.add_child(need_label)
		var btn := Button.new()
		btn.text = Loc.t("magic.craft_make")
		btn.custom_minimum_size = Vector2(0, 30)
		btn.focus_mode = Control.FOCUS_NONE
		var ra := String(r["a"])
		var rb := String(r["b"])
		btn.pressed.connect(func() -> void:
			city.craft_spell(ra, rb)
			_rebuild_craft_rows())
		vbox.add_child(btn)
		craft_box.add_child(row)
		_spell_craft_rows.append({"spell_id": spell_id, "a": ra, "b": rb,
				"need": need_label, "btn": btn})
	# v1.66: подсказка быстрого каста Z/X — первые два изученных
	_slot_hint = _label(14)
	_slot_hint.modulate = Color(1, 1, 1, 0.7)
	_magic_box.add_child(_slot_hint)''', 'panel-rows')

# декларации новых переменных панели
rep('scripts/city_hud_base.gd', '''var _rune_slot_a: OptionButton''',
    '''var _spell_craft_rows: Array = []
var _slot_hint: Label = null
var _rune_slot_a: OptionButton''', 'panel-vars')

# _rebuild_rune_slots -> перестройка статусов строк
rep('scripts/city_hud_build.gd',
    '''func _rebuild_rune_slots() -> void:
	for slot in [_rune_slot_a, _rune_slot_b]:
		slot.clear()
		for stack in Game.inventory:
			var item_id := String(stack["id"])
			if not item_id.begins_with("rune_"):
				continue
			var text := "%s ×%d" % [Loc.t(_rune_loc(item_id)), int(stack["count"])]
			slot.add_item(text)
			slot.set_item_metadata(slot.item_count - 1, item_id)
	_update_craft_preview()''',
    '''func _rebuild_craft_rows() -> void:
	_update_craft_preview()


## v1.66: статусы строк крафта — руны рюкзака против каждого рецепта.
func _update_craft_preview() -> void:
	var known_lines: Array = []
	for row in _spell_craft_rows:
		var spell_id := String(row["spell_id"])
		var ra := int(Game.count_item(String(row["a"])))
		var rb := int(Game.count_item(String(row["b"])))
		var need_pair := 2 if String(row["a"]) == String(row["b"]) else 1
		var need_label: Label = row["need"]
		var btn: Button = row["btn"]
		if Game.has_spell(spell_id):
			var lvl := Game.spell_level(spell_id)
			need_label.text = "%s — %s" % [Loc.t("magic.craft_known"),
					Loc.t("magic.level") % lvl]
			btn.visible = false
			known_lines.append("%s (ур. %d)" % [Loc.t("spell." + spell_id), lvl])
			continue
		btn.visible = true
		var have_a := ra >= (2 if String(row["a"]) == String(row["b"]) else 1)
		var have_b := rb >= (2 if String(row["b"]) == String(row["a"]) else 1)
		var names := "%s + %s" % [Loc.t(_rune_loc(String(row["a"]))),
				Loc.t(_rune_loc(String(row["b"])))]
		if have_a and have_b:
			need_label.text = "%s — %s" % [names, Loc.t("magic.craft_ready")]
			btn.disabled = false
		else:
			var miss_arr: Array = []
			if not have_a:
				miss_arr.append(Loc.t(_rune_loc(String(row["a"]))))
			if not have_b:
				miss_arr.append(Loc.t(_rune_loc(String(row["b"]))))
			need_label.text = "%s — %s %s" % [names, Loc.t("magic.craft_need"),
					" + ".join(miss_arr)]
			btn.disabled = true
	# подсказка быстрого каста: первые два изученных (Z/X в городе)
	if _slot_hint != null:
		var parts: Array = []
		for i in mini(2, Game.spellbook.size()):
			parts.append("%s — %s" % ["ZX"[i], Loc.t("spell." + String(Game.spellbook[i]))])
		_slot_hint.text = Loc.t("magic.slots_hint") % (" + ".join(parts) if not parts.is_empty() else Loc.t("magic.slots_none"))''', 'rows-refresh')

# старые функции-заглушки: _on_craft_pressed и _selected_rune больше не нужны
rep('scripts/city_hud_build.gd',
    '''func _on_craft_pressed() -> void:
	city.craft_spell(_selected_rune(_rune_slot_a), _selected_rune(_rune_slot_b))
	_rebuild_rune_slots()''',
    '''func _selected_rune(_slot: OptionButton) -> String:
	return ""   # v1.66: дропдауны рун заменены списком рецептов''', 'on-craft-gone')

# _refresh_magic: обновлять строки крафта (статусы меняются с рунами)
rep('scripts/city_hud_build.gd',
    '''func _refresh_magic() -> void:
	_pollution_big.text = _pollution_text()''',
    '''func _refresh_magic() -> void:
	_update_craft_preview()   # v1.66: статусы крафта всегда свежие
	_pollution_big.text = _pollution_text()''', 'refresh-craft')

# --- 5) Z/X в городе: быстрый каст первых двух изученных ---------------------
rep('scripts/city_input.gd',
    '''	if event.is_action_pressed("interact"):''',
    '''	# v1.66 (магия-просто): Z/X — быстрый каст первых двух изученных
	# заклинаний (в данже 1–9 уже работают — спеллбук по порядку)
	if event is InputEventKey and event.pressed and not event.echo \\
			and (event.physical_keycode == KEY_Z or event.physical_keycode == KEY_X):
		var slot_idx := 0 if event.physical_keycode == KEY_Z else 1
		if slot_idx < Game.spellbook.size():
			city.cast_combat_spell(String(Game.spellbook[slot_idx]))
		else:
			hud.toast(Loc.t("magic.slot_empty"))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):''', 'city-zx')

# --- 6) XP/звук/множитель в кастах -------------------------------------------
rep('scripts/city.gd',
    '''func cast_combat_spell(spell_id: String) -> void:
	var err: String = _cast_combat_spell(spell_id)
	if err == "":
		hud.toast(Loc.t("magic.cast_done") % Loc.t("spell." + spell_id))
	else:
		hud.toast(Loc.t(err))''',
    '''func cast_combat_spell(spell_id: String) -> void:
	var err: String = _cast_combat_spell(spell_id)
	if err == "":
		var lvl := Game.spell_cast(spell_id)   # v1.66: прокачка использованием
		SfxLib.play("spell_" + String(Game.magic.spell(spell_id).get("school", "wild")))
		hud.toast(Loc.t("magic.cast_done") % Loc.t("spell." + spell_id)
				+ (" " + Loc.t("magic.level") % lvl if lvl > 0 else ""))
	else:
		hud.toast(Loc.t(err))''', 'city-combat-xp')

rep('scripts/city.gd',
    '''	p2["damage"] = int(round(float(p2.get("damage", 0)) * hero.spell_mult()))''',
    '''	p2["damage"] = int(round(float(p2.get("damage", 0)) * hero.spell_mult()
			* Game.spell_power(spell_id)))   # v1.66: прокачка заклинания''', 'city-power')

rep('scripts/city.gd',
    '''func cast_city_spell(spell_id: String) -> void:''',
    '''func cast_city_spell(spell_id: String) -> void:
	SfxLib.play("spell_" + String(Game.magic.spell(spell_id).get("school", "wild")))   # v1.65.3
	Game.spell_cast(spell_id)   # v1.66: городские касты тоже качают''', 'city-cast-city')

# данж: звук + xp + множитель
rep('scripts/dungeon_build.gd',
    '''	hero.mana -= cost''',
    '''	hero.mana -= cost
	SfxLib.play("spell_" + String(Game.magic.spell(spell_id).get("school", "wild")))   # v1.65.3
	Game.spell_cast(spell_id)   # v1.66: прокачка использованием''', 'dungeon-cast')

rep('scripts/dungeon_build.gd',
    '''	params2["damage"] = int(round(float(params2.get("damage", 0)) * hero.spell_mult()))
	params2["heal"] = int(round(float(params2.get("heal", 0)) * hero.spell_mult()))''',
    '''	params2["damage"] = int(round(float(params2.get("damage", 0)) * hero.spell_mult()
			* Game.spell_power(spell_id)))   # v1.66
	params2["heal"] = int(round(float(params2.get("heal", 0)) * hero.spell_mult()
			* Game.spell_power(spell_id)))''', 'dungeon-power')

# --- 7) гарантия первого заклинания ------------------------------------------
rep('scripts/dungeon.gd',
    '''func _check_dungeon_cleared() -> void:''',
    '''func _check_dungeon_cleared() -> void:
	_first_spell_teach()''', 'check-hook')

rep('scripts/dungeon.gd',
    '''func _check_dungeon_cleared() -> void:
	_first_spell_teach()''',
    '''func _first_spell_teach() -> void:
	# v1.66 (магия-просто): первый зачищенный данж гарантирует руны
	# первого заклинания + подсказку (дизайн-док 15-ОЖИВЛЕНИЕ, аспект 2)
	var gift: Array = Game.first_spell_gift()
	if gift.is_empty():
		return
	for rune_id in gift:
		Game.add_item(rune_id, 1)
	hud.toast(Loc.t("tut.first_spell"))


func _check_dungeon_cleared() -> void:''', 'first-gift')

# --- 8) локализация ----------------------------------------------------------
loc_new = {
    "magic.craft_ready": "руны на месте — скрафти",
    "magic.craft_need": "не хватает:",
    "magic.slot_empty": "Заклинание не изучено — скрафти на алтаре (R)",
    "magic.slots_hint": "Быстрый каст: %s",
    "magic.slots_none": "Быстрый каст: пока нет заклинаний",
    "magic.level": "ур. %d",
    "tut.first_spell": "В РЮКЗАКЕ РУНЫ ПЕРВОГО ЗАКЛИНАНИЯ! Вернись в город: алтарь (R) — скрафти и колдуй на Z/X.",
}
# слить в loc/ru.json
import json
lp = 'loc/ru.json'
d = json.load(open(lp, encoding='utf-8'))
for k, v in loc_new.items():
    d[k] = v
json.dump(d, open(lp, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
ok.append('loc')

# keybar города: Z/X в строку клавиш
rep('loc/ru.json', '', '', 'noop')  # no-op, правки строки ниже точечно
ks = read('loc/ru.json')
import json as _json
dd = _json.loads(ks)
if 'city.keys_bar' in dd and 'Z/X' not in dd['city.keys_bar']:
    dd['city.keys_bar'] = dd['city.keys_bar'] + ' · Z/X — заклинания'
    _json.dump(dd, open(lp, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    ok.append('keybar')

write('_report.txt', 'APPLIED: ' + ', '.join(ok) + '\nMISSED: ' + ', '.join(miss))
print('APPLIED:', ok)
print('MISSED:', miss)
