# Часть: сцена города — hover-подписи, сплетни, письма, роутер событий sim.events,
# имена, день/ночь, смерть героя и лут руин. Один класс, поведение не меняется.
extends "res://scripts/city_base.gd"

## Нет здания — подписываем зону (поле/пастбище и пр., 2026-10-21).
func _update_hover() -> void:
	if build_mode != "" or enchant_mode != "" or zone_mode != "" or road_mode or plant_mode \
			or move_mode or plaza_mode:
		hud.set_hover_info("", Vector2.ZERO)
		return
	# житель-кружок под курсором (правки v1.20): имя, специальность,
	# куда идёт и о чём думает — инструмент отладки жизни деревни
	var res_tt := _resident_hover_text()
	if res_tt != "":
		hud.set_hover_info(res_tt, get_viewport().get_mouse_position())
		return
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	var b: Dictionary = sim.building_at(tile)
	if b.is_empty():
		var zone_text := _zone_hover_text(sim.zone_at(tile))
		if zone_text == "":
			hud.set_hover_info("", Vector2.ZERO)
			return
		hud.set_hover_info(zone_text, get_viewport().get_mouse_position())
		return
	hud.set_hover_info(_hover_text(b), get_viewport().get_mouse_position())


## Тултип кружка жителя у мыши: имя + профессия + мысль (куда идёт, что делает).
func _resident_hover_text() -> String:
	var mouse := get_global_mouse_position()
	var best: Dictionary = {}
	var best_d := 22.0
	for r in sim.residents:
		if int(r.get("inside", 0)) > 0:
			continue   # спит внутри — не на карте
		var d: float = (r["pos"] as Vector2).distance_to(mouse)
		if d < best_d:
			best_d = d
			best = r
	if best.is_empty():
		return ""
	sim.log_thought(best)   # наведение — мысль уходит в журнал отладки
	var prof := String(best["prof"])
	var prof_name := Loc.t("prof.elder_golem") if prof == "elder" else ""
	if prof_name == "" and prof != "":
		prof_name = _prof_name(prof)
	elif prof == "":
		prof_name = Loc.t("city.res_child")
	return "%s • %s\n%s" % [String(best["name"]), prof_name, sim.resident_thought(best)]


## Подпись зоны при наведении: имя + живая статистика поля/пастбища.
func _zone_hover_text(z: Dictionary) -> String:
	if z.is_empty():
		return ""
	var type_id := String(z["type"])
	var name := Loc.t("zone." + type_id)
	if type_id == "field":
		var st: Dictionary = sim.field_stats(z)
		var crop := Loc.t(String(sim.crop_def(String(z.get("crop", "turnip"))).get("loc", "")))
		if int(st["ripe"]) > 0:
			return Loc.t("city.hover_field_ripe") % [name, crop, int(st["ripe"]), int(st["filled"])]
		return Loc.t("city.hover_field") % [name, crop, int(st["sown"]), int(st["filled"])]
	if type_id == "pasture":
		var cap: int = sim.pasture_capacity(z)
		return Loc.t("city.hover_pasture") % [name, sim._livestock_in(int(z["id"])), maxf(cap, 1)]
	var fill_work: float = float(cfg.get("zones", {}).get("fill_work", 4.0))
	var filled := 0
	for i in (z["cells"] as Array).size():
		if float((z["progress"] as Array)[i]) >= fill_work:
			filled += 1
	return Loc.t("city.hover_zone_progress") % [name, filled, (z["cells"] as Array).size()]


func _hover_text(b: Dictionary) -> String:
	var text := _hover_base(b)
	# куча ресурса у здания (M6): «куча: 12 еда»
	if bool(b["done"]) and (b as Dictionary).has("pile"):
		var pile: Dictionary = b["pile"]
		var total := 0.0
		var key := ""
		var best := 0.0
		for k in pile:
			total += float(pile[k])
			if float(pile[k]) > best:
				best = float(pile[k])
				key = String(k)
		if total >= 0.5:
			text += " • " + Loc.t("city.hover_pile") % [int(total), Loc.t("res." + key)]
	return text


