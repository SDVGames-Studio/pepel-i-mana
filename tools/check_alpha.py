import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from spritemap import read_png, write_png, COLS, TS
BASE = os.path.join(os.path.dirname(__file__), "..")
W, H, PX = read_png(os.path.join(BASE, "assets", "sprites", "kenney_sprites.png"))
IDX = [108, 109, 110, 111, 112, 84, 85, 87, 88, 96, 97, 99, 100, 120, 121, 122, 123, 124, 127, 128, 129, 130, 102, 116, 104, 106, 90, 92]
Z, PAD, G, percol = 6, 2, 1, 14
rows = (len(IDX) + percol - 1) // percol
OW = percol * (TS * Z + PAD + G) + G
OH = rows * (TS * Z + PAD + G) + G
canvas = bytearray([0x40, 0x80, 0x40, 255] * (OW * OH))
def put(x, y, rgba):
    if 0 <= x < OW and 0 <= y < OH:
        o = (y * OW + x) * 4
        if rgba[3] > 0:
            canvas[o:o + 4] = bytes(rgba[:4])
for i, idx in enumerate(IDX):
    tx0, ty0 = i % percol, i // percol
    sx, sy = (idx % COLS) * TS, (idx // COLS) * TS
    x0, y0 = G + tx0 * (TS * Z + PAD + G), G + ty0 * (TS * Z + PAD + G)
    for py in range(TS):
        for px in range(TS):
            o = ((sy + py) * W + sx + px) * 4
            for dy in range(Z):
                for dx in range(Z):
                    put(x0 + px * Z + dx, y0 + py * Z + dy, PX[o:o + 4])
write_png(os.path.join(BASE, "tools", "check_alpha.png"), OW, OH, canvas)
print("OK")
