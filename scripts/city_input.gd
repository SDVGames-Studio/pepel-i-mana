# Часть: сцена города — ввод (клавиатура/мышь), меню-оверлей, режимы стройки/зон/
# дорог/переноса/посадки, пауза и зум. Один класс, поведение не меняется.
extends "res://scripts/city_events.gd"

func _unhandled_input(event: InputEvent) -> void:
	# v1.50 «Живая земля»: зум карты колесом мыши — землю города можно
	# приближать и отдалять (границы — data/city.json → zoom)
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP \
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_wheel_zoom(1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
		return
	# v1.66 (магия-просто): Z/X — быстрый каст первых двух изученных
	# заклинаний (в данже 1–9 уже работают — спеллбук по порядку)
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_Z or event.physical_keycode == KEY_X):
		var slot_idx := 0 if event.physical_keycode == KEY_Z else 1
		if slot_idx < Game.spellbook.size():
			cast_combat_spell(String(Game.spellbook[slot_idx]))
		else:
			hud.toast(Loc.t("magic.slot_empty"))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		# в чужом городе герой — гость: аномалия, оружейка, храм и ручной
		# труд — только дома («Мир v2», этап 3)
		# v1.48: руины городской карты — лут-тайл рядом (кристаллы/руна)
		if _try_ruin_loot():
			return
		if not guest:
			if _near_anomaly:
				if Game.dungeon_available(sim.day_number()):
					_enter_dungeon()
				else:
					hud.toast(Loc.t("city.dungeon_locked_toast") % (Game.dungeon_lock_day - sim.day_number()))
				return
			if not _near_armory.is_empty():
				_buy_hero_kit()
				return
			if _near_temple:
				_pray_at_temple()
				return
			# ручной труд героя (правки v1.12.2): стройка/дерево/скала
			if _hero_act():
				return
	if event.is_action_pressed("inventory"):
		hud.toggle_residents()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_I:
				_equip_panel.toggle()
			KEY_L:
				if guest:
					hud.toast(Loc.t("city.guest_own_city"))
				else:
					_gov_panel.toggle()
			KEY_Q:
				if guest:
					hud.toast(Loc.t("city.guest_own_city"))
				else:
					_quests_panel.toggle()
			KEY_K:
				_codex_panel.toggle()
			KEY_P:
				toggle_pause()
			KEY_R:
				hud.toggle_magic()
			KEY_U:
				if guest:
					hud.toast(Loc.t("city.guest_own_city"))
				else:
					hud.toggle_research()
			KEY_C:
				hud.toggle_chronicle()
			KEY_M:
				hud.toggle_market()
			KEY_N:
				_overview.toggle()   # обзорная карта города (v1.51)
				return
			# v1.50.2: масштаб карты города и с клавиатуры — «+»/«−»
			# (дубль колеса мыши: у кого-то его нет под рукой)
			KEY_EQUAL, KEY_KP_ADD:
				_wheel_zoom(1.12)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_wheel_zoom(1.0 / 1.12)
			KEY_1:
				set_speed(1)
			KEY_2:
				set_speed(2)
			KEY_3:
				set_speed(3)
			KEY_4:
				set_speed(10)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and enchant_mode != "":
			_try_enchant()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and enchant_mode != "":
			set_enchant_mode("")
			return
		if event.button_index == MOUSE_BUTTON_LEFT and move_mode:
			_try_move_click()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and move_mode:
			if not _move_bld.is_empty():
				_pick_move_bld({})   # сперва снимаем здание, режим живёт
			else:
				set_move_mode(false)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and plaza_mode:
			var pt: Vector2i = map.tile_of_px(get_global_mouse_position())
			var perr: String = sim.move_plaza(pt)
			if perr == "":
				hud.toast(Loc.t("city.plaza_moved"))
				set_plaza_mode(false)
			else:
				hud.toast(Loc.t(perr))
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and plaza_mode:
			set_plaza_mode(false)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and zone_mode != "":
			# этап 2, аспект 3: клик по готовой грядке — сменить культуру поля
			if zone_mode == "field" and not hud.crop_pick_visible():
				var zf: Dictionary = sim.field_at(map.tile_of_px(get_global_mouse_position()))
				if not zf.is_empty():
					_pick_zone_id = int(zf["id"])
					var cname: String = Loc.t(String(sim.crop_def(String(zf.get("crop", "turnip"))).get("loc", "")))
					_open_crop_picker(Loc.t("city.crop_pick_change") % cname)
					return
			_dragging = true
			_drag_from = map.tile_of_px(get_global_mouse_position())
			_drag_to = _drag_from
			_sync_view_tools()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and (zone_mode != "" or road_mode or plant_mode):
			_cancel_crop_pick()
			set_zone_mode("")
			set_road_mode(false)
			set_plant_mode(false)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and road_mode:
			_dragging = true
			_paint_road(map.tile_of_px(get_global_mouse_position()))
			return
		if event.button_index == MOUSE_BUTTON_LEFT and plant_mode:
			_try_plant(map.tile_of_px(get_global_mouse_position()))
			return
		if event.button_index == MOUSE_BUTTON_LEFT and build_mode != "":
			_try_place()
		elif event.button_index == MOUSE_BUTTON_RIGHT and build_mode != "":
			set_build_mode("")
		elif event.button_index == MOUSE_BUTTON_LEFT and zone_mode == "" and not road_mode and not plant_mode:
			hero.city_attack(sim)   # ЛКМ без режима — удар героя в городе (M5)
			# охота в городе (замечание 2026-10-20): удар снимает зверя в дуге
			var wpn: Dictionary = Game.weapon_params()
			var kill: Dictionary = sim.hero_hit_animal(hero.global_position, hero.facing,
					float(wpn.get("range", hero.p["attack_range"])),
					float(wpn.get("arc", hero.p["attack_arc"])))
			if not kill.is_empty():
				# еда (мясо/рыба) сразу в общий пул города — охота кормит город
				# (замечание приёмки этапа 2: герой не мог добыть еду);
				# остальное (шкура, перо) — в рюкзак
				var parts := PackedStringArray()
				var food_got := 0
				for d: Dictionary in kill["drops"]:
					var iid := String(d["id"])
					if iid == "meat" or iid == "fish_raw":
						food_got += int(d["count"])
					else:
						Game.add_item(iid, int(d["count"]))
						parts.append("%s ×%d" % [Loc.t("item." + iid), int(d["count"])])
				if food_got > 0:
					sim._add_resource_capped("food", float(food_got))
					parts.insert(0, "%s ×%d" % [Loc.t("res.food"), food_got])
				hud.toast(Loc.t("world.hunt_got") % [Loc.t("fauna." + String(kill["kind"])), ", ".join(parts)])
				sim.chronicle_add("chron.hunt", Loc.t("fauna." + String(kill["kind"])))
				sim.quest_hunted()   # доска объявлений (M14-K)
				Game.stat("hunts")
			# удар героя по кладбищу (M11): выкорчёвывание нечистого места
			if sim.hero_hit_building(hero.global_position, hero.facing,
					float(hero.p["attack_range"]), float(hero.p["attack_arc"]), hero.eff_damage()) == "necro_hit":
				hud.toast(Loc.t("city.necro_hit_toast"))
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _dragging:
			_dragging = false
			_sync_view_tools()
			if zone_mode != "":
				_apply_zone()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to = map.tile_of_px(get_global_mouse_position())
		if road_mode:
			_paint_road(_drag_to)
		_sync_view_tools()
	elif event.is_action_pressed("ui_cancel"):
		if build_mode != "":
			set_build_mode("")
		elif enchant_mode != "":
			set_enchant_mode("")
		elif move_mode:
			if not _move_bld.is_empty():
				_pick_move_bld({})
			else:
				set_move_mode(false)
		elif plaza_mode:
			set_plaza_mode(false)
		elif hud.crop_pick_visible():
			_cancel_crop_pick()   # пикер закрыт — остаёмся в режиме поля
		elif zone_mode != "":
			set_zone_mode("")
		elif road_mode:
			set_road_mode(false)
		elif plant_mode:
			set_plant_mode(false)
		elif hud.magic_visible():
			hud.toggle_magic()
		elif hud.research_visible():
			hud.toggle_research()
		elif hud.residents_visible():
			hud.toggle_residents()
		elif hud.chronicle_visible():
			hud.toggle_chronicle()
		elif hud.market_visible():
			hud.toggle_market()
		elif _equip_panel.is_open():
			_equip_panel.close()
		elif _gov_panel.is_open():
			_gov_panel.close()
		elif _quests_panel.is_open():
			_quests_panel.close()
		elif _codex_panel.is_open():
			_codex_panel.close()
		elif _menu_layer != null:
			pass   # меню уже открыто поверх — Esc съест само меню
		else:
			_open_menu_overlay()


