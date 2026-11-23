#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v1.89: мысли жителей + панель «Летопись жителя» + локали. Разовый патч.
import io
import json
import sys


def patch(path, old, new):
    src = io.open(path, encoding='utf-8').read()
    if old not in src:
        print('!! НЕ НАЙДЕНО в %s: %r' % (path, old[:70]))
        sys.exit(1)
    io.open(path, 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))


# ---------- 1. Мысли жителя (city_sim_residents.gd, в конец файла) ----------
sim_res = io.open('scripts/city_sim_residents.gd', encoding='utf-8').read()
if 'resident_thoughts' not in sim_res:
    sim_res += '\n\n## Мысли жителя (v1.89): 1-3 строки «о чём он думает сейчас» — из\n' \
        '## состояния (голод/хворь/рана/сон), настроения и характера: каждая черта\n' \
        '## даёт свой голос (ворчун/весельчак/лентяй/трудяга/обжора/мечтатель/стоик).\n' \
        'func resident_thoughts(r: Dictionary) -> Array:\n' \
        '\tvar out: Array = []\n' \
        '\tvar voice := "plain"\n' \
        '\tfor v in ["grumpy", "cheerful", "lazy", "hardworking", "glutton", "dreamer", "stoic"]:\n' \
        '\t\tif v in (r.get("traits", []) as Array):\n' \
        '\t\t\tvoice = String(v)\n' \
        '\t\t\tbreak\n' \
        '\tmatch String(r.get("state", "")):\n' \
        '\t\t"hungry":\n' \
        '\t\t\tout.append(Loc.t("thought.hungry." + voice))\n' \
        '\t\t"sick":\n' \
        '\t\t\tout.append(Loc.t("thought.sick." + voice))\n' \
        '\t\t"wounded":\n' \
        '\t\t\tout.append(Loc.t("thought.wounded." + voice))\n' \
        '\t\t"sleep":\n' \
        '\t\t\tout.append(Loc.t("thought.sleep." + voice))\n' \
        '\tif out.is_empty():\n' \
        '\t\tvar mood := int(r.get("mood", 50.0))\n' \
        '\t\tif mood >= 75:\n' \
        '\t\t\tout.append(Loc.t("thought.mood_high"))\n' \
        '\t\telif mood <= 25:\n' \
        '\t\t\tout.append(Loc.t("thought.mood_low"))\n' \
        '\tvar best: Dictionary = rel_best(r)\n' \
        '\tif not best.is_empty():\n' \
        '\t\tout.append(Loc.t("thought.friend") % String(best["other"]["name"]))\n' \
        '\tvar worst: Dictionary = rel_worst(r)\n' \
        '\tif not worst.is_empty():\n' \
        '\t\tout.append(Loc.t("thought.foe") % String(worst["other"]["name"]))\n' \
        '\tif String(r.get("goal", "")) != "":\n' \
        '\t\tout.append(Loc.t("thought.goal") % Loc.t("goal." + String(r["goal"])))\n' \
        '\tif out.is_empty() or (out.size() < 2 and String(r.get("state", "")) == "idle"):\n' \
        '\t\tout.append(Loc.t("thought.idle." + voice))\n' \
        '\twhile out.size() > 3:\n' \
        '\t\tout.pop_back()\n' \
        '\treturn out\n'
    io.open('scripts/city_sim_residents.gd', 'w', encoding='utf-8', newline='').write(sim_res)

# ---------- 2. Ссылки-имена в списке (city_hud.gd) ----------
patch('scripts/city_hud.gd',
      '\t\tvar parts := PackedStringArray()\n'
      '\t\tvar name_line := String(r["name"])\n'
      '\t\tif int(r.get("partner", -1)) >= 0:\n'
      '\t\t\tname_line += " [color=#f48fb1]♥[/color]"   # состоит в паре (M13)\n'
      '\t\tparts.append("[b]%s[/b]" % name_line)',
      '\t\tvar parts := PackedStringArray()\n'
      '\t\tvar name_line := String(r["name"])\n'
      '\t\tif int(r.get("partner", -1)) >= 0:\n'
      '\t\t\tname_line += " [color=#f48fb1]♥[/color]"   # состоит в паре (M13)\n'
      '\t\t# v1.89: клик по имени открывает дневник жителя (мысли + история)\n'
      '\t\tvar ruid := int(r.get("uid", -1))\n'
      '\t\tif ruid >= 0:\n'
      '\t\t\tparts.append("[url=res:%d][b]%s[/b][/url]" % [ruid, name_line])\n'
      '\t\telse:\n'
      '\t\t\tparts.append("[b]%s[/b]" % name_line)')

