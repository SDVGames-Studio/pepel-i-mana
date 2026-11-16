# -*- coding: utf-8 -*-
"""Нарезчик листов монстров и героя заказчика (v1.74, волна «Монстры»).

Источник: F:\\...\\новые ассеты монстров\\*.png (+ главный герой\\).
Листы RGBA, но альфа не заполнена — фон запечён в цвет: пурпур #FF00FF,
белый/шахматка, на «Без названия» — чёрный + пурпур. Кеи:
  magenta — глобальный кей пурпура (+кайма), допускает запертый пурпур;
  white   — затопка от краёв по светлому малонасыщенному;
  darkmix — затопка тёмного + глобальный кей пурпура.
Фигуры — связные компоненты (scipy.ndimage.label), мелочь клеится к
ближней крупной фигуре.

Выход: assets/sprites/monsters_new/<лист>_<номер>.png
       + tools/_mon_contact_<лист>.png (нумерованный контрольный лист).
"""
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

SRC = (r"F:\востановление кхорно юнитов\assets"
       r"\ассеты домов\новые ассеты монстров")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "assets", "sprites", "monsters_new")
PAD = 4
MIN_AREA = 800
GAP_MERGE = 10

SHEETS = {
    "atlas_monsters_03_uglin_bandit_forest_undead_alpha.png": ("magenta", "m03"),
    "atlas_monsters_04_nightcreature_chicken_deathspike_werewolf_bannik_polevik_vodyanoy_kikimora.png": ("magenta", "m04"),
    "atlas_monsters_05_rgba_1024.png": ("magenta", "m05"),
    "atlas_ordinary_monsters_36_rgba_1024.png": ("magenta", "m36"),
    "Атлас тёмных фэнтезийных монстров.png": ("white", "darkfant"),
    "Без названия.png": ("darkmix", "unnamed"),
    "Пиксельные боссы тёмного фэнтези.png": ("white", "bosses_a"),
    "Пиксельные боссы_ мрачная коллекция спрайтов.png": ("white", "bosses_b"),
    "Пиксельные монстры на пурпурном фоне.png": ("magenta", "purple"),
    "Пиксельный атлас готических существ.png": ("white", "gothic"),
    "Пиксельный атлас монстров и животных.png": ("white", "beasts"),
    "Пиксельный атлас тёмных монстров (1).png": ("magenta", "dark1"),
    "Пиксельный атлас тёмных монстров.png": ("magenta", "dark0"),
    "Пиксельный атлас тёмных фэнтези-монстров.png": ("white", "darkf2"),
    "Пиксельный атлас тёмных чудовищ.png": ("white", "chudov"),
    "Пиксельный бестиарий тёмного фэнтези.png": ("white", "bestiar"),
    os.path.join("главный герой", "Пиксельный атлас мрачного рыцаря.png"): ("white", "hero"),
}


def bg_mask(rgb: np.ndarray, kind: str) -> np.ndarray:
    r = rgb[:, :, 0].astype(np.int16)
    g = rgb[:, :, 1].astype(np.int16)
    b = rgb[:, :, 2].astype(np.int16)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = mx - mn
    magenta = (r > 170) & (b > 170) & (g < 140)
    if kind == "magenta":
        return magenta
    if kind == "white":
        return (mx >= 200) & (sat <= 30)
    # darkmix: тёмный фон ИЛИ пурпур
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    return (lum <= 26) | magenta


def key_flood(rgb: np.ndarray, kind: str) -> np.ndarray:
    cand = bg_mask(rgb, kind)
    if kind == "magenta":
        grown = ndimage.binary_dilation(cand, iterations=2)
        r = rgb[:, :, 0].astype(np.int16)
        g = rgb[:, :, 1].astype(np.int16)
        b = rgb[:, :, 2].astype(np.int16)
        halo = grown & (g < (np.minimum(r, b) - 24))
        return cand | halo
    # white / darkmix: только связанное с краем
    lab, n = ndimage.label(cand)
    border = set(np.unique(np.concatenate((
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]))))
    border.discard(0)
    key = np.isin(lab, list(border))
    if kind == "darkmix":
        # пурпур глобально (в т.ч. запертый)
        key = key | bg_mask(rgb, "magenta")
    return key


def components(fg: np.ndarray) -> list:
    lab, n = ndimage.label(fg)
    comps = []
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        area = int(ys.size)
        if area < 60:
            continue
        comps.append({"x0": int(xs.min()), "y0": int(ys.min()),
                      "x1": int(xs.max()), "y1": int(ys.max()), "a": area})
    big = [c for c in comps if c["a"] >= MIN_AREA]
    small = [c for c in comps if c["a"] < MIN_AREA]
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
    big.sort(key=lambda c: (c["y0"] // 200, c["x0"]))
    return big


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for fname, (kind, short) in SHEETS.items():
        img = Image.open(os.path.join(SRC, fname)).convert("RGB")
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
            crop.save(os.path.join(OUT, "%s_%02d.png" % (short, k)))
            crops.append((k, crop))
        cols, TW, CH = 8, 150, 190
        rows = (len(crops) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * (TW + 6) + 6, rows * CH + 6),
                          (40, 44, 48))
        dr = ImageDraw.Draw(sheet)
        for i, (k, crop) in enumerate(crops):
            sc = min((TW - 10) / crop.size[0], (CH - 26) / crop.size[1], 1.0)
            t = crop.resize((max(1, int(crop.size[0] * sc)),
                             max(1, int(crop.size[1] * sc))), Image.LANCZOS)
            x = 6 + (i % cols) * (TW + 6)
            y = 6 + (i // cols) * CH
            sheet.paste(t, (x + (TW - t.size[0]) // 2, y + 4), t)
            dr.text((x + 6, y + CH - 18), "%02d" % k, fill=(255, 220, 120))
        sheet.save(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "_mon_contact_%s.png" % short))
        print("%-9s фигур=%d" % (short, len(crops)))


if __name__ == "__main__":
    main()
