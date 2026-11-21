# -*- coding: utf-8 -*-
"""АТЛАС СЕЗОНОВ → 4 БИОМА (v1.79.4): полотно 1254×1254 из 4 квадрантов
(весна/лето/осень/зима) нарезается в сезонные биомы города.

Квадранты классифицируются АВТОМАТИЧЕСКИ по среднему цвету:
  зима  — самый светлый (снег),
  осень — самый тёплый (красного больше зелёного),
  из двух зелёных: весна — светлее, лето — темнее.

Запуск: python tools/slice_season_atlas.py <атлас.png> [--max 24]
Каждый квадрант нарезается на 32×32 тайлы (равномерно по площади,
make_tileable) в assets/sprites/env/biomes/<весна|лето|осень|зима>/,
манифест обновляется с полем season.
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


def classify(mean):
    r, g, b = mean
    lum = r * 0.299 + g * 0.587 + b * 0.114
    if lum > 120.0:
        return "зима"
    if r > g + 10.0:
        return "осень"
    return "зелёный"   # весна или лето — различим по светлоте пары


def cut_quadrants(img):
    H, W = img.shape[:2]
    hw, hh = W // 2, H // 2
    return {
        "TL": img[0:hh, 0:hw],
        "TR": img[0:hh, hw:W],
        "BL": img[hh:H, 0:hw],
        "BR": img[hh:H, hw:W],
    }


def cut_tiles(quad, max_tiles):
    H, W = quad.shape[:2]
    cells = []
    for cy in range(H // TS):
        for cx in range(W // TS):
            cell = quad[cy * TS:(cy + 1) * TS, cx * TS:(cx + 1) * TS]
            if cell[:, :, 3].min() > 200:
                cells.append((cx, cy, cell))
    if not cells:
        return []
    step = max(1, len(cells) // max_tiles)
    return cells[::step][:max_tiles]


SCALE = 2


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    src = sys.argv[1]
    max_tiles = 24
    for i, a in enumerate(sys.argv):
        if a == "--scale" and i + 1 < len(sys.argv):
            SCALE = max(1, int(sys.argv[i + 1]))
        if a == "--max" and i + 1 < len(sys.argv):
            max_tiles = int(sys.argv[i + 1])
    if not os.path.exists(src):
        print("!! нет атласа:", src)
        return
    srcim = Image.open(src).convert("RGBA")
    srcim = srcim.resize((srcim.size[0] * SCALE, srcim.size[1] * SCALE), Image.NEAREST)
    img = np.array(srcim)
    quads = cut_quadrants(img)
    # средние цвета квадрантов
    stats = {}
    for k, q in quads.items():
        m = q[:, :, :3].reshape(-1, 3).mean(axis=0)
        stats[k] = {"mean": m, "lum": m[0] * 0.299 + m[1] * 0.587 + m[2] * 0.114}
        print("квадрант %s: mean=(%.0f,%.0f,%.0f) lum=%.0f" % (
            k, m[0], m[1], m[2], stats[k]["lum"]))
    # классификация
    seasons = {}
    greens = [k for k in quads if classify(stats[k]["mean"]) == "зелёный"]
    for k in quads:
        cl = classify(stats[k]["mean"])
        if cl in ("зима", "осень"):
            seasons[k] = cl
    if len(greens) == 2:
        greens.sort(key=lambda k: stats[k]["lum"])
        seasons[greens[0]] = "лето"
        seasons[greens[1]] = "весна"
    elif len(greens) == 1:
        seasons[greens[0]] = "лето"
    print("квадранты → сезоны:", seasons)
    if len(set(seasons.values())) < 4:
        print("!! не все 4 сезона определены — атлас не подходит")
        return
    # нарезка квадрантов в биомы
    mf = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as fh:
            mf = json.load(fh)
    for k, q in quads.items():
        season = seasons[k]
        tiles = cut_tiles(q, max_tiles)
        if len(tiles) < 6:
            print("!! %s: мало тайлов" % season)
            continue
        means = [c[:, :, :3].reshape(-1, 3).mean(axis=0) for _x, _y, c in tiles]
        shared = np.clip(np.mean(means, axis=0), 1, 254).astype(np.uint8)
        bdir = os.path.join(BIOMES, season)
        os.makedirs(bdir, exist_ok=True)
        grass = []
        for i, (_x, _y, cell) in enumerate(tiles, 1):
            t = make_tileable(np.ascontiguousarray(cell))
            Image.fromarray(t).save(os.path.join(bdir, "grass_%d.png" % i))
            Image.fromarray(np.tile(shared, (TS, TS, 1))).save(
                os.path.join(bdir, "grass_%d_fill.png" % i))
            grass.append("res://assets/sprites/env/biomes/%s/grass_%d.png"
                         % (season, i))
        entry = mf.get(season, {})
        entry["grass"] = grass
        entry["label"] = season
        entry["season"] = {"весна": "spring", "лето": "summer",
                           "осень": "autumn", "зима": "winter"}[season]
        mf[season] = entry
        print("%-8s тайлов=%d" % (season, len(tiles)))
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(mf, fh, ensure_ascii=False, indent=1)
    print("манифест обновлён")


if __name__ == "__main__":
    main()
