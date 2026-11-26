# -*- coding: utf-8 -*-
"""shot_world2: полный съём тумана через fog_new (текстура тумана стирается
view'ом только по fog_new — механизм v1.40.2). Запуск: python -I tools/patch_shot_reveal.py
"""
import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
P = os.path.join(GAME, "tools", "shot_world2.gd")


def read(p):
    with io.open(p, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(p, s):
    with io.open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)
    assert len(read(p)) > 0


s = read(P)
nl = "\r\n" if "\r\n" in s else "\n"
old = ('\tfor y in map.h:\n'
       '\t\tfor x in map.w:\n'
       '\t\t\tmap.fog[Vector2i(x, y)] = true\n').replace("\n", nl)
new = ('\tvar all: Array = []\n'
       '\tfor y in map.h:\n'
       '\t\tfor x in map.w:\n'
       '\t\t\tvar p := Vector2i(x, y)\n'
       '\t\t\tmap.fog[p] = true\n'
       '\t\t\tall.append(p)\n'
       '\tmap.fog_new = all\n'
       '\tmap.fog_ver += 1\n').replace("\n", nl)
assert old in s, "якорь _reveal_all не найден"
write(P, s.replace(old, new))
print("ok: tools/shot_world2.gd — туман снимается через fog_new")
