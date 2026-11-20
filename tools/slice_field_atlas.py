# -*- coding: utf-8 -*-
"""АТЛАС 11 ПОЛОТЕН → 11 БИОМОВ (v1.79.5): «Атлас пиксельных
ландшафтных текстур» (1254×1254, сетка 4×3) — каждое полотно вырезается
(обрезая шахматную рамку по альфе) и подключается как ЦЕЛОЕ ПОЛОТНО
биома (canvas.png + поле canvas в манифесте): земля города рисуется
полотном 1:1, без тайлов и без второго слоя.

Порядок блоков в атласе (рядами слева направо):
  древний лес, пустыня, степи,
  скалы, мёртвый лес, проклятый лес,
  огненные земли, мистический лес, древний лес-хвойный (замена),
  берёзовая роща, цветущий край, (пусто)
Заменённые: «древний лес» — мох с кустиками (ряд 1), «древний лес»
хвойный (ряд 3) — тоже древний лес (берём хвойный, он характернее).
Болот в атласе нет — просить у ИИ отдельно.

Запуск: python tools/slice_field_atlas.py <атлас.png>
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
BIOMES = os.path.join(GAME, "assets", "sprites", "env", "biomes")
MANIFEST = os.path.join(BIOMES, "manifest.json")
COLS, ROWS = 3, 4

# порядок блоков в атласе → тег биома
ORDER = [
    ["", "пустыня", "степи"],
    ["скалы", "мёртвый лес", "проклятый лес"],
    ["огненные земли", "мистический лес", "древний лес"],
    ["берёзовая роща", "цветущий край", ""],
]


def alpha_bbox(img):
    """Обрезка шахматной рамки: у атласа «прозрачность» НАРИСОВАНА
    бело-серыми пикселями (непрозрачными!) — резать по светлым
    нейтральным пикселям (>170, разброс каналов < 14): строка/колонка
    блока, где таких больше половины — рамка."""
    a = np.array(img)
    rgb = a[:, :, :3].astype(np.int32)
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    checker = ((mx > 170) & (mx - mn < 14)).mean(axis=1)
    col_c = ((mx > 170) & (mx - mn < 14)).mean(axis=0)
    y0, y1 = 0, a.shape[0]
    x0, x1 = 0, a.shape[1]
    while y0 < y1 and checker[y0] > 0.5:
        y0 += 1
    while y1 > y0 and checker[y1 - 1] > 0.5:
        y1 -= 1
    while x0 < x1 and col_c[x0] > 0.5:
        x0 += 1
    while x1 > x0 and col_c[x1 - 1] > 0.5:
        x1 -= 1
    # v1.79.5: внутренняя чистка — строки/колонки, где больше 15%
    # шахматных пикселей (шов замощения), удаляются целиком
    inner = a[y0:y1, x0:x1]
    irgb = inner[:, :, :3].astype(np.int32)
    imx = irgb.max(axis=2)
    imn = irgb.min(axis=2)
    ichk = ((imx > 170) & (imx - imn < 14)).mean(axis=1)
    jchk = ((imx > 170) & (imx - imn < 14)).mean(axis=0)
    keep_rows = np.where(ichk <= 0.15)[0]
    keep_cols = np.where(jchk <= 0.15)[0]
    if len(keep_rows) < 100 or len(keep_cols) < 100:
        keep_rows = np.arange(inner.shape[0])
        keep_cols = np.arange(inner.shape[1])
    y0 += int(keep_rows[0]); y1 = y0 + int(keep_rows[-1]) + 1
    x0 += int(keep_cols[0]); x1 = x0 + int(keep_cols[-1]) + 1
    if y1 - y0 < 100 or x1 - x0 < 100:
        ys, xs = np.where(a[:, :, 3] > 60)
        if len(xs) == 0:
            return None
        return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    return (x0, y0, x1, y1)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    src = sys.argv[1]
    if not os.path.exists(src):
        print("!! нет атласа:", src)
        return
    at = Image.open(src).convert("RGBA")
    W, H = at.size
    bw, bh = W // COLS, H // ROWS
    mf = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as fh:
            mf = json.load(fh)
    for r in range(ROWS):
        for c in range(COLS):
            if r >= len(ORDER) or c >= len(ORDER[r]):
                continue
            if r >= len(ORDER) or c >= len(ORDER[r]):
                continue
            tag = ORDER[r][c]
            if tag == "":
                continue
            block = at.crop((c * bw, r * bh, (c + 1) * bw, (r + 1) * bh))
            bb = alpha_bbox(block)
            if bb is None:
                continue
            field = block.crop(bb)
            bdir = os.path.join(BIOMES, tag)
            os.makedirs(bdir, exist_ok=True)
            field.save(os.path.join(bdir, "canvas.png"))
            # мини-тайлы для совместимости (композитор/стенд смотрят grass_*)
            fa = np.array(field)
            cells = []
            TS = 32
            for cy in range(fa.shape[0] // TS):
                for cx in range(fa.shape[1] // TS):
                    cell = fa[cy * TS:(cy + 1) * TS, cx * TS:(cx + 1) * TS]
                    if cell[:, :, 3].min() > 200:
                        cells.append(cell)
            step = max(1, len(cells) // 12)
            pick = cells[::step][:12]
            means = [c[:, :, :3].reshape(-1, 3).mean(axis=0) for c in pick]
            shared = np.clip(np.mean(means, axis=0), 1, 254).astype(np.uint8)
            for i, cell in enumerate(pick, 1):
                Image.fromarray(cell).save(
                    os.path.join(bdir, "grass_%d.png" % i))
                Image.fromarray(np.tile(shared, (TS, TS, 1))).save(
                    os.path.join(bdir, "grass_%d_fill.png" % i))
            entry = mf.get(tag, {})
            entry["canvas"] = "res://assets/sprites/env/biomes/%s/canvas.png" % tag
            entry["label"] = tag
            entry["grass"] = ["res://assets/sprites/env/biomes/%s/grass_%d.png"
                              % (tag, i + 1) for i in range(len(pick))]
            entry.pop("season", None)   # мировые биомы — вне сезонного календаря
            mf[tag] = entry
            print("%-16s полотно %dx%d + тайлов %d" % (
                tag, field.size[0], field.size[1], len(pick)))
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(mf, fh, ensure_ascii=False, indent=1)
    print("манифест обновлён")


if __name__ == "__main__":
    main()
