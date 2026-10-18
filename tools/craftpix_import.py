# Импорт craftpix-ассетов в assets/sprites (M10). Запуск:
#   blender -b --python tools/craftpix_import.py
# Blender нужен как декодер PNG (системного Python нет): bpy читает любые
# форматы (в т.ч. colormap), пиксели RGBA float, строки идут снизу вверх.
import bpy
import os

SRC = r"F:\востановление кхорно юнитов\assets"
HERE = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.abspath(os.path.join(HERE, "..", "assets", "sprites"))

P_CIT = os.path.join(SRC, "craftpix-net-865357-free-pixel-citizens-for-top-down-tower-defense")
P_ORC = os.path.join(SRC, "craftpix-net-363992-free-top-down-orc-game-character-pixel-art", "PNG")
P_ANI = os.path.join(SRC, "craftpix-net-291971-free-top-down-animals-farm-pixel-art-sprites", "PNG", "Without_shadow")
P_TREE = os.path.join(SRC, "craftpix-net-385863-free-top-down-trees-pixel-art", "PNG", "Assets_separately", "Trees")
P_ROCK = os.path.join(SRC, "craftpix-net-974061-free-rocks-and-stones-top-down-pixel-art", "PNG", "Objects_separately")
P_PLANT = os.path.join(SRC, "craftpix-net-200380-free-pixel-art-plants-for-farm", "PNG")
P_SUMMER = os.path.join(SRC, "craftpix-net-381103-free-simple-summer-top-down-vector-tileset", "PNG")
P_FORT = os.path.join(SRC, "craftpix-net-749505-free-medieval-fortress-top-down-pixel-minigame-kit", "Tileset")

_copied = 0


def load(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = list(img.pixels)
    bpy.data.images.remove(img)
    return w, h, px


def save(path, w, h, px):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = bpy.data.images.new("tmp", w, h, alpha=True)
    img.pixels = px
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)
    global _copied
    _copied += 1


def get(w, h, px, x, y):
    i = ((h - 1 - y) * w + x) * 4
    return px[i:i + 4]


def crop(w, h, px, cx, cy, cw, ch):
    out = [0.0] * (cw * ch * 4)
    for y in range(ch):
        for x in range(cw):
            di = ((ch - 1 - y) * cw + x) * 4
            out[di:di + 4] = get(w, h, px, cx + x, cy + y)
    return out


def scale(w, h, px, nw, nh):
    out = [0.0] * (nw * nh * 4)
    fx, fy = w / float(nw), h / float(nh)
    for y in range(nh):
        for x in range(nw):
            r = g = b = a = 0.0
            n = 0
            for sy in range(int(y * fy), max(int(y * fy) + 1, int((y + 1) * fy))):
                for sx in range(int(x * fx), max(int(x * fx) + 1, int((x + 1) * fx))):
                    c = get(w, h, px, sx, sy)
                    r += c[0]; g += c[1]; b += c[2]; a += c[3]; n += 1
            di = ((nh - 1 - y) * nw + x) * 4
            out[di] = r / n; out[di + 1] = g / n; out[di + 2] = b / n; out[di + 3] = a / n
    return out


def copy(src, dst):
    w, h, px = load(src)
    save(os.path.join(SPRITES, dst), w, h, px)


# --- окружение города: деревья, скалы, пень --------------------------------
for i, name in enumerate(["Tree1", "Tree2", "Tree3", "Moss_tree1"], 1):
    copy(os.path.join(P_TREE, name + ".png"), "env/tree%d.png" % i)
copy(os.path.join(P_TREE, "Fruit_tree1.png"), "env/tree_fruit.png")
copy(os.path.join(P_TREE, "Broken_tree1.png"), "env/stump.png")
for i, name in enumerate(["Rock1_2", "Rock2_3", "Rock3_4", "Rock4_1"], 1):
    copy(os.path.join(P_ROCK, name + "_no_shadow.png"), "env/rock%d.png" % i)

# --- граждане: 4 варианта x направления d/s/u x walk/idle -------------------
for i in range(1, 5):
    for d in ["D", "S", "U"]:
        for a in ["Walk", "Idle"]:
            copy(os.path.join(P_CIT, str(i), "%s_%s.png" % (d, a)),
                 "citizens/c%d_%s_%s.png" % (i, d.lower(), a.lower()))

# --- орки-бандиты: 3 варианта, лист 4x6 (ряды: front,back,left,right) ------
for i in range(1, 4):
    for a in ["walk", "idle", "death"]:
        copy(os.path.join(P_ORC, "Orc%d" % i, "Without_shadow", "orc%d_%s_without_shadow.png" % (i, a)),
             "orcs/orc%d_%s.png" % (i, a))

