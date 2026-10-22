# Часть: рынок и караваны, торговые палатки, скот, сады, ворота, личности, таверна.
# Правки структуры v1.20.2: огромный city_sim.gd разбит на extends-цепочку
# частей; это один класс, разложенный по файлам — поведение не меняется.
extends "res://scripts/city_sim_zones.gd"

# --- рынок и караваны мэра (M10) ---------------------------------------------

## Рынок работает: построен и за ним закреплен торговец.
func market_ready() -> bool:
	for b in buildings:
		if String(b["type"]) == "market" and bool(b["done"]) and int(b["worker"]) > 0:
			return true
	return false


## Ежедневный бросок: раз в N дней караван приходит в город (рынок активен).
func _roll_market() -> void:
	var mcfg: Dictionary = cfg.get("market", {})
	if mcfg.is_empty() or not market_ready():
		caravan_here = false
		return
	if caravan_here:
		caravan_here = false   # простоял день и уехал
		events.append({"type": "caravan_left"})
		return
	if day - _last_caravan_day < int(mcfg.get("caravan_days", 4)):
		return
	caravan_here = true
	_last_caravan_day = day
	events.append({"type": "caravan_arrived"})


## Отправить свой караван с товаром (организует мэр). deal — из city.json
## "market.deals". Возвращает "" или ключ ошибки без префикса.
func send_caravan(deal: Dictionary) -> String:
	var mcfg: Dictionary = cfg.get("market", {})
	if not market_ready():
		return "no_market"
	if caravans_out.size() >= int(mcfg.get("max_out", 2)):
		return "caravan_busy"
	var amount := float(deal["amount"])
	if float(res.get(String(deal["res"]), 0.0)) < amount:
		return "no_res"
	res[String(deal["res"])] = float(res[String(deal["res"])]) - amount
	caravans_out.append({"res": String(deal["res"]), "amount": amount,
			"left": int(deal["days"]), "coins": int(deal["coins"]),
			"dest": String(deal.get("dest", "traders"))})
	events.append({"type": "caravan_sent", "res": String(deal["res"]), "amount": int(amount)})
	_chron("chron.caravan_sent", Loc_res(String(deal["res"])), str(int(amount)))
	return ""


func Loc_res(key: String) -> String:
	return key


## Дневной тик отправленных караванов: доход в монеты или разграбление.
func _tick_caravans() -> void:
	var mcfg: Dictionary = cfg.get("market", {})
	var still: Array = []
	for c: Dictionary in caravans_out:
		c["left"] = int(c["left"]) - 1
		if int(c["left"]) > 0:
			still.append(c)
			continue
		if _event_rng.randf() < float(mcfg.get("loss_chance", 0.15)):
			events.append({"type": "caravan_lost", "res": String(c["res"])})
			_chron("chron.caravan_lost", Loc_res(String(c["res"])), str(int(float(c["amount"]))))
		else:
			var coins := int(c["coins"])
			Game_coins_add(coins)
			events.append({"type": "caravan_returned", "coins": coins})
			_chron("chron.caravan_returned", str(coins))
	caravans_out = still




func Game_coins_add(n: int) -> void:
	if coins_sink.is_valid():
		coins_sink.call(n)


## Цена каравана на базаре (за единицу) — из city.json -> market.caravan_buy.
func caravan_price(key: String) -> float:
	return float(cfg.get("market", {}).get("caravan_buy", {}).get(key, 3))


## Купить у пришедшего каравана (в пул города). "" или ключ ошибки.
func market_buy(key: String, count: int) -> String:
	if not caravan_here:
		return "no_caravan"
	var price := caravan_price(key)
	var cost := int(ceilf(price * float(count)))
	if coins_source.is_valid() and int(coins_source.call()) < cost:
		return "no_coins"
	var free := float(storage_cap()) - float(res.get(key, 0.0))
	var add := minf(float(count), maxf(0.0, free))
	if add <= 0.0:
		return "storage_full"
	res[key] = float(res.get(key, 0.0)) + add
	Game_coins_add(-int(ceilf(price * add)))
	return ""


