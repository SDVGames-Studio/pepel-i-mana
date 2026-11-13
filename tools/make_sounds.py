# -*- coding: utf-8 -*-
"""Генератор звуков и музыки «Пепел и Мана» (v1.65, программа «Оживление»
аспект 1 — ЗВУК-ФУНДАМЕНТ). Детерминирован: random.seed(0) — перегенерация
= запуск скрипта, как у спрайтовых генераторов tools/make_*.py.

Инструменты — славянские и греческие (матрица дизайн-дока
docs/design/15-ОЖИВЛЕНИЕ.md + решения заказчика 2026-11-13):
  гусли/домра/балалайка/кифара/арфа  -> Karplus-Strong щипок
  свирель/калюка/кугиклы/жалейка/авлос -> флейтовые тоны (синус+вибрато+дыхание;
                                          авлос — двойной, резче)
  рожок -> сигнальный медный тон
  бубен/тимпан/било/кимвалы/трещотки/ложки -> ударные синтез
  волынка/гудок -> дрон с биением

Выход: assets/audio/sfx/*.wav (эффекты), assets/audio/amb/*.wav (амбиент-лупы),
assets/audio/music/*.wav (музыкальные стемы, лупы 32 с). Все лупы бесшовные.
"""
import math
import os
import random
import struct
import wave

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
random.seed(0)


def write_wav(path, samples, vol=0.8):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    k = vol / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * k)) * 32767))
                               for s in samples))
    print(" ", os.path.relpath(path, os.path.join(ROOT, "..")), len(samples) / SR, "с")


def silence(sec):
    return [0.0] * int(sec * SR)


def mix(dst, src, at, gain=1.0):
    """Вклеить src в буфер dst с позиции at секунд (суммирование)."""
    i0 = int(at * SR)
    need = i0 + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[i0 + i] += v * gain
    return dst


def env(n, a=0.01, d=0.3, sustain=0.0):
    """Простая огибающая: атака a сек, спад d, хвост sustain."""
    out = []
    na, nd = max(1, int(a * SR)), max(1, int(d * SR))
    for i in range(n):
        if i < na:
            out.append(i / na)
        elif i < na + nd:
            out.append(1.0 - (i - na) / nd * (1.0 - sustain))
        else:
            out.append(sustain)
    return out


def echo(buf, delay=0.16, gain=0.22, taps=2):
    """Простое эхо-пространство (псевдо-реверб)."""
    out = list(buf)
    d = int(delay * SR)
    for t in range(1, taps + 1):
        g = gain ** t
        for i, v in enumerate(buf):
            j = i + d * t
            if j < len(out):
                out[j] += v * g
    peak = max(1e-6, max(abs(s) for s in out))
    if peak > 0.95:
        k = 0.95 / peak
        return [s * k for s in out]
    return out


# --- инструменты -------------------------------------------------------------

def pluck(freq, dur, bright=0.5, vol=1.0, decay=0.9955, tremolo=0.0):
    """Струнный щипок v1.65.2: АДДИТИВНАЯ модель — 7 гармоник с разным
    затуханием и мягкой атакой (тёплый «гусельный» тембр; KS звучал как
    электрогитара — замечание заказчика). tremolo>0 — балалайковая дрожь."""
    total = int(dur * SR)
    out = [0.0] * total
    for h in range(1, 8):
        amp = 1.0 / (h ** (1.2 + (1.0 - bright) * 0.8))
        dec = 3.2 + h * (1.2 + bright * 1.4)
        det = 1.0 + (h % 2) * 0.0012
        ph = random.uniform(0.0, TAU)
        f = freq * det * h
        if f > SR / 2.0:
            break
        for i in range(total):
            tt = i / SR
            a = amp * math.exp(-dec * tt)
            if a < 0.001:
                break
            atk = min(1.0, tt / 0.008)
            tmod = 1.0 + tremolo * math.sin(TAU * 9.0 * tt)
            out[i] += math.sin(TAU * f * tt + ph) * a * atk * tmod
    peak = max(1e-6, max(abs(x) for x in out))
    if peak > 1.0:
        k = 1.0 / peak
        return [x * k * vol for x in out]
    return [x * vol for x in out]


def flute(freq, dur, vol=1.0, breath=0.25, vib=5.0, vib_depth=0.006, rough=False):
    """Свирель/кугиклы/жалейка; rough=True — авлос (двойной, резкий)."""
    total = int(dur * SR)
    out = []
    ph = 0.0
    e_list = env(total, a=0.04, d=dur * 0.9, sustain=0.55)   # O(n) — было O(n^2) (v1.65 фикс)
    for i in range(total):
        tt = i / SR
        f = freq * (1.0 + math.sin(tt * vib * TAU) * vib_depth)
        ph += TAU * f / SR
        s = math.sin(ph)
        if rough:
            s += 0.35 * math.sin(ph * 2.0 + 0.7) + 0.18 * math.sin(ph * 3.0)
            s *= 0.75
        br = (random.uniform(-1, 1)) * breath * 0.35
        out.append((s * 0.8 + br) * e_list[i] * vol)
    return out


def horn(freq, dur, vol=1.0):
    """Рожок: сигнальный медный тон (пила+синус, мягкая атака)."""
    total = int(dur * SR)
    out = []
    e_list = env(total, a=0.03, d=dur * 0.85, sustain=0.5)   # O(n) — было O(n^2)
    for i in range(total):
        tt = i / SR
        ph = TAU * freq * tt
        saw = 2.0 * ((freq * tt) % 1.0) - 1.0
        s = math.sin(ph) * 0.6 + saw * 0.25 + math.sin(ph * 2) * 0.15
        out.append(s * e_list[i] * vol * 0.8)
    return out


