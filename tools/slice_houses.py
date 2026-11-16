# -*- coding: utf-8 -*-
"""Нарезчик новых листов домов заказчика (v1.73, волна «Новые ассеты домов»).

Источник: F:\\...\\ассеты домов\\Новые ассеты домов\\*.png — 6 листов RGB
БЕЗ альфы. Три вида фона снимаются затопкой от краёв (flood fill):
  white    — белый/серый фон (листы крепостей 1536x1024);
  magenta  — пурпур #FF00FF (постройки деревенского фэнтези);
  checker  — запечённая «шахматка» светло-серых тонов (3 листа 1254x1254).
Затопка обязательна: светлые окна/камень внутри арта окружены тёмным
контуром и не должны стать прозрачными.

Выход: assets/sprites/buildings_new/<лист>_<номер>.png (кроп с полем 4px)
+ tools/_houses_contact_<лист>.png (нумерованный контрольный лист).
Детерминирован: только кропы и пороговые кеи.
"""
import os
from collections import deque

import numpy as np
from PIL import Image
from scipy import ndimage

SRC_DIR = (r"F:\востановление кхорно юнитов\assets"
           r"\ассеты домов\Новые ассеты домов")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "assets", "sprites", "buildings_new")
PAD = 4
MIN_AREA = 1500        # мельче — пыль/осколки
GAP_MERGE = 10         # обломки ближе этого к крупной фигуре клеятся к ней

# файл -> вид фона
SHEETS = {
    "07c35422-df68-40b3-b73e-f9077fc74ce5.png": "white",
    "Пиксельные крепости и магические святилища.png": "white",
    "Пиксельные постройки деревенского фэнтези.png": "magenta",
    "Пиксельный атлас славянских деревенских домов.png": "checker",
    "Пиксельный лист средневековых мастерских.png": "checker",
    "Пиксельный набор славянских деревенских построек.png": "checker",
}
SHEET_SHORT = {
    "07c35422-df68-40b3-b73e-f9077fc74ce5.png": "fort",
    "Пиксельные крепости и магические святилища.png": "sanct",
    "Пиксельные постройки деревенского фэнтези.png": "fancy",
    "Пиксельный атлас славянских деревенских домов.png": "slav",
    "Пиксельный лист средневековых мастерских.png": "workshop",
    "Пиксельный набор славянских деревенских построек.png": "village",
}


def bg_mask(rgb: np.ndarray, kind: str) -> np.ndarray:
    """Маска «похоже на фон» по цвету."""
    r = rgb[:, :, 0].astype(np.int16)
    g = rgb[:, :, 1].astype(np.int16)
    b = rgb[:, :, 2].astype(np.int16)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = mx - mn
    if kind == "magenta":
        return (r > 170) & (b > 170) & (g < 140)
    # white/checker: светлый малонасыщенный (оба тона шахматки 219-255)
    return (mx >= 200) & (sat <= 30)


def key_flood(rgb: np.ndarray, kind: str) -> np.ndarray:
    """True = фон. magenta/white — кей ГЛОБАЛЬНЫЙ: пурпур заперт и внутри
    фигур (колодец, грядка), светлая шахматка — внутри арок ворот (листы
    fort/sanct); арт таких цветов не содержит (окна тёплые, камень
    фактурный). checker — только затопка от краёв (внутри фигур legit
    светлые тона)."""
    cand = bg_mask(rgb, kind)
    if kind == "magenta":
        key = cand
        grown = ndimage.binary_dilation(key, iterations=2)
        r = rgb[:, :, 0].astype(np.int16)
        g = rgb[:, :, 1].astype(np.int16)
        b = rgb[:, :, 2].astype(np.int16)
        halo = grown & (g < (np.minimum(r, b) - 24))
        return key | halo
    if kind == "white":
        return cand
    lab, n = ndimage.label(cand)
    border_labels = set(np.unique(np.concatenate((
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]))))
    border_labels.discard(0)
    return np.isin(lab, list(border_labels))


