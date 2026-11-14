# -*- coding: utf-8 -*-
"""Нарезчик ассет-кита «Пепел и Мана» (v1.69, волна «Новый облик мира»).

Источник: F:/востановление кхорно юнитов/assets/ассеты домов/
новые ассеты использовать толькоих/*.png — листы, подписанные заказчиком
(категории прямо на листах). Листы RGB на почти чёрном фоне — при нарезке
фон переводится в альфу (lum-key с мягким порогом: тени остаются
полупрозрачными, свечение сохраняется).

Выход: assets/sprites/kit/<имя>.png + tools/_kit_contact.png (контрольный
лист). Детерминирован: только кропы и порог, без случайностей.
"""
import os
import sys
from PIL import Image

SRC_DIR = (r"F:\востановление кхорно юнитов\assets"
           r"\ассеты домов\новые ассеты использовать толькоих")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "assets", "sprites", "kit")
KEY_LO = 17.0   # ниже — фон (альфа 0); фон листа lum 11-15
KEY_HI = 26.0   # выше — полный цвет; тёмный артефакт листа lum ~29


def key_black(img: Image.Image, lo: float = KEY_LO) -> Image.Image:
    """RGB на чёрном -> RGBA: ЗАЛИВКА от краёв кропа — прозрачным становится
    только фон, СВЯЗАННЫЙ с границей (фон листа неравномерный, до lum 33,
    поэтому пороговой кей съедал тёмный арт). Тени под зданиями, отделённые
    светлой землёй, остаются в арте."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    dark = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            dark[y][x] = lum <= lo
    # flood fill тёмной связной области от всех граничных пикселей
    from collections import deque
    seen = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if dark[y][x] and not seen[y][x]:
                seen[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if dark[y][x] and not seen[y][x]:
                seen[y][x] = True
                q.append((x, y))
    while q:
        cx, cy = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h and dark[ny][nx] and not seen[ny][nx]:
                seen[ny][nx] = True
                q.append((nx, ny))
    for y in range(h):
        for x in range(w):
            if seen[y][x]:
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 0)
    return rgba


def autocrop(img: Image.Image, pad: int = 2) -> Image.Image:
    bbox = img.getbbox()
    if bbox is None:
        return img
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
    x1 = min(img.size[0], x1 + pad); y1 = min(img.size[1], y1 + pad)
    return img.crop((x0, y0, x1, y1))


# (имя, лист, (x0, y0, x1, y1)) — координаты в пикселях листа 1312x1199.
# Категории листа «здания.png»: Жильё и жизнь / Ресурсы / Ремёсла /
# Оборона / Магия / Особые постройки / Декор и окружение.
CROPS = [
    # --- Жильё и жизнь ---
    ("house_l1",   "здания.png", (20, 60, 130, 200)),
    ("house_l2",   "здания.png", (150, 40, 300, 210)),
    ("house_l3",   "здания.png", (330, 30, 500, 215)),
    ("house_tower","здания.png", (510, 45, 610, 215)),
    ("longhouse",  "здания.png", (10, 225, 175, 370)),
    ("manor",      "здания.png", (215, 215, 345, 370)),
    ("keep_tower", "здания.png", (355, 210, 450, 370)),
    ("barn",       "здания.png", (470, 250, 560, 370)),
    ("well",       "здания.png", (565, 255, 650, 370)),
    # --- Ресурсы ---
    ("farm_beds",  "здания.png", (680, 70, 810, 165)),
    ("hedge_grow", "здания.png", (825, 85, 940, 165)),
    ("windmill",   "здания.png", (935, 15, 1035, 170)),
    ("hunter_hut", "здания.png", (1082, 60, 1182, 168)),
    ("sty",        "здания.png", (1180, 75, 1300, 170)),
    ("forester",   "здания.png", (682, 190, 782, 358)),
    ("mine_round", "здания.png", (858, 195, 1008, 365)),
    ("mine_arch",  "здания.png", (1015, 195, 1140, 370)),
    ("quarry",     "здания.png", (1145, 235, 1232, 362)),
    ("cart",       "здания.png", (1238, 250, 1310, 348)),
    # --- Ремёсла ---
    ("forge",      "здания.png", (15, 400, 150, 550)),
    ("crafter_h",  "здания.png", (165, 395, 300, 555)),
    ("workshop",   "здания.png", (315, 380, 430, 560)),
    ("pottery",    "здания.png", (440, 410, 555, 555)),
    ("tannery",    "здания.png", (570, 390, 660, 555)),
    # --- Оборона ---
    ("wall_sec",   "здания.png", (735, 405, 880, 545)),
    ("gate",       "здания.png", (890, 395, 1000, 550)),
    ("tower",      "здания.png", (1090, 385, 1175, 555)),
    ("wall_sec2",  "здания.png", (1180, 430, 1310, 545)),
    # --- Магия ---
    ("altar",      "здания.png", (20, 590, 165, 775)),
    ("obelisk1",   "здания.png", (180, 585, 245, 770)),
    ("obelisk2",   "здания.png", (250, 590, 320, 775)),
    ("magic_temple","здания.png",(325, 560, 430, 780)),
    ("portal",     "здания.png", (445, 575, 520, 780)),
    ("font_basin", "здания.png", (530, 600, 650, 780)),
    # --- Особые постройки ---
    ("tavern",     "здания.png", (640, 600, 785, 778)),
    ("tent",       "здания.png", (785, 625, 900, 775)),
    ("temple",     "здания.png", (905, 545, 1010, 780)),
    ("chapel",     "здания.png", (1015, 585, 1090, 775)),
    ("crypt_arch", "здания.png", (1095, 590, 1180, 775)),
    ("beacon",     "здания.png", (1230, 550, 1310, 775)),
    # --- Декор и окружение (низ листа) ---
    ("statue_1",   "здания.png", (650, 795, 720, 955)),
    ("statue_2",   "здания.png", (725, 790, 790, 955)),
    ("tree_red",   "здания.png", (495, 780, 590, 965)),
    ("bridge_big", "здания.png", (1075, 990, 1310, 1130)),
    ("bridge_pont","здания.png", (770, 1005, 1055, 1115)),
]


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    sheets: dict = {}
    rows = []
    for name, sheet, box in CROPS:
        if sheet not in sheets:
            sheets[sheet] = Image.open(os.path.join(SRC_DIR, sheet)).convert("RGB")
        crop = sheets[sheet].crop(box)
        cut = autocrop(key_black(crop))
        path = os.path.join(OUT, name + ".png")
        cut.save(path)
        print("kit/%s.png %s" % (name, cut.size))
        rows.append((name, cut))
    # контрольный лист: нарезки на тёмно-сером фоне, подписи опущены
    cols = 7
    cell_w = max(r[1].size[0] for r in rows) + 10
    cell_h = max(r[1].size[1] for r in rows) + 10
    grid = Image.new("RGB", (cols * cell_w,
                             ((len(rows) + cols - 1) // cols) * cell_h), (26, 24, 22))
    for i, (name, im) in enumerate(rows):
        gx = (i % cols) * cell_w + 5
        gy = (i // cols) * cell_h + 5
        grid.paste(im, (gx, gy), im)
    grid.save(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "_kit_contact.png"))
    print("контрольный лист: tools/_kit_contact.png")


if __name__ == "__main__":
    main()