func _hover_base(b: Dictionary) -> String:
	var bld_name := _bld_name(String(b["type"]))
	if not bool(b["done"]):
		var work := 1.0
		for d in cfg["buildings"]:
			if String(d["id"]) == String(b["type"]):
				work = float(d["build_work"])
		var pct := int(clampf(float(b["progress"]) / work * 100.0, 0.0, 100.0))
		return Loc.t("city.hover_site") % [bld_name, pct]
	# руины (этап 2, аспект 5): чинятся героем за 40% стоимости
	if bool(b.get("razed", false)):
		return Loc.t("city.hover_razed") % bld_name
	if float(b.get("stun_left", 0.0)) > 0.0:
		return Loc.t("city.hover_stun") % bld_name
	if _bld_effect(b) == "gate":
		return "%s • %s" % [bld_name, Loc.t("city.gate_open" if sim.is_gate_open(b) else "city.gate_closed")]
	if String(b.get("enchant", "")) != "":
		return "%s • %s" % [bld_name, Loc.t("ench." + String(b["enchant"]))]
	# кладбище (M11): после раскрытия видно тьму и численность тайной армии
	if String(b["type"]) == "cemetery" and sim.necro_known:
		return "%s • %s" % [bld_name, Loc.t("city.hover_necro")
				% [int(round(float(sim.necro_dark) * 100.0)), int(sim.necro_army)]]
	# повреждённое здание показывает прочность (E — ремонт за 40%)
	var max_hp := float(sim._bld_max_hp(String(b["type"])))
	if float(b.get("hp", max_hp)) < max_hp:
		return Loc.t("city.hover_damaged") % [bld_name,
				int(round(100.0 * float(b.get("hp", max_hp)) / max_hp))]
	return bld_name


## Текст события региона (v1.55) по словарю из npc_cities.rivalry_day.
## Бонусы герою от уникальных богатств (v1.57): кристалл лича — заклинания,
## кровь вампира — здоровье. Пока ресурсы в пуле города.
func _apply_resource_hero_bonuses() -> void:
	if hero == null or sim == null:
		return
	hero.resource_spell_mult = 1.15 if float(sim.res.get("lich_crystal", 0.0)) >= 1.0 else 1.0
	hero.resource_hp = 15 if float(sim.res.get("vampire_blood", 0.0)) >= 1.0 else 0
	hero.hp = mini(hero.hp, hero.hp_max())


## Слухи и разговоры (v1.56): событие города → житель подходящей профессии
## «говорит» обоснованную фразу (урожай — фермер, жила — шахтёр...).
func _gossip(event_type: String, prof: String) -> void:
	if sim == null:
		return
	var candidates: Array = []
	for r in sim.residents:
		if String(r["prof"]) == prof and String(r.get("say", "")) == "" \
				and int(r.get("inside", 0)) == 0:
			candidates.append(r)
	if candidates.is_empty():
		return
	var pick: Dictionary = candidates[randi() % candidates.size()]
	pick["say"] = "say." + prof + "." + event_type
	pick["say_until"] = float(sim.time) + 9.0


## Текст события региона (v1.55) по словарю из npc_cities.rivalry_day.
func _region_text(ev: Dictionary) -> String:
	var key := "world." + String(ev["type"])
	match String(ev["type"]):
		"region_raid":
			return Loc.t(key) % [String(ev["name"]), int(ev["n"])]
		"region_migrants":
			return Loc.t(key) % [String(ev["name"]), String(ev["who"])]
		"region_sabotage":
			return Loc.t(key) % [String(ev["name"]), _bld_name(String(ev["bld"]))]
		"region_gift":
			return Loc.t(key) % [String(ev["name"]), int(ev["n"])]
		"region_war":
			return Loc.t(key) % [String(ev["winner"]), String(ev["loser"])]
		"region_capital", "region_capital_hold":
			return Loc.t(key) % int(ev["days"])
		"region_lost_capital":
			return Loc.t(key) % [String(ev["name"]), int(ev["rank"])]
		"caravan_in", "caravan_out":
			return Loc.t(key) % [String(ev["name"]), Loc.t("res." + String(ev["res"])),
					int(ev["n"]), int(ev["pay"])]
		"ally_raid":
			return Loc.t(key) % [String(ev["name"]), int(ev["n"])]
	return Loc.t(key)


