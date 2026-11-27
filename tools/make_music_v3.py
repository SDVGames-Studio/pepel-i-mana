# -*- coding: utf-8 -*-
"""МУЗЫКА v3 (бриф заказчика: «не денди 1992» — пэды/реверб/минор,
инструментальные тембры). Чистый numpy: additive pluck (гусли),
мягкие пэды с детюном и LFO, дрон-бас, Frame-drum, FFT-фильтры,
свёрточный реверб (шумовой IR), стерео-широта.

Рендер на ПРИЁМКУ (2 файла, build/audio_preview — вне git):
  mus_menu_v3.wav          — главное меню: тёмный фолк, ля-минор
  mus_city_spring_v3.wav   — город, весна: ре-дорий, светлее

Запуск: python -I tools/make_music_v3.py
"""
import os
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(20261128)


def midi2f(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def fft_lp(x, fc, order=3.0):
    """Мягкий lowpass через спектр (векторно, без IIR-циклов)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    H = 1.0 / (1.0 + (f / max(80.0, fc)) ** order)
    return np.fft.irfft(X * H, n=len(x))


def env_ar(n, atk, rel):
    e = np.ones(n)
    a = min(n, int(atk * SR))
    r = min(n - a, int(rel * SR))
    if a > 0:
        e[:a] = np.linspace(0, 1, a) ** 2
    if r > 0:
        e[-r:] *= np.linspace(1, 0, r) ** 1.4
    return e


def pluck(f, dur, vel=1.0):
    """Ясная щипковая струна (сантур/гусли): один когерентный голос,
    выровненные фазы, жёсткость струны даёт блеск без биений;
    живость — атака и стерео-дубль, ноты не «выскакивают»."""
    vel = vel * float(rng.uniform(0.9, 1.1))
    f = f * 2 ** (float(rng.uniform(-3, 3)) / 1200.0)
    dur = dur * float(rng.uniform(0.94, 1.1))
    n = int(dur * SR)
    t = np.arange(n) / SR
    bright = min(1.0, 0.55 + vel * 0.6)
    out = np.zeros(n)
    for k in range(1, 13):
        amp = (1.0 / k ** 1.3) * (bright ** (k - 1))
        fk = f * k * (1.0 + 0.0004 * k * k)   # жёсткость струны
        out += amp * np.sin(2 * np.pi * fk * t) * np.exp(-t * (2.2 + 1.5 * k ** 0.65))
    out += 0.07 * rng.standard_normal(n) * np.exp(-t * 90)
    return vel * out * 0.4


def arp_bar(events, t0, chord, BAR, vel, wide=0.5, up=True):
    """Перебор гуслей: 8 струн за такт по аккорду, соседние внахлёст
    (хвост 2.2с), чередование панорамы — в любой момент звенят 3-4 струны."""
    tones = [chord[0], chord[1], chord[2], chord[2] + 12]
    order = tones + tones[::-1][1:-1] if False else (tones + tones[1:3])
    seq = order[:8]
    while len(seq) < 8:
        seq.append(tones[len(seq) % len(tones)])
    if not up:
        seq = seq[::-1]
    for k, m in enumerate(seq):
        events.append((t0 + k * BAR / 8.0 + float(rng.uniform(-0.012, 0.012)),
                       pluck(midi2f(m), 2.2, vel * float(rng.uniform(0.85, 1.15))),
                       (-wide if k % 2 == 0 else wide) * float(rng.uniform(0.7, 1.0))))

def pad_voice(f, dur, vel=1.0):
    """Мягкий пэд: 3 детюна, тёплые гармоники, LFO дыхания."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    v = np.zeros(n)
    for det in (-2.4, 0.0, 2.2):
        fd = f * 2 ** (det / 1200.0)
        v += np.sin(2 * np.pi * fd * t) \
            + 0.32 * np.sin(2 * np.pi * 2 * fd * t + 1.3) \
            + 0.11 * np.sin(2 * np.pi * 3 * fd * t + 0.6)
    v /= 3.0
    lfo = 1.0 + 0.08 * np.sin(2 * np.pi * 0.11 * t + f * 0.01)
    return vel * fft_lp(v * env_ar(n, min(1.9, dur * 0.32), min(2.3, dur * 0.38)), 2400) / 1.6


def drone(f, dur, vel=0.8):
    """Дрон-бас: корень + субоктава, медленное дыхание."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    v = np.sin(2 * np.pi * f * t) \
        + (0.62 * np.sin(2 * np.pi * f * 0.5 * t + 0.4) if f >= 48.0 else 0.0) \
        + 0.22 * np.sin(2 * np.pi * f * 2.0 * t + 1.1)
    v *= 0.86 + 0.14 * np.sin(2 * np.pi * 0.07 * t)
    return vel * fft_lp(v * env_ar(n, 2.2, 2.4), 700) / 1.7


def thump(vel=0.5):
    """Обрядовый барабан: низкий удар с падением питча."""
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    f = 92 * np.exp(-t * 16) + 42
    v = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 15)
    v += 0.28 * rng.standard_normal(n) * np.exp(-t * 80)
    return vel * fft_lp(v, 900)


def tick(vel=0.08):
    n = int(0.06 * SR)
    v = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * 0.009))
    return vel * fft_lp(fft_lp(v, 7000, 1.2), 2500, 0.8)


def chirp(f0, f1, dur=0.09, vel=0.10):
    """Птица: короткий глиссандо-свист."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return vel * np.sin(ph) * np.sin(np.pi * t / dur) ** 2


def convolve_reverb(x, wet=0.26, tone=4200):
    """Свёрточный реверб: экспон. шумовой IR, lowpass, FFT-свёртка."""
    ir_len = int(2.1 * SR)
    ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (SR * 0.52))
    ir = fft_lp(ir, tone)
    ir /= np.sqrt(np.sum(ir ** 2)) if np.sum(ir ** 2) > 0 else 1.0
    N = 1
    while N < len(x) + ir_len:
        N <<= 1
    X = np.fft.rfft(x, N)
    H = np.fft.rfft(ir, N)
    wet_sig = np.fft.irfft(X * H, N)[:len(x)]
    return x + wet * wet_sig