## Меню-оверлей (v1.54): Esc в городе БЕЗ смены сцены — главный экран
## меню ложится поверх, город на паузе. Прежний выход пересоздавал сцену:
## полная перевыпечка воды/теней давала «долго думает, текстуры не
## прогружены». Закрывает меню само (Esc/«Продолжить») — через флаг.
func _open_menu_overlay() -> void:
	if _menu_layer != null:
		return
	sim.paused = true
	Game.menu_overlay = true
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_layer.add_child(dim)
	_menu_layer.add_child(load("res://scenes/main_menu.tscn").instantiate())
	add_child(_menu_layer)


## Esc (фидбек заказчика 2026-10-20): как раньше — сразу в меню; перед выходом
## запоминаем героя, чтобы «Продолжить» и «Сохранить» в меню вернули его
## на то же место (замечание 2026-10-20: герой не должен сбегаться в центр).
## В поселении НПС герой «стоит на карте мира у поселения» — мир продолжает
## жить, «Продолжить» вернёт к поселению.
func _exit_to_menu() -> void:
	sim.paused = true
	if guest:
		if Game.city_sim != null:
			Game.city_sim.paused = true
		if Game.npc_cities != null:
			Game.npc_cities.set_paused(true, Game.visiting_city_id)
		var poi: Dictionary = Game.world_map.poi_by_id(Game.visiting_city_id)
		Game.menu_hero_tile = poi["tile"] if (Game.world_map != null and not poi.is_empty()) \
				else Vector2i(-1, -1)
		Game.menu_hero_hp = -1
		Game.menu_hero_mana = -1
		Game.city_return_tile = Vector2i(-1, -1)
	else:
		Game.menu_hero_tile = map.tile_of_px(hero.global_position)
		Game.menu_hero_hp = hero.hp
		Game.menu_hero_mana = hero.mana
		Game.city_return_tile = Game.menu_hero_tile
	get_tree().change_scene_to_file(MENU_SCENE)


