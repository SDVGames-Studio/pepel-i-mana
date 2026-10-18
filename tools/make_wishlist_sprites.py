# -*- coding: utf-8 -*-
# Спрайты вишлиста M11: деревья с явным стволом, саженцы, меч героя,
# дух леса, Древень (босс леса), кладбище. Запуск через Blender headless:
#   blender -b --python tools/make_wishlist_sprites.py
# Плюс: копия 18 домов из F:/kust/new-world-v-2/assets/dom и скал rocky-area.
# Результат: assets/sprites/env/*.png, assets/sprites/buildings/*.png,
# превью tools/wishlist_preview.png, tools/dom_sheet.png.
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ENV = os.path.join(GAME, "assets", "sprites", "env")
BLD = os.path.join(GAME, "assets", "sprites", "buildings")
REF = "F:/kust/new-world-v-2/assets"

# общие цвета
OUT = (0, 0, 0, 0)


def P(r, g, b, a=255):
    return (r, g, b, a)


# ---------------------------------------------------------------- деревья ----
# 24x36. '.' прозрачный. Ствол заметный: 6px ширина, ~10-12px высота.

PAL_LEAF = {
    "k": P(24, 30, 18),      # контур листвы
    "d": P(34, 62, 30),      # тень листвы
    "l": P(58, 96, 44),      # листва
    "h": P(84, 128, 58),     # свет листвы
    "t": P(66, 44, 26),      # ствол тень
    "T": P(104, 72, 42),     # ствол
    "u": P(134, 98, 58),     # ствол свет
    "g": P(120, 70, 30),     # сучок
}

OAK = [
    "........kkkkkk..........",
    "......kklhhhhlkk........",
    ".....klhhhhhhhldk.......",
    "....klhhhhhhhhhhldk.....",
    "...kdlhhhhhhhhhhhldk....",
    "..kdllhhhhhhhhhhhlllk...",
    ".kdlleehhhhhhhheellldk..",
    ".kdlleehhhhhhhheellldk..",
    "kdllheehhhhhhhheehllldk.",
    "kdlheeeeeehheeeeeehlldk.",
    "kdheeeeeeeeeeeeeeeehldk.",
    "kdeellllleeeeeelllleedk.",
    "kdeehhhhhllllllhhhhheedk",
    "kdeehhhhhllllllhhhhheedk",
    ".kdehhhhhllllllhhhhhedk.",
    ".kdehhhhhllllllhhhhhedk.",
    "..kdhhhhhllllllhhhhdk...",
    "..kddhhhhhllllhhhddk....",
    "...kddhhhhhhhhhhddk.....",
    "....kddddhhhhhdddk......",
    ".....kkddddddddkk.......",
    ".......kkddddkk.........",
    "........kgtttgk.........",
    "........kTuttuk.........",
    "........kTuttuk.........",
    "........kTuttTk.........",
    "........kTutTTk.........",
    "........kTutTTk.........",
    ".......kuTutTTk.........",
    ".......kuTutTTk.........",
    "......kuTTutTTTk........",
    "......kuTTutTTTk........",
    ".....kuTTTttTTTTk.......",
    ".....kttttttttttk.......",
    "......kkkkkkkkkk........",
    "........................",
]

PINE_PAL = {
    "k": P(16, 30, 20),
    "d": P(22, 52, 34),
    "l": P(34, 78, 48),
    "h": P(52, 108, 64),
    "t": P(60, 40, 24),
    "T": P(96, 66, 38),
}

