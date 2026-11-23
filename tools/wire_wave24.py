#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# [REUSE] Волна 2026-11-23 (вторая): растения полей по сетке, улей пепла
# (гнездо мутантов + плесень), звери-новинки (медведь/лось/виндиго).
# Где ещё применимо: следующий лист-сетка — свой блок GRID в main().
import json
import os
import shutil

from PIL import Image

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
W = os.path.join(BASE, "assets", "sprites", "wave1123")
ENV = os.path.join(BASE, "assets", "sprites", "env")
SRC = (r"F:\востановление кхорно юнитов\assets\ассеты домов\новые ассеты монстров"
       r"\главный герой\новые биомы\подземелье чудь\предметы\деревья\животные"
       r"\кладбише\руины чуди\дял скал\идолы")

# ряды атласа растений (сверху вниз) — имена культур из data/city.json
CROP_ROWS = ["wheat", "turnip", "cabbage", "pumpkin", "hops", "grapes"]
# порядок блобов листа «грибной улей и пепел» (по рядам, слева направо)
HIVE_NAMES = ["hive_1", "hive_2", "hive_3",
              "hive_cocoon", "hive_eggs", "hive_sporocarp", "hive_bones",
              "mold_1", "mold_2", "mold_3", "mold_4",
              "mold_burned_1", "mold_burned_2"]


def blobs(im, thresh=60, min_px=400, ds=4):
    """Компоненты связности по альфе (см. slice_wave23.py)."""
    w, h = im.size
    gw, gh = w // ds, h // ds
    small = im.getchannel("A").resize((gw, gh))
    px = small.load()
    seen = [[False] * gw for _ in range(gh)]
    out = []
    for gy in range(gh):
        for gx in range(gw):
            if seen[gy][gx] or px[gx, gy] < thresh:
                continue
            stack = [(gx, gy)]
            seen[gy][gx] = True
            cells = []
            while stack:
                cx, cy = stack.pop()
                cells.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < gw and 0 <= ny < gh and not seen[ny][nx] and px[nx, ny] >= thresh:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            if len(cells) * ds * ds < min_px:
                continue
            xs = [c[0] for c in cells]
            ys = [c[1] for c in cells]
            out.append([min(xs) * ds, min(ys) * ds, (max(xs) + 1) * ds, (max(ys) + 1) * ds])
    return out


def save(im, box, name):
    im.crop(box).save(os.path.join(ENV, name + ".png"))
    print("env/%s.png" % name)


def main():
    # 1) РАСТЕНИЯ: сетка 5 колонок × 6 рядов, в каждой клетке одно растение
    src = os.path.join(SRC, "растения", "Пиксельный атлас стадий роста растений.png")
    im = Image.open(src).convert("RGBA")
    cw, ch = im.size[0] / 5.0, im.size[1] / 6.0
    for r, culture in enumerate(CROP_ROWS):
        for c in range(5):
            cell = im.crop((int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)))
            bs = blobs(cell, min_px=300)
            if not bs:
                print("!! пустая клетка %s/%d" % (culture, c + 1))
                continue
            bx0, by0, bx1, by1 = bs[0]
            save(cell, (bx0, by0, bx1, by1), "crop_%s_%d" % (culture, c + 1))
    # 2) УЛЕЙ ПЕПЛА: блобы по рядам
    src = os.path.join(SRC, "растения", "улий", "Пиксельные спрайты грибного улья и пепла.png")
    im = Image.open(src).convert("RGBA")
    bs = blobs(im, min_px=500)
    bs.sort(key=lambda b: (b[1] // 100, b[0]))
    if len(bs) != len(HIVE_NAMES):
        print("!! улей: блобов %d, ожидалось %d — проверь контакт" % (len(bs), len(HIVE_NAMES)))
    for i, name in enumerate(HIVE_NAMES):
        if i < len(bs):
            save(im, tuple(bs[i]), name)
    # 3) ЗВЕРИ: медведь 01-07, лось 08-14, виндиго 15-20 (forest_creatures)
    for name, off, n in [("an_bear", 1, 7), ("an_elk", 8, 7), ("wendigo", 15, 6)]:
        for i in range(n):
            src = os.path.join(W, "forest_creatures", "%02d.png" % (off + i))
            shutil.copyfile(src, os.path.join(ENV, "%s_%d.png" % (name, i + 1)))
            print("env/%s_%d.png" % (name, i + 1))


if __name__ == "__main__":
    main()
