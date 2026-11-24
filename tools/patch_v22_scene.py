# -*- coding: utf-8 -*-
## v2.2 патч 8: сцена — флаги близости, E-цепочка (след/допрос/лагерь/алтарь),
## диалоги и тосты, рисование следов/лагерей/духов, спрайт идола, локи.
import io

ROOT = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts"

# ============ city_base.gd: флаги + подсказки ============
pb = ROOT + r"\city_base.gd"
b = io.open(pb, encoding="utf-8").read()
assert "_near_track" not in b, "city_base: already patched"
a = "var _near_mold := Vector2i(-1, -1)  # v1.84: заражённая плесенью клетка рядом\n"
assert a in b, "city_base: var anchor missing"
b = b.replace(a, a + (
    "var _near_track: Dictionary = {}   # v2.2 п.3: свежий след у ног героя\n"
    "var _near_spy: Dictionary = {}     # v2.2 п.4а: подозрительный путник рядом\n"
    "var _near_camp: Dictionary = {}    # v2.2 п.4: найденный тайный лагерь рядом\n"
    "var _near_altar: Dictionary = {}   # v2.2 п.2: алтарь благодати с духом рядом\n"), 1)

a2 = '''	# v1.84: серая плесень рядом — E лечит магией (10 маны)
	_near_mold = Vector2i(-1, -1)
'''
assert a2 in b, "city_base: mold flag anchor missing"
b = b.replace(a2, a2 + '''	# v2.2: следы, лазутчики, тайные лагеря, алтарь благодати
	_near_track = {}
	_near_spy = {}
	_near_camp = {}
	_near_altar = {}
	if not guest:
		var tr_cfg: Dictionary = sim.cfg.get("tracks", {})
		var tr_life := float(tr_cfg.get("life_days", 1.2)) * float(sim.cfg["day_length"])
		_near_track = sim.TRACKS.near(sim.city_tracks, hero.position,
				float(map.ts) * 1.7, float(sim.time), tr_life)
		for w2 in sim.wanderers:
			if bool(w2.get("spy", false)) and hero.position.distance_to(
					w2["pos"] as Vector2) < float(map.ts) * 1.7:
				_near_spy = w2
				break
		for camp in sim.secret_camps:
			if bool(camp.get("found", false)) and hero.position.distance_to(
					map.tile_center_px(camp["tile"] as Vector2i)) < float(map.ts) * 2.2:
				_near_camp = camp
				break
		for bld in sim.buildings:
			if bool(bld["done"]) and String(bld["type"]) == "grace_altar" \\
					and hero.position.distance_to(
					map.tile_center_px(bld["tile"] as Vector2i)) < float(map.ts) * 2.2:
				var sp2: Dictionary = sim.spirit_of(bld)
				_near_altar = {"bld": bld, "spirit": sp2}
				break
''', 1)

a3 = '''	elif _near_elder:
		hud.set_hint(Loc.t("elder.mem_hint"))
'''
assert a3 in b, "city_base: hint chain anchor missing"
r3 = '''	elif _near_elder:
		hud.set_hint(Loc.t("elder.mem_hint"))
	elif not _near_camp.is_empty():
		hud.set_hint(Loc.t("city.camp_hint"))
	elif not _near_altar.is_empty():
		hud.set_hint(Loc.t("city.altar_hint"))
	elif not _near_spy.is_empty():
		hud.set_hint(Loc.t("city.spy_hint"))
	elif not _near_track.is_empty():
		hud.set_hint(Loc.t("city.track_follow_hint"))
'''
b = b.replace(a3, r3, 1)
io.open(pb, "w", encoding="utf-8", newline="\n").write(b)
print("city_base: flags + hints")

# ============ city_input.gd: E-цепочка ============
pi = ROOT + r"\city_input.gd"
i = io.open(pi, encoding="utf-8").read()
assert "_near_track" not in i, "city_input: already patched"
a4 = '''			# v1.81: староста-голем — диалог «Память мира» (док 18)
			if _near_elder:
				_open_elder_dialog()
				return
'''
assert a4 in i, "city_input: elder anchor missing"
r4 = a4 + '''			# v2.2 п.4: найденный тайный лагерь — штурм героя/стражей
			if not _near_camp.is_empty():
				_open_camp_dialog(_near_camp)
				return
			# v2.2 п.2: алтарь благодати — выбор дела духа
			if not _near_altar.is_empty() and not (_near_altar["spirit"] as Dictionary).is_empty():
				_open_altar_dialog(_near_altar)
				return
			# v2.2 п.4а: допрос подозрительного путника
			if not _near_spy.is_empty():
				_interrogate_action(_near_spy)
				return
			# v2.2 п.3: идти по следу
			if not _near_track.is_empty():
				_follow_tracks_action()
				return
'''
i = i.replace(a4, r4, 1)
io.open(pi, "w", encoding="utf-8", newline="\n").write(i)
print("city_input: E-chain")

