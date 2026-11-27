# -*- coding: utf-8 -*-
"""Расширение make_music_v3.py: render -> assets/audio/music (22050 стерео),
+4 трека: лето/осень/зима/бой. Меню и весна не тронуты (rng-порядок цел).
Запуск: python -I tools/patch_music_ext.py
"""
import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
P = os.path.join(GAME, "tools", "make_music_v3.py")

s = io.open(P, encoding="utf-8", newline="").read()

# 1) render(): выход в assets/audio/music, 22050 стерео (lowpass + децимация)
i0 = s.index("def render(")
i1 = s.index("HERE = os.path.dirname")
new_r = (
    "def render(out_path):\n"
    '    """Синтез 44.1к -> реверб -> lowpass 10к -> 22050 стерео (формат треков)."""\n'
    "    n = int((total + 3.0) * SR)\n"
    "    buf = np.zeros((n, 2))\n"
    "    for t, sig, pan in ev:\n"
    "        place(buf, t, sig, pan)\n"
    "    for ch, tone, wet in ((0, 4300, 0.27), (1, 3600, 0.24)):\n"
    "        buf[:, ch] = convolve_reverb(buf[:, ch], wet, tone)\n"
    "    peak = np.max(np.abs(buf))\n"
    "    if peak > 0:\n"
    "        buf *= 0.86 / peak\n"
    "    for ch in (0, 1):\n"
    "        buf[:, ch] = fft_lp(buf[:, ch], 10000)\n"
    "    pcm = (buf[::2] * 32767).astype(np.int16)\n"
    '    with wave.open(out_path, "wb") as w:\n'
    "        w.setnchannels(2)\n"
    "        w.setsampwidth(2)\n"
    "        w.setframerate(SR // 2)\n"
    "        w.writeframes(pcm.tobytes())\n"
    '    print("ok: %s (%.1fs, %.1fMB)" % (out_path, len(pcm) / float(SR // 2),\n'
    "            os.path.getsize(out_path) / 1e6))\n"
    "\n"
    "\n"
)
s = s[:i0] + new_r + s[i1:]

# 2) выходные пути -> assets/audio/music
s = s.replace(
    'HERE_OUT = os.path.join(os.path.dirname(HERE), "build", "audio_preview")\n'
    "os.makedirs(HERE_OUT, exist_ok=True)\n",
    'MUS = os.path.join(GAME, "assets", "audio", "music")\n')
s = s.replace('render(total, "mus_menu_v3.wav")',
              'render(os.path.join(MUS, "mus_menu_v3.wav"))')
s = s.replace('render(total, "mus_city_spring_v3.wav")',
              'render(os.path.join(MUS, "mus_city_spring_v3.wav"))')

