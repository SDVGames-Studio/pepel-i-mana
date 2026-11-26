# -*- coding: utf-8 -*-
"""v3.0.0 «Масштаб и стройка» (приказ заказчика 26.11, «повторял много раз»):
- стройка НЕ на деревьях и НЕ на клетках зон (поля/пастбища неприкосновенны);
- ферма старосты — по максимальному выхлопу (свободная земля под грядки);
- масштаб: жители 27->34, герой 32->40, полотно земли мельче (÷3 -> ÷6);
- площадь постройки: здания w2 -> w3 (стены/ворота/шатёр/мост/башня — нет).
Запуск: python -I tools/patch_v300_build.py
"""
import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)


def read(p):
    with io.open(p, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(p, s):
    with io.open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)
    assert len(read(p)) > 0


def patch(p, old, new):
    s = read(p)
    nl = "\r\n" if "\r\n" in s else "\n"
    old_nl = old.replace("\n", nl)
    new_nl = new.replace("\n", nl)
    assert old_nl in s, "якорь не найден в %s: %r" % (p, old[:60])
    assert s.count(old_nl) == 1, "якорь неуникален в %s" % p
    write(p, s.replace(old_nl, new_nl))
    print("ok:", os.path.relpath(p, GAME))


# 1) стройка: не на деревьях, не на зонах
P = os.path.join(GAME, "scripts", "city_sim_build.gd")
patch(P,
      '\t# главная площадь (правки v1.20): в радиусе plaza.radius клеток строить нельзя\n'
      '\tif type_id != "bridge" and near_plaza(tile):\n'
      '\t\treturn false\n'
      '\tif not map.is_nature_walkable(tile):',
      '\t# главная площадь (правки v1.20): в радиусе plaza.radius клеток строить нельзя\n'
      '\tif type_id != "bridge" and near_plaza(tile):\n'
      '\t\treturn false\n'
      '\t# v3.0 (заказчик): НЕ строим в лесу (прямо на деревьях) и на клетках\n'
      '\t# зон — поля/пастбища неприкосновенны, ферма не встанет на чужие грядки\n'
      '\tif type_id != "bridge" and map.grid[tile.y][tile.x] == map.TILE_TREE:\n'
      '\t\treturn false\n'
      '\tif _tile_in_zone(tile):\n'
      '\t\treturn false\n'
      '\tif not map.is_nature_walkable(tile):')

# 2) староста: ферма по максимальному выхлопу
P = os.path.join(GAME, "scripts", "city_sim_gov_plan.gd")
patch(P,
      '\t\t\tif col_d >= best_d:',
      '\t\t\t# v3.0: ферма сканирует ВСЁ (счёт по свободной земле, не по дистанции)\n'
      '\t\t\tif col_d >= best_d and type_id != "farm":')
patch(P,
      '\t\t\tif not ok:\n'
      '\t\t\t\tcontinue\n'
      '\t\t\tbest = t\n'
      '\t\t\tbest_d = col_d',
      '\t\t\tif not ok:\n'
      '\t\t\t\tcontinue\n'
      '\t\t\t# v3.0 (заказчик): ферма — по максимальному выхлопу: вокруг площадки\n'
      '\t\t\t# нужна свободная земля под грядки; минимум и радиус — в city.json\n'
      '\t\t\t# (farming.min_farmland / farming.field_radius)\n'
      '\t\t\tif type_id == "farm":\n'
      '\t\t\t\tvar sc: int = _free_farmland(t, w)\n'
      '\t\t\t\tif sc < int(cfg.get("farming", {}).get("min_farmland", 8)):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t\tif sc > int(c.get("best_sc", -1)) or (sc == int(c.get("best_sc", -1)) and col_d < best_d):\n'
      '\t\t\t\t\tc["best_sc"] = sc\n'
      '\t\t\t\t\tbest = t\n'
      '\t\t\t\t\tbest_d = col_d\n'
      '\t\t\t\tcontinue\n'
      '\t\t\tbest = t\n'
      '\t\t\tbest_d = col_d')
patch(P,
      'func _advance_gather_scan(c: Dictionary, budget: int) -> void:',
      '## v3.0: свободных клеток под грядки вокруг прямоугольника w×w\n'
      '## (годна: трава без дерева, без здания, без зоны).\n'
      'func _free_farmland(t: Vector2i, w: int) -> int:\n'
      '\tvar n := 0\n'
      '\tvar r := int(cfg.get("farming", {}).get("field_radius", 3))\n'
      '\tfor dy in range(-r, w + r):\n'
      '\t\tfor dx in range(-r, w + r):\n'
      '\t\t\tvar ct := t + Vector2i(dx, dy)\n'
      '\t\t\tif map.in_bounds(ct) and map.grid[ct.y][ct.x] == map.TILE_GRASS \\\n'
      '\t\t\t\t\tand building_at(ct).is_empty() and not _tile_in_zone(ct):\n'
      '\t\t\t\tn += 1\n'
      '\treturn n\n'
      '\n'
      '\n'
      'func _advance_gather_scan(c: Dictionary, budget: int) -> void:')

# 3) масштабы: земля мельче, жители/герой крупнее
P = os.path.join(GAME, "scripts", "city_terrain_base.gd")
patch(P,
      'const CANVAS_DENSITY := 3    # v1.79.12: полотно сжимается при загрузке в',
      'const CANVAS_DENSITY := 6    # v3.0 (заказчик: «кусок травы размером с персонажа»):\n'
      '                             # земля мельче фигур; было ÷3 (v1.79.12) —')

P = os.path.join(GAME, "scripts", "assets.gd")
patch(P,
      'const VILLAGER_VISIBLE_H := 27.0 # целевой видимый рост жителя (рыцарь — 31, v1.67.2)',
      'const VILLAGER_VISIBLE_H := 34.0 # целевой видимый рост жителя (v3.0: был 27 —\n'
      '                                 # заказчик: персонажи крупнее; рыцарь 40)')

P = os.path.join(GAME, "scripts", "hero.gd")
patch(P,
      'const KNIGHT_TARGET_H := 32.0   # v2.7.1: был 38 (дома казались меньше героя)   # v2.5.4: был 44 — дома казались меньше героя   # v1.79.2: герой = 1.4 тайла (был 31px = 1 тайл — «соотношение неправильное»)',
      'const KNIGHT_TARGET_H := 40.0   # v3.0: был 32 (v2.7.1) — заказчик: герои крупнее;\n'
      '                                # дома теперь 3x3 (144px при 1.5x) — иерархия держится')

# 4) площадь постройки: w2 -> w3 (кроме стен/ворот/шатра/моста/башни)
P = os.path.join(GAME, "data", "city.json")
cd = json.loads(read(P))
KEEP = {"wall", "gate", "tent", "bridge", "tower"}
n = 0
for b in cd.get("buildings", []):
    if int(b.get("w", 1)) == 2 and str(b.get("id")) not in KEEP:
        b["w"] = 3
        n += 1
write(P, json.dumps(cd, ensure_ascii=False, indent=2) + "\n")
print("ok: data/city.json — %d зданий w2->w3 (стены/ворота/шатёр/мост/башня не тронуты)" % n)

# 5) версия
P = os.path.join(GAME, "data", "version.json")
s = read(P)
assert '"version": "2.9.0"' in s
write(P, s.replace('"version": "2.9.0"', '"version": "3.0.0"'))
print("ok: data/version.json -> 3.0.0")

print("ПАТЧ v3.0.0 ГОТОВ")
