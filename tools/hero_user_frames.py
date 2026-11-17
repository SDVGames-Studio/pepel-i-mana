# -*- coding: utf-8 -*-
"""Сборка полос героя из ПОДПИСАННЫХ заказчиком кадров (tools/hero_frames/
«<группа> (N).png») — v1.75.7. Единый масштаб по union-высоте группы
«айдл стоять», фигуры по низу кадра 120x80 (линия земли)."""
import os
import re

from PIL import Image

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hero_frames")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "assets", "sprites", "hero")
FRAME_W, FRAME_H = 120, 80
TARGET_H = 76

# полоса <- (префикс группы, зациклена ли сортировка по N)
STRIPS = [
    ("knight_Idle",    "айдл стоять"),
    ("knight_Attack",  "атака"),
    ("knight_Run",     "бег в право"),
    ("knight_RunDown", "бег в низ"),
    ("knight_Roll",    "дэш"),
    ("knight_Crouch",  "крастца"),
    ("knight_Cast",    "магия"),
    ("knight_Death",   "смерть героя"),
]


def group_files(prefix):
    fs = []
    plain = prefix + ".png"
    for f in os.listdir(SRC):
        if f == plain:            # одиночный кадр без номера («дэш.png»)
            fs.append((0, f))
            continue
        m = re.match(r"(.*)\((\d+)\)\.png$", f)
        if m and m.group(1).strip() == prefix:
            fs.append((int(m.group(2)), f))
    return [f for _, f in sorted(fs)]


def union_h(paths):
    boxes = []
    for p in paths:
        im = Image.open(os.path.join(SRC, p)).convert("RGBA")
        bb = im.getbbox()
        if bb:
            boxes.append(bb[3] - bb[1])
    return max(boxes) if boxes else TARGET_H


def main():
    idle = group_files("айдл стоять")
    scale = TARGET_H / float(union_h(idle))
    print("idle union scale: %.3f" % scale)
    for strip, prefix in STRIPS:
        files = group_files(prefix)
        assert files, "нет файлов группы: " + prefix
        canvas = Image.new("RGBA", (FRAME_W * len(files), FRAME_H),
                           (0, 0, 0, 0))
        for i, fname in enumerate(files):
            im = Image.open(os.path.join(SRC, fname)).convert("RGBA")
            nw = max(1, int(im.size[0] * scale))
            nh = max(1, int(im.size[1] * scale))
            if nh > FRAME_H:
                nw = max(1, int(nw * float(FRAME_H) / nh))
                nh = FRAME_H
            im = im.resize((nw, nh), Image.LANCZOS)
            canvas.paste(im, (i * FRAME_W + (FRAME_W - nw) // 2,
                              FRAME_H - nh), im)
        canvas.save(os.path.join(OUT, strip + ".png"))
        print(strip, canvas.size, len(files), "кадров")


if __name__ == "__main__":
    main()