PINE = [
    "...........kk...........",
    "..........khhk..........",
    ".........khhhhk.........",
    ".........klhhlk.........",
    "........kllhhllk........",
    ".......kllhhhlllk.......",
    ".......kdlhhlldk........",
    "......kdllhhllldk.......",
    ".....kdlhhhhhhldk.......",
    ".....kdllhhhllldk.......",
    "....kdllhhhhhllldk......",
    "....kdlhhhhhhhhldk......",
    "...kdllhhhhhhhhlldk.....",
    "...kdlhhhhhhhhhhldk.....",
    "..kdllhhhhhhhhhhlldk....",
    "..kdlhhhhhhhhhhhhldk....",
    ".kdllhhhhhhhhhhhhllldk..",
    ".kdlhhhhhhhhhhhhhhhldk..",
    "kdllhhhhhhhhhhhhhhllldk.",
    "kddhhhhhhhhhhhhhhhhhddk.",
    ".kkdddddddddddddddddkk..",
    "..........kTTk..........",
    "..........kTTk..........",
    "..........kTTk..........",
    ".........kuTTTk.........",
    ".........kuTTTk.........",
    "........kuTTTTTk........",
    "........kuTTTTTk........",
    ".......kuTTTTTTTk.......",
    ".......kttttttttk.......",
    "........kkkkkkkk........",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
]

BIRCH_PAL = {
    "k": P(26, 34, 24),
    "d": P(66, 100, 56),
    "l": P(104, 140, 74),
    "h": P(150, 178, 96),
    "w": P(214, 214, 200),   # белая кора
    "W": P(238, 238, 226),
    "b": P(40, 40, 40),      # чёрные чёрточки
}

BIRCH = [
    ".........kkkk...........",
    ".......kkdhhdkk.........",
    "......klhhhhhllk........",
    ".....klhhhhhhhhlk.......",
    "....klhhhhhhhhhhlk......",
    "...klhhhhhhhhhhhhdk.....",
    "...khhhhhhhhhhhhhhk.....",
    "..khhhhhhdllldhhhhhk....",
    "..khhhhhdlhhhldhhhhk....",
    "..khhhhhdlhhhldhhhhk....",
    "...khhhhdllllldhhhk.....",
    "...kdhhhhhhhhhhhhdk.....",
    "....kdhhhhhhhhhhk.......",
    ".....kkdhhhhhhkk........",
    ".......kkddddkk.........",
    "........kWbbWk..........",
    "........kWbbWk..........",
    "........kWWWbk..........",
    "........kbWWWk..........",
    "........kWbbWk..........",
    "........kbWWWk..........",
    "........kWbbWk..........",
    ".......kuWWbWk..........",
    ".......kuWWWbk..........",
    "......kuWWbbWk..........",
    "......kuWWWWbk..........",
    ".....kuWWbbWWk..........",
    ".....kuWWWWWbk..........",
    "....kuWWbbWWWk..........",
    "....kttttttttk..........",
    ".....kkkkkkkk...........",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
]

AUTUMN_PAL = {
    "k": P(46, 26, 14),
    "d": P(132, 62, 24),
    "l": P(190, 106, 36),
    "h": P(232, 158, 58),
    "r": P(156, 48, 30),
    "t": P(66, 44, 26),
    "T": P(104, 72, 42),
}

AUTUMN = [
    "........kkkkkk..........",
    "......kklhhhhlkk........",
    ".....klhhhhhhhhdk.......",
    "....klhhhhlrhhhhldk.....",
    "...kdlhhhhrrelhhlldk....",
    "..kdllhhhhreeerhllllk...",
    ".kdlhhhllhrreeehlllhdk..",
    ".kdlhhlllhhhrehllllhdk..",
    "kdllhhlllhhhhhhllllhldk.",
    "kdlhhllhhhhhhhhhlllhldk.",
    "kdhhllhhhhhhhhhhhhllhdk.",
    "kdeelllhhhhhhhhhhllleedk",
    "kdeehhlllhhhhhhllhhheedk",
    "kdeehllllhhhhhhlllhheedk",
    ".kdehllllhhhhhhlllheedk.",
    ".kdeellllhhhhhhlllleedk.",
    "..kdellllhhhhhhllledk...",
    "..kddelllhhhhhhlledk....",
    "...kddellhhhhhhhedk.....",
    "....kdddellhhheddk......",
    ".....kkdddddddddkk......",
    ".......kkdddddkk........",
    "........kTtttTk.........",
    "........kTuttTk.........",
    "........kTuttTk.........",
    "........kTuttTk.........",
    ".......kuTuttTk.........",
    ".......kuTuttTk.........",
    "......kuTTuttTk.........",
    "......kuTTutTTk.........",
    ".....kuTTTutTTTk........",
    ".....kuTTTttTTTk........",
    "....kuTTTttttTTTk.......",
    "....ktttttttttttk.......",
    ".....kkkkkkkkkkk........",
    "........................",
]

