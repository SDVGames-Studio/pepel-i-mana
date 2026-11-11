# Часть: экономика производства — мастерская, производство в пул,
# бонусы богатств региона и ремесленный двор (v1.56).
# Структура v1.62.0: вынесено из city_sim_tick.gd. Один класс, поведение
# не меняется. Кучи (_add_pile/_pile_total) остались в тике — их зовут
# звенья выше.
extends "res://scripts/city_sim_residents.gd"

## Бонусы владения богатствами региона (v1.56): данные в city.json
## → resource_bonuses. Золото — монеты, рыбное изобилие — еда, предметы
## роскоши — настроение всем, янтарь — медленнее падает настроение.
func _apply_resource_bonuses() -> void:
	var bcfg: Dictionary = cfg.get("resource_bonuses", {})
	if bcfg.is_empty():
		return
	if float(res.get("gold", 0.0)) >= float(bcfg.get("gold_min", 1.0)):
		if coins_sink.is_valid():
			coins_sink.call(int(bcfg.get("gold_coins", 2)))   # налог золотом
	if float(res.get("lux", 0.0)) >= float(bcfg.get("lux_min", 1.0)):
		for r in residents:
			r["mood"] = clampf(float(r["mood"]) + float(bcfg.get("lux_mood", 1.0)), 0.0, 100.0)
	# v1.57: АЛКОГОЛЬ — гуляка городу (зимой вдвое веселее — согревает)
	var alcohol := float(res.get("alcohol", 0.0))
	if alcohol >= 1.0:
		var winter := season() == "winter"
		var am := float(cfg.get("alcohol_mood_winter" if winter else "alcohol_mood", 1.5))
		if alcohol >= 3.0:
			am += 1.0
		for r in residents:
			r["mood"] = clampf(float(r["mood"]) + am, 0.0, 100.0)
	# v1.60: караванные богатства — серебро (торговая репутация, монеты)
	# и янтарь (красота в домах, настроение)
	if float(res.get("silver", 0.0)) >= float(bcfg.get("silver_min", 10.0)) \
			and coins_sink.is_valid():
		coins_sink.call(int(bcfg.get("silver_coins", 2)))
	if float(res.get("amber", 0.0)) >= float(bcfg.get("amber_min", 8.0)):
		var am_mood := float(bcfg.get("amber_mood", 1.0))
		for r in residents:
			r["mood"] = clampf(float(r["mood"]) + am_mood, 0.0, 100.0)
	# v1.57: РАЗНООБРАЗИЕ ЕДЫ — за каждый возделанный вид культуры +0.5
	# настроения (до 3 видов) + рыбное изобилие считается
	var kinds := {}
	for z in zones:
		if String(z["type"]) != "field":
			continue
		for c in z["crops"]:
			if not (c as Dictionary).is_empty():
				kinds[String(c.get("crop", "?"))] = true
	if map.region_resource == "fish_abound":
		kinds["fish"] = true
	var variety := mini(3, kinds.size())
	if variety > 0:
		var vm := float(bcfg.get("variety_mood", 0.5)) * float(variety)
		for r in residents:
			r["mood"] = clampf(float(r["mood"]) + vm, 0.0, 100.0)
	if map.region_resource == "fish_abound" and not buildings.filter(
			func(b): return _active(b) and String(b["type"]) == "pier").is_empty():
		_add_resource_capped("food", float(bcfg.get("fish_food", 3.0)))


## Ремесленный двор (v1.56): за день превращает сырьё в ПРЕДМЕТЫ РОСКОШИ.
## Приоритет сырья: золото → серебро → жемчуг → янтарь → медь (2 → 1 lux).
func _craftsman_convert() -> void:
	var cdef: Dictionary = {}
	for d in cfg.get("buildings", []):
		if String(d.get("id", "")) == "craftsman":
			cdef = d
			break
	if cdef.is_empty():
		return
	var craft: Dictionary = cdef.get("craft", {})
	if craft.is_empty():
		return
	var per := float(cdef.get("cost_raw", 2.0))
	var working := false
	for b in buildings:
		if _active(b) and String(b["type"]) == "craftsman" and int(b["worker"]) > 0:
			working = true
			break
	if not working:
		return
	for raw_id in ["gold", "silver", "pearls", "amber", "copper"]:
		if float(res.get(raw_id, 0.0)) >= per:
			res[raw_id] = float(res[raw_id]) - per
			_add_resource_capped("lux", 1.0)
			events.append({"type": "lux_made", "res": raw_id})
			return   # один товар в день — роскошь редкая по определению


