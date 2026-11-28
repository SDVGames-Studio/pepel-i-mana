# -*- coding: utf-8 -*-
"""v3.1.0: версия, README, CHANGELOG. Запуск: python -I tools/patch_v310_docs.py
"""
import io
import json
import os

GAME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

p = os.path.join(GAME, "data", "version.json")
d = json.load(io.open(p, encoding="utf-8"))
d["version"] = "3.1.0"
io.open(p, "w", encoding="utf-8", newline="").write(
    json.dumps(d, ensure_ascii=False, indent=2) + chr(10))

p = os.path.join(GAME, "README.md")
s = io.open(p, encoding="utf-8", newline="").read()
s = s.replace("# Пепел и Благодать — v3.0.9", "# Пепел и Благодать — v3.1.0")
io.open(p, "w", encoding="utf-8", newline="").write(s)

p = os.path.join(GAME, "CHANGELOG_E2.md")
s2 = io.open(p, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s2 else "\n"
anchor = "## v3.0.7 — «Натуральные струны» (2026-11-28)"
L = [
    "## v3.1.0 — «Вся музыка и все звуки» (2026-11-28)",
    "",
    "Приказ: «делай дальше всю музыку. и звуки».",
    "",
    "- **+7 треков KS-движком** (13 всего): мир «степной переход» (шаг баса",
    "  на полутакт), данж (ре-минор низко, било-намёк), тёмный данж",
    "  (ля-фригийский, глухой), босс (132 BPM, ми-гармонический, Б-мажор —",
    "  угроза, било-акценты), праздник (100 BPM танец: бас сильные, струны",
    "  слабые, мажорный риф), город ночь/день (фолбэки);",
    "- **Все 44 SFX перегенерированы** (tools/make_sfx_v3.py, натуральный",
    "  синтез): удары/урон/гибель — мембрана с двумя модами + трещоты;",
    "  coin/pickup/quest/wedding/birth/fanfare/rune/spells — KS-колокольчики",
    "  и арпеджио; bell_day — било; build_done/chop/hammer/mine — дерево/",
    "  металл/камень (KS-кнока + трещота); шаги (трава/дорога/камень/вода),",
    "  rustles, swing, tree_fall — шум-текстуры с правильными спадами;",
    "  boss_roar — низкий рёв. Имена файлов прежние — манифест SFX не менялся;",
    "- **Манифест**: все состояния на v3-треки, старые слои сняты",
    "  (world/dungeon/boss/festival/night/day); test_sfx/test_v304 переведены.",
    "",
]
block = nl.join(L) + nl
assert anchor in s2
s2 = s2.replace(anchor, block + anchor, 1)
io.open(p, "w", encoding="utf-8", newline="").write(s2)
print("ok: v3.1.0 — версия, README, CHANGELOG")
