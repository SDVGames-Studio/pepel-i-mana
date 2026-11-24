# -*- coding: utf-8 -*-
## v2.2 патч 6: данные — 30-е здание grace_altar, cfg-блоки, враг
## wander_hunter (спрайт бандита-лучника), ключи локализации.
import io, json, sys

ROOT = r"F:\Z2\.zcode\workspace\default\pepel-i-mana"

# --- city.json: здание после altar, cfg после mold ---
pc = ROOT + r"\data\city.json"
c = io.open(pc, encoding="utf-8").read()
if "grace_altar" in c:
    print("city.json: already patched")
else:
    a_altar = '''			"worker": "acolyte",
			"effect": "altar",
			"district": "work",
			"cat": "magic"
		},
'''
    assert a_altar in c, "city.json: altar block anchor missing"
    r_altar = a_altar + '''		{
			"id": "grace_altar",
			"w": 2,
			"sprite": "b:altar",
			"short": "bld.short.grace_altar",
			"loc": "bld.grace_altar",
			"desc": "bld.desc.grace_altar",
			"color": "#b39ddb",
			"cost": {
				"stone": 14,
				"crystal": 4
			},
			"build_work": 45,
			"worker": "acolyte",
			"effect": "grace_altar",
			"district": "work",
			"cat": "magic",
			"_comment": "v2.2: алтарь благодати — призывает духа-работника (стройка/добыча); эффективность от мастерства аколита 50-120%; минус: фонит магическим загрязнением -> серая плесень"
		},
'''
    c = c.replace(a_altar, r_altar, 1)
    a_mold = '''	"mold": {
		"start_pollution": 25.0,
		"max_tiles": 45,
		"spread_chance": 0.1,
		"_note": "v1.84: серая плесень — заражает землю (травяные тайлы), расползается от загрязнения, плодит тварей; лечится магией героя (E, 10 маны)"
	}
}'''
    assert a_mold in c, "city.json: mold block anchor missing"
    r_mold = '''	"mold": {
		"start_pollution": 25.0,
		"max_tiles": 45,
		"spread_chance": 0.1,
		"_note": "v1.84: серая плесень — заражает землю (травяные тайлы), расползается от загрязнения, плодит тварей; лечится магией героя (E, 10 маны)"
	},
	"tracks": {
		"life_days": 1.2,
		"min_step": 24.0,
		"cap": 1200,
		"hunter_sense": 220.0,
		"_note": "v2.2 п.3: следы всех ходячих на карте города; тают по времени, дождь ускоряет (CityTracks.RAIN_MULT)"
	},
	"grace_altar": {
		"pollution_per_day": 1.5,
		"skill_max": 20.0,
		"skill_per_day": 1.0,
		"eff_min": 0.5,
		"eff_span": 0.7,
		"respawn_days": 3,
		"speed": 70.0,
		"_note": "v2.2 п.2: алтарь благодати — дух-работник (стройка/добыча), эффективность 0.5..1.2 от мастерства аколита; фонит загрязнением -> плесень"
	},
	"camps": {
		"enabled": true,
		"start_day": 8,
		"gap_days": 7,
		"chance": 0.35,
		"crime_every_days": 3,
		"steal_food": 5.0,
		"steal_coins": 4.0,
		"sermon_mood": 3.0,
		"guards_needed": 2,
		"guards_win": 0.75,
		"hero_power": 3,
		"camp_power": 4,
		"loot_food": 8.0,
		"loot_coins": 15,
		"truce_days": 12,
		"_note": "v2.2 п.4: тайные лагеря бандитов/сектантов — скрытая POI, кражи/проповеди; найдут по следам и уликам, разгром — герой или стража"
	},
	"hunt_squad": {
		"enabled": true,
		"chance": 0.25,
		"gap_days": 5,
		"travel_days": 1,
		"members": 3,
		"_note": "v2.2 п.1: странствующие охотники на чудовищ — после отбонной волны с шансом идут на логово сами, городу доля добычи"
	}
}'''
    c = c.replace(a_mold, r_mold, 1)
    io.open(pc, "w", encoding="utf-8", newline="\n").write(c)
    print("city.json: grace_altar + cfg blocks")

# --- enemies.json: wander_hunter (человечий спрайт, в волны не попадает —
#     веса в threat.enemy_weights у него нет) ---
pe = ROOT + r"\data\enemies.json"
e = io.open(pe, encoding="utf-8").read()
if "wander_hunter" in e:
    print("enemies.json: already patched")
else:
    a = '\t\t"_comment": "виндиго: лесной людоед-дух, страшится света"\n\t}\n]'
    assert a in e, "enemies.json: tail anchor missing"
    r = '''\t\t"_comment": "виндиго: лесной людоед-дух, страшится света"
\t},
\t{
\t\t"id": "wander_hunter",
\t\t"loc": "enemy.wander_hunter",
\t\t"hp": 10,
\t\t"damage": 3,
\t\t"speed": 80,
\t\t"aggro": 140,
\t\t"attack_range": 22,
\t\t"attack_cooldown": 1.0,
\t\t"radius": 9,
\t\t"color": "#8d6e63",
\t\t"sprite": "e:bandit_archer",
\t\t"xp": 0,
\t\t"_comment": "v2.2 п.1: странствующий охотник на чудовищ (союзный отряд, role hunt_ally); в волны не попадает — нет веса в threat.enemy_weights"
\t}
]'''
    e = e.replace(a, r, 1)
    io.open(pe, "w", encoding="utf-8", newline="\n").write(e)
    print("enemies.json: wander_hunter")

