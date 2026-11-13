# Часть: сцена города — магия (крафт/каст/зачарование), боевые заклинания героя,
# автономия, E-действия, переходы в данж и на карту мира.
# Корень extends-цепочки: сцена scenes/city.tscn ссылается на этот файл.
extends "res://scripts/city_input.gd"

## Крафт из панели магии: пара рун по таблице рецептов, только у работающего алтаря.
func craft_spell(rune_a: String, rune_b: String) -> void:
	if rune_a == "" or rune_b == "":
		hud.toast(Loc.t("magic.craft_need_two"))
		return
	if not sim.altar_ready():
		hud.toast(Loc.t("magic.no_altar"))
		return
	var spell_id: String = Game.magic.recipe_result(rune_a, rune_b)
	if spell_id == "":
		hud.toast(Loc.t("magic.craft_none"))
		return
	if Game.has_spell(spell_id):
		hud.toast(Loc.t("magic.craft_known"))
		return
	if Game.count_item(rune_a) < 1 or Game.count_item(rune_b) < 1:
		hud.toast(Loc.t("magic.craft_need_two"))
		return
	Game.remove_item(rune_a, 1)
	Game.remove_item(rune_b, 1)
	Game.learn_spell(spell_id)
	hud.toast(Loc.t("magic.craft_done") % Loc.t("spell." + spell_id))


## Городское заклинание из панели магии (расход — кристаллы из пула).
func cast_city_spell(spell_id: String) -> void:
	SfxLib.play("spell_" + String(Game.magic.spell(spell_id).get("school", "wild")))   # v1.65.3
	Game.spell_cast(spell_id)   # v1.66: городские касты тоже качают
	var def: Dictionary = Game.magic.spell(spell_id)
	if def.is_empty():
		return
	var err: String = sim.cast_city_spell(def)
	if err == "":
		hud.toast(Loc.t("magic.cast_done") % Loc.t(String(def["loc"])))
	else:
		hud.toast(Loc.t("magic." + err))


## Выбор зачарования в панели; повторное нажатие / ПКМ / Esc отменяет.
func set_enchant_mode(ench_id: String) -> void:
	if ench_id != "" and _guest_block():
		return
	enchant_mode = "" if enchant_mode == ench_id else ench_id
	view.enchant_mode = enchant_mode
	if enchant_mode == "":
		hud.set_enchant_hint("")
		return
	var def: Dictionary = Game.magic.enchantment(ench_id)
	var target_name := Loc.t("city.any_bld") if String(def.get("target", "any")) == "any" \
			else _bld_name(String(def["target"]))
	hud.set_enchant_hint(Loc.t("magic.enchant_pick") % target_name)


func _try_enchant() -> void:
	var ench_id := enchant_mode
	set_enchant_mode("")
	var bld: Dictionary = sim.building_at(map.tile_of_px(get_global_mouse_position()))
	if bld.is_empty():
		hud.toast(Loc.t("magic.enchant_wrong"))
		return
	var err: String = sim.enchant_building(bld, Game.magic.enchantment(ench_id), Game.inventory)
	if err == "":
		hud.toast(Loc.t("magic.enchant_done") % _bld_name(String(bld["type"])))
	else:
		hud.toast(Loc.t("magic." + err))


## Скорость города: x1/x2/x3 (пункт плана M2). Пауза снимается.
func set_speed(value: int) -> void:
	sim.speed = value
	sim.paused = false


# --- боевые заклинания героя в городе (v1.49: паритет с данжем) -------------

## Свиток из панели экипировки: тратит предмет, кастует бесплатно.
func _cast_scroll(item_id: String) -> String:
	var item: Dictionary = Game.item_def(item_id)
	var spell_id := String(item.get("spell_id", ""))
	if spell_id == "" or Game.magic.spell(spell_id).is_empty():
		return "eq.not_usable"
	if Game.count_item(item_id) < 1:
		return "eq.not_owned"
	if hero.dead:
		return "eq.not_usable"
	if hero.spell_cd_left(spell_id) > 0.0:
		return "magic.cooldown"
	Game.remove_item(item_id, 1)
	_cast_combat_spell(spell_id, true)
	return ""


