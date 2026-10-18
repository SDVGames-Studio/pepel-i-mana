# -*- coding: utf-8 -*-
# Пропы «предмет-функция» для зданий (M12, замечание приёмки M11):
# производственное здание = рамка-фундамент + характерный предмет
# (наковальня=кузня, верстак=мастерская, котёл=таверна…).
# Сетка символов + палитра -> PNG, как в make_wishlist_sprites.py.
# Запуск: blender -b --python tools/make_props.py
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PROPS = os.path.join(os.path.dirname(HERE), "assets", "sprites", "props")


def P(r, g, b, a=255):
    return (r, g, b, a)


# общий: контур, дерево, сталь
K = P(24, 20, 18)
T = P(122, 84, 48)    # дерево тёмн.
U = P(158, 116, 66)   # дерево светлое
W = P(96, 66, 38)     # колода/тёмное дерево
S = P(148, 152, 160)  # сталь
D = P(96, 100, 110)   # сталь тёмная
SH = P(196, 202, 212)  # сталь светлая
G = P(212, 164, 66)   # латунь/золото
O = P(226, 120, 44)   # огонь
R = P(188, 64, 40)    # угли/руда

STEEL = {"k": K, "S": S, "D": D, "H": SH, "T": T, "U": U, "W": W, "G": G, "O": O, "R": R}

ANVIL = [
    "..kkkkkkkkkkkkkkk.....",
    ".kHHHHHHHHHHHHHHHk....",
    "kSHHkkHHHHHHHkkHHSk...",
    "kSk...kHHHHHk...kSk...",
    ".k....kHHHHHk....k....",
    "......kHHHHHk.........",
    "......kkHHHkk.........",
    ".......kHHHk..........",
    ".......kDHDk..........",
    "....kkkkDDDkkkkk......",
    "...kWWWWDDDDDWWWk.....",
    "...kWWWWDDDDDWWWk.....",
    "....kWWkDDDDDkWWk.....",
    "....kkkkkkkkkkkkk.....",
]

WORKBENCH = [
    "............................",
    "..khhk......kkkk............",
    "..khTk......kSSk............",
    "..khhk..kkkkkSSkkkkk........",
    ".kkkkkkkUUUUUUUUUUUkkkkkkk..",
    ".kTTTTTTUUUTTTTTTUUUTTTTTTk.",
    ".kTTTTTTUUUTTTTTTUUUTTTTTTk.",
    ".kTkTTkUUUTTkTTTTUUUTTkTTk..",
    "..kk.kkUUUkk.kTTTkkk.kk.....",
    "......kUUk...kTTk...........",
    "......kUUk...kTTk...........",
    ".....kkkkk...kkkkk..........",
]

SAWLOG = [
    "..........................",
    "......kkkkkkkkkkkkkkkk....",
    ".....kTTTTTTTTTTTTTTTTk...",
    "....kTTHHTTTTTTTTTTTTTTk..",
    "...kTTTHHTTTTTTTTTTTTTTk..",
    "....kkkTTkkkkkkkkkkkkkk...",
    "...kGGGkTTk...............",
    "..kGkSGGkTTk..............",
    "..kGkSSGGkTk..............",
    "..kGGkSSGGTk..............",
    "...kGGkkSGGTk.............",
    "....kk.kGGGGk.............",
    "........kkkk..............",
]

CAULDRON = [
    "....kkkkkkkkkk......",
    "...kDGGGGGGGGDk.....",
    "..kDDGGGGGGGGDDk....",
    "..kDDDDDDDDDDDDk....",
    ".kDDDDDDDDDDDDDDk...",
    ".kDkkkkkkkkkkkkDk...",
    "kDkGGGGGGGGGGGGkDk..",
    "kDkGGrrGGGGrrGGkDk..",
    "kDkGGGGGGGGGGGGkDk..",
    ".kkDDDDDDDDDDDDkk...",
    "...kkDDDDDDDDkk.....",
    "..O.kkkkkkkkk.O.....",
    ".OOO..O...O..OOO....",
    "OOO.O.OO.OO.O.OOO...",
]

