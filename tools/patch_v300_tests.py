# -*- coding: utf-8 -*-
"""v3.0: правки тестов под новые правила (в той же волне, конвенция):
- test_stage2: площадь зданий 3×3 (стены/ворота/шатёр/мост 1×1, башня 2×2);
- test_eras: пастбище больше не уступает клетку стройке (v3.0);
- test_eras: плавильня у склада на +4 (при 3×3 зазор на +3 стал нулевым);
- test_life_a: место под лесопилку 3×3 у дерева (радио ±3, w из сима);
- test_threat: дальняя оружейная от кузни +12 (кузня 3×3).
Запуск: python -I tools/patch_v300_tests.py
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


def patch(p, old, new, count=1):
    s = read(p)
    nl = "\r\n" if "\r\n" in s else "\n"
    old_nl = old.replace("\n", nl)
    new_nl = new.replace("\n", nl)
    assert s.count(old_nl) == count, "якорь x%d в %s: %r" % (s.count(old_nl), p, old[:60])
    write(p, s.replace(old_nl, new_nl))
    print("ok:", os.path.relpath(p, GAME))


# 1) test_stage2: ожидаемая площадь по типу
P = os.path.join(GAME, "tests", "test_stage2.gd")
patch(P,
      '\t\t\t_check(w == 2, "здание «%s» — 2×2" % bid)',
      '\t\t\t# v3.0: площадь 3×3 (заказчик: здания крупнее, площадь больше);\n'
      '\t\t\t# стены/ворота/шатёр/мост 1×1, башня 2×2 — в линии стен\n'
      '\t\t\tvar w_exp: int = 1 if bid in ["wall", "gate", "tent", "bridge"] \\\n'
      '\t\t\t\t\telse (2 if bid == "tower" else 3)\n'
      '\t\t\t_check(w == w_exp, "здание «%s» — площадь %d×%d" % [bid, w_exp, w_exp])')

# 2) test_eras: пастбище НЕ уступает клетку (v3.0)
P = os.path.join(GAME, "tests", "test_eras.gd")
patch(P,
      '\tsim_z2.place_building("wall", zcells[0])\n'
      '\t_check((sim_z2.zones[0]["cells"] as Array).size() == before_n - 1,\n'
      '\t\t\t"здание на клетке пастбища убирает клетку из зоны")',
      '\t# v3.0 (заказчик): здания НЕ строятся на клетках зон — пастбище\n'
      '\t# больше не уступает клетку, поле и пастбище равноправно закрыты\n'
      '\t_check(sim_z2.place_building("wall", zcells[0]) == false,\n'
      '\t\t\t"v3.0: здание на клетке пастбища не ставится")\n'
      '\t_check((sim_z2.zones[0]["cells"] as Array).size() == before_n,\n'
      '\t\t\t"v3.0: клетка пастбища осталась в зоне")')

# 3) test_eras: плавильня на +4 (зазор 1 при 3×3)
patch(P,
      '\tvar smelt_tile_l: Vector2i = sim_l.map.nearest_walkable((barn_l["tile"] as Vector2i) + Vector2i(3, 0))',
      '\t# v3.0: склад 3×3 — зазор 1 начинается с +4 (на +3 зазор нулевой)\n'
      '\tvar smelt_tile_l: Vector2i = sim_l.map.nearest_walkable((barn_l["tile"] as Vector2i) + Vector2i(4, 0))')

# 4) test_life_a: место под лесопилку 3×3 у дерева
P = os.path.join(GAME, "tests", "test_life_a.gd")
patch(P,
      '\tfor dy in range(-2, 3):\n'
      '\t\tfor dx in range(-2, 3):\n'
      '\t\t\tvar t := tree_tile + Vector2i(dx, dy)\n'
      '\t\t\t# этап 2, аспект 2: лесопилка 2×2 — прямоугольник годен и не накрывает дерево\n'
      '\t\t\tif not sim_f.is_buildable_rect("sawmill", t) or sim_f.placement_block("sawmill", t) != "":\n'
      '\t\t\t\tcontinue\n'
      '\t\t\tvar covers := false\n'
      '\t\t\tfor cell in sim_f.bld_cells({"type": "sawmill", "tile": t, "w": 2}):',
      '\tvar saw_w: int = sim_f.bld_w_of_type("sawmill")   # v3.0: 3×3\n'
      '\tfor dy in range(-3, 4):\n'
      '\t\tfor dx in range(-3, 4):\n'
      '\t\t\tvar t := tree_tile + Vector2i(dx, dy)\n'
      '\t\t\t# v3.0: лесопилка 3×3 — прямоугольник годен и не накрывает дерево\n'
      '\t\t\tif not sim_f.is_buildable_rect("sawmill", t) or sim_f.placement_block("sawmill", t) != "":\n'
      '\t\t\t\tcontinue\n'
      '\t\t\tvar covers := false\n'
      '\t\t\tfor cell in sim_f.bld_cells({"type": "sawmill", "tile": t, "w": saw_w}):')

# 5) test_threat: дальняя оружейная от кузни +12
P = os.path.join(GAME, "tests", "test_threat.gd")
patch(P,
      '\tvar far_tile: Vector2i = _find_free_tile(sim, sim.map.spawn_tile + Vector2i(10, 0))\n'
      '\t_check(sim.placement_block("armory", far_tile) != "", "оружейная вдали от кузни не ставится")',
      '\t# v3.0: кузня 3×3 — дальнюю оружейную меряем от неё же (+12, радиус правила меньше)\n'
      '\tvar far_tile: Vector2i = _find_free_tile(sim, (forge["tile"] as Vector2i) + Vector2i(12, 0))\n'
      '\t_check(sim.placement_block("armory", far_tile) != "", "оружейная вдали от кузни не ставится")')

print("ПАТЧ ТЕСТОВ v3.0 ГОТОВ")
