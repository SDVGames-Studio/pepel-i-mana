# -*- coding: utf-8 -*-
# Трава «как в видео jess::codes (dual-grid)»: 6 БЕСШОВНЫХ тайлов 32×32,
# 3 тона-семейства × 2 варианта. Слои: крупные пятна (wrap-шум) → плотный
# мелкий крап тём/светл → пучки травинок (2–3 травинки, тёмное основание +
# светлый кончик). Тайлы повторяются без швов: шум и крап берутся по mod 32.
# Запуск: python tools/make_video_grass.py (PIL). Результат:
#   assets/sprites/env/grass_L1|L2|M1|M2|D1|D2.png + tools/grass_preview.png
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ENV = os.path.join(GAME, "assets", "sprites", "env")
TS = 32

# Семейства тонов — синхронизированы с data/city.json (colors.grass*):
# L = grass (светлая поляна), M = grass_alt, D = grass2 (тёмная поляна)
FAMILIES = [
    ("L", (92, 160, 70)),    # #5ca046
    ("M", (84, 151, 64)),    # #549740
    ("D", (73, 137, 56)),    # #498938
]


def _h(x, y, n=10000, s=0):
    v = (x * 374761393 + y * 668265263 + s * 974634757) & 0x7FFFFFFF
    v ^= v >> 13
    return v % n


# Значение билинейного wrap-шума 0..1 с периодом P (швов нет по построению)
def vnoise(xf, yf, P, s):
    x0, y0 = int(xf) % P, int(yf) % P
    x1, y1 = (x0 + 1) % P, (y0 + 1) % P
    fx, fy = xf - int(xf), yf - int(yf)
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _h(x0, y0, 1000, s) / 999.0, _h(x1, y0, 1000, s) / 999.0
    c, d = _h(x0, y1, 1000, s) / 999.0, _h(x1, y1, 1000, s) / 999.0
    top = a + (b - a) * sx
    bot = c + (d - c) * sx
    return top + (bot - top) * sy


def clamp(v):
    return max(0, min(255, int(round(v))))


def make_tile(base, seed):
    r, g, b = base
    img = Image.new("RGB", (TS, TS), (r, g, b))
    px = img.load()
    # 1) крупные пятна: два слоя wrap-шума, постеризация в 3 уровня
    for y in range(TS):
        for x in range(TS):
            n = vnoise(x / 11.0, y / 11.0, 11, seed) * 0.65 \
                + vnoise(x / 5.0, y / 5.0, 5, seed + 40) * 0.35
            k = (n - 0.5) * 0.22          # ±11% яркости
            px[x, y] = (clamp(r * (1 + k)), clamp(g * (1 + k)), clamp(b * (1 + k)))
    # 2) плотный крап: тёмные и светлые точки (у jess крап покрывает ~30%)
    for y in range(TS):
        for x in range(TS):
            h = _h(x, y, 1000, seed * 7 + 1)
            cur = px[x, y]
            if h < 90:                     # тёмная точка
                px[x, y] = (clamp(cur[0] * 0.80), clamp(cur[1] * 0.80), clamp(cur[2] * 0.80))
            elif h < 180:                  # светлая точка
                px[x, y] = (clamp(cur[0] * 1.16), clamp(cur[1] * 1.14), clamp(cur[2] * 1.10))
    # 3) пучки травинок: 2–4 травинки по 2–3 пикселя, тёмное основание,
    #    светлый кончик — «живые» мазки поверх крапа (координаты mod 32)
    dark = (clamp(r * 0.68), clamp(g * 0.68), clamp(b * 0.68))
    lite = (clamp(r * 1.28), clamp(g * 1.26), clamp(b * 1.20))
    ncl = 11 + seed % 3
    for i in range(ncl):
        cx = 3 + _h(i, seed, 26)
        cy = 5 + _h(seed, i, 24)
        blades = 2 + _h(i * 3, seed, 3)
        for k in range(blades):
            bx = (cx + k * 2 - blades) % TS
            by = cy % TS
            h = _h(bx, by, 4, seed)
            px[bx, by] = dark
            px[bx, (by - 1) % TS] = (
                clamp((px[bx, (by - 1) % TS][0] + dark[0]) / 2),
                clamp((px[bx, (by - 1) % TS][1] + dark[1]) / 2),
                clamp((px[bx, (by - 1) % TS][2] + dark[2]) / 2))
            if h < 3:                      # высокая травинка со светлым кончиком
                px[bx, (by - 2) % TS] = lite
    return img


def main():
    os.makedirs(ENV, exist_ok=True)
    tiles = []
    for fi, (fam, base) in enumerate(FAMILIES):
        for v in (1, 2):
            seed = (fi * 31 + v * 7 + 3) * 17
            img = make_tile(base, seed)
            name = "grass_%s%d" % (fam, v)
            img.save(os.path.join(ENV, name + ".png"))
            tiles.append((name, img))
    # превью: 4×4 повтора каждого тайла, полоса вариантов
    pad = 6
    ph = TS * 4
    sheet = Image.new("RGB", (len(tiles) * (TS * 4 + pad) + pad, ph + 2 * pad), (46, 52, 44))
    for i, (_, img) in enumerate(tiles):
        big = Image.new("RGB", (TS * 4, TS * 4))
        for ty in range(4):
            for tx in range(4):
                big.paste(img, (tx * TS, ty * TS))
        sheet.paste(big, (pad + i * (TS * 4 + pad), pad))
    sheet.save(os.path.join(HERE, "grass_preview.png"))
    print("OK: %d тайла травы" % len(tiles))


main()
