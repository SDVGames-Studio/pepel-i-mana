# -*- coding: utf-8 -*-
# Деревья «как в видео jess::codes (dual-grid)»: пухлые кроноблобы из
# перекрывающихся кругов, чистый тёмный контур, 4 тона (тень/основа/свет/
# блик) с дизерингом Байера 4×4, светлые мазки-листья сверху-слева, тёмный
# подбой снизу-справа, короткий ствол с корневым раструбом.
# Породы: дуб ×2, сосна ×2, берёза ×2 (белый ствол в крапинку), осеннее,
# липа ×2 (цветки), плодовое (красные яблоки).
# Запуск: python tools/make_video_trees.py (PIL). Результат:
#   assets/sprites/env/tree_*.png + tools/video_preview.png (полоса на траве)
import os
import math
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ENV = os.path.join(GAME, "assets", "sprites", "env")

BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def _h(x, y, n=10000, s=0):
    v = (x * 374761393 + y * 668265263 + s * 974634757) & 0x7FFFFFFF
    v ^= v >> 13
    return v % n


def _mix(c1, c2, t):
    return tuple(int(round(a + (b - a) * t)) for a, b in zip(c1, c2))


# ---------------------------------------------------------------- палитры ----
PAL_OAK = {
    "k": (24, 42, 24), "d": (40, 86, 40), "m": (60, 118, 52),
    "l": (88, 152, 70), "h": (122, 186, 88),
    "T": (100, 70, 44), "t": (74, 50, 30), "u": (126, 92, 58),
}
PAL_OAK2 = dict(PAL_OAK)
PAL_OAK2["m"] = (66, 124, 56)
PAL_OAK2["l"] = (96, 158, 74)

PAL_PINE = {
    "k": (16, 36, 24), "d": (22, 62, 40), "m": (36, 92, 54),
    "l": (54, 122, 70), "h": (78, 152, 86),
    "T": (86, 60, 36), "t": (62, 42, 26), "u": (110, 78, 48),
}
PAL_PINE2 = dict(PAL_PINE)
PAL_PINE2["m"] = (30, 82, 48)
PAL_PINE2["l"] = (46, 110, 64)

PAL_BIRCH = {
    "k": (26, 50, 30), "d": (64, 106, 54), "m": (98, 142, 68),
    "l": (136, 174, 88), "h": (178, 206, 112),
    "W": (214, 214, 200), "w2": (240, 240, 228), "b": (52, 52, 50),
    "k2": (66, 68, 64), "sh": (176, 178, 168),
}
PAL_BIRCH2 = dict(PAL_BIRCH)
PAL_BIRCH2["m"] = (90, 134, 62)
PAL_BIRCH2["h"] = (188, 212, 118)

PAL_AUTUMN = {
    "k": (52, 28, 14), "d": (134, 62, 22), "m": (190, 102, 32),
    "l": (228, 146, 46), "h": (250, 192, 76), "r": (198, 54, 44),
    "T": (100, 70, 44), "t": (74, 50, 30), "u": (126, 92, 58),
}
PAL_LIME = {
    "k": (28, 46, 22), "d": (58, 100, 42), "m": (86, 134, 58),
    "l": (118, 166, 76), "h": (152, 198, 96), "f": (246, 240, 180),
    "T": (110, 80, 50), "t": (82, 58, 36), "u": (138, 102, 62),
}
PAL_LIME2 = dict(PAL_LIME)
PAL_LIME2["m"] = (94, 142, 62)
PAL_LIME2["l"] = (128, 174, 82)

PAL_FRUIT = {
    "k": (24, 42, 24), "d": (38, 80, 38), "m": (54, 110, 48),
    "l": (82, 144, 66), "h": (114, 178, 84),
    "r": (212, 58, 50), "R": (240, 118, 90),
    "T": (100, 70, 44), "t": (74, 50, 30), "u": (126, 92, 58),
}