# ============ city_events.gd: диалоги + тосты событий ============
pe = ROOT + r"\city_events.gd"
e = io.open(pe, encoding="utf-8").read()
assert "_open_camp_dialog" not in e, "city_events: already patched"
a5 = '''			"mold_started":
				hud.toast(Loc.t("city.mold_started"))
'''
assert a5 in e, "city_events: mold toast anchor missing"
r5 = a5 + '''			"spirit_summoned":
				hud.toast(Loc.t("city.spirit_summoned"))
			"spirit_died":
				hud.toast(Loc.t("city.spirit_died"))
			"hunt_report":
				hud.toast(Loc.t("city.hunt_report_toast") % String(ev.get("side", "")))
			"hunt_squad_come":
				_letter("hunt_squad_come", Loc.t("city.hunt_squad_come"))
			"hunt_squad_here":
				hud.toast(Loc.t("city.hunt_squad_here"))
			"hunt_squad_win":
				_letter("hunt_squad_win", Loc.t("city.hunt_squad_win"))
			"warehouse_theft":
				hud.toast(Loc.t("city.warehouse_theft") % int(ev.get("food", 0)))
			"sect_sermon":
				hud.toast(Loc.t("city.sect_sermon"))
			"camp_found":
				_letter("camp_found", Loc.t("city.camp_found_toast"))
			"camp_razed":
				_letter("camp_razed", Loc.t("city.camp_razed_toast"))
			"hive_knows_city":
				hud.toast(Loc.t("city.hive_knows_toast"))
			"hive_alert_fuzzy":
				hud.toast(Loc.t("city.hive_alert_toast"))
'''
e = e.replace(a5, r5, 1)

tail = '''

## ==================== v2.2: СЛЕДЫ / ЛАГЕРЯ / АЛТАРЬ / ДОПРОС ====================

## «Идти по следу» (E у свежего следа): подсветить цепочку и показать,
## куда она ведёт (по следам мутантов — к логову, по лазутчикам — к лагерю).
func _follow_tracks_action() -> void:
	var tcfg: Dictionary = sim.cfg.get("tracks", {})
	var life := float(tcfg.get("life_days", 1.2)) * float(sim.cfg["day_length"])
	var chain: Array = []
	for who in ["raider", "spy", "res"]:
		chain = sim.TRACKS.chain(sim.city_tracks, hero.position,
				float(map.ts) * 2.0, float(sim.time), life, who, 12)
		if chain.size() >= 2:
			break
	if chain.is_empty():
		hud.toast(Loc.t("city.track_lost"))
		return
	sim.track_chain = chain
	sim.track_hint_until = float(sim.time) + 15.0
	var dirv: Vector2 = chain.back()["dir"]
	hud.toast(Loc.t("city.track_hint") % sim._compass_of(dirv))


## Допрос «путника» (E рядом): алиби, улика с раскрытием лагеря или паника.
func _interrogate_action(spy: Dictionary) -> void:
	var res := sim.interrogate_spy(int(spy["id"]))
	match res:
		"alibi":
			hud.toast(Loc.t("city.spy_alibi"))
		"confess":
			hud.toast(Loc.t("city.spy_confess"))
		"fled":
			hud.toast(Loc.t("city.spy_fled"))


## Диалог найденного тайного лагеря: штурм героем или отправить стражу.
func _open_camp_dialog(camp: Dictionary) -> void:
	var kind := Loc.t("camp.kind." + String(camp["kind"]))
	var lines: Array = []
	lines.append(Loc.t("city.camp_found_line") % kind)
	var choices: Array = []
	choices.append({
		"text": Loc.t("city.camp_choice_hero"),
		"action": func() -> void:
			var err: String = sim.assault_camp(true)
			if err != "":
				hud.toast(Loc.t(err))
	})
	choices.append({
		"text": Loc.t("city.camp_choice_guards"),
		"action": func() -> void:
			var err2: String = sim.assault_camp(false)
			if err2 != "":
				hud.toast(Loc.t(err2))
			else:
				hud.toast(Loc.t("city.camp_razed_toast"))
	})
	hud.open_choice(Loc.t("city.camp_title"), lines, choices)


## Диалог алтаря благодати: куда назначить духа (стройка/добыча/отдых).
func _open_altar_dialog(near: Dictionary) -> void:
	var sp: Dictionary = near["spirit"]
	var lines: Array = []
	lines.append(Loc.t("city.altar_eff_line") % int(round(float(sp["eff"]) * 100.0)))
	lines.append(Loc.t("city.altar_hp_line") % [int(sp["hp"]), int(sp["hp_max"])])
	var choices: Array = []
	choices.append({
		"text": Loc.t("city.altar_choice_build"),
		"action": func() -> void: sp["mode"] = "build"
	})
	choices.append({
		"text": Loc.t("city.altar_choice_gather"),
		"action": func() -> void: sp["mode"] = "gather"
	})
	choices.append({
		"text": Loc.t("city.altar_choice_idle"),
		"action": func() -> void: sp["mode"] = "idle"
	})
	hud.open_choice(Loc.t("city.altar_title"), lines, choices)
'''
e = e.rstrip("\n") + "\n" + tail
io.open(pe, "w", encoding="utf-8", newline="\n").write(e)
print("city_events: dialogs + toasts")

