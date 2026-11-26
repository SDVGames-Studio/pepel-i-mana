# -*- coding: utf-8 -*-
"""v2.8-фикс-2: тип НЕ выводится из untyped rng (грабля цепочки extends) —
явные типы в _build_regions/_region_blob. Запуск: python -I tools/patch_v280_rng2.py
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
    assert old_nl in s, "якорь не найден: %r" % old[:70]
    assert s.count(old_nl) == 1, "якорь неуникален: %r" % old[:70]
    write(p, s.replace(old_nl, new_nl))
    print("ok:", os.path.relpath(p, GAME))


G = os.path.join(GAME, "scripts", "world_map_gen.gd")

patch(G,
      '\t\tvar rng = _rng if LEGACY_REGIONS.has(id) else rx\n'
      '\t\tvar count := rng.randi_range(int(entry.get("count_min", 1)), int(entry.get("count_max", 1)))',
      '\t\tvar rng: RandomNumberGenerator = _rng if LEGACY_REGIONS.has(id) else rx\n'
      '\t\tvar count: int = rng.randi_range(int(entry.get("count_min", 1)), int(entry.get("count_max", 1)))')

patch(G,
      '\tvar ph1 := rng.randf() * TAU\n'
      '\tvar ph2 := rng.randf() * TAU\n'
      '\tvar a1 := rng.randf_range(0.10, 0.20)\n'
      '\tvar a2 := rng.randf_range(0.06, 0.12)',
      '\tvar ph1: float = rng.randf() * TAU\n'
      '\tvar ph2: float = rng.randf() * TAU\n'
      '\tvar a1: float = rng.randf_range(0.10, 0.20)\n'
      '\tvar a2: float = rng.randf_range(0.06, 0.12)')

print("ПАТЧ ТИПОВ ГОТОВ")
