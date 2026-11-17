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
    # v1.75.4: ряды атласа ПЕРЕСМОТРЕНЫ по зуму: 0 стойка, 1 бег ВБОК,
    # 2 бег ВВЕРХ (спиной), 3 бег ВНИЗ (анфас), 4 кувырок (старт — стойка
    # с мечом), 5 удары, 6 каст, 7 взрыв, 8 ПРИСЕД, 9 урон, 10 смерть.
    # Полосы смотрят ВЛЕВО.
    "knight_Idle":   (ROWS[0], [0, 2, 4, 6, 8, 10]),   # дыхание, 6 кадров
    "knight_Run":    (ROWS[1], None),                  # вбок
    "knight_RunUp":  (ROWS[2], None),                  # спиной вверх
    "knight_RunDown": (ROWS[3], None),                 # анфас вниз
    "knight_Roll":   (ROWS[4], [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
    "knight_Ready":  (ROWS[4], [0, 1]),                # боевая стойка (перед кувырком)
    "knight_Attack": (ROWS[5], [5, 6, 7, 8, 9, 10]),
    "knight_Cast":   (ROWS[6], None),
    "knight_Explode": (ROWS[7], None),
    "knight_Crouch": (ROWS[8], None),                  # присед
    "knight_Hurt":   (ROWS[9], None),                  # урон
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


def main() -> None:
    """Единый масштаб на ВЕСЬ лист (v1.75.2): нормируем по union-высоте
    idle-ряда, клетки режем целиком и выравниваем по низу кадра. Раньше
    каждый кадр кадрировался и масштабировался своим фактором — фигура
    пульсировала ростом/пропорциями (герой «дёргался»)."""
    img = Image.open(SRC).convert("RGB")
    rgb = np.array(img)
    fg = ~key_checker(rgb)
    rgba_img = np.dstack([rgb, np.where(fg, 255, 0).astype(np.uint8)])
    sheet = Image.fromarray(rgba_img, "RGBA")
    cw = img.size[0] / float(COLS)
    idle_y0, idle_y1 = STRIPS["knight_Idle"][0]
    idle_union = sheet.crop((0, idle_y0, img.size[0], idle_y1 + 1)).getbbox()
    scale = TARGET_H / float(idle_union[3] - idle_union[1])
    print("idle union:", idle_union, "scale: %.3f" % scale)
    for name, (band, picks) in STRIPS.items():
        y0, y1 = band
        idxs = list(range(COLS)) if picks is None else picks
        strip = Image.new("RGBA", (FRAME_W * len(idxs), FRAME_H),
                          (0, 0, 0, 0))
        for i, k in enumerate(idxs):
            cell = sheet.crop((int(k * cw), y0, int((k + 1) * cw), y1 + 1))
            nw = max(1, int(cell.size[0] * scale))
            nh = max(1, int(cell.size[1] * scale))
            if nh > FRAME_H:      # ряд с широкими взмахами (атака/смерть)
                nw = max(1, int(nw * float(FRAME_H) / nh))
                nh = FRAME_H
            cell = cell.resize((nw, nh), Image.LANCZOS)
            strip.paste(cell, (i * FRAME_W + (FRAME_W - nw) // 2,
                               FRAME_H - nh))   # низ клетки = линия земли
        strip.save(os.path.join(OUT, name + ".png"))
        print(name, strip.size, len(idxs), "кадров")


if __name__ == "__main__":
    main()
