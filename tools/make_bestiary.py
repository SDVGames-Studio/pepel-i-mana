# -*- coding: utf-8 -*-
# Спрайты вишлиста M13: ангелы/демоны/нежить, замки драконов.
# Сетка символов + палитра -> PNG (как в make_wishlist_sprites.py).
# Запуск: blender -b --python tools/make_bestiary.py
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ENV = os.path.join(GAME, "assets", "sprites", "env")
BLD = os.path.join(GAME, "assets", "sprites", "buildings")


def P(r, g, b, a=255):
    return (r, g, b, a)


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
    w = max(len(row) for row in grid)
    rows = [row.ljust(w, ".") for row in grid]
    return [[pal.get(ch, (0, 0, 0, 0)) for ch in row] for row in rows]


def scale_px(px, f):
    out = []
    for row in px:
        wide = []
        for p in row:
            wide.extend([p] * f)
        out.extend([wide] * f)
    return out


# ------------------------------------------------------------- палитры -------

PAL_GHOUL = {
    "k": P(22, 18, 22),
    "s": P(112, 136, 96),
    "d": P(80, 100, 66),
    "h": P(152, 174, 120),
    "e": P(206, 62, 50),
    "t": P(56, 46, 56),
    "r": P(78, 64, 80),
}

PAL_WRAITH = {
    "k": P(16, 14, 24),
    "c": P(60, 56, 84),
    "d": P(42, 38, 62),
    "h": P(90, 86, 120),
    "e": P(130, 226, 236),
}

PAL_IMP = {
    "k": P(26, 10, 12),
    "s": P(172, 54, 44),
    "d": P(122, 34, 30),
    "h": P(212, 88, 64),
    "e": P(242, 202, 82),
    "w": P(62, 20, 26),
}

PAL_HELL = {
    "k": P(22, 8, 10),
    "b": P(74, 30, 34),
    "d": P(52, 20, 26),
    "f": P(244, 138, 42),
    "F": P(255, 212, 92),
    "e": P(255, 244, 210),
}

PAL_SERAPH = {
    "k": P(20, 16, 28),
    "w": P(190, 188, 200),
    "W": P(232, 232, 240),
    "a": P(68, 54, 92),
    "A": P(108, 90, 148),
    "H": P(218, 182, 92),
    "e": P(196, 128, 255),
    "s": P(216, 206, 198),
}

PAL_LORD = {
    "k": P(22, 6, 10),
    "s": P(152, 38, 42),
    "d": P(104, 24, 28),
    "h": P(202, 72, 60),
    "n": P(228, 216, 192),
    "e": P(255, 192, 62),
    "w": P(56, 14, 18),
}

PAL_WHELP = {
    "k": P(12, 22, 24),
    "s": P(54, 112, 112),
    "d": P(36, 80, 82),
    "h": P(120, 172, 140),
    "e": P(250, 182, 62),
    "w": P(38, 66, 72),
}

PAL_DRAGON = {
    "k": P(18, 10, 10),
    "s": P(142, 60, 44),
    "d": P(98, 38, 32),
    "h": P(198, 98, 64),
    "b": P(218, 174, 92),
    "e": P(255, 222, 92),
    "w": P(72, 28, 28),
    "W": P(108, 44, 40),
}

PAL_CASTLE = {
    "k": P(20, 16, 20),
    "S": P(110, 106, 118),
    "d": P(78, 74, 86),
    "h": P(142, 138, 152),
    "r": P(192, 62, 50),
    "g": P(32, 26, 30),
    "w": P(250, 172, 62),
}

# Монстры аномалии (issue #1): замена тайлам Kenney k:108/109/110 —
# в бою они читались как круглые кляксы («красные круги»).
PAL_MUTANT = {
    "k": P(18, 22, 12),
    "s": P(122, 166, 82),
    "d": P(86, 120, 56),
    "h": P(164, 202, 114),
    "e": P(226, 64, 54),
    "n": P(232, 228, 202),
    "t": P(98, 76, 58),
}

PAL_BRUTE = {
    "k": P(14, 20, 10),
    "s": P(94, 130, 60),
    "d": P(64, 92, 40),
    "h": P(132, 168, 84),
    "e": P(250, 198, 60),
    "n": P(226, 222, 196),
    "t": P(78, 58, 44),
}

PAL_SPITTER = {
    "k": P(18, 22, 10),
    "s": P(156, 178, 70),
    "d": P(114, 134, 46),
    "h": P(192, 210, 106),
    "e": P(255, 122, 66),
    "n": P(238, 234, 206),
    "m": P(72, 28, 28),
}


