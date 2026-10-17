import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from spritemap import read_png, write_png
BASE = os.path.join(os.path.dirname(__file__), "..")
names = sorted(os.listdir(os.path.join(BASE, "assets", "sprites", "buildings")))
names = [n for n in names if n.endswith(".png")] + ["../tree.png", "../rock.png", "../ore.png"]
TS, Z, G = 32, 4, 1
percol = 8
rows = (len(names) + percol - 1) // percol
OW = percol * (TS * Z + G) + G
OH = rows * (TS * Z + G) + G
canvas = bytearray([0x50, 0x60, 0x50, 255] * (OW * OH))
for i, name in enumerate(names):
    w, h, px = read_png(os.path.join(BASE, "assets", "sprites", "buildings", name))
    x0 = G + (i % percol) * (TS * Z + G)
    y0 = G + (i // percol) * (TS * Z + G)
    for y in range(h):
        for x in range(w):
            c = px[(y * w + x) * 4:(y * w + x) * 4 + 4]
            if c[3] == 0:
                continue
            for dy in range(Z):
                for dx in range(Z):
                    xx, yy = x0 + x * Z + dx, y0 + y * Z + dy
                    o = (yy * OW + xx) * 4
                    canvas[o:o + 4] = bytes(c)
import traceback
try:
    write_png(os.path.join(BASE, "tools", "buildings_sheet.png"), OW, OH, canvas)
except Exception:
    traceback.print_exc()
print("DONE")
print("OK", len(names))
