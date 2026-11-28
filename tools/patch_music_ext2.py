# -*- coding: utf-8 -*-
"""v3.1 «вся музыка»: 7 новых KS-треков — мир, данж (база/тёмный), босс,
праздник, город ночь/день (фолбэки). Принятые 6 не тронуты (rng-порядок:
дописываются ПОСЛЕ боевого блока). Запуск: python -I tools/patch_music_ext2.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "tools", "make_music_v3.py")
s = io.open(P, encoding="utf-8", newline="").read()

TAIL = r'''

# ---------------------------------------------------------------- мир
# Карта мира: степной переход, 84 BPM, ми-дорий, шаг баса на каждую
# половину такта — путь через дикий мир.
BPM = 84
BAR = 4 * 60.0 / BPM
PROG = [
    ("E", [52, 55, 59]), ("C", [48, 52, 55]), ("D", [50, 54, 57]), ("G", [43, 47, 50]),
    ("E", [52, 55, 59]), ("G", [43, 47, 50]), ("D", [50, 54, 57]), ("C", [48, 52, 55]),
]
BASS = {"E": 40, "C": 36, "D": 38, "G": 43}
SCALE = [64, 66, 67, 69, 71, 74, 76]   # ми-дорий
WRLD = [
    (0.0, 2, 0.9, 0.32), (1.0, 3, 0.8, 0.28), (2.0, 4, 1.0, 0.34), (3.0, 2, 0.8, 0.28),
    (0.5, 1, 0.8, 0.28), (1.5, 2, 0.9, 0.30), (3.0, 3, 1.0, 0.32),
    (0.0, 3, 1.0, 0.32), (1.5, 4, 0.9, 0.30), (2.5, 5, 1.0, 0.32),
    (0.0, 4, 0.9, 0.30), (1.0, 3, 0.8, 0.28), (2.5, 2, 1.2, 0.34),
    (0.5, 2, 0.9, 0.28), (2.0, 3, 1.0, 0.32), (3.0, 1, 0.8, 0.26),
    (0.0, 4, 1.0, 0.34), (2.0, 5, 1.0, 0.32),
    (0.5, 3, 0.9, 0.28), (2.0, 2, 1.0, 0.30), (3.5, 1, 0.6, 0.24),
]
ev = []
total = 0.0
for cycle in range(3):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        for j, m in enumerate(chord):
            ev.append((t0 + 0.05 * j, ks_pluck(midi2f(m), BAR * 1.3 - 0.05 * j, 0.28,
                    damp=0.998, lp=3000, pick=0.45), -0.3 + 0.3 * j))
        # шаг: бас на каждую половину такта (корень-квинта)
        ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 0.55, 0.5, damp=0.9975), 0.0))
        ev.append((t0 + BAR / 2.0, ks_bass(midi2f(BASS[root] + 7), BAR * 0.55, 0.4,
                damp=0.9975), 0.0))
        ev.append((t0, thump2(0.22), -0.1))
        k7 = (cycle * len(PROG) + i) % len(WRLD)
        off, ni, dur, vel = WRLD[k7]
        sig = ks_pluck(midi2f(SCALE[ni]), dur, vel, damp=0.9955, lp=6000, pick=0.3)
        tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.015, 0.015))
        ev.append((tt, sig, float(rng.uniform(-0.3, 0.3))))
render(os.path.join(MUS, "mus_world_v3.wav"))

# ---------------------------------------------------------------- данж
# База данжа: ре-минор низко и редко, 58 BPM, без перкуссии, било-намёк.
BPM = 58
BAR = 4 * 60.0 / BPM
PROG = [
    ("D", [50, 53, 57]), ("B", [46, 53, 58]), ("G", [43, 50, 55]), ("A", [45, 52, 57]),
]
BASS = {"D": 38, "B": 35, "G": 43, "A": 33}
SCALE = [62, 65, 68, 69, 72, 74]   # ре-гармонический, низко-средне
ev = []
total = 0.0
for cycle in range(2):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.6, 0.85), 0.0))
        for j, m in enumerate(chord):
            ev.append((t0 + 0.12 * j, ks_pluck(midi2f(m - 12), BAR * 2.0 - 0.12 * j, 0.2,
                    damp=0.9988, lp=1800, pick=0.45), -0.3 + 0.3 * j))
        if (cycle * len(PROG) + i) % 4 == 2:
            ev.append((t0, bell2(midi2f(45), 7.0, 0.3), -0.15))
        if i % 2 == 1:
            k8 = (cycle * len(PROG) + i) % len(SCALE)
            ev.append((t0 + BAR * 0.5, ks_pluck(midi2f(SCALE[k8]), 2.5, 0.22,
                    damp=0.9975, lp=4000, pick=0.45), float(rng.uniform(-0.3, 0.3))))
render(os.path.join(MUS, "mus_dungeon_base_v3.wav"))

# ---------------------------------------------------------------- данж тёмный
# Тёмный биом: ля-фригийский, 54 BPM, глуше и реже базы, било тяжёлое.
BPM = 54
BAR = 4 * 60.0 / BPM
PROG = [
    ("A", [45, 52, 57]), ("B", [47, 51, 54]), ("G", [43, 50, 55]), ("E", [40, 47, 52]),
]
BASS = {"A": 33, "B": 35, "G": 31, "E": 28}
SCALE = [57, 58, 60, 62, 64, 65]
ev = []
total = 0.0
for cycle in range(2):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.8, 0.9), 0.0))
        for j, m in enumerate(chord):
            ev.append((t0 + 0.14 * j, ks_pluck(midi2f(m - 12), BAR * 2.2 - 0.14 * j, 0.17,
                    damp=0.9989, lp=1500, pick=0.48), -0.3 + 0.3 * j))
        if i % 2 == 0:
            ev.append((t0, bell2(midi2f(40), 8.0, 0.35), 0.0))
        if i % 2 == 1:
            k9 = (cycle * len(PROG) + i) % len(SCALE)
            ev.append((t0 + BAR * 0.75, ks_pluck(midi2f(SCALE[k9] + 12), 3.0, 0.18,
                    damp=0.9975, lp=3600, pick=0.45), float(rng.uniform(-0.4, 0.4))))
render(os.path.join(MUS, "mus_dungeon_dark_v3.wav"))

# ---------------------------------------------------------------- босс
# Босс: 132 BPM, ми-гармонический (доминанта Си-мажор — угроза),
# KS-уколы + тяжёлая мембрана + било-акценты. Агрессия не как в бою.
BPM = 132
BAR = 4 * 60.0 / BPM
PROG = [
    ("E", [40, 47, 52]), ("C", [36, 43, 48]), ("D", [38, 45, 50]), ("B", [35, 47, 51]),
]
BASS = {"E": 28, "C": 36, "D": 38, "B": 35}
OST = [52, 55, 56, 59, 55, 52, 59, 56]
RIFF = [64, 65, 64, 62, 59, 62, 64, 59, 52, 55, 56, 59, 65, 64, 62, 59]
ev = []
total = 0.0
for cycle in range(4):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        for j, m in enumerate(chord):
            ev.append((t0 + 0.02 * j, ks_pluck(midi2f(m + 12), 0.55 - 0.02 * j, 0.5,
                    damp=0.9935, lp=5600, pick=0.12), -0.3 + 0.3 * j))
        ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.05, 0.75, damp=0.9972, pick=0.15), 0.0))
        for b in range(4):
            ev.append((t0 + b * BAR / 4.0, thump2(0.58 if b % 2 == 0 else 0.36), 0.0))
        for b in range(8):
            ev.append((t0 + b * BAR / 8.0 + BAR / 16.0, tick(0.09 if b % 2 == 0 else 0.05),
                       0.45 if b % 2 == 0 else -0.45))
        for k10 in range(8):
            sig = ks_pluck(midi2f(OST[k10]), 0.4, 0.32, damp=0.994, lp=6000, pick=0.12)
            ev.append((t0 + k10 * BAR / 8.0, sig, 0.3 * np.sin(k10 + i)))
        if i == 3:
            ev.append((t0, bell2(midi2f(52), 5.0, 0.32), 0.0))
render(os.path.join(MUS, "mus_boss_v3.wav"))

# ---------------------------------------------------------------- праздник
# Праздник: до-мажор, 100 BPM, танец — бас на сильные, струны на слабые,
# риф мажорной пентатоники.
BPM = 100
BAR = 4 * 60.0 / BPM
PROG = [
    ("C", [48, 52, 55]), ("F", [41, 48, 53]), ("G", [43, 47, 50]), ("C", [48, 52, 55]),
    ("Am", [45, 52, 57]), ("F", [41, 48, 53]), ("G", [43, 47, 50]), ("C", [48, 52, 55]),
]
BASS = {"C": 36, "F": 41, "G": 43, "Am": 33}
SCALE = [72, 74, 76, 79, 81, 84]
FEST = [
    (0.0, 0, 0.4, 0.34), (0.5, 1, 0.4, 0.3), (1.0, 2, 0.4, 0.32), (2.0, 3, 0.5, 0.34),
    (3.0, 2, 0.4, 0.3), (3.5, 1, 0.4, 0.28),
    (0.0, 2, 0.4, 0.32), (1.0, 3, 0.4, 0.3), (2.0, 4, 0.5, 0.34), (3.5, 3, 0.4, 0.28),
    (0.5, 3, 0.4, 0.3), (1.5, 2, 0.4, 0.3), (2.5, 1, 0.4, 0.3), (3.0, 0, 0.6, 0.34),
    (0.0, 4, 0.5, 0.34), (1.5, 3, 0.4, 0.3), (2.0, 2, 0.4, 0.3), (3.5, 2, 0.4, 0.28),
    (0.0, 5, 0.6, 0.36), (2.0, 4, 0.5, 0.32), (3.0, 3, 0.4, 0.3),
    (0.5, 2, 0.4, 0.3), (1.5, 3, 0.4, 0.3), (2.5, 4, 0.5, 0.34), (3.0, 5, 0.6, 0.36),
]
ev = []
total = 0.0
for cycle in range(3):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 0.5, 0.55, damp=0.9965, pick=0.2), 0.0))
        ev.append((t0 + BAR / 2.0, ks_bass(midi2f(BASS[root] + 12), BAR * 0.45, 0.4,
                damp=0.9965, pick=0.2), 0.0))
        for b in range(2):
            ev.append((t0 + b * BAR / 2.0, thump2(0.26), 0.0))
        for b in range(8):
            if b % 2 == 1:
                ev.append((t0 + b * BAR / 8.0, tick(0.07), 0.4 if b < 4 else -0.4))
        # «ои-ой» аккорд на слабые восьмые
        for j, m in enumerate(chord):
            ev.append((t0 + BAR / 2.0 + 0.02 * j, ks_pluck(midi2f(m + 12), 0.3, 0.22,
                    damp=0.993, lp=5200, pick=0.15), -0.2 + 0.2 * j))
        k11 = (cycle * len(PROG) + i) % len(FEST)
        for off, ni, dur, vel in FEST[k11 * 4: k11 * 4 + 4]:
            sig = ks_pluck(midi2f(SCALE[ni]), dur, vel, damp=0.995, lp=6500, pick=0.3)
            tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.01, 0.01))
            ev.append((tt, sig, float(rng.uniform(-0.3, 0.3))))
render(os.path.join(MUS, "mus_festival_v3.wav"))

# ---------------------------------------------------------------- ночь города
# Город ночью: 60 BPM, ля-минор мягко: держание + редкая струна, без ударов.
BPM = 60
BAR = 4 * 60.0 / BPM
PROG = [
    ("Am", [45, 52, 57]), ("F", [53, 57, 60]), ("C", [48, 52, 55]), ("G", [55, 59, 62]),
]
BASS = {"Am": 33, "F": 41, "C": 36, "G": 43}
SCALE = [69, 72, 76, 79, 81]
NIGHT_M = [(1.0, 0), (0.5, 1), (2.0, 2), (1.5, 3), (0.0, 4), (2.5, 1), (3.0, 0)]
ev = []
total = 0.0
for cycle in range(2):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.4, 0.5), 0.0))
        for j, m in enumerate(chord):
            ev.append((t0 + 0.09 * j, ks_pluck(midi2f(m), BAR * 1.7 - 0.09 * j, 0.24,
                    damp=0.9985, lp=2600, pick=0.45), -0.3 + 0.3 * j))
        k12 = (cycle * len(PROG) + i) % len(NIGHT_M)
        off, ni = NIGHT_M[k12]
        sig = ks_pluck(midi2f(SCALE[ni]), 2.4, 0.2, damp=0.997, lp=4800, pick=0.45)
        ev.append((t0 + off * BAR / 4.0, sig, float(rng.uniform(-0.3, 0.3))))
render(os.path.join(MUS, "mus_city_night_v3.wav"))

# ---------------------------------------------------------------- день города
# Фолбэк дня (без сезона): до-мажор просто и ровно, 80 BPM.
BPM = 80
BAR = 4 * 60.0 / BPM
PROG = [
    ("C", [48, 52, 55]), ("G", [55, 59, 62]), ("Am", [45, 52, 57]), ("F", [53, 57, 60]),
]
BASS = {"C": 36, "G": 43, "Am": 33, "F": 41}
ev = []
total = 0.0
for cycle in range(2):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.2, 0.55, damp=0.997, pick=0.2), 0.0))
        for j, m in enumerate(chord):
            ev.append((t0 + 0.08 * j, ks_pluck(midi2f(m + 12), BAR * 1.25 - 0.08 * j, 0.26,
                    damp=0.9955, lp=5200, pick=0.3), -0.3 + 0.3 * j))
        arp_bar(ev, t0, chord, BAR, 0.16, wide=0.4, up=(i % 2 == 0))
        k13 = (cycle * len(PROG) + i) % len(MELO)
        for off, ni, dur, vel in MELO[k13 * 3: k13 * 3 + 3]:
            sig = pluck(midi2f(72 + ni % 5), dur, vel * 0.9)
            ev.append((t0 + off * BAR / 4.0, sig, float(rng.uniform(-0.3, 0.3))))
render(os.path.join(MUS, "mus_city_day_v3.wav"))

print("ГОТОВО — 13 треков в assets/audio/music/")
'''
marker = 'print("ГОТОВО — 6 треков в assets/audio/music/")'
assert s.count(marker) == 1
s = s.replace(marker, TAIL.lstrip("\n"))
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ok: 7 треков дописаны")
