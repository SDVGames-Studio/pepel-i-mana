#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v1.98.0: версия + доки (догоняет коммит f051046).
import io
import json

v = json.load(open('data/version.json', encoding='utf-8'))
v['version'] = '1.98.0'
json.dump(v, open('data/version.json', 'w', encoding='utf-8'), indent='\t', ensure_ascii=False)
open('data/version.json', 'a', encoding='utf-8').write('\n')

p = 'CHANGELOG_E2.md'
s = io.open(p, encoding='utf-8').read()
a = '> По разделам удобно искать: `grep -n "^## " CHANGELOG_E2.md`.\n'
e = '''
## v1.98.0 — квесты: NPC в центре, заказы сбоку с «!» (ждёт приёмки)

Фидбек приёмки v1.97.1: «задание от NPC — по центру; пришедшее/
случайное — сбоку как событие; журнал заданий?»

- разговор с NPC (староста и др.) — выбор-диалог ВЕРНУТ ПО ЦЕНТРУ
  (v1.97.1 уводил вправо — неправильно);
- заказ с доски объявлений (sim.quests): при появлении — событие
  quest_new → сообщение-происшествие с «!» («Новое задание от %s —
  детали в журнале (клавиша Q)»);
- ЖУРНАЛ ЗАДАНИЙ УЖЕ ЕСТЬ: клавиша Q — доска объявлений (взять/
  сдать), заказы от жителей с наградой;
- тесты зелёные.
'''
assert a in s
io.open(p, 'w', encoding='utf-8', newline='').write(s.replace(a, a + e, 1))

p2 = 'СЛЕДУЮЩИЙ-ШАГ.md'
s2 = io.open(p2, encoding='utf-8').read()
old = 'волны 1.80-1.96; СЛЕДУЮЩАЯ = v1.97 HUD-компакт, СПРОЕКТИРОВАНА)'
new = 'волны 1.80-1.98; v1.97-1.98 HUD и квест-уведомления — ждёт приёмки)'
if old in s2:
    s2 = s2.replace(old, new, 1)
else:
    print('!! реле-якорь не найден — проверить вручную')
io.open(p2, 'w', encoding='utf-8', newline='').write(s2)
print('docs v1.98.0 ok')
