# -*- coding: utf-8 -*-
"""Нарезчик биома «Лето» (v1.76): атлас заказчика «Биомы лето»
(1536×1024 RGBA, честная альфа) -> тайлы игры.

Выход:
  assets/sprites/env/summer/grass_S1..S6.png  — 6 тайлов травы 32×32
  assets/sprites/env/summer/fm_water_summer.png — полоса воды 192×96
      (6 кадров × 3 ряда, как fm_water.png)
  assets/sprites/env/summer/tree2_summer_*.png — деревья (компоненты)
  tools/_summer_contact_*.png — контрольные листы
"""
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

SRC = (r"F:\востановление кхорно юнитов\assets\ассеты домов"
       r"\новые ассеты монстров\Биомы лето"
       r"\Пиксельный атлас лесных и водных тайловета.png")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "assets", "sprites", "env", "summer")
TS = 32
PAD = 2


def main():
    os.makedirs(OUT, exist_ok=True)
    img = Image.open(SRC).convert("RGBA")
    W, H = img.size
    rgb = np.array(img)

    # --- 1) земляные тайлы: полные 32×32 клетки ---
    ground_cells = []
    for cy in range(H // TS):
        for cx in range(W // TS):
            cell = rgb[cy * TS:(cy + 1) * TS, cx * TS:(cx + 1) * TS]
            a = cell[:, :, 3]
            if a.min() > 200:                    # клетка полностью залита
                ground_cells.append((cx, cy, cell))
    # классификация по среднему цвету
    stats = []
    for cx, cy, cell in ground_cells:
        mean = cell[:, :, :3].reshape(-1, 3).mean(axis=0)
        stats.append((cx, cy, mean))
    greens = [(cx, cy, m) for cx, cy, m in stats
              if m[1] > m[0] + 8 and m[1] > m[2] + 8]   # зелёный доминирует
    blues = [(cx, cy, m) for cx, cy, m in stats
             if m[2] > m[0] + 10 and m[2] > m[1] + 10]  # вода
    # зелёные: САМЫЙ БОЛЬШОЙ связный кластер (поле травы рисуется единым
    # массивом — клетки внутри поля стыкуются между собой; тайлы из разных
    # полей дают квадратные швы). Из кластера берём 6 клеток: первую строку
    # поля + начало второй.
    cell_set = {(cx, cy) for cx, cy, _ in greens}
    best_set: set = set()
    for seed in list(cell_set):
        if seed in best_set:
            continue
        comp, q = set(), [seed]
        while q:
            c = q.pop()
            if c in comp or c not in cell_set:
                continue
            comp.add(c)
            x, y = c
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q.append((x + dx, y + dy))
        if len(comp) > len(best_set):
            best_set = comp
    # v1.76.2: берём ПЕРВОЕ зелёное поле листа (левый верхний угол —
    # светлая трава с белыми цветами): клетки стыкуются между собой и
    # дают яркую «летнюю» поляну, а не тёмный мох из соседних групп
    pick = [(cx, cy) for cy in range(0, 4) for cx in range(0, 4)
            if (cx, cy) in cell_set][:6]
    if len(pick) < 6:   # фолбэк: любой кластер
        for (cx, cy) in sorted(best_set):
            if len(pick) < 6 and (cx, cy) not in pick:
                pick.append((cx, cy))
    names = ["grass_S1", "grass_S2", "grass_S3", "grass_S4", "grass_S5", "grass_S6"]
    # v1.76.2: поле травы НЕ тайлится по вертикали (рисовано лентами) —
    # вертикальные швы были видны. Рецепт: сплошная заливка средним цветом
    # поля + фактура поля ПОВЕРХ с ослабленной альфой (центр 55%, края 10%)
    # — швы растворяются, фактура травинок остаётся.
    FEATHER = 8
    for (cx, cy), nm in zip(pick, names):
        cell = np.array(rgb[cy*TS:(cy+1)*TS, cx*TS:(cx+1)*TS])
        core = cell[:, :, :3].reshape(-1, 3).mean(axis=0).astype(np.uint8)
        fill = np.zeros((TS, TS, 4), np.uint8)
        fill[:, :, :3] = core
        fill[:, :, 3] = 255
        # маска фактуры: альфа поля ослабляется к краям (растворение швов)
        yy, xx = np.mgrid[0:TS, 0:TS]
        edge = np.minimum(np.minimum(xx, TS - 1 - xx),
                          np.minimum(yy, TS - 1 - yy)).astype(np.float32)
        ramp = 0.10 + 0.45 * np.clip(edge / float(FEATHER), 0.0, 1.0)
        cell[:, :, 3] = (cell[:, :, 3].astype(np.float32) * ramp).astype(np.uint8)
        # композит поля на заливку
        af = cell[:, :, 3:4].astype(np.float32) / 255.0
        comp = (cell[:, :, :3].astype(np.float32) * af
                + fill[:, :, :3].astype(np.float32) * (1.0 - af)).astype(np.uint8)
        out_tile = np.dstack([comp, np.full((TS, TS), 255, np.uint8)])
        Image.fromarray(out_tile).save(os.path.join(OUT, nm + ".png"))
        Image.fromarray(np.tile(core, (TS, TS, 1))).save(
            os.path.join(OUT, nm + "_fill.png"))
    print("трава: кластер %d клеток, взято %d из поля" % (len(best_set), len(pick)))

    # --- 2) вода: 18 синих клеток -> полоса 6 кадров x 3 ряда ---
    # v1.76.1: вода — 6 клеток ИЗ ОДНОЙ ГОРИЗОНТАЛЬНОЙ РЕКИ (cy=12, клетки
    # 1-4 и 6-7 — рисовались как сплошная река, стыкуются между собой),
    # не случайные 18 клеток (берега/пруд давали квадратные швы)
    river = [(1, 12), (2, 12), (3, 12), (4, 12), (6, 12), (7, 12)]
    river = [(cx, cy) for cx, cy in river if any(gx == cx and gy == cy for gx, gy, _ in blues)]
    # полоса 6 кадров x 3 ОДИНАКОВЫХ ряда: движок берёт variant = t.y % 3,
    # ряды 1-2 должны существовать (иначе вырез за краем полосы)
    strip = Image.new("RGBA", (TS * len(river), TS * 3), (0, 0, 0, 0))
    for i, (cx, cy) in enumerate(river):
        cell = Image.fromarray(rgb[cy*TS:(cy+1)*TS, cx*TS:(cx+1)*TS])
        for r in range(3):
            strip.paste(cell, (i * TS, r * TS))
    strip.save(os.path.join(OUT, "fm_water_summer.png"))
    print("вода: река %d клеток -> fm_water_summer.png (6x3)" % len(river))

    # --- 3) деревья/декор: компоненты нижней части листа ---
    y_decor = H // 2
    a = rgb[y_decor:, :, 3]
    fg = a > 40
    lab, n = ndimage.label(fg)
    comps = []
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        if ys.size < 900:
            continue
        comps.append((int(xs.min()), int(ys.min()) + y_decor,
                      int(xs.max()), int(ys.max()) + y_decor, int(ys.size)))
    comps.sort(key=lambda c: (c[1] // 120, c[0]))
    contact = Image.new("RGB", (10 * 130 + 10,
                                ((len(comps) + 9) // 10) * 160 + 10),
                        (40, 44, 48))
    dr = ImageDraw.Draw(contact)
    for k, (x0, y0, x1, y1, area) in enumerate(comps):
        crop = img.crop((max(0, x0 - PAD), max(0, y0 - PAD),
                         min(W, x1 + PAD + 1), min(H, y1 + PAD + 1)))
        crop.save(os.path.join(OUT, "decor_%02d.png" % k))
        sc = min(110.0 / crop.size[0], 120.0 / crop.size[1])
        t = crop.resize((max(1, int(crop.size[0] * sc)),
                         max(1, int(crop.size[1] * sc))), Image.LANCZOS)
        x = 10 + (k % 10) * 130
        y = 10 + (k // 10) * 160
        contact.paste(t, (x + (110 - t.size[0]) // 2, y), t)
        dr.text((x + 4, y + 126), "%02d h%d" % (k, y1 - y0),
                fill=(255, 220, 120))
    contact.save(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "_summer_contact.png"))
    print("декор-компонентов:", len(comps), "-> _summer_contact.png")


if __name__ == "__main__":
    main()