## Зеркалим состояние инструментов зоны/дороги в отрисовку.
func _sync_view_tools() -> void:
	view.zone_mode = zone_mode
	view.road_mode = road_mode
	view.dragging = _dragging
	view.drag_from = _drag_from
	view.drag_to = _drag_to
	view.move_mode = move_mode
	view.move_bld_id = int(_move_bld.get("id", -1))
	view.plaza_mode = plaza_mode


## Выделение зоны применено: все клетки прямоугольника уходят в симуляцию.
## Правки v1.21: поле вручную больше не размечается — его распахивает ферма
## (клик по готовой грядке по-прежнему меняет культуру поля).
func _apply_zone() -> void:
	if zone_mode == "field":
		hud.toast(Loc.t("city.zone_field_farm"))
		return
	var cells: Array = []
	var x0 := mini(_drag_from.x, _drag_to.x)
	var x1 := maxi(_drag_from.x, _drag_to.x)
	var y0 := mini(_drag_from.y, _drag_to.y)
	var y1 := maxi(_drag_from.y, _drag_to.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			cells.append(Vector2i(x, y))
	var added: int = sim.add_zone(zone_mode, cells)
	if added > 0:
		hud.toast(Loc.t("city.zone_added") % [Loc.t("zone." + zone_mode), added])
	else:
		hud.toast(Loc.t("city.zone_bad"))


## Кнопки культур (этап 2, аспект 3): смена культуры готового поля кликом.
func _open_crop_picker(title: String) -> void:
	var defs: Array = []
	for cid in cfg.get("farming", {}).get("crops", {}):
		var cd: Dictionary = cfg["farming"]["crops"][cid]
		defs.append({"id": String(cid), "loc": String(cd.get("loc", cid)),
				"desc": String(cd.get("desc", ""))})
	hud.show_crop_pick(defs, title, _on_crop_picked)


func _on_crop_picked(crop: String) -> void:
	if _pick_zone_id >= 0:
		var z: Dictionary = sim.zone_by_id(_pick_zone_id)
		_pick_zone_id = -1
		if sim.set_field_crop(z, crop):
			hud.toast(Loc.t("city.crop_changed") % Loc.t(String(sim.crop_def(crop).get("loc", crop))))
	view.queue_redraw()


func _cancel_crop_pick() -> void:
	_pick_zone_id = -1
	hud.hide_crop_pick()


## Дорога: тайл под курсором (или под пером при зажатой ЛКМ).
func _paint_road(tile: Vector2i) -> void:
	var err: String = sim.place_road(tile)
	match err:
		"":
			_road_warned = false
		"no_stone":
			if not _road_warned:
				_road_warned = true
				hud.toast(Loc.t("city.road_no_stone"))


## Инструменты стройки/зон/дорог — только в своём городе: в поселении НПС
## городом управляют его жители («Мир v2», этап 3, №120).
func _guest_block() -> bool:
	if guest:
		hud.toast(Loc.t("city.guest_no_build"))
		return true
	return false


## Инструмент переноса зданий (этап 2, аспект 5): клик по готовому зданию —
## снять, клик по новому месту — поставить (бесплатно). ПКМ/Esc — отмена.
func set_move_mode(on: bool) -> void:
	if on and _guest_block():
		return
	move_mode = on
	if move_mode:
		zone_mode = ""
		road_mode = false
		plant_mode = false
		view.plant_mode = false
		if build_mode != "":
			set_build_mode("")
		if enchant_mode != "":
			set_enchant_mode("")
		hud.set_hint(Loc.t("city.move_pick"))
	elif build_mode == "" and zone_mode == "" and not road_mode and not plant_mode:
		hud.set_hint(_default_hint())
	_pick_move_bld({})
	_sync_view_tools()


## Клик в режиме переноса: выбор здания или перенос на место под курсором.
func _try_move_click() -> void:
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if _move_bld.is_empty():
		var b: Dictionary = sim.building_at(tile)
		if b.is_empty() or not sim._active(b):
			hud.toast(Loc.t("city.move_bad_bld"))
			return
		_pick_move_bld(b)
		hud.set_hint(Loc.t("city.move_place") % _bld_name(String(b["type"])))
		return
	var err: String = sim.move_building(_move_bld, tile)
	if err == "bad_spot":
		hud.toast(Loc.t("city.move_bad_spot"))
		return
	if err != "":
		hud.toast(Loc.t("city.move_bad_bld"))
		return
	set_move_mode(false)   # перенесли — инструмент своё отработал


## Запомнить снимаемое здание ({} — сбросить) и обновить призрак.
func _pick_move_bld(b: Dictionary) -> void:
	_move_bld = b
	_sync_view_tools()


## Цена ремонта одной строкой: «4 дерево, 2 камень».
func _cost_str(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in cost:
		parts.append("%d %s" % [int(cost[key]), Loc.t("res." + key)])
	return ", ".join(parts)


## Инструмент зоны: повторное нажатие / ПКМ / Esc отменяет.
func set_zone_mode(type_id: String) -> void:
	if _guest_block():
		return
	zone_mode = "" if zone_mode == type_id else type_id
	_cancel_crop_pick()   # смена инструмента закрывает выбор культуры
	if zone_mode != "":
		road_mode = false
		plant_mode = false
		view.plant_mode = false
		if move_mode:
			set_move_mode(false)
		if plaza_mode:
			set_plaza_mode(false)
		if build_mode != "":
			set_build_mode("")
		hud.set_hint(Loc.t("city.zone_hint") % Loc.t("zone." + zone_mode))
	elif build_mode == "" and not road_mode and not plant_mode:
		hud.set_hint(_default_hint())
	_sync_view_tools()


## Перенос главной площади (правки v1.20): клик по новому месту — площадь 2×2
## переезжает, вокруг неё по-прежнему нельзя строить.
func set_plaza_mode(on: bool) -> void:
	if on and _guest_block():
		return
	plaza_mode = on
	if plaza_mode:
		zone_mode = ""
		road_mode = false
		plant_mode = false
		view.plant_mode = false
		if move_mode:
			set_move_mode(false)
		if build_mode != "":
			set_build_mode("")
		hud.set_hint(Loc.t("city.plaza_pick"))
	elif build_mode == "" and zone_mode == "" and not road_mode and not plant_mode:
		hud.set_hint(_default_hint())
	_sync_view_tools()


## Инструмент дороги.
func set_road_mode(on: bool) -> void:
	if on and _guest_block():
		return
	road_mode = on
	if road_mode:
		zone_mode = ""
		if move_mode:
			set_move_mode(false)
		if build_mode != "":
			set_build_mode("")
		hud.set_hint(Loc.t("city.road_hint") % int(cfg.get("roads", {}).get("cost_stone", 1)))
	elif build_mode == "" and zone_mode == "" and not plant_mode and not move_mode:
		hud.set_hint(_default_hint())
	_sync_view_tools()


## Инструмент посадки леса (M11): клик — саженец (семя из пула).
func set_plant_mode(on: bool) -> void:
	if on and _guest_block():
		return
	plant_mode = on
	view.plant_mode = on
	if plant_mode:
		zone_mode = ""
		road_mode = false
		if move_mode:
			set_move_mode(false)
		if build_mode != "":
			set_build_mode("")
		hud.set_hint(Loc.t("city.plant_hint") % int(cfg.get("forest", {}).get("seed_cost", 1)))
	elif build_mode == "" and zone_mode == "" and not road_mode and not move_mode:
		hud.set_hint(_default_hint())
	_sync_view_tools()


## Посадить саженец в тайл. Ошибки — тостом.
func _try_plant(tile: Vector2i) -> void:
	var err: String = sim.plant_sapling(tile)
	if err == "no_seeds":
		hud.toast(Loc.t("city.plant_no_seeds"))
	elif err == "bad":
		hud.toast(Loc.t("city.plant_bad"))


func _try_place() -> void:
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not sim.is_buildable_rect(build_mode, tile):
		hud.toast(Loc.t("city.cant_build_here"))
		return
	var cost: Dictionary = {}
	for b in cfg["buildings"]:
		if String(b["id"]) == build_mode:
			cost = b["cost"]
	if not sim.can_afford(cost):
		hud.toast(Loc.t("city.need_resources"))
		return
	var block: String = sim.placement_block(build_mode, tile)
	if block != "":
		hud.toast(Loc.t(block))
		return
	sim.place_building(build_mode, tile)


func set_build_mode(type_id: String) -> void:
	if type_id != "" and _guest_block():
		return
	build_mode = type_id
	view.build_mode = type_id
	if type_id != "" and (zone_mode != "" or road_mode or plant_mode):
		# выбор здания снимает инструменты зоны, дороги и посадки
		zone_mode = ""
		road_mode = false
		plant_mode = false
		view.plant_mode = false
		_sync_view_tools()
	if type_id != "" and move_mode:
		set_move_mode(false)
	if type_id == "":
		hud.set_hint(_default_hint())
		return
	for b in cfg["buildings"]:
		if String(b["id"]) == type_id:
			hud.set_hint(Loc.t("city.build_hint") % _bld_hint(b))


## Подсказка выбранного здания: имя (цена — эффект).
func _bld_hint(b: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in b["cost"]:
		parts.append("%d %s" % [int(b["cost"][key]), Loc.t("res." + key)])
	var desc := Loc.t(String(b["desc"]))
	if b.has("produce"):
		desc = desc % int(b["produce"]["per_day"])
	elif String(b.get("effect", "")) == "storage":
		desc = desc % int(cfg["storage_per_warehouse"])
	elif String(b.get("effect", "")) == "tavern":
		var tcfg: Dictionary = cfg.get("tavern", {})
		desc = desc % int(float(tcfg.get("food_per_day", 8.0)))
	elif String(b.get("effect", "")) == "decor":
		desc = desc % int(b.get("mood", 0))
	return "%s (%s; %s)" % [Loc.t(String(b["loc"])), ", ".join(parts), desc]


## Молитва у храма (M14-H): раз в день избирает божество (выбор — в панели L).
func _pray_at_temple() -> void:
	if String(sim.god) == "":
		hud.toast(Loc.t("god.need_choose"))
		return
	var err: String = sim.pray(sim.god)
	if err == "":
		Game.codex_seen("gods", sim.god)   # кодекс (M14-K)
	hud.toast(Loc.t(err) if err != "" else Loc.t("god.prayed"))


func toggle_pause() -> void:
	sim.paused = not sim.paused
	if sim.paused:
		hud.toast(Loc.t("city.paused"))


## Зум камеры колесом (v1.50): приближение показывает землю/тайлы крупно,
## отдаление — всю карту. Границы и шаг — data/city.json → zoom.
func _wheel_zoom(factor: float) -> void:
	if hero == null:
		return
	var cam: Node = hero.get_node_or_null("Camera")
	if cam == null or not (cam is Camera2D):
		return
	var zcfg: Dictionary = sim.cfg.get("zoom", {})
	var zmin := float(zcfg.get("min", 1.2))
	var zmax := float(zcfg.get("max", 3.0))
	var z: Vector2 = (cam.zoom as Vector2) * factor
	cam.zoom = Vector2(clampf(z.x, zmin, zmax), clampf(z.y, zmin, zmax))


## --- Магия (M3): крафт, городские заклинания, зачарование ----------------

