# -*- coding: utf-8 -*-
"""v2.9 «Рыцарь-герой: листы заказчика 26.11» — резак полос hero.
Листы 1536x1024 RGBA (альфа чистая) -> блобы по колонной проекции
(6 групп с зазором >=12px) -> нормализация в клетку 120x80
(фигура 74px высотой, по центру, ноги к низу) -> горизонтальные полосы
assets/sprites/hero/knight_*.png. Боковой бег листа смотрит ВЛЕВО —
отзеркаливается (конвенция: полосы ВПРАВО).
Запуск: python -I tools/slice_hero_v29.py
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
SRC = r"F:\востановление кхорно юнитов\assets\ассеты домов\новые ассеты монстров\главный герой"
OUT = os.path.join(GAME, "assets", "sprites", "hero")
CELL_W, CELL_H = 120, 80
CHAR_H = 74.0
MIN_GAP = 12
MIN_AREA = 400

# (лист заказчика, выходная полоса, зеркалить)
SHEETS = [
    ("Пиксельный рыцарь в красном плаще.png", "knight_Idle", False),
    ("Пиксельный спрайт бегущего тёмного рыцаря.png", "knight_Run", True),
    ("Шесть кадров бегущего рыцаря в плаще.png", "knight_RunUp", False),
    ("Шесть кадров бегущего тёмного рыцаря.png", "knight_RunDown", False),
    ("Пиксельная анимация удара тёмного рыцаря.png", "knight_Attack", False),
    ("Пиксельный рыцарь_ заклинание крови.png", "knight_Cast", False),
    ("Пиксельная анимация падения тёмного рыцаря.png", "knight_Death", False),
    ("Пиксельный рывок мрачного рыцаря.png", "knight_Roll", False),
]


def groups_by_columns(alpha, min_gap=MIN_GAP):
    """Группы кадров: колонки, где есть alpha>=60, с зазором >= min_gap."""
    occ = (alpha >= 60).any(axis=0)
    groups = []
    start = None
    gap = 0
    for x, on in enumerate(occ):
        if on:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                groups.append((start, x - gap + 1))
                start = None
                gap = 0
    if start is not None:
        groups.append((start, len(occ)))
    return groups


def six_groups(alpha, W):
    """Ровно 6 групп: убывающий зазор, затем ровные полосы W/6
    (эффект удара перелезает через зазор и слипает соседей)."""
    for g in (MIN_GAP, 8, 6, 4, 2):
        gs = groups_by_columns(alpha, g)
        if len(gs) == 6:
            return gs, "gap=%d" % g
    band = W // 6
    return [(i * band, (i + 1) * band) for i in range(6)], "равные полосы"


def main():
    # эталон масштаба: самая высокая «чистая» фигура (макс blob айдла)
    ref_h = None
    for src, out, flip in SHEETS:
        im = Image.open(os.path.join(SRC, src)).convert("RGBA")
        a = np.array(im)
        alpha = a[:, :, 3]
        gs, how = six_groups(alpha, im.size[0])
        print("  %s: группировка %s" % (src[:36], how))
        assert len(gs) == 6, "%s: групп %d, ждём 6" % (src, len(gs))
        hs = []
        for x0, x1 in gs:
            sub = alpha[:, x0:x1]
            ys = np.where((sub >= 60).any(axis=1))[0]
            hs.append(int(ys[-1] - ys[0] + 1))
        if ref_h is None:
            ref_h = float(max(hs))
            print("эталон высоты фигуры: %d px (лист %s)" % (int(ref_h), src))
        scale = CHAR_H / ref_h
        cells = []
        for x0, x1 in gs:
            sub = a[:, x0:x1]
            m = sub[:, :, 3] >= 60
            ys, xs = np.where(m)
            y0, y1, xx0, xx1 = ys.min(), ys.max(), xs.min(), xs.max()
            crop = Image.fromarray(sub[y0:y1 + 1, xx0:xx1 + 1])
            w, h = crop.size
            s = min(scale, 114.0 / float(w))
            nw, nh = max(1, int(round(w * s))), max(1, int(round(h * s)))
            if flip:
                crop = crop.transpose(Image.FLIP_LEFT_RIGHT)
            crop = crop.resize((nw, nh), Image.LANCZOS)
            cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            cell.paste(crop, ((CELL_W - nw) // 2, CELL_H - 2 - nh), crop)
            cells.append(cell)
        strip = Image.new("RGBA", (CELL_W * len(cells), CELL_H), (0, 0, 0, 0))
        for i, c in enumerate(cells):
            strip.paste(c, (i * CELL_W, 0))
        dst = os.path.join(OUT, out + ".png")
        strip.save(dst)
        print("ok: %s <- %s (%d кадров, %dx%d)" % (out, src[:28], len(cells), strip.size[0], strip.size[1]))


if __name__ == "__main__":
    main()
