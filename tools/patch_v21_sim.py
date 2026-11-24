# -*- coding: utf-8 -*-
## v2.1 «Мозг старосты» патч 1: сим-слой — оборонный рывок и таверна по
## мечте (war-дневной блок), чемпион города (гибель героя -> подкрепление).
import io, sys

ROOT = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts"

# --- base: состояние чемпиона ---
pb = ROOT + r"\city_sim_base.gd"
b = io.open(pb, encoding="utf-8").read()
if "champion_due_day" in b:
    print("base: already patched")
else:
    a = "var acolyte_skill := 0.0       # мастерство аколита-контролёра (растёт со службой, 0..20)\n"
    assert a in b, "base: vars anchor missing"
    r = a + (
        "# v2.1 «Мозг старосты»: странствующий чемпион — подкрепление после гибели героя\n"
        "var champion: Dictionary = {}  # {name, hp, hp_max, atk, speed, pos, target, cd}\n"
        "var champion_due_day := -1     # день, когда придет чемпион (-1 — герой жив)\n")
    b = b.replace(a, r, 1)
    a2 = "\tacolyte_skill = 0.0\n"
    assert a2 in b, "base: reset anchor missing"
    b = b.replace(a2, a2 + "\tchampion = {}\n\tchampion_due_day = -1\n", 1)
    io.open(pb, "w", encoding="utf-8", newline="\n").write(b)
    print("base: champion state")

# --- war: рывок, таверна, чемпион ---
pw = ROOT + r"\city_sim_war.gd"
w = io.open(pw, encoding="utf-8").read()
if "defence_rush_daily" in w:
    print("war: already patched")
    sys.exit(0)

# 1) дневной блок: рывок и таверна до лагерей
a1 = '''		secret_camp_daily()
		altar_daily()
		hunt_report_daily()
		hunt_squad_daily()
'''
assert a1 in w, "war: daily block anchor missing"
r1 = '''		defence_rush_daily()   # v2.1 причина 1: оборонный рывок до волны
		tavern_request_daily() # v2.1 причина 2: мечта «пировать» -> таверна
		_champion_daily()      # v2.1 причина 3: чемпион после гибели героя
		secret_camp_daily()
		altar_daily()
		hunt_report_daily()
		hunt_squad_daily()
'''
w = w.replace(a1, r1, 1)

# 2) тик: чемпион дерётся в волне (рядом с духами)
a2 = '''func _update_ambush_units(dt: float, tcfg: Dictionary) -> void:
	if not spirits.is_empty():
		_update_spirits(dt)   # v2.2 п.2: духи благодати работают и гибнут
'''
assert a2 in w, "war: ambush head anchor missing"
r2 = '''func _update_ambush_units(dt: float, tcfg: Dictionary) -> void:
	if not spirits.is_empty():
		_update_spirits(dt)   # v2.2 п.2: духи благодати работают и гибнут
	_update_champion(dt)   # v2.1: чемпион города держит волну
'''
w = w.replace(a2, r2, 1)

# 3) мутанты отвлекаются на чемпиона (после блока героя, перед жителями)
a3 = '''	# v1.46 («Новый мир v2» этап 4): герой далеко или его нет — мутанты
	# переключаются на ближайшего жителя (город перестаёт быть невидимым)
	var hero_d2: float = (r["pos"] as Vector2).distance_to(hero_pos) if hero_alive else 1e9
'''
assert a3 in w, "war: raider diversion anchor missing"
r3 = '''	# v2.1: чемпион города — та же приманка, что герой: держит волну на стенах
	if not (champion as Dictionary).is_empty() and bool(champion.get("alive", true)):
		var to_ch: Vector2 = (champion["pos"] as Vector2) - (r["pos"] as Vector2)
		var ch_d: float = to_ch.length()
		if ch_d <= float(p["aggro"]):
			if ch_d <= float(p["attack_range"]) + 12.0:
				if float(r["atk_cd"]) <= 0.0:
					r["atk_cd"] = float(p["attack_cooldown"])
					champion["hp"] = float(champion["hp"]) - float(p["damage"])
				return true
			if _raider_move_to(r, map.tile_of_px(champion["pos"] as Vector2),
					float(p["speed"]) * mv):
				return true
	# v1.46 («Новый мир v2» этап 4): герой далеко или его нет — мутанты
	# переключаются на ближайшего жителя (город перестаёт быть невидимым)
	var hero_d2: float = (r["pos"] as Vector2).distance_to(hero_pos) if hero_alive else 1e9
'''
w = w.replace(a3, r3, 1)

