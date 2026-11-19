# -*- coding: utf-8 -*-
"""СБОРЩИК СЕЗОННЫХ БИОМОВ + ВОДА ВСЕМ БИОМАМ (v1.78.6, поручение заказчика
«попробуй сделать биомы сейчас сам, и нормально реки и болота и озёра,
времена года тоже»).

Сезонные биомы (весна/осень/зима) перегенерируются из ИСХОДНЫХ листов:
  трава:  полные клетки ОДНОГО поля листа (кластер по цвету сезона, до 24
          клеток) — общий тон + нормализация + дизеринг кромки;
  вода:   лента реки листа (последовательность синих клеток в строке);
          если лист воды не дал (запечённый тёмный фон) — СТАНДАРТНАЯ
          полоса fm_water, тонированная в цвет воды биома (осень —
          холодная серо-синяя, зима — ледяная, болота — топь...);
  манифест получает поле season — город сам берёт биом при смене сезона.
Всем остальным биомам БЕЗ воды печатается тонированная полоса — реки,
озёра и болота перестают быть стандартными во всех биомах.

Запуск: python tools/build_season_biomes.py
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
BIOMES_DIR = os.path.join(GAME, "assets", "sprites", "env", "biomes")
MANIFEST = os.path.join(BIOMES_DIR, "manifest.json")
BASE = r"F:\востановление кхорно юнитов\assets\ассеты домов\новые ассеты монстров"
FM_WATER = os.path.join(GAME, "assets", "sprites", "env", "fm_water.png")
TS = 32
FEATHER = 8

# сезонные биомы: (папка, файл, признак клетки травы, цвет воды-фолбэк)
SEASON_BIOMES = [
    ("весна", "биом весна",
     "Пиксельный атлас весеннего леса и водоёмов.png",
     lambda m: m[1] > m[0] + 5 and m[1] > m[2] + 5,          # зелёные
     (63, 99, 122)),
    ("осень", "БИОМ ОСЕНЬ",
     "Осенний пиксельный тайлсет для RPG.png",
     lambda m: m[0] > m[2] + 15 and (m[0] * 0.299 + m[1] * 0.587
               + m[2] * 0.114) > 45,                        # тёплые
     (74, 107, 124)),
    ("зима", "биомы зима",
     "Зимний пиксельный атлас тайлов и объектов.png",
     lambda m: (m[0] * 0.299 + m[1] * 0.587 + m[2] * 0.114) > 135
               and m[2] >= m[0] - 8,                        # светлые холодные
     (88, 132, 158)),
]

# мировые биомы без воды: цвет воды-фолбэк (тонирование fm_water)
WATER_TINT = {
    "болота": (70, 82, 58),
    "берёзовая роща": (74, 107, 124),
    "древний лес": (47, 85, 68),
    "мёртвый лес": (58, 68, 72),
    "огненные земли": (61, 74, 82),
    "проклятый лес": (51, 68, 58),
    "пустыня": (79, 163, 168),
    "степи": (76, 127, 150),
    "цветущий край": (87, 178, 212),
}
# у мистического леса и скал своя вода есть — не трогаем

SEASON_TAG = {"весна": "spring", "осень": "autumn", "зима": "winter"}


def full_cells(rgb):
    H, W = rgb.shape[:2]
    out = []
    for cy in range(H // TS):
        for cx in range(W // TS):
            cell = rgb[cy * TS:(cy + 1) * TS, cx * TS:(cx + 1) * TS]
            if cell[:, :, 3].min() > 200:
                m = cell[:, :, :3].reshape(-1, 3).mean(axis=0)
                lum = m[0] * 0.299 + m[1] * 0.587 + m[2] * 0.114
                # шашечка-вместо-альфы (весенний лист): почти вся клетка —
                # светлые нейтральные пиксели двух тонов = фон листа
                flat = cell[:, :, :3].reshape(-1, 3)
                mx = flat.max(axis=1)
                mn = flat.min(axis=1)
                lightmask = (mx > 170) & (mx - mn < 14)
                light = float(lightmask.mean())
                if light > 0.75:
                    spread = float(mx[lightmask].max()) - float(
                        mn[lightmask].min())
                    if spread > 12.0:
                        continue
                out.append((cx, cy, m, lum))
    return out


def largest_cluster(cells):
    best = set()
    for seed in list(cells):
        if seed in best:
            continue
        comp, q = set(), [seed]
        while q:
            c = q.pop()
            if c in comp or c not in cells:
                continue
            comp.add(c)
            x, y = c
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q.append((x + dx, y + dy))
        if len(comp) > len(best):
            best = comp
    return best


def clean_checker(tile):
    """Шашечка-вместо-альфы (весенний лист): пиксель шашечка = светлый
    нейтральный (max>170, разброс<14) И пара на ±8px — светлый нейтральный
    ДРУГОГО тона (шахматное чередование; снег и цветы пар не имеют).
    Снимается ЗАЛИВКОЙ ОТ КРАЁВ клетки — цветы в центре не достижимы.
    Дырки заливаются средним цветом оставшихся пикселей.
    Возвращает (tile, доля съеденного 0..1)."""
    H, W = tile.shape[:2]
    r = tile[:, :, 0].astype(np.int32)
    g = tile[:, :, 1].astype(np.int32)
    b = tile[:, :, 2].astype(np.int32)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    light = (mx > 170) & (mx - mn < 14)
    sums = r + g + b
    pair = np.zeros((H, W), bool)
    for dy, dx in ((8, 0), (-8, 0), (0, 8), (0, -8)):
        sh_s = np.roll(np.roll(sums, -dy, axis=0), -dx, axis=1)
        sh_l = np.roll(np.roll(light, -dy, axis=0), -dx, axis=1)
        if dy == 8:
            sh_s[-dy:, :] = sums[:1, :].mean()
            sh_l[-dy:, :] = False
        elif dy == -8:
            sh_s[:8, :] = sums[-1:, :].mean()
            sh_l[:8, :] = False
        elif dx == 8:
            sh_s[:, -dx:] = sums[:, :1].mean()
            sh_l[:, -dx:] = False
        elif dx == -8:
            sh_s[:, :8] = sums[:, -1:].mean()
            sh_l[:, :8] = False
        pair |= light & sh_l & (np.abs(sums - sh_s) >= 36)
    # заливка от краёв (BFS по шашечным пикселям): помечаем СЪЕДЕННЫЕ
    from collections import deque
    rest = pair.copy()          # ещё не съеденные шашечные пиксели
    eaten = np.zeros((H, W), bool)
    queue = deque()
    for x in range(W):
        for ye in (0, H - 1):
            if rest[ye, x]:
                rest[ye, x] = False
                eaten[ye, x] = True
                queue.append((ye, x))
    for y in range(H):
        for xe in (0, W - 1):
            if rest[y, xe]:
                rest[y, xe] = False
                eaten[y, xe] = True
                queue.append((y, xe))
    while queue:
        y, x = queue.popleft()
        for dy2, dx2 in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy2, x + dx2
            if 0 <= ny < H and 0 <= nx < W and rest[ny, nx]:
                rest[ny, nx] = False
                eaten[ny, nx] = True
                queue.append((ny, nx))
    if not eaten.any():
        return tile, 0.0
    keep = ~eaten
    mean = tile[:, :, :3][keep].mean(axis=0).astype(np.uint8)
    out = tile.copy()
    out[eaten, :3] = mean
    out[eaten, 3] = 255
    return out, float(eaten.mean())


def make_tileable(tile, F=7):
    """Бесшовность: края тайла зеркально сливаются с противоположными
    (правый край <-> левый, верх <-> низ) — тайл стыкуется сам с собой
    бесшовно, а с нормализованным тоном набора и с любым соседом
    (v1.78.9: тайлы-«кусочки иллюстраций» не сливались в землю)."""
    H, W = tile.shape[:2]
    rgb = tile[:, :, :3].astype(np.float32)
    a = tile[:, :, 3].astype(np.float32) / 255.0
    out = rgb.copy()
    for y in range(H):
        for x in range(W):
            c = rgb[y, x].copy()
            wx = 0.0
            if x < F:
                wx = 0.5 * (1.0 - x / float(F))
            elif x >= W - F:
                wx = 0.5 * (1.0 - (W - 1 - x) / float(F))
            if wx > 0.0:
                c = c * (1.0 - wx) + rgb[y, W - 1 - x] * wx
            wy = 0.0
            if y < F:
                wy = 0.5 * (1.0 - y / float(F))
            elif y >= H - F:
                wy = 0.5 * (1.0 - (H - 1 - y) / float(F))
            if wy > 0.0:
                c = c * (1.0 - wy) + rgb[H - 1 - y, x] * wy
            out[y, x] = c
    t = np.dstack([np.clip(out, 0, 255).astype(np.uint8),
                   tile[:, :, 3].copy()])
    return t


def composite(tile, shared_mean):
    """Общий тон + БЕСШОВНОСТЬ (v1.78.9): нормализация жёстче, края тайла
    зеркально сливаются с противоположными — тайлы сливаются в единую
    землю (раньше каждый читался отдельным квадратиком)."""
    tm = tile[:, :, :3].reshape(-1, 3).mean(axis=0)
    ratio = np.clip(shared_mean / np.maximum(tm, 1.0), 0.8, 1.25)
    t = tile.astype(np.float32)
    t[:, :, :3] = np.clip(t[:, :, :3] * ratio, 0, 255)
    t = t.astype(np.uint8)
    t = make_tileable(t)
    out = np.dstack([t[:, :, :3], np.full((TS, TS), 255, np.uint8)])
    return Image.fromarray(out), Image.fromarray(
        np.tile(shared_mean, (TS, TS, 1)))


def longest_water_run(cells, lum_min):
    cells = [(cx, cy, m, lum) for cx, cy, m, lum in cells if lum > lum_min]
    rows = {}
    for cx, cy, m, lum in cells:
        if m[2] > m[0] + 8 and m[2] > m[1] + 4:
            rows.setdefault(cy, []).append(cx)
    best_y, best = None, []
    for cy, xs in rows.items():
        xs.sort()
        run = [xs[0]]
        for x in xs[1:]:
            if x == run[-1] + 1:
                run.append(x)
            else:
                if len(run) > len(best):
                    best_y, best = cy, run
                run = [x]
        if len(run) > len(best):
            best_y, best = cy, run
    return best_y, best


def tint_water(target):
    """Стандартная полоса fm_water, перекрашенная в цвет биома:
    относительная яркость каждого пикселя сохраняется (пена светлее)."""
    im = np.array(Image.open(FM_WATER).convert("RGBA")).astype(np.float32)
    lum = (im[:, :, 0] * 0.299 + im[:, :, 1] * 0.587 + im[:, :, 2] * 0.114)
    base = lum[im[:, :, 3] > 128].mean() if (im[:, :, 3] > 128).any() else 128.0
    scale = np.clip(lum / maxf(base), 0.25, 2.2)
    t = np.array(target, np.float32)
    out = np.zeros_like(im)
    for ch in range(3):
        out[:, :, ch] = np.clip(t[ch] * scale, 0, 255)
    out[:, :, 3] = im[:, :, 3]
    return Image.fromarray(out.astype(np.uint8))


def maxf(x):
    return x if x > 0 else 1.0


def build_grass(tag, folder, fname, classify):
    path = os.path.join(BASE, folder, fname)
    if not os.path.exists(path):
        print("!! нет листа:", tag)
        return None
    img = Image.open(path).convert("RGBA")
    rgb = np.array(img)
    cells = full_cells(rgb)
    # трава: полные не-водные клетки, ПРИОРИТЕТ сплошным (минимум шашечки
    # после чистки — ленточные клетки дают бледные полосы на карте)
    ground = [(cx, cy) for cx, cy, m, lum in cells
              if not (m[2] > m[0] + 8 and m[2] > m[1] + 4)
              and classify(m)]
    scored = []
    for cx, cy in ground:
        tile, eaten = clean_checker(
            np.ascontiguousarray(rgb[cy * TS:(cy + 1) * TS, cx * TS:(cx + 1) * TS]))
        if eaten > 0.8:
            continue   # клетка почти целиком шашечка — фон листа
        scored.append((eaten, cx, cy, tile))
    scored.sort(key=lambda s: s[0])
    pick = scored[:24]
    bdir = os.path.join(BIOMES_DIR, tag)
    os.makedirs(bdir, exist_ok=True)
    means = [t[:, :, :3].reshape(-1, 3).mean(axis=0)
             for _e, _cx, _cy, t in pick]
    shared = np.clip(np.mean(means, axis=0), 1, 254).astype(np.uint8)
    for i, (_e, _cx, _cy, tile) in enumerate(pick, 1):
        comp_img, fill_img = composite(tile, shared)
        comp_img.save(os.path.join(bdir, "grass_%d.png" % i))
        fill_img.save(os.path.join(bdir, "grass_%d_fill.png" % i))
    return rgb, cells, len(pick)


def build_water(tag, rgb, cells, target, bdir):
    H, W = rgb.shape[:2]
    full_ratio = len(cells) / float((H // TS) * (W // TS))
    # запечённый фон листа: вода ищется только светлая (иначе грязь);
    # прозрачный лист: берём любую синюю ленту
    lum_min = 70.0 if full_ratio > 0.55 else 30.0
    wy, run = longest_water_run(cells, lum_min)
    if wy is not None and len(run) >= 3:
        strip = Image.new("RGBA", (TS * 6, TS * 3), (0, 0, 0, 0))
        for i in range(6):
            cx = run[i % len(run)]
            cell = Image.fromarray(
                rgb[wy * TS:(wy + 1) * TS, cx * TS:(cx + 1) * TS])
            for r in range(3):
                strip.paste(cell, (i * TS, r * TS))
        strip.save(os.path.join(bdir, "water.png"))
        return "свои %d клеток (лента y=%d)" % (len(run), wy)
    if target is None:
        return ""
    tint_water(target).save(os.path.join(bdir, "water.png"))
    return "тонированная %s" % (target,)


def main():
    import json
    with open(MANIFEST, encoding="utf-8") as fh:
        mf = json.load(fh)
    # --- сезонные: трава заново из поля листа + вода + season
    for tag, folder, fname, classify, wtarget in SEASON_BIOMES:
        built = build_grass(tag, folder, fname, classify)
        if built is None:
            continue
        rgb, cells, n = built
        bdir = os.path.join(BIOMES_DIR, tag)
        wsrc = build_water(tag, rgb, cells, wtarget, bdir)
        mf[tag]["grass"] = ["res://assets/sprites/env/biomes/%s/grass_%d.png"
                            % (tag, i + 1) for i in range(n)]
        mf[tag]["water"] = "res://assets/sprites/env/biomes/%s/water.png" % tag
        mf[tag]["season"] = SEASON_TAG[tag]
        mf[tag]["label"] = tag
        print("%-8s трава=%d вода=%s" % (tag, n, wsrc))
    # --- мировым без воды: тонированная полоса (реки/озёра/болота везде)
    for tag, target in WATER_TINT.items():
        if tag not in mf or mf[tag].get("water"):
            continue
        bdir = os.path.join(BIOMES_DIR, tag)
        os.makedirs(bdir, exist_ok=True)
        tint_water(target).save(os.path.join(bdir, "water.png"))
        mf[tag]["water"] = "res://assets/sprites/env/biomes/%s/water.png" % tag
        print("%-16s вода: тонированная %s" % (tag, target))
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(mf, fh, ensure_ascii=False, indent=1)
    print("манифест:", MANIFEST)


if __name__ == "__main__":
    main()