## Донесение-письмо вместо тоста (v1.53): крупные события — справа.
func _letter(ev_type: String, msg: String) -> void:
	hud.toast(msg)   # короткая вспышка внизу остаётся
	if _notices != null:
		_notices.push(ev_type, msg)


func _process_events() -> void:
	for ev in sim.events:
		var bld_name := _bld_name(String(ev.get("bld", "")))
		match String(ev["type"]):
			"site":
				hud.toast(Loc.t("city.site_started") % bld_name)
			"built":
				hud.toast(Loc.t("city.built_done") % bld_name)
				_rebuild_collision()
				Game.stat("buildings")   # статистика (M14-K)
				_gossip("built", "builder")   # v1.56: строитель гордится
			"no_worker":
				hud.toast(Loc.t("city.no_free_worker") % bld_name)
			"wild_flash":
				hud.toast(Loc.t("magic.wild_flash") % bld_name)
			"wild_surge":
				hud.toast(Loc.t("magic.wild_surge"))
			"wild_gift":
				hud.toast(Loc.t("magic.wild_gift"))
			"refugee":
				_letter("refugee", Loc.t("city.refugee_came") % String(ev["name"]))
			"birth":
				hud.toast(Loc.t("city.birth_toast") % String(ev["name"]))
			"grown":
				hud.toast(Loc.t("city.grown_toast") % [String(ev["name"]), _prof_name(String(ev["prof"]))])
			"died":
				hud.toast(Loc.t("city.died_toast") % String(ev["name"]))
			"wounded":
				hud.toast(Loc.t("city.wounded_toast") % String(ev["name"]))
			"learned":
				hud.toast(Loc.t("city.learned_toast") % [String(ev["name"]), _prof_name(String(ev["prof"]))])
			"autobuild":
				hud.toast(Loc.t("city.autobuild_toast") % [String(ev["name"]), _bld_name(String(ev["bld"]))])
			"golem_awakens":
				hud.toast(Loc.t("city.golem_toast"))
			"morning_plan":
				hud.toast(Loc.t("city.morning_plan_toast"))
			"winter_soon":
				_letter("winter_soon", Loc.t("city.winter_soon") % int(ev["days"]))
				hud.refresh()
			"legend_joined":
				_letter("legend_joined", Loc.t("world.legend_joined") % String(ev["name"]))
				hud.refresh()
			"hauled":
				hud.toast(Loc.t("city.hauled_toast") % [String(ev["name"]), int(ev["n"]),
						Loc.t("res." + String(ev["res"]))])
			"promoted":
				hud.toast(Loc.t("city.promoted_toast") % String(ev["name"]))
			"autonomy":
				hud.toast(Loc.t("city.autonomy_done"))
				hud.refresh()
			"gate":
				hud.toast(Loc.t("city.gate_open" if bool(ev["open"]) else "city.gate_closed"))
				# коллизии ворот не меняются (для героя ворота — дверь, v1.26)
			"skill_up":
				hud.toast(Loc.t("city.skill_up_toast") % [String(ev["name"]), Loc.t("skill." + String(ev["rank"]))])
			"quarrel":
				hud.toast(Loc.t("story.quarrel_toast") % [String(ev["a"]), String(ev["b"])])
			"friendship":
				hud.toast(Loc.t("story.friendship_toast") % [String(ev["a"]), String(ev["b"])])
			"discovery":
				hud.toast(Loc.t("story.discovery_toast") % [String(ev["name"]), Loc.t("res." + String(ev["res"]))])
			"betrayal":
				hud.toast(Loc.t("story.betrayal_toast") % String(ev["name"]))
			"betrayal_caught":
				hud.toast(Loc.t("story.betrayal_caught_toast") % String(ev["name"]))
			"mutation_good":
				hud.toast(Loc.t("story.mutation_good_toast") % String(ev["name"]))
			"mutation_bad":
				hud.toast(Loc.t("story.mutation_bad_toast") % String(ev["name"]))
			# --- угрозы (M5) ---
			"raid_warn":
				_gossip("raid", "guard")   # v1.56: страж предупреждает
				_letter("raid_warn", Loc.t("city.raid_warn") % "%.1f" % float(ev["eta"]))
			"raid_start":
				_letter("raid_start", Loc.t("city.raid_siege_toast" if bool(ev["siege"]) else "city.raid_toast") % int(ev["count"]))
			"raid_repelled":
				_letter("raid_repelled", Loc.t("city.raid_repelled_toast") % int(ev["crystals"]))
			"raid_breached":
				_letter("raid_breached", Loc.t("city.raid_breached_toast") % int(ev["razed"]))
			"razed":
				_letter("razed", Loc.t("city.razed_toast") % bld_name)
				_rebuild_collision()
			"dungeon_calm":
				# данж у города зачищен — волны мутантов сдвинулись (2026-10-21)
				hud.toast(Loc.t("city.dungeon_calm_toast") % int(ev["days"]))
			# --- улей мутантов («Новый мир v2», v1.44) ---
			"hive_built":
				_letter("hive_built", Loc.t("event.hive_built"))
			"hive_grew":
				_letter("hive_grew", Loc.t("event.hive_grew") % int(ev["level"]))
			"hive_wave":
				_letter("hive_wave", Loc.t("event.hive_wave") % int(ev["count"]))
			"mutant_hit":
				hud.toast(Loc.t("event.mutant_hit") % String(ev["name"]))
			"hive_destroyed":
				_letter("hive_destroyed", Loc.t("event.hive_destroyed") % int(ev["level"]))
				_rebuild_collision()
			"hero_kill":
				# v1.49: убийства мутантов в городе качают навыки, как в данже
				var ups: int = Game.skills.add_xp(int(ev["xp"]))
				if ups > 0:
					hud.toast(Loc.t("hud.level_up") % Game.skills.level)
			# --- эпицентр катастрофы («Новый мир v2», v1.45) ---
			"twisted_fell":
				_letter("twisted_fell", Loc.t("event.twisted_fell") % String(ev["a"]))
			"twisted_attack":
				_letter("twisted_attack", Loc.t("event.twisted_attack") % String(ev["a"]))
			"eruption":
				_letter("eruption", Loc.t("event.eruption") % int(ev["power"]))
			# --- соцжизнь/паника (v1.47) ---
			"raid_panic":
				_letter("raid_panic", Loc.t("city.raid_panic_toast"))
			"date":
				hud.toast(Loc.t("city.date_toast") % [String(ev["a"]), String(ev["b"])])
			"jealous":
				hud.toast(Loc.t("city.jealous_toast") % [String(ev["name"]), String(ev["other"])])
			"mutant_hit":
				hud.toast(Loc.t("event.mutant_hit") % String(ev["name"]))
			"hero_haul":
				# герой унёс кучу здания на склад (2026-10-21)
				hud.toast(Loc.t("city.hero_haul_done") % [int(ev.get("n", 0)),
						Loc.t("res." + String(ev.get("res", "food")))])
			# --- ремонт и перенос (этап 2, аспект 5) ---
			"bld_repaired":
				hud.toast(Loc.t("city.restored_toast" if bool(ev.get("razed", false))
						else "city.repaired_toast") % [bld_name, _cost_str(ev.get("cost", {}))])
				_rebuild_collision()
			"city_repaired":
				# город чинит сам: строитель 50%, непрофильный житель 70% (v1.21.3)
				hud.toast(Loc.t("city.city_repaired_toast") % [String(ev.get("name", "")),
						_bld_name(String(ev["bld"])), int(round(float(ev.get("frac", 0.7)) * 100.0))])
				_rebuild_collision()
			"bld_moved":
				hud.toast(Loc.t("city.moved_toast") % bld_name)
				_rebuild_collision()
			"storm_warn":
				_letter("storm_warn", Loc.t("city.storm_warn_toast"))
			"storm_start":
				_letter("storm_start", Loc.t("city.storm_start_toast"))
			"storm_end":
				_letter("storm_end", Loc.t("city.storm_end_toast"))
			"storm_strike":
				_letter("storm_strike", Loc.t("city.storm_strike_toast") % bld_name)
			"hero_hit":
				hero.take_damage(int(ev["dmg"]))
			"hunt":
				hud.toast(Loc.t("city.hunt_toast") % [String(ev["name"]), int(ev["food"])])
			"guard_trained":
				hud.toast(Loc.t("city.guard_trained_toast") % String(ev["name"]))
			"hunter_trained":
				hud.toast(Loc.t("city.hunter_trained_toast") % String(ev["name"]))
			# --- зоны и логистика (M6) ---
			"zone_done":
				hud.toast(Loc.t("city.zone_done_toast") % Loc.t("zone." + String(ev["zone"])))
			"porter_trained":
				hud.toast(Loc.t("city.porter_trained_toast") % String(ev["name"]))
			"road_auto":
				hud.toast(Loc.t("city.road_auto_toast") % int(ev["count"]))
			# --- скот, поля, рынок (M10) ---
			"tame_sent":
				hud.toast(Loc.t("city.tame_sent_toast") % String(ev.get("name", "")))
			"pig_slaughtered":
				hud.toast(Loc.t("city.pig_slaughtered_toast") % int(ev.get("food", 0)))
			"livestock_tame":
				hud.toast(Loc.t("city.livestock_tame_toast") % Loc.t("animal." + String(ev["kind"])))
			"livestock_born":
				hud.toast(Loc.t("city.livestock_born_toast") % Loc.t("animal." + String(ev["kind"])))
			"livestock_food":
				hud.toast(Loc.t("city.livestock_food_toast") % int(ev["food"]))
			"orchard_harvest":
				hud.toast(Loc.t("city.orchard_toast") % int(ev["food"]))
			"caravan_arrived":
				_letter("caravan_arrived", Loc.t("city.caravan_arrived_toast"))
			"caravan_left":
				_letter("caravan_left", Loc.t("city.caravan_left_toast"))
			"caravan_sent":
				hud.toast(Loc.t("city.caravan_sent_toast") % [int(ev["amount"]), Loc.t("res." + String(ev["res"]))])
			"caravan_returned":
				_letter("caravan_returned", Loc.t("city.caravan_returned_toast") % int(ev["coins"]))
			"caravan_lost":
				_letter("caravan_lost", Loc.t("city.caravan_lost_toast") % Loc.t("res." + String(ev["res"])))
			# --- торговые палатки (этап 2, аспект 4) ---
			"tent_income":
				hud.toast(Loc.t("city.tent_income_toast") % int(ev["coins"]))
			"wanderer_arrived":
				hud.toast(Loc.t("city.wanderer_toast"))
			# --- вишлист M11: лес, скала, некромант ---
			"tree_felled":
				pass   # тихо: летопись знает, спиливать — работа
			"tree_sawed":
				pass   # тихо: доски упали в кучу лесопилки (v1.21)
			"quarry_processed":
				pass   # тихо: камень лежит в куче каменоломни (v1.21)
			"quarry_bonus":
				hud.toast(Loc.t("city.quarry_bonus_toast") % Loc.t("res." + String(ev["res"])))
			"mine_hauled":
				pass   # тихо: шахта копит руду и камень (v1.21)
			"farm_field":
				hud.toast(Loc.t("city.farm_field_toast") % int(ev["cells"]))
			"sapling_planted":
				hud.toast(Loc.t("city.sapling_toast"))
			"tree_grown":
				hud.toast(Loc.t("city.tree_grown_toast"))
			"forest_warn":
				_letter("forest_warn", Loc.t("city.forest_warn_toast"))
			"spirit_attack":
				hud.toast(Loc.t("city.spirit_toast") % int(ev.get("count", 0)))
			"forest_boss_attack":
				hud.toast(Loc.t("city.forest_boss_toast"))
			"forest_repelled":
				hud.toast(Loc.t("city.forest_repelled_toast"))
			"spirit_hit":
				hud.toast(Loc.t("city.spirit_hit_toast") % String(ev["name"]))
			"ore_revealed":
				hud.toast(Loc.t("city.ore_toast"))
				_rebuild_collision()
			"gem_found":
				hud.toast(Loc.t("city.gem_toast"))
			"rock_gone":
				hud.toast(Loc.t("city.rock_gone_toast"))
				_rebuild_collision()
			"necro_revealed":
				if String(ev.get("name", "")) != "":
					hud.toast(Loc.t("city.necro_seen_toast") % String(ev["name"]))
				else:
					hud.toast(Loc.t("city.necro_revealed_toast"))
			"necro_summon":
				hud.toast(Loc.t("city.necro_summon_toast"))
			"undead_rising":
				_letter("undead_rising", Loc.t("city.undead_toast") % int(ev.get("count", 0)))
			"necro_purged":
				hud.toast(Loc.t("city.necro_purged_toast"))
				_rebuild_collision()
			# --- кладбище и останки (v1.23) ---
			"cemetery_founded":
				hud.toast(Loc.t("city.cemetery_founded_toast"))
			"cremated":
				hud.toast(Loc.t("city.cremated_toast") % String(ev.get("name", "")))
			"corpse_buried":
				hud.toast(Loc.t("city.corpse_buried_toast") % Loc.t("enemy." + String(ev.get("kind", ""))))
			"spar":
				hud.toast(Loc.t("city.spar_toast") % [String(ev.get("a", "")), String(ev.get("b", ""))])
			"log_hauled":
				hud.toast(Loc.t("city.log_hauled_toast") % String(ev.get("name", "")))
			"dark_storm":
				_letter("dark_storm", Loc.t("city.dark_storm_toast"))
			# --- вишлист M13: пары и День основания ---
			"wedding":
				hud.toast(Loc.t("story.wedding_toast") % [String(ev["a"]), String(ev["b"])])
			"widow":
				hud.toast(Loc.t("story.widow_toast") % [String(ev["a"]), String(ev["b"])])
			"found_day":
				hud.toast(Loc.t("city.found_day_toast"))
			"found_skip":
				hud.toast(Loc.t("city.found_skip_toast"))
			# --- сейв (M14-A) ---
			"lux_made":
				hud.toast(Loc.t("event.lux_made"))
			"pests":
				hud.toast(Loc.t("event.pests") % int(ev["lost"]))
			"deposit_gone":
				hud.toast(Loc.t("event.deposit_gone"))
			"autosaved":
				hud.toast(Loc.t("menu.autosaved"))
			# --- жизнь v3 (M14-F) ---
			"goal_done":
				hud.toast(Loc.t("city.goal_done") % [String(ev["name"]), Loc.t("goal." + String(ev["goal"]))])
			"fest_gift":
				hud.toast(Loc.t("city.fest_gift") % [String(ev["a"]), String(ev["b"])])
			# --- управление (M14-H) ---
			"law_vote":
				hud.toast(Loc.t("city.law_vote") % [Loc.t("law." + String(ev["law"])),
						Loc.t("gov.law_passed") if bool(ev["ok"]) else Loc.t("gov.law_rejected")])
			"service":
				hud.toast(Loc.t("city.service"))
			"pray":
				hud.toast(Loc.t("god.prayed"))
			"bridge":
				hud.toast(Loc.t("city.bridge_done"))
			"quest_done":
				Game.stat("quests")
				hud.toast(Loc.t("city.quest_done") % [String(ev["customer"]), int(ev["reward"])])
			"story":
				Game.codex_seen("story", String(ev["id"]))
				hud.toast(Loc.t("story." + String(ev["id"])))
	sim.events.clear()