# ---------- 3. Панель жителя (city_hud.gd, в конец) ----------
hud = io.open('scripts/city_hud.gd', encoding='utf-8').read()
if 'open_resident' not in hud:
    hud += ('\n\n# --- Дневник жителя (v1.89): клик по имени в списке (Tab) -------------------\n'
            'var _res_detail_panel: PanelContainer = null\n'
            'var _res_detail_text: RichTextLabel = null\n\n\n'
            'func open_resident(uid: int) -> void:\n'
            '\tvar r: Dictionary = sim.resident_by_uid(uid)\n'
            '\tif r.is_empty():\n'
            '\t\treturn\n'
            '\tif _res_detail_panel == null:\n'
            '\t\t_res_detail_panel = PanelContainer.new()\n'
            '\t\t_res_detail_panel.add_theme_stylebox_override("panel", _panel_style())\n'
            '\t\t_res_detail_panel.visible = false\n'
            '\t\t_set_rect(_res_detail_panel, Vector2(250, 90), Vector2(410, 700))\n'
            '\t\tadd_child(_res_detail_panel)\n'
            '\t\tvar box := VBoxContainer.new()\n'
            '\t\t_res_detail_panel.add_child(box)\n'
            '\t\tvar head := HBoxContainer.new()\n'
            '\t\tbox.add_child(head)\n'
            '\t\tvar title := _label(20)\n'
            '\t\ttitle.text = Loc.t("city.resident_panel")\n'
            '\t\ttitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n'
            '\t\thead.add_child(title)\n'
            '\t\tvar close := _toggle_btn("×", func() -> void: close_resident())\n'
            '\t\tclose.text = "×"\n'
            '\t\thead.add_child(close)\n'
            '\t\t_res_detail_text = RichTextLabel.new()\n'
            '\t\t_res_detail_text.bbcode_enabled = true\n'
            '\t\t_res_detail_text.fit_content = true\n'
            '\t\tbox.add_child(_res_detail_text)\n'
            '\tvar b := PackedStringArray()\n'
            '\tb.append("[b][color=#ffe082]%s[/color][/b]" % String(r["name"]))\n'
            '\tif String(r["prof"]) == "":\n'
            '\t\tb.append("[color=#fff59d]%s[/color]" % Loc.t("city.state.child"))\n'
            '\telse:\n'
            '\t\tb.append(_prof_loc(String(r["prof"])))\n'
            '\tvar trait_names := PackedStringArray()\n'
            '\tfor t_id in r.get("traits", []):\n'
            '\t\ttrait_names.append(Loc.t("trait." + String(t_id)))\n'
            '\tif not trait_names.is_empty():\n'
            '\t\tb.append("[color=#9fa8da]%s[/color]" % ", ".join(trait_names))\n'
            '\tb.append("[color=#c8c8c8]%s[/color]" % Loc.t("city.state." + String(r["state"])))\n'
            '\tb.append("%s: %d%%" % [Loc.t("city.mood_label"), int(r.get("mood", 50.0))])\n'
            '\tif int(r.get("partner", -1)) >= 0:\n'
            '\t\tvar sp: Dictionary = sim._resident_by_id(int(r["partner"]))\n'
            '\t\tif not sp.is_empty():\n'
            '\t\t\tb.append("[color=#f48fb1]%s %s[/color]" % [Loc.t("city.spouse"), String(sp["name"])])\n'
            '\tif String(r.get("goal", "")) != "":\n'
            '\t\tb.append("[color=#ce93d8]%s: %s[/color]" % [Loc.t("city.goal_label"), Loc.t("goal." + String(r["goal"]))])\n'
            '\tvar best: Dictionary = sim.rel_best(r)\n'
            '\tif not best.is_empty():\n'
            '\t\tb.append("[color=#80cbc4]%s %s[/color]" % [Loc.t("city.rel_friend"), String(best["other"]["name"])])\n'
            '\tvar worst: Dictionary = sim.rel_worst(r)\n'
            '\tif not worst.is_empty():\n'
            '\t\tb.append("[color=#ef9a9a]%s %s[/color]" % [Loc.t("city.rel_foe"), String(worst["other"]["name"])])\n'
            '\tb.append("")\n'
            '\tb.append("[b][color=#ffe082]%s[/color][/b]" % Loc.t("city.thoughts"))\n'
            '\tfor th in sim.resident_thoughts(r):\n'
            '\t\tb.append("[i][color=#c5cae9]«%s»[/color][/i]" % String(th))\n'
            '\tb.append("")\n'
            '\tb.append("[b][color=#ffe082]%s[/color][/b]" % Loc.t("city.diary"))\n'
            '\tvar log: Array = r.get("log", [])\n'
            '\tfor i in range(log.size() - 1, -1, -1):\n'
            '\t\tvar e: Dictionary = log[i]\n'
            '\t\tb.append("[color=#8d8d8d][%s %d][/color] %s" % [Loc.t("city.day_word"), int(e["d"]), _dlog_text_of(e)])\n'
            '\t_res_detail_text.text = "\\n".join(b)\n'
            '\t_res_detail_panel.visible = true\n\n\n'
            'func close_resident() -> void:\n'
            '\tif _res_detail_panel != null:\n'
            '\t\t_res_detail_panel.visible = false\n\n\n'
            '## Строка дневника: ключ dlog.* + аргументы локализуются здесь.\n'
            'func _dlog_text_of(e: Dictionary) -> String:\n'
            '\tvar fmt := Loc.t(String(e["k"]))\n'
            '\tvar args: Array = []\n'
            '\tfor a in (e.get("a", []) as Array):\n'
            '\t\tvar s := String(a)\n'
            '\t\targs.append(_prof_loc(s) if String(e["k"]) in ["dlog.job", "dlog.conscript"] else s)\n'
            '\tif args.is_empty():\n'
            '\t\treturn fmt\n'
            '\treturn fmt % args\n')
    io.open('scripts/city_hud.gd', 'w', encoding='utf-8', newline='').write(hud)

