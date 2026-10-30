# -*- coding: utf-8 -*-
"""Природа 2.0 (v1.39.0): нарезка и подгонка ассетов ForgottenMemories
(русские папки заказчика `F:\\востановление кхорно юнитов\\assets\\ассеты природы`)
под мастер-гамму «Пепла и Маны», плюс генерация серо-синего камня.

Выход (assets/sprites/env + props):
  n2_water_lake.png / n2_water_river.png / n2_water_swamp.png — полосы
      из 3 бесшовных тайлов 32x32 (вода пака, яркость перемаплена на
      градиент мастера: озеро глубже, река светлее, болото — мутная зелень);
  n2_stone1..3.png — серо-синий камень 32x32 (генерация: пятна шума,
      фасеты, трещины, дизер-зерно — техника make_video_grass.py);
  tree2_red/teal/birch/pine/willow.png — деревья пака (компоненты альфы
      Trees_seperated.png), обесцвечены ~12% под приглушённую гамму;
  props/bush2_a..d.png, props/stone2_a..b.png — кусты и камни (Props.png).

Детерминировано: перезапуск = те же файлы. Превью — tools/nature2_preview.png.
Запуск: python tools/make_nature2.py
"""
import os
import sys

from PIL import Image, ImageDraw
import numpy as np

SRC = r"F:\востановление кхорно юнитов\assets\ассеты природы\ForgottenMemories"
OUT_ENV = os.path.join("assets", "sprites", "env")
OUT_PROPS = os.path.join("assets", "sprites", "props")
TS = 32


# ---------- утилиты ----------
def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def grad_lut(stops, n=256):
    """LUT из стопов [(pos, hex)...] — для перемапа яркости на палитру."""
    xs = np.array([p for p, _ in stops])
    cs = np.array([hex2rgb(c) for _, c in stops], dtype=float)
    pos = np.linspace(0.0, 1.0, n)[:, None]
    out = np.zeros((n, 3))
    for ch in range(3):
        out[:, ch] = np.interp(pos[:, 0], xs, cs[:, ch])
    return out