def drone(freq, dur, vol=1.0, beat=0.7):
    """Волынка/гудок: дрон с медленным биением двух расстроенных тонов."""
    total = int(dur * SR)
    out = []
    ph1 = ph2 = 0.0
    for i in range(total):
        f2 = freq * (1.0 + beat * 0.004)
        ph1 += TAU * freq / SR
        ph2 += TAU * f2 / SR
        s = math.sin(ph1) * 0.5 + math.sin(ph2) * 0.5 + math.sin(ph1 * 2) * 0.12
        out.append(s * vol * 0.6)
    return out


def hit_low(freq=70.0, dur=0.35, vol=1.0):
    """Тимпан/толчок: синус с падением высоты + шумовой тычок."""
    total = int(dur * SR)
    out = []
    for i in range(total):
        tt = i / SR
        f = freq * (1.0 - 0.4 * tt / dur)
        ph = TAU * f * tt
        s = math.sin(ph) * math.exp(-tt * 9.0)
        s += random.uniform(-1, 1) * math.exp(-tt * 40.0) * 0.5
        out.append(s * vol * 0.9)
    return out


def cymbal(dur=0.5, vol=1.0):
    """Кимвалы: металлический звон — шум через резонансы."""
    total = int(dur * SR)
    out = []
    for i in range(total):
        tt = i / SR
        s = 0.0
        for f, a in [(3200, 1.0), (4700, 0.7), (6100, 0.5), (8300, 0.4)]:
            s += a * math.sin(TAU * f * tt + random.uniform(0, 0.2))
        e = math.exp(-tt * 7.0)
        out.append(s * e * vol * 0.22)
    return out


def wood_click(freq=1100.0, dur=0.06, vol=1.0):
    """Трещотка/ложки: деревянный щелчок."""
    total = int(dur * SR)
    out = []
    for i in range(total):
        tt = i / SR
        s = math.sin(TAU * freq * tt) * math.exp(-tt * 90.0)
        s += random.uniform(-1, 1) * math.exp(-tt * 160.0) * 0.6
        out.append(s * vol)
    return out



def swing(dur=0.22, vol=1.0):
    """Взмах оружия: шумовой свуш с подъёмом и спадом."""
    total = int(dur * SR)
    out = []
    last = 0.0
    for i in range(total):
        tt = i / total
        lp = 0.02 + 0.2 * math.sin(tt * math.pi)
        last = last * (1.0 - lp) + random.uniform(-1, 1) * lp
        amp = math.sin(tt * math.pi) ** 1.5
        out.append(last * amp * vol * 0.9)
    return out


def bell(freq, dur, vol=1.0, strike=1.0):
    """Било/колокол: набор негармоничных партиалов."""
    total = int(dur * SR)
    out = []
    for i in range(total):
        tt = i / SR
        s = 0.0
        for mult, a in [(1.0, 1.0), (2.7, 0.5), (5.4, 0.25), (8.1, 0.12)]:
            s += a * math.sin(TAU * freq * mult * tt) * math.exp(-tt * (3.5 / mult))
        out.append(s * vol * 0.5 * strike)
    return out


def noise_bed(dur, lp=0.12, vol=1.0, lfo=0.1, lfo_depth=0.5):
    """Шумовая подушка (ветер) с медленной модуляцией громкости."""
    total = int(dur * SR)
    out = [0.0] * total
    last = 0.0
    for i in range(total):
        tt = i / SR
        last = last * (1.0 - lp) + random.uniform(-1, 1) * lp
        m = 1.0 - lfo_depth * 0.5 * (1.0 + math.sin(TAU * lfo * tt))
        out[i] = last * vol * m
    return out


TAU = math.pi * 2

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name, octave):
    semis = NOTE[name] + (octave - 4) * 12 - 9  # A4 = 440
    return 440.0 * (2.0 ** (semis / 12.0))


# --- музыкальные лупы --------------------------------------------------------

def render_track(path, bpm, bars, scale, pattern, instr, vol=0.75, base_oct=4,
                 echo_on=True, drone_note=None, drone_vol=0.16, swing=0.0):
    """pattern: список тактов; такт = строка шагов '0 3 . 2' (индекс в scale,
    '.' — пауза), 16 шагов на такт (1/16)."""
    beat = 60.0 / bpm
    step = beat / 4.0
    total = bars * 16 * step
    buf = silence(total)
    if drone_note is not None:
        base = hz(drone_note[0], drone_note[1])
        mix(buf, drone(base, total, drone_vol), 0)
        mix(buf, drone(base * 1.4983, total, drone_vol * 0.55), 0)   # бурдон квинтой
    for bar_i, pat in enumerate(pattern):
        steps = pat.split()
        for s_i, tok in enumerate(steps):
            if tok == ".":
                continue
            ni = int(tok) % len(scale)
            name, octv = scale[ni]
            at = (bar_i * 16 + s_i) * step
            sw = swing * step * (0.5 if s_i % 2 else -0.5)
            at = max(0.0, at + sw)
            dur = step * (3.0 if s_i % 4 == 0 else 2.0)
            mix(buf, instr(hz(name, octv), dur), at)
    if echo_on:
        buf = echo(buf, 0.16, 0.2, 2)
    write_wav(path, buf, vol)


def render_amb(path, sec, layers):
    buf = silence(sec)
    for layer in layers:
        mix(buf, layer["buf"], layer.get("at", 0.0), layer.get("gain", 1.0))
    write_wav(path, buf, 0.75)


def bird_chirp():
    """Мягкий двухсложный низкий свист с вибрато (не «пи-пи»)."""
    out = []
    f0 = random.uniform(900, 1400)
    for k in range(2):
        d = random.uniform(0.10, 0.16)
        n = int(d * SR)
        for i in range(n):
            tt = i / SR
            f = f0 * (1.0 + 0.06 * math.sin(TAU * 22.0 * tt)) * (1.0 - 0.12 * tt / d)
            e = env(n, a=0.02, d=d * 0.75)[i]
            out.append(math.sin(TAU * f * tt) * e * 0.5)
        out.extend([0.0] * int(random.uniform(0.06, 0.1) * SR))
    return out


