# -*- coding: utf-8 -*-
"""v2.8-фикс-3: каноническая индентация блока «канвас региона» в запеке
(съехала при правках). Запуск: python -I tools/patch_v280_indent.py
"""
import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
P = os.path.join(GAME, "scripts", "world_view.gd")

with io.open(P, "r", encoding="utf-8", newline="") as f:
    lines = f.read().splitlines(keepends=True)

nl = "\r\n" if "".join(lines[:50]).find("\r\n") >= 0 else "\n"

ia = ib = -1
for i, ln in enumerate(lines):
    if 'if treg != "" and rcv.has(treg):' in ln and ia < 0:
        ia = i
    if "var wmk := clampf" in ln:
        ib = i
        break
assert ia > 0 and ib > ia, "маркеры блока не найдены: ia=%d ib=%d" % (ia, ib)

canon = [
    '\t\t\tif treg != "" and rcv.has(treg):' + nl,
    '\t\t\t\tvar cimg: Image = rcv[treg]' + nl,
    '\t\t\t\t# 1 тексель полотна на пиксель запеки — соседние пиксели' + nl,
    '\t\t\t\t# читают соседние тексели: текстура цельная, без «крупы»' + nl,
    '\t\t\t\t# (канон «весны»: плотность текселей = плотность показа)' + nl,
    '\t\t\t\tvar tc: Color = cimg.get_pixel(' + nl,
    '\t\t\t\t\tint(px) % cimg.get_width(),' + nl,
    '\t\t\t\t\tint(py) % cimg.get_height())' + nl,
    '\t\t\t\tvar tkind: int = int(map.grid[tty][ttx])' + nl,
    '\t\t\t\tif tkind == map.TILE_FOREST:' + nl,
    '\t\t\t\t\ttc = tc.darkened(0.22)' + nl,
    '\t\t\t\telif tkind == map.TILE_WASTE:' + nl,
    '\t\t\t\t\ttc = tc.darkened(0.12)' + nl,
    '\t\t\t\tbase = tc' + nl,
]
lines[ia:ib] = canon
with io.open(P, "w", encoding="utf-8", newline="") as f:
    f.write("".join(lines))
print("ok: блок канваса переписан, строки %d-%d" % (ia + 1, ib))
