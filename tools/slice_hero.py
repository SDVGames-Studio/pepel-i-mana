# -*- coding: utf-8 -*-
"""Герой: лист «мрачного рыцаря» (1254x1254, шахматка запечена) -> полосы
assets/sprites/hero/knight_*.png (кадры 120x80, фигура по низу кадра).

Ряды листа (сверху): 0 стойка (12, кадры 1 и 3 — вспышки урона, их
пропускаем), 1 бег, 4 присед/кувырок, 5 удары мечом, 10 смерть лёжа.
Полосы для игры: Idle 10 кадров, Run 12, Attack 6, Roll 12, Death ~10.
KNIGHT_CHAR_H в hero.gd = высота фигуры в новом кадре.
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = (r"F:\востановление кхорно юнитов\assets"
       r"\ассеты домов\новые ассеты монстров"
       r"\главный герой\Пиксельный атлас мрачного рыцаря.png")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "assets", "sprites", "hero")
FRAME_W, FRAME_H = 120, 80
TARGET_H = 76          # фигура в кадре (KNIGHT_CHAR_H в hero.gd)
COLS = 12

# anim -> (границы ряда y0,y1, список кадров или None=все)
# ряды листа (низкая плотность между ними измерена, см. CHANGELOG v1.74):
ROWS = [(7, 127), (133, 252), (261, 377), (384, 501), (512, 594),
        (612, 725), (737, 852), (863, 982), (997, 1066), (1081, 1165),
        (1179, 1254)]
STRIPS = {
    "knight_Idle":   (ROWS[0], [0, 2, 4, 5, 6, 7, 8, 9, 10, 11]),
    "knight_Run":    (ROWS[1], None),
    "knight_Attack": (ROWS[5], [5, 6, 7, 8, 9, 10]),
    "knight_Roll":   (ROWS[4], None),
    "knight_Death":  (ROWS[10], None),
}


def key_checker(rgb: np.ndarray) -> np.ndarray:
    """Фон = светлый малонасыщенный, связанный с краем."""
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
    return np.isin(lab, list(border))


def fit_frame(rgba: Image.Image) -> Image.Image:
    """Кадр 120x80: фигура вписана по высоте, ноги на нижнем крае."""
    bbox = rgba.getbbox()
    if bbox:
        rgba = rgba.crop(bbox)
    sc = min(TARGET_H / float(rgba.size[1]),
             (FRAME_W - 8) / float(rgba.size[0]))
    nw = max(1, int(rgba.size[0] * sc))
    nh = max(1, int(rgba.size[1] * sc))
    fig = rgba.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    canvas.paste(fig, ((FRAME_W - nw) // 2, FRAME_H - nh), fig)
    return canvas


def main() -> None:
    img = Image.open(SRC).convert("RGB")
    rgb = np.array(img)
    fg = ~key_checker(rgb)
    rgba_img = np.dstack([rgb, np.where(fg, 255, 0).astype(np.uint8)])
    sheet = Image.fromarray(rgba_img, "RGBA")
    cw = img.size[0] / float(COLS)
    for name, (band, picks) in STRIPS.items():
        y0, y1 = band
        idxs = list(range(COLS)) if picks is None else picks
        strip = Image.new("RGBA", (FRAME_W * len(idxs), FRAME_H),
                          (0, 0, 0, 0))
        for i, k in enumerate(idxs):
            cell = sheet.crop((int(k * cw), y0, int((k + 1) * cw), y1 + 1))
            strip.paste(fit_frame(cell), (i * FRAME_W, 0))
        strip.save(os.path.join(OUT, name + ".png"))
        print(name, strip.size, len(idxs), "кадров")


if __name__ == "__main__":
    main()
