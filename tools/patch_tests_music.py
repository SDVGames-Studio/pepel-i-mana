# -*- coding: utf-8 -*-
"""v3.1 тесты: track_for и стемы на v3-имена. Запуск: python -I tools/patch_tests_music.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "tests", "test_sfx.gd")
s = io.open(P, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"


def rep(old, new):
    global s
    old_nl = old.replace("\n", nl)
    new_nl = new.replace("\n", nl)
    assert s.count(old_nl) == 1, "count=%d: %r" % (s.count(old_nl), old[:70])
    s = s.replace(old_nl, new_nl)


rep('_check(SfxLib.track_for({"scene": "city", "festival": true}) == "mus_festival",\n'
    '\t\t\t"праздник — своя пьеса (не поверх дневной, BPM совпадает)")',
    '_check(SfxLib.track_for({"scene": "city", "festival": true}) == "mus_festival_v3",\n'
    '\t\t\t"праздник — своя пьеса v3")')
rep('_check(SfxLib.track_for({"scene": "city", "night": false}) == "mus_city_day",',
    '_check(SfxLib.track_for({"scene": "city", "night": false}) == "mus_city_day_v3",')
rep('_check(SfxLib.track_for({"scene": "city", "night": true}) == "mus_city_night",',
    '_check(SfxLib.track_for({"scene": "city", "night": true}) == "mus_city_night_v3",')
rep('_check(SfxLib.track_for({"scene": "dungeon"}) == "mus_dungeon_base",',
    '_check(SfxLib.track_for({"scene": "dungeon"}) == "mus_dungeon_base_v3",')
rep('_check(SfxLib.track_for({"scene": "dungeon", "dark_biome": true}) == "mus_dungeon_dark",',
    '_check(SfxLib.track_for({"scene": "dungeon", "dark_biome": true}) == "mus_dungeon_dark_v3",')
rep('_check(SfxLib.track_for({"scene": "dungeon", "boss": true}) == "mus_dungeon_base"\n'
    '\t\t\tand SfxLib._state_key({"scene": "dungeon", "boss": true}) == "boss",\n'
    '\t\t\t"босс рядом — слой тимпанов")',
    '_check(SfxLib.track_for({"scene": "dungeon", "boss": true}) == "mus_boss_v3"\n'
    '\t\t\tand SfxLib._state_key({"scene": "dungeon", "boss": true}) == "boss",\n'
    '\t\t\t"босс рядом — своя тема v3")')
rep('_check(SfxLib.track_for({"scene": "world"}) == "mus_world", "карта мира — рожок")',
    '_check(SfxLib.track_for({"scene": "world"}) == "mus_world_v3", "карта мира — степной переход")')
rep('	for mus in ["mus_menu", "mus_city_day", "mus_city_night", "mus_world",\n'
    '\t\t\t"mus_dungeon_base", "mus_dungeon_dark", "mus_boss_layer", "mus_victory"]:',
    '	for mus in ["mus_menu_v3", "mus_city_day_v3", "mus_city_night_v3", "mus_world_v3",\n'
    '\t\t\t"mus_dungeon_base_v3", "mus_dungeon_dark_v3", "mus_boss_v3", "mus_festival_v3",\n'
    '\t\t\t"mus_battle_v3", "mus_city_spring_v3", "mus_city_summer_v3",\n'
    '\t\t\t"mus_city_autumn_v3", "mus_city_winter_v3", "mus_boss_layer", "mus_victory"]:')
rep('_check(SfxLib.track_for({"scene": "city", "night": false}) == "mus_city_day_v3",\n'
    '\t\t\t"город днём без сезона — прежний трек (фолбэк)")',
    '_check(SfxLib.track_for({"scene": "city", "night": false}) == "mus_city_day_v3",\n'
    '\t\t\t"город днём без сезона — фолбэк v3")')
rep('_check(SfxLib.track_for({"scene": "city", "night": true}) == "mus_city_night_v3",\n'
    '\t\t\t"город ночью без сезона — прежний трек (фолбэк)")',
    '_check(SfxLib.track_for({"scene": "city", "night": true}) == "mus_city_night_v3",\n'
    '\t\t\t"город ночью без сезона — фолбэк v3")')

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ok: test_sfx на v3-имена")