# --- loc/ru.json: ключи v2.2 ---
pl = ROOT + r"\loc\ru.json"
l = io.open(pl, encoding="utf-8").read()
if "bld.grace_altar" in l:
    print("ru.json: already patched")
else:
    a = '\t"city.harvest_feast": "Праздник урожая!"\n}'
    assert a in l, "ru.json: tail anchor missing"
    keys = {
        "bld.grace_altar": "Алтарь благодати",
        "bld.short.grace_altar": "Алтарь",
        "bld.desc.grace_altar": "Призывает духа благодати — неутомимого работника (стройка или добыча). Сила духа зависит от мастерства аколита-контролёра (50–120% работника). Минус: алтарь фонит магическим загрязнением — землю тянет серой плесенью.",
        "enemy.wander_hunter": "Странствующий охотник",
        "city.spirit_summoned": "Алтарь благодати призвал духа-работника",
        "city.spirit_died": "Дух благодати пал в волне — алтарь перезовёт его",
        "city.track_hint": "Следы ведут: %s",
        "city.track_follow": "Идти по следу",
        "city.camp_found_toast": "Найден тайный лагерь в окрестностях!",
        "city.camp_razed_toast": "Тайный лагерь разгромлен!",
        "city.camp_none": "Лагеря не найдено",
        "city.camp_not_found": "Сначала найдите лагерь — по следам или уликам",
        "city.camp_need_guards": "Нужно хотя бы 2 стражи на ногах",
        "city.camp_assault_fail": "Штурм отбит — лагерь держится",
        "city.camp_choice_hero": "Штурмовать (герой)",
        "city.camp_choice_guards": "Отправить стражу",
        "city.camp_title": "Тайный лагерь",
        "city.camp_found_line": "Здесь прятались %s. Пора покончить с этим.",
        "city.spy_interrogate": "Допросить путника",
        "city.spy_suspicion_line": "Этот путник приходит слишком часто. И каждый раз после его визитов склад беднее.",
        "city.spy_alibi": "Путник отшучивается: «Я простой странник, кормлюсь торгом».",
        "city.spy_confess": "Под давлением путник выдаёт лагерь в предместье!",
        "city.spy_fled": "Путник побледнел и бросился бежать!",
        "city.spy_choice_press": "Допрашивать жёстче",
        "city.spy_choice_release": "Отпустить",
        "city.altar_title": "Алтарь благодати",
        "city.altar_eff_line": "Дух работает с силою %d%%.",
        "city.altar_hp_line": "Сила духа: %d/%d.",
        "city.altar_choice_build": "На стройку",
        "city.altar_choice_gather": "На добычу",
        "city.altar_choice_idle": "Ко алтарю (отдых)",
        "city.altar_no_work": "Духу не нашлось дела — пусть пока парит ко алтарю.",
        "city.hunt_report_toast": "Охотник: свежие следы мутантов ведут на %s!",
        "city.hunt_squad_come": "К городу идут странствующие охотники на чудовищ!",
        "city.hunt_squad_here": "Охотники прибыли и идут на логово мутантов!",
        "city.hunt_squad_win": "Охотники разорили логово! Городу — доля добычи.",
        "city.warehouse_theft": "Кража со склада! Пропало еды: %d",
        "city.sect_sermon": "Ночью в предместье слышали сектантские проповеди…",
        "chron.hive_knows": "Логово нашло город — волны теперь идут в цель",
        "chron.hive_alert_fuzzy": "Ищейка мутантов учуяла опасность и бежала в логово",
        "chron.hunt_report": "Охотник докладывает: следы на %s",
        "chron.theft": "Кража со склада: %s еды",
        "chron.sermon": "Сектантская проповедь в предместье",
        "chron.camp_found": "Найден тайный лагерь (%s)",
        "chron.camp_razed": "Тайный лагерь разгромлен (%s)",
        "chron.hunt_squad_come": "Идут странствующие охотники на чудовищ",
        "chron.hunt_squad_here": "Охотники вышли на логово",
        "chron.hunt_squad_win": "Охотники разорили логово — городу доля добычи",
        "chron.spirit_died": "Дух благодати пал в волне",
        "chron.spirit_summoned": "Алтарь призвал духа благодати",
        "camp.kind.bandit": "бандиты",
        "camp.kind.sect": "сектанты",
        "diary.spy_seen": "Опять этот путник… и снова склад пуст. Что-то тут не так.",
        "dlog.spy_seen": "Этот путник заходит слишком часто. И пропажи — каждый раз после него.",
        "city.spirit_draw": "дух",
    }
    parts = []
    for k, v in keys.items():
        parts.append('\t"%s": %s' % (k, json.dumps(v, ensure_ascii=False)))
    r = a[:-2] + ",\n" + ",\n".join(parts) + "\n}"
    l = l.replace(a, r, 1)
    io.open(pl, "w", encoding="utf-8", newline="\n").write(l)
    print("ru.json: v2.2 keys")

# валидация JSON
for p in (pc, pe, pl):
    json.load(io.open(p, encoding="utf-8"))
print("JSON valid")
