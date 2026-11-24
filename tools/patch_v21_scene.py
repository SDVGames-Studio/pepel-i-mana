# -*- coding: utf-8 -*-
## v2.1 «Мозг старосты» патч 2: сцена/вью/данные — hero_fell хук города,
## отрисовка чемпиона, письма, локализация, конфиг, бот diary_story, сейв.
import io, json, sys

ROOT = r"F:\Z2\.zcode\workspace\default\pepel-i-mana"

# --- city_base: смерть героя в данже -> город ждёт чемпиона ---
pb = ROOT + r"\scripts\city_base.gd"
b = io.open(pb, encoding="utf-8").read()
if "hero_fell" not in b:
    a = '''	sim.paused = false
	get_tree().paused = false   # v1.30.1: после смерти в данже пауза не должна протекать в город
'''
    assert a in b, "city_base: ready anchor missing"
    r = a + '''	# v2.1 причина 3: герой погиб в данже — город ждёт странствующего чемпиона
	if not guest and bool(Game.get("last_run_death")):
		sim.hero_fell()
		Game.last_run_death = false
'''
    b = b.replace(a, r, 1)
    io.open(pb, "w", encoding="utf-8", newline="\n").write(b)
    print("city_base: hero_fell hook")

# --- city_view_nature: чемпион в списке отрисовки ---
pv = ROOT + r"\scripts\city_view_nature.gd"
v = io.open(pv, encoding="utf-8").read()
if '"champion"' not in v:
    a = '''	for s in sim.spirits:
		dyn.append([Vector2(s["pos"]).y, "spirit", s])
'''
    assert a in v, "view: spirits dyn anchor missing"
    r = a + '''	if not (sim.champion as Dictionary).is_empty():
		dyn.append([Vector2(sim.champion["pos"]).y, "champion", sim.champion])
'''
    v = v.replace(a, r, 1)
    a2 = '''			"spirit":
				_draw_spirit(e[2])
'''
    assert a2 in v, "view: spirit branch anchor missing"
    v = v.replace(a2, a2 + '''			"champion":
				_draw_champion(e[2])
''', 1)
    a3 = "## Дух благодати (v2.2 п.2): полупрозрачная приземистая фигура с ореолом."
    assert a3 in v, "view: spirit draw anchor missing"
    champ_draw = '''## Чемпион города (v2.1): тёмная фигура в стальном нагруднике с алым плюмажем.
func _draw_champion(c: Dictionary) -> void:
	var pos: Vector2 = c["pos"]
	var bob := sin(_anim_time * 5.0) * 1.5
	var base := pos + Vector2(0, -3)
	# тень
	draw_circle(pos + Vector2(0, 2), float(map.ts) * 0.3, Color(0, 0, 0, 0.18))
	# алый плащ за спиной
	draw_circle(base + Vector2(-3, -float(map.ts) * 0.30 + bob), float(map.ts) * 0.22,
			Color(0.62, 0.13, 0.15, 0.85))
	# стальной нагрудник
	draw_circle(base + Vector2(0, -float(map.ts) * 0.28 + bob), float(map.ts) * 0.20,
			Color(0.72, 0.74, 0.80, 0.95))
	draw_circle(base + Vector2(0, -float(map.ts) * 0.28 + bob), float(map.ts) * 0.12,
			Color(0.85, 0.87, 0.92, 1.0))
	# шлем с плюмажем
	var head := base + Vector2(0, -float(map.ts) * 0.52 + bob)
	draw_circle(head, float(map.ts) * 0.12, Color(0.55, 0.57, 0.62, 1.0))
	draw_rect(Rect2(head + Vector2(-1.5, -float(map.ts) * 0.30), Vector2(3.0, 7.0)),
			Color(0.75, 0.15, 0.18, 0.95))


'''
    v = v.replace(a3, champ_draw + a3, 1)
    io.open(pv, "w", encoding="utf-8", newline="\n").write(v)
    print("city_view_nature: champion")

# --- notice_feed: типы писем ---
pn = ROOT + r"\scripts\notice_feed.gd"
n = io.open(pn, encoding="utf-8").read()
if "champion_arrived" not in n:
    a = '\t"wanderer": "people", "refugee": "people", "legend_joined": "people",\n'
    assert a in n, "notice_feed: people kinds anchor missing"
    r = a + '''	"hero_fell": "people", "champion_arrived": "people", "champion_fell": "threat",
	"tavern_request": "people",
'''
    n = n.replace(a, r, 1)
    io.open(pn, "w", encoding="utf-8", newline="\n").write(n)
    print("notice_feed: letter kinds")

# --- city_events: тосты/письма новых событий ---
pe = ROOT + r"\scripts\city_events.gd"
e = io.open(pe, encoding="utf-8").read()
if "champion_arrived" not in e:
    a = '''			"spirit_summoned":
				hud.toast(Loc.t("city.spirit_summoned"))
'''
    assert a in e, "city_events: toast anchor missing"
    r = a + '''			"hero_fell":
				_letter("hero_fell", Loc.t("city.hero_fell_letter"))
			"champion_arrived":
				_letter("champion_arrived",
						Loc.t("city.champion_letter") % String(ev.get("name", "")))
			"champion_fell":
				hud.toast(Loc.t("city.champion_fell_toast"))
			"tavern_request":
				_letter("tavern_request",
						Loc.t("city.tavern_request_letter") % String(ev.get("name", "")))
			"defence_rush":
				hud.toast(Loc.t("city.defence_rush_toast"))
'''
    e = e.replace(a, r, 1)
    io.open(pe, "w", encoding="utf-8", newline="\n").write(e)
    print("city_events: v2.1 toasts")