def remap_to_gradient(img, lut, target_mean):
    """Яркость пикселя -> градиент палитры; средний цвет подтягивается
    к целевому (аддитивный сдвиг) — тон пака ложится в гамму игры."""
    a = np.array(img.convert("RGBA"), dtype=float)
    lum = (0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]) / 255.0
    idx = np.clip((lum * 255).astype(int), 0, 255)
    rgb = lut[idx]                       # h,w,3
    shift = np.array(target_mean, dtype=float) - rgb.reshape(-1, 3).mean(axis=0)
    rgb = np.clip(rgb + shift, 0, 255)
    out = np.dstack([rgb, a[:, :, 3:4]]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def desaturate(img, sat=0.88, val=0.96):
    """Приглушить сочность пака под «пасмурную» гамму мастера."""
    a = np.array(img.convert("RGBA"), dtype=float)
    rgb = a[:, :, :3]
    gray = rgb @ np.array([0.299, 0.587, 0.114])
    rgb = gray[:, :, None] + (rgb - gray[:, :, None]) * sat
    rgb = np.clip(rgb * val, 0, 255)
    return Image.fromarray(np.dstack([rgb, a[:, :, 3:4]]).astype(np.uint8), "RGBA")


def components(img, min_area=120):
    """Связные компоненты альфы -> [(bbox, area)]. Простая BFS по сетке."""
    a = np.array(img.convert("RGBA"))[:, :, 3] > 16
    h, w = a.shape
    seen = np.zeros((h, w), dtype=bool)
    out = []
    for sy in range(h):
        for sx in range(w):
            if not a[sy, sx] or seen[sy, sx]:
                continue
            stack = [(sy, sx)]
            seen[sy, sx] = True
            x0 = x1 = sx
            y0 = y1 = sy
            area = 0
            while stack:
                y, x = stack.pop()
                area += 1
                x0 = min(x0, x); x1 = max(x1, x)
                y0 = min(y0, y); y1 = max(y1, y)
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and a[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if area >= min_area:
                out.append(((x0, y0, x1 + 1, y1 + 1), area))
    return out


def crop_alpha(img, box, pad=2):
    """Вырезать спрайт по bbox с прозрачным полем pad и обрезкой пустых краёв."""
    x0, y0, x1, y1 = box
    c = img.crop((max(0, x0 - pad), max(0, y0 - pad), min(img.width, x1 + pad),
                  min(img.height, y1 + pad)))
    return c


# ---------- вода ----------
def build_water(sheet):
    """3 бесшовных чистых тайла из блока воды (B1: rows 288/320/352 при x=32)
    -> по полосе на тип воды с перемапом яркости на градиент мастера."""
    tiles = [sheet.crop((32, 288, 64, 320)),
             sheet.crop((64, 320, 96, 352)),
             sheet.crop((96, 352, 128, 384))]
    kinds = {
        "lake":  ([(0.0, "#173f52"), (0.45, "#2e7391"), (1.0, "#5fb0c9")], (63, 135, 181)),
        "river": ([(0.0, "#1f5f70"), (0.45, "#3f93ac"), (1.0, "#8fd0da")], (87, 178, 212)),
        "swamp": ([(0.0, "#24301f"), (0.45, "#43523a"), (1.0, "#6d7d55")], (70, 82, 58)),
    }
    for kind, (stops, mean) in kinds.items():
        lut = grad_lut(stops)
        strip = Image.new("RGBA", (TS * 3, TS), (0, 0, 0, 0))
        for i, t in enumerate(tiles):
            strip.paste(remap_to_gradient(t, lut, mean), (i * TS, 0))
        strip.save(os.path.join(OUT_ENV, "n2_water_%s.png" % kind))
        print("  n2_water_%s.png %s" % (kind, strip.size))


# ---------- камень (генерация, серо-синий мастер) ----------
def _hash_noise(x, y, n, salt=0):
    v = int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791))
    return abs(v) % max(1, n)


def _noise2(xf, yf, n, salt):
    """Билинейный value-noise (как в city_terrain.gd) — пятна без сетки."""
    x0, y0 = int(xf), int(yf)
    fx, fy = xf - x0, yf - y0
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    a = _hash_noise(x0, y0, n, salt)
    b = _hash_noise(x0 + 1, y0, n, salt)
    c = _hash_noise(x0, y0 + 1, n, salt)
    d = _hash_noise(x0 + 1, y0 + 1, n, salt)
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy


def _periodic_noise(x, y, period, n, salt):
    """Value-noise, периодичный по тайлу (решётка mod period) — без швов."""
    xf = x * period / float(TS)
    yf = y * period / float(TS)
    x0, y0 = int(xf), int(yf)
    fx, fy = xf - x0, yf - y0
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    def lat(ix, iy):
        return _hash_noise((ix % period) + salt * 131, (iy % period) + salt * 57, n, salt)
    a = lat(x0, y0)
    b = lat(x0 + 1, y0)
    c = lat(x0, y0 + 1)
    d = lat(x0 + 1, y0 + 1)
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy


