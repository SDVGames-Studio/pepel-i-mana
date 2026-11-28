# -*- coding: utf-8 -*-
"""v3.0.7 музыка «натурально» (фидбек: «звучит плохо, нужно более
натурально»): зима и бой переведены на Karplus-Strong физмодель струны
(настоящий щипок: шумовое возбуждение, затухание по периоду, ком-выбор
позиции щипка), мембрана барабана с двумя модами, било с биениями партий
и щелчком удара. Аддитивные пэды в этих треках больше не звучат.
Принятые меню/весна/лето/осень НЕ тронуты (helpers общие не менялись).
Запуск: python -I tools/patch_music_natural.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "tools", "make_music_v3.py")
s = io.open(P, encoding="utf-8", newline="").read()

# 1) новые натуральные инструменты — вставить перед convolve_reverb
HELPERS = '''def ks_pluck(f, dur, vel=1.0, damp=0.996, lp=8000, pick=0.28):
    """Karplus-Strong: физмодель щипковой струны. Возбуждение — шум с
    комом позиции щипка; каждый период сигнал сглаживается и глохнет —
    естественный спад, у высоких струн быстрее (как в жизни)."""
    N = max(2, int(SR / f))
    exc = rng.standard_normal(N)
    exc = fft_lp(exc, min(f * 9.0, lp))
    d = max(1, int(N * pick))
    exc[d:] -= exc[:-d] * 0.85
    exc[:d] *= 0.2
    n = int(dur * SR)
    blocks = (n + N - 1) // N
    b = exc.copy()
    out = np.empty(blocks * N)
    for i in range(blocks):
        out[i * N:(i + 1) * N] = b
        b = damp * 0.5 * (b + np.roll(b, -1))
    return vel * fft_lp(out[:n], 7000)


def ks_bass(f, dur, vel=1.0, damp=0.9993):
    """Низкая струна: медленный KS-спад + lowpass в тело — тяжесть без
    синтетического гула."""
    return vel * fft_lp(ks_pluck(f, dur, 1.0, damp=damp, lp=1400, pick=0.42), 520)


def thump2(vel=0.5):
    """Обрядовая мембрана: две моды (тело с падением питча + звон обода)
    и настоящий щелчок кожи."""
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(96 * np.exp(-t * 14) + 44) / SR) * np.exp(-t * 11)
    ring = 0.38 * np.sin(2 * np.pi * 187 * t) * np.exp(-t * 26)
    click = 0.3 * rng.standard_normal(n) * np.exp(-t * 75)
    return vel * fft_lp(body + ring + click, 1100)


def bell2(f, dur, vel=0.3):
    """Било: партии с биением (пара расстроенных ~0.15%), щелчок удара
    в атаке — живой металл, не органный регистр."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, a in ((0.5, 0.4), (1.0, 1.0), (2.4, 0.4), (3.0, 0.2), (4.2, 0.09)):
        for det in (1.0, 1.0015):
            out += a * 0.5 * np.sin(2 * np.pi * f * ratio * det * t
                    + float(rng.uniform(0, 6.28))) * np.exp(-t * (1.3 + ratio * 0.5))
    strike = 0.25 * fft_lp(rng.standard_normal(n), f * 6.0) * np.exp(-t * 60)
    return vel * fft_lp((out + strike) * env_ar(n, 0.002, dur * 0.7), 3600)


