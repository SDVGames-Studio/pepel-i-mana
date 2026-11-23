#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v1.94: тайные роли — вор и демонолог. Прячут мысли, прокалываются,
# раскрытие после 3 улик в дневнике. Разовый патч.
import io
import json
import sys


def patch(path, old, new):
    src = io.open(path, encoding='utf-8').read()
    if old not in src:
        print('!! НЕ НАЙДЕНО в %s: %r' % (path, old[:70]))
        sys.exit(1)
    io.open(path, 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))


# починка сломанной строки
patch('scripts/city_sim_residents.gd',
      '\tif s == "necromancer":\n'
      '\t\treturn not bool(sim necro_known) if false else not necro_known\n'
      '\treturn true',
      '\tif s == "necromancer":\n'
      '\t\treturn not necro_known   # некромант скрыт до городового раскрытия\n'
      '\treturn true')

# ---------- проколы и раскрытие: в _daily_notes (tick.gd) ----------
patch('scripts/city_sim_tick.gd',
      'func _daily_notes() -> void:\n'
      '\tif int(day) % 5 != 0:\n'
      '\t\treturn\n'
      '\tvar s := String(season())\n'
      '\tfor r in residents:\n'
      '\t\tif bool(r.get("golem", false)):\n'
      '\t\t\tcontinue\n'
      '\t\tres_log(r, "dlog.note", [s])',
      'func _daily_notes() -> void:\n'
      '\tif int(day) % 5 != 0:\n'
      '\t\treturn\n'
      '\tvar s := String(season())\n'
      '\tfor r in residents:\n'
      '\t\tif bool(r.get("golem", false)):\n'
      '\t\t\tcontinue\n'
      '\t\tres_log(r, "dlog.note", [s])\n'
      '\t\t# v1.94: тайный житель изредка ПРОКАЛЫВАЕТСЯ — улика в дневнике\n'
      '\t\tvar sec := String(r.get("secret", ""))\n'
      '\t\tif sec != "" and not bool(r.get("secret_revealed", false)) \\\n'
      '\t\t\t\tand sec != "necromancer" and _event_rng.randf() < 0.12:\n'
      '\t\t\tres_log(r, "dlog.slip", [sec])\n'
      '\t\t\tif _secret_slips(r) >= 3:\n'
      '\t\t\t\tr["secret_revealed"] = true\n'
      '\t\t\t\t_chron("chron.secret_out", String(r["name"]), "secret." + sec)\n'
      '\t\t\t\tevents.append({"type": "secret_out", "name": String(r["name"]),\n'
      '\t\t\t\t\t"role": sec})\n\n\n'
      '## Сколько улик-проколов в дневнике тайного жителя (v1.94).\n'
      'func _secret_slips(r: Dictionary) -> int:\n'
      '\tvar n := 0\n'
      '\tfor e in (r.get("log", []) as Array):\n'
      '\t\tif String(e["k"]) == "dlog.slip":\n'
      '\t\t\tn += 1\n'
      '\treturn n')

# ---------- HUD: скрытый пишет телеграфом (сухо), раскрытый — правду ----------
patch('scripts/city_hud_base.gd',
      '\tvar base := String(e["k"]).substr(5)\n'
      '\tvar goal_id := ""',
      '\tvar base := String(e["k"]).substr(5)\n'
      '\tif String(e["k"]) == "dlog.slip":\n'
      '\t\tvar srole := String((e.get("a", []) as Array)[0])\n'
      '\t\treturn Loc.t("diary.slip." + srole)\n'
      '\t# v1.94: нераскрытый тайный житель пишет СУХО (нейтральный стиль) —\n'
      '\t# это само по себе улика внимательному читателю\n'
      '\tif _secret_hidden_public(r):\n'
      '\t\treturn _dlog_text_of(e)\n'
      '\tvar goal_id := ""')
patch('scripts/city_hud_base.gd',
      '## Строка дневника: ключ dlog.* + аргументы локализуются здесь.',
      '## Тайный житель нераскрыт? (HUD не знает внутренностей сима —\n'
      '## дублируем простое правило по данным жителя и флагам сима.)\n'
      'func _secret_hidden_public(r: Dictionary) -> bool:\n'
      '\tvar s := String(r.get("secret", ""))\n'
      '\tif s == "" or bool(r.get("secret_revealed", false)):\n'
      '\t\treturn false\n'
      '\tif s == "necromancer":\n'
      '\t\treturn not bool(sim.necro_known)\n'
      '\treturn true\n\n\n'
      '## Строка дневника: ключ dlog.* + аргументы локализуются здесь.')

# мысли тоже через публичную маску (в residents Thoughts уже смотрит
# _secret_hidden из сима — ок), тег в списке:
patch('scripts/city_hud.gd',
      '\t\t\tif String(r.get("secret", "")) == "necromancer" and bool(sim.necro_known):\n'
      '\t\t\t\tprof_text += " [color=#ba68c8](%s)[/color]" % Loc.t("city.necro_tag")',
      '\t\t\tif String(r.get("secret", "")) == "necromancer" and bool(sim.necro_known):\n'
      '\t\t\t\tprof_text += " [color=#ba68c8](%s)[/color]" % Loc.t("city.necro_tag")\n'
      '\t\t\telif String(r.get("secret", "")) != "" and bool(r.get("secret_revealed", false)):\n'
      '\t\t\t\tprof_text += " [color=#ba68c8](%s)[/color]" % Loc.t("secret." + String(r["secret"]))')

# ---------- локали ----------
p = 'loc/ru.json'
L = json.load(open(p, encoding='utf-8'))
L['thought.masked.1'] = 'Ничего особенного. Обычный день.'
L['thought.masked.2'] = 'Всё как всегда. Не смотри так.'
L['thought.masked.3'] = 'Мысли? Какие мысли. Я просто работаю.'
L['thought.slip.thief'] = 'Что за шёпот у склада ночью?.. Неважно. Забудь.'
L['thought.slip.demonologist'] = 'Мел на полу, свеча догорела... это не моё. Уже не моё.'
L['diary.slip.thief'] = 'Ночью опять не спал. Куда-то выходил... Чего смотрите? Ключи чужие — нашёл.'
L['diary.slip.demonologist'] = 'Руки в саже, на полу круг мелом. С утра всё замыл и молчу.'
L['secret.thief'] = 'вор'
L['secret.demonologist'] = 'демонолог'
L['chron.secret_out'] = 'Город раскрыл %s: оказывается, %s!'
io.open(p, 'w', encoding='utf-8', newline='\n').write(json.dumps(L, ensure_ascii=False, indent='\t'))
print('секреты v1.94 ок; ключей:', len(L))
