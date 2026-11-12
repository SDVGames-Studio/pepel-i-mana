# Пропсы города (v1.63): нарезка заказчика (118 шт, ASSETS.md) открывается
# через префикс pc: и подключена справочниками отрисовки.
# Модуль тестов (структура v1.20.2); общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"


func _test_props() -> void:
	print("[Пропсы города v1.63]")
	# 1) папка на месте и нарезка полная
	var dir := DirAccess.open("res://assets/sprites/props_city")
	_check(dir != null, "папка props_city доступна")
	var names: Array = []
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.get_extension() == "png":
				names.append(fn.get_basename())
			fn = dir.get_next()
		dir.list_dir_end()
	_check(names.size() >= 118, "нарезка полная: %d пропсов (>= 118)" % names.size())
	# 2) каждый файл открывается через префикс pc: (assets.gd)
	var missing: Array = []
	for n in names:
		if Assets.sprite("pc:" + String(n)) == null:
			missing.append(n)
	_check(missing.is_empty(), "все %d пропсов открываются через pc:%s" % [
			names.size(), "" if missing.is_empty() else " — нет: " + ", ".join(missing.slice(0, 5))])
	# 3) справочники отрисовки ведут только на существующие файлы
	var vp: Script = load("res://scripts/city_view_props.gd")
	_check(vp != null and vp.can_instantiate(), "city_view_props.gd компилируется")
	var refs: Array = (vp.GRAVE_REFS as Array) + (vp.LANTERN_REFS as Array) \
			+ (vp.STATUE_REFS as Array) + (vp.PROP_PILE.values() as Array)
	var bad_refs: Array = []
	for ref in refs:
		if Assets.sprite(String(ref)) == null:
			bad_refs.append(String(ref))
	_check(refs.size() >= 40 and bad_refs.is_empty(),
			"справочники валидны: %d рефов, битых %d" % [refs.size(), bad_refs.size()])
	# 4) данные: рынок одет шатром из пака
	var city_cfg: Variant = _read_json("res://data/city.json")
	if city_cfg is Dictionary:
		var mref := ""
		for b in (city_cfg as Dictionary).get("buildings", []):
			if String((b as Dictionary).get("id", "")) == "market":
				mref = String((b as Dictionary).get("sprite", ""))
				break
		_check(mref == "pc:шатёр", "рынок рисуется шатром из пака (pc:шатёр)")
		_check(Assets.sprite("pc:шатёр") != null, "шатёр рынка существует")
	# 5) расстановка детерминирована: хэш-функция стабильна (дисциплина
	# расстановки фонарей/надгробий — без новой симуляции)
	_check(vp._hash(3, 7, 6) == vp._hash(3, 7, 6), "хэш расстановки детерминирован")
