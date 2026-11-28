# -*- coding: utf-8 -*-
"""SFX v3 (v3.1, бриф «натурально»): перегенерация ВСЕХ 45 звуков
действий из data/music.json в натуральных тембрах — Karplus-Strong
струны, мембрана с двумя модами, шум-трещоты кожи/дерева/камня,
било с биением. Те же имена файлов — манифест не меняется.
Запуск: python -I tools/make_sfx_v3.py
"""
import io
import json
import os
import wave

import numpy as np

SR = 22050
rng = np.random.default_rng(31112026)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets", "audio", "sfx")


def midi2f(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def fft_lp(x, fc, order=3.0):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    return np.fft.irfft(X / (1.0 + (f / max(60.0, fc)) ** order), n=len(x))


def env_ar(n, atk, rel):
    e = np.ones(n)
    a = min(n, max(1, int(atk * SR)))
    r = min(n - a, max(1, int(rel * SR)))
    e[:a] = np.linspace(0, 1, a) ** 2
    e[-r:] *= np.linspace(1, 0, r) ** 1.3
    return e


def ks(f, dur, vel=1.0, damp=0.996, lp=7000, pick=0.28):
    """Karplus-Strong струна (та же физмодель, что в музыке v3)."""
    N = max(2, int(SR / f))
    exc = rng.standard_normal(N)
    exc = fft_lp(exc, min(f * 5.0, lp))
    d = max(1, int(N * pick))
    exc[d:] -= exc[:-d] * 0.45
    exc[:d] *= 0.45
    m = min(N // 8, 24)
    if m > 0 and N - m > 0:   # у высоких нот период крошечный — без сшивки
        exc[N - m:] = np.linspace(exc[N - m], exc[0], m)
    n = int(dur * SR)
    blocks = (n + N - 1) // N
    b = exc.copy()
    out = np.empty(blocks * N)
    for i in range(blocks):
        out[i * N:(i + 1) * N] = b
        b = damp * 0.5 * (b + np.roll(b, -1))
    return vel * fft_lp(out[:n], lp)


def mem(vel=0.6, pitch=96, drop=14, dur=0.3):
    """Мембрана: тело с падением питча + звон обода + щелчок кожи."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(pitch * np.exp(-t * drop) + pitch * 0.45) / SR) \
        * np.exp(-t * (drop * 0.8))
    ring = 0.3 * np.sin(2 * np.pi * pitch * 2.0 * t) * np.exp(-t * 24)
    click = 0.25 * rng.standard_normal(n) * np.exp(-t * 80)
    return vel * fft_lp(body + ring + click, 1100)


def crack(vel=0.5, fc=3000, dur=0.06):
    """Трещота/щелчок: короткий шумовой хлопок."""
    n = int(dur * SR)
    return vel * fft_lp(rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * 0.008)), fc)


def sweep(dur, f0, f1, vel=0.5):
    """Падающий шум (падение, взмах, обвал)."""
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    # качественный даунсвип через нарезку спектра на 12 кусков
    parts = []
    step = n // 12
    for i in range(12):
        fc = f0 + (f1 - f0) * i / 11.0
        parts.append(fft_lp(noise[i * step:(i + 1) * step], max(120.0, fc)))
    x = np.concatenate(parts)
    if len(x) < n:
        x = np.concatenate([x, np.zeros(n - len(x))])
    return vel * x[:n] * env_ar(n, dur * 0.15, dur * 0.5)


def bell(f, dur, vel=0.4):
    """Било: партии с биением + щелчок удара."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, a in ((0.5, 0.4), (1.0, 1.0), (2.4, 0.4), (3.0, 0.2), (4.2, 0.09)):
        for det in (1.0, 1.0015):
            out += a * 0.5 * np.sin(2 * np.pi * f * ratio * det * t
                    + float(rng.uniform(0, 6.28))) * np.exp(-t * (1.3 + ratio * 0.5))
    strike = 0.25 * fft_lp(rng.standard_normal(n), f * 6.0) * np.exp(-t * 60)
    return vel * fft_lp((out + strike) * env_ar(n, 0.002, dur * 0.7), 3600)


def seq(events, dur):
    """events: (t, sig) — моно-сборка с нормализацией."""
    n = int(dur * SR)
    buf = np.zeros(n)
    for t, sig in events:
        i = int(t * SR)
        if i >= n:
            continue
        seg = sig[:n - i]
        buf[i:i + len(seg)] += seg
    peak = np.max(np.abs(buf))
    if peak > 0:
        buf *= 0.85 / peak
    return (buf * 32767).astype(np.int16)


GEN = {}

# --- удар/урон/гибель ---
GEN["hit"] = lambda: seq([(0, mem(1.0)), (0, crack(0.5, 3500, 0.05))], 0.4)
GEN["hero_hurt"] = lambda: seq([(0, mem(0.9, pitch=70, drop=18, dur=0.35)),
        (0, crack(0.4, 1800, 0.08))], 0.45)
GEN["enemy_die"] = lambda: seq([(0, crack(0.7, 2600, 0.09)),
        (0.05, sweep(0.5, 1800, 200, 0.7)),
        (0.3, mem(0.5, pitch=60, drop=20, dur=0.3))], 0.75)

# --- добыча/подбор ---
GEN["coin"] = lambda: seq([(0, ks(midi2f(103), 0.3, 0.8, damp=0.9945, lp=9000, pick=0.2)),
        (0.07, ks(midi2f(110), 0.35, 0.7, damp=0.9945, lp=9000, pick=0.2))], 0.45)
GEN["pickup"] = lambda: seq([(0, ks(midi2f(96), 0.3, 0.7, damp=0.995, lp=8000, pick=0.22)),
        (0.05, ks(midi2f(103), 0.35, 0.6, damp=0.995, lp=8000, pick=0.22))], 0.45)
GEN["chest"] = lambda: seq([(0, ks(midi2f(59), 0.18, 0.7, damp=0.986, lp=1300, pick=0.3)),
        (0, crack(0.4, 1600, 0.04)),
        (0.12, ks(midi2f(59), 0.16, 0.6, damp=0.986, lp=1300, pick=0.3)),
        (0.22, ks(midi2f(103), 0.3, 0.6, damp=0.9945, lp=9000, pick=0.2)),
        (0.3, ks(midi2f(110), 0.3, 0.5, damp=0.9945, lp=9000, pick=0.2))], 0.75)

# --- интерфейс ---
GEN["ui_click"] = lambda: seq([(0, crack(0.35, 4500, 0.02)),
        (0, ks(midi2f(91), 0.05, 0.3, damp=0.99, lp=6000))], 0.1)
GEN["toast"] = lambda: seq([(0, ks(midi2f(88), 0.18, 0.4, damp=0.996, lp=5000, pick=0.3)),
        (0.09, ks(midi2f(93), 0.22, 0.35, damp=0.996, lp=5000, pick=0.3))], 0.4)
GEN["alarm"] = lambda: seq([x
        for t in (0.0, 0.26, 0.52) for x in (
            (t, ks(midi2f(69), 0.2, 0.7, damp=0.9935, lp=6000, pick=0.15)),
            (t, mem(0.4, pitch=80, drop=20, dur=0.2)))], 0.9)
GEN["bell_day"] = lambda: seq([(0, bell(midi2f(69), 3.5, 0.75))], 3.6)

# --- стройка/ремесло ---
GEN["build_done"] = lambda: seq([(0, ks(midi2f(57), 0.2, 0.8, damp=0.986, lp=1300, pick=0.3)),
        (0, crack(0.5, 2000, 0.05)),
        (0.13, ks(midi2f(57), 0.25, 0.9, damp=0.986, lp=1300, pick=0.3)),
        (0.13, crack(0.6, 2200, 0.05))], 0.55)
GEN["quest_done"] = lambda: seq([(0.0, ks(midi2f(84), 0.25, 0.6, damp=0.995, lp=7000, pick=0.25)),
        (0.1, ks(midi2f(88), 0.25, 0.6, damp=0.995, lp=7000, pick=0.25)),
        (0.2, ks(midi2f(91), 0.25, 0.65, damp=0.995, lp=7000, pick=0.25)),
        (0.3, ks(midi2f(96), 0.4, 0.75, damp=0.995, lp=7000, pick=0.25))], 0.85)
GEN["wedding"] = lambda: seq([(0.0 * i, ks(midi2f(84 + i * 4), 0.3, 0.55, damp=0.995, lp=7000, pick=0.25))
        for i in range(4)] + [(0.55, bell(midi2f(96), 2.2, 0.35))], 2.8)
GEN["birth"] = lambda: seq([(0, ks(midi2f(93), 0.5, 0.5, damp=0.997, lp=6000, pick=0.3)),
        (0.1, bell(midi2f(105), 2.5, 0.3))], 2.7)

# --- деревья/рубы: три варианта wood-knock ---
for i, (f0, v0) in enumerate(((180, 0.85), (165, 0.9), (205, 0.8))):
    GEN["chop" if i == 0 else "chop_%d" % (i + 1)] = (lambda f0=f0, v0=v0: seq(
        [(0, ks(midi2f(2), 0.22, v0, damp=0.985, lp=1400, pick=0.3)),
         (0, crack(0.6, 2800, 0.04))], 0.3))
GEN["tree_fall"] = lambda: seq([(0, crack(0.7, 2200, 0.07)),
        (0.15, crack(0.8, 1800, 0.09)),
        (0.25, sweep(0.9, 1500, 150, 0.8)),
        (0.95, mem(1.0, pitch=55, drop=16, dur=0.5)),
        (0.95, crack(0.8, 1200, 0.12))], 1.5)

# --- молот/наковальня ---
for i, (f0, v0) in enumerate(((97, 0.8), (103, 0.85), (92, 0.8))):
    GEN["hammer" if i == 0 else "hammer_%d" % (i + 1)] = (lambda f0=f0, v0=v0: seq(
        [(0, crack(0.55, 5000, 0.03)),
         (0, ks(f0 / 10.0, 0.16, v0, damp=0.9945, lp=7000, pick=0.15))], 0.25))
# --- камень/шахта ---
for i, v0 in enumerate((0.9, 0.8, 0.85)):
    GEN["mine" if i == 0 else "mine_%d" % (i + 1)] = (lambda v0=v0: seq(
        [(0, crack(v0, 3800, 0.05)),
         (0, crack(v0 * 0.6, 1600, 0.1)),
         (0.07, crack(v0 * 0.5, 2500, 0.06))], 0.3))

# --- шаги ---
for i, fc in enumerate((2400, 2100, 2600)):
    GEN["step_grass" if i == 0 else "step_grass_%d" % (i + 1)] = (lambda fc=fc: seq(
        [(0, crack(0.22, fc, 0.05))], 0.12))
for i, fc in enumerate((3000, 3300)):
    GEN["step_road" if i == 0 else "step_road_%d" % (i + 1)] = (lambda fc=fc: seq(
        [(0, crack(0.25, fc, 0.04)), (0, crack(0.12, 1200, 0.03))], 0.12))
for i, fc in enumerate((4200, 3800)):
    GEN["step_stone" if i == 0 else "step_stone_%d" % (i + 1)] = (lambda fc=fc: seq(
        [(0, crack(0.3, fc, 0.025)), (0, crack(0.15, 2000, 0.02))], 0.1))
for i in range(2):
    GEN["step_water" if i == 0 else "step_water_%d" % (i + 1)] = (lambda: seq(
        [(0, crack(0.3, 1800, 0.06)),
         (0.03, ks(midi2f(96 + i * 5), 0.12, 0.25, damp=0.995, lp=7000, pick=0.2))], 0.2))

# --- шелесты ---
for name, fc, dur, v in (("rustle_soft", 1800, 0.16, 0.25), ("rustle_med", 2400, 0.22, 0.35),
        ("rustle_hard", 3200, 0.28, 0.45)):
    GEN[name] = (lambda fc=fc, dur=dur, v=v: seq([(0, sweep(dur, fc * 1.4, fc * 0.5, v))], dur + 0.1))

# --- заклинания ---
GEN["spell_wild"] = lambda: seq([(0, sweep(0.35, 400, 2400, 0.5)),
        (0.1, ks(midi2f(64), 0.5, 0.5, damp=0.995, lp=4000, pick=0.35))], 0.7)
GEN["spell_light"] = lambda: seq([(0, ks(midi2f(91), 0.3, 0.6, damp=0.995, lp=9000, pick=0.18)),
        (0.04, ks(midi2f(96), 0.35, 0.5, damp=0.995, lp=9000, pick=0.18)),
        (0.08, ks(midi2f(103), 0.4, 0.45, damp=0.995, lp=9000, pick=0.18))], 0.6)
GEN["spell_nature"] = lambda: seq([(0, crack(0.3, 1500, 0.12)),
        (0.05, ks(midi2f(67), 0.5, 0.45, damp=0.996, lp=3500, pick=0.35)),
        (0.12, crack(0.2, 1300, 0.1))], 0.7)
GEN["spell_forbidden"] = lambda: seq([(0, sweep(0.4, 2200, 250, 0.5)),
        (0.05, ks(midi2f(51), 0.6, 0.5, damp=0.996, lp=2500, pick=0.4))], 0.75)
GEN["rune"] = lambda: seq([(0, ks(midi2f(57), 0.9, 0.5, damp=0.9975, lp=4200, pick=0.35)),
        (0.08, ks(midi2f(64), 0.8, 0.35, damp=0.9975, lp=4500, pick=0.35))], 1.1)

# --- босс/фанфары ---
GEN["boss_roar"] = lambda: seq([(0, mem(1.0, pitch=52, drop=10, dur=0.9)),
        (0.05, sweep(0.85, 900, 150, 0.75)),
        (0.4, crack(0.5, 1000, 0.2))], 1.1)
GEN["fanfare"] = lambda: seq([(0.0 * i, ks(midi2f(72 + i * 4), 0.4, 0.55, damp=0.995, lp=7000, pick=0.22))
        for i in range(4)] + [(0.4, mem(0.5))], 0.9)

# --- swing ---
GEN["swing"] = lambda: seq([(0, sweep(0.18, 1100, 350, 0.55)),
        (0, crack(0.15, 2400, 0.03))], 0.28)

import json
mf = json.load(io.open(os.path.join(os.path.dirname(HERE), "data", "music.json"), encoding="utf-8"))
missing = set(mf["sfx"].keys()) - set(GEN.keys())
extra = set(GEN.keys()) - set(mf["sfx"].keys())
assert not missing and not extra, (missing, extra)

os.makedirs(OUT, exist_ok=True)
for name, gen in sorted(GEN.items()):
    pcm = gen()
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
print("ok: %d звуков перегенерированы в %s" % (len(GEN), OUT))