def cricket_burst(dur=0.9):
    """Сверчки: мягкая трель ~1400 Гц, приглушённая."""
    out = [0.0] * int(dur * SR)
    for k in range(int(dur / 0.15)):
        n = int(0.05 * SR)
        for i in range(n):
            tt = i / SR
            f = 1400.0 * (1.0 + 0.04 * math.sin(TAU * 30.0 * tt))
            out[int(k * 0.15 * SR) + i] += math.sin(TAU * f * tt) \
                    * env(n, a=0.008, d=n / SR * 0.8)[i] * 0.28
    return out


def drip():
    n = int(0.12 * SR)
    out = []
    for i in range(n):
        tt = i / SR
        f = 1800.0 * (1.0 - 0.5 * tt / 0.12)
        out.append(math.sin(TAU * f * tt) * math.exp(-tt * 45.0) * 0.8)
    return out


def owl_hoot():
    out = []
    for d, g in [(0.28, 0.9), (0.4, 1.0)]:
        n = int(d * SR)
        for i in range(n):
            tt = i / SR
            f = 340.0 * (1.0 - 0.1 * tt / d)
            out.append(math.sin(TAU * f * tt) * env(n, 0.08, d * 0.7)[i] * g * 0.7)
        out.extend([0.0] * int(0.12 * SR))
    return out


# --- эффекты -----------------------------------------------------------------

def step(dur=0.09, lp=0.18, vol=1.0, thud=0.0, thud_f=120.0):
    """Шаг: короткий глухой шорох; thud — низкий тычок (пятка)."""
    n = int(dur * SR)
    out = [0.0] * n
    last = 0.0
    for i in range(n):
        tt = i / SR
        last = last * (1.0 - lp) + random.uniform(-1, 1) * lp
        out[i] = last * math.exp(-tt * 55.0)
        if thud > 0.0:
            out[i] += math.sin(TAU * thud_f * tt) * math.exp(-tt * 60.0) * thud
    return [x * vol for x in out]


def sfx_chop():
    """Удар топора по дереву: резкий треск + деревянный резонанс."""
    buf = silence(0.35)
    mix(buf, [random.uniform(-1, 1) * math.exp(-(i / SR) * 30.0) for i in range(int(0.08 * SR))], 0.0, 0.9)
    n = int(0.3 * SR)
    for i in range(n):
        tt = i / SR
        s = math.sin(TAU * 420.0 * tt) * 0.5 + math.sin(TAU * 780.0 * tt) * 0.3
        mix(buf, [s * math.exp(-tt * 14.0)], 0.01, 1.0)
    mix(buf, noise_bed(0.2, lp=0.15, vol=0.3), 0.02)
    return buf


def sfx_hammer():
    """Удар молота в стройке: деревянный тычок + металлический звон."""
    buf = silence(0.3)
    mix(buf, hit_low(95, 0.18, 0.9), 0.0)
    n = int(0.22 * SR)
    for i in range(n):
        tt = i / SR
        s = math.sin(TAU * 1150.0 * tt) * 0.4 + math.sin(TAU * 1900.0 * tt) * 0.2
        mix(buf, [s * math.exp(-tt * 26.0)], 0.012, 1.0)
    return buf


def sfx_mine():
    """Удар киркой по камню: звон + щебень."""
    buf = silence(0.3)
    n = int(0.25 * SR)
    for i in range(n):
        tt = i / SR
        s = math.sin(TAU * 900.0 * tt) * 0.4 + math.sin(TAU * 2400.0 * tt) * 0.3
        mix(buf, [s * math.exp(-tt * 20.0)], 0.0, 1.0)
    mix(buf, [random.uniform(-1, 1) * math.exp(-(i / SR) * 25.0) for i in range(int(0.12 * SR))], 0.01, 0.7)
    return buf


def sfx_hit():
    return echo(mix(mix(silence(0.3), hit_low(90, 0.3, 0.9), 0),
                    noise_bed(0.12, lp=0.3, vol=0.25), 0), 0.05, 0.3, 1)


def sfx_hero_hurt():
    n = int(0.25 * SR)
    out = []
    for i in range(n):
        tt = i / SR
        f = 180.0 * (1.0 - 0.3 * tt / 0.25)
        out.append((math.sin(TAU * f * tt) * 0.7 + random.uniform(-1, 1) * 0.3)
                   * math.exp(-tt * 16.0))
    return out


def sfx_enemy_die():
    n = int(0.4 * SR)
    out = []
    for i in range(n):
        tt = i / SR
        f = 700.0 * (1.0 - 0.75 * tt / 0.4)
        ph = TAU * f * tt
        out.append((math.sin(ph) * 0.6 + random.uniform(-1, 1) * 0.25)
                   * math.exp(-tt * 7.0) * 0.8)
    return out


def coin2():
    buf = silence(0.4)
    mix(buf, bell(1245.0, 0.25, 0.7), 0.0)
    mix(buf, bell(1661.0, 0.3, 0.8), 0.07)
    return buf


def sfx_pickup():
    buf = silence(0.45)
    for k, f in enumerate([523.25, 659.25, 783.99]):
        mix(buf, pluck(f, 0.3, 0.6, 0.8), k * 0.07)
    return buf


def sfx_ui_click():
    return wood_click(1400.0, 0.05, 0.7)


def sfx_toast():
    buf = silence(0.3)
    mix(buf, bell(880.0, 0.2, 0.5), 0.0)
    mix(buf, bell(1174.7, 0.22, 0.6), 0.09)
    return buf