MORTAR = [
    "....kk.kk.kk.....",
    "....kllkllklk....",
    "...kllllllllk....",
    "....kkkkkkkk.....",
    "....kSSSSSSk.....",
    "...kSSSSSSSSk....",
    "...kSHHSSSSSk....",
    "...kSSSSSSSSk....",
    "....kSSSSSSk.....",
    "....kSSSSSSk.....",
    "...kkkkkkkkkk....",
]

CRUCIBLE = [
    "...kkkkkkkkkkkkkk....",
    "..kDDDDDDDDDDDDDDk...",
    "..kDDDDkkkkkkDDDDk...",
    "..kDDDkSSSSSSkDDDk...",
    "..kDDDkSSSSSSkDDDk...",
    "..kDDDDkkkkkkDDDDk...",
    "..kDDDkSSSSSSkDDDk...",
    "..kDDDkSOOOOSkDDDk...",
    "..kDDDkSOOROSkDDDk...",
    "..kDDDkSOROOSkDDDk...",
    "..kDDDDkOOOOKDDDDk...",
    "..kDDDDDkkkkDDDDDk...",
    ".kDDDDDDDDDDDDDDDDk..",
    ".kkkkkkkkkkkkkkkkkk..",
]

RACK = [
    "...kS...kS...kkkk.....",
    "...kS...kS..kSSSSk....",
    "...kS...kS..kSHHSk....",
    "...kS...kS..kSHHSk....",
    "...kD...kD..kSSSSk....",
    "...kD...kD...kSSk.....",
    "..kkkkk.kkkk..kk......",
    "..kUUUkkkUUUkk........",
    "..kUUUUUUUUUUk........",
    "..kUkkTTTTkkUk........",
    "..kUkTTTTTTkUk........",
    "..kkkTTTTTTkkk........",
    "....kTTTTTTk..........",
    "....kkkkkkkk..........",
]

CRATES = [
    "kkkkkkkkkkkk..kkkkkk....",
    "kUUUUUUUUUUk..kTTTTk....",
    "kUkkkkkkkkUk..kTkTk.....",
    "kUkTTTTTTkUk..kTTTk.....",
    "kUkTkTTkTkUk..kkkkkk....",
    "kUkTTTTTTkUk............",
    "kUkkkkkkkkUk..ssssss....",
    "kUUUUUUUUUUk..sSSSSs....",
    "kUkkkkkkkkUk..sSSSSs....",
    "kUkTTTTTTkUk..ssssss....",
    "kkkkkkkkkkkk............",
]

STALL = [
    "..kkkkkkkkkkkkkkkkkkk....",
    ".krrwwrrwwrrwwrrwwrrwk...",
    ".kwwrrwwrrwwrrwwrrwwk....",
    ".kkkkkkkkkkkkkkkkkkkk....",
    "..kR................Rk...",
    "..kR.kUUUUUUUUUUUUk.Rk...",
    "..kR.kUUTTTTTTTTUUk.Rk...",
    "..kR.kUUTkkkkkkTTUk.Rk...",
    "..kR.kUUTkGGGGkTTUk.Rk...",
    "..kR.kUUTkGhhGkTTUk.Rk...",
    "..kk.kUUUkGGGGkUUUk.kk...",
    ".....kUUUUUUUUUUUUk......",
    ".....kkkkkkkkkkkkkk......",
]

MINECART = [
    "..........................",
    "...kkkkkkkkkkkkkkkk.......",
    "..kRRRRRRRRRRRRRRRRk......",
    ".kRRddRRRRRdddRRRRRRk.....",
    ".kRdddRRRRRdddRRRRRRRk....",
    ".kkkkkkkkkkkkkkkkkkkkk....",
    ".kDDDDDDDDDDDDDDDDDDDk....",
    "..kDDDDDDDDDDDDDDDDk......",
    "...kDDDk......kDDDDk......",
    "...kkkkk......kkkkkk......",
]

