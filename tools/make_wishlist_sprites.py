# -*- coding: utf-8 -*-
# Спрайты вишлиста M11 (v2): деревья со стволом строятся ГЕНЕРАТОРОМ —
# профиль кроны + дизеринг трёх тонов + широкий ствол с расширением к низу.
# Плюс: копия 18 домов из F:/kust/new-world-v-2/assets/dom и скал rocky-area.
# Запуск: blender -b --python tools/make_wishlist_sprites.py
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ENV = os.path.join(GAME, "assets", "sprites", "env")
BLD = os.path.join(GAME, "assets", "sprites", "buildings")
REF = "F:/kust/new-world-v-2/assets"


def P(r, g, b, a=255):
    return (r, g, b, a)


def _h(x, y, n=97, s=0):
    v = (x * 73856093 + y * 19349663 + s * 83492791) & 0x7FFFFFFF
    return v % max(1, n)


# ------------------------------------------------- генератор круглой кроны ----

PAL_LEAF = {
    "k": P(24, 30, 18),
    "d": P(38, 66, 32),
    "l": P(58, 96, 44),
    "h": P(88, 132, 62),
    "m": P(30, 44, 26),
    "t": P(66, 44, 26),
    "T": P(104, 72, 42),
    "u": P(134, 98, 58),
}

PAL_AUTUMN = {
    "k": P(46, 26, 14),
    "d": P(132, 62, 24),
    "l": P(190, 106, 36),
    "h": P(232, 158, 58),
    "m": P(110, 44, 20),
    "t": P(66, 44, 26),
    "T": P(104, 72, 42),
    "u": P(134, 98, 58),
    "r": P(198, 52, 48),
}

PAL_PINE = {
    "k": P(16, 30, 20),
    "d": P(22, 52, 34),
    "l": P(34, 78, 48),
    "h": P(56, 112, 66),
    "m": P(16, 36, 24),
    "t": P(60, 40, 24),
    "T": P(96, 66, 38),
    "u": P(122, 88, 52),
}

PAL_FRUIT = dict(PAL_LEAF)
PAL_FRUIT["r"] = P(214, 60, 52)
PAL_FRUIT["R"] = P(240, 110, 84)


def build_tree(pal, seed=1, style="round", W=26, trunk_rows=15, dots=None):
    """Крона по профилю + дизеринг, ствол с расширением к низу."""
    if style == "cone":
        prof = [1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12]
        trunk_rows = 9
    else:
        prof = [2, 4, 6, 8, 9, 10, 11, 12, 12, 13, 13, 13, 13, 12, 12, 11, 10, 9, 8, 6, 4, 2]
    H = len(prof)
    cx = W // 2
    total = H + trunk_rows
    grid = [["." for _ in range(W)] for _ in range(total)]
    # --- крона ---
    for y in range(H):
        half = prof[y]
        wob = 1 if (y // 4) % 2 == 0 else -1
        ccx = cx + (wob if style == "round" else 0)
        for x in range(ccx - half, ccx + half + 1):
            if x < 0 or x >= W:
                continue
            edge = abs(x - ccx) == half or y == 0 or y == H - 1
            if edge:
                grid[y][x] = "k"
                continue
            t = abs(x - ccx) / max(1.0, float(half))
            ny = y / float(H - 1)
            if style == "cone":
                band = ny
            else:
                band = t * 0.75 + (ny - 0.3) * 0.45
            r = _h(x, y, 100, seed)
            if band < 0.34:
                grid[y][x] = "h"
            elif band < 0.68:
                grid[y][x] = "l" if r > 28 else "h"
            else:
                grid[y][x] = "d" if r > 18 else "l"
            if r < 2 and style == "round":
                grid[y][x] = "m"
    if dots:
        for dx, dy, ch in dots:
            if 0 <= dy < H and 0 <= dx < W and grid[dy][dx] not in ("." , "k"):
                grid[dy][dx] = ch
    # --- ствол ---
    ty0 = H - 2
    for i in range(trunk_rows):
        y = ty0 + i
        flare = 0 if i < trunk_rows - 5 else (i - (trunk_rows - 6) + 1) // 2
        half = (2 if style != "cone" else 1) + flare
        for x in range(cx - half - 1, cx + half + 2):
            if x < 0 or x >= W:
                continue
            if x == cx - half - 1 or x == cx + half + 1:
                grid[y][x] = "k"
            elif x >= cx + half:
                grid[y][x] = "u"
            elif x <= cx - half + 1:
                grid[y][x] = "t"
            else:
                grid[y][x] = "T"
    # нижний обрез темнее
    yb = total - 1
    for x in range(W):
        if grid[yb][x] != ".":
            grid[yb][x] = "t"
    return ["".join(row) for row in grid]


FRUIT_DOTS = [(7, 6, "r"), (14, 5, "r"), (11, 10, "R"), (17, 11, "r"), (6, 13, "R"), (13, 15, "r")]

OAK = build_tree(PAL_LEAF, seed=3)
AUTUMN = build_tree(PAL_AUTUMN, seed=7)
FRUIT = build_tree(PAL_FRUIT, seed=3, dots=FRUIT_DOTS)
PINE = build_tree(PAL_PINE, seed=5, style="cone")

# ------------------------------------------------------------- берёза --------
BIRCH_PAL = {
    "k": P(26, 34, 24),
    "d": P(66, 100, 56),
    "l": P(104, 140, 74),
    "h": P(150, 178, 96),
    "w": P(214, 214, 200),
    "W": P(238, 238, 226),
    "b": P(40, 40, 40),
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
]

# --------------------------------------------------------- сухостой ----------
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
    "g": P(58, 74, 44),
    "G": P(78, 92, 54),
    "s": P(132, 134, 128),
    "S": P(174, 176, 168),
    "d": P(96, 98, 94),
    "w": P(104, 84, 56),
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
    return [[pal.get(ch, (0, 0, 0, 0)) for ch in row] for row in grid]


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
    ("tree_pine", PINE, PAL_PINE),
    ("tree_birch", BIRCH, BIRCH_PAL),
    ("tree_autumn", AUTUMN, PAL_AUTUMN),
    ("tree_fruit2", FRUIT, PAL_FRUIT),
    ("tree_old", OLD, OLD_PAL),
    ("sap1", SAP1, SAP_PAL),
    ("sap2", SAP2, SAP_PAL),
    ("sword", SWORD, SWORD_PAL),
    ("spirit", SPIRIT, SPIRIT_PAL),
    ("treant", TREANT, TREANT_PAL),
    ("cemetery", CEMETERY, CEMETERY_PAL),
]


def make_previews(made):
    f = 4
    pad = 8
    imgs = [scale_px(px, f) for _, px, _ in made]
    w = sum(len(i[0]) + pad for i in imgs) + pad
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
    print("OK")


main()