def sfx_alarm():
    buf = silence(1.6)
    for k in range(3):
        mix(buf, bell(523.25, 0.5, 0.9, strike=1.2), k * 0.5)
        mix(buf, bell(523.25 * 1.335, 0.4, 0.5), k * 0.5 + 0.12)
    return buf


def sfx_bell_day():
    buf = silence(1.4)
    for k in range(2):
        mix(buf, bell(659.25, 0.6, 0.8), k * 0.55)
    return buf


def sfx_build_done():
    buf = silence(0.7)
    for k, f in enumerate([392, 523, 659]):
        mix(buf, wood_click(f * 2, 0.08, 0.8), k * 0.14)
        mix(buf, pluck(f, 0.35, 0.5, 0.7), k * 0.14)
    return buf


def sfx_quest_done():
    buf = silence(0.8)
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        mix(buf, pluck(f, 0.4, 0.6, 0.8), k * 0.11)
    return buf


def sfx_wedding():
    buf = silence(1.2)
    mel = [(523.25, 0.0), (659.25, 0.15), (783.99, 0.3), (1046.5, 0.45),
           (783.99, 0.7), (1046.5, 0.85)]
    for f, at in mel:
        mix(buf, pluck(f, 0.5, 0.55, 0.75), at)
        mix(buf, wood_click(2200, 0.05, 0.4), at)
    return buf


def sfx_birth():
    buf = silence(0.7)
    mix(buf, flute(hz("E", 5), 0.4, 0.7), 0.0)
    mix(buf, flute(hz("G", 5), 0.4, 0.7), 0.22)
    return buf


def sfx_tree_fall_dark():
    """Тёмный вал: треск кроны, тяжёлый удар, гул почвы, шелест листвы."""
    buf = silence(2.0)
    for k, at in enumerate([0.0, 0.07, 0.13, 0.22]):
        g = 0.9 - k * 0.15
        mix(buf, [random.uniform(-1, 1) * math.exp(-(i / SR) * 45.0) for i in range(int(0.1 * SR))], at, g)
    mix(buf, hit_low(52, 0.8, 1.0), 0.62)
    mix(buf, noise_bed(1.2, lp=0.1, vol=0.3), 0.62)
    mix(buf, noise_bed(1.1, lp=0.3, vol=0.22), 0.75)
    return buf


def sfx_tree_fall():
    return sfx_tree_fall_dark()


def sfx_spell(school):
    buf = silence(0.55)
    if school == "wild":
        crack = [random.uniform(-1, 1) * math.exp(-(i / SR) * 9.0) for i in range(int(0.35 * SR))]
        mix(buf, crack, 0.0, 0.8)
        mix(buf, hit_low(120, 0.2, 0.6), 0.02)
    elif school == "light":
        for k, f in enumerate([1046.5, 1318.5, 1568.0]):
            mix(buf, bell(f, 0.4, 0.55), k * 0.06)
    elif school == "nature":
        for k in range(5):
            mix(buf, bird_chirp(), 0.02 + k * 0.07, 0.35)
    else:  # forbidden
        dark = [math.sin(TAU * 110 * (i / SR)) * 0.5
                + math.sin(TAU * 116 * (i / SR)) * 0.5
                + random.uniform(-1, 1) * 0.12 for i in range(int(0.5 * SR))]
        mix(buf, dark, 0.0, 0.8)
        mix(buf, flute(hz("A", 3), 0.4, 0.5, rough=True), 0.1)
    return buf


def sfx_chest():
    buf = silence(0.6)
    mix(buf, wood_click(500, 0.12, 0.9), 0.0)
    for k, f in enumerate([783.99, 1046.5]):
        mix(buf, bell(f, 0.3, 0.5), 0.15 + k * 0.08)
    return buf


def sfx_rune():
    buf = silence(0.8)
    for k, f in enumerate([440, 554.37, 659.25, 880]):
        mix(buf, flute(f, 0.35, 0.5, vib=6.5), k * 0.1)
    return buf


def sfx_boss_roar():
    n = int(1.1 * SR)
    out = []
    for i in range(n):
        tt = i / SR
        f = 90.0 * (1.0 + 0.5 * math.sin(tt * 5.0)) * (1.0 - 0.3 * tt / 1.1)
        ph = TAU * f * tt
        s = math.sin(ph) * 0.7 + math.sin(ph * 1.5) * 0.3 + random.uniform(-1, 1) * 0.35
        out.append(s * math.exp(-tt * 3.0) * 0.9)
    return echo(out, 0.2, 0.3, 2)


def sfx_fanfare():
    buf = silence(1.5)
    mel = [(523.25, 0.0), (659.25, 0.12), (783.99, 0.24), (1046.5, 0.36),
           (783.99, 0.6), (1046.5, 0.78), (1318.5, 1.0)]
    for f, at in mel:
        mix(buf, horn(f, 0.3, 0.8), at)
        mix(buf, pluck(f / 2, 0.4, 0.5, 0.4), at)
    return buf


# --- амбиент -----------------------------------------------------------------

def lowpass(buf, lp):
    out = [0.0] * len(buf)
    last = 0.0
    for i, v in enumerate(buf):
        last = last * (1.0 - lp) + v * lp
        out[i] = last
    return out


def raven_caw():
    """Далёкий ворон: 2-3 каркающих импульса с падением высоты."""
    out = silence(1.2)
    for k, at in enumerate([0.0, 0.32, 0.55]):
        n = int(0.14 * SR)
        caw = []
        for i in range(n):
            tt = i / SR
            f = (260.0 - 60.0 * tt / 0.14) * (1.0 - k * 0.06)
            ph = TAU * f * tt
            s = math.sin(ph) * 0.5 + math.sin(ph * 2.2) * 0.3 + math.sin(ph * 0.5) * 0.3
            s += random.uniform(-1, 1) * 0.25
            caw.append(s * env(n, a=0.015, d=n / SR * 0.6)[i])
        mix(out, caw, at, 0.9)
    return echo(out, 0.14, 0.3, 2)