FRUIT_PAL = dict(PAL_LEAF)
FRUIT_PAL["r"] = P(198, 52, 48)
FRUIT_PAL["R"] = P(238, 92, 70)

FRUIT = [
    "........kkkkkk..........",
    "......kklhhhhlkk........",
    ".....klhhhhhhhldk.......",
    "....klhhhrhhhhhhldk.....",
    "...kdlhhhhhhhhrhhldk....",
    "..kdllhhhhhhhhhhhlllk...",
    ".kdllhhrhhhhhhhhellldk..",
    ".kdllehhrhhhhheelhllldk.",
    "kdllheeeeeehheeeerlllldk",
    "kdlheeeeeehheeeeeehllldk",
    "kdheeeeeeeeeeeeeeeehrldk",
    "kdeellllleeeeeelllleedk.",
    "kdeehhhhhlllrllhhhhheedk",
    "kdeehhhhhllllllhhhrheedk",
    ".kdehhhhhllllllhhhhhedk.",
    ".kderhhhhllllllhhhhredk.",
    "..kdhhhhhlllrllhhhhdk...",
    "..kddhhhhhllllhhhrdk....",
    "...kddhhhhhhhhhhhdk.....",
    "....kddddhhhhhdddk......",
    ".....kkddddddddkk.......",
    ".......kkddddkk.........",
    "........kTtttTk.........",
    "........kTuttTk.........",
    "........kTuttTk.........",
    "........kTuttTk.........",
    ".......kuTuttTk.........",
    ".......kuTuttTk.........",
    "......kuTTutTTk.........",
    "......kuTTutTTk.........",
    ".....kuTTTutTTTk........",
    ".....kuTTTttTTTk........",
    "....kuTTTttttTTTk.......",
    "....ktttttttttttk.......",
    ".....kkkkkkkkkkk........",
    "........................",
]

OLD_PAL = {
    "k": P(30, 26, 22),
    "T": P(88, 76, 62),
    "u": P(118, 104, 84),
    "g": P(70, 60, 48),
    "m": P(52, 48, 40),
}

OLD = [
    "............k...........",
    ".....k.....kgk....k.....",
    "....kgk...kgkgk..kgk....",
    "....kgk..kgk.kgk.kgk....",
    "...kg.kg.kgk.kgk.kg.k...",
    "...kgesk.kgk.kgk.ksegk..",
    "....kggeskgeskgesegk....",
    ".....kgesgesgesgsek.....",
    "......kgsagesagsek......",
    ".......kgssssssgk.......",
    "........kumumuuk........",
    "........kTTuTTk.........",
    ".......kuTTuTTk.........",
    ".......kuTTuTTk.........",
    "......kuTTTuTTTk........",
    "......kuTTTuTTTk........",
    ".....kuTTTTuTTTTk.......",
    ".....kuTTTTuTTTTk.......",
    "....kuTTTTTuTTTTTk......",
    "....kuTTTTTuTTTTTk......",
    "...kuTTTTTTuTTTTTTk.....",
    "...kuTTTTTTuTTTTTTk.....",
    "..kuTTTTTTTuTTTTTTTk....",
    "..kmmmmmmmmmmmmmmmmk....",
    "...kkkkkkkkkkkkkkkk.....",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
]

# ------------------------------------------------- саженцы (2 стадии) --------
SAP_PAL = {
    "k": P(28, 44, 22),
    "l": P(72, 110, 50),
    "h": P(104, 146, 68),
    "t": P(96, 66, 38),
}

