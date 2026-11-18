# -*- coding: utf-8 -*-
"""Нарезчик ВСЕХ биомов заказчика (v1.76.1): папки «биом/биомы» -> тайлы.

Каждый биом -> assets/sprites/env/biomes/<тег>/:
  grass_1..6.png (+ _fill.png подложка среднего цвета)  — земля 32×32
  water.png (6 кадров x 3 ряда)                          — полоса воды
  tree_1..5.png                                          — деревья
Плюс манифест assets/sprites/env/biomes/manifest.json — пути травы/воды/
деревьев читают city_terrain (трава), water_terrain (вода),
city_view_base (деревья).
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

BASE = r"F:\востановление кхорно юнитов\assets\ассеты домов\новые ассеты монстров"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "assets", "sprites", "env", "biomes")
TS = 32
FEATHER = 8
PAD = 3

# тег -> (папка, файл). Только папки «биом/биомы» (решение заказчика).
BIOMES = [
    ("весна",     "биом весна",       "Пиксельный атлас весеннего леса и водоёмов.png"),
    ("осень",     "БИОМ ОСЕНЬ",       "Осенний пиксельный тайлсет для RPG.png"),
    ("зима",      "биомы зима",       "Зимний пиксельный атлас тайлов и объектов.png"),
    ("болота",    "биом болота",      "Пиксельный атлас болотных тайлов.png"),
    ("берёзовая роща", "биом березовая роща", "Осенний берёзовый лес — тайлсет sprites.png"),
    ("древний лес", "биом древний лес", "Пиксельный атлас мрачного леса.png"),
    ("мёртвый лес", "биом мертвый лес", "Пиксельный атлас мёртвого леса.png"),
    ("мистический лес", "биом мистический лес", "Пиксельный атлас зачарованного леса.png"),
    ("огненные земли", "биом огненый", "Пиксельный атлас вулканических земель.png"),
    ("проклятый лес", "биом проклетый лес", "Атлас пиксельных спрайтов проклятого леса.png"),
    ("пустыня",   "биом пустыня",     "Пиксельный атлас пустынных тайлов и руин.png"),
    ("степи",     "биом степи",       "Пиксельный атлас степных тайлов и декораций.png"),
    ("скалы",     "биомы скалы",      "Фэнтезийный атлас горных и водных тайлов.png"),
    ("цветущий край", "биомы цветуший край и речной", "Пиксельный атлас фантастического мира-1.png"),
]


def full_cells(rgb):
    H, W = rgb.shape[:2]
    out = []
    for cy in range(H // TS):
        for cx in range(W // TS):
            cell = rgb[cy*TS:(cy+1)*TS, cx*TS:(cx+1)*TS]
            if cell[:, :, 3].min() > 200:
                m = cell[:, :, :3].reshape(-1, 3).mean(axis=0)
                out.append((cx, cy, m))
    return out


def largest_ground(cells):
    non_water = {(cx, cy) for cx, cy, m in cells
                 if not (m[2] > m[0] + 10 and m[2] > m[1] + 10)}
    best, q = set(), []
    for seed in list(non_water):
        if seed in best:
            continue
        comp, qq = set(), [seed]
        while qq:
            c = qq.pop()
            if c in comp or c not in non_water:
                continue
            comp.add(c)
            x, y = c
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    qq.append((x + dx, y + dy))
        if len(comp) > len(best):
            best = comp
    return best


def longest_water_run(cells):
    # v1.76.2: клетки с ТЁМНЫМ фоном листа (запечённая тьма вокруг) дают
    # грязные квадраты — вода берётся только со светлотой > 70
    cells = [(cx, cy, m) for cx, cy, m in cells
             if (m[0] * 0.299 + m[1] * 0.587 + m[2] * 0.114) > 70.0]
    rows = {}
    for cx, cy, m in cells:
        if m[2] > m[0] + 10 and m[2] > m[1] + 10:
            rows.setdefault(cy, []).append(cx)
    best_y, best = None, []
    for cy, xs in rows.items():
        xs.sort()
        run = [xs[0]]
        for x in xs[1:]:
            if x == run[-1] + 1:
                run.append(x)
            else:
                if len(run) > len(best):
                    best_y, best = cy, run
                run = [x]
        if len(run) > len(best):
            best_y, best = cy, run
    return best_y, best


def composite(tile, shared_mean):
    """v1.76.2: ОБЩАЯ заливка кластера + нормализация цвета тайла к ней.
    Разные средние тайлов давали квадратную мозайку («весна шахматкой») —
    теперь базовый тон один, тайлы несут только фактуру."""
    fill = np.zeros((TS, TS, 4), np.uint8)
    fill[:, :, :3] = shared_mean
    fill[:, :, 3] = 255
    # нормализация каналов тайла к общему тону (мягкая, с потолком x1.4)
    tm = tile[:, :, :3].reshape(-1, 3).mean(axis=0)
    ratio = np.clip(shared_mean / np.maximum(tm, 1.0), 0.7, 1.4)
    t = tile.astype(np.float32)
    t[:, :, :3] *= ratio
    t[:, :, :3] = np.clip(t[:, :, :3], 0, 255)
    t = t.astype(np.uint8)
    yy, xx = np.mgrid[0:TS, 0:TS]
    edge = np.minimum(np.minimum(xx, TS - 1 - xx),
                      np.minimum(yy, TS - 1 - yy)).astype(np.float32)
    # v1.76.3: фактура автора почти в полную силу (0.35..1.0), гасится
    # только кайма — «пластиковая» заливка 10-55% убивала лист заказчика
    ramp = 0.35 + 0.65 * np.clip(edge / float(FEATHER), 0.0, 1.0)
    t[:, :, 3] = (t[:, :, 3].astype(np.float32) * ramp).astype(np.uint8)
    af = t[:, :, 3:4].astype(np.float32) / 255.0
    comp = (t[:, :, :3].astype(np.float32) * af
            + fill[:, :, :3].astype(np.float32) * (1.0 - af)).astype(np.uint8)
    out = np.dstack([comp, np.full((TS, TS), 255, np.uint8)])
    return Image.fromarray(out), Image.fromarray(np.tile(shared_mean, (TS, TS, 1)))


def main():
    manifest = {}
    for tag, folder, fname in BIOMES:
        path = os.path.join(BASE, folder, fname)
        if not os.path.exists(path):
            print("!! нет файла:", tag)
            continue
        img = Image.open(path).convert("RGBA")
        rgb = np.array(img)
        cells = full_cells(rgb)
        # v1.78.3: ВСЕ полные не-водные клетки листа (до 40) — заказчик:
        # «наполнение не полное» — в библиотеке композитора должны быть
        # ВСЕ тайлы листа, не выборка
        allg = [(cx, cy) for cx, cy, m in cells
                if not (m[2] > m[0] + 10 and m[2] > m[1] + 10)]
        allg.sort(key=lambda c: (c[1], c[0]))
        pick = allg[:40]
        bdir = os.path.join(OUT, tag)
        os.makedirs(bdir, exist_ok=True)
        grass_paths = []
        means = [rgb[cy*TS:(cy+1)*TS, cx*TS:(cx+1)*TS][:, :, :3]
                 .reshape(-1, 3).mean(axis=0) for cx, cy in pick]
        shared_mean = np.clip(np.mean(means, axis=0), 1, 254).astype(np.uint8)
        for i, (cx, cy) in enumerate(pick, 1):
            tile = rgb[cy*TS:(cy+1)*TS, cx*TS:(cx+1)*TS]
            comp_img, fill_img = composite(np.ascontiguousarray(tile), shared_mean)
            comp_img.save(os.path.join(bdir, "grass_%d.png" % i))
            fill_img.save(os.path.join(bdir, "grass_%d_fill.png" % i))
            grass_paths.append("res://assets/sprites/env/biomes/%s/grass_%d.png" % (tag, i))
        wy, run = longest_water_run(cells)
        water_path = ""
        if wy is not None and len(run) >= 3:
            strip = Image.new("RGBA", (TS * 6, TS * 3), (0, 0, 0, 0))
            for i in range(6):
                cx = run[i % len(run)]
                cell = img.crop((cx * TS, wy * TS, (cx + 1) * TS, (wy + 1) * TS))
                for r in range(3):
                    strip.paste(cell, (i * TS, r * TS))
            strip.save(os.path.join(bdir, "water.png"))
            water_path = "res://assets/sprites/env/biomes/%s/water.png" % tag
        y_half = img.size[1] // 2
        fg = rgb[y_half:, :, 3] > 40
        lab, n = ndimage.label(fg)
        comps = []
        for i in range(1, n + 1):
            ys, xs = np.where(lab == i)
            h, w = int(ys.max() - ys.min()), int(xs.max() - xs.min())
            if h >= 90 and w >= 40 and ys.size >= 2000:
                comps.append((int(xs.min()), int(ys.min()) + y_half,
                              int(xs.max()), int(ys.max()) + y_half, ys.size))
        comps.sort(key=lambda c: -c[4])
        tree_refs = []
        for k, (x0, y0, x1, y1, _a) in enumerate(comps[:5]):
            crop = img.crop((max(0, x0 - PAD), max(0, y0 - PAD),
                             min(img.size[0], x1 + PAD + 1),
                             min(img.size[1], y1 + PAD + 1)))
            name = "tree_%d.png" % (k + 1)
            crop.save(os.path.join(bdir, name))
            tree_refs.append("img:env/biomes/%s/%s" % (tag, name))
        manifest[tag] = {
            "grass": grass_paths, "water": water_path,
            "trees": tree_refs,
        }
        print("%-16s трава=%d вода=%s деревьев=%d/%d" % (
            tag, len(pick), "да" if water_path else "нет",
            min(5, len(comps)), len(comps)))
    mf = os.path.join(OUT, "manifest.json")
    with open(mf, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=1)
    print("manifest:", mf)


if __name__ == "__main__":
    main()