# ------------------------------------------------------------- сетки ---------

GHOUL = [
    "      kkkkk       ",
    "     khhhhhk      ",
    "    khssssshk     ",
    "    ksekkksek     ",
    "    ksssssssk     ",
    "    kssdkkdssk    ",
    "   kksssssssssk   ",
    "  ksskttttttkssk  ",
    " kssk.trrrrt.kssk ",
    " ksk..trrrrt..ksk ",
    " ksk..ktrrtk..ksk ",
    " .k...kttrtk...k. ",
    "      ktrrtk      ",
    "      k.rr.k      ",
    "     kss.kssk     ",
    "     ks...ksk     ",
    "     kk...kkk     ",
]

WRAITH = [
    "       kkk        ",
    "      khhhk       ",
    "     khccchk      ",
    "     kckkkck      ",
    "     kceccek      ",
    "    kkcckckkk     ",
    "    kccccccck     ",
    "   kcccccccccck   ",
    "   kcdcccccddck   ",
    "  kcdcccccccdck   ",
    "  kcdcccccccdck   ",
    "  kkccccccccckk   ",
    "   kccccccccck    ",
    "   kccccccccck    ",
    "   k.ccc.ccc.k    ",
    "   k..k...k..k    ",
    "    ..k...k..     ",
    "       k.k        ",
]

IMP = [
    ".k..........k.",
    ".kk........kk.",
    "..ksk....ksk..",
    "..ksskkkkssk..",
    ".kshhssssshsk.",
    ".ksekkkkksek..",
    ".ksssssssssk..",
    "..ksskkkkssk..",
    ".wkssssssskw..",
    "wwksdsssdskw..",
    "ww.ksdssdsk...",
    "...kssssssk...",
    "....kssssk....",
    ".....kssk.....",
    "....ks.ss.k...",
    "....kk.kk.k...",
]

HELL = [
    ".......kFk.......",
    "......kFfFk......",
    ".....kFfffFk.....",
    "....kffFfFffk....",
    "....kfFkkfFfk....",
    "....kfeke kefk...".replace(" ", "k"),
    "....kfffkkfffk...",
    ".....kkfbbfkk....",
    "....kbbbbbbbk....",
    "...kbdbbbbdbk....",
    "..kbkbbbbbbkbk...",
    ".kbk.bbbbbk.bk...",
    ".bk..kbbbk..kb...",
    ".k...kbbbk...k...",
    ".....kbdbk.......",
    ".....kbbbk.......",
    ".....k.dbk.......",
    "....kb.k.bk......",
    "....k..k..k......",
    "....kk.kk.k......",
]

SERAPH = [
    "..k...................k...",
    ".kwk.................kwk..",
    "kwwk.......kkk.......kwwk.",
    "kwwk......kHkHk......kwwk.",
    "kwwkk....kk..kk....kkwwk..",
    ".kwwwk...k....k...kwwwk...",
    ".kwwwk...kssssk...kwwwk...",
    "..kwwk...kekkkek..kwwk....",
    "..kwwwk..kssssk..kwwwk....",
    "...kwwk..kaaaak..kwwk.....",
    "...kwwwkkaaaaaakkwwwk.....",
    "....kwwwwaAAAawwwwk.......",
    "....kwwwwaaawwewwwk.......",
    ".....kwwwwaawwwwwk........",
    ".....k.wwwwawwwwk.........",
    "........kwwawwk...........",
    "........kwaawk............",
    ".........kaak.............",
    ".........kaak.............",
    "........ksaks.k...........",
    "........ksk.sk............",
    "........kk..kk............",
]

LORD = [
    "....kn........kn.......",
    "....knn......knn.......",
    ".....kn.kkkk.kn........",
    ".....knksssskn.........",
    "....kksssssssskk.......",
    "...kssssssssssssk......",
    "...ksekksssskessk......",
    "...kssssssssssssk......",
    "....kssskkkksssk.......",
    "..kksskssssssksskk.....",
    ".kwwkskssssssksswwk....",
    "kwwwksksssssskswwwk....",
    "kwwk.kssssssssk.kwwk...",
    "kwwk.kssdssdssk.kwwk...",
    ".kk..kssssssssk..kk....",
    ".....kssssssssk........",
    ".....kksssssskk........",
    "....ksdksssskdsk.......",
    "...ksdk.kssk.kdsk......",
    "..ksk..kssssk..ksk.....",
    "..kk...kskkssk...kk....",
    ".......kssk.kssk.......",
    ".......ksk...ksk.......",
    ".......kk.....kk.......",
]