# 4) новые функции в хвост
tail = '''

## ==================== v2.1 «МОЗГ СТАРОСТЫ» ====================
## Диагноз 100-дневного прогона: город не строил оборону до волны
## (стены начинались только после полной застройки), таверна по мечте
## жителя ничем не подкреплена, после гибели героя город гас без замены.

## Герой пал (данж или симуляция): город молится о странствующем чемпионе.
func hero_fell() -> void:
	if champion_due_day > 0 or not (champion as Dictionary).is_empty():
		return   # уже ждём или чемпион на месте
	var ccfg: Dictionary = cfg.get("champion", {})
	champion_due_day = int(day) + int(ccfg.get("delay_min", 3)) \\
			+ (_event_rng.randi_range(0, maxi(0, int(ccfg.get("delay_max", 5))
					- int(ccfg.get("delay_min", 3)))))
	events.append({"type": "hero_fell"})
	_chron("chron.hero_fell")


## Ежедневно: чемпиона ждут — и он приходит (один раз, без замены).
func _champion_daily() -> void:
	if champion_due_day < 0 or not (champion as Dictionary).is_empty():
		return
	if int(day) < champion_due_day or map == null:
		return
	var ccfg: Dictionary = cfg.get("champion", {})
	var names: Array = ccfg.get("names", ["Ратмир", "Добрыня", "Горазд", "Свенн"])
	var nm := String(names[_event_rng.randi_range(0, names.size() - 1)])
	var t := map.spawn_tile
	for attempt in 40:
		var ang := TAU * _event_rng.randf()
		var rr := 6.0 + _event_rng.randf() * 4.0
		var t2 := map.spawn_tile + Vector2i(int(round(cos(ang) * rr)),
				int(round(sin(ang) * rr)))
		if map.in_bounds(t2) and map.is_walkable(t2):
			t = t2
			break
	champion = {
		"name": nm, "hp": float(ccfg.get("hp", 60.0)), "hp_max": float(ccfg.get("hp", 60.0)),
		"atk": float(ccfg.get("atk", 9.0)), "speed": float(ccfg.get("speed", 80.0)),
		"pos": map.tile_center_px(t), "target": Vector2i(-1, -1), "cd": 0.0,
		"alive": true,
	}
	champion_due_day = -1
	events.append({"type": "champion_arrived", "name": nm})
	_chron("chron.champion_arrived", nm)


## Тик чемпиона: в волне держит строй мутантов у стен, вне волны — у ворот.
func _update_champion(dt: float) -> void:
	if (champion as Dictionary).is_empty():
		return
	if not bool(champion.get("alive", true)):
		champion = {}
		return
	champion["cd"] = maxf(0.0, float(champion["cd"]) - dt)
	# мутанты рядом бьют чемпиона (отвлечение уже в _raider_update)
	if raid_active:
		var vic: Dictionary = _nearest_raider(champion["pos"] as Vector2,
				float(map.ts) * 5.0)
		if not vic.is_empty():
			var goal: Vector2 = vic["pos"] as Vector2
			if (champion["pos"] as Vector2).distance_to(goal) < float(map.ts) * 0.9:
				if float(champion["cd"]) <= 0.0:
					champion["cd"] = 0.7
					_hit_raider(vic, int(round(float(champion["atk"]))),
							Vector2i(-9999, -9999), "champion")
			else:
				var v: Vector2 = goal - (champion["pos"] as Vector2)
				champion["pos"] = (champion["pos"] as Vector2) \\
						+ v.normalized() * float(champion["speed"]) * dt
		if float(champion["hp"]) <= 0.0:
			champion = {}
			events.append({"type": "champion_fell"})
			_chron("chron.champion_fell")


## Причина 1: ОБОРОННЫЙ РЫВОК — волна близко (ETA <= eta_days), а город
## не укреплён: староста ставит кузню (стражи с железом) и ведёт стены
## сегментами вокруг жилья, не дожидаясь полной застройки.
func defence_rush_daily() -> void:
	if map == null:
		return
	var rcfg: Dictionary = cfg.get("defence_rush", {})
	if rcfg.get("enabled", true) == false:
		return
	if float(raid_eta_days()) > float(rcfg.get("eta_days", 5.0)):
		return
	if _defence_ready():
		return
	var built := 0
	# 1) кузня — без неё стражам нечем вооружиться
	var forge := false
	for b in buildings:
		if String(b["type"]) == "forge" and _active(b):
			forge = true
			break
	if not forge and not _autobuild_site_exists("forge"):
		var ft := _find_autobuild_tile("forge")
		if ft != Vector2i(-1, -1) and place_building("forge", ft):
			_announce_autobuild("forge", true)
			built += 1
	# 2) стены — три звена за день по кольцу жилья
	for i in 3:
		var wt := _next_wall_tile()
		if wt == Vector2i(-1, -1):
			break
		if not place_building("wall", wt):
			break
		built += 1
	if built > 0:
		events.append({"type": "defence_rush", "built": built})
		_chron("chron.defence_rush")


## Город готов к волне: кольцо стен замкнуто, кузня стоит, стражей двое.
func _defence_ready() -> bool:
	if _next_wall_tile() != Vector2i(-1, -1):
		return false
	var forge := false
	for b in buildings:
		if String(b["type"]) == "forge" and _active(b):
			forge = true
			break
	if not forge:
		return false
	var guards := 0
	for r in residents:
		if String(r["prof"]) == "guard":
			guards += 1
	return guards >= 2


## Причина 2: мечта «пировать в таверне» — житель ПИШЕТ старосте
## («Кира просит таверну»), и при pop >= 8 таверна строится вне очереди.
func tavern_request_daily() -> void:
	if map == null:
		return
	var tcfg: Dictionary = cfg.get("tavern_request", {})
	if tcfg.get("enabled", true) == false:
		return
	# таверна уже есть или строится
	var have := false
	for b in buildings:
		if String(b["type"]) == "tavern":
			have = true
			break
	if have:
		return
	if residents.size() < int(tcfg.get("pop", 8)):
		return
	for r in residents:
		if String(r.get("goal", "")) != "feast_tavern" or bool(r.get("tavern_asked", false)):
			continue
		r["tavern_asked"] = true
		events.append({"type": "tavern_request", "name": String(r["name"])})
		_chron("chron.tavern_request", String(r["name"]))
		var tt := _find_autobuild_tile("tavern")
		if tt != Vector2i(-1, -1) and place_building("tavern", tt):
			_announce_autobuild("tavern", true)
		return   # одно письмо в день — староста не читает пачками
'''
w = w.rstrip("\n") + "\n" + tail
io.open(pw, "w", encoding="utf-8", newline="\n").write(w)
print("war: v2.1 defence rush + tavern + champion")