def components(fg: np.ndarray) -> list:
    """Связные компоненты арта: [(bbox, area)]. Мелочь возле крупной
    фигуры (дым, флюгер) клеится к ней через GAP_MERGE."""
    lab, n = ndimage.label(fg)
    comps = []
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        area = int(ys.size)
        if area < 60:                     # единичные пиксели — сразу прочь
            continue
        comps.append({"x0": int(xs.min()), "y0": int(ys.min()),
                      "x1": int(xs.max()), "y1": int(ys.max()), "a": area})
    big = [c for c in comps if c["a"] >= MIN_AREA]
    small = [c for c in comps if c["a"] < MIN_AREA]
    # мелочь: приращиваем к ближайшей крупной фигуре, если почти касается
    for s in small:
        best, best_d = None, GAP_MERGE + 1
        for c in big:
            dx = max(c["x0"] - s["x1"], s["x0"] - c["x1"], 0)
            dy = max(c["y0"] - s["y1"], s["y0"] - c["y1"], 0)
            d = max(dx, dy)
            if d < best_d:
                best, best_d = c, d
        if best is not None:
            best["x0"] = min(best["x0"], s["x0"])
            best["y0"] = min(best["y0"], s["y0"])
            best["x1"] = max(best["x1"], s["x1"])
            best["y1"] = max(best["y1"], s["y1"])
    big.sort(key=lambda c: (c["y0"] // 160, c["x0"]))
    return big


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    index = []
    for fname, kind in SHEETS.items():
        short = SHEET_SHORT[fname]
        img = Image.open(os.path.join(SRC_DIR, fname)).convert("RGB")
        rgb = np.array(img)
        fg = ~key_flood(rgb, kind)
        comps = components(fg)
        rgba = np.dstack([rgb, np.where(fg, 255, 0).astype(np.uint8)])
        sheet_out = Image.fromarray(rgba, "RGBA")
        crops = []
        for k, c in enumerate(comps):
            x0 = max(0, c["x0"] - PAD); y0 = max(0, c["y0"] - PAD)
            x1 = min(img.size[0], c["x1"] + PAD + 1)
            y1 = min(img.size[1], c["y1"] + PAD + 1)
            crop = sheet_out.crop((x0, y0, x1, y1))
            name = "%s_%02d.png" % (short, k)
            crop.save(os.path.join(OUT, name))
            crops.append((name, crop, c))
            index.append((short, k, c))
        # контрольный лист с номерами
        tile_w = 220
        rows = []
        row = []
        for name, crop, c in crops:
            sc = min(1.0, (tile_w - 10) / crop.size[0],
                     150.0 / crop.size[1])
            thumb = crop.resize((max(1, int(crop.size[0] * sc)),
                                 max(1, int(crop.size[1] * sc))),
                                Image.LANCZOS)
            row.append((name.split("_")[1][:2], thumb))
            if len(row) == 6:
                rows.append(row)
                row = []
        if row:
            rows.append(row)
        ch = max(max(t.size[1] for _, t in r) for r in rows) + 26
        sheet = Image.new("RGB", (6 * (tile_w + 8) + 8,
                                  len(rows) * ch + 8), (40, 44, 48))
        from PIL import ImageDraw
        dr = ImageDraw.Draw(sheet)
        for ri, r in enumerate(rows):
            for ci, (num, t) in enumerate(r):
                x = 8 + ci * (tile_w + 8)
                y = 8 + ri * ch
                sheet.paste(t, (x, y), t)
                dr.text((x + 4, y + t.size[1] + 2), num, fill=(255, 220, 120))
        sheet.save(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "_houses_contact_%s.png" % short))
        print("%s: фигур=%d" % (short, len(crops)))
    print("всего фигур:", len(index))


if __name__ == "__main__":
    main()