WHELP = [
    ".......kk...........",
    "......kwwk..........",
    ".....kwwsk..........",
    "....kwwssk..kk......",
    "...kwwssskkwsk......",
    "..kssssssssk........",
    ".ksekksssssk........",
    "kssssskssssk........",
    "kshhhk.kssk.........",
    ".kkhhk..kskk........",
    "..kkk..ksk.ksk......",
    ".....kssk...ksk.....",
    "....kssk.....kk.....",
    "....ksk.............",
    "....kk..............",
]

DRAGON = [
    "...........kk...................",
    "..........kddk..................",
    "....kk...kdssk..................",
    "...kwwk.kwssk...................",
    "..kwwkwkwsk.....................",
    "..kwwkwssk......................",
    "...kwwwssk......................",
    "....kwsssk......................",
    "...ksssssk......................",
    "..ksekkssk......................",
    ".ksssssssk......................",
    "ksskhhhkkssk....................",
    "ksk.khhhkkssk...................",
    ".kk.kbbhk.ksskkk................",
    "....kbbhk.kwwwsk................",
    "....kbbbk.kwwwwk................",
    "...kbbbssk.kwwwk................",
    "...kbsssk...kwwk................",
    "...kbssk.....kwk................",
    "...kbsk.......kk................",
    "..kbbsk.........................",
    "..kbbsk.........................",
    "...kkk..........................",
]

CASTLE = [
    "kkkkkk......kkkkkk......kkkkkk",
    "kSSSSk......kShhSk......kSSSSk",
    "kSdSk.......kSdSk.......kSdSk.",
    "kShSk.......kShSk.......kShSk.",
    "kSSSk..kkkkkkSSSkkkkkk..kSSSk.",
    "kSSSkkkSSSSSSSSSSSSSSSkkkSSSk.",
    "kSSSSSSSdSSSSSSSSSSdSSSSSSSSk.",
    "kSSdSSSSSSSSkSSkSSSSSSSSdSSSk.",
    "kSSSSSwSSSSSkSSkSSSSSwSSSSSSk.",
    "kSSSSSwSSSSSkSSkSSSSSwSSSSSSk.",
    "kdSSSSkSSSSSkSSkSSSSSkSSSSdSk",
    "kdSSSSkSSdSSkSSkSSdSSkSSSSdSk",
    "kdSSSSkSSSSSkSSkSSSSSkSSSSdSk",
    "kSSSSSkSSSSSkSSkSSSSSkSSSSSSk",
    "kSSwSSkSSSSSkSSkSSSSSkSSwSSSk",
    "kSwSwSkSSdSSkSSkSSdSSkSwSwSSk",
    "kSSSSSkSSSSSkSSkSSSSSkSSSSSSk",
    "kdddddkggggggggggggggkdddddddk",
    "kdSSdSkkggSSSSSSSSggkkSdSSdSk",
    "kSSSSSk.kgggggggggggk.kSSSSSk",
    "kSSSSSk.kggSSSSSSSggk.kSSSSSk",
    "kSSSSSk.kgggkkkkkgggk.kSSSSSk",
    "kdddddSkkgggk..kggggkSddddddk",
    "kkkkkkkkkgggk..kgggkkkkkkkkkk",
    ".......kggggk..kggggk........",
    ".......kkkkkk..kkkkkk........",
]


# Монстры аномалии: мутант (тощий, зубы, рёбра), брют (массивный, кулаки до земли),
# плевун (жаба с разинутой пастью).
MUTANT = [
    "      kkkkk       ",
    "     khhhhhk      ",
    "    khssssshk     ",
    "    ksekkksek     ",
    "    kssnnnssk     ",
    "    kssdkkdssk    ",
    "   kksssssssssk   ",
    "  kssksdsdsdkssk  ",
    " kssk.sdsdsd.kssk ",
    " ksk..sdsdsd..ksk ",
    " ksk..ksddsk..ksk ",
    " .k...kssssk...k. ",
    "      kttttk      ",
    "      k.tt.k      ",
    "     kss.kssk     ",
    "     ks...ksk     ",
    "     kk...kkk     ",
]