func _do_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		# дикая вспышка: здание молчит, работник стоит
		r["state"] = "idle"
		return
	if at_bld(r, bld):
		_produce_tick(r, bld, dt)
	else:
		_move_towards(r, bld_spot(bld), dt)


## Добытчики у источников (лесопилка/каменоломня/шахта) — правки v1.21
## переехали в city_sim_gather.gd: лесоруб валит и пилит, шахтёр носит
## сырой камень на переработку. Ниже — мастерская и производство.


## Мастерская (M6, перепрофилирование): сперва чинит повреждённые здания,
## когда чинить нечего — перерабатывает дерево и камень в инструменты.
func _workshop_work(r: Dictionary, bld: Dictionary, dt: float) -> void:
	if float(bld.get("stun_left", 0.0)) > 0.0:
		r["state"] = "idle"
		return
	var broken := _damaged_building(bld)
	if broken.is_empty():
		_produce_tick(r, bld, dt)   # переработка излишков в инструменты
		return
	if at_bld(r, broken):
		r["state"] = "repair"
		var rate: float = float(cfg.get("repair", {}).get("per_day", 15.0)) * work_mult(r)
		var max_hp := float(_bld_max_hp(String(broken["type"])))
		broken["hp"] = minf(float(broken.get("hp", max_hp)) + rate * dt / float(cfg["day_length"]), max_hp)
		r["fatigue"] += dt / float(cfg["day_length"]) * _fatigue_cost(r)
		_grow_skill(r, dt)
	else:
		_move_towards(r, bld_spot(broken), dt)


## Повреждённое готовое здание ближе прочих (для мастерской). Руины мастерская
## не поднимает — только стоящие повреждённые (этап 2, аспект 5).
func _damaged_building(near: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b in buildings:
		if not _active(b):
			continue
		var max_hp := float(_bld_max_hp(String(b["type"])))
		if float(b.get("hp", max_hp)) >= max_hp:
			continue
		var d: float = map.tile_center_px(b["tile"]).distance_to(map.tile_center_px(near["tile"]))
		if d < best_d:
			best_d = d
			best = b
	return best



## Само производство: расход материалов, множители — и продукция СРАЗУ
## в общий пул (v1.25, заказчик: «в лесопилке остался какой-то пул досок —
## а зачем?»). Куч у зданий больше нет; носильщик остался только для
## старых сейвов — разносит уцелевшие кучи (M6 физическая логистика упразднена).
func _produce_tick(r: Dictionary, bld: Dictionary, dt: float) -> void:
	r["state"] = "work"
	r["fatigue"] += dt / float(cfg["day_length"]) * _fatigue_cost(r)
	_grow_skill(r, dt)
	var prod: Dictionary = _def(bld)["produce"]
	# расход материалов (мастерская: дерево + камень -> инструменты)
	var portion: float = dt / float(cfg["day_length"])
	var inputs: Dictionary = prod.get("inputs", {})
	for key in inputs:
		if float(res.get(String(key), 0.0)) < float(inputs[key]) * portion:
			r["state"] = "idle"   # материалы кончились — стоит
			return
	for key in inputs:
		res[String(key)] = maxf(0.0, float(res[key]) - float(inputs[key]) * portion)
	var boost: float = blessing_boost()
	var amount: float = float(prod["per_day"]) * portion * boost * production_mult(bld) * work_mult(r)
	_add_resource_capped(String(prod["res"]), amount)
	# v1.56: пристань добывает богатство воды (жемчуг/рыбное изобилие) —
	# половина темпа от еды; на суше у пристани ресурса нет
	if String(bld["type"]) == "pier" and map.region_resource in ["pearls", "fish_abound"]:
		_add_resource_capped(String(map.region_resource), amount * 0.5)
	# шахта даёт и камень вместе с рудой (заказчик)
	if prod.has("res2"):
		var amount2: float = float(prod["per_day2"]) * portion * boost * production_mult(bld) * work_mult(r)
		_add_resource_capped(String(prod["res2"]), amount2)
