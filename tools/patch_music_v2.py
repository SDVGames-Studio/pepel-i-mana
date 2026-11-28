# -*- coding: utf-8 -*-
"""v3.0.6 музыка по фидбеку: зима — без «шума моря» (ветер убран),
холодно и ТЯЖЕЛО (глубокий дрон, било, фригийский колорит, без перкуссии
кроме редкого удара сердца); бой — динамичнее и агрессивнее (138 BPM,
двойной барабан, остинато + перекличка, секция B с мелодией).
Принятые меню/весна/лето/осень не тронуты (rng-порядок цел).
Запуск: python -I tools/patch_music_v2.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "tools", "make_music_v3.py")
s = io.open(P, encoding="utf-8", newline="").read()

# маркеры секций
i_w = s.index("# ---------------------------------------------------------------- зима")
i_b = s.index("# ---------------------------------------------------------------- бой")
i_end = s.index('print("ГОТОВО — 6 треков в assets/audio/music/")')

NEW = r'''# ---------------------------------------------------------------- зима
# v3.0.6 (фидбек: «шум моря» → холодный тяжёлый период): ветер УБРАН.
# Тяжесть: глубокий дрон с квинтой, било (негармоничные партии, долгий
# спад), фригийский колорит (F над Em), редкие высокие струны, без
# перкуссии кроме глухого удара-сердцебиения.
BPM = 56
BAR = 4 * 60.0 / BPM
PROG = [
    ("E", [52, 55, 59]), ("C", [48, 52, 55]), ("A", [45, 52, 57]), ("B", [47, 51, 54]),
    ("E", [52, 55, 59]), ("F", [53, 57, 60]), ("C", [48, 52, 55]), ("B", [47, 51, 54]),
]
BASS = {"E": 40, "C": 36, "A": 33, "B": 35, "F": 41}
SCALE = [64, 65, 67, 69, 71, 72, 76]   # ми-фригийский, высокие
WIN_MELO = [
    (1.0, 0, 2.0, 0.3), (0.0, 2, 2.2, 0.28),
    (1.5, 3, 2.0, 0.3), (0.0, 1, 2.4, 0.26),
    (2.0, 4, 2.2, 0.3), (0.0, 3, 2.2, 0.28),
    (1.0, 5, 2.4, 0.3), (0.0, 2, 2.2, 0.26),
    (1.5, 1, 2.0, 0.28), (0.0, 4, 2.4, 0.3),
    (2.0, 2, 2.2, 0.28), (0.0, 3, 2.2, 0.28),
    (1.0, 6, 2.4, 0.3), (0.0, 5, 2.2, 0.28),
    (1.5, 4, 2.2, 0.3), (0.0, 2, 2.4, 0.26),
    (1.0, 3, 2.2, 0.3), (0.0, 1, 2.2, 0.26),
    (2.0, 0, 2.4, 0.28),
]
ev = []
total = 0.0
for cycle in range(2):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        for j, m in enumerate(chord):
            ev.append((t0 + 0.05 * j, pad_voice(midi2f(m), BAR * 1.08 - 0.05 * j, 0.3), -0.35 + 0.35 * j))
        bass_m = BASS[root]
        ev.append((t0, drone(midi2f(bass_m), BAR * 1.08, 0.85 if i % 4 == 3 else 0.72), 0.0))
        # сердце: глухой низкий удар в начале такта, через такт
        if (cycle * len(PROG) + i) % 2 == 0:
            ev.append((t0, thump(0.3), 0.0))
        # било: длинный холодный звон на первом и пятом тактах круга
        if i == 0 or i == 4:
            ev.append((t0, bell(midi2f(52 + 12), 6.5, 0.4), -0.2))
        # одна редкая струна-льдинка на такт
        k4 = (cycle * len(PROG) + i) % len(WIN_MELO)
        off, ni, dur, vel = WIN_MELO[k4]
        sig = pluck(midi2f(SCALE[ni]), dur, vel)
        tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.015, 0.015))
        pan = float(rng.uniform(-0.3, 0.3))
        ev.append((tt, sig, pan))
        ev.append((tt + 0.011, sig * 0.4, -pan))
render(os.path.join(MUS, "mus_city_winter_v3.wav"))

# ---------------------------------------------------------------- бой
# v3.0.6 (фидбек: «динамичнее и агрессивнее»): 118→138 BPM, барабан
# двойной (сильные доли + шестнадцатые тики с перекличкой), остинато
# плотнее, секция B — наступательная перекличка струн, финальный разгон.
BPM = 138
BAR = 4 * 60.0 / BPM
PROG = [
    ("A", [45, 52, 57]), ("G", [43, 50, 55]), ("F", [41, 48, 53]), ("E", [40, 47, 52]),
]
BASS = {"A": 33, "G": 31, "F": 29, "E": 28}
OST = [57, 60, 62, 64, 60, 57, 64, 60]
RIFF = [64, 65, 64, 62, 60, 62, 64, 60, 57, 60, 62, 64, 65, 64, 62, 60]
HIGH = [72, 74, 76, 77, 76, 74]
ev = []
total = 0.0


def _battle_bar(t0, root, chord, section, bar_i):
    global total
    total = t0 + BAR
    # уколы пэда: сильная доля + синкопа на «и» второй
    for j, m in enumerate(chord):
        ev.append((t0 + 0.02 * j, pad_voice(midi2f(m + 12), BAR * 0.4 - 0.02 * j, 0.55), -0.3 + 0.3 * j))
    if section != "A" and bar_i % 2 == 1:
        ev.append((t0 + BAR * 0.375, pad_voice(midi2f(chord[2] + 12), BAR * 0.25, 0.4), 0.2))
    ev.append((t0, drone(midi2f(BASS[root]), BAR * 1.02, 0.65), 0.0))
    # барабан: все четыре доли + шестнадцатые тики перекличкой
    for b in range(4):
        ev.append((t0 + b * BAR / 4.0, thump(0.55 if b % 2 == 0 else 0.35), 0.0))
    for b in range(8):
        ev.append((t0 + b * BAR / 8.0 + BAR / 16.0, tick(0.1 if b % 2 == 0 else 0.06),
                   0.45 if b % 2 == 0 else -0.45))
    # глухой двойной удар в конце каждого 4-го такта (разгон)
    if bar_i % 4 == 3:
        ev.append((t0 + BAR * 0.75, thump(0.4), 0.0))
        ev.append((t0 + BAR * 0.875, thump(0.5), 0.0))
    # остинато: восьмые, в B секции — с перекличкой верхних струн
    for k5 in range(8):
        sig = pluck(midi2f(OST[k5]), 0.35, 0.34)
        ev.append((t0 + k5 * BAR / 8.0, sig, 0.3 * np.sin(k5 + bar_i)))
    if section == "B":
        for k6 in range(4):
            m = RIFF[(bar_i * 4 + k6) % len(RIFF)]
            ev.append((t0 + k6 * BAR / 4.0 + BAR / 16.0,
                       pluck(midi2f(m + 12), 0.4, 0.36), -0.3 * np.sin(bar_i + k6)))
        if bar_i % 2 == 0:
            ev.append((t0 + BAR * 0.5, pluck(midi2f(HIGH[(bar_i // 2) % len(HIGH)] + 12),
                    0.5, 0.22), 0.4))


for cycle in range(4):
    for i, (root, chord) in enumerate(PROG):
        # A A B B A A B B (разгон-циклы: вторая половина — секция B)
        section = "B" if i >= 2 else "A"
        _battle_bar((cycle * len(PROG) + i) * BAR, root, chord, section, cycle * len(PROG) + i)
render(os.path.join(MUS, "mus_battle_v3.wav"))

'''
s = s[:i_w] + NEW + s[i_end:]

# хелпер било — вставить перед render()
bell = '''def bell(f, dur, vel=0.3):
    """Било/колокол: негармоничные партии (реальный профиль колокола),
    долгий холодный спад — тяжесть зимнего периода."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, a in ((0.5, 0.4), (1.0, 1.0), (2.4, 0.45), (3.0, 0.22), (4.2, 0.1)):
        out += a * np.sin(2 * np.pi * f * ratio * t + float(rng.uniform(0, 6.28))) \\
            * np.exp(-t * (1.4 + ratio * 0.55))
    return vel * fft_lp(out * env_ar(n, 0.004, dur * 0.7), 3400)


'''
anchor = "def convolve_reverb"
i_c = s.index(anchor)
s = s[:i_c] + bell + s[i_c:]

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ok: зима и бой переписаны по фидбеку")