BRUTE = [
    "       kkkk       ",
    "      khssshk     ",
    "      ksekesk     ",
    "      kssdnsk     ",
    "    kksssssskk    ",
    "  kssssssssssk    ",
    " ksdsssssssdssk   ",
    " kssdsssssdsssk   ",
    "ksssddddddssssk   ",
    "kssk sddds kssk   ",
    "kssk kdddk kssk   ",
    "kdsk kkdkk ksdk   ",
    "kkk  kttk  kkk    ",
    "     ktt ktk      ",
    "    ktsk ktsk     ",
    "    kk...kkk      ",
]

SPITTER = [
    "    kkkkkkk     ",
    "   khssssshk    ",
    "  ksekkkkkesk   ",
    "  kssnnnnnssk   ",
    " ksmmmmmmmmsk   ",
    " ksmnnnnnmsk    ",
    " ksssssssssk    ",
    "ksdsssssssdsk   ",
    "kssdssssdssk    ",
    " ksssssssssk    ",
    " kkssk..kssk    ",
    " .ksk...ksk     ",
    " .kkk...kkk     ",
]



# ------------------------------------------------- M14-D: вампиры и личи -----

PAL_VAMPIRE = {
    "k": P(18, 16, 26),
    "h": P(28, 22, 38),
    "p": P(214, 206, 198),
    "e": P(205, 30, 42),
    "w": P(242, 240, 232),
    "c": P(96, 18, 30),
    "s": P(42, 36, 52),
}

VAMPIRE = [
    "     kkkkk     ",
    "    khhhhhk    ",
    "    khppphk    ",
    "    kpekpek    ",
    "    kpppppk    ",
    "    kpwkwpk    ",
    "    kkpppkk    ",
    "   kccpppcck   ",
    "  kcccpccck    ",
    " kcccccccccck  ",
    " ksccccccccsck ",
    " kskcccccccksk ",
    " kkkccccccckkk ",
    "    kck kck    ",
    "    kkk kkk    ",
]

ARCHVAMPIRE = [
    "      kkkkk      ",
    "     kFhhhFk     ",
    "     khppphk     ",
    "     kpekpek     ",
    "     kpppppk     ",
    "     kpwkwpk     ",
    "     kkpppkk     ",
    "    kccpppcck    ",
    "   kcccpccck     ",
    "  kcccrcccrccck  ",
    " kcccccccccccccck",
    " ksrcrcrrrcrcrsck",
    " kskccrrrrrccksk ",
    " kkkcccrrrccckkk ",
    "   kcccck kccck  ",
    "   kck   k  kck  ",
    "   kkk   kk  kkk ",
]

PAL_LICH = {
    "k": P(16, 12, 24),
    "F": P(232, 192, 84),
    "w": P(232, 228, 214),
    "v": P(84, 52, 120),
    "r": P(118, 224, 238),
    "s": P(50, 32, 74),
}

LICH = [
    "    kFkFkFk    ",
    "    kFFFFFFk   ",
    "    kwwwwwwk   ",
    "   kwwkwkwwk   ",
    "   kwwwwwwwk   ",
    "   kwkwkwkwk   ",
    "    kwwwwwk    ",
    "   kvvvvvvvk   ",
    "  kvrvvvvrvk   ",
    "  kvvvrvrvvvk  ",
    "  kvvvvvvvvvk  ",
    " kvvrvvvvrvvvk ",
    " kvvvvvvvvvvvk ",
    " ksvvvvvvvvvsk ",
    " kskvvvvvvvksk ",
    " kkcvk k kvck  ",
    "   vk kkk kv   ",
    "   kk     kk   ",
]

ARCHLICH = [
    "     kFkFkFkFk     ",
    "     kFFFFFFFFk    ",
    "     kwwwwwwwwk    ",
    "    kwwkwwkwwwk    ",
    "    kwwrwwrwwwk    ",
    "    kwwwwwwwwwk    ",
    "    kwkwwwwkwk     ",
    "     kwwwwwwk      ",
    "    kvvvvvvvvk     ",
    "   kvvrvvvvrvvk    ",
    "  kvvvvrvrvvvvvk   ",
    "  kvvvvvvvvvvvvk   ",
    " kvvrvvvvrvvvvvvvk ",
    " kvvvvvvrvvvvvvvvk ",
    " ksvvvvvvvvvvvvvsk ",
    " kskvvvrvvvvrvvksk ",
    " kkcvvk kkk kvvck  ",
    "   vvk  k k  kvv   ",
    "   kk   kkk   kk   ",
]

PAL_SKMAGE = {
    "k": P(16, 14, 22),
    "h": P(44, 36, 66),
    "w": P(230, 226, 212),
    "r": P(72, 52, 104),
    "o": P(140, 120, 220),
}