def place(buf, t_s, sig, pan=0.0):
    i = int(t_s * SR)
    if i < 0 or i >= len(buf):
        return
    seg = sig[: len(buf) - i]
    gl = np.sqrt(0.5 * (1.0 - pan))
    gr = np.sqrt(0.5 * (1.0 + pan))
    buf[i: i + len(seg), 0] += seg * gl
    buf[i: i + len(seg), 1] += seg * gr


def render(out_path):
    """Синтез 44.1к -> реверб -> lowpass 10к -> 22050 стерео (формат треков)."""
    n = int((total + 3.0) * SR)
    buf = np.zeros((n, 2))
    for t, sig, pan in ev:
        place(buf, t, sig, pan)
    for ch, tone, wet in ((0, 4300, 0.27), (1, 3600, 0.24)):
        buf[:, ch] = convolve_reverb(buf[:, ch], wet, tone)
    peak = np.max(np.abs(buf))
    if peak > 0:
        buf *= 0.86 / peak
    for ch in (0, 1):
        buf[:, ch] = fft_lp(buf[:, ch], 10000)
    pcm = (buf[::2] * 32767).astype(np.int16)
    with wave.open(out_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR // 2)
        w.writeframes(pcm.tobytes())
    print("ok: %s (%.1fs, %.1fMB)" % (out_path, len(pcm) / float(SR // 2),
            os.path.getsize(out_path) / 1e6))


HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
MUS = os.path.join(GAME, "assets", "audio", "music")

# ---------------------------------------------------------------- меню
# Тёмный фолк «Пепел и Благодать»: ля-минор, 68 BPM, пэды + гусли + дрон.
BPM = 68
BAR = 4 * 60.0 / BPM
# 8-тактовый круг ×2: Am F C Em | Am F G Em
PROG = [
    ("A", [57, 60, 64]), ("F", [53, 57, 60]), ("C", [48, 52, 55]), ("E", [52, 55, 59]),
    ("A", [57, 60, 64]), ("F", [53, 57, 60]), ("G", [55, 59, 62]), ("E", [52, 55, 59]),
]
BASS = {"A": 33, "F": 41, "C": 36, "E": 40, "G": 43}   # ниже 48 Гц дрон мутнеет
SCALE = [69, 72, 74, 76, 79, 81]   # ля-минор пентатоника (A4..A5)
# мотив гуслей: (доля в такте, индекс ноты, длительность, вел)
MOTIF = [
    (0.0, 0, 1.4, 0.42), (1.5, 2, 0.8, 0.34), (2.5, 3, 1.0, 0.38),
    (3.5, 1, 0.5, 0.30),
    (0.0, 3, 1.2, 0.40), (2.0, 4, 0.9, 0.34), (3.0, 2, 1.0, 0.30),
    (0.5, 1, 0.8, 0.32), (2.5, 0, 1.4, 0.40),
    (1.0, 3, 0.9, 0.34), (2.0, 5, 1.4, 0.36),
    (0.0, 2, 1.2, 0.36), (2.5, 3, 0.8, 0.30), (3.5, 1, 0.5, 0.26),
    (0.0, 4, 1.4, 0.40), (2.0, 2, 1.0, 0.32),
    (1.0, 1, 0.9, 0.30), (3.0, 0, 1.2, 0.34),
    (0.5, 3, 1.0, 0.34), (2.5, 2, 1.2, 0.38),
    (0.0, 0, 1.4, 0.40), (2.0, 3, 1.0, 0.34),
    (1.0, 4, 0.9, 0.34), (3.0, 2, 1.0, 0.30),
    (0.0, 5, 1.6, 0.42), (2.5, 3, 1.0, 0.30),
    (0.0, 2, 1.2, 0.36), (2.0, 1, 1.0, 0.32), (3.5, 0, 0.5, 0.26),
    (0.5, 3, 1.2, 0.36), (2.5, 0, 1.4, 0.40),
    (0.0, 1, 1.2, 0.34), (2.0, 2, 1.4, 0.38),
]
ev = []
total = 0.0
for cycle in range(2):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        for j, m in enumerate(chord):
            pan = -0.35 + 0.35 * j
            ev.append((t0 + 0.045 * j, pad_voice(midi2f(m), BAR * 1.05 - 0.045 * j, 0.42), pan))
        # гусли-перебор: несколько струн звенят внахлёст весь такт
        arp_bar(ev, t0, chord, BAR, 0.16, wide=0.45, up=(i % 2 == 0))
        bass_m = BASS[root] + (7 if i % 4 == 3 else 0)
        ev.append((t0, drone(midi2f(bass_m), BAR * 1.05, 0.55 if i % 4 == 3 else 0.5), 0.0))
        k = (cycle * len(PROG) + i) % (len(MOTIF) // 3)
        for off, ni, dur, vel in MOTIF[k * 3: k * 3 + 3]:
            sig = pluck(midi2f(SCALE[ni]), dur, vel)
            tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.015, 0.015))
            pan = float(rng.uniform(-0.3, 0.3))
            ev.append((tt, sig, pan))
            # стерео-дубль 11мс с той же нотой — блеск, не чужая нота
            ev.append((tt + 0.011, sig * 0.42, -pan))
        # редкий тёплый колокол на сильную долю каждого 4-го такта
        if i % 4 == 2:
            ev.append((t0, pluck(midi2f(SCALE[4]) * 0.5, 3.5, 0.16), -0.15))
render(os.path.join(MUS, "mus_menu_v3.wav"))

# ---------------------------------------------------------------- весна
# Город весной: ре-дорий, 86 BPM, светлее, гусли активнее, барабан, птицы.
BPM = 86
BAR = 4 * 60.0 / BPM
# 8-тактовый круг ×3: Dm G C Am | Dm C G C
PROG = [
    ("D", [50, 53, 57]), ("G", [55, 59, 62]), ("C", [48, 52, 55]), ("A", [57, 60, 64]),
    ("D", [50, 53, 57]), ("C", [48, 52, 55]), ("G", [55, 59, 62]), ("C", [48, 52, 55]),
]
BASS = {"D": 38, "G": 43, "C": 36, "A": 33}
SCALE = [62, 65, 67, 69, 72, 74, 76, 79]   # ре-дорий
MELO = [
    (0.0, 4, 0.9, 0.34), (1.0, 5, 0.7, 0.30), (1.5, 4, 0.7, 0.28), (2.0, 6, 1.0, 0.36), (3.0, 5, 0.8, 0.30),
    (0.0, 3, 0.8, 0.32), (1.0, 4, 0.9, 0.34), (2.5, 3, 0.9, 0.28),
    (0.0, 2, 0.8, 0.30), (1.5, 3, 0.7, 0.30), (2.0, 4, 1.2, 0.36),
    (0.5, 5, 0.8, 0.32), (1.5, 6, 0.9, 0.34), (3.0, 4, 0.8, 0.30),
    (0.0, 4, 0.9, 0.34), (1.5, 7, 0.8, 0.30), (2.5, 6, 1.0, 0.36),
    (0.0, 5, 0.9, 0.32), (2.0, 3, 1.0, 0.34), (3.0, 2, 0.8, 0.28),
    (0.0, 4, 0.8, 0.34), (1.0, 3, 0.7, 0.28), (2.0, 2, 1.2, 0.36),
    (0.5, 3, 0.9, 0.32), (2.0, 4, 0.9, 0.34), (3.0, 5, 0.8, 0.30),
    (0.0, 6, 0.9, 0.36), (1.5, 5, 0.7, 0.28), (2.5, 4, 0.9, 0.32),
    (0.0, 3, 0.8, 0.32), (1.5, 2, 0.8, 0.28), (2.5, 3, 1.2, 0.34),
    (0.0, 4, 1.0, 0.36), (2.0, 5, 0.9, 0.32), (3.0, 6, 0.8, 0.30),
    (0.5, 4, 0.8, 0.30), (1.5, 3, 0.8, 0.30), (2.5, 2, 1.2, 0.34),
    (0.0, 2, 0.9, 0.32), (1.5, 3, 0.8, 0.30), (2.5, 4, 1.2, 0.36),
    (0.0, 5, 0.8, 0.32), (1.0, 4, 0.8, 0.30), (2.5, 3, 1.0, 0.32),
    (0.0, 4, 0.9, 0.34), (2.0, 2, 1.0, 0.32), (3.0, 1, 0.8, 0.28),
    (0.5, 3, 0.9, 0.32), (2.0, 4, 1.0, 0.34),
    (0.0, 6, 1.0, 0.36), (1.5, 4, 0.8, 0.30), (3.0, 2, 0.9, 0.30),
    (0.0, 3, 0.9, 0.32), (2.0, 4, 0.9, 0.34), (3.0, 3, 0.7, 0.28),
    (0.0, 2, 0.9, 0.32), (1.5, 4, 0.8, 0.30), (2.5, 5, 1.2, 0.36),
    (0.0, 4, 0.9, 0.34), (2.0, 3, 0.9, 0.30),
    (0.5, 2, 0.9, 0.30), (2.0, 3, 1.2, 0.34), (3.5, 4, 0.5, 0.26),
    (0.0, 5, 0.9, 0.34), (1.5, 6, 0.8, 0.30), (2.5, 7, 1.2, 0.38),
    (0.0, 4, 0.9, 0.34), (2.0, 5, 0.9, 0.32), (3.0, 6, 0.8, 0.30),
    (0.0, 3, 1.0, 0.32), (2.0, 2, 1.2, 0.34),
    (0.5, 3, 0.8, 0.30), (1.5, 4, 0.8, 0.30), (2.5, 3, 1.0, 0.32),
]
ev = []
total = 0.0
for cycle in range(3):
    for i, (root, chord) in enumerate(PROG):
        t0 = (cycle * len(PROG) + i) * BAR
        total = t0 + BAR
        for j, m in enumerate(chord):
            ev.append((t0 + 0.045 * j, pad_voice(midi2f(m), BAR * 1.04 - 0.045 * j, 0.36), -0.35 + 0.35 * j))
        arp_bar(ev, t0, chord, BAR, 0.19, wide=0.5, up=(i % 2 == 0))
        bass_m = BASS[root] + (7 if i % 4 == 3 else 0)
        ev.append((t0, drone(midi2f(bass_m), BAR * 1.04, 0.42 if i % 4 == 3 else 0.5), 0.0))
        # обрядовый барабан: сильная доля + мягкая третья
        ev.append((t0, thump(0.42), -0.1))
        ev.append((t0 + 2 * BAR / 4.0, thump(0.2), 0.1))
        ev.append((t0 + 1.5 * BAR / 4.0, tick(0.07), 0.3))
        ev.append((t0 + 3.5 * BAR / 4.0, tick(0.06), -0.3))
        k2 = (cycle * len(PROG) + i) % (len(MELO) // 3)
        for off, ni, dur, vel in MELO[k2 * 3: k2 * 3 + 3]:
            sig = pluck(midi2f(SCALE[ni]), dur, vel)
            tt = t0 + off * BAR / 4.0 + float(rng.uniform(-0.015, 0.015))
            pan = float(rng.uniform(-0.35, 0.35))
            ev.append((tt, sig, pan))
            ev.append((tt + 0.011, sig * 0.4, -pan))
        # птицы: 1-2 щелчка в такте через такт, тише на 2-м круге
        if (cycle * len(PROG) + i) % 2 == 1:
            tt = t0 + rng.uniform(0.2, BAR - 0.4)
            f0 = rng.uniform(2400, 3300)
            ev.append((tt, chirp(f0, f0 * rng.uniform(1.25, 1.5), vel=0.055 if cycle else 0.075),
                       rng.uniform(-0.6, 0.6)))
render(os.path.join(MUS, "mus_city_spring_v3.wav"))

print("

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