SAP1 = [
    "........",
    "...kl...",
    "..khlk..",
    "...kt...",
    "...kt...",
    "..kttk..",
    "........",
]

SAP2 = [
    "..........",
    "...kllk...",
    "..kllhlk..",
    ".klhhhlhk.",
    ".klhllhlk.",
    "..kllllk..",
    "...kttk...",
    "...kttk...",
    "..kttttk..",
    "..........",
]

# --------------------------------------------------------- меч героя ---------
SWORD_PAL = {
    "k": P(20, 22, 28),
    "s": P(150, 158, 172),
    "S": P(210, 216, 228),
    "g": P(150, 108, 44),
    "G": P(206, 160, 70),
    "h": P(84, 58, 32),
}

SWORD = [
    ".....kk..",
    ".....kSk.",
    ".....kSk.",
    ".....kSk.",
    ".....kSk.",
    ".....kSk.",
    ".....kSk.",
    ".....kSk.",
    ".....kSk.",
    "....kkSkk",
    "..kkgGgk.",
    ".kGGGGk..",
    ".kkGkk...",
    "..khk....",
    "..khk....",
    ".khhk....",
]

# ----------------------------------------------------------- дух леса --------
SPIRIT_PAL = {
    "k": P(30, 52, 56),
    "b": P(96, 168, 160),
    "B": P(160, 220, 208),
    "w": P(226, 248, 240),
    "e": P(24, 40, 48),
}

SPIRIT = [
    "....kkkkkk....",
    "...kBBBBBBk...",
    "..kBBwwwwBBk..",
    "..kBwwwwwBbk..",
    ".kBwwewewwBk..",
    ".kBwwewewwbk..",
    ".kBwwwwwwbbk..",
    ".kBwwwbwwwbk..",
    ".kBbwwwwbbbk..",
    "..kBbbbbbbk...",
    "..kBbbwbbbbk..",
    "..kBbwbbwbbk..",
    "..kBbwb.wbbk..",
    "...kb..b..bk..",
    "....b..b...b..",
    "..............",
]

# ------------------------------------------- Древень (босс леса) 26x40 -------
TREANT_PAL = {
    "k": P(26, 34, 20),
    "T": P(78, 58, 34),
    "u": P(112, 84, 48),
    "d": P(44, 78, 36),
    "l": P(64, 110, 46),
    "h": P(90, 142, 60),
    "e": P(255, 196, 64),
    "m": P(40, 30, 18),
}

TREANT = [
    "....khhk........khk.......",
    "...khllhk......khllk......",
    "...kdlhlk.....khlldk......",
    "....kdlk......kdldk.......",
    ".....kdTk....kuTdk........",
    ".....kuTTk..kuTTk.........",
    "......kuTTkkuTTk..........",
    ".......kuTTTTTk...........",
    "........kuTTTk............",
    "......kuTTTTTTTku.........",
    "....kuTTTuuuuTTTTk........",
    "...kuTTTuuuuuuTTTTk.......",
    "..kuTTTuuuuuuuuTTTTk......",
    "..kuTTuuuTTTTuuuTTTk......",
    ".kuTTuuuTTTTTTuuuTTTk.....",
    ".kuTTuuTThemeeTuuuTTk.....",
    "kuTTTuuTTekekekTuuuTTk....",
    "kuTTTuuTTkmmmkmTuuuTTTk...",
    "kuTTTuuuTTTmmmTTuuuTTTk...",
    "kuTTTuuuTTTTTTTTuuuTTTk...",
    "kuTTTuuuTmmmmmmmTuuuTTk...",
    "kuTTTuuuTmmmmmmmTuuuTTk...",
    ".kuTTuuuTTmmmmmTTuuuTTk...",
    ".kuTTuuTTTmmmmmTTTuuTTk...",
    ".kuTTuuuTTTmmmTTTuuuTTk...",
    "..kuTuuuuTTTmTTTuuuuTTk...",
    "..kuTTuuuuTTTTTuuuuuTTk...",
    "...kuTTTuuuuuuuuuuTTTk....",
    "...kuTTTTTuuuuuuuTTTTk....",
    "....kuTTTTTuuuuTTTTTk.....",
    ".....kuTTTTTTTTTTTkk......",
    ".....kuTTTTkkuTTTTk.......",
    "....kuTTTTk.kuTTTTk.......",
    "....kuTTTk...kuTTTk.......",
    "...kuTTTTk...kuTTTTk......",
    "...kmmmmmk...kmmmmmk......",
    "....kkkkk.....kkkkk.......",
]