# ---------- 4. meta_clicked (city_hud_build.gd) ----------
patch('scripts/city_hud_build.gd',
      '\t_residents_text = RichTextLabel.new()\n'
      '\t_residents_text.bbcode_enabled = true\n'
      '\t_residents_text.fit_content = true\n'
      '\t_residents_text.custom_minimum_size = Vector2(370, 0)\n'
      '\trp_scroll.add_child(_residents_text)',
      '\t_residents_text = RichTextLabel.new()\n'
      '\t_residents_text.bbcode_enabled = true\n'
      '\t_residents_text.fit_content = true\n'
      '\t_residents_text.custom_minimum_size = Vector2(370, 0)\n'
      '\t_residents_text.meta_clicked.connect(func(meta: Variant) -> void:\n'
      '\t\tvar m := String(meta)\n'
      '\t\tif m.begins_with("res:"):\n'
      '\t\t\topen_resident(int(m.substr(4))))\n'
      '\trp_scroll.add_child(_residents_text)')

# ---------- 5. Локали ----------
p = 'loc/ru.json'
L = json.load(open(p, encoding='utf-8'))
L['city.resident_panel'] = 'Летопись жителя'
L['city.thoughts'] = 'Мысли сейчас'
L['city.diary'] = 'Дневник'
L['city.mood_label'] = 'Настроение'
L['city.goal_label'] = 'Цель'
L['city.spouse'] = 'В паре с'
L['city.day_word'] = 'День'
voices = {
    'plain': {
        'hungry': 'В брюхе пусто, хоть свисти. Надо бы поесть...',
        'sick': 'Кости ломит, голова тяжёлая. Не до работы...',
        'wounded': 'Рана ноет. Побуду в сторонке, пока затянется.',
        'sleep': 'Спится... пусть мир подождёт.',
        'idle': 'Тихий день. И слава богу.'},
    'grumpy': {
        'hungry': 'Опять еды нет! Все вокруг сыты, один я голодный.',
        'sick': 'Ну конечно, заболел. Как всегда, в самое тяжёлое время.',
        'wounded': 'Видите эту рану? Терпи теперь, как терпеть умею.',
        'sleep': 'Хоть посплю, пока никто с глупостями не лезет.',
        'idle': 'Скучно. Эту стройку потом сами же и расхлёбывать.'},
    'cheerful': {
        'hungry': 'Живот бурчит, а на душе весело — скоро поедим!',
        'sick': 'И это пройдёт. Отлежусь — и снова в строй!',
        'wounded': 'Эх, шрамы украшают! Заживёт — расскажу всем, как было.',
        'sleep': 'Сны сегодня будут добрые, чувствую.',
        'idle': 'Хорошо-то как! Птицы поют, люди хлопочут — жизнь!'},
    'lazy': {
        'hungry': 'До стола дойти бы... но и это слишком движений.',
        'sick': 'Болеть — уважительная причина полежать. Наконец-то.',
        'wounded': 'Рана? Значит, лежать можно честно. Я не против.',
        'sleep': 'Моё любимое занятие. Не будите.',
        'idle': 'Ничего не делать — это тоже работа, и я её люблю.'},
    'hardworking': {
        'hungry': 'Поесть бы — и снова в поле, дела не ждут.',
        'sick': 'Кто же работу доделает, если я лежу?..',
        'wounded': 'Руки чешутся работать, а приходится отлёживать.',
        'sleep': 'Утром — сразу за дело, план готов.',
        'idle': 'Стою без дела — словно день впустую ушёл.'},
    'glutton': {
        'hungry': 'Пустой желудок — это трагедия! Где моя похлёбка?!',
        'sick': 'Даже в хворь думаю о еде. Отлежусь с куском пирога.',
        'wounded': 'Еда — лучшее лекарство, говорю вам!',
        'sleep': 'И во сне ем. Хорошо.',
        'idle': 'Размышляю... о еде. В основном о еде.'},
    'dreamer': {
        'hungry': 'Голод — лишь испытание. Я стану мудрее...',
        'sick': 'В лихорадке снятся чудесные вещи. Может, и не болеть?',
        'wounded': 'Рана — это история. Однажды я её запишу.',
        'sleep': 'Утром проснусь другим человеком. Лучшим.',
        'idle': 'Смотрю на облака и думаю: а что там, за холмами?'},
    'stoic': {
        'hungry': 'Голод переносим. Есть дела важнее.',
        'sick': 'Хворь пройдёт. Стенаю лишь слабые.',
        'wounded': 'Больно. Терплю.',
        'sleep': 'Отдых — часть работы.',
        'idle': 'Спокойствие. Всё идёт, как идёт.'},
}
for v, d in voices.items():
    for k, s in d.items():
        L['thought.%s.%s' % (k, v)] = s