## Продать каравану из пула. "" или ключ ошибки.
func market_sell(key: String, count: int) -> String:
	if not caravan_here:
		return "no_caravan"
	var have := float(res.get(key, 0.0))
	var take := minf(float(count), have)
	if take <= 0.0:
		return "no_res"
	var price := caravan_price(key) * float(cfg.get("market", {}).get("caravan_sell_mult", 0.5))
	res[key] = have - take
	Game_coins_add(int(floorf(price * take)))
	return ""


# --- торговые палатки (этап 2, аспект 4) --------------------------------------
# Отдельная дешёвая постройка 1×1 (лимит 3) с назначенным торговцем; доход —
# монеты от излишков общего пула; живая сцена: покупатели-жители и бродячие
# торговцы у палаток. Рынок/караваны мэра (M10) не заменяет — дополняет.

func _tent_cfg() -> Dictionary:
	return cfg.get("tent", {})


## Работающие палатки: готовые и с назначенным торговцем.
func working_tents() -> Array:
	var out: Array = []
	for b in buildings:
		if String(b["type"]) == "tent" and bool(b["done"]) and int(b["worker"]) > 0:
			out.append(b)
	return out


## Потребность города в ресурсе (порог излишков): еда — запас на несколько
## дней по ртам жителей, прочее — фиксированные пороги tent.need.
func _tent_need(key: String) -> float:
	if key == "food":
		var eaters := 0.0
		for r in residents:
			var portion := _trait_prod(r, "food_mult")
			if String(r["prof"]) == "":
				portion *= float(people.get("child_food", 0.5))
			eaters += portion
		return eaters * float(cfg["food_per_resident_day"]) \
				* float(_tent_cfg().get("need_days_food", 2.0))
	return float(_tent_cfg().get("need", {}).get(key, 0.0))


## Доход палатки за день в монетах: продаются излишки пула — всё сверх
## потребностей города. Пустой пул (голодающий город) — палатка стоит.
## Бродячий торговец у палатки скупает оптом (income_mult).
func _tent_income(b: Dictionary) -> int:
	var rates: Dictionary = _tent_cfg().get("coin_per_unit", {})
	if rates.is_empty():
		return 0
	var coins := 0.0
	for key in rates:
		var surplus := float(res.get(String(key), 0.0)) - _tent_need(String(key))
		if surplus > 0.0:
			coins += surplus * float(rates[key])
	coins = minf(coins, float(_tent_cfg().get("max_coins_per_day", 8)))
	if _wanderer_at(b):
		coins *= float(_tent_cfg().get("wander", {}).get("income_mult", 2.0))
	# этап 2, аспект 6: торговый квартал оживляет палатку
	if String(b.get("quarter", "")) == "trade":
		coins *= float(cfg.get("zones", {}).get("quarters", {}).get("mult", 1.0))
	return int(coins)


## Ежедневный доход всех палаток: монеты в казну (общую с героем), один тост.
func _tick_tents() -> void:
	var total := 0
	for b in working_tents():
		total += _tent_income(b)
	if total <= 0:
		return
	Game_coins_add(total)
	events.append({"type": "tent_income", "coins": total})


## Бродячий торговец стоит у этой палатки?
func _wanderer_at(b: Dictionary) -> bool:
	for w in wanderers:
		if String(w["mode"]) == "trade" and int(w["tent"]) == int(b["id"]):
			return true
	return false


## Здание по id (для бродячих торговцев, палатка могла переехать).
func _building_by_id(bid: int) -> Dictionary:
	for b in buildings:
		if int(b["id"]) == bid:
			return b
	return {}


## Раз в wander.every_days дней к работающей палатке заходит бродячий
## торговец-нейтрал (в городе не больше одного за раз).
func _roll_wanderer() -> void:
	var wcfg: Dictionary = _tent_cfg().get("wander", {})
	if wcfg.is_empty() or not wanderers.is_empty():
		return
	if day - _last_wanderer_day < int(wcfg.get("every_days", 3)):
		return
	var tents := working_tents()
	if tents.is_empty():
		return
	_last_wanderer_day = day
	var from := _edge_tile()
	wanderers.append({
		"id": _wanderer_id, "pos": map.tile_center_px(from), "path": PackedVector2Array(),
		"target": Vector2i(-1, -1), "mode": "come", "tent": int(tents[0]["id"]),
		"left": 0.0, "come": 0.0, "edge": from,
		"prof": "", "dir": "front", "state": "", "moving": false,
	})
	_wanderer_id += 1