## Каст из панели магии (R): боевое заклинание героя по курсору/на себя.
func cast_combat_spell(spell_id: String) -> void:
	var err: String = _cast_combat_spell(spell_id)
	if err == "":
		var lvl := Game.spell_cast(spell_id)   # v1.66: прокачка использованием
		SfxLib.play("spell_" + String(Game.magic.spell(spell_id).get("school", "wild")))
		hud.toast(Loc.t("magic.cast_done") % Loc.t("spell." + spell_id)
				+ (" " + Loc.t("magic.level") % lvl if lvl > 0 else ""))
	else:
		hud.toast(Loc.t(err))


## Боевое заклинание в городе: та же математика, что в данже (dungeon.gd),
## но урон считают данные симуляции — рейдеры не ноды. "" — успех.
func _cast_combat_spell(spell_id: String, free_cast := false) -> String:
	if hero.dead:
		return "eq.not_usable"
	var def: Dictionary = Game.magic.spell(spell_id)
	if def.is_empty() or String(def["where"]) != "dungeon":
		return "magic.city_only" if String(def.get("where", "")) == "city" else "eq.not_usable"
	if spell_id == "light_beacon":
		return "magic.city_only"   # маяк света — только тьма данжа
	if hero.spell_cd_left(spell_id) > 0.0:
		return "magic.cooldown"
	var cost := 0 if free_cast else int(def.get("mana_cost", 0))
	if hero.mana < cost:
		return "magic.no_mana"
	hero.mana -= cost
	# магия качает статы (v1.24): каст — интеллект, трата маны — мудрость
	var ha: Dictionary = hero.attrs_cfg()
	Game.hero_train("int", float(ha.get("train_cast_int", 0.15)))
	if cost > 0:
		Game.hero_train("wis", float(ha.get("train_cast_wis", 0.05)) \
				+ float(ha.get("train_mana_wis", 0.04)) * float(cost))
	hero.set_spell_cd(spell_id, float(def.get("cooldown", 3.0)) * hero.skill_mult("spell_cd_mult", 1.0))
	var p2: Dictionary = def.get("params", {}).duplicate(true)
	p2["damage"] = int(round(float(p2.get("damage", 0)) * hero.spell_mult()
			* Game.spell_power(spell_id)))   # v1.66: прокачка заклинания
	p2["heal"] = int(round(float(p2.get("heal", 0)) * hero.spell_mult()))
	var col: Color = Game.magic.school_color(String(def["school"]))
	match spell_id:
		"fire_flash", "corrupt_blast", "void_rift":
			var pos: Vector2 = _cast_point(float(p2.get("range", 200.0)))
			sim.hero_spell_burst(pos, float(p2.get("radius", 46.0)) * hero.skill_mult("radius_mult", 1.0),
					int(p2.get("damage", 4)))
			_add_fx("burst", col, float(p2.get("radius", 46.0)), 0.4, pos)
		"chain_bolt":
			sim.hero_spell_burst(hero.global_position,
					float(p2.get("radius", 170.0)), int(p2.get("damage", 2)),
					int(p2.get("targets", 3)))
			_add_fx("ring", col, float(p2.get("radius", 170.0)) * 0.5, 0.35, hero.global_position)
		"heal":
			hero.heal(int(p2.get("heal", 5)))
			_add_fx("ring", col, 22.0, 0.5, hero.global_position)
		"shield":
			hero.cast_shield(float(p2.get("duration", 5.0)))
			_add_fx("ring", col, 26.0, 0.6, hero.global_position)
		"stone_skin":
			hero.temp_armor_bonus(float(p2.get("duration", 10.0)), int(p2.get("armor", 1)))
			_add_fx("ring", col, 24.0, 0.5, hero.global_position)
		"overcharge":
			hero.temp_damage_bonus(float(p2.get("duration", 8.0)), int(p2.get("damage_bonus", 2)))
			_add_fx("ring", col, 24.0, 0.5, hero.global_position)
		"roots":
			var rpos: Vector2 = _cast_point(float(p2.get("range", 200.0)))
			sim.slow_raiders_at(rpos, float(p2.get("radius", 58.0)), float(p2.get("stun", 3.0)))
			_add_fx("zone", col, float(p2.get("radius", 58.0)), 0.6, rpos)
		"thorns", "plague":
			# v1.49: зона работает разово — суммарный урон dps×длительность + замедление
			var zpos: Vector2 = _cast_point(float(p2.get("range", 200.0)))
			var zr: float = float(p2.get("radius", 58.0))
			var total: int = int(round(float(p2.get("dps", 1)) * float(p2.get("duration", 4.0)) * hero.spell_mult()))
			sim.hero_spell_burst(zpos, zr, total)
			sim.slow_raiders_at(zpos, zr, float(p2.get("duration", 4.0)))
			_add_fx("zone", col, zr, 0.7, zpos)
		"drain_life":
			var dres: Dictionary = sim.hero_spell_burst(hero.global_position,
					float(p2.get("radius", 180.0)), int(p2.get("damage", 3)),
					int(p2.get("targets", 2)))
			if int(dres["hits"]) > 0:
				hero.heal(int(dres["hits"]) * int(p2.get("heal_per_target", 2)))
			_add_fx("ring", col, 24.0, 0.45, hero.global_position)
		"soul_burn":
			var spos: Vector2 = _cast_point(float(p2.get("range", 200.0)))
			var sres: Dictionary = sim.hero_spell_burst(spos, float(p2.get("radius", 60.0)),
					int(p2.get("damage", 5)), 1)
			if int(sres["hits"]) > 0:
				hero.add_mana(int(p2.get("mana_per_target", 1)))
			_add_fx("burst", col, float(p2.get("radius", 60.0)), 0.45, spos)
	# дикая магия загрязняет регион (как из данжа)
	if float(def.get("pollution", 0.0)) > 0.0:
		sim.add_pollution(float(def["pollution"]))
	return ""


