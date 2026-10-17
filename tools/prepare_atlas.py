# Копия атласа с прозрачным фоном у тайлов существ/предметов (индексы 60+).
# Фон = цвет углов тайла (одинаковый тёмный) -> alpha 0 строго по равенству.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from spritemap import read_png, write_png, COLS, ROWS, TS
BASE = os.path.join(os.path.dirname(__file__), "..")
W, H, PX = read_png(os.path.join(BASE, "assets", "sprites", "kenney.png"))
out = bytearray(PX)
CUT_FROM = 60
cleared = 0
for idx in range(CUT_FROM, COLS * ROWS):
    tx, ty = (idx % COLS) * TS, (idx // COLS) * TS
    corners = [((ty) * W + tx) * 4, ((ty) * W + tx + TS - 1) * 4,
               ((ty + TS - 1) * W + tx) * 4, ((ty + TS - 1) * W + tx + TS - 1) * 4]
    bg = [tuple(PX[c:c + 3]) for c in corners]
    if len(set(bg)) != 1:
        continue
    b = bg[0]
    if sum(b) > 160:
        continue  # светлый фон — не «подложка существ»
    for py in range(TS):
        for px in range(TS):
            o = ((ty + py) * W + tx + px) * 4
            if tuple(PX[o:o + 3]) == b:
                out[o + 3] = 0
                cleared += 1
write_png(os.path.join(BASE, "assets", "sprites", "kenney_sprites.png"), W, H, out)
print("OK cleared px:", cleared)