## Тик бродячих торговцев: дойти до палатки, поторговать, уйти к краю карты
## (уходит через тот же край, откуда пришёл).
func _update_wanderers(dt: float) -> void:
	var wcfg: Dictionary = _tent_cfg().get("wander", {})
	var day_len := float(cfg["day_length"])
	var still: Array = []
	for w: Dictionary in wanderers:
		var tent := _building_by_id(int(w["tent"]))
		if tent.is_empty() or not bool(tent["done"]) or int(tent["worker"]) <= 0:
			w["mode"] = "leave"   # палатку снесли или торговец ушёл — делать нечего
		var mode := String(w["mode"])
		if mode == "come":
			w["come"] = float(w.get("come", 0.0)) + dt
			var spot := bld_spot(tent)
			_move_towards(w, spot, dt)
			if map.tile_of_px(w["pos"]) == spot:
				w["mode"] = "trade"
				w["left"] = float(wcfg.get("stay_days", 0.6)) * day_len
				events.append({"type": "wanderer_arrived"})
			elif float(w["come"]) > 2.0 * day_len:
				w["mode"] = "leave"   # застрял по пути — разворачивается
				w["target"] = Vector2i(-1, -1)
		elif mode == "trade":
			w["left"] = float(w["left"]) - dt
			if float(w["left"]) <= 0.0:
				w["mode"] = "leave"
				w["target"] = Vector2i(-1, -1)
		else:   # leave: дошёл до своего края — ушёл из города
			var edge: Vector2i = w.get("edge", _edge_tile())
			_move_towards(w, edge, dt)
			if map.tile_of_px(w["pos"]) == edge:
				continue
		still.append(w)
	wanderers = still


## Живая сцена (этап 2, аспект 4): свободный житель изредка подходит
## «покупать» к работающей палатке — реплика-облачко, кулдаун.
func _tent_visit(r: Dictionary, dt: float) -> bool:
	var scfg: Dictionary = _tent_cfg().get("scene", {})
	if scfg.is_empty():
		return false
	r["shop_cd_left"] = maxf(0.0, float(r.get("shop_cd_left", 0.0)) - dt)
	var visit: Dictionary = r.get("shop", {})
	if not visit.is_empty():
		var tent := _building_by_id(int(visit.get("bld", -1)))
		if tent.is_empty() or not bool(tent["done"]) or int(tent["worker"]) <= 0:
			r["shop"] = {}   # палатка пропала — визит отменяется
			return false
		var target: Vector2i = bld_spot(tent)
		if float(r.get("chat_left", 0.0)) > 0.0:
			r["chat_left"] = float(r["chat_left"]) - dt
			if float(r["chat_left"]) <= 0.0:
				r["chat_key"] = ""
				r["shop"] = {}
				r["shop_cd_left"] = float(scfg.get("visit_cd", 30.0))
			else:
				r["state"] = "chat"
				r["path"] = PackedVector2Array()
			return true
		if not _arrived(r, target):
			_move_towards(r, target, dt)
		else:
			r["state"] = "chat"
			r["path"] = PackedVector2Array()
			r["chat_key"] = String(visit["key"])
			r["chat_left"] = float(scfg.get("buy_seconds", 3.0))
		return true
	if float(r.get("shop_cd_left", 0.0)) > 0.0:
		return false
	var tents := working_tents()
	if tents.is_empty():
		return false
	var day_len := float(cfg["day_length"])
	var chance := float(scfg.get("visit_chance_per_day", 6.0)) * dt / day_len
	for w in wanderers:   # бродячий у палатки — очередь длиннее, сцена живее
		if String(w["mode"]) == "trade":
			chance *= float(scfg.get("wander_visit_mult", 2.5))
			break
	if randf() >= chance:
		return false
	var tent: Dictionary = tents[randi() % tents.size()]
	var lines := maxi(1, int(scfg.get("buy_lines", 6)))
	r["shop"] = {"bld": int(tent["id"]), "key": "shop.%d" % (randi() % lines + 1)}
	return true