def build_stone():
    """Серо-синий камень (мастер-гамма #5a6470/#8a94a0): пятна шума +
    фасеты + 1-2 трещины + дизер-зерно. Бесшовность: шум периодичен по
    тайлу, фасеты и трещины рисуются с переносом на ±TS."""
    base = hex2rgb("#6a7482")
    for v in range(3):
        img = Image.new("RGBA", (TS, TS))
        px = img.load()
        for y in range(TS):
            for x in range(TS):
                n = _periodic_noise(x, y, 8, 100, 41 + v) / 99.0
                tone = (n - 0.5) * 0.16
                dith = (_hash_noise(x, y, 4, v + 3) - 1.5) / 48.0
                rgb = tuple(max(0, min(255, int(base[c] * (1.0 + tone + dith))))
                            for c in range(3))
                px[x, y] = rgb + (255,)
        d = ImageDraw.Draw(img)
        offs = [(dx, dy) for dx in (-TS, 0, TS) for dy in (-TS, 0, TS)]
        # фасеты: светлые/тёмные сколы — с переносом через край тайла
        for i in range(3):
            h = _hash_noise(v * 31 + i, i * 17, 1000, 91)
            cx = h % TS
            cy = (h // 31) % TS
            r = 2 + h % 3
            col = hex2rgb("#98a2b0") if i % 2 == 0 else hex2rgb("#4c5664")
            for ox, oy in offs:
                d.ellipse((cx + ox - r, cy + oy - r * 0.7, cx + ox + r, cy + oy + r * 0.7),
                          fill=col + (45,))
        # трещина: одна короткая прямая с изломом (кривые «крючки»
        # читались как мусор — урок v1.39.0)
        for i in range(1):
            h = _hash_noise(v * 7 + i, 3, 1000, 13)
            x0 = h % TS
            y0 = (h // 17) % TS
            pts = [(x0, y0), (x0 + 5 + h % 4, y0 + 3 + h % 3),
                   (x0 + 11 + h % 5, y0 + 4 + h % 4)]
            for ox, oy in offs:
                d.line([((px_ + ox) % TS, (py_ + oy) % TS) for px_, py_ in pts],
                       fill="#3d4650", width=1)
        img.save(os.path.join(OUT_ENV, "n2_stone%d.png" % (v + 1)))
        print("  n2_stone%d.png" % (v + 1))


# ---------- деревья и пропсы ----------
def build_trees():
    """Trees_seperated.png: связные компоненты -> 5 деревьев (2 ряда:
    ряд 1 — компактные, ряд 2 — пышные; берём самые крупные по рядам).
    Порядок в ряду: красный, бирюзовый, жёлтая берёза, сосна, ива."""
    sheet = Image.open(os.path.join(SRC, "Trees_seperated.png")).convert("RGBA")
    comps = components(sheet, min_area=250)
    # ряды по y-центру: компоненты с cy < 320 — верхний ряд
    upper = sorted([c for c in comps if (c[0][1] + c[0][3]) / 2 < 320],
                   key=lambda c: c[0][0])
    lower = sorted([c for c in comps if (c[0][1] + c[0][3]) / 2 >= 320],
                   key=lambda c: c[0][0])
    # деревья — крупные (ширина > 36) и не тень (тень почти чёрная);
    # пни мелкие — пропускаем
    def is_tree(c):
        box = c[0]
        if box[2] - box[0] <= 36:
            return False
        region = np.array(sheet.crop(box).convert("RGBA"), dtype=float)
        vis = region[:, :, 3] > 32
        if not vis.any():
            return False
        lum = (region[:, :, :3].mean(axis=2) * vis).sum() / vis.sum()
        mx = region[:, :, :3].max(axis=2)
        return lum > 58.0 and float(mx[vis].mean()) > 80.0
    up_trees = [c for c in upper if is_tree(c)]
    lo_trees = [c for c in lower if is_tree(c)]
    names = ["red", "teal", "birch", "pine"]
    # ива — последняя (самая широкая) в ряду
    sat_map = {"red": (0.80, 0.94), "teal": (0.88, 0.97),
               "birch": (0.86, 0.95), "pine": (0.88, 0.95),
               "willow": (0.90, 0.96)}
    picks = {}
    for i, name in enumerate(names):
        if i < len(up_trees):
            picks[name] = up_trees[i][0]
    # ива: самая широкая из нижнего ряда (среди «не тени»)
    if lo_trees:
        willow = max(lo_trees, key=lambda c: c[0][2] - c[0][0])
        picks["willow"] = willow[0]
    for name, box in picks.items():
        spr = crop_alpha(sheet, box, pad=2)
        sat, val = sat_map[name]
        spr = desaturate(spr, sat, val)
        spr.save(os.path.join(OUT_ENV, "tree2_%s.png" % name))
        print("  tree2_%s.png %s" % (name, spr.size))


def build_props():
    """Props.png: кусты (5 цветных рядов справа — берём 4) и камни (слева)."""
    sheet = Image.open(os.path.join(SRC, "Props.png")).convert("RGBA")
    comps = components(sheet, min_area=90)
    bushes = []
    stones = []
    for box, area in comps:
        x0, y0, x1, y1 = box
        w, h = x1 - x0, y1 - y0
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        region = np.array(sheet.crop(box).convert("RGBA"), dtype=float)
        vis = region[:, :, 3] > 32
        if not vis.any():
            continue
        rgb = region[:, :, :3][vis]
        mx = rgb.max(axis=1)
        mn = rgb.min(axis=1)
        sat = float(np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0).mean())
        lum = float(rgb.mean())
        if cx > 480 and 28 <= w <= 90 and 28 <= h <= 90:
            bushes.append((box, area, cy))
        elif cx < 200 and sat < 0.34 and area >= 300 and w <= 90 and h <= 60:
            stones.append((box, area))   # серые кластеры — камни, не деревья
    # кусты: по одному на цветной ряд (ряды ~ по y)
    bushes.sort(key=lambda b: (b[2], -b[1]))
    rows = []
    for box, area, cy in bushes:
        if not rows or cy - rows[-1][0] > 40:
            rows.append((cy, box))
    names = ["a", "b", "c", "d"]
    for i, (_, box) in enumerate(rows[:4]):
        spr = desaturate(crop_alpha(sheet, box), 0.85, 0.95)
        spr.save(os.path.join(OUT_PROPS, "bush2_%s.png" % names[i]))
        print("  props/bush2_%s.png %s" % (names[i], spr.size))
    # камни: два самых крупных кластера слева
    stones.sort(key=lambda s: -s[1])
    for i in range(min(2, len(stones))):
        spr = desaturate(crop_alpha(sheet, stones[i][0]), 0.85, 0.95)
        spr.save(os.path.join(OUT_PROPS, "stone2_%s.png" % "ab"[i]))
        print("  props/stone2_%s.png %s" % ("ab"[i], spr.size))


# ---------- превью ----------
def build_preview():
    names = ["n2_water_lake", "n2_water_river", "n2_water_swamp"]
    tiles = ["n2_stone1", "n2_stone2", "n2_stone3"]
    trees = ["tree2_red", "tree2_teal", "tree2_birch", "tree2_pine", "tree2_willow"]
    props = ["bush2_a", "bush2_b", "bush2_c", "bush2_d", "stone2_a", "stone2_b"]
    imgs = [os.path.join(OUT_ENV, n + ".png") for n in names + tiles + trees]
    imgs += [os.path.join(OUT_PROPS, n + ".png") for n in props]
    cell = 96
    cols = 6
    rows = (len(imgs) + cols - 1) // cols
    prev = Image.new("RGBA", (cell * cols, cell * rows), (52, 58, 66, 255))
    d = ImageDraw.Draw(prev)
    for i, p in enumerate(imgs):
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGBA")
        im.thumbnail((cell - 8, cell - 8), Image.NEAREST)
        x = (i % cols) * cell
        y = (i // cols) * cell
        prev.alpha_composite(im, (x + (cell - im.width) // 2, y + (cell - im.height) // 2))
        d.rectangle((x, y, x + cell - 1, y + cell - 1), outline=(30, 34, 40, 255))
    prev.save("tools/nature2_preview.png")
    print("  tools/nature2_preview.png")


def main():
    os.makedirs(OUT_ENV, exist_ok=True)
    os.makedirs(OUT_PROPS, exist_ok=True)
    print("Природа 2.0: нарезка ForgottenMemories ->")
    build_water(Image.open(os.path.join(SRC, "WaterTiles-6frames.png")).convert("RGBA"))
    build_stone()
    build_trees()
    build_props()
    build_preview()
    print("Готово.")


if __name__ == "__main__":
    sys.exit(main())
