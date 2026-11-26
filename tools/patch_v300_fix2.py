# -*- coding: utf-8 -*-
"""v3.0-фикс-2: шахта/каменоломня — исключение из «лесного» правила (сидят
в скалах, дерево в footprint — под нож); тесты под 3×3 (дом/сад/лесопилка/
плавильня перебором сторон). Запуск: python -I tools/patch_v300_fix2.py
"""
import io
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


# 1) шахта/каменоломня — исключение из лесного правила (руда в скалах у деревьев)
P = os.path.join(GAME, "scripts", "city_sim_build.gd")
patch(P,
      '\tif type_id != "bridge" and map.grid[tile.y][tile.x] == map.TILE_TREE:\n'
      '\t\treturn false',
      '\tif type_id != "bridge" and type_id != "mine" and type_id != "quarry" \\\n'
      '\t\t\tand map.grid[tile.y][tile.x] == map.TILE_TREE:\n'
      '\t\treturn false')

# 2) test_stage2: площади — дом/сад 3×3, mine/quarry 2×2
P = os.path.join(GAME, "tests", "test_stage2.gd")
patch(P,
      '\t\t\tvar w_exp: int = 1 if bid in ["wall", "gate", "tent", "bridge"] \\\n'
      '\t\t\t\t\telse (2 if bid == "tower" else 3)',
      '\t\t\tvar w_exp: int = 1 if bid in ["wall", "gate", "tent", "bridge"] \\\n'
      '\t\t\t\t\telse (2 if bid in ["tower", "mine", "quarry"] else 3)')
patch(P,
      '\t_check(sim.place_building("house", t1), "дом 2×2 ставится")\n'
      '\tvar site: Dictionary = sim.building_at(t1)\n'
      '\t_check(not site.is_empty() and sim.bld_w(site) == 2, "построенный дом занимает 2×2")',
      '\t_check(sim.place_building("house", t1), "дом 3×3 ставится")\n'
      '\tvar site: Dictionary = sim.building_at(t1)\n'
      '\t_check(not site.is_empty() and sim.bld_w(site) == 3, "построенный дом занимает 3×3")')
patch(P,
      '\t_check(solid_cnt == 4, "готовый дом непроходим во всех 4 клетках")',
      '\t_check(solid_cnt == 9, "готовый дом непроходим во всех 9 клетках")')
patch(P,
      '\t_check(int(legacy["w"]) == 2, "мигрированному саду присвоен размер 2×2")',
      '\t_check(int(legacy["w"]) == 3, "мигрированному саду присвоен размер 3×3")')
patch(P,
      '\t_check(covered == 4, "мигрированный сад занимает 4 клетки")',
      '\t_check(covered == 9, "мигрированный сад занимает 9 клеток")')

# 3) test_life_a: кольца поиска места под лесопилку шире (3×3 у кромки леса)
P = os.path.join(GAME, "tests", "test_life_a.gd")
patch(P,
      '\tfor dy in range(-3, 4):\n'
      '\t\tfor dx in range(-3, 4):',
      '\tfor dy in range(-5, 6):\n'
      '\t\tfor dx in range(-5, 6):')

# 4) test_eras: плавильня у склада — перебор сторон (дерево/зона в 3×3)
P = os.path.join(GAME, "tests", "test_eras.gd")
patch(P,
      '\t# v3.0: склад 3×3 — зазор 1 начинается с +4 (на +3 зазор нулевой)\n'
      '\tvar smelt_tile_l: Vector2i = sim_l.map.nearest_walkable((barn_l["tile"] as Vector2i) + Vector2i(4, 0))',
      '\t# v3.0: склад 3×3 — зазор 1 с +4; сторону выбираем перебором\n'
      '\t# (в 3×3 кандидата может попасть дерево/зона)\n'
      '\tvar smelt_tile_l: Vector2i = Vector2i(-1, -1)\n'
      '\tfor off_l in [Vector2i(4, 0), Vector2i(0, 4), Vector2i(-4, 0), Vector2i(0, -4)]:\n'
      '\t\tvar cand_l: Vector2i = sim_l.map.nearest_walkable((barn_l["tile"] as Vector2i) + off_l)\n'
      '\t\tif sim_l.is_buildable_rect("smelter", cand_l) and sim_l.placement_gap_ok("smelter", cand_l):\n'
      '\t\t\tsmelt_tile_l = cand_l\n'
      '\t\t\tbreak')

print("ПАТЧ ФИКС-2 ГОТОВ")
