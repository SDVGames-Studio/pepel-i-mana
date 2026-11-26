# -*- coding: utf-8 -*-
"""v3.0-фикс-3: стены/ворота умеют расчищать дерево под собой (кольцо
частокола смыкается через лес — иначе дыры для мутантов); life_a ищет
место под лесопилку перебором достижимых деревьев. Запуск:
python -I tools/patch_v300_fix3.py
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


# 1) стены/ворота: дерево под 1×1 вырубается (частокол смыкается в лесу)
P = os.path.join(GAME, "scripts", "city_sim_build.gd")
patch(P,
      '\tif type_id != "bridge" and type_id != "mine" and type_id != "quarry" \\\n'
      '\t\t\tand map.grid[tile.y][tile.x] == map.TILE_TREE:\n'
      '\t\treturn false',
      '\t# v3.0: стены/ворота вырубают дерево под собой (кольцо частокола\n'
      '\t# обязано смыкаться через лес), шахта/каменоломня сидят в скалах;\n'
      '\t# прочие здания в лесу строить нельзя (заказчик)\n'
      '\tif type_id != "bridge" and type_id != "mine" and type_id != "quarry" \\\n'
      '\t\t\tand type_id != "wall" and type_id != "gate" \\\n'
      '\t\t\tand map.grid[tile.y][tile.x] == map.TILE_TREE:\n'
      '\t\treturn false')

# 2) life_a: перебор достижимых деревьев, пока у какого-то не найдётся место 3×3
P = os.path.join(GAME, "tests", "test_life_a.gd")
patch(P,
      '\tvar tree_tile := Vector2i(-1, -1)\n'
      '\t# дерево — из ДОСТИЖИМЫХ от старта (v1.29.4): карта режется рекой, первое\n'
      '\t# по скану дерево могло оказаться на другом берегу без моста — лесоруб\n'
      '\t# до него не дойдёт, и тест ловил флак по сиду\n'
      '\tvar reach: Dictionary = sim_f.map._reachable_from(sim_f.map.spawn_tile)\n'
      '\tfor y in sim_f.map.h:\n'
      '\t\tfor x in sim_f.map.w:\n'
      '\t\t\tif sim_f.map.grid[y][x] == sim_f.map.TILE_TREE \\\n'
      '\t\t\t\t\tand reach.has(Vector2i(x, y)):\n'
      '\t\t\t\ttree_tile = Vector2i(x, y)\n'
      '\t\t\t\tbreak\n'
      '\t\tif tree_tile.x >= 0:\n'
      '\t\t\tbreak',
      '\tvar tree_tile := Vector2i(-1, -1)\n'
      '\t# дерево — из ДОСТИЖИМЫХ от старта (v1.29.4): карта режется рекой, первое\n'
      '\t# по скану дерево могло оказаться на другом берегу без моста — лесоруб\n'
      '\t# до него не дойдёт, и тест ловил флак по сиду. v3.0: деревьев несколько\n'
      '\t# (у первого в гуще леса может не быть окна 3×3 под лесопилку)\n'
      '\tvar reach: Dictionary = sim_f.map._reachable_from(sim_f.map.spawn_tile)\n'
      '\tvar tree_spots: Array = []\n'
      '\tfor y in sim_f.map.h:\n'
      '\t\tfor x in sim_f.map.w:\n'
      '\t\t\tif sim_f.map.grid[y][x] == sim_f.map.TILE_TREE \\\n'
      '\t\t\t\t\tand reach.has(Vector2i(x, y)):\n'
      '\t\t\t\ttree_spots.append(Vector2i(x, y))')

print("ПАТЧ ФИКС-3 ГОТОВ (деревья-кандидаты собраны, цикл ниже переписывается)")