# ------------------------------------------------------------- кладбище ------
CEMETERY_PAL = {
    "k": P(26, 30, 24),
    "g": P(58, 74, 44),      # тёмная трава
    "G": P(78, 92, 54),
    "s": P(132, 134, 128),   # камень
    "S": P(174, 176, 168),
    "d": P(96, 98, 94),
    "w": P(104, 84, 56),     # дерево креста
}

CEMETERY = [
    "..............................",
    "..........kk......kk..........",
    "..........kSk......kSk........",
    "..........kSk.....kkSkk.......",
    "..........kSk.....kwSk........",
    "..........kSk.....kwSk........",
    "..........kSk.....kwSk........",
    ".....kk...kSk.....kwSk...kk...",
    "....kSkk.kSSkk...kkSSkk.kSkk..",
    "....kSSkkSSSSk...kSSSSkkSSk...",
    "...kkSSkSSSSSkk.kSSSSSkkSSkk..",
    "..kgggggggggggggggggggggggggk.",
    ".kgGgGgGgGgGgGgGgGgGgGgGgGgGk.",
    ".kgGgGgdgggdggGgGgdgggdgGgGGk.",
    ".kgGgGgggggggGgGgGgggggggGgGk.",
    "..kkkkkkkkkkkkkkkkkkkkkkkkkk..",
]

# ------------------------------------------------------------- сборка --------

def write_png(path, px):
    h = len(px)
    w = len(px[0])
    raw = b""
    for row in px:
        raw += b"\x00"
        for r, g, b, a in row:
            raw += struct.pack("4B", r, g, b, a)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def grid_to_px(grid, pal):
    return [[pal.get(ch, OUT) for ch in row] for row in grid]


def scale_px(px, f):
    out = []
    for row in px:
        wide = []
        for p in row:
            wide.extend([p] * f)
        out.extend([wide] * f)
    return out


SPRITES = [
    ("tree_oak", OAK, PAL_LEAF),
    ("tree_pine", PINE, PINE_PAL),
    ("tree_birch", BIRCH, BIRCH_PAL),
    ("tree_autumn", AUTUMN, AUTUMN_PAL),
    ("tree_fruit2", FRUIT, FRUIT_PAL),
    ("tree_old", OLD, OLD_PAL),
    ("sap1", SAP1, SAP_PAL),
    ("sap2", SAP2, SAP_PAL),
    ("sword", SWORD, SWORD_PAL),
    ("spirit", SPIRIT, SPIRIT_PAL),
    ("treant", TREANT, TREANT_PAL),
    ("cemetery", CEMETERY, CEMETERY_PAL),
]


def make_previews(made):
    """Превью x5 всех новых спрайтов в один лист."""
    f = 5
    pad = 8
    imgs = [scale_px(px, f) for _, px, _ in made]
    w = sum(i and len(i[0]) + pad for i in imgs) + pad
    h = max(len(i) for i in imgs) + 2 * pad
    sheet = [[(40, 44, 52, 255) for _ in range(w)] for _ in range(h)]
    x = pad
    for img in imgs:
        for yy, row in enumerate(img):
            for xx, col in enumerate(row):
                if col[3] > 0:
                    sheet[pad + yy][x + xx] = col
        x += len(img[0]) + pad
    write_png(os.path.join(HERE, "wishlist_preview.png"), sheet)


