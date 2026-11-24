# -*- coding: utf-8 -*-
## v2.2 патч 7: путники-лазутчики (п.4а) — спавн и кражи в trade,
## допрос в war (там виден reveal_camp).
import io

ROOT = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts"

# --- trade: спавн лазутчика среди путников + разбор ухода ---
pt = ROOT + r"\city_sim_trade.gd"
t = io.open(pt, encoding="utf-8").read()
assert "_spy_depart" not in t, "trade: already patched"

a1 = '''	_last_wanderer_day = day
	var from := _edge_tile()
	wanderers.append({
		"id": _wanderer_id, "pos": map.tile_center_px(from), "path": PackedVector2Array(),
		"target": Vector2i(-1, -1), "mode": "come", "tent": int(tents[0]["id"]),
		"left": 0.0, "come": 0.0, "edge": from,
		"prof": "", "dir": "front", "state": "", "moving": false,
	})
	_wanderer_id += 1
'''
assert a1 in t, "trade: roll_wanderer anchor missing"
r1 = '''	_last_wanderer_day = day
	var from := _edge_tile()
	var spy := false
	var spy_name := ""
	var spy_camp := -1
	# v2.2 п.4а: воры из тайного лагеря приходят «путниками мимоходом»
	if not secret_camps.is_empty():
		var has_spy := false
		for x in wanderers:
			if bool(x.get("spy", false)):
				has_spy = true
				break
		if not has_spy and _event_rng.randf() < float(
				(cfg.get("camps", {}).get("spy_chance", 0.5))):
			var camp: Dictionary = secret_camps[0]
			var names: Array = camp.get("spies", [])
			if not names.is_empty():
				spy = true
				spy_name = String(names[int(camp.get("visits", 0)) % names.size()])
				spy_camp = int(camp["id"])
	wanderers.append({
		"id": _wanderer_id, "pos": map.tile_center_px(from), "path": PackedVector2Array(),
		"target": Vector2i(-1, -1), "mode": "come", "tent": int(tents[0]["id"]),
		"left": 0.0, "come": 0.0, "edge": from,
		"prof": "", "dir": "front", "state": "", "moving": false,
		"spy": spy, "spy_name": spy_name, "spy_camp": spy_camp,
	})
	_wanderer_id += 1
'''
t = t.replace(a1, r1, 1)

# уход путника за край: лазутчик прощается кражей
a2 = '''		else:   # leave: дошёл до своего края — ушёл из города
			var edge: Vector2i = w.get("edge", _edge_tile())
			_move_towards(w, edge, dt)
			if map.tile_of_px(w["pos"]) == edge:
				continue
		still.append(w)
'''
assert a2 in t, "trade: leave anchor missing"
r2 = '''		else:   # leave: дошёл до своего края — ушёл из города
			var edge: Vector2i = w.get("edge", _edge_tile())
			_move_towards(w, edge, dt)
			if map.tile_of_px(w["pos"]) == edge:
				if bool(w.get("spy", false)):
					_spy_depart(w)   # v2.2 п.4а: после визита — кража и подозрение
				continue
		still.append(w)
'''
t = t.replace(a2, r2, 1)

tail = '''

## ==================== ПУТНИКИ-ЛАЗУТЧИКИ (v2.2 п.4а) ====================
## Воры из тайного лагеря ходят в город под видом путников; после визита —
## шанс кражи со склада; жители замечают частые визиты + пропажи (мысли/
## дневники), при допросе (war.interrogate_spy) выдают лагерь или паникуют.

## Лагерь по id ({} если разгромлен).
func _spy_camp(cid: int) -> Dictionary:
	for c in secret_camps:
		if int(c["id"]) == cid:
			return c
	return {}


## Визит окончен: путник ушёл за край — подводим итоги визита.
func _spy_depart(w: Dictionary) -> void:
	var camp: Dictionary = _spy_camp(int(w.get("spy_camp", -1)))
	var ccfg: Dictionary = cfg.get("camps", {})
	var sname := String(w.get("spy_name", "путник"))
	var kn: Dictionary = spy_known.get(sname, {"visits": 0})
	kn["visits"] = int(kn["visits"]) + 1
	spy_known[sname] = kn
	if not camp.is_empty():
		camp["visits"] = int(camp["visits"]) + 1
	if _event_rng.randf() < float(ccfg.get("spy_steal_chance", 0.6)):
		var took := minf(float(ccfg.get("spy_steal_food", 3.0)), float(res.get("food", 0.0)))
		if took > 0.0:
			res["food"] = float(res["food"]) - took
			events.append({"type": "warehouse_theft", "food": int(took)})
		if not camp.is_empty():
			camp["suspicion"] = int(camp["suspicion"]) + 1
	# жители замечают: тот же облик + пропажи -> мысли/дневники
	if int(kn["visits"]) >= 2 and _event_rng.randf() < 0.5:
		for r in residents:
			if _event_rng.randf() < 0.5:
				res_log(r, "dlog.spy_seen")
				break
'''
t = t.rstrip("\n") + "\n" + tail
io.open(pt, "w", encoding="utf-8", newline="\n").write(t)
print("trade: spy wanderers")

# --- war: допрос (видит reveal_camp и _chron) ---
pw = ROOT + r"\city_sim_war.gd"
w = io.open(pw, encoding="utf-8").read()
assert "func interrogate_spy" not in w, "war: interrogate already there"
tail2 = '''

## ==================== ДОПРОС ЛАЗУТЧИКА (v2.2 п.4а) ====================
## Герой (или житель) допрашивает «путника» (E рядом, из city_events).
## "" — не лазутчик; "alibi" — отговорка (подозрение мало); "confess" —
## выдал лагерь; "fled" — запаниковал и убегает.
func interrogate_spy(wanderer_id: int) -> String:
	var w: Dictionary = {}
	for x in wanderers:
		if int(x["id"]) == wanderer_id:
			w = x
			break
	if w.is_empty() or not bool(w.get("spy", false)):
		return ""
	var sname := String(w.get("spy_name", "путник"))
	var kn: Dictionary = spy_known.get(sname, {"visits": 0})
	var camp: Dictionary = {}
	for c2 in secret_camps:
		if int(c2["id"]) == int(w.get("spy_camp", -1)):
			camp = c2
			break
	var suspicion := int(camp.get("suspicion", 0)) if not camp.is_empty() else int(kn["visits"])
	if suspicion < 2:
		return "alibi"
	if _event_rng.randf() < 0.6 and not camp.is_empty():
		reveal_camp()          # улика: лагерь раскрыт
		w["mode"] = "leave"    # путник спешит уйти
		w["target"] = Vector2i(-1, -1)
		_chron("chron.spy_confess", sname)
		return "confess"
	# паника: убегает, лагерь не выдал
	w["mode"] = "leave"
	w["target"] = Vector2i(-1, -1)
	_chron("chron.spy_fled")
	return "fled"
'''
w = w.rstrip("\n") + "\n" + tail2
io.open(pw, "w", encoding="utf-8", newline="\n").write(w)
print("war: interrogate_spy")