TOOLS_STONE = [
    "....kkkkkkkkkkk......",
    "..kkSSSSSSSSSSSkk....",
    ".kSSHHHSSSSSHHSSSk...",
    ".kSHHHHSSSSHHHSSSk...",
    ".kSSHHSSSSSSHHSSSk...",
    ".kkSSSSSSSSSSSSSkk...",
    "..kkkkkkkkkkkkkkk....",
    "..kDDk...kk...kDDk...",
    "...kk...kSSk...kk....",
    "........kSSk.........",
    "........kkkk.........",
    ".......kSSk..........",
    "......kSSSk..........",
    "......kkkk...........",
]

HAY = [
    "......kddk.........",
    "....kddhhddk.......",
    "...kdhhhhhhdk......",
    "..kdhhhlhhhhdk.....",
    "..kdhlllhhhhddk....",
    ".kdhhlllhhhhhhdk...",
    ".kdhhlllhhhhhhhdk..",
    "kdhhhlllhhhhhhhhdk.",
    "kdhhlhlhhhhhlhhhhk.",
    "kdhhhhhhhhhhllhhdk.",
    "kddhhhhhhhhhllhhdk.",
    "kddddhhhhhhhllhddk.",
    "kkddddddddddddddkk.",
    "..kkkkkkkkkkkkkk...",
]

PALETTES = {
    "anvil": STEEL,
    "workbench": dict(STEEL, h=P(196, 202, 212)),
    "sawlog": dict(STEEL, G=P(206, 160, 70)),
    "cauldron": dict(STEEL, G=P(126, 186, 92), r=P(86, 140, 70)),
    "mortar": dict(STEEL, l=P(104, 146, 68), S=P(190, 182, 170), H=P(214, 208, 196)),
    "crucible": dict(STEEL, S=P(150, 150, 156)),
    "rack": STEEL,
    "crates": dict(STEEL, T=P(150, 108, 58), U=P(184, 138, 76), s=P(196, 168, 106), S=P(224, 198, 130)),
    "stall": dict(STEEL, r=P(198, 72, 60), w=P(232, 226, 210), R=P(120, 84, 48), G=P(206, 160, 70), h=P(120, 170, 90)),
    "minecart": dict(STEEL, R=P(150, 108, 62), d=P(122, 86, 50)),
    "tools_stone": dict(STEEL, S=P(146, 142, 132), H=P(178, 174, 162)),
    "hay": dict(STEEL, d=P(168, 122, 52), h=P(214, 172, 84), l=P(238, 206, 122)),
}

SPRITES = [
    ("anvil", ANVIL),
    ("workbench", WORKBENCH),
    ("sawlog", SAWLOG),
    ("cauldron", CAULDRON),
    ("mortar", MORTAR),
    ("crucible", CRUCIBLE),
    ("rack", RACK),
    ("crates", CRATES),
    ("stall", STALL),
    ("minecart", MINECART),
    ("tools_stone", TOOLS_STONE),
    ("hay", HAY),
]


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


def make_preview(made):
    f = 4
    pad = 8
    imgs = [[[(0, 0, 0, 0) for _ in row] for row in px] for _, px in made]
    for i, (_, px) in enumerate(made):
        imgs[i] = px
    w = sum(len(i[0]) * f + pad for i in imgs) + pad
    h = max(len(i) for i in imgs) * f + 2 * pad
    sheet = [[(40, 44, 52, 255) for _ in range(w)] for _ in range(h)]
    x = pad
    for img in imgs:
        for yy, row in enumerate(img):
            for xx, col in enumerate(row):
                if col[3] > 0:
                    for fy in range(f):
                        for fx in range(f):
                            sheet[pad + yy * f + fy][x + xx * f + fx] = col
        x += len(img[0]) * f + pad
    write_png(os.path.join(HERE, "props_preview.png"), sheet)


def main():
    os.makedirs(PROPS, exist_ok=True)
    made = []
    for name, grid in SPRITES:
        widths = {len(row) for row in grid}
        if len(widths) != 1:
            raise SystemExit("%s: строки разной длины: %s" % (name, widths))
        pal = PALETTES[name]
        px = [[pal.get(ch, (0, 0, 0, 0)) for ch in row] for row in grid]
        write_png(os.path.join(PROPS, name + ".png"), px)
        made.append((name, px))
        print("ok", name, len(grid[0]), "x", len(grid))
    make_preview(made)
    print("OK")


main()