SKELETON_MAGE = [
    "      kkk      ",
    "     khhhhk    ",
    "    khhhhhhk   ",
    "   khhhhhhhhk  ",
    "  khhhhhhhhhhk ",
    " khhkkkkkkkkhhk",
    "     kwwwwk    ",
    "    kwwkwwwk   ",
    "    kwwwwwwk   ",
    "    kwkwwkwk   ",
    "     kwwwwk    ",
    "    kkrrrrkk   ",
    "   krrrorrork  ",
    "   krkrrrrkrk  ",
    "   krk kkk krk ",
    "   kk  k k  kk ",
    "       k k     ",
]

PAL_VKEEP = {
    "k": P(36, 32, 42),
    "e": P(198, 32, 44),
}

VAMPIRE_KEEP = [
    "  k     k     k  ",
    "  kk   kkk   kk  ",
    "  kek  kek  kek  ",
    "  kek  kek  kek  ",
    "  kekk kek kekk  ",
    "  kkkkkkkkkkkkk  ",
    "  kkkkkkkkkkkkk  ",
    "  kekekekekekek  ",
    "  kkkkkkkkkkkkk  ",
    " kkkekekekekekkk ",
    " kkkkkkkkkkkkkkk ",
    " kkekkkekekkkekk ",
    " kkkkkkkkkkkkkkk ",
    "kkkkkkkkkkkkkkkkk",
]

PAL_LTOWER = {
    "k": P(20, 16, 30),
    "v": P(72, 52, 104),
    "r": P(118, 226, 240),
    "F": P(232, 192, 84),
}

LICH_TOWER = [
    "       kFk       ",
    "      kFkFk      ",
    "       kvk       ",
    "      kvvvk      ",
    "      kvrvk      ",
    "      kvvvk      ",
    "     kvvrvvk     ",
    "     kvvvvvk     ",
    "     kvvrvvk     ",
    "     kvvvvvk     ",
    "    kvvvrvvvk    ",
    "    kvvvvvvvk    ",
    "    kvvvrvvvk    ",
    "   kvvvvvvvvvk   ",
    "   kvvvvvvvvvk   ",
    "  kkvvkkkkkvvkk  ",
    " kkvvk     kvvkk ",
    "kkkkkkkkkkkkkkkkk",
]

# ------------------------------------------------------------- сборка --------

# (имя, сетка, палитра, папка)
SPRITES = [
    ("ghoul", GHOUL, PAL_GHOUL, ENV),
    ("wraith", WRAITH, PAL_WRAITH, ENV),
    ("imp", IMP, PAL_IMP, ENV),
    ("hellcaller", HELL, PAL_HELL, ENV),
    ("seraph", SERAPH, PAL_SERAPH, ENV),
    ("demon_lord", LORD, PAL_LORD, ENV),
    ("dragon_whelp", WHELP, PAL_WHELP, ENV),
    ("dragon", DRAGON, PAL_DRAGON, ENV),
    ("castle", CASTLE, PAL_CASTLE, BLD),
    ("mutant", MUTANT, PAL_MUTANT, ENV),
    ("brute", BRUTE, PAL_BRUTE, ENV),
    ("spitter", SPITTER, PAL_SPITTER, ENV),
    ("vampire", VAMPIRE, PAL_VAMPIRE, ENV),
    ("archvampire", ARCHVAMPIRE, PAL_VAMPIRE, ENV),
    ("lich", LICH, PAL_LICH, ENV),
    ("archlich", ARCHLICH, PAL_LICH, ENV),
    ("skeleton_mage", SKELETON_MAGE, PAL_SKMAGE, ENV),
    ("vampire_keep", VAMPIRE_KEEP, PAL_VKEEP, BLD),
    ("lich_tower", LICH_TOWER, PAL_LTOWER, BLD),
]


def make_previews(made):
    f = 4
    pad = 8
    imgs = [scale_px(px, f) for _, px, _, _ in made]
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
    write_png(os.path.join(HERE, "bestiary_preview.png"), sheet)


def main():
    os.makedirs(ENV, exist_ok=True)
    os.makedirs(BLD, exist_ok=True)
    made = []
    for name, grid, pal, folder in SPRITES:
        px = grid_to_px(grid, pal)
        write_png(os.path.join(folder, name + ".png"), px)
        made.append((name, px, pal, folder))
        print(name, len(px[0]), "x", len(px))
    make_previews(made)
    print("OK")


main()