'''
anchor = "def convolve_reverb"
i_c = s.index(anchor)
s = s[:i_c] + HELPERS + s[i_c:]

# 2) зима и бой: целиком новые тела
i_w = s.index("# ---------------------------------------------------------------- зима")
i_b = s.index("# ---------------------------------------------------------------- бой")
i_end = s.index('print("ГОТОВО — 6 треков в assets/audio/music/")')

NEW = r'''# ---------------------------------------------------------------- зима
# v3.0.7 «натурально»: ветер-шум и аддитивные пэды УБРАНЫ. Вся ткань —
# Karplus-Strong струны: низкая тяжёлая (перезакачка каждый такт),
# холодный перебор-держание, льдинки, било с биениями. 56 BPM.
BPM = 56
BAR = 4 * 60.0 / BPM
PROG = [
    ("E", [52, 55, 59]), ("C", [48, 52, 55]), ("A", [45, 52, 57]), ("B", [47, 51, 54]),
    ("E", [52, 55, 59]), ("F", [53, 57, 60]), ("C", [48, 52, 55]), ("B", [47, 51, 54]),
]
BASS = {"E": 40, "C": 36, "A": 33, "B": 35, "F": 41}
SCALE = [64, 65, 67, 69, 71, 72, 76]
WIN_MELO = [
    (1.0, 0, 2.2), (0.0, 2, 2.4),
    (1.5, 3, 2.2), (0.0, 1, 2.6),
    (2.0, 4, 2.4), (0.0, 3, 2.4),
    (1.0, 5, 2.6), (0.0, 2, 2.4),
    (1.5, 1, 2.2), (0.0, 4, 2.6),
    (2.0, 2, 2.4), (0.0, 3, 2.4),
    (1.0, 6, 2.6), (0.0, 5, 2.4),
    (1.5, 4, 2.4), (0.0, 2, 2.6),
    (1.0, 3, 2.4), (0.0, 1, 2.4),
    (2.0, 0, 2.6),
]
ev = []
total = 0.0
for cycle in range(2):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        # низкая струна — перезакачка каждый такт (жизнь инструмента)
        ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.5, 0.9), 0.0))
        # держание: три струны аккорда внахлёст, долго звенят
        for j, m in enumerate(chord):
            ev.append((t0 + 0.09 * j,
                       ks_pluck(midi2f(m), BAR * 1.6 - 0.09 * j, 0.3,
                                damp=0.9975, lp=4200),
                       -0.35 + 0.35 * j))
        # сердце: глухой удар через такт
        if (cycle * len(PROG) + i) % 2 == 0:
            ev.append((t0, thump2(0.32), 0.0))
        # било на первом и пятом тактах круга
        if i == 0 or i == 4:
            ev.append((t0, bell2(midi2f(64), 7.0, 0.42), -0.2))
        # льдинка: одна струна на такт
        k4 = (cycle * len(PROG) + i) % len(WIN_MELO)
        off, ni, dur = WIN_MELO[k4]
        sig = ks_pluck(midi2f(SCALE[ni]), dur, 0.3, damp=0.997, lp=7000)
        tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.015, 0.015))
        pan = float(rng.uniform(-0.3, 0.3))
        ev.append((tt, sig, pan))
        ev.append((tt + 0.011, sig * 0.4, -pan))
render(os.path.join(MUS, "mus_city_winter_v3.wav"))

# ---------------------------------------------------------------- бой
# v3.0.7 «натурально»: та же агрессия (138 BPM, A/B секции), но вся
# ткань KS-струны и мембрана thump2 — остинато, уколы, перекличка.
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
    # укол: три KS-струны аккорда быстро друг за другом (щипок-выпад)
    for j, m in enumerate(chord):
        ev.append((t0 + 0.02 * j,
                   ks_pluck(midi2f(m + 12), 0.5 - 0.02 * j, 0.5,
                            damp=0.9935, lp=6000),
                   -0.3 + 0.3 * j))
    if section != "A" and bar_i % 2 == 1:
        ev.append((t0 + BAR * 0.375,
                   ks_pluck(midi2f(chord[2] + 24), 0.35, 0.4, damp=0.9935, lp=6500),
                   0.2))
    ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.05, 0.7, damp=0.9975), 0.0))
    # мембрана: все доли + шестнадцатые тики перекличкой
    for b in range(4):
        ev.append((t0 + b * BAR / 4.0, thump2(0.6 if b % 2 == 0 else 0.38), 0.0))
    for b in range(8):
        ev.append((t0 + b * BAR / 8.0 + BAR / 16.0, tick(0.1 if b % 2 == 0 else 0.06),
                   0.45 if b % 2 == 0 else -0.45))
    if bar_i % 4 == 3:
        ev.append((t0 + BAR * 0.75, thump2(0.45), 0.0))
        ev.append((t0 + BAR * 0.875, thump2(0.55), 0.0))
    # остинато: восьмые KS-струны, в B — перекличка рифом и высокими
    for k5 in range(8):
        sig = ks_pluck(midi2f(OST[k5]), 0.45, 0.34, damp=0.994, lp=6500)
        ev.append((t0 + k5 * BAR / 8.0, sig, 0.3 * np.sin(k5 + bar_i)))
    if section == "B":
        for k6 in range(4):
            m = RIFF[(bar_i * 4 + k6) % len(RIFF)]
            ev.append((t0 + k6 * BAR / 4.0 + BAR / 16.0,
                       ks_pluck(midi2f(m + 12), 0.45, 0.36, damp=0.994, lp=6500),
                       -0.3 * np.sin(bar_i + k6)))
        if bar_i % 2 == 0:
            ev.append((t0 + BAR * 0.5,
                       ks_pluck(midi2f(HIGH[(bar_i // 2) % len(HIGH)] + 12), 0.5, 0.22,
                                damp=0.994, lp=7000), 0.4))


for cycle in range(6):
    for i, (root, chord) in enumerate(PROG):
        # A A B B A A B B (разгон-циклы: вторая половина — секция B)
        section = "B" if i >= 2 else "A"
        _battle_bar((cycle * len(PROG) + i) * BAR, root, chord, section, cycle * len(PROG) + i)
render(os.path.join(MUS, "mus_battle_v3.wav"))

'''
s = s[:i_w] + NEW + s[i_end:]

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ok: зима/бой на Karplus-Strong и мембране")