# ------------------------------------------------------------- ствол ---------
def draw_trunk(px, W, H, cx, top_y, pal, birch=False, seed=0):
    """Ствол с раструбом у корней; top_y прячется под кроной."""
    bottom = H - 1
    rows = bottom - top_y + 1
    for i in range(rows):
        y = top_y + i
        prog = i / max(1, rows - 1)
        half = 2 if not birch else 1
        if prog > 0.72:                       # корневой раструб
            half += int((prog - 0.72) * 8)    # к земле шире
        for x in range(cx - half - 1, cx + half + 2):
            if x < 0 or x >= W:
                continue
            if x == cx - half - 1 or x == cx + half + 1:
                px[x, y] = pal["k2"] if birch else pal["k"]
            elif x >= cx + half:
                px[x, y] = pal["b"] if (birch and _h(x, y, 5, seed) < 2) else (
                    pal["sh"] if birch else pal["t"])
            elif x <= cx - half + (0 if birch else 0):
                px[x, y] = pal["w2"] if birch else pal["u"]
            else:
                if birch:
                    px[x, y] = pal["b"] if _h(x, y * 3, 7, seed) < 1 else pal["W"]
                else:
                    px[x, y] = pal["T"]
    # земля у корней чуть темнее (контакт)
    for x in range(cx - 4, cx + 5):
        if 0 <= x < W and _h(x, bottom, 3, seed) < 1:
            px[x, bottom] = pal["k"]