def wind_gust():
    """Порыв ветра: нарастающе-спадающий шум (2.6 с) — не постоянный фон."""
    total = int(2.6 * SR)
    out = [0.0] * total
    last = 0.0
    for i in range(total):
        tt = i / total
        lp = 0.03 + 0.14 * math.sin(tt * math.pi)
        last = last * (1.0 - lp) + random.uniform(-1, 1) * lp
        out[i] = last * math.sin(tt * math.pi) ** 1.2
    return out


def amb_day():
    """День: почти тишина — один далёкий ворон. Только инструменты в музыке."""
    buf = silence(24.0)
    mix(buf, raven_caw(), random.uniform(9.0, 15.0), 0.25)
    return buf


def wolf_howl():
    """Далёкий вой волка: подъём и спад тона с вибрато."""
    n = int(1.9 * SR)
    out = []
    ph = 0.0
    for i in range(n):
        tt = i / n
        f = 300.0 + 190.0 * math.sin(tt * math.pi) + math.sin(tt * 26.0) * 9.0
        ph += TAU * f / SR
        s = math.sin(ph) * 0.7 + math.sin(ph * 2.0) * 0.15 + random.uniform(-1, 1) * 0.06
        e = math.sin(tt * math.pi) ** 0.7
        out.append(s * e * 0.8)
    return echo(lowpass(out, 0.25), 0.25, 0.3, 2)


def crack_branch():
    buf = silence(0.25)
    for at in [0.0, 0.09]:
        mix(buf, [random.uniform(-1, 1) * math.exp(-(i / SR) * 38.0) for i in range(int(0.08 * SR))], at, 0.7)
    return buf


def amb_night():
    """Тёмное фэнтези, ночь: почти тишина — далёкий волк, глухая сова,
    хруст ветки."""
    buf = silence(24.0)
    mix(buf, wolf_howl(), random.uniform(2.0, 6.0), 0.35)
    mix(buf, owl_hoot(), random.uniform(10.0, 16.0), 0.35)
    mix(buf, crack_branch(), random.uniform(4.0, 9.0), 0.5)
    mix(buf, crack_branch(), random.uniform(14.0, 20.0), 0.4)
    return buf


def amb_dungeon():
    buf = silence(24.0)
    mix(buf, drone(hz("A", 1), 24.0, 0.5, beat=1.2), 0)
    at = 0.8
    while at < 22.0:
        mix(buf, drip(), at, random.uniform(0.5, 1.0))
        mix(buf, drip(), at + 0.18, 0.3)   # эхо капли
        at += random.uniform(1.8, 3.5)
    return buf


def amb_raid():
    buf = silence(12.0)
    pat = [0.0, 0.75, 1.5, 2.25, 3.0, 3.5]
    bar = 3.0
    for t0 in [0.0, bar, bar * 2, bar * 3 - 0.001]:
        for i, at in enumerate(pat):
            if at < bar:
                mix(buf, hit_low(55 if i % 2 == 0 else 75, 0.3, 0.9), t0 + at)
        mix(buf, wood_click(900, 0.06, 0.5), t0 + 2.0)
        mix(buf, wood_click(900, 0.06, 0.5), t0 + 2.75)
    mix(buf, drone(hz("E", 2), 12.0, 0.3), 0)
    return echo(buf, 0.2, 0.2, 1)


def amb_storm():
    buf = noise_bed(24.0, lp=0.1, vol=0.3, lfo=0.08, lfo_depth=0.9)
    for at in [4.0, 11.5, 19.0]:
        n = int(1.2 * SR)
        rumble = [random.uniform(-1, 1) * math.exp(-(i / SR) * 2.5) * 0.8 for i in range(n)]
        mix(buf, rumble, at, 0.7)
    return buf


# --- музыкальные стемы -------------------------------------------------------

# Лады: славянская пентатоника (минорная) для быта, фригийская тьма для данжей.
PENTA = [("A", 3), ("C", 4), ("D", 4), ("E", 4), ("G", 4), ("A", 4), ("C", 5), ("E", 5)]
PENTA_LOW = [("A", 2), ("C", 3), ("D", 3), ("E", 3), ("G", 3), ("A", 3), ("C", 4), ("E", 4)]
DARK = [("A", 2), ("B", 2), ("C", 3), ("D", 3), ("E", 3), ("F", 3), ("A", 3), ("C", 4)]
MAGIC = [("D", 4), ("E", 4), ("F", 4), ("A", 4), ("B", 4), ("C", 5), ("D", 5), ("F", 5)]


def mus_city_day():
    pat = [
        "0 . 2 . 4 . 2 . 5 . 4 . 2 . 1 .",
        "0 . 2 . 4 . 5 . 6 . 4 . 2 . 1 .",
        "4 . 5 . 6 . 4 . 2 . 4 . 2 . 1 .",
        "0 . 2 . 1 . 0 . 5 . 4 . 2 . 0 .",
    ]
    render_track("mus_city_day", 92, 4, PENTA, pat,
                 lambda f, d: pluck(f, d, 0.55, 0.9), 0.72, 4,
                 drone_note=("A", 2), drone_vol=0.12)


def mus_city_layer():
    pat = [
        ". . 2 . . 4 . . 5 . . 4 . . 2 .",
        ". . 2 . . 5 . . 6 . . 4 . . 5 .",
        ". . 4 . . 6 . . 4 . . 2 . . 4 .",
        ". . 2 . . 1 . . 0 . . 2 . . 4 .",
    ]
    render_track("mus_city_layer", 92, 4, PENTA, pat,
                 lambda f, d: pluck(f, d * 0.7, 0.35, 0.7), 0.5, 4, echo_on=False)