# ============ city_flora.gd: рисование следов и найденных лагерей ============
pf = ROOT + r"\city_flora.gd"
f = io.open(pf, encoding="utf-8").read()
assert "city_tracks" not in f, "city_flora: already patched"
anchor_end = "	if sim != null and sim.get(\"mold\") != null:"
assert anchor_end in f, "city_flora: mold block anchor missing"
add = '''	# v2.2 п.3: следы всех ходячих — тающие точки; цепочка «идти по следу» ярче
	if sim != null and sim.get("city_tracks") != null:
		var tracks: Array = sim.city_tracks
		var now: float = float(sim.time)
		var tr_cfg: Dictionary = sim.cfg.get("tracks", {})
		var tr_life := float(tr_cfg.get("life_days", 1.2)) * float(sim.cfg["day_length"])
		var chain: Array = sim.get("track_chain", [])
		var hinted := float(sim.get("track_hint_until", 0.0)) > now
		for tr in tracks:
			var p3: Vector2 = tr["pos"]
			if p3.x < vis.position.x or p3.x > vis.end.x \\
					or p3.y < vis.position.y or p3.y > vis.end.y:
				continue
			var age := clampf(1.0 - (now - float(tr["t"])) / tr_life, 0.0, 1.0)
			var col := Color(0.45, 0.36, 0.28, 0.55 * age)
			match String(tr["who"]):
				"raider":
					col = Color(0.55, 0.25, 0.2, 0.6 * age)
				"spy":
					col = Color(0.4, 0.3, 0.5, 0.7 * age)
				"animal":
					col = Color(0.5, 0.45, 0.3, 0.45 * age)
				"wanderer":
					col = Color(0.4, 0.42, 0.5, 0.5 * age)
			var in_chain := false
			if hinted:
				for c4 in chain:
					if c4 == tr:
						in_chain = true
						break
			if in_chain:
				col.a = 0.95
				draw_circle(p3, 3.0, col)
				draw_arc(p3, 5.5, 0, TAU, 12, col, 1.0)
			else:
				draw_circle(p3, 2.2, col)
	# v2.2 п.4: найденный тайный лагерь — метка (бандиты красная, сектанты лиловая)
	if sim != null and sim.get("secret_camps") != null:
		for camp in (sim.secret_camps as Array):
			if not bool(camp.get("found", false)):
				continue
			var cp: Vector2 = map.tile_center_px(camp["tile"] as Vector2i)
			var ccol := Color(0.8, 0.3, 0.2, 0.9) \\
					if String(camp["kind"]) == "bandit" else Color(0.6, 0.3, 0.7, 0.9)
			draw_arc(cp, float(map.ts) * 0.9, 0, TAU, 20, ccol, 2.0)
			draw_line(cp + Vector2(-6, -6), cp + Vector2(6, 6), ccol, 2.0)
			draw_line(cp + Vector2(-6, 6), cp + Vector2(6, -6), ccol, 2.0)
'''
f = f.replace(anchor_end, add + anchor_end, 1)
io.open(pf, "w", encoding="utf-8", newline="\n").write(f)
print("city_flora: tracks + camps")

