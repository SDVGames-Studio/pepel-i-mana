#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# [REUSE] Волна 2026-11-24: мельница и пшеница. Блоб-нарезка листа
# «Пиксельный набор фермерски» (порог альфы 60 против грязи фона),
# проводка в env/ + buildings/. Где ещё применимо: следующие листы.
import json
import os
import sys

from PIL import Image, ImageDraw

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = (r"F:\востановление кхорно юнитов\assets\ассеты домов\новые ассеты монстров"
       r"\главный герой\новые биомы\подземелье чудь\предметы\деревья\животные"
       r"\кладбише\руины чуди\дял скал\идолы\растения\улий\мельница и пшеница"
       r"\Пиксельный набор фермерски.png")
OUT = os.path.join(BASE, "assets", "sprites", "wave1124")
ENV = os.path.join(BASE, "assets", "sprites", "env")
BLD = os.path.join(BASE, "assets", "sprites", "buildings")
DS = 4

# порядок блобов (ряды сверху вниз, слева направо)
NAMES = [
    "wheat_stage_1", "wheat_stage_2", "wheat_stage_3", "wheat_stage_4", "wheat_stage_5",
    "stubble", "harvest_pile", "hay_stook", "hay_rick", "harvest_cart",
    "mill_a", "mill_b", "mill_c", "millstone", "grain_sacks",
]


def blobs(im, thresh=60, min_px=400, ds=DS):
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


def main():
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(SRC).convert("RGBA")
    bs = blobs(im)
    bs.sort(key=lambda b: (b[1] // 100, b[0]))
    print("блобов:", len(bs), "ожидалось:", len(NAMES))
    if len(bs) != len(NAMES):
        # контакт-лист для разбора расхождений
        cell = 110
        cols = 8
        rows = (len(bs) + cols - 1) // cols
        cs = Image.new("RGBA", (cols * cell, rows * (cell + 14)), (24, 24, 28, 255))
        d = ImageDraw.Draw(cs)
        for i, (x0, y0, x1, y1) in enumerate(bs):
            cx, cy = (i % cols) * cell, (i // cols) * (cell + 14)
            th = im.crop((x0, y0, x1, y1))
            sc = min((cell - 6) / max(1, th.height), (cell - 6) / max(1, th.width), 1.0)
            thumb = th.resize((max(1, int(th.width * sc)), max(1, int(th.height * sc))))
            cs.paste(thumb, (cx + (cell - thumb.width) // 2, cy + (cell - thumb.height) // 2), thumb)
            d.text((cx + 4, cy + cell - 2), str(i + 1), fill=(255, 220, 120, 255))
        cs.save(os.path.join(OUT, "_contact_mill.png"))
        print("!! контакт-лист: _contact_mill.png — сверить имена")
    manifest = []
    for i, (x0, y0, x1, y1) in enumerate(bs):
        name = NAMES[i] if i < len(NAMES) else "mill_unknown_%d" % (i + 1)
        crop = im.crop((x0, y0, x1, y1))
        crop.save(os.path.join(OUT, "%02d.png" % (i + 1)))
        manifest.append({"file": "%02d.png" % (i + 1), "name": name,
                         "bbox": [x0, y0, x1, y1], "w": x1 - x0, "h": y1 - y0})
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"sheet": SRC, "count": len(manifest), "items": manifest},
                  f, ensure_ascii=False, indent=1)
    # проводка: env (весь сет) + мельница-А как здание
    for m in manifest:
        src = os.path.join(OUT, m["file"])
        if m["name"] == "mill_a":
            dst = os.path.join(BLD, "мельница.png")
            shutil_copy(src, dst)
            print("buildings/мельница.png")
        else:
            shutil_copy(src, os.path.join(ENV, m["name"] + ".png"))
            print("env/%s.png" % m["name"])


def shutil_copy(src, dst):
    import shutil
    shutil.copyfile(src, dst)


if __name__ == "__main__":
    sys.exit(main())
