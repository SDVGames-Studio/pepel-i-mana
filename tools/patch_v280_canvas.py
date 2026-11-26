# -*- coding: utf-8 -*-
"""v2.8: полотна регионов мира — ТА ЖЕ ОБРАБОТКА, что у сезонных полотен
города («весна», city_terrain_base._load_grass_set): ÷3 LANCZOS + бесшовные
края F=8 + статический кэш по пути. Запуск: python -I tools/patch_v280_canvas.py
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
    assert old_nl in s, "якорь не найден в %s: %r" % (p, old[:60])
    assert s.count(old_nl) == 1, "якорь неуникален в %s" % p
    write(p, s.replace(old_nl, new_nl))
    print("ok:", os.path.relpath(p, GAME))


P = os.path.join(GAME, "scripts", "world_view.gd")

# 1) загрузка канваса региона — через общий обработчик (ниже)
patch(P,
      '\t\tvar cvp := String((bmf[btag] as Dictionary).get("canvas", ""))\n'
      '\t\tvar ctex: Texture2D = Assets.tex(cvp) if cvp != "" else null\n'
      '\t\tif ctex != null:\n'
      '\t\t\trcv[String((entry as Dictionary).get("id", ""))] = ctex.get_image()',
      '\t\tvar cvp := String((bmf[btag] as Dictionary).get("canvas", ""))\n'
      '\t\tif cvp == "":\n'
      '\t\t\tcontinue\n'
      '\t\tvar cimg: Image = _region_canvas_img(cvp)\n'
      '\t\tif cimg != null:\n'
      '\t\t\trcv[String((entry as Dictionary).get("id", ""))] = cimg')

# 2) сам обработчик — канон «весны» (÷3 LANCZOS + сшивка краёв + кэш)
patch(P,
      'const BAKE_ROCK := Color("#8a8276")   # скальный тон вершин',
      'const BAKE_ROCK := Color("#8a8276")   # скальный тон вершин\n'
      '\n'
      '## v2.8: полотно региона мира — ТА ЖЕ ОБРАБОТКА, что у сезонных полотен\n'
      '## города («весна», city_terrain_base._load_grass_set): ÷3 LANCZOS +\n'
      '## бесшовные края F=8 (замощение без шва) + статический кэш по пути.\n'
      'static var _canvas_cache := {}\n'
      'const CANVAS_DENSITY := 3   # как CANVAS_DENSITY в city_terrain_base\n'
      '\n'
      '\n'
      'static func _region_canvas_img(path: String) -> Image:\n'
      '\tif _canvas_cache.has(path):\n'
      '\t\treturn _canvas_cache[path]\n'
      '\tvar ct: Texture2D = Assets.tex(path)\n'
      '\tif ct == null:\n'
      '\t\treturn null\n'
      '\tvar cim: Image = ct.get_image()\n'
      '\tif cim == null or cim.is_empty():\n'
      '\t\treturn null\n'
      '\tif cim.is_compressed():\n'
      '\t\tcim.decompress()\n'
      '\tif cim.get_width() > 96 and cim.get_height() > 96:\n'
      '\t\tcim.convert(Image.FORMAT_RGBA8)\n'
      '\t\tcim.resize(int(cim.get_width() / float(CANVAS_DENSITY)),\n'
      '\t\t\t\tint(cim.get_height() / float(CANVAS_DENSITY)),\n'
      '\t\t\t\tImage.INTERPOLATE_LANCZOS)\n'
      '\t\tvar W := cim.get_width()\n'
      '\t\tvar H := cim.get_height()\n'
      '\t\tvar F := 8\n'
      '\t\tvar dup: Image = cim.duplicate()\n'
      '\t\tfor y in range(F):\n'
      '\t\t\tvar wy := 0.5 * (1.0 - float(y) / float(F))\n'
      '\t\t\tvar y2 := H - 1 - y\n'
      '\t\t\tfor x in range(W):\n'
      '\t\t\t\tcim.set_pixel(x, y, dup.get_pixel(x, y)\n'
      '\t\t\t\t\t\t.lerp(dup.get_pixel(x, y2), wy))\n'
      '\t\t\t\tcim.set_pixel(x, y2, dup.get_pixel(x, y2)\n'
      '\t\t\t\t\t\t.lerp(dup.get_pixel(x, y), wy))\n'
      '\t\tfor y in range(F, H - F):\n'
      '\t\t\tfor x in range(F):\n'
      '\t\t\t\tvar wx := 0.5 * (1.0 - float(x) / float(F))\n'
      '\t\t\t\tvar x2 := W - 1 - x\n'
      '\t\t\t\tcim.set_pixel(x, y, dup.get_pixel(x, y)\n'
      '\t\t\t\t\t\t.lerp(dup.get_pixel(x2, y), wx))\n'
      '\t\t\t\tcim.set_pixel(x2, y, dup.get_pixel(x2, y)\n'
      '\t\t\t\t\t\t.lerp(dup.get_pixel(x, y), wx))\n'
      '\t_canvas_cache[path] = cim\n'
      '\treturn cim')

print("ПАТЧ канвас-обработки v2.8 ГОТОВ")
