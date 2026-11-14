# -*- coding: utf-8 -*-
"""Конвертер атласов жителей заказчика -> листы формата игры.

Атласы (F:\\...\\новые ассеты\\*.png): 1254x1254 RGBA, левая половина —
анфас (правая — вид сзади, в игре не используется: город зеркалит сам),
7 кадров в ряду. Ряды разделяются пустыми полосами (автоопределение).

Выход: assets/sprites/villagers/Kit<Имя>.png — кадры 32px, 10 колонок:
ряд 0 — стойка (4 кадра), ряд 1 — ходьба (6), ряд 2 — работа (4).
Ноги на y=30, видимый рост ~26px (единообразие персонажей v1.67.2).

Профессии-выходы:
  строитель-воин -> KitBuilder (работа: верстак) + KitLumberjack (рубка)
  фермер         -> KitFarmer  (работа: землёй в присяде)
"""
import os
from PIL import Image

SRC_DIR = (r"F:\востановление кхорно юнитов\assets"
           r"\ассеты домов\новые ассеты")
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                       "assets", "sprites", "villagers")

FRAME = 32
FEET_Y = 30.0
TARGET_H = 26.0

# файл -> индексы рядов (по порядку сверху вниз): стойка / шаг / работа /
# доп. работа (для второй профессии из того же атласа)
ATLAS_FILES = [
    ("Пиксельный атлас строителя-воина.png", {"idle": 0, "walk": 1, "work": 2,
                                              "work2": 3, "tag": "Builder",
                                              "tag2": "Lumberjack"}),
    ("Пиксельный фермер_ полный набор анимаций.png", {"idle": 0, "walk": 1,
                                                      "work": 5, "tag": "Farmer"}),
]


def slice_frames(img, y0, y1, n):
    w = img.size[0]
    strip_w = w // 2          # анфас — левая половина
    fw = strip_w / 7.0        # 7 кадров в ряду
    frames = []
    for i in range(n):
        fr = img.crop((int(i * fw), y0, int((i + 1) * fw), y1))
        bbox = fr.getbbox()
        if bbox:
            fr = fr.crop(bbox)
        frames.append(fr)
    return frames


def fit_frame(fr):
    w, h = fr.size
    sc = TARGET_H / float(h)
    nw, nh = max(1, int(round(w * sc))), max(1, int(round(h * sc)))
    fr2 = fr.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    canvas.paste(fr2, ((FRAME - nw) // 2, int(round(FEET_Y - nh))), fr2)
    return canvas


def row_bands(img):
    import numpy as np
    a = np.array(img.getchannel("A"))
    rows = (a > 8).sum(axis=1)
    filled = [y for y in range(len(rows)) if rows[y] > 0]
    bands = []
    s0 = prev = filled[0]
    for y in filled[1:]:
        if y != prev + 1:
            bands.append((s0, prev))
            s0 = y
        prev = y
    bands.append((s0, prev))
    return bands


def build_sheet(img, bands, rows_spec, name):
    sheet = Image.new("RGBA", (FRAME * 10, FRAME * 4), (0, 0, 0, 0))
    for row_idx, out_row, n in rows_spec:
        y0, y1 = bands[row_idx]
        for i, fr in enumerate(slice_frames(img, y0, y1, n)):
            sheet.paste(fit_frame(fr), (i * FRAME, out_row * FRAME))
    path = os.path.join(OUT_DIR, name)
    sheet.save(path)
    print(name, sheet.size)


def main():
    for fname, r in ATLAS_FILES:
        img = Image.open(os.path.join(SRC_DIR, fname)).convert("RGBA")
        bands = row_bands(img)
        common = [(r["idle"], 0, 4), (r["walk"], 1, 6), (r["work"], 2, 4)]
        build_sheet(img, bands, common, "Kit%s.png" % r["tag"])
        if "work2" in r:
            build_sheet(img, bands, [
                (r["idle"], 0, 4), (r["walk"], 1, 6), (r["work2"], 2, 4)],
                "Kit%s.png" % r["tag2"])


if __name__ == "__main__":
    main()