## Торговец за палаткой: подходит ко входу и стоит за прилавком (state=work).
func _tent_tend(r: Dictionary, b: Dictionary, dt: float) -> void:
	if at_bld(r, b):
		r["state"] = "work"
		r["path"] = PackedVector2Array()
		r["fatigue"] = minf(1.0, float(r["fatigue"]) + dt / float(cfg["day_length"]) * 0.5)
		_grow_skill(r, dt)
	else:
		_move_towards(r, bld_spot(b), dt)


# --- яблоневые сады (M10) -----------------------------------------------------

## Сад растёт: у готового сада зреют яблоки (stage), потом урожай в пул.
func _tick_orchards() -> void:
	var ocfg: Dictionary = cfg.get("orchard", {})
	if ocfg.is_empty():
		return
	for b in buildings:
		if String(b["type"]) != "orchard" or not _active(b):
			continue
		b["apple_stage"] = int(b.get("apple_stage", 0))
		if int(b["apple_stage"]) < int(ocfg.get("stages", 3)):
			b["apple_stage"] = int(b["apple_stage"]) + 1
		elif _event_rng.randf() < float(ocfg.get("harvest_chance", 0.7)):
			var harvest: float = float(ocfg.get("food", 14.0)) * orchard_mult()   # M14-J: лето/буря
			_add_resource_capped("food", harvest)
			b["apple_stage"] = 0
			events.append({"type": "orchard_harvest", "food": int(harvest)})


# --- ворота в стене ---------------------------------------------------------

## Ворота открыты, если рядом (≤3 тайлов) стоит вышка со стражем (заказчик).
## При надвигающейся или идущей атаке ворота ЗАКРЫТЫ всегда (M5).
func _gate_open(gate: Dictionary) -> bool:
	if raid_active or _raid_warned:
		return false
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "guard" and int(b["worker"]) > 0:
			if Vector2(b["tile"]).distance_to(Vector2(gate["tile"])) <= 3.0:
				return true
	return false


func is_gate_open(gate: Dictionary) -> bool:
	if not _active(gate):
		return false
	return bool(_gate_state.get(str(gate["id"]), false))


## При смене состояния — тайл ворот становится проходимым или стеной.
func _update_gates() -> void:
	for b in buildings:
		if not _active(b) or _def(b).get("effect", "") != "gate":
			continue
		var open := _gate_open(b)
		var key := str(b["id"])
		if not _gate_state.has(key) or bool(_gate_state[key]) != open:
			_gate_state[key] = open
			map.set_solid(b["tile"], not open)
			events.append({"type": "gate", "open": open})


# --- жители-личности (M4) -------------------------------------------------

func _trait_sum(r: Dictionary, key: String, base: float) -> float:
	var total := base
	for t_id in r.get("traits", []):
		var td: Dictionary = _trait_map.get(String(t_id), {})
		total += float(td.get(key, 0.0))
	return total


func _trait_prod(r: Dictionary, key: String) -> float:
	var mult := 1.0
	for t_id in r.get("traits", []):
		var td: Dictionary = _trait_map.get(String(t_id), {})
		mult *= float(td.get(key, 1.0))
	return mult


func _has_trait_flag(r: Dictionary, flag: String) -> bool:
	for t_id in r.get("traits", []):
		var td: Dictionary = _trait_map.get(String(t_id), {})
		if bool(td.get(flag, false)):
			return true
	return false


func _adults() -> Array:
	var out: Array = []
	for r in residents:
		if String(r["prof"]) != "" and not _is_golem(r):
			out.append(r)
	return out


## Голем-староста: не житель — не ест, не болеет, не женится (правки v1.20).
func _is_golem(r: Dictionary) -> bool:
	return bool(r.get("golem", false)) or String(r.get("prof", "")) == "elder"


func _avg_mood() -> float:
	if residents.is_empty():
		return float(people.get("mood_base", 50.0))
	var total := 0.0
	for r in residents:
		total += float(r["mood"])
	return total / residents.size()


func _friend_alive(r: Dictionary) -> bool:
	var fid := int(r.get("friend", -1))
	if fid < 0:
		return false
	for other in residents:
		if int(other["id"]) == fid:
			return true
	return false