## Точка каста: курсор, не дальше range_px от героя (как в данже).
func _cast_point(range_px: float) -> Vector2:
	var to: Vector2 = get_global_mouse_position() - hero.global_position
	if to.length() <= range_px:
		return hero.global_position + to
	return hero.global_position + to.normalized() * range_px


## Визуал заклинания (тот же SpellFx, что в данже).
func _add_fx(kind: String, col: Color, radius: float, dur: float, pos: Vector2) -> void:
	var fx = load("res://scripts/spell_fx.gd").new()
	fx.setup(kind, col, radius, dur)
	fx.position = pos
	add_child(fx)


## Кнопка «Автономия» (правки v1.12.0): с 10 поселенцев деревня живёт сама.
## Отказ честно объясняется тостом (мало поселенцев или уже автономна).
func go_autonomous() -> void:
	if guest:
		return   # чужой город уже живёт сам — решение не героя
	var err_key: String = sim.go_autonomous()
	if err_key == "city.autonomy_need":
		hud.toast(Loc.t(err_key) % sim.autonomy_pop())
	elif err_key != "":
		hud.toast(Loc.t(err_key))
	hud.refresh()


## E у природы или стройки: герой работает сам (правки v1.12.2).
## Порядок: стройка → ремонт (этап 2, аспект 5) → дерево → скала/руда → сбор →
## посев → вспашка (2026-10-21: герой сам сеет и пашет поля).
func _hero_act() -> bool:
	if _hero_work_cd > 0.0:
		return false   # кулдаун: молча, тосты не спамим
	var hw: Dictionary = cfg.get("hero_work", {})
	var res: String = sim.hero_build(hero.position)
	if res != "" and res != "done":
		SfxLib.play("hammer")   # v1.65.3
	if res == "" and not _hero_repair_bld.is_empty():
		var err: String = sim.repair_building(_hero_repair_bld)
		if err == "":
			_hero_work_cd = float(hw.get("cooldown", 0.35))
			return true   # тост покажет событие bld_repaired
		if err == "no_res":
			hud.toast(Loc.t("city.repair_no_res") % _cost_str(sim.repair_cost(String(_hero_repair_bld["type"]))))
			_hero_work_cd = float(hw.get("cooldown", 0.35))
			return true
	# "full" между кадрами починила мастерская — идём дальше
	if res == "":
		res = sim.hero_haul(hero.position)
	if res == "":
		res = sim.hero_chop(hero.position)
		if res != "":
			SfxLib.play("chop")   # v1.65.3: удар топора (вал — событием tree_felled)
	if res == "":
		res = sim.hero_mine(hero.position)
		if res != "":
			SfxLib.play("mine")   # v1.65.3: удар кирки
	if res == "":
		res = sim.hero_harvest(hero.position)
	if res == "":
		res = sim.hero_sow(hero.position)
	if res == "":
		res = sim.hero_till(hero.position)
	if res == "":
		return false
	_hero_work_cd = float(hw.get("cooldown", 0.35))
	# труд качает стату героя (v1.24): рубка и копилка — силу и выносливость
	var ha: Dictionary = hero.attrs_cfg()
	Game.hero_train("str", float(ha.get("train_work_str", 0.1)))
	Game.hero_train("end", float(ha.get("train_work_end", 0.05)))
	match res:
		"fell":
			hud.toast(Loc.t("city.hero_tree_felled"))
		"ore":
			hud.toast(Loc.t("city.hero_ore_found"))
		"gem":
			hud.toast(Loc.t("city.hero_gem_found"))
		"stone":
			hud.toast(Loc.t("city.hero_rock_done"))
		"food":
			hud.toast(Loc.t("city.hero_harvest_done"))
		"sow":
			hud.toast(Loc.t("city.hero_sow_done"))
		"no_seeds":
			hud.toast(Loc.t("city.hero_sow_no_seeds"))
		"tilled":
			hud.toast(Loc.t("city.hero_till_done"))
		"done":
			# стена/ворота стали преградой — не даём герою остаться внутри
			var st: Vector2i = map.tile_of_px(hero.position)
			if not map.is_walkable(st):
				for n in [st + Vector2i(1, 0), st + Vector2i(-1, 0),
						st + Vector2i(0, 1), st + Vector2i(0, -1)]:
					if map.in_bounds(n) and map.is_walkable(n):
						hero.position = map.tile_center_px(n)
						break
	return true