def mus_city_night():
    pat = [
        "5 . . . . . 4 . . . . . 2 . . .",
        ". . . . 4 . . . . . 2 . . . . .",
        "5 . . . . . 6 . . . 4 . . . . .",
        ". . 2 . . . . . 1 . . . . . . .",
    ]
    render_track("mus_city_night", 62, 4, PENTA, pat,
                 lambda f, d: flute(f, d * 1.6, 0.8, breath=0.2, vib=4.5), 0.62, 4,
                 drone_note=("A", 2), drone_vol=0.14)


def mus_festival():
    fast = "0 0 2 0 4 0 2 0 5 0 4 0 2 0 4 0"
    pat = [fast, "0 0 2 0 4 0 5 0 6 0 5 0 4 0 2 0", fast,
           "6 0 5 0 4 0 5 0 2 0 4 0 2 0 1 0"]
    render_track("mus_festival", 132, 4, PENTA, pat,
                 lambda f, d: pluck(f, d * 0.5, 0.8, 0.85), 0.7, 4, echo_on=False)
    # ложки/трещотки поверх — отдельный файл-слой
    buf = silence(4 * 16 * (60.0 / 132) / 4)
    step = (60.0 / 132) / 4
    for bar in range(4):
        for s_i in range(16):
            if s_i % 4 == 2:
                mix(buf, wood_click(900, 0.05, 0.6), (bar * 16 + s_i) * step)
            if s_i % 8 == 6:
                mix(buf, wood_click(1400, 0.04, 0.5), (bar * 16 + s_i) * step)
    write_wav("mus_festival_layer", buf, 0.5)


def mus_world():
    pat = [
        "0 . . 2 . . 4 . . . 5 . . . 4 .",
        ". . 6 . . . 4 . . 2 . . . . . .",
        "5 . . 4 . . 2 . . . 1 . . . 0 .",
        ". . . . 2 . . . 4 . . . 2 . . .",
    ]
    render_track("mus_world", 78, 4, PENTA, pat,
                 lambda f, d: flute(f, d * 1.3, 0.75, breath=0.3, vib=4.0), 0.66, 4,
                 drone_note=("D", 3), drone_vol=0.12)
    # рожок-зов поверх — слой
    buf = silence(16 * (60.0 / 78) / 4 * 4)
    for bar, at in [(0, 0.5), (2, 4.5)]:
        mix(buf, horn(hz("D", 4), 0.5, 0.6), at)
        mix(buf, horn(hz("A", 4), 0.7, 0.65), at + 0.6)
    write_wav("mus_world_layer", buf, 0.45)


def mus_dungeon_base():
    pat = [
        "0 . . 2 . . 3 . . 4 . . 2 . . .",
        "0 . . 2 . . 3 . . 5 . . 4 . . .",
        "4 . . 5 . . 3 . . 2 . . 0 . . .",
        "0 . . 3 . . 2 . . 1 . . 0 . . .",
    ]
    render_track("mus_dungeon_base", 66, 4, MAGIC, pat,
                 lambda f, d: pluck(f, d * 1.4, 0.45, 0.85, decay=0.997), 0.62, 4,
                 drone_note=("D", 2), drone_vol=0.2)


def mus_dungeon_dark():
    pat = [
        "0 . . . 1 . . . 0 . . . 2 . . .",
        "0 . . . 1 . . . 3 . . . 2 . . .",
        "4 . . . 3 . . . 1 . . . 0 . . .",
        "0 . . . 2 . . . 1 . . . 0 . . .",
    ]
    render_track("mus_dungeon_dark", 58, 4, DARK, pat,
                 lambda f, d: flute(f, d * 1.8, 0.8, breath=0.45, vib=3.5, rough=True),
                 0.62, 3, drone_note=("A", 1), drone_vol=0.26)
    # арфа-псалтерий поверх (магия данжа) — слой
    render_track("mus_dungeon_magic", 58, 4, MAGIC,
                 [". . 3 . . 4 . . 5 . . 3 . . 1 .",
                  ". . 3 . . 5 . . 4 . . 2 . . 3 ."],
                 lambda f, d: pluck(f, d * 1.2, 0.5, 0.6, decay=0.997), 0.4, 4)


def mus_boss_layer():
    step = 60.0 / 76 / 4
    buf = silence(4 * 16 * step)
    for bar in range(4):
        for s_i, hitv in [(0, 1.0), (6, 0.7), (8, 0.9), (14, 0.7)]:
            mix(buf, hit_low(60 if s_i % 8 == 0 else 78, 0.3, hitv), (bar * 16 + s_i) * step)
        if bar % 2 == 1:
            mix(buf, cymbal(0.6, 0.8), bar * 16 * step + 12 * step)
    mix(buf, drone(hz("A", 1), 4 * 16 * step, 0.4), 0)
    write_wav("mus_boss_layer", buf, 0.8)


def mus_menu():
    pat = [
        "0 . . 2 . . 4 . . . 2 . . 1 . .",
        "0 . . 2 . . 4 . . . 5 . . . . .",
        "6 . . 5 . . 4 . . . 2 . . . . .",
        "4 . . 2 . . 1 . . . 0 . . . . .",
    ]
    render_track("mus_menu", 56, 4, PENTA, pat,
                 lambda f, d: pluck(f, d * 1.8, 0.5, 0.8, decay=0.9965), 0.7, 4,
                 drone_note=("A", 2), drone_vol=0.14)


def mus_victory():
    buf = silence(5.0)
    mel = [(523.25, 0.0, 0.3), (659.25, 0.18, 0.3), (783.99, 0.36, 0.3),
           (1046.5, 0.54, 0.5), (880.0, 0.9, 0.3), (1046.5, 1.1, 0.3),
           (1318.5, 1.35, 0.8), (1568.0, 1.8, 1.4)]
    for f, at, dur in mel:
        mix(buf, pluck(f, dur, 0.6, 0.85), at)
        mix(buf, bell(f * 2, dur * 0.8, 0.3), at)
    for at in [0.0, 0.36, 0.54, 1.35, 1.8]:
        mix(buf, wood_click(1600, 0.06, 0.5), at)
    write_wav("mus_victory", echo(buf, 0.18, 0.25, 2), 0.85, )