# --- животные: лист 32x32, 8 рядов (idle f/b/l/r, walk f/b/l/r) -------------
for name, dst in [("Bull", "cow"), ("Sheep", "sheep"), ("Piglet", "pig"),
                  ("Chick", "chicken"), ("Turkey", "turkey")]:
    copy(os.path.join(P_ANI, "%s_animation_without_shadow.png" % name), "animals/%s.png" % dst)

# --- реквизит: телега, палатка, костёр, ящики --------------------------------
w, h, px = load(os.path.join(P_SUMMER, "Top-Down Simple Summer_Prop - Wooden Cart.png"))
save(os.path.join(SPRITES, "props/cart.png"), 128, 64, scale(w, h, px, 128, 64))
w, h, px = load(os.path.join(P_SUMMER, "Top-Down Simple Summer_Prop - Tent.png"))
save(os.path.join(SPRITES, "props/tent.png"), 112, 104, scale(w, h, px, 112, 104))
copy(os.path.join(P_FORT, "Fire.png"), "props/fire.png")
w, h, px = load(os.path.join(P_PLANT, "Supplies.png"))
save(os.path.join(SPRITES, "props/crate.png"), 48, 48, crop(w, h, px, 0, 0, 48, 48))
save(os.path.join(SPRITES, "props/sack.png"), 48, 48, crop(w, h, px, 96, 48, 48, 48))

# --- растения: полосы роста культур из Plants.png (48px, левый блок) --------
w, h, px = load(os.path.join(P_PLANT, "Plants.png"))
found = 0
for row in range(9):
    cells = []
    for col in range(6):
        cell = crop(w, h, px, col * 48, row * 48, 48, 48)
        opaque = sum(1 for i in range(3, len(cell), 4) if cell[i] > 0.05)
        if opaque > 40:
            cells.append(cell)
    if len(cells) >= 4 and found < 3:
        for st, cell in enumerate(cells[:4]):
            save(os.path.join(SPRITES, "plants/crop%d_%d.png" % (found, st)), 48, 48, cell)
        found += 1
print("crop strips:", found)

# --- контрольный лист: кадры х4 для проверки --------------------------------
check = [("citizens/c1_d_walk.png", 48, 48, 0), ("citizens/c1_s_walk.png", 48, 48, 0),
         ("citizens/c1_u_walk.png", 48, 48, 0), ("orcs/orc1_walk.png", 64, 64, 7),
         ("animals/sheep.png", 32, 32, 0), ("animals/sheep.png", 32, 32, 32 + 4),
         ("animals/cow.png", 32, 32, 0), ("plants/crop0_3.png", 48, 48, 0),
         ("props/crate.png", 48, 48, 0), ("props/fire.png", 32, 32, 0),
         ("env/tree1.png", 128, 128, 0), ("env/rock1.png", 64, 64, 0),
         ("props/cart.png", 128, 64, 0), ("env/tree_fruit.png", 128, 128, 0)]
COLS = 4
CW, CH = 140, 140
rows = (len(check) + COLS - 1) // COLS
sheet = [0.0] * (CW * COLS * CH * rows * 4)
for idx, (path, fw, fh, frame) in enumerate(check):
    w, h, px = load(os.path.join(SPRITES, path))
    fx = (frame % (w // fw)) * fw
    fy = (frame // (w // fw)) * fh
    cell = crop(w, h, px, fx, fy, fw, fh)
    z = max(1, min(3, (CW - 6) // fw, (CH - 6) // fh))
    big = [0.0] * (fw * z * fh * z * 4)
    for y in range(fh * z):
        for x in range(fw * z):
            c = cell[((y // z) * fw + (x // z)) * 4:((y // z) * fw + (x // z)) * 4 + 4]
            di = ((fh * z - 1 - y) * fw * z + x) * 4
            big[di:di + 4] = c
    cx = (idx % COLS) * CW + (CW - fw * z) // 2
    cy = (idx // COLS) * CH + (CH - fh * z) // 2
    for y in range(fh * z):
        for x in range(fw * z):
            di = ((CH * rows - 1 - (cy + y)) * CW * COLS + cx + x) * 4
            sheet[di:di + 4] = big[(y * fw * z + x) * 4:(y * fw * z + x) * 4 + 4]
save(os.path.join(HERE, "craftpix_check.png"), CW * COLS, CH * rows, sheet)
print("OK files:", _copied)