# --- diary_story: бот сообщает о гибели героя ---
pd = ROOT + r"\tools\diary_story.gd"
d = io.open(pd, encoding="utf-8").read()
if "hero_fell" not in d:
    a = "\t\t\t\tsim.hero_alive = false\n"
    assert a in d, "diary_story: bot death anchor missing"
    r = "\t\t\t\tsim.hero_alive = false\n\t\t\t\tsim.hero_fell()   # v2.1: город зовёт чемпиона\n"
    d = d.replace(a, r, 1)
    io.open(pd, "w", encoding="utf-8", newline="\n").write(d)
    print("diary_story: hero_fell")

# --- save: чемпион ---
psw = ROOT + r"\scripts\save_game_write.gd"
sw = io.open(psw, encoding="utf-8").read()
if '"champion"' not in sw:
    a = '\t\t"acolyte_skill": float(sim.acolyte_skill),\n'
    assert a in sw, "save_write: acolyte anchor missing"
    r = a + '\t\t"champion": sim.champion,\n\t\t"champion_due_day": int(sim.champion_due_day),\n'
    sw = sw.replace(a, r, 1)
    io.open(psw, "w", encoding="utf-8", newline="\n").write(sw)
    print("save_write: champion")

ps = ROOT + r"\scripts\save_game.gd"
s = io.open(ps, encoding="utf-8").read()
if '"champion"' not in s:
    a = "\tsim.acolyte_skill = float(sd.get(\"acolyte_skill\", 0.0))\n"
    assert a in s, "save: acolyte anchor missing"
    r = a + '''	sim.champion = _dec(sd.get("champion", {}))
	if not sim.champion.is_empty():
		sim.champion["pos"] = sim.champion.get("pos", Vector2.ZERO) as Vector2
	sim.champion_due_day = int(sd.get("champion_due_day", -1))
'''
    s = s.replace(a, r, 1)
    io.open(ps, "w", encoding="utf-8", newline="\n").write(s)
    print("save: champion")

# --- city.json: конфиги v2.1 ---
pc = ROOT + r"\data\city.json"
c = json.load(io.open(pc, encoding="utf-8"))
if "defence_rush" not in c:
    c["defence_rush"] = {
        "enabled": True, "eta_days": 5.0,
        "_note": "v2.1 причина 1: за 5 дней до волны староста строит кузню и ведёт стены, не дожидаясь полной застройки",
    }
    c["tavern_request"] = {
        "enabled": True, "pop": 8,
        "_note": "v2.1 причина 2: житель с мечтой feast_tavern пишет старосте — таверна вне очереди при pop >= 8",
    }
    c["champion"] = {
        "hp": 60.0, "atk": 9.0, "speed": 80.0,
        "delay_min": 3, "delay_max": 5,
        "names": ["Ратмир", "Добрыня", "Горазд", "Свенн"],
        "_note": "v2.1 причина 3: странствующий чемпион приходит через 3-5 дней после гибели героя, держит волну у стен; погибает — не заменяется",
    }
    json.dump(c, io.open(pc, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent="\t")
    print("city.json: v2.1 cfg")

# --- loc/ru.json: ключи v2.1 ---
pl = ROOT + r"\loc\ru.json"
l = io.open(pl, encoding="utf-8").read()
if "city.champion_letter" not in l:
    keys = {
        "city.hero_fell_letter": "Герой пал. Город скорбит — старейшины молятся о странствующем чемпионе.",
        "city.champion_letter": "%s, странствующий чемпион, пришёл в город: «Слышал о вашей беде. Пока не выберете нового героя — стены держу я».",
        "city.champion_fell_toast": "Чемпион пал, прикрывая город…",
        "city.tavern_request_letter": "%s просит старосту: «Мне бы таверну — столы, песни, праздник урожая!»",
        "city.defence_rush_toast": "Староста: «Волна близко! Кузню — и стены до замыкания!»",
        "chron.hero_fell": "Герой пал — город ждёт чемпиона",
        "chron.champion_arrived": "Странствующий чемпион %s пришёл на помощь",
        "chron.champion_fell": "Чемпион города пал в волне",
        "chron.tavern_request": "%s просит старосту построить таверну",
        "chron.defence_rush": "Староста объявил оборонный рывок: кузня и стены до волны",
    }
    import re
    a2 = l.rindex("\n}")
    body = l[:a2]
    add2 = ",\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(vv, ensure_ascii=False)) for k, vv in keys.items())
    l = body + add2 + "\n}\n"
    io.open(pl, "w", encoding="utf-8", newline="\n").write(l)
    print("ru.json: v2.1 keys")
json.load(io.open(pl, encoding="utf-8"))
print("ru.json valid")