def main():
    out_sfx = os.path.join(ROOT, "sfx")
    out_amb = os.path.join(ROOT, "amb")
    out_mus = os.path.join(ROOT, "music")
    for d in (out_sfx, out_amb, out_mus):
        os.makedirs(d, exist_ok=True)

    def wp(name, buf, vol=0.8):
        write_wav(os.path.join(ROOT, name), buf, vol)

    print("[SFX]")
    wp("sfx/hit.wav", sfx_hit(), 0.85)
    wp("sfx/hero_hurt.wav", sfx_hero_hurt(), 0.8)
    wp("sfx/enemy_die.wav", sfx_enemy_die(), 0.75)
    wp("sfx/coin.wav", coin2(), 0.8)
    wp("sfx/pickup.wav", sfx_pickup(), 0.8)
    wp("sfx/ui_click.wav", sfx_ui_click(), 0.6)
    wp("sfx/toast.wav", sfx_toast(), 0.6)
    wp("sfx/alarm.wav", sfx_alarm(), 0.9)
    wp("sfx/bell_day.wav", sfx_bell_day(), 0.7)
    wp("sfx/build_done.wav", sfx_build_done(), 0.8)
    wp("sfx/quest_done.wav", sfx_quest_done(), 0.8)
    wp("sfx/wedding.wav", sfx_wedding(), 0.75)
    wp("sfx/birth.wav", sfx_birth(), 0.7)
    wp("sfx/tree_fall.wav", sfx_tree_fall(), 0.85)
    wp("sfx/spell_wild.wav", sfx_spell("wild"), 0.8)
    wp("sfx/spell_light.wav", sfx_spell("light"), 0.8)
    wp("sfx/spell_nature.wav", sfx_spell("nature"), 0.8)
    wp("sfx/spell_forbidden.wav", sfx_spell("forbidden"), 0.8)
    wp("sfx/chest.wav", sfx_chest(), 0.8)
    wp("sfx/rune.wav", sfx_rune(), 0.8)
    wp("sfx/boss_roar.wav", sfx_boss_roar(), 0.9)
    wp("sfx/fanfare.wav", sfx_fanfare(), 0.85)
    wp("sfx/step_grass.wav", step(0.09, 0.18, 0.55), 0.55)
    wp("sfx/step_road.wav", step(0.08, 0.28, 0.6, thud=0.5, thud_f=110.0), 0.6)
    wp("sfx/step_stone.wav", step(0.07, 0.35, 0.6, thud=0.4, thud_f=200.0), 0.6)
    wp("sfx/step_water.wav", echo([random.uniform(-1, 1) * math.exp(-(i / SR) * 18.0) for i in range(int(0.16 * SR))], 0.05, 0.4, 1), 0.5)
    wp("sfx/chop.wav", sfx_chop(), 0.9)
    wp("sfx/hammer.wav", sfx_hammer(), 0.8)
    wp("sfx/mine.wav", sfx_mine(), 0.85)
    wp("sfx/swing.wav", swing(), 0.6)

    print("[AMB]")
    wp("amb/amb_day.wav", amb_day(), 0.7)
    wp("amb/amb_night.wav", amb_night(), 0.7)
    wp("amb/amb_dungeon.wav", amb_dungeon(), 0.7)
    wp("amb/amb_raid.wav", amb_raid(), 0.8)
    wp("music/mus_raid_drums.wav", amb_raid(), 0.8)
    wp("amb/amb_storm.wav", amb_storm(), 0.7)

    print("[MUSIC]")
    mroot = os.path.join(ROOT, "music")
    render_track(os.path.join(mroot, "mus_city_day.wav"), 92, 4, PENTA,
                 ["0 . 2 . 4 . 2 . 5 . 4 . 2 . 1 .",
                  "0 . 2 . 4 . 5 . 6 . 4 . 2 . 1 .",
                  "4 . 5 . 6 . 4 . 2 . 4 . 2 . 1 .",
                  "0 . 2 . 1 . 0 . 5 . 4 . 2 . 0 ."],
                 lambda f, d: pluck(f, d, 0.55, 0.9), 0.72, 4,
                 drone_note=("A", 2), drone_vol=0.12)
    render_track(os.path.join(mroot, "mus_city_layer.wav"), 92, 4, PENTA,
                 [". . 2 . . 4 . . 5 . . 4 . . 2 .",
                  ". . 2 . . 5 . . 6 . . 4 . . 5 .",
                  ". . 4 . . 6 . . 4 . . 2 . . 4 .",
                  ". . 2 . . 1 . . 0 . . 2 . . 4 ."],
                 lambda f, d: pluck(f, d * 0.7, 0.35, 0.7), 0.5, 4, echo_on=False)
    render_track(os.path.join(mroot, "mus_city_night.wav"), 62, 4, PENTA,
                 ["5 . . . . . 4 . . . . . 2 . . .",
                  ". . . . 4 . . . . . 2 . . . . .",
                  "5 . . . . . 6 . . . 4 . . . . .",
                  ". . 2 . . . . . 1 . . . . . . ."],
                 lambda f, d: flute(f, d * 1.6, 0.8, breath=0.2, vib=4.5), 0.62, 4,
                 drone_note=("A", 2), drone_vol=0.14)
    render_track(os.path.join(mroot, "mus_festival.wav"), 132, 4, PENTA,
                 ["0 0 2 0 4 0 2 0 5 0 4 0 2 0 4 0",
                  "0 0 2 0 4 0 5 0 6 0 5 0 4 0 2 0",
                  "0 0 2 0 4 0 2 0 5 0 4 0 2 0 4 0",
                  "6 0 5 0 4 0 5 0 2 0 4 0 2 0 1 0"],
                 lambda f, d: pluck(f, d * 0.5, 0.8, 0.85), 0.7, 4, echo_on=False)
    step_f = (60.0 / 132) / 4
    fbuf = silence(4 * 16 * step_f)
    for bar in range(4):
        for s_i in range(16):
            if s_i % 4 == 2:
                mix(fbuf, wood_click(900, 0.05, 0.6), (bar * 16 + s_i) * step_f)
            if s_i % 8 == 6:
                mix(fbuf, wood_click(1400, 0.04, 0.5), (bar * 16 + s_i) * step_f)
    write_wav(os.path.join(mroot, "mus_festival_layer.wav"), fbuf, 0.5)
    render_track(os.path.join(mroot, "mus_world.wav"), 78, 4, PENTA,
                 ["0 . . 2 . . 4 . . . 5 . . . 4 .",
                  ". . 6 . . . 4 . . 2 . . . . . .",
                  "5 . . 4 . . 2 . . . 1 . . . 0 .",
                  ". . . . 2 . . . 4 . . . 2 . . ."],
                 lambda f, d: flute(f, d * 1.3, 0.75, breath=0.3, vib=4.0), 0.66, 4,
                 drone_note=("D", 3), drone_vol=0.12)
    wbuf = silence(16 * (60.0 / 78) / 4 * 4)
    for at in [0.5, 4.5]:
        mix(wbuf, horn(hz("D", 4), 0.5, 0.6), at)
        mix(wbuf, horn(hz("A", 4), 0.7, 0.65), at + 0.6)
    write_wav(os.path.join(mroot, "mus_world_layer.wav"), wbuf, 0.45)
    render_track(os.path.join(mroot, "mus_dungeon_base.wav"), 66, 4, MAGIC,
                 ["0 . . 2 . . 3 . . 4 . . 2 . . .",
                  "0 . . 2 . . 3 . . 5 . . 4 . . .",
                  "4 . . 5 . . 3 . . 2 . . 0 . . .",
                  "0 . . 3 . . 2 . . 1 . . 0 . . ."],
                 lambda f, d: pluck(f, d * 1.4, 0.45, 0.85, decay=0.997), 0.62, 4,
                 drone_note=("D", 2), drone_vol=0.2)
    render_track(os.path.join(mroot, "mus_dungeon_dark.wav"), 58, 4, DARK,
                 ["0 . . . 1 . . . 0 . . . 2 . . .",
                  "0 . . . 1 . . . 3 . . . 2 . . .",
                  "4 . . . 3 . . . 1 . . . 0 . . .",
                  "0 . . . 2 . . . 1 . . . 0 . . ."],
                 lambda f, d: flute(f, d * 1.8, 0.8, breath=0.45, vib=3.5, rough=True),
                 0.62, 3, drone_note=("A", 1), drone_vol=0.26)
    render_track(os.path.join(mroot, "mus_dungeon_magic.wav"), 58, 4, MAGIC,
                 [". . 3 . . 4 . . 5 . . 3 . . 1 .",
                  ". . 3 . . 5 . . 4 . . 2 . . 3 .",
                  ". . 4 . . 5 . . 3 . . 1 . . . .",
                  ". . 3 . . 4 . . 2 . . 1 . . . ."],
                 lambda f, d: pluck(f, d * 1.2, 0.5, 0.6, decay=0.997), 0.4, 4)
    step_b = 60.0 / 76 / 4
    bbuf = silence(4 * 16 * step_b)
    for bar in range(4):
        for s_i, hitv in [(0, 1.0), (6, 0.7), (8, 0.9), (14, 0.7)]:
            mix(bbuf, hit_low(60 if s_i % 8 == 0 else 78, 0.3, hitv), (bar * 16 + s_i) * step_b)
        if bar % 2 == 1:
            mix(bbuf, cymbal(0.6, 0.8), bar * 16 * step_b + 12 * step_b)
    mix(bbuf, drone(hz("A", 1), 4 * 16 * step_b, 0.4), 0)
    write_wav(os.path.join(mroot, "mus_boss_layer.wav"), bbuf, 0.8)
    render_track(os.path.join(mroot, "mus_menu.wav"), 56, 4, PENTA,
                 ["0 . . 2 . . 4 . . . 2 . . 1 . .",
                  "0 . . 2 . . 4 . . . 5 . . . . .",
                  "6 . . 5 . . 4 . . . 2 . . . . .",
                  "4 . . 2 . . 1 . . . 0 . . . . ."],
                 lambda f, d: pluck(f, d * 1.8, 0.5, 0.8, decay=0.9965), 0.7, 4,
                 drone_note=("A", 2), drone_vol=0.14)
    vbuf = silence(5.0)
    mel = [(523.25, 0.0, 0.3), (659.25, 0.18, 0.3), (783.99, 0.36, 0.3),
           (1046.5, 0.54, 0.5), (880.0, 0.9, 0.3), (1046.5, 1.1, 0.3),
           (1318.5, 1.35, 0.8), (1568.0, 1.8, 1.4)]
    for f, at, dur in mel:
        mix(vbuf, pluck(f, dur, 0.6, 0.85), at)
        mix(vbuf, bell(f * 2, dur * 0.8, 0.3), at)
    for at in [0.0, 0.36, 0.54, 1.35, 1.8]:
        mix(vbuf, wood_click(1600, 0.06, 0.5), at)
    write_wav(os.path.join(mroot, "mus_victory.wav"), echo(vbuf, 0.18, 0.25, 2), 0.85)
    print("Готово: sfx 22, amb 5, music 11")


if __name__ == "__main__":
    main()