# ============ city_view_nature.gd: дух в списке отрисовки ============
pv = ROOT + r"\city_view_nature.gd"
v = io.open(pv, encoding="utf-8").read()
assert '"spirit"' not in v, "city_view_nature: already patched"
a6 = '''	for w in sim.wanderers:
		dyn.append([Vector2(w["pos"]).y, "wanderer", w])
'''
assert a6 in v, "nature view: wanderer dyn anchor missing"
r6 = a6 + '''	for s in sim.spirits:
		dyn.append([Vector2(s["pos"]).y, "spirit", s])
'''
v = v.replace(a6, r6, 1)
a7 = '''			"raider":
				_draw_raider(e[2])
'''
assert a7 in v, "nature view: raider branch anchor missing"
r7 = a7 + '''			"spirit":
				_draw_spirit(e[2])
'''
v = v.replace(a7, r7, 1)
a8 = "func _draw_wanderer(w: Dictionary) -> void:"
assert a8 in v, "nature view: draw_wanderer anchor missing"
spirit_draw = '''## Дух благодати (v2.2 п.2): полупрозрачная приземистая фигура с ореолом.
func _draw_spirit(s: Dictionary) -> void:
	var pos: Vector2 = s["pos"]
	var bob := sin(_anim_time * 2.4 + float(int(s["id"])) * 1.7) * 2.0
	var top := pos + Vector2(0, -float(map.ts) * 0.55 + bob)
	draw_circle(pos + Vector2(0, -2), float(map.ts) * 0.38, Color(0.75, 0.7, 0.95, 0.18))
	draw_circle(top, float(map.ts) * 0.16, Color(0.85, 0.82, 1.0, 0.55))
	draw_circle(top, float(map.ts) * 0.09, Color(1.0, 1.0, 1.0, 0.75))


'''
v = v.replace(a8, spirit_draw + a8, 1)
io.open(pv, "w", encoding="utf-8", newline="\n").write(v)
print("city_view_nature: spirit")

# ============ city_view.gd: спрайт grace_altar (идолы Мокоши) ============
pw2 = ROOT + r"\city_view.gd"
w2 = io.open(pw2, encoding="utf-8").read()
assert "GRACE_ALTAR_REFS" not in w2, "city_view: already patched"
a9 = '''	if type_id == "statue":
'''
assert a9 in w2, "city_view: statue anchor missing"
r9 = '''	if type_id == "grace_altar":
		# v2.2 п.2: алтарь благодати — идолы из пака «идолы богов» (вариации)
		return GRACE_ALTAR_REFS[_hash(int(b["id"]), 7, GRACE_ALTAR_REFS.size())]
	if type_id == "statue":
'''
w2 = w2.replace(a9, r9, 1)
a10 = "func _bld_sprite_ref(type_id: String, b: Dictionary) -> String:"
assert a10 in w2, "city_view: sprite ref anchor missing"
w2 = w2.replace(a10, "const GRACE_ALTAR_REFS := [\n\t\"img:env/idol_mokosh_a\",\n\t\"img:env/idol_mokosh_b\",\n]\n\n\n" + a10, 1)
io.open(pw2, "w", encoding="utf-8", newline="\n").write(w2)
print("city_view: grace_altar sprite")

# ============ loc/ru.json: второй пакет ключей ============
import json
pl = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\loc\ru.json"
l = io.open(pl, encoding="utf-8").read()
if "city.camp_hint" not in l:
    keys2 = {
        "city.hive_knows_toast": "Логово мутантов нашло город — волны теперь идут в цель!",
        "city.hive_alert_toast": "Ищейка мутантов учуяла героя и убежала в логово",
        "city.track_follow_hint": "E: идти по следу",
        "city.camp_hint": "E: тайный лагерь — штурм",
        "city.altar_hint": "E: алтарь благодати — дух",
        "city.spy_hint": "E: допросить путника",
        "city.track_lost": "Следы истаяли — не за чем идти",
        "chron.spy_confess": "Путник %s выдал тайный лагерь на допросе",
        "chron.spy_fled": "Подозрительный путник запаниковал и сбежал",
    }
    a11 = '\t"city.spirit_draw": "дух"\n}'
    assert a11 in l, "ru.json: tail anchor 2 missing"
    parts = []
    for k, vv in keys2.items():
        parts.append('\t"%s": %s' % (k, json.dumps(vv, ensure_ascii=False)))
    r11 = a11[:-2] + ",\n" + ",\n".join(parts) + "\n}"
    l = l.replace(a11, r11, 1)
    io.open(pl, "w", encoding="utf-8", newline="\n").write(l)
    print("ru.json: keys batch 2")
json.load(io.open(pl, encoding="utf-8"))
print("ru.json valid")