L['thought.mood_high'] = 'На душе светло — город растёт, и я с ним.'
L['thought.mood_low'] = 'Всё валится из рук... тоскливо на сердце.'
L['thought.friend'] = 'С %s у нас лад — хорошо, когда есть кто-то за спиной.'
L['thought.foe'] = 'Только бы %s не путался под ногами...'
L['thought.goal'] = 'Держу в голове своё: %s.'
dlogs = {
    'dlog.came': 'Пришёл в город с переселенцами.',
    'dlog.born': 'Родился в городе.',
    'dlog.child_born': 'У нас родился ребёнок — %s.',
    'dlog.married': 'Обвенчался с %s.',
    'dlog.job': 'Взрослея, выбрал дело: %s.',
    'dlog.conscript': 'Мобилизован: теперь %s.',
    'dlog.rank3': 'Слыву умельцем — опыта набрался.',
    'dlog.rank5': 'Стал мастером своего дела!',
    'dlog.sick': 'Заболел. Лежу.',
    'dlog.wounded': 'Ранен. Отлёживаюсь.',
    'dlog.lost': 'Не стало близкого — %s. Горюю.',
}
for k, s in dlogs.items():
    L[k] = s
io.open(p, 'w', encoding='utf-8', newline='\n').write(json.dumps(L, ensure_ascii=False, indent='\t'))
print('HUD + мысли + локали ок; всего ключей:', len(L))
