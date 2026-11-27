# -*- coding: utf-8 -*-
"""v3.0.3 (фидбек скрина): колодец возвращён на 2×2 и рисуется ×0.9 —
не выше персонажа; у дома со всех сторон коридор house_gap=3 под дорогу
и проход (и в автострое, и в ручной стройке). Запуск:
python -I tools/patch_v303_well_gap.py
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
    assert s.count(old_nl) == 1, "якорь x%d в %s: %r" % (s.count(old_nl), p, old[:60])
    write(p, s.replace(old_nl, new_nl))
    print("ok:", os.path.relpath(p, GAME))


# 1) колодец: футпринт 2×2 (мелкий объект, не дом)
P = os.path.join(GAME, "data", "city.json")
cd = json.loads(read(P))
for b in cd.get("buildings", []):
    if str(b.get("id")) == "well":
        b["w"] = 2
cd.setdefault("placement", {})["house_gap"] = 3
write(P, json.dumps(cd, ensure_ascii=False, indent=2) + "\n")
print("ok: data/city.json — well 2×2, placement.house_gap=3")

# 2) колодец: визуальный масштаб 1.4 → 0.9 (ниже героя)
P = os.path.join(GAME, "scripts", "city_view.gd")
patch(P,
      '\t\t\tvar bld_scale: float = 1.4 if type_id == "well" else 1.5',
      '\t\t\t# v3.0.3: колодец не выше персонажа (фидбек скрина) — 2×2 × 0.9\n'
      '\t\t\tvar bld_scale: float = 0.9 if type_id == "well" else 1.5')

# 3) ручная стройка: house_gap для пар с домом
P = os.path.join(GAME, "scripts", "city_sim_build.gd")
patch(P,
      '\tvar wall_class := type_id == "wall" or type_id == "gate"\n'
      '\tfor b in buildings:',
      '\tvar wall_class := type_id == "wall" or type_id == "gate"\n'
      '\tvar house_class := type_id == "house"\n'
      '\tfor b in buildings:')
patch(P,
      '\t\telif other_type != "wall" and other_type != "gate":\n'
      '\t\t\tif gap < int(pcfg.get("build_gap", 1)):\n'
      '\t\t\t\treturn false',
      '\t\telif other_type != "wall" and other_type != "gate":\n'
      '\t\t\t# v3.0.3: у дома со всех сторон коридор под дорогу/проход\n'
      '\t\t\tvar req := int(pcfg.get("build_gap", 1))\n'
      '\t\t\tif (house_class or other_type == "house") \\\n'
      '\t\t\t\t\tand int(pcfg.get("house_gap", 3)) > req:\n'
      '\t\t\t\treq = int(pcfg.get("house_gap", 3))\n'
      '\t\t\tif gap < req:\n'
      '\t\t\t\treturn false')

# 4) автостройка старосты: тот же house_gap
P = os.path.join(GAME, "scripts", "city_sim_gov_plan.gd")
patch(P,
      '\tvar build_gap := int(pcfg.get("build_gap", 1))\n'
      '\tvar wall_gap := int(pcfg.get("wall_house_gap", 3))',
      '\tvar build_gap := int(pcfg.get("build_gap", 1))\n'
      '\tvar wall_gap := int(pcfg.get("wall_house_gap", 3))\n'
      '\tvar house_gap := int(pcfg.get("house_gap", 3))')
patch(P,
      '\t\t\t\tif maxi(dx2, dy2) < (wall_gap if (o["wall"] and o["house"]) else build_gap):',
      '\t\t\t\t# v3.0.3: у дома со всех сторон коридор под дорогу/проход\n'
      '\t\t\t\tvar need := wall_gap if (o["wall"] and o["house"]) else build_gap\n'
      '\t\t\t\tif (o["house"] or type_id == "house") and house_gap > need:\n'
      '\t\t\t\t\tneed = house_gap\n'
      '\t\t\t\tif maxi(dx2, dy2) < need:')

print("ПАТЧ v3.0.3 ГОТОВ")