func _friend_working(r: Dictionary) -> bool:
	var fid := int(r.get("friend", -1))
	if fid < 0:
		return false
	for other in residents:
		if int(other["id"]) == fid:
			return String(other["state"]) == "work" or String(other["state"]) == "build"
	return false


## Итоговый множитель работы: настроение + черты + навык + друг + мутация.
## Пустой амбар режет работу до «голодных» 40% — но работа не встаёт совсем.
func work_mult(r: Dictionary) -> float:
	var mult := 1.0
	var mood := float(r.get("mood", 50.0))
	if mood >= float(people.get("mood_good", 70.0)):
		mult *= float(people.get("work_mood_good", 1.1))
	elif mood <= float(people.get("mood_bad", 30.0)):
		mult *= float(people.get("work_mood_bad", 0.7))
	mult *= _trait_prod(r, "work_mult")
	mult *= 1.0 + float(people.get("skill_prod", 0.08)) * float(r.get("skill", 0.0))
	if _friend_working(r):
		mult *= float(people.get("friend_work", 1.1))
	mult *= 1.0 + float(r.get("work_bonus", 0.0))
	# цветовая система (правки v1.20): основная специальность — полная отдача,
	# дополнительные цвета — со штрафом (чем больше цветов, тем ниже КПД),
	# чужой цвет — вполсилы; белый голем-староста цветов не имеет
	var need := _work_need(r)
	if need != "":
		mult *= color_work_mult(r, need)
	# инструменты из мастерской ускоряют всех, пока есть в хранилище
	if float(res.get("tools", 0.0)) > 0.0:
		mult *= float(cfg.get("tools_boost", 1.15))
	# атака мутантов: работы вполсилы, только храбрые не боятся (M5)
	if raid_active and not _has_trait_flag(r, "fearless"):
		mult *= float(cfg.get("threat", {}).get("fear_work", 0.75))
	if float(res["food"]) <= 0.0:
		mult *= float(people.get("starving_work", 0.6))
	return clampf(mult, 0.2, 3.0)


## Текущее «цветовое» задание жителя: стройка — строитель, иначе профессия
## рабочего места. "" — свободен/не за производством.
func _work_need(r: Dictionary) -> String:
	if r.get("site", null) != null:
		return "builder"
	if r.get("bld", null) != null:
		return String(_def(r["bld"]).get("worker", ""))
	return ""


## Цветовая эффективность (правки v1.20): основной цвет — 1.0; дополнительный
## цвет — extra_mult, но каждый лишний цвет «размывает» мастера (dilution);
## чужой цвет — off_mult. Голем-староста белый: без цветовых бонусов.
func color_work_mult(r: Dictionary, need: String) -> float:
	var ccfg: Dictionary = cfg.get("work_colors", {})
	if need == "" or need == String(r["prof"]):
		return 1.0
	if _is_golem(r):
		return float(ccfg.get("golem_mult", 0.75))
	var extras: Array = r.get("prof_extra", [])
	if extras.has(need):
		var base := float(ccfg.get("extra_mult", 0.7))
		var dilution := float(ccfg.get("dilution_per_color", 0.08))
		return maxf(float(ccfg.get("extra_floor", 0.4)),
				base * (1.0 - dilution * maxi(0, extras.size() - 1)))
	return float(ccfg.get("off_mult", 0.35))


## Кружок жителя (правки v1.20): цвет основной специальности, голем — белый.
func resident_color(r: Dictionary) -> Color:
	if _is_golem(r):
		return Color.WHITE
	if String(r["prof"]) == "":
		return Color("#b0a08c")   # ребёнок — серо-бежевый кружок
	for p in cfg.get("professions", []):
		if String(p["id"]) == String(r["prof"]):
			return Color(String(p.get("color", "#ffffff")))
	return Color.WHITE


