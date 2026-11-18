# -*- coding: utf-8 -*-
"""КОМПОЗИТОР БИОМОВ (v1.77.0) — «собери биом сам».

Заказчик складывает PNG-файлы в папку assets/sprites/env/biomes_composed/
<имя биома>/ (имя папки = тег). Файлы можно свободно копировать из
нарезанной библиотеки assets/sprites/env/biomes/<тег>/ (grass_*, water,
tree_*) или приносить свои. Правила имён:

  трава:   любые PNG, имя начинается с grass / tile / трава
           (НЕ *_fill.png — подложки генерируются сами)
  вода:    water*.png / вода*.png — тайл 32×32 или готовая полоса 192×96
  деревья: tree*.png / дерево*.png — любое количество
  season.txt:   одна строка: spring|summer|autumn|winter (или по-русски)
                — биом станет скином этого сезона во всём городе
  label.txt:    одна строка — как подписывать на стенде (необязательно)

Запуск: python tools/compose_biome.py
  - приводит траву к единому рецепту (общий тон + нормализация +
    мягкие края — единообразие со всей землёй игры),
  - воду разворачивает в полосу 6 кадров × 3 ряда,
  - пишет биом в манифест assets/sprites/env/biomes/manifest.json —
    после этого он сам появляется: в городе (по сезону из season.txt,
    либо превью SHOT_BIOME=<тег>), на тестовом стенде (галерея), и
    готов к карте мира.
"""
import json
import os
import shutil

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
COMPOSED = os.path.join(GAME, "assets", "sprites", "env", "biomes_composed")
MANIFEST = os.path.join(GAME, "assets", "sprites", "env", "biomes",
                        "manifest.json")
TS = 32
FEATHER = 8

SEASON_RU = {"весна": "spring", "лето": "summer", "осень": "autumn",
             "зима": "winter"}


def classify(fname):
    n = fname.lower()
    if n.endswith("_fill.png") or n == "label.txt" or n == "season.txt":
        return None
    if n.startswith(("grass", "tile", "трава")):
        return "grass"
    if n.startswith(("water", "вода")):
        return "water"
    if n.startswith(("tree", "дерево")):
        return "tree"
    return None


def uniform_recipe(img, shared_mean):
    """Единый рецепт земли: нормализация к общему тону + мягкие края
    поверх сплошной подложки (то же, что у biome-тайлов игры)."""
    tile = np.array(img.convert("RGBA"))
    if tile.shape[:2] != (TS, TS):
        tile = np.array(img.convert("RGBA").resize((TS, TS), Image.NEAREST))
    tm = tile[:, :, :3].reshape(-1, 3).mean(axis=0)
    ratio = np.clip(shared_mean / np.maximum(tm, 1.0), 0.7, 1.4)
    t = tile.astype(np.float32)
    t[:, :, :3] = np.clip(t[:, :, :3] * ratio, 0, 255)
    t = t.astype(np.uint8)
    yy, xx = np.mgrid[0:TS, 0:TS]
    edge = np.minimum(np.minimum(xx, TS - 1 - xx),
                      np.minimum(yy, TS - 1 - yy)).astype(np.float32)
    ramp = 0.35 + 0.65 * np.clip(edge / float(FEATHER), 0.0, 1.0)
    t[:, :, 3] = (t[:, :, 3].astype(np.float32) * ramp).astype(np.uint8)
    af = t[:, :, 3:4].astype(np.float32) / 255.0
    comp = (t[:, :, :3].astype(np.float32) * af
            + shared_mean.astype(np.float32) * (1.0 - af)).astype(np.uint8)
    out = np.dstack([comp, np.full((TS, TS), 255, np.uint8)])
    return Image.fromarray(out)