## Комплект героя из оружейки: металл из пула, бонусы урона/брони (M5.1).
func _buy_hero_kit() -> void:
	var err: String = Game.buy_hero_kit(cfg, sim)
	if err == "":
		var kit: Dictionary = Game.hero_kit_bonus(cfg)
		hero.bonus_damage = int(kit["damage"])
		hero.bonus_armor = int(kit["armor"])
		hud.toast(Loc.t("city.armory_bought_toast") % Game.hero_kits)
	elif err == "armory_max":
		hud.toast(Loc.t("city.armory_max_toast"))
	else:
		hud.toast(Loc.t("city.armory_no_metal_toast"))


func _enter_dungeon() -> void:
	sim.speed = 1
	sim.paused = false
	get_tree().change_scene_to_file(DUNGEON_SCENE)


## Шаг за край города — на карту мира (фидбек приёмки M8): вся рамка карты —
## зона перехода. На карте мира герой появляется с той же стороны города.
## В поселении НПС («Мир v2», этап 3) — к клетке поселения, визит окончен.
func _exit_to_world(dir: Vector2i) -> void:
	sim.speed = 1
	sim.paused = false
	if Game.world_map == null:
		Game.new_world()
	if guest:
		var poi: Dictionary = Game.world_map.poi_by_id(Game.visiting_city_id)
		var base: Vector2i = poi["tile"] if not poi.is_empty() else Game.world_map.city_tile
		Game.world_hero_tile = Game.world_map.nearest_walkable(base + dir)
		Game.visiting_city_id = -1
	else:
		Game.world_hero_tile = Game.world_map.nearest_walkable(Game.world_map.city_tile + dir)
	Game.city_return_tile = Vector2i(-1, -1)
	get_tree().change_scene_to_file(WORLD_SCENE)


## Герой в одном тайле от рамки карты — подсказка о выходе в мир.
func _near_map_border() -> bool:
	var t: Vector2i = map.tile_of_px(hero.position)
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if map.border_dir(t + d) != Vector2i.ZERO:
			return true
	return false


func _default_hint() -> String:
	if guest:
		return "%s   ·   %s" % [Loc.t("city.guest_hint"), Loc.t("city.world_exit_hint")]
	return "%s   ·   %s   ·   %s" % [Loc.t("city.enter_anomaly"),
			Loc.t("city.world_exit_hint"), Loc.t("city.back_hint")]


## Подсветка зданий под курсором в режиме зачарования — рисует view.
func enchant_target_valid(tile: Vector2i) -> bool:
	var def: Dictionary = Game.magic.enchantment(enchant_mode)
	var bld: Dictionary = sim.building_at(tile)
	if def.is_empty() or bld.is_empty() or not sim._active(bld):
		return false
	var target := String(def.get("target", "any"))
	return target == "any" or String(bld["type"]) == target


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