## Настроение плывёт к целевому: черты + загрязнение + потребности + события.
func _mood_target(r: Dictionary) -> float:
	var target: float = float(people.get("mood_base", 50.0))
	target += _trait_sum(r, "mood", 0.0)
	target += _trait_sum(r, "pollution_mood", 0.0) * pollution
	if float(res["food"]) <= 0.0:
		target -= 35.0
	if float(r["fatigue"]) >= float(cfg["tired_at"]):
		target -= 10.0
	if String(r.get("ail", "")) != "":
		target -= 25.0
	var home: Dictionary = r["home"] if r["home"] != null else {}
	if not home.is_empty():
		target += 8.0
	else:
		target -= 8.0
	# декор и комфорт (сад, статуя — ответ №18): уют поднимает мораль всему городу
	target += decor_mood()
	if _friend_alive(r):
		target += float(people.get("friend_mood", 6.0))
	if tavern_active():
		var tcfg: Dictionary = cfg.get("tavern", {})
		var tavern_mood := float(tcfg.get("mood", 12.0))
		if has_law("prohibition"):
			tavern_mood *= float(law_param("prohibition", "tavern_mood_mult", 1.0))
		target += tavern_mood
	if has_law("prohibition"):
		target += float(law_param("prohibition", "mood", 0.0))
	if has_law("taxes"):
		target += float(law_param("taxes", "mood", 0.0))
	if god == "home":
		target += float(god_def().get("value", 0.0))   # благословение «Дома»
	# автономная деревня (правки v1.12.0): гордость за самоуправление
	if autonomous:
		target += float(cfg.get("autonomy", {}).get("mood", 0.0))
	# погода и сезоны (M14-J): дождь тоска, пепельная буря страшна,
	# замёрзшую ночью зиму город помнит
	if weather == "rain":
		target += float(_weather_cfg().get("effects", {}).get("rain_mood", -2.0))
	elif weather == "ash_storm":
		target += float(_weather_cfg().get("effects", {}).get("ash_mood", -5.0))
	if froze_last_night:
		target += float(_weather_cfg().get("effects", {}).get("cold_mood", -10.0))
	# память v3 (M14-F): свежие события качают настроение, старые тлеют в хвосте
	target += _memory_mood(r)
	return clampf(target, 0.0, 100.0)


func _update_mood(r: Dictionary, dt: float, day_len: float) -> void:
	var target := _mood_target(r)
	var rate: float = float(people.get("mood_rate", 1.5))
	r["mood"] = clampf(float(r["mood"]) + (target - float(r["mood"])) * rate * dt / day_len, 0.0, 100.0)


## Навык растёт, пока житель работает; вехи — «опытный» и «мастер».
func _grow_skill(r: Dictionary, dt: float) -> void:
	var rate: float = float(people.get("skill_rate", 0.5)) * _trait_prod(r, "skill_rate")
	var skill_max: float = float(people.get("skill_max", 5.0))
	var before := float(r["skill"])
	r["skill"] = minf(skill_max, before + rate * dt / float(cfg["day_length"]))
	var expert_at: float = float(people.get("skill_expert_at", 3.0))
	var rank := int(r.get("rank", 0))
	if rank < 3 and float(r["skill"]) >= expert_at:
		r["rank"] = 3
		_chron("chron.skill_expert", String(r["name"]), String(r["prof"]))
		events.append({"type": "skill_up", "name": String(r["name"]), "rank": "expert"})
	elif rank < 5 and float(r["skill"]) >= skill_max - 0.001:
		r["rank"] = 5
		_chron("chron.skill_master", String(r["name"]), String(r["prof"]))
		events.append({"type": "skill_up", "name": String(r["name"]), "rank": "master"})


func _make_ail(r: Dictionary, kind: String, chron_key: String) -> void:
	r["ail"] = kind
	r["ail_days"] = 0.0
	_chron(chron_key, String(r["name"]))
	# болеющий не держит рабочее место: здоровый замещающий подхватит (анти-стопор)
	if r["bld"] != null:
		(r["bld"] as Dictionary)["worker"] = -1
	if r["site"] != null:
		(r["site"] as Dictionary)["worker"] = -1
	r["bld"] = null
	r["site"] = null
	r["sub_prof"] = ""
	_assign_jobs()


## Больной/раненый идёт домой и лежит.
func _lie_ill(r: Dictionary, dt: float) -> void:
	if _homeless(r):
		r["home"] = _free_home(r)
	var home: Dictionary = r["home"]
	if not home.is_empty():
		if not at_bld(r, home):
			_move_towards(r, bld_spot(home), dt)
			return
		r["inside"] = 1   # болтый лежит внутри дома, с карты не виден
	r["state"] = String(r["ail"])


