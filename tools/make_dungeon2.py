# -*- coding: utf-8 -*-
"""Данжи v2 (v1.42.0, этап 4 программы «Мир v2»): нарезка и подгонка пака
подземелий заказчика (`F:\\востановление кхорно юнитов\\assets\\ассеты подземельев
\\free-2d-top-down-pixel-dungeon-asset-pack`) под мастер-гамму «Пепла и Маны»,
плюс генерация недостающего (мох, рунный круг, чаша жаровни) в технике
предыдущих генераторов (пятна + дизеринг, make_nature2.py / make_video_grass.py).

Референсы стиля («для Z.ai/данж, биомы и мир», РЕФЕРЕНСЫ-СТИЛЬ.md):
свет «тёплый фонарь + холодные сине-бирюзовые лужи/пропасти» (a8ea4e27),
пепельная порча — красно-чёрные потёки/трещины на кирпиче (5f017950),
мох/трава наползают на камень скруглёнными пятнами (0d1fe2dc),
рунные круги на полу — интерактивные точки.

Выход (assets/sprites/env, 32×32 — апскейл пака ×2 NEAREST):
  d2_floor_a/b/c.png — плиты пола пака (чистая кладка), нормализованы
      в светлый серый (тонируются цветом биома на рантайме);
  d2_wall_top.png — верх стены (блоки с кладкой);
  d2_wall_face.png — грань стены (кирпич) с подсвеченной верхней кромкой
      и затемнённым низом;
  d2_shadow.png — мягкая тень под грань стены на пол;
  d2_crack_a/b/c.png — трещины пола (декали, тонируются);
  d2_wall_crack_a/b.png — трещиноватая грань (порченые комнаты, красный тинт);
  d2_water_1/2/3.png, d2_foam.png — холодная вода (3 кадра анимации) и блик;
  d2_fire_1/2/3.png, d2_fire_s1/2/3.png — огонь жаровни, большой и малый
      (3 кадра мерцания, тёплые цвета пака сохранены);
  d2_brazier.png — каменная чаша жаровни (генерация);
  d2_moss_a/b.png — пятна мха, наползающие на камень (генерация);
  d2_rune.png — рунный круг 48×48 (генерация, тонируется школой);
  props/d2_prop_crystal1/2/3, skull, bones, rubble1/2, web.png — пропсы пака.

Детерминировано: перезапуск = те же файлы. Превью — tools/dungeon2_preview.png.
Запуск: python tools/make_dungeon2.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = os.path.join(
    r"F:\востановление кхорно юнитов\assets\ассеты подземельев",
    "free-2d-top-down-pixel-dungeon-asset-pack", "Tiled_files")
OUT_ENV = os.path.join("assets", "sprites", "env")
OUT_PROPS = os.path.join("assets", "sprites", "props")
TS = 32  # тайл игры; пак 16px -> x2 NEAREST


# ---------- утилиты (техника make_nature2.py) ----------

def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def grad_lut(stops, n=256):
    xs = np.array([p for p, _ in stops])
    cs = np.array([hex2rgb(c) for _, c in stops], dtype=float)
    pos = np.linspace(0.0, 1.0, n)
    out = np.zeros((n, 3))
    for ch in range(3):
        out[:, ch] = np.interp(pos, xs, cs[:, ch])
    return out


GRAY_LUT = grad_lut([(0.0, "#23262e"), (0.55, "#8b909a"), (1.0, "#e9ecef")])


def normalize_gray(img, target_mean=0.80):
    """Яркость -> серый градиент мастера, среднее к target_mean: текстура
    читается, финальный тон задаёт тинт биома на рантайме."""
    a = np.array(img.convert("RGBA"), dtype=float)
    lum = (0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]) / 255.0
    idx = np.clip((lum * 255).astype(int), 0, 255)
    rgb = GRAY_LUT[idx]
    shift = target_mean * 255.0 - rgb.reshape(-1, 3).mean(axis=0)
    rgb = np.clip(rgb + shift, 0, 255)
    out = np.dstack([rgb, a[:, :, 3:4]]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def desaturate(img, sat=0.9, val=0.97):
    a = np.array(img.convert("RGBA"), dtype=float)
    rgb = a[:, :, :3]
    gray = rgb @ np.array([0.299, 0.587, 0.114])
    rgb = gray[:, :, None] + (rgb - gray[:, :, None]) * sat
    rgb = np.clip(rgb * val, 0, 255)
    return Image.fromarray(np.dstack([rgb, a[:, :, 3:4]]).astype(np.uint8), "RGBA")


def scale2(img):
    """16 -> 32 NEAREST: пиксельная чёткость как у города."""
    return img.resize((img.width * 2, img.height * 2), Image.NEAREST)


def tile(sheet, tx, ty):
    return sheet.crop((tx * 16, ty * 16, tx * 16 + 16, ty * 16 + 16))


# ---------- детерминированный шум ----------

def cell_noise(w, h, seed, cell=4):
    """Мягкое поле 0..1: билинейная интерполяция решётки случайных значений."""
    rng = np.random.default_rng(seed)
    gw = int(np.ceil((w - 1) / cell)) + 2
    gh = int(np.ceil((h - 1) / cell)) + 2
    grid = rng.random((gh, gw))
    ys = np.arange(h) / float(cell)
    xs = np.arange(w) / float(cell)
    out = np.zeros((h, w))
    for y in range(h):
        gy = ys[y]
        y0, fy = int(gy), gy - int(gy)
        for x in range(w):
            gx = xs[x]
            x0, fx = int(gx), gx - int(gx)
            v00 = grid[y0, x0]
            v01 = grid[y0, x0 + 1]
            v10 = grid[y0 + 1, x0]
            v11 = grid[y0 + 1, x0 + 1]
            out[y, x] = (v00 * (1 - fx) * (1 - fy) + v01 * fx * (1 - fy)
                         + v10 * (1 - fx) * fy + v11 * fx * fy)
    return out


def bayer2(x, y):
    return [[0.0, 0.5], [0.5, 0.25]][y % 2][x % 2]


# ---------- нарезка пака ----------

def cut_pack():
    wf = Image.open(os.path.join(SRC, "walls_floor.png")).convert("RGBA")
    water = Image.open(os.path.join(SRC, "Water_coasts_animation.png")).convert("RGBA")
    cracks_f = Image.open(os.path.join(SRC, "decorative_cracks_floor.png")).convert("RGBA")
    cracks_w = Image.open(os.path.join(SRC, "decorative_cracks_walls.png")).convert("RGBA")
    fire = Image.open(os.path.join(SRC, "fire_animation.png")).convert("RGBA")
    obj = Image.open(os.path.join(SRC, "Objects.png")).convert("RGBA")

    saved = []

    def put(name, img):
        img = scale2(img) if img.width == 16 else img
        img.save(os.path.join(OUT_ENV, name + ".png"))
        saved.append(name)

    def put_prop(name, img):
        img = scale2(img) if img.width == 16 else img
        img.save(os.path.join(OUT_PROPS, name + ".png"))
        saved.append("props/" + name)

    # пол: плиты пака (тёмные у пака -> нормализация в светлый серый;
    # финальный тон даст тинт биома). v1.42.2: тайлы БЕЗ запечённых
    # пропсов — в (6,1) пака лежит «бочка/скелет», её принимали за
    # предмет под сундуком. Только чистая кладка.
    # v1.42.4: НАСТОЯЩИЕ полы пака — лист decorative_cracks_floor
    # (walls_floor rows 1-4 — это верха стен; их «чёрточки» читались как
    # лишний декор). Ряд 1 — чистая плита; ряды 0/2 — кромки с тенью
    # у стен (автотайл, как в демо-карте пака).
    fl = Image.open(os.path.join(SRC, "decorative_cracks_floor.png")).convert("RGBA")

    def ftile(tx, ty):
        return fl.crop((tx * 16, ty * 16, tx * 16 + 16, ty * 16 + 16))
    put("d2_floor_a", normalize_gray(ftile(1, 1), 0.80))
    put("d2_floor_b", normalize_gray(ftile(3, 1), 0.80))
    put("d2_floor_c", normalize_gray(ftile(5, 1), 0.80))
    put("d2_edge_n", normalize_gray(ftile(1, 0), 0.80))
    put("d2_edge_s", normalize_gray(ftile(5, 0), 0.80))
    put("d2_edge_w", normalize_gray(ftile(1, 2), 0.80))
    put("d2_edge_e", normalize_gray(ftile(5, 2), 0.80))

    # стены: верх — блоки с кладкой; грань — кирпич пака + кромка/низ свои
    put("d2_wall_top", normalize_gray(tile(wf, 9, 6), 0.80))
    face = normalize_gray(tile(wf, 2, 19), 0.80).resize((32, 32), Image.NEAREST)
    face = bake_face_edges(face)
    put("d2_wall_face", face)

    # тень под грань на пол (полупрозрачный овал пака, ряд 26)
    sh = tile(wf, 6, 26)
    put("d2_shadow", sh)

    # трещины пола (декали)
    put("d2_crack_a", normalize_gray(tile(cracks_f, 0, 8), 0.55))
    put("d2_crack_b", normalize_gray(tile(cracks_f, 5, 8), 0.55))
    put("d2_crack_c", normalize_gray(tile(cracks_f, 0, 9), 0.55))

    # трещиноватые грани стен (порча: красный тинт на рантайме)
    put("d2_wall_crack_a", normalize_gray(tile(cracks_w, 0, 9), 0.80))
    put("d2_wall_crack_b", normalize_gray(tile(cracks_w, 4, 11), 0.80))

    # вода: холодная бирюза (референс a8ea4e27), 3 кадра банка анимации
    put("d2_water_1", water_tone(tile(water, 3, 1)))
    put("d2_water_2", water_tone(tile(water, 3, 11)))
    put("d2_water_3", water_tone(tile(water, 3, 21)))
    put("d2_foam", water_tone(tile(water, 7, 30), bright=1.8))

    # огонь: кадр = колонка-полоса 16×48 (верх/тело/основание), мерцание —
    # колонки 3/6/9; тёплые цвета пака и альфа-подложка свечения не тронуты
    for i, tx in enumerate((3, 6, 9), 1):
        put(f"d2_fire_{i}", fire.crop((tx * 16, 0, tx * 16 + 16, 48)))
        put(f"d2_fire_s{i}", fire.crop((tx * 16, 9 * 16, tx * 16 + 16, 9 * 16 + 48)))
    put("d2_brazier", make_brazier())

    # мох и рунный круг — генерация
    put("d2_moss_a", make_moss(11))
    put("d2_moss_b", make_moss(37))
    put("d2_rune", make_rune())

    # пропсы (приглушить сочность пака, как в v1.39)
    put_prop("d2_prop_crystal1", desaturate(tile(obj, 1, 1)))
    put_prop("d2_prop_crystal2", desaturate(tile(obj, 2, 2)))
    put_prop("d2_prop_crystal3", desaturate(tile(obj, 4, 3)))
    put_prop("d2_prop_skull", desaturate(tile(obj, 17, 5)))
    put_prop("d2_prop_bones", desaturate(tile(obj, 19, 5)))
    put_prop("d2_prop_rubble1", desaturate(tile(obj, 10, 1)))
    put_prop("d2_prop_rubble2", desaturate(tile(obj, 12, 1)))
    put_prop("d2_prop_web", desaturate(tile(obj, 5, 7)))
    return saved


WATER_LUT = grad_lut([(0.0, "#10222e"), (0.5, "#1d4152"), (0.85, "#3f7d94"), (1.0, "#9fdcec")])


def water_tone(img, bright=1.0):
    """Вода пака -> холодная бирюза мастера (референс a8ea4e27)."""
    a = np.array(img.convert("RGBA"), dtype=float)
    lum = (0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]) / 255.0
    idx = np.clip((lum * 255).astype(int), 0, 255)
    rgb = WATER_LUT[idx]
    if bright != 1.0:
        rgb = np.clip(rgb * bright, 0, 255)
    return Image.fromarray(np.dstack([rgb, a[:, :, 3:4]]).astype(np.uint8), "RGBA")


def bake_face_edges(face32):
    """Грань стены: светлая кромка сверху (на неё «светит» верх), тень снизу —
    рельеф кладки как на референсах (5f017950)."""
    a = np.array(face32, dtype=float)
    h, w = a.shape[:2]
    for y in range(h):
        if y < 3:
            k = 1.0 + 0.28 * (3 - y) / 3.0
        elif y >= h - 4:
            k = 1.0 - 0.30 * (y - (h - 5)) / 4.0
        else:
            k = 1.0
        a[y, :, 0:3] = np.clip(a[y, :, 0:3] * k, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def make_brazier():
    """Каменная чаша жаровни 16×16: тёмная чаша + тлеющие угли в зеве."""
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    stone = [(104, 100, 96), (74, 71, 68), (52, 50, 48)]
    # ножка
    d.rectangle((7, 12, 8, 14), fill=stone[2])
    # чаша (трапеция)
    d.polygon([(3, 6), (12, 6), (11, 12), (4, 12)], fill=stone[1])
    d.line((3, 6, 12, 6), fill=stone[0])
    d.line((4, 12, 11, 12), fill=stone[2])
    # зев с углями
    d.ellipse((4, 4, 11, 8), fill=stone[2])
    coals = [(120, 52, 20), (196, 92, 30), (255, 168, 66)]
    rng = np.random.default_rng(5)
    for i in range(9):
        x = 5 + int(rng.integers(0, 6))
        y = 5 + int(rng.integers(0, 3))
        d.point((x, y), fill=coals[i % 3])
    return img


def make_moss(seed):
    """Пятно мха 16×16: скруглённые блобы в 3 тона зелени с дизерингом кромки
    (референс 0d1fe2dc — мох наползает на камень мягкими пятнами)."""
    field = cell_noise(16, 16, seed, cell=5)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    greens = [(52, 84, 44), (74, 110, 54), (104, 140, 66)]
    for y in range(16):
        for x in range(16):
            v = field[y, x]
            # форма пятна: мягкий диск с шумом
            dx, dy = (x - 7.5) / 8.0, (y - 8.5) / 9.0
            r = (dx * dx + dy * dy) ** 0.5
            edge = 0.62 + 0.30 * ((cell_noise(16, 16, seed + 1, 4)[y, x]) - 0.5)
            if r > edge + 0.22:
                continue
            t = v
            if r > edge - 0.08:  # дизеринг кромки
                t -= 0.35 if bayer2(x, y) > 0.3 else 0.0
                if t < 0.25:
                    continue
            tone = greens[1] if t < 0.45 else (greens[2] if t > 0.72 else greens[0])
            a = 235 if r < edge - 0.15 else 170
            px[x, y] = (*tone, a)
    return img


def make_rune():
    """Рунный круг 48×48: двойное кольцо, глифы-чёрточки по кругу, ядро-свечение.
    Тон — нейтральный серый, на рантайме тонируется цветом школы магии."""
    S = 48
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2.0
    base = (168, 172, 182)
    bright = (236, 240, 248)
    d.ellipse((c - 21, c - 21, c + 21, c + 21), outline=(*base, 235), width=2)
    d.ellipse((c - 15, c - 15, c + 15, c + 15), outline=(*base, 200), width=1)
    # внутренний «пентакль» из хорд
    import math
    pts = []
    for k in range(5):
        ang = -math.pi / 2 + k * 4 * math.pi / 5
        pts.append((c + 13 * math.cos(ang), c + 13 * math.sin(ang)))
    d.line(pts + [pts[0]], fill=(*base, 190), width=1)
    # глифы по внешнему кольцу
    rng = np.random.default_rng(21)
    for k in range(10):
        ang = k * math.pi / 5
        x = c + 18 * math.cos(ang)
        y = c + 18 * math.sin(ang)
        for j in range(2 + int(rng.integers(0, 2))):
            ox = int(rng.integers(-2, 3))
            oy = int(rng.integers(-2, 3))
            ln = 1 + int(rng.integers(0, 3))
            if rng.random() < 0.5:
                d.line((x + ox - ln, y + oy, x + ox + ln, y + oy), fill=(*bright, 255), width=1)
            else:
                d.line((x + ox, y + oy - ln, x + ox, y + oy + ln), fill=(*bright, 255), width=1)
    # ядро
    d.ellipse((c - 5, c - 5, c + 5, c + 5), fill=(*bright, 120))
    d.ellipse((c - 2, c - 2, c + 2, c + 2), fill=(*bright, 235))
    return img


# ---------- превью ----------

def preview(saved):
    tiles = [Image.open(os.path.join(OUT_ENV, n + ".png")) for n in saved
             if not n.startswith("props/")]
    cols = 8
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 34 + 2, rows * 34 + 2), (30, 30, 38))
    for i, t in enumerate(tiles):
        x = 2 + (i % cols) * 34
        y = 2 + (i // cols) * 34
        sheet.paste(t, (x, y), t)
    sheet.save(os.path.join("tools", "dungeon2_preview.png"))
    print("превью: tools/dungeon2_preview.png")


if __name__ == "__main__":
    os.makedirs(OUT_ENV, exist_ok=True)
    os.makedirs(OUT_PROPS, exist_ok=True)
    names = cut_pack()
    preview(names)
    print(f"готово: {len(names)} спрайтов -> assets/sprites/env|props (d2_*)")