func _prof_name(prof_id: String) -> String:
	for p in cfg["professions"]:
		if String(p["id"]) == prof_id:
			return Loc.t(String(p["loc"]))
	return prof_id


func _bld_name(type_id: String) -> String:
	for b in cfg["buildings"]:
		if String(b["id"]) == type_id:
			return Loc.t(String(b["loc"]))
	return type_id


## Фактор ночи 0..1 (рассвет/закат — плавный fade). Общий для света и погоды
## (v1.30.2: туманная вуаль темнеет вместе с миром).
func _night_amount() -> float:
	var day_len := float(cfg["day_length"])
	var nf := float(cfg["night_fraction"])
	var fade := 8.0
	var t := fmod(sim.time, day_len)
	var night_start := day_len * (1.0 - nf)
	if t >= night_start:
		return 1.0
	if t >= night_start - fade:
		return (t - (night_start - fade)) / fade
	if t <= fade:
		return 1.0 - t / fade
	return 0.0


func _update_daylight() -> void:
	var day_len := float(cfg["day_length"])
	var nf := float(cfg["night_fraction"])
	var t := fmod(sim.time, day_len)
	var amount := _night_amount()
	# v1.27: свет дня задаёт солнечный цикл — характер дня и краска фазы
	# (рассвет/золотой час/закат по палитре этого дня)
	var sky := SKY
	var mood: int = sky.mood_of(sim.day_number(), String(sim.weather))
	var day_col: Color = sky.daylight_color(mood, fmod(t, day_len) / day_len, nf, sim.day_number())
	var night_color: Color = sky.night_color(mood)   # ночь тоже своя: звёздная/глухая
	_modulate.color = day_col.lerp(night_color, amount)
	if _ambience != null:
		_ambience.night = amount   # светлячки и огоньки разгораются к ночи
	if view != null:
		view.night = amount   # v1.31: солнечные блики воды гаснут к ночи
	# магическое загрязнение подкрашивает воздух (больше — фиолетовее)
	var pol_cfg: Dictionary = cfg.get("pollution", {})
	var pol_t := clampf(sim.pollution / maxf(1.0, float(pol_cfg.get("max", 100.0))), 0.0, 1.0)
	_modulate.color = _modulate.color.lerp(Color(0.82, 0.68, 0.95), pol_t * 0.3)
	# магическая буря (M5): небо наливается грозой
	if sim.storm_state == "active":
		_modulate.color = _modulate.color.lerp(Color(0.6, 0.5, 0.85), 0.4)
	elif sim.storm_state == "warn":
		_modulate.color = _modulate.color.lerp(Color(0.7, 0.6, 0.9), 0.2)