## Смерть жителя: летопись, тост, горе всем (храбрый/трусливый меняют силу).
func _kill(r: Dictionary, chron_key: String) -> void:
	_chron(chron_key, String(r["name"]))
	events.append({"type": "died", "name": String(r["name"])})
	_start_funeral(r, Vector2(r["pos"]))   # процессия к кладбищу, могилка (M12)
	var grief: float = float(people.get("grief_mood", 20.0))
	for other in residents:
		if other == r:
			continue
		var gm := _trait_prod(other, "grief_mult")
		other["mood"] = clampf(float(other["mood"]) - grief * gm, 0.0, 100.0)
	if r["bld"] != null:
		(r["bld"] as Dictionary)["worker"] = -1
	if r["site"] != null:
		(r["site"] as Dictionary)["worker"] = -1
	if bool(r.get("kit", false)):
		res["kits"] = float(res.get("kits", 0.0)) + 1.0   # комплект вернулся в хранилище
	# овдовевший партнёр (M13): сброс пары и дополнительное горе
	var pid := int(r.get("partner", -1))
	if pid >= 0:
		var widow := _resident_by_id(pid)
		if not widow.is_empty():
			widow["partner"] = -1
			widow["mood"] = clampf(float(widow["mood"])
					- float(people.get("couples", {}).get("widow_grief", 10.0)), 0.0, 100.0)
			_chron("chron.widow", String(widow["name"]), String(r["name"]))
			_mem_push(widow, "widow")   # память v3: горе тает медленно
			events.append({"type": "widow", "a": String(widow["name"]), "b": String(r["name"])})
	residents.erase(r)
	_assign_jobs()


func _resident_by_id(res_id: int) -> Dictionary:
	for r in residents:
		if int(r["id"]) == res_id:
			return r
	return {}


func _healer_ready() -> bool:
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "heal" and int(b["worker"]) > 0:
			return true
	return false


func _manned_towers() -> int:
	var count := 0
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "guard" and int(b["worker"]) > 0:
			count += 1
	return count


## Запас еды хотя бы на день впереди — иначе город не тянется и приток стоит.
## Кучи еды у ферм тоже считаются (M6: они скоро попадут на склад).
func _food_reserve_ok() -> bool:
	var have: float = float(res["food"]) + _piled_total_of("food")
	return have >= float(residents.size()) * float(cfg["food_per_resident_day"])


## Почему не растёт город (беженцы и рождения): "" — всё ок, иначе ключ локализации.
func growth_block() -> String:
	if residents.size() >= pop_cap():
		return "city.growth_cap"
	if not _food_reserve_ok():
		return "city.growth_food"
	var min_gate: float = minf(
			float(people.get("refugees", {}).get("mood_gate", 45.0)),
			float(people.get("births", {}).get("mood_gate", 60.0)))
	if _avg_mood() < min_gate:
		return "city.growth_mood"
	return ""


# --- таверна (излишки еды -> пиво -> настроение) ---------------------------

## Хватает ли еды сверх дневного запаса: только тогда таверна варит пиво.
func _tavern_surplus() -> bool:
	var reserve: float = float(residents.size()) * float(cfg["food_per_resident_day"])
	return float(res["food"]) > reserve + 1.0


func tavern_active() -> bool:
	var tcfg: Dictionary = cfg.get("tavern", {})
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "tavern" and int(b["worker"]) > 0:
			return _tavern_surplus()
	return false


## Работающая таверна пьёт только ИЗЛИШКИ еды сверх дневного запаса (просьба заказчика).
func _tavern_beer(dt: float, day_len: float) -> void:
	var tcfg: Dictionary = cfg.get("tavern", {})
	for b in buildings:
		if b["done"] and _def(b).get("effect", "") == "tavern" and int(b["worker"]) > 0:
			var sip: float = float(tcfg.get("food_per_day", 8.0)) * dt / day_len
			if _tavern_surplus():
				res["food"] = maxf(0.0, float(res["food"]) - sip)


