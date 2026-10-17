import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from spritemap import read_png, write_png, COLS, TS
IDX = [4, 5, 16, 17, 27, 28, 41, 43, 44, 36, 37, 38, 40, 0, 1, 48, 102, 65, 90, 92, 116, 125, 126, 127, 128, 129, 130, 123, 124, 120, 121, 122, 108, 109, 110, 111, 112, 84, 85, 86, 87, 88, 96, 97, 98, 99, 100, 89, 91, 103, 104, 105, 106, 107, 74, 72, 73, 75, 57]
W, H, PX = read_png(os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "kenney.png"))
Z, PAD, G = 6, 2, 1
n = len(IDX)
percol = 12
rows = (n + percol - 1) // percol
OW = percol * (TS * Z + PAD + G) + G
OH = rows * (TS * Z + PAD + G) + G
canvas = bytearray(OW * OH * 4)
def put(x, y, rgba, alpha=255):
    if 0 <= x < OW and 0 <= y < OH:
        o = (y * OW + x) * 4
        canvas[o:o + 3] = bytes(rgba[:3]); canvas[o + 3] = max(canvas[o + 3], alpha)
for i, idx in enumerate(IDX):
    tx, ty = i % percol, i // percol
    sx, sy = (idx % COLS) * TS, (idx // COLS) * TS
    x0, y0 = G + tx * (TS * Z + PAD + G), G + ty * (TS * Z + PAD + G)
    for py in range(TS):
        for px in range(TS):
            o = ((sy + py) * W + sx + px) * 4
            r, g, b, a = PX[o:o + 4]
            for dy in range(Z):
                for dx in range(Z):
                    put(x0 + px * Z + dx, y0 + py * Z + dy, (r, g, b), a)
out = os.path.join(os.path.dirname(__file__), "tilepick.png")
write_png(out, OW, OH, canvas)
print("OK", out)
