# -*- coding: utf-8 -*-
"""АВТОНОЖ «ПОЛОТНО → БИОМ» (v1.79.2): одно большое бесшовное полотно
земли (напр. 1024×1024 из промта «ПОЛОТНО БИОМА») нарезается на тайлы
32×32 биома. Все тайлы из ОДНОЙ картинки — тон/фактура гарантированно
едины, «мессива из разных кусков» нет.

Запуск: python tools/slice_field.py <путь к полотну.png> <тег биома>
  [--season spring|summer|autumn|winter] [--max 24]
Полотно кладётся в assets/sprites/env/biomes/<тег>/ и манифест
обновляется — город/стенд/композитор подхватывают сами.
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
TS = 32


def make_tileable(tile, F=7):
    H, W = tile.shape[:2]
    rgb = tile[:, :, :3].astype(np.float32)
    out = rgb.copy()
    for y in range(H):
        for x in range(W):
            c = rgb[y, x].copy()
            wx = 0.0
            if x < F:
                wx = 0.5 * (1.0 - x / float(F))
            elif x >= W - F:
                wx = 0.5 * (1.0 - (W - 1 - x) / float(F))
            if wx > 0.0:
                c = c * (1.0 - wx) + rgb[y, W - 1 - x] * wx
            wy = 0.0
            if y < F:
                wy = 0.5 * (1.0 - y / float(F))
            elif y >= H - F:
                wy = 0.5 * (1.0 - (H - 1 - y) / float(F))
            if wy > 0.0:
                c = c * (1.0 - wy) + rgb[H - 1 - y, x] * wy
            out[y, x] = c
    return np.dstack([np.clip(out, 0, 255).astype(np.uint8),
                      tile[:, :, 3].copy()])


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return
    src = sys.argv[1]
    tag = sys.argv[2]
    season = ""
    max_tiles = 24
    for i, a in enumerate(sys.argv):
        if a == "--season" and i + 1 < len(sys.argv):
            season = sys.argv[i + 1]
        if a == "--max" and i + 1 < len(sys.argv):
            max_tiles = int(sys.argv[i + 1])
    if not os.path.exists(src):
        print("!! нет полотна:", src)
        return
    img = np.array(Image.open(src).convert("RGBA"))
    H, W = img.shape[:2]
    cells = []
    for cy in range(H // TS):
        for cx in range(W // TS):
            cell = img[cy * TS:(cy + 1) * TS, cx * TS:(cx + 1) * TS]
            if cell[:, :, 3].min() > 200:
                cells.append((cx, cy, cell))
    if not cells:
        print("!! полотно без полных клеток")
        return
    # равномерная выборка по сетке (не первые N — фактура по всей площади)
    step = max(1, len(cells) // max_tiles)
    pick = cells[::step][:max_tiles]
    means = [c[:, :, :3].reshape(-1, 3).mean(axis=0) for _x, _y, c in pick]
    shared = np.clip(np.mean(means, axis=0), 1, 254).astype(np.uint8)
    bdir = os.path.join(BIOMES, tag)
    os.makedirs(bdir, exist_ok=True)
    grass = []
    for i, (_x, _y, cell) in enumerate(pick, 1):
        t = make_tileable(np.ascontiguousarray(cell))
        Image.fromarray(t).save(os.path.join(bdir, "grass_%d.png" % i))
        Image.fromarray(np.tile(shared, (TS, TS, 1))).save(
            os.path.join(bdir, "grass_%d_fill.png" % i))
        grass.append("res://assets/sprites/env/biomes/%s/grass_%d.png" % (tag, i))
    mf = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as fh:
            mf = json.load(fh)
    entry = mf.get(tag, {})
    entry["grass"] = grass
    entry["label"] = tag
    if season:
        entry["season"] = season
    mf[tag] = entry
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(mf, fh, ensure_ascii=False, indent=1)
    print("биом «%s»: %d тайлов из полотна %dx%d%s" % (
        tag, len(pick), W, H, " сезон=" + season if season else ""))
    print("манифест обновлён")


if __name__ == "__main__":
    main()