def build_water(path):
    """Любой водный арт -> полоса 192×96 (6 кадров × 3 ряда)."""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    if (w, h) == (192, 96):
        return im
    if (w, h) == (TS, TS):
        strip = Image.new("RGBA", (192, 96), (0, 0, 0, 0))
        for r in range(3):
            for f in range(6):
                strip.paste(im, (f * TS, r * TS))
        return strip
    if h == TS and w % TS == 0 and w >= TS:
        base = im.crop((0, 0, min(w, 192), TS))
        strip = Image.new("RGBA", (192, 96), (0, 0, 0, 0))
        for r in range(3):
            for f in range(6):
                strip.paste(base.crop(((f % max(1, base.size[0] // TS)) * TS, 0,
                                       (f % max(1, base.size[0] // TS)) * TS + TS, TS)),
                            (f * TS, r * TS))
        return strip
    return im.resize((192, 96), Image.NEAREST)


def main():
    if not os.path.isdir(COMPOSED) or not os.listdir(COMPOSED):
        print("biomes_composed пуст — см. README внутри папки")
        return
    mf = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as fh:
            mf = json.load(fh)
    changed = False
    for tag in sorted(os.listdir(COMPOSED)):
        folder = os.path.join(COMPOSED, tag)
        if not os.path.isdir(folder):
            continue
        files = sorted(os.listdir(folder))
        grass = [f for f in files if classify(f) == "grass"]
        water = [f for f in files if classify(f) == "water"]
        trees = [f for f in files if classify(f) == "tree"]
        if not grass:
            print("!! %s: нет файлов травы (grass*/tile*/трава*) — пропуск" % tag)
            continue
        # общий тон по траве
        means = []
        for f in grass:
            im = Image.open(os.path.join(folder, f)).convert("RGBA")
            if im.size != (TS, TS):
                im = im.resize((TS, TS), Image.NEAREST)
            means.append(np.array(im)[:, :, :3].reshape(-1, 3).mean(axis=0))
        shared = np.clip(np.mean(means, axis=0), 1, 254).astype(np.uint8)
        grass_paths = []
        for i, f in enumerate(grass, 1):
            src = Image.open(os.path.join(folder, f)).convert("RGBA")
            out = uniform_recipe(src, shared)
            out.save(os.path.join(folder, "grass_%d.png" % i))
            Image.fromarray(np.tile(shared, (TS, TS, 1))).save(
                os.path.join(folder, "grass_%d_fill.png" % i))
            grass_paths.append("res://assets/sprites/env/biomes_composed/%s/grass_%d.png" % (tag, i))
            if f != "grass_%d.png" % i:
                os.remove(os.path.join(folder, f)) if False else None
        water_path = ""
        if water:
            wsrc = build_water(os.path.join(folder, water[0]))
            wsrc.save(os.path.join(folder, "water.png"))
            water_path = "res://assets/sprites/env/biomes_composed/%s/water.png" % tag
        tree_refs = []
        for i, f in enumerate(trees, 1):
            dst = "tree_%d.png" % i
            if f != dst:
                shutil.copyfile(os.path.join(folder, f),
                                os.path.join(folder, dst))
            tree_refs.append("img:env/biomes_composed/%s/%s" % (tag, dst))
        entry = {"grass": grass_paths, "water": water_path, "trees": tree_refs}
        label_file = os.path.join(folder, "label.txt")
        if os.path.exists(label_file):
            with open(label_file, encoding="utf-8") as fh:
                entry["label"] = fh.readline().strip()
        season_file = os.path.join(folder, "season.txt")
        if os.path.exists(season_file):
            with open(season_file, encoding="utf-8") as fh:
                sv = fh.readline().strip().lower()
            entry["season"] = SEASON_RU.get(sv, sv)
        mf[tag] = entry
        changed = True
        print("биом «%s»: трава=%d вода=%s деревьев=%d%s%s" % (
            tag, len(grass), "да" if water else "нет", len(trees),
            " сезон=" + entry.get("season", "") if "season" in entry else "",
            " («" + entry["label"] + "»)" if "label" in entry else ""))
    if changed:
        with open(MANIFEST, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(mf, fh, ensure_ascii=False, indent=1)
        print("манифест обновлён:", MANIFEST)


if __name__ == "__main__":
    main()