def copy_refs():
    """Дома из assets/dom (18 шт) и скалы rocky-area — в проект."""
    import shutil
    dom_src = os.path.join(REF, "dom", "PNG", "buildings")
    n = 0
    for i in range(1, 19):
        src = os.path.join(dom_src, "building_%d" % i, "building_1.png")
        dst = os.path.join(BLD, "dom%d.png" % i)
        if os.path.exists(src):
            shutil.copyfile(src, dst)
            n += 1
    print("dom copied:", n)
    rock_src = os.path.join(REF, "craftpix-net-639143-free-rocky-area-objects-pixel-art",
                            "PNG", "Objects_separately")
    picks = ["Oval_rock2_grass_shadow.png", "Oval_rock3_grass_shadow.png",
             "Oval_rock5_grass_shadow.png", "Cave_entrance1_grass_shadow.png"]
    for j, name in enumerate(picks, 1):
        src = os.path.join(rock_src, name)
        dst = os.path.join(ENV, "mrock%d.png" % j)
        if os.path.exists(src):
            shutil.copyfile(src, dst)
    print("rocks copied")


def make_dom_sheet():
    """Контактный лист 18 домов (по 6 в ряду, высота 180) — для выбора маппинга."""
    import shutil

    def read_png_wh(path):
        with open(path, "rb") as f:
            data = f.read(33)
        w = int.from_bytes(data[16:20], "big")
        h = int.from_bytes(data[20:24], "big")
        return w, h

    rows, cols = 3, 6
    cell_w, cell_h = 240, 200
    sheet = [[(46, 50, 58, 255) for _ in range(cols * cell_w)] for _ in range(rows * cell_h)]
    for i in range(18):
        path = os.path.join(BLD, "dom%d.png" % (i + 1))
        if not os.path.exists(path):
            continue
        w, h = read_png_wh(path)
        f = min(180.0 / h, 220.0 / w)
        nw, nh = max(1, int(w * f)), max(1, int(h * f))
        # ближайший сосед по решётке позиций (просто превью, не арт)
        ox = (i % cols) * cell_w + (cell_w - nw) // 2
        oy = (i // cols) * cell_h + (cell_h - nh) // 2
        # читаем PNG целиком через zlib (без PIL): декодируем свой же формат
        with open(path, "rb") as fobj:
            data = fobj.read()
        # deflate-поток между IDAT-чанками
        idat = b""
        pos = 8
        while pos < len(data):
            ln = int.from_bytes(data[pos:pos + 4], "big")
            tag = data[pos + 4:pos + 8]
            if tag == b"IDAT":
                idat += data[pos + 8:pos + 8 + ln]
            pos += 12 + ln
        raw = zlib.decompress(idat)
        stride = w * 4 + 1
        for y in range(0, h, max(1, h // nh)):
            row = raw[y * stride + 1:(y + 1) * stride]
            ty = oy + (y * nh) // h
            if ty >= (i // cols + 1) * cell_h:
                break
            for x in range(0, w, max(1, w // nw)):
                px = row[x * 4:x * 4 + 4]
                if len(px) < 4 or px[3] < 128:
                    continue
                tx = ox + (x * nw) // w
                if 0 <= ty < len(sheet) and 0 <= tx < len(sheet[0]):
                    sheet[ty][tx] = (px[0], px[1], px[2], 255)
    write_png(os.path.join(HERE, "dom_sheet.png"), sheet)


def main():
    os.makedirs(ENV, exist_ok=True)
    os.makedirs(BLD, exist_ok=True)
    made = []
    for name, grid, pal in SPRITES:
        widths = {len(row) for row in grid}
        if len(widths) != 1:
            raise SystemExit("%s: строки разной длины: %s" % (name, widths))
        px = grid_to_px(grid, pal)
        write_png(os.path.join(ENV, name + ".png"), px)
        made.append((name, px, pal))
    make_previews(made)
    copy_refs()
    make_dom_sheet()
    print("OK")


main()
