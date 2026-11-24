# -*- coding: utf-8 -*-
## v2.0 «Проводка задела»: раскладка нарезанного wave1123 в env/.
## Деревья B (16) + пни B (8) + брёвна B (8); лесные существа: кадры
## 21-56 (волк/лиса/заяц/ворон/рыба/жаба) — 01-20 (медведь/лось/виндиго)
## уже проводил wire_wave24.py.
import json, os, shutil

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "assets", "sprites", "wave1123")
ENV = os.path.join(ROOT, "assets", "sprites", "env")


def save(src, name):
    shutil.copyfile(os.path.join(SRC, src), os.path.join(ENV, name + ".png"))
    print("env/%s.png" % name)


# --- деревья B: 16 стволов ---
TREES = [
    (1, "tree3_spruce"), (2, "tree3_birch"), (3, "tree3_oak"), (4, "tree3_snag"),
    (5, "tree3_willow"), (6, "tree3_apple_bloom"), (7, "tree3_maple_orange"),
    (8, "tree3_dead"), (9, "tree3_spruce_snow"), (10, "tree3_birch_autumn"),
    (11, "tree3_oak_dark"), (12, "tree3_snag_knotty"), (13, "tree3_willow_autumn"),
    (14, "tree3_sakura"), (15, "tree3_maple_red"), (16, "tree3_dead_snow"),
]
for n, name in TREES:
    save("trees_logs_b/%02d.png" % n, name)

# --- пни B: 8 ---
STUMPS = [
    (17, "stump3_wide"), (18, "stump3_mossy"), (19, "stump3_old"), (20, "stump3_split"),
    (21, "stump3_knotty"), (22, "stump3_snow"), (23, "stump3_mushrooms"), (24, "stump3_snow2"),
]
for n, name in STUMPS:
    save("trees_logs_b/%02d.png" % n, name)

# --- брёвна B: 8 ---
LOGS = [
    (25, "log3_mossy"), (26, "log3_branch"), (27, "log3_leafy"), (28, "log3_birch"),
    (29, "log3_bough"), (30, "log3_birch_branch"), (31, "log3_stack"), (32, "log3_snow"),
]
for n, name in LOGS:
    save("trees_logs_b/%02d.png" % n, name)

# --- лесные существа: кадры 21-56 (варианты B в пулы faun'ы) ---
CREATURES = [
    ("an_wolf_b", 21, 26, 6),   # волк 21-26
    ("an_fox_b", 27, 32, 6),    # лиса 27-32
    ("an_hare_b", 33, 38, 6),   # заяц 33-38
    ("an_bird_b", 39, 44, 6),   # ворон 39-44
    ("an_fish_b", 45, 55, 6),   # рыба 45,47,...,55
    ("an_toad_b", 46, 56, 6),   # жаба 46,48,...,56
]
for name, off, end, n in CREATURES:
    for i in range(n):
        num = off + i * (2 if name in ("an_fish_b", "an_toad_b") else 1)
        if num > end:
            break
        save("forest_creatures/%02d.png" % num, "%s_%d" % (name, i + 1))

# --- семантические манифесты ---
# лут: номер -> id предмета из items.json (сверено по контакт-листу)
LOOT_MAP = {
    "01": "rusty_blade", "02": "iron_sword", "03": "knight_sword", "04": "rune_blade",
    "05": "dragon_blade", "06": "woodsman_axe", "07": "reaper_axe", "08": "hunting_spear",
    "09": "drake_spear", "10": "hunter_bow", "11": "wind_bow", "12": "apprentice_staff",
    "13": "storm_staff", "14": "padded_vest", "15": "hunter_coat", "16": "chainmail",
    "17": "dragon_plate", "18": "shadow_cloak", "19": "phoenix_feather", "20": "wolf_fang",
    "21": "iron_ring", "22": "mana_pendant", "23": "bear_totem", "24": "crystal_amulet",
    "25": "eye_of_ash", "26": "scroll_fire", "27": "scroll_bolt", "28": "scroll_heal",
    "29": "scroll_shield", "30": "scroll_roots", "31": "scroll_stone", "32": "potion_heal",
}
mp = os.path.join(SRC, "loot_items", "manifest.json")
m = json.load(open(mp, encoding="utf-8"))
for it in m.get("items", []):
    num = os.path.splitext(String(it["file"]) if False else it["file"])[0]
    it["item"] = LOOT_MAP.get(num, "")
m["by_item"] = {v: k + ".png" for k, v in LOOT_MAP.items()}
m["note"] = "v2.0 ЛУТ-1: item — id предмета из data/items.json (сверка по контакт-листу 2026-11-24)"
json.dump(m, open(mp, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
print("loot manifest: 32 item ids")

tb = os.path.join(SRC, "trees_logs_b", "manifest.json")
tm = json.load(open(tb, encoding="utf-8"))
names = [x[1] for x in TREES] + [x[1] for x in STUMPS] + [x[1] for x in LOGS]
for it, nm in zip(tm.get("items", []), names):
    it["name"] = nm
tm["note"] = "v2.0: деревья/пни/брёвна пакета B — имена env-спрайтов"
json.dump(tm, open(tb, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
print("trees_logs_b manifest: names")

fc = os.path.join(SRC, "forest_creatures", "manifest.json")
fm = json.load(open(fc, encoding="utf-8"))
blocks = [("bear", 1, 7), ("elk", 8, 7), ("wendigo", 15, 6), ("wolf", 21, 6),
          ("fox", 27, 6), ("hare", 33, 6), ("bird", 39, 6)]
for it in fm.get("items", []):
    num = int(os.path.splitext(it["file"])[0])
    nm = ""
    for kind, off, n in blocks:
        if off <= num < off + n:
            nm = "%s_%d" % (kind, num - off + 1)
            break
    else:
        nm = ("fish_%d" % ((num - 45) // 2 + 1)) if num % 2 == 1 else ("toad_%d" % ((num - 46) // 2 + 1))
    it["name"] = nm
fm["note"] = "v2.0: кадры существ — вид_№ (1-20 проводил wire_wave24: an_bear/an_elk/wendigo)"
json.dump(fm, open(fc, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
print("forest_creatures manifest: names")