# 3) хвост: 4 новых трека
TAIL = r'''

# ---------------------------------------------------------------- лето
# Самый светлый: до-мажор, 82 BPM, птиц больше, перебор живее.
BPM = 82
BAR = 4 * 60.0 / BPM
PROG = [
    ("C", [48, 52, 55]), ("G", [55, 59, 62]), ("A", [57, 60, 64]), ("F", [53, 57, 60]),
    ("C", [48, 52, 55]), ("F", [53, 57, 60]), ("G", [55, 59, 62]), ("C", [48, 52, 55]),
]
BASS = {"C": 36, "G": 43, "A": 33, "F": 41}
SCALE = [60, 62, 64, 67, 69, 72, 74, 76]   # до-мажор
ev = []
total = 0.0
for cycle in range(3):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        for j, m in enumerate(chord):
            ev.append((t0 + 0.045 * j, pad_voice(midi2f(m), BAR * 1.04 - 0.045 * j, 0.36), -0.35 + 0.35 * j))
        arp_bar(ev, t0, chord, BAR, 0.2, wide=0.5, up=(i % 2 == 0))
        bass_m = BASS[root] + (7 if i % 4 == 3 else 0)
        ev.append((t0, drone(midi2f(bass_m), BAR * 1.04, 0.42 if i % 4 == 3 else 0.5), 0.0))
        ev.append((t0, thump(0.3), -0.1))
        ev.append((t0 + 2 * BAR / 4.0, thump(0.16), 0.1))
        k2 = (cycle * len(PROG) + i) % (len(MELO) // 3)
        for off, ni, dur, vel in MELO[k2 * 3: k2 * 3 + 3]:
            sig = pluck(midi2f(SCALE[ni]), dur, vel)
            tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.015, 0.015))
            pan = float(rng.uniform(-0.35, 0.35))
            ev.append((tt, sig, pan))
            ev.append((tt + 0.011, sig * 0.4, -pan))
        if (cycle * len(PROG) + i) % 2 == 0:
            tt = t0 + rng.uniform(0.2, BAR - 0.4)
            f0 = rng.uniform(2500, 3400)
            ev.append((tt, chirp(f0, f0 * rng.uniform(1.3, 1.55), vel=0.07), rng.uniform(-0.6, 0.6)))
render(os.path.join(MUS, "mus_city_summer_v3.wav"))

# ---------------------------------------------------------------- осень
# Темнее и реже: ля-минор, 74 BPM, мотив редкий, птиц мало.
BPM = 74
BAR = 4 * 60.0 / BPM
PROG = [
    ("A", [57, 60, 64]), ("F", [53, 57, 60]), ("C", [48, 52, 55]), ("G", [55, 59, 62]),
    ("A", [57, 60, 64]), ("C", [48, 52, 55]), ("F", [53, 57, 60]), ("E", [52, 55, 59]),
]
BASS = {"A": 33, "F": 41, "C": 36, "G": 43, "E": 40}
SCALE = [69, 72, 74, 76, 79, 81]
AUT_MELO = [
    (0.0, 0, 1.3, 0.34), (2.0, 2, 1.0, 0.30), (3.0, 1, 0.9, 0.26),
    (0.5, 3, 1.1, 0.32), (2.5, 2, 1.2, 0.34),
    (0.0, 4, 1.4, 0.36), (2.5, 3, 1.0, 0.28),
    (1.0, 2, 0.9, 0.30), (3.0, 0, 1.2, 0.32),
    (0.0, 1, 1.2, 0.32), (2.5, 4, 1.2, 0.34),
    (0.5, 3, 1.1, 0.30), (3.0, 2, 1.0, 0.28),
    (0.0, 5, 1.5, 0.36), (2.5, 1, 1.0, 0.28),
    (1.0, 0, 1.1, 0.30), (2.5, 2, 1.2, 0.34),
    (0.0, 3, 1.3, 0.34), (2.0, 4, 1.2, 0.32),
    (0.5, 2, 1.0, 0.30), (3.0, 0, 1.2, 0.30),
    (0.0, 4, 1.4, 0.34), (2.5, 2, 1.1, 0.28),
    (1.0, 1, 1.0, 0.28), (3.0, 3, 1.2, 0.32),
]
ev = []
total = 0.0
for cycle in range(3):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        for j, m in enumerate(chord):
            ev.append((t0 + 0.045 * j, pad_voice(midi2f(m), BAR * 1.04 - 0.045 * j, 0.4), -0.35 + 0.35 * j))
        arp_bar(ev, t0, chord, BAR, 0.15, wide=0.45, up=(i % 2 == 0))
        bass_m = BASS[root] + (7 if i % 4 == 3 else 0)
        ev.append((t0, drone(midi2f(bass_m), BAR * 1.04, 0.42 if i % 4 == 3 else 0.5), 0.0))
        ev.append((t0, thump(0.2), -0.1))
        k3 = (cycle * len(PROG) + i) % (len(AUT_MELO) // 2)
        for off, ni, dur, vel in AUT_MELO[k3 * 2: k3 * 2 + 2]:
            sig = pluck(midi2f(SCALE[ni]), dur, vel)
            tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.015, 0.015))
            pan = float(rng.uniform(-0.3, 0.3))
            ev.append((tt, sig, pan))
            ev.append((tt + 0.011, sig * 0.4, -pan))
        if (cycle * len(PROG) + i) % 4 == 2:
            tt = t0 + rng.uniform(0.3, BAR - 0.5)
            f0 = rng.uniform(2200, 2900)
            ev.append((tt, chirp(f0, f0 * rng.uniform(1.2, 1.4), vel=0.045), rng.uniform(-0.5, 0.5)))
render(os.path.join(MUS, "mus_city_autumn_v3.wav"))

# ---------------------------------------------------------------- зима
# Холодно и просторно: ми-минор, 64 BPM, струны-льдинки высоко и редко,
# ветер вместо птиц.
BPM = 64
BAR = 4 * 60.0 / BPM
PROG = [
    ("E", [52, 55, 59]), ("C", [48, 52, 55]), ("G", [55, 59, 62]), ("D", [50, 54, 57]),
    ("E", [52, 55, 59]), ("G", [55, 59, 62]), ("C", [48, 52, 55]), ("D", [50, 54, 57]),
]
BASS = {"E": 40, "C": 36, "G": 43, "D": 38}
SCALE = [64, 67, 71, 74, 76, 79]
WIN_MELO = [
    (0.0, 0, 1.4, 0.3), (2.5, 1, 1.0, 0.26),
    (0.5, 2, 1.2, 0.28), (2.5, 3, 1.2, 0.30),
    (1.0, 4, 1.3, 0.3), (3.0, 2, 1.0, 0.26),
    (0.0, 3, 1.3, 0.28), (2.0, 5, 1.4, 0.3),
    (0.5, 1, 1.1, 0.26), (3.0, 0, 1.3, 0.28),
    (1.0, 2, 1.2, 0.28), (3.0, 4, 1.2, 0.28),
    (0.0, 5, 1.5, 0.3), (2.5, 3, 1.1, 0.26),
    (0.5, 4, 1.2, 0.28), (2.5, 2, 1.2, 0.28),
    (0.0, 1, 1.3, 0.28), (3.0, 3, 1.2, 0.28),
    (0.5, 2, 1.2, 0.28), (2.5, 0, 1.4, 0.28),
    (0.0, 3, 1.3, 0.28), (2.5, 4, 1.2, 0.28),
    (1.0, 5, 1.4, 0.3),
    (0.0, 2, 1.4, 0.28), (2.5, 1, 1.1, 0.24),
]
ev = []
total = 0.0
for cycle in range(3):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        for j, m in enumerate(chord):
            ev.append((t0 + 0.045 * j, pad_voice(midi2f(m), BAR * 1.06 - 0.045 * j, 0.34), -0.35 + 0.35 * j))
        arp_bar(ev, t0, chord, BAR, 0.11, wide=0.4, up=(i % 2 == 0))
        bass_m = BASS[root] + (7 if i % 4 == 3 else 0)
        ev.append((t0, drone(midi2f(bass_m), BAR * 1.06, 0.42 if i % 4 == 3 else 0.5), 0.0))
        k4 = (cycle * len(PROG) + i) % (len(WIN_MELO) // 2)
        for off, ni, dur, vel in WIN_MELO[k4 * 2: k4 * 2 + 2]:
            sig = pluck(midi2f(SCALE[ni]), dur, vel)
            tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.015, 0.015))
            pan = float(rng.uniform(-0.3, 0.3))
            ev.append((tt, sig, pan))
            ev.append((tt + 0.011, sig * 0.4, -pan))
# ветер: куски тихого шумового дыхания по 12с, два тона
for tt in range(0, int(total), 12):
    d = min(12.0, total + 1.0 - tt)
    if d <= 0.5:
        break
    n = int(d * SR)
    w2 = fft_lp(rng.standard_normal(n), 560.0, 2.0)
    w2 *= (0.7 + 0.3 * np.sin(2 * np.pi * 0.06 * np.arange(n) / SR)) \
        * env_ar(n, min(2.5, d * 0.3), min(2.5, d * 0.3))
    ev.append((float(tt), w2 * 0.045, 0.0))
render(os.path.join(MUS, "mus_city_winter_v3.wav"))

# ---------------------------------------------------------------- бой
# Рейд: ля-минор, 118 BPM, остинато низких струн, плотный барабан,
# аккордовые уколы, андулусийский спуск Am G F E.
BPM = 118
BAR = 4 * 60.0 / BPM
PROG = [
    ("A", [45, 52, 57]), ("G", [43, 50, 55]), ("F", [41, 48, 53]), ("E", [40, 47, 52]),
]
BASS = {"A": 33, "G": 31, "F": 29, "E": 28}
OST = [57, 60, 62, 64, 60, 57, 64, 60]
ev = []
total = 0.0
for cycle in range(2):
    for i, (root, chord) in enumerate(PROG):
        for rep in range(2):
            t0 = (cycle * len(PROG) * 2 + i * 2 + rep) * BAR
            total = t0 + BAR
            for j, m in enumerate(chord):
                ev.append((t0 + 0.03 * j, pad_voice(midi2f(m + 12), BAR * 0.55 - 0.03 * j, 0.5), -0.3 + 0.3 * j))
            ev.append((t0, drone(midi2f(BASS[root]), BAR * 1.02, 0.6), 0.0))
            for b in range(4):
                ev.append((t0 + b * BAR / 4.0, thump(0.5 if b % 2 == 0 else 0.3), 0.0))
            for b in range(8):
                ev.append((t0 + b * BAR / 8.0 + BAR / 16.0, tick(0.09), 0.4 if b % 2 == 0 else -0.4))
            for k5 in range(8):
                sig = pluck(midi2f(OST[k5]), 0.5, 0.3)
                ev.append((t0 + k5 * BAR / 8.0, sig, 0.3 * np.sin(k5 + i)))
            ev.append((t0, pluck(midi2f(chord[2] + 12), 1.2, 0.3), -0.3))
render(os.path.join(MUS, "mus_battle_v3.wav"))

print("ГОТОВО — 6 треков в assets/audio/music/")
'''
s = s.rstrip() + "\n" + TAIL
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ok: скрипт дополнен 4 треками")
