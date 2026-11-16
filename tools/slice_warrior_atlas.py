# -*- coding: utf-8 -*-
"""Конвертер атласов жителей заказчика -> листы формата игры.

Атласы (F:\\...\\новые ассеты\\*.png): 1254x1254 RGBA, левая половина —
анфас (правая — вид сзади, в игре не используется: город зеркалит сам),
7 кадров в ряду. Ряды разделяются пустыми полосами (автоопределение).

Выход: assets/sprites/villagers/Kit<Имя>.png — кадры 32px, 10 колонок:
ряд 0 — стойка (4 кадра), ряд 1 — ходьба (6), ряд 2 — работа (4).
Ноги на y=30, видимый рост ~26px (единообразие персонажей v1.67.2).

Профессии-выходы (v1.71: строитель/лесоруб/фермер; v1.72: волна 2 —
ещё 13 профессий + староста в задел):
  строитель-воин -> KitBuilder (работа: верстак) + KitLumberjack (рубка)
  фермер         -> KitFarmer  (работа: землёй в присяде)
  кузнец         -> KitSmith     носильщик -> KitPorter
  лекарь         -> KitHealer    рыбак     -> KitFisher
  охотник        -> KitHunter    мастер    -> KitMaster (проф. crafter)
  старейшина-маг -> KitElder   (ЗАДЕЛ: староста в игре — голем, не проводится)
  тавернщик      -> KitBartender маг       -> KitAcolyte
  кузнец-дварф   -> KitArmorer   гном-кузнец -> KitSmelter
  купец          -> KitTrader    стражник  -> KitGuard
  шахтёр-гном    -> KitMiner
Не используются (RGB без альфы, фон белый): трактирщик (12), кузнец дварф (21);
дровосек-фэнтези (05) — нестандартная сетка, лесоруб остался на рубке строителя.
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
    # --- волна 2 «Жители кита» (v1.72): индексы полос ПРОНУМЕРОВАНЫ БЕЗ
    # фильтра пылинок (как их видит row_bands ниже) — сверены по превью
    ("Атлас анимаций средневекового кузнеца.png", {"idle": 1, "walk": 3,
                                                   "work": 4, "tag": "Smith"}),
    ("Атлас спрайтов бородатого носильщика.png", {"idle": 1, "walk": 2,
                                                  "work": 3, "tag": "Porter"}),
    ("Изображение ChatGPT 15 нояб. 2026 г., 17_52_45.png", {"idle": 0,
                                                            "walk": 3,
                                                            "work": 5,
                                                            "tag": "Healer"}),
    ("Лист спрайтов рыбака-ремесленника.png", {"idle": 0, "walk": 1,
                                               "work": 3, "tag": "Fisher"}),
    ("Лист спрайтов средневекового лучника.png", {"idle": 0, "walk": 5,
                                                  "work": 2, "tag": "Hunter"}),
    ("Пиксельный атлас мастера-кузнеца.png", {"idle": 0, "walk": 10,
                                              "work": 6, "tag": "Master"}),
    ("Пиксельный атлас старейшины-мага.png", {"idle": 0, "walk": 2,
                                              "work": 4, "tag": "Elder"}),
    ("Пиксельный атлас тавернщика.png", {"idle": 0, "walk": 1, "work": 5,
                                         "tag": "Bartender"}),
    ("Пиксельный спрайт-лист мага с заклинаниями.png", {"idle": 0, "walk": 1,
                                                        "work": 4,
                                                        "tag": "Acolyte"}),
    ("Спрайт-лист бородатого кузнеца-дварфа.png", {"idle": 0, "walk": 1,
                                                   "work": 4, "tag": "Armorer"}),
    ("Спрайт-лист гнома-кузнеца.png", {"idle": 0, "walk": 1, "work": 5,
                                       "tag": "Smelter"}),
    ("Спрайт-лист средневекового купца.png", {"idle": 0, "walk": 3,
                                              "work": 2, "tag": "Trader"}),
    ("Спрайт-лист средневекового стражника.png", {"idle": 0, "walk": 3,
                                                  "work": 6, "tag": "Guard"}),
    ("Спрайт-лист шахтёра-гнома.png", {"idle": 0, "walk": 1, "work": 4,
                                       "tag": "Miner"}),
]


def slice_frames(img, y0, y1, n, fig_w):
    """Кадры ряда: блобы фигур; слипшиеся блобы (шире 1.35 фигуры) режутся
    по «перетяжкам» — локальным минимумам вертикальной плотности (у части
    листов кита фигуры стоят вплотную, равная резка рождает кадры-
    «половинки» — билборд-баг v1.72/v1.75)."""
    import numpy as np
    band = img.crop((0, y0, img.size[0], y1 + 1))
    a = np.array(band.getchannel("A"))
    dens = (a > 8).sum(axis=0)
    filled = dens > 0
    w = len(filled)
    runs = []
    i = 0
    while i < w:
        if filled[i]:
            j = i
            while j + 1 < w and filled[j + 1]:
                j += 1
            runs.append([i, j])
            i = j + 1
        else:
            i += 1
    figs = []
    for x0, x1 in runs:
        bw = x1 - x0 + 1
        if bw < 0.3 * fig_w:
            continue   # пылинка/осколок в стороне от фигур
        if bw <= 1.35 * fig_w:
            figs.append((x0, x1))
            continue
        # перетяжки внутри слипшегося блоба
        seg = dens[x0:x1 + 1]
        peak = np.percentile(seg[seg > 0], 90)
        thin = seg < peak * 0.22
        cuts = []
        k = 0
        while k < len(thin):
            if thin[k]:
                g0 = k
                while k + 1 < len(thin) and thin[k + 1]:
                    k += 1
                if k - g0 + 1 <= 0.3 * fig_w:   # узкая перетяжка, не дыра
                    cuts.append(x0 + (g0 + k) // 2)
            k += 1
        if not cuts:
            figs.append((x0, x1))
            continue
        edges = [x0 - 1] + cuts + [x1 + 1]
        for t in range(len(edges) - 1):
            a0, a1 = edges[t] + 1, edges[t + 1] - 1
            if a1 - a0 + 1 >= 0.3 * fig_w:
                figs.append((a0, a1))
    if not figs:
        return []
    if len(figs) > n:
        step = len(figs) / float(n)
        figs = [figs[int(t * step)] for t in range(n)]
    frames = []
    for x0, x1 in figs:
        fr = band.crop((x0, 0, x1 + 1, band.size[1]))
        bbox = fr.getbbox()
        if bbox:
            fr = fr.crop(bbox)
        frames.append(fr)
    while len(frames) < n:
        frames.append(frames[len(frames) % max(1, len(frames))])
    return frames


def estimate_fig_w(img, bands, walk_idx):
    """Средняя ширина фигуры — медиана блобов walk-ряда (40-260px)."""
    import numpy as np
    y0, y1 = bands[walk_idx]
    band = img.crop((0, y0, img.size[0], y1 + 1))
    a = np.array(band.getchannel("A"))
    dens = (a > 8).sum(axis=0)
    filled = dens > 0
    ws = []
    i = 0
    while i < len(filled):
        if filled[i]:
            j = i
            while j + 1 < len(filled) and filled[j + 1]:
                j += 1
            if 40 <= j - i + 1 <= 260:
                ws.append(j - i + 1)
            i = j + 1
        else:
            i += 1
    if not ws:
        return 80
    ws.sort()
    return ws[len(ws) // 2]


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


def build_sheet(img, bands, rows_spec, name, fig_w):
    sheet = Image.new("RGBA", (FRAME * 10, FRAME * 4), (0, 0, 0, 0))
    counts = {}
    for row_idx, out_row, n in rows_spec:
        y0, y1 = bands[row_idx]
        frs = slice_frames(img, y0, y1, n, fig_w)
        counts[out_row] = len(frs)
        for i, fr in enumerate(frs):
            sheet.paste(fit_frame(fr), (i * FRAME, out_row * FRAME))
    path = os.path.join(OUT_DIR, name)
    sheet.save(path)
    print("%s %s  idle=%d walk=%d work=%d" % (
        name, sheet.size, counts.get(0, 0), counts.get(1, 0), counts.get(2, 0)))


def main():
    for fname, r in ATLAS_FILES:
        img = Image.open(os.path.join(SRC_DIR, fname)).convert("RGBA")
        img = img.crop((0, 0, img.size[0] // 2, img.size[1]))  # анфас — левая половина
        bands = row_bands(img)
        fig_w = estimate_fig_w(img, bands, r["walk"])
        common = [(r["idle"], 0, 4), (r["walk"], 1, 6), (r["work"], 2, 4)]
        build_sheet(img, bands, common, "Kit%s.png" % r["tag"], fig_w)
        if "work2" in r:
            build_sheet(img, bands, [
                (r["idle"], 0, 4), (r["walk"], 1, 6), (r["work2"], 2, 4)],
                "Kit%s.png" % r["tag2"], fig_w)


if __name__ == "__main__":
    main()