# ------------------------------------------------------- круглая крона -------
def build_round_tree(W, H, cx, circles, pal, trunk_top, seed,
                     sparkles=True, flowers=None, fruits=0, autumn_mix=0,
                     birch=False):
    """Крона-«облако» из кругов + ствол. circles — [(cx,cy,r),]."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    inside = set()
    ys = [cy - r for _, cy, r in circles]
    ye = [cy + r for _, cy, r in circles]
    for y in range(max(0, min(ys) - 1), min(H, max(ye) + 2)):
        for x in range(W):
            for (ccx, ccy, r) in circles:
                if (x - ccx) ** 2 + (y - ccy) ** 2 <= r * r:
                    inside.add((x, y))
                    break

    def boundary(p):
        x, y = p
        return any((x + dx, y + dy) not in inside
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))

    bounds = {p for p in inside if boundary(p)}
    # центр кроны для светового градиента
    gx = sum(p[0] for p in inside) / float(len(inside))
    gy = sum(p[1] for p in inside) / float(len(inside))
    rad = max(math.hypot(p[0] - gx, p[1] - gy) for p in inside)
    for (x, y) in inside:
        nx = (x - gx) / rad
        ny = (y - gy) / rad
        v = 0.52 - 0.34 * nx - 0.30 * ny          # свет сверху-слева
        # лопастные бугры: близость к центру своего круга чуть светлит
        for (ccx, ccy, r) in circles:
            dd = math.hypot(x - ccx, y - ccy) / r
            if dd < 0.55:
                v += 0.10 * (1.0 - dd / 0.55)
                break
        v += (BAYER4[y % 4][x % 4] / 16.0 - 0.5) * 0.34   # дизеринг
        if (x, y) in bounds:
            if x + y >= gx + gy:
                v = -1.0                              # тёмный подбой края
            else:
                v = 1.0                               # светлая верхняя кромка
        if v > 0.62:
            c = pal["h"]
        elif v > 0.47:
            c = pal["l"]
        elif v > 0.30:
            c = pal["m"]
        else:
            c = pal["d"]
        if autumn_mix and c in (pal["m"], pal["l"]) and _h(x, y, 100, seed) < autumn_mix:
            c = pal["r"]
        px[x, y] = c + (255,)
    # контур поверх
    for (x, y) in bounds:
        px[x, y] = pal["k"] + (255,)
    # светлые мазки-листья в верхней-левой половине
    if sparkles:
        for i in range(10):
            sx = int(gx + (_h(i, seed, 100, 1) / 100.0 - 0.5) * rad * 1.4)
            sy = int(gy + (_h(seed, i, 100, 2) / 100.0 - 0.55) * rad * 1.4)
            if (sx, sy) in inside and (sx, sy) not in bounds \
                    and sx + sy < gx + gy + rad * 0.3:
                col = pal["h"] if _h(i, 3, 2, seed) == 0 else pal["l"]
                px[sx, sy] = col + (255,)
                if (sx + 1, sy) in inside and (sx + 1, sy) not in bounds:
                    px[sx + 1, sy] = _mix(col, pal["m"], 0.5) + (255,)
    # цветки (липа): кремовые пары точек
    if flowers:
        for i in range(flowers):
            fx = int(gx + (_h(i, seed, 100, 3) / 100.0 - 0.5) * rad * 1.7)
            fy = int(gy + (_h(seed, i, 100, 4) / 100.0 - 0.5) * rad * 1.7)
            if (fx, fy) in inside and (fx, fy) not in bounds:
                px[fx, fy] = pal["f"] + (255,)
                if (fx, fy + 1) in inside:
                    px[fx, fy + 1] = _mix(pal["f"], (255, 255, 255), 0.5) + (255,)
    # яблоки: 2×2 — три красных + светлый уголок
    for i in range(fruits):
        for tries in range(20):
            fx = int(gx + (_h(i * 7 + tries, seed, 100, 5) / 100.0 - 0.5) * rad * 1.8)
            fy = int(gy + (_h(seed, i * 7 + tries, 100, 6) / 100.0 - 0.5) * rad * 1.8)
            if (fx, fy) in inside and (fx, fy) not in bounds \
                    and (fx + 1, fy) in inside and (fx, fy + 1) in inside:
                px[fx, fy] = pal["R"] + (255,)
                px[fx + 1, fy] = pal["r"] + (255,)
                px[fx, fy + 1] = pal["r"] + (255,)
                px[fx + 1, fy + 1] = _mix(pal["r"], pal["k"], 0.35) + (255,)
                break
    draw_trunk(px, W, H, cx, trunk_top, pal, birch=birch, seed=seed)
    return img


# ------------------------------------------------------------- сосна ---------
def build_pine(W, H, cx, tiers, pal, trunk_top, seed):
    """Ярусная конусная крона: tiers — [(apex_y, base_y, half_w),] сверху вниз."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    inside = set()
    tier_of = {}
    for ti, (ay, by, hw) in enumerate(tiers):
        for y in range(max(0, ay), min(H, by + 1)):
            span = max(1, by - ay)
            half = int(round(hw * float(y - ay) / span))
            if _h(y, ti, 4, seed) < 2:            # зазубрина края яруса
                half = max(0, half - 1)
            for x in range(cx - half, cx + half + 1):
                if 0 <= x < W and (x, y) not in inside:
                    inside.add((x, y))
                    tier_of[(x, y)] = ti
    bounds = {p for p in inside
              if any((p[0] + dx, p[1] + dy) not in inside
                     for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
    n_tiers = len(tiers)
    for (x, y) in inside:
        ti = tier_of[(x, y)]
        ay, by, hw = tiers[ti]
        span = max(1, by - ay)
        half = max(1.0, float(hw * (y - ay)) / span)
        nx = (x - cx) / half
        v = 0.50 - 0.26 * nx                      # левая сторона светлее
        v += 0.14 * (n_tiers - 1 - ti) / max(1, n_tiers - 1) * 2 - 0.07
        v += (BAYER4[y % 4][x % 4] / 16.0 - 0.5) * 0.24
        prog = float(y - ay) / span
        if prog > 0.8:                            # подбой нижней кромки яруса
            v -= 0.22
        if (x, y) in bounds:
            v = -1.0 if (x + y >= cx + y) else 0.8
        if v > 0.60:
            c = pal["h"]
        elif v > 0.46:
            c = pal["l"]
        elif v > 0.29:
            c = pal["m"]
        else:
            c = pal["d"]
        px[x, y] = c + (255,)
    for (x, y) in bounds:
        px[x, y] = pal["k"] + (255,)
    draw_trunk(px, W, H, cx, trunk_top, pal, seed=seed)
    return img


# --------------------------------------------------------------- породы ------
def make_all():
    os.makedirs(ENV, exist_ok=True)
    made = {}
    # дуб: широкое «облако» из 5 лопастей
    made["tree_oak"] = build_round_tree(
        48, 50, 24,
        [(24, 16, 13), (12, 20, 8), (36, 21, 8), (18, 9, 7), (31, 10, 7), (24, 26, 9)],
        PAL_OAK, trunk_top=32, seed=3)
    made["tree_oak2"] = build_round_tree(
        44, 46, 22,
        [(22, 15, 12), (12, 18, 8), (32, 19, 8), (16, 9, 6), (28, 9, 6), (22, 24, 8)],
        PAL_OAK2, trunk_top=29, seed=11)
    # сосна: три яруса конуса
    made["tree_pine"] = build_pine(
        30, 52, 15,
        [(2, 16, 7), (13, 30, 10), (26, 44, 13)],
        PAL_PINE, trunk_top=43, seed=5)
    made["tree_pine2"] = build_pine(
        28, 46, 14,
        [(2, 14, 7), (11, 27, 10), (23, 39, 12)],
        PAL_PINE2, trunk_top=38, seed=9)
    # берёза: светлая ажурная крона + белый ствол в крапинку
    made["tree_birch"] = build_round_tree(
        42, 52, 21,
        [(21, 12, 10), (13, 15, 6), (29, 16, 6), (21, 19, 7)],
        PAL_BIRCH, trunk_top=25, seed=7, birch=True)
    made["tree_birch2"] = build_round_tree(
        46, 54, 23,
        [(23, 13, 11), (14, 17, 7), (32, 17, 7), (23, 21, 8)],
        PAL_BIRCH2, trunk_top=27, seed=13, birch=True)
    # осеннее: оранжевая листва с красной примесью
    made["tree_autumn"] = build_round_tree(
        46, 47, 23,
        [(23, 16, 13), (12, 20, 8), (34, 21, 8), (17, 9, 7), (29, 10, 7), (23, 26, 9)],
        PAL_AUTUMN, trunk_top=31, seed=17, autumn_mix=12)
    # липа: самая широкая крона, жёлто-зелёная, кремовые цветки
    made["tree_lime"] = build_round_tree(
        50, 49, 25,
        [(25, 16, 15), (12, 21, 9), (38, 21, 9), (17, 9, 8), (33, 9, 8), (25, 27, 10)],
        PAL_LIME, trunk_top=32, seed=21, flowers=9)
    made["tree_lime2"] = build_round_tree(
        46, 46, 23,
        [(23, 15, 14), (11, 20, 8), (35, 20, 8), (16, 9, 7), (30, 10, 7), (23, 25, 9)],
        PAL_LIME2, trunk_top=30, seed=29, flowers=7)
    # плодовое: яблоки 2×2
    made["tree_fruit2"] = build_round_tree(
        44, 47, 22,
        [(22, 15, 12), (12, 19, 8), (32, 20, 8), (16, 9, 6), (28, 9, 6), (22, 24, 8)],
        PAL_FRUIT, trunk_top=30, seed=23, fruits=6)
    for name, img in made.items():
        img.save(os.path.join(ENV, name + ".png"))
    return made


def make_preview(made):
    # полоса деревьев на травяной текстуре (grass_M1.png), ×2 масштаб
    grass = Image.open(os.path.join(ENV, "grass_M1.png")).convert("RGB")
    names = ["tree_oak", "tree_oak2", "tree_pine", "tree_pine2", "tree_birch",
             "tree_birch2", "tree_autumn", "tree_lime", "tree_lime2", "tree_fruit2"]
    f = 2
    pad = 10
    cw = max(made[n].width for n in names) * f + pad
    ch = max(made[n].height for n in names) * f + pad * 2
    sheet = Image.new("RGB", (cw * len(names), ch), (0, 0, 0))
    gx = grass.resize((cw * len(names), ch), Image.NEAREST)
    # тайл травы без швов
    for ty in range(0, ch, 32):
        for tx in range(0, cw * len(names), 32):
            sheet.paste(grass, (tx, ty))
    for i, n in enumerate(names):
        big = made[n].resize((made[n].width * f, made[n].height * f), Image.NEAREST)
        sheet.paste(big, (i * cw + pad // 2, ch - big.height - pad // 2), big)
    sheet.save(os.path.join(HERE, "video_preview.png"))
    print("OK: %d деревьев + tools/video_preview.png" % len(made))


made = make_all()
make_preview(made)