## Герой пал в городе (M5): не умирает окончательно — жители оттаскивают к центру.
func _on_hero_down() -> void:
	if sim.raid_active:
		sim.hero_alive = false
	hud.toast(Loc.t("city.hero_down_toast"))
	hero.dead = false
	hero.hp = maxi(1, int(hero.p["hp"]) / 3)
	hero.position = map.tile_center_px(map.spawn_tile)
	hero.queue_redraw()


## v1.48: сбор лута руин (кристаллы/руна) — тайл рядом с героем.
func _try_ruin_loot() -> bool:
	var t: Vector2i = map.tile_of_px(hero.position)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var lt: Vector2i = t + d
		if not map.ruin_loot.has(lt):
			continue
		map.ruin_loot.erase(lt)
		var roll := randf()
		if roll < 0.5:
			var n := 2 + (randi() % 3)
			sim.res["crystal"] = float(sim.res.get("crystal", 0.0)) + float(n)
			hud.toast(Loc.t("city.ruin_crystal") % n)
		else:
			var runes := {}
			for rcp in Game.magic.cfg.get("recipes", []):
				runes[String(rcp["a"])] = true
				runes[String(rcp["b"])] = true
			var keys: Array = runes.keys()
			var rune_id := String(keys[randi() % keys.size()])
			Game.add_item(rune_id)
			hud.toast(Loc.t("city.ruin_rune") % Loc.t(rune_id))
		return true
	return false

