#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# [REUSE] Волна 2026-11-23: универсальная блоб-нарезка листов заказчика.
# Где ещё применимо: любой новый лист «новые ассеты» — добавить в SHEETS.
# Порог по альфе (>=T) отсекает грязь фона (alpha 1-16 у ChatGPT-листов).
# Выход: assets/sprites/wave1123/<имя>/NN.png + manifest.json + контакт-лист.
import json
import os
import sys

from PIL import Image, ImageDraw

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = r"F:\востановление кхорно юнитов\assets\ассеты домов\новые ассеты монстров\главный герой\новые биомы\подземелье чудь"
OUT = os.path.join(BASE, "assets", "sprites", "wave1123")

# (подпуть от SRC, имя выхода, порог альфы, мин. площадь блоба px^2)
SHEETS = [
    ("Пиксельный атлас мрачных сокровищ и реликвий.png", "chud_treasures", 60, 400),
    ("Пиксельный атлас тёмных реликвий.png", "chud_relics", 60, 400),
    (r"предметы\Пиксельный атлас фэнтезийных предметов.png", "loot_items", 60, 300),
    (r"предметы\деревья\Пиксельные лесные ассеты_ деревья и брёвна.png", "trees_logs_a", 60, 600),
    (r"предметы\деревья\Пиксельный набор деревьев и брёвен.png", "trees_logs_b", 60, 600),
    (r"предметы\деревья\животные\Пиксельный спрайт-лист дикой природы.png", "wildlife", 60, 250),
    (r"предметы\деревья\животные\Пиксельный атлас лесных существ.png", "forest_creatures", 60, 250),
    (r"предметы\деревья\животные\кладбише\Пиксельный набор мрачного кладбища.png", "cemetery", 60, 400),
    (r"предметы\деревья\животные\кладбише\руины чуди\Пиксельный атлас мрачных руин и подземелий.png", "chud_ruins", 60, 400),
    (r"предметы\деревья\животные\кладбише\руины чуди\дял скал\Пиксельные камни и руины_ лист ассетов.png", "rocks", 60, 400),
    (r"предметы\деревья\животные\кладбише\руины чуди\дял скал\идолы\Пиксельные деревянные тотемы_ набор из шести.png", "idols", 60, 600),
]

DOWNSCALE = 4  # сетка поиска блобов (скорость)


def find_blobs(alpha, w, h, thresh, min_px):
    """Компоненты связности по сетке 1/DOWNSCALE, bbox уточняется в 1:1."""
    gw, gh = w // DOWNSCALE, h // DOWNSCALE
    lab = [[0] * gw for _ in range(gh)]
    blobs = []
    for gy in range(gh):
        for gx in range(gw):
            if alpha[gy][gx] < thresh or lab[gy][gx]:
                continue
            n = len(blobs) + 1
            stack = [(gx, gy)]
            lab[gy][gx] = n
            cells = []
            while stack:
                cx, cy = stack.pop()
                cells.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < gw and 0 <= ny < gh and lab[ny][nx] == 0 and alpha[ny][nx] >= thresh:
                        lab[ny][nx] = n
                        stack.append((nx, ny))
            area = len(cells) * DOWNSCALE * DOWNSCALE
            if area < min_px:
                continue
            xs = [c[0] for c in cells]
            ys = [c[1] for c in cells]
            blobs.append([min(xs) * DOWNSCALE, min(ys) * DOWNSCALE,
                          (max(xs) + 1) * DOWNSCALE, (max(ys) + 1) * DOWNSCALE, area])
    return blobs


def main() -> None:
    manifest = {}
    contacts = []
    for rel, name, thresh, min_px in SHEETS:
        path = os.path.join(SRC, rel)
        if not os.path.isfile(path):
            print("!! нет файла: %s" % rel)
            continue
        im = Image.open(path).convert("RGBA")
        w, h = im.size
        small = im.getchannel("A").resize((w // DOWNSCALE, h // DOWNSCALE))
        px = small.load()
        alpha = [[px[x, y] for x in range(small.size[0])] for y in range(small.size[1])]
        blobs = find_blobs(alpha, w, h, thresh, min_px)
        blobs.sort(key=lambda b: (b[1] // 100, b[0]))
        outdir = os.path.join(OUT, name)
        os.makedirs(outdir, exist_ok=True)
        entries = []
        crops = []
        for i, (x0, y0, x1, y1, area) in enumerate(blobs):
            crop = im.crop((x0, y0, x1, y1))
            fn = "%02d.png" % (i + 1)
            crop.save(os.path.join(outdir, fn))
            entries.append({"file": fn, "bbox": [x0, y0, x1, y1], "w": x1 - x0, "h": y1 - y0})
            crops.append((fn, crop))
        with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump({"sheet": rel, "count": len(entries), "items": entries}, f, ensure_ascii=False, indent=1)
        manifest[name] = entries
        contacts.append((name, crops))
        print("%-18s %2d блобов" % (name, len(entries)))

    # контакт-листы: по одному на лист, индексы подписаны (для нейминга агентом)
    for name, crops in contacts:
        if not crops:
            continue
        cell = 110
        cols = 8
        rows = (len(crops) + cols - 1) // cols
        cs = Image.new("RGBA", (cols * cell, rows * (cell + 14)), (24, 24, 28, 255))
        d = ImageDraw.Draw(cs)
        for i, (fn, crop) in enumerate(crops):
            cx, cy = (i % cols) * cell, (i // cols) * (cell + 14)
            th = min(crop.height, cell - 6)
            tw = min(crop.width, cell - 6)
            sc = min(th / max(1, crop.height), tw / max(1, crop.width), 1.0)
            thumb = crop.resize((max(1, int(crop.width * sc)), max(1, int(crop.height * sc))))
            cs.paste(thumb, (cx + (cell - thumb.width) // 2, cy + (cell - thumb.height) // 2), thumb)
            d.text((cx + 4, cy + cell - 2), fn.replace(".png", ""), fill=(255, 220, 120, 255))
        cpath = os.path.join(OUT, "_contact_%s.png" % name)
        cs.save(cpath)
        print("контакт-лист: %s" % os.path.basename(cpath))


if __name__ == "__main__":
    sys.exit(main())
