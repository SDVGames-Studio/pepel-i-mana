# -*- coding: utf-8 -*-
"""Нарезка НОВОГО героя «красный плащ» (v1.79): листы заказчика из
«новые ассеты монстров/главный герой» -> полосы assets/sprites/hero/
knight_*.png (кадры 120×80, низ = линия земли, масштаб по стойке).

Листы (все 1536×1024, кадры в один ряд колонками):
  рыцарь в красном плаще     — стойка (айдл, 6 кадров)
  спрайт бегущего тёмного    — бег профиль (6)
  шесть кадров бегущего в плаще — бег второй (6)
  анимация удара             — атака (6, с дугой)
  пиксельный рывок           — рывок (~5)
  заклинание крови           — каст (6)
  анимация падения           — смерть (6, кадр 2 — урон)

Запуск: python tools/slice_hero2.py
"""
import os
import re

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = (r"F:\востановление кхорно юнитов\assets\ассеты домов"
        r"\новые ассеты монстров\главный герой")
OUT = os.path.join(HERE, "..", "assets", "sprites", "hero")
FRAME_W, FRAME_H = 120, 80
TARGET_H = 76          # высота фигуры в кадре (как hero_user_frames)
PAD = 4

SHEETS = [
    ("Пиксельный рыцарь в красном плаще.png", "idle"),
    ("Пиксельный спрайт бегущего тёмного рыцаря.png", "run"),
    ("Шесть кадров бегущего рыцаря в плаще.png", "run2"),
    ("Пиксельная анимация удара тёмного рыцаря.png", "attack"),
    ("Пиксельный рывок мрачного рыцаря.png", "roll"),
    ("Пиксельный рыцарь_ заклинание крови.png", "cast"),
    ("Пиксельная анимация падения тёмного рыцаря.png", "death"),
]

STRIP_NAMES = {
    "idle": "knight_Idle",
    "run": "knight_Run",
    "run2": "knight_RunDown",
    "attack": "knight_Attack",
    "roll": "knight_Roll",
    "cast": "knight_Cast",
    "death": "knight_Death",
}


def sheet_frames(path):
    """Кадры листа: колонки-блобы, слипшиеся разрезаются по минимуму
    плотности (valley). Возвращает список bbox (x0, y0, x1, y1)."""
    rgb = np.array(Image.open(path).convert("RGBA"))
    occ = rgb[:, :, 3] > 40
    cols = occ.any(axis=0).astype(np.int8)
    # блобы по колонкам
    runs, start = [], None
    for x, v in enumerate(cols):
        if v and start is None:
            start = x
        elif not v and start is not None:
            if x - start > 20:
                runs.append((start, x))
            start = None
    if start is not None and len(cols) - start > 20:
        runs.append((start, len(cols)))
    widths = [b - a for a, b in runs]
    med = float(np.median(widths)) if widths else 0.0
    frames = []
    for a, b in runs:
        if b - a > med * 1.55 and med > 0:
            # слипшиеся: valley-разрез по минимумам плотности колонок
            dens = occ[:, a:b].sum(axis=0).astype(np.float32)
            k = max(1, int(round((b - a) / med)))
            cuts = [a]
            for i in range(1, k):
                lo = a + int((b - a) * (i - 0.42) / k)
                hi = a + int((b - a) * (i + 0.42) / k)
                local = dens[lo - a:hi - a]
                cut = lo + int(np.argmin(local)) if len(local) else lo
                cuts.append(cut)
            cuts.append(b)
            for i in range(k):
                frames.append((cuts[i], cuts[i + 1]))
        else:
            frames.append((a, b))
    # bbox по вертикали для каждого кадра
    out = []
    for a, b in frames:
        zone = occ[:, a:b]
        rows = zone.any(axis=1)
        ys = np.where(rows)[0]
        if len(ys) == 0:
            continue
        out.append((a, int(ys[0]), b, int(ys[-1]) + 1))
    return out


def make_tile(img, scale, out_name):
    """Кадр -> 120×80: фигура масштабируется по высоте, низ на землю,
    центр по X."""
    fw, fh = img.size
    nw = max(1, int(round(fw * scale)))
    nh = max(1, int(round(fh * scale)))
    r = img.resize((nw, nh), Image.LANCZOS)
    tile = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    cx = (FRAME_W - nw) // 2
    ground = FRAME_H - 4   # линия земли (низ кадра, как в hero_user_frames)
    tile.alpha_composite(r, (cx, ground - nh))
    return tile


def main():
    # 1) собрать все кадры всех листов, ЕДИНЫЙ масштаб по стойке (idle)
    data = {}
    idle_max_h = 0
    for fname, key in SHEETS:
        path = os.path.join(BASE, fname)
        if not os.path.exists(path):
            print("!! нет листа:", fname)
            continue
        boxes = sheet_frames(path)
        imgs = []
        for (x0, y0, x1, y1) in boxes:
            img = Image.open(path).convert("RGBA").crop(
                (x0, y0, x1, y1))
            imgs.append(img)
            if key == "idle":
                idle_max_h = max(idle_max_h, y1 - y0)
        data[key] = imgs
        print("%-46s кадров=%d (ширины %s)" % (
            fname[:46], len(imgs),
            str([b - a for a, _y, b, _y2 in boxes])))
    scale = TARGET_H / float(max(1, idle_max_h))
    print("единый масштаб: %.3f (стойка %dpx)" % (scale, idle_max_h))
    # 2) полосы
    for key, imgs in data.items():
        strip = Image.new("RGBA", (FRAME_W * max(1, len(imgs)), FRAME_H),
                          (0, 0, 0, 0))
        for i, img in enumerate(imgs):
            tile = make_tile(img, scale, key)
            strip.alpha_composite(tile, (i * FRAME_W, 0))
        name = STRIP_NAMES[key]
        strip.save(os.path.join(OUT, name + ".png"))
        print("полоса %s: %d кадров" % (name, len(imgs)))
    # 3) урон — 2-й кадр падения (падает на колено)
    if "death" in data and len(data["death"]) >= 2:
        img = data["death"][1]
        tile = make_tile(img, scale, "hurt")
        tile.save(os.path.join(OUT, "knight_Hurt.png"))
        print("полоса knight_Hurt: 1 кадр (падение, кадр 2)")
    # 4) контакт-лист
    strip_files = sorted(set(STRIP_NAMES.values()))
    total_w = sum(FRAME_W * (4 if f != "knight_Hurt" else 1) and FRAME_W * 8
                  for f in strip_files)
    contact = Image.new("RGBA", (FRAME_W * 8, FRAME_H * len(strip_files)),
                        (40, 44, 48, 255))
    for i, f in enumerate(strip_files):
        p = os.path.join(OUT, f + ".png")
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGBA")
        contact.alpha_composite(im, (0, i * FRAME_H))
    contact.save(os.path.join(HERE, "_hero2_contact.png"))
    print("контакт: tools/_hero2_contact.png")


if __name__ == "__main__":
    main()
