# -*- coding: utf-8 -*-
"""v2.8-фикс: новые биом-регионы кидают кости ОТДЕЛЬНЫМ RNG — главный
поток _rng не смещается, POI/дороги/раскладка мира после регионов
ровно как в 2.7.1 (тест «старая дорога быстрее равнины» снова зелёный).
Запуск: python -I tools/patch_v280_rng.py
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
    assert old_nl in s, "якорь не найден в %s: %r" % (p, old[:70])
    assert s.count(old_nl) == 1, "якорь неуникален в %s: %r" % (p, old[:70])
    write(p, s.replace(old_nl, new_nl))
    print("ok:", os.path.relpath(p, GAME))


G = os.path.join(GAME, "scripts", "world_map_gen.gd")
B = os.path.join(GAME, "scripts", "world_map_base.gd")

# 1) _random_inner_tile — источник случайности параметром (старые зовут
#    без параметра — главный поток, как в 2.7.1)
patch(G,
      'func _random_inner_tile() -> Vector2i:\n'
      '\treturn Vector2i(_rng.randi_range(4, w - 5), _rng.randi_range(4, h - 5))',
      'func _random_inner_tile(rng = null) -> Vector2i:\n'
      '\tif rng == null:\n'
      '\t\trng = _rng\n'
      '\treturn Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))')

# 2) _build_regions — новым регионам свой поток (сид от attempt-сида)
patch(G,
      'func _build_regions(rcfg: Dictionary) -> void:\n'
      '\tvar list: Array = rcfg.get("list", [])\n'
      '\tfor entry: Dictionary in list:\n'
      '\t\tvar id := String(entry.get("id", ""))\n'
      '\t\tvar count := _rng.randi_range(int(entry.get("count_min", 1)), int(entry.get("count_max", 1)))\n'
      '\t\tfor i in count:\n'
      '\t\t\tvar c := _region_center(id, entry)\n'
      '\t\t\tif c == Vector2i(-1, -1):\n'
      '\t\t\t\tcontinue\n'
      '\t\t\tvar rad: Array = entry.get("radius", [3, 5])\n'
      '\t\t\t_region_blob(c, _rng.randi_range(int(rad[0]), int(rad[1])), id)',
      '## v2.8: регионы вне LEGACY_REGIONS кидают кости ОТДЕЛЬНЫМ потоком —\n'
      '## главный _rng не смещается, POI/дороги после регионов как в 2.7.1\n'
      'const LEGACY_REGIONS := ["snow", "volcanic", "desert", "dead"]\n'
      '\n'
      '\n'
      'func _build_regions(rcfg: Dictionary) -> void:\n'
      '\tvar list: Array = rcfg.get("list", [])\n'
      '\tvar rx := RandomNumberGenerator.new()\n'
      '\trx.seed = int(_rng.seed) + 610_000_003\n'
      '\tfor entry: Dictionary in list:\n'
      '\t\tvar id := String(entry.get("id", ""))\n'
      '\t\tvar rng = _rng if LEGACY_REGIONS.has(id) else rx\n'
      '\t\tvar count := rng.randi_range(int(entry.get("count_min", 1)), int(entry.get("count_max", 1)))\n'
      '\t\tfor i in count:\n'
      '\t\t\tvar c := _region_center(id, entry, rng)\n'
      '\t\t\tif c == Vector2i(-1, -1):\n'
      '\t\t\t\tcontinue\n'
      '\t\t\tvar rad: Array = entry.get("radius", [3, 5])\n'
      '\t\t\t_region_blob(c, rng.randi_range(int(rad[0]), int(rad[1])), id, rng)')

# 3) _region_center / _region_blob — источник случайности параметром
patch(G,
      'func _region_center(id: String, entry: Dictionary) -> Vector2i:\n'
      '\tvar moist_thr := float(entry.get("moist_max", 0.5))\n'
      '\tfor attempt in 200:\n'
      '\t\tvar p := _random_inner_tile()',
      'func _region_center(id: String, entry: Dictionary, rng = null) -> Vector2i:\n'
      '\tvar moist_thr := float(entry.get("moist_max", 0.5))\n'
      '\tfor attempt in 200:\n'
      '\t\tvar p := _random_inner_tile(rng)')
patch(G,
      'func _region_blob(center: Vector2i, radius: int, id: String) -> void:\n'
      '\tvar ph1 := _rng.randf() * TAU\n'
      '\tvar ph2 := _rng.randf() * TAU\n'
      '\tvar a1 := _rng.randf_range(0.10, 0.20)\n'
      '\tvar a2 := _rng.randf_range(0.06, 0.12)',
      'func _region_blob(center: Vector2i, radius: int, id: String, rng = null) -> void:\n'
      '\tif rng == null:\n'
      '\t\trng = _rng\n'
      '\tvar ph1 := rng.randf() * TAU\n'
      '\tvar ph2 := rng.randf() * TAU\n'
      '\tvar a1 := rng.randf_range(0.10, 0.20)\n'
      '\tvar a2 := rng.randf_range(0.06, 0.12)')

# 4) стаб в base — сигнатуры цепочки в синхроне
patch(B,
      'func _random_inner_tile() -> Vector2i:\n'
      '\treturn Vector2i(-1, -1)',
      'func _random_inner_tile(rng = null) -> Vector2i:\n'
      '\treturn Vector2i(-1, -1)')

print("ПАТЧ RNG v2.8 ГОТОВ")
