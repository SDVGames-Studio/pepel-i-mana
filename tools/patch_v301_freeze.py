# -*- coding: utf-8 -*-
"""v3.0.2 (зависание 26.11): скан фермы старосты перебирает ВСЮ карту без
дистанционного отсева, и каждый кандидат через _tile_in_zone ходил по всем
зонам×клеткам — кадры вставали на секунды. Теперь: клетки зон одним
словарём на вызов + ограничение радиуса скана фермы (placement.farm_scan_cap).
Запуск: python -I tools/patch_v301_freeze.py
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


P = os.path.join(GAME, "scripts", "city_sim_gov_plan.gd")

# 1) словарь клеток зон один на вызов скана (только ферма его платит)
patch(P,
      '\tvar pcfg: Dictionary = cfg.get("placement", {})\n'
      '\tvar build_gap := int(pcfg.get("build_gap", 1))\n'
      '\tvar wall_gap := int(pcfg.get("wall_house_gap", 3))',
      '\tvar pcfg: Dictionary = cfg.get("placement", {})\n'
      '\tvar build_gap := int(pcfg.get("build_gap", 1))\n'
      '\tvar wall_gap := int(pcfg.get("wall_house_gap", 3))\n'
      '\t# v3.0.2 (зависание 26.11): скан фермы идёт по всей карте без\n'
      '\t# дистанционного отсева — клетки зон собираем ОДНИМ словарём на\n'
      '\t# вызов; иначе каждый кандидат через _tile_in_zone ходил по всем\n'
      '\t# зонам×клеткам и кадры вставали на секунды\n'
      '\tvar zset := {}\n'
      '\tif type_id == "farm":\n'
      '\t\tfor z in zones:\n'
      '\t\t\tfor cz in (z["cells"] as Array):\n'
      '\t\t\t\tzset[cz] = true')

# 2) радиус скана фермы + словарь вместо _tile_in_zone
patch(P,
      '\t\t\tif type_id == "farm":\n'
      '\t\t\t\tvar sc: int = _free_farmland(t, w)',
      '\t\t\tif type_id == "farm":\n'
      '\t\t\t\tif col_d > float(int(pcfg.get("farm_scan_cap", 48))):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t\tvar sc: int = _free_farmland(t, w, zset)')

# 3) _free_farmland — зона по словарю O(1)
patch(P,
      'func _free_farmland(t: Vector2i, w: int) -> int:',
      'func _free_farmland(t: Vector2i, w: int, zset: Dictionary) -> int:')
patch(P,
      '\t\t\tif map.in_bounds(ct) and map.grid[ct.y][ct.x] == map.TILE_GRASS \\\n'
      '\t\t\t\t\tand building_at(ct).is_empty() and not _tile_in_zone(ct):',
      '\t\t\tif map.in_bounds(ct) and map.grid[ct.y][ct.x] == map.TILE_GRASS \\\n'
      '\t\t\t\t\tand building_at(ct).is_empty() and not zset.has(ct):')

print("ПАТЧ v3.0.2 ГОТОВ")
