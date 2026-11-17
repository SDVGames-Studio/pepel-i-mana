# -*- coding: utf-8 -*-
"""Контакт-лист атласа героя ПОКАДРОВО (v1.75.7): каждый кадр отдельной
ячейкой с номером ряда/кадра — заказчик подписывает, какие кадры брать
в idle/attack/etc, агент собирает полосы по подписи."""
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

SRC = (r"F:\востановление кхорно юнитов\assets\ассеты домов\новые ассеты монстров"
       r"\главный герой\Пиксельный атлас мрачного рыцаря.png")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hero_frames")

ROWS = [(7, 127), (133, 252), (261, 377), (384, 501), (512, 594),
        (612, 725), (737, 852), (863, 982), (997, 1066), (1081, 1165),
        (1179, 1254)]
COLS = 12
CELL_W, CELL_H = 240, 190


def key_checker(rgb):
    r = rgb[:, :, 0].astype(np.int16)
    g = rgb[:, :, 1].astype(np.int16)
    b = rgb[:, :, 2].astype(np.int16)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    cand = (mx >= 200) & ((mx - mn) <= 30)
    lab, n = ndimage.label(cand)
    border = set(np.unique(np.concatenate((
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]))))
    border.discard(0)
    return ~np.isin(lab, list(border))


def main():
    os.makedirs(OUT, exist_ok=True)
    img = Image.open(SRC).convert("RGB")
    rgb = np.array(img)
    fg = key_checker(rgb)
    rgba = np.dstack([rgb, np.where(fg, 255, 0).astype(np.uint8)])
    sheet_img = Image.fromarray(rgba, "RGBA")
    cw = img.size[0] / float(COLS)
    for part, rows in ((0, range(0, 6)), (1, range(6, 11))):
        W = 130 + COLS * (CELL_W + 8) + 8
        H = len(rows) * (CELL_H + 34) + 8
        out = Image.new("RGB", (W, H), (38, 42, 46))
        dr = ImageDraw.Draw(out)
        y = 8
        for ri in rows:
            y0, y1 = ROWS[ri]
            dr.text((10, y + CELL_H // 2 - 26), "РЯД", fill=(255, 210, 100))
            dr.text((10, y + CELL_H // 2 - 6), str(ri), fill=(255, 210, 100))
            for ci in range(COLS):
                cell = sheet_img.crop((int(ci * cw), y0,
                                       int((ci + 1) * cw), y1 + 1))
                sc = min((CELL_W - 14) / cell.size[0],
                         (CELL_H - 22) / cell.size[1])
                t = cell.resize((max(1, int(cell.size[0] * sc)),
                                 max(1, int(cell.size[1] * sc))),
                                Image.LANCZOS)
                x = 130 + ci * (CELL_W + 8)
                out.paste(t, (x + (CELL_W - t.size[0]) // 2, y + 4), t)
                dr.text((x + 8, y + CELL_H + 6),
                        "кадр %d" % ci, fill=(160, 220, 255))
            y += CELL_H + 34
        path = os.path.join(OUT, "hero_frames_%d.png" % part)
        out.save(path)
        print(path, out.size)
    # отдельные кадры в папку (если захочется рассмотреть крупно)
    for ri, (y0, y1) in enumerate(ROWS):
        for ci in range(COLS):
            cell = sheet_img.crop((int(ci * cw), y0, int((ci + 1) * cw), y1 + 1))
            cell.save(os.path.join(OUT, "r%02d_c%02d.png" % (ri, ci)))
    print("кадры:", len(ROWS) * COLS)


if __name__ == "__main__":
    main()
