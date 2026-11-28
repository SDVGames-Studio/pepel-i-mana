# -*- coding: utf-8 -*-
"""SFX: смешанные суммы разной длины -> отдельные события одного времени
(seq складывает в буфере сам). Запуск: python -I tools/patch_sfx_mix.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "tools", "make_sfx_v3.py")
s = io.open(P, encoding="utf-8", newline="").read()

REPS = [
    ('GEN["hit"] = lambda: seq([(0, mem(1.0) + crack(0.5, 3500, 0.05))], 0.4)',
     'GEN["hit"] = lambda: seq([(0, mem(1.0)), (0, crack(0.5, 3500, 0.05))], 0.4)'),
    ('GEN["hero_hurt"] = lambda: seq([(0, mem(0.9, pitch=70, drop=18, dur=0.35)\n'
     '                                 + crack(0.4, 1800, 0.08))], 0.45)',
     'GEN["hero_hurt"] = lambda: seq([(0, mem(0.9, pitch=70, drop=18, dur=0.35)),\n'
     '        (0, crack(0.4, 1800, 0.08))], 0.45)'),
    ('GEN["alarm"] = lambda: seq([(t, ks(midi2f(69), 0.2, 0.7, damp=0.9935, lp=6000, pick=0.15)\n'
     '                             + mem(0.4, pitch=80, drop=20, dur=0.18))\n'
     '        for t in (0.0, 0.26, 0.52)], 0.9)',
     'GEN["alarm"] = lambda: seq([x\n'
     '        for t in (0.0, 0.26, 0.52) for x in (\n'
     '            (t, ks(midi2f(69), 0.2, 0.7, damp=0.9935, lp=6000, pick=0.15)),\n'
     '            (t, mem(0.4, pitch=80, drop=20, dur=0.2)))], 0.9)'),
    ('GEN["build_done"] = lambda: seq([(0, ks(midi2f(57), 0.2, 0.8, damp=0.986, lp=1300, pick=0.3)\n'
     '                                  + crack(0.5, 2000, 0.05)),\n'
     '        (0.13, ks(midi2f(57), 0.25, 0.9, damp=0.986, lp=1300, pick=0.3)\n'
     '         + crack(0.6, 2200, 0.05))], 0.55)',
     'GEN["build_done"] = lambda: seq([(0, ks(midi2f(57), 0.2, 0.8, damp=0.986, lp=1300, pick=0.3)),\n'
     '        (0, crack(0.5, 2000, 0.05)),\n'
     '        (0.13, ks(midi2f(57), 0.25, 0.9, damp=0.986, lp=1300, pick=0.3)),\n'
     '        (0.13, crack(0.6, 2200, 0.05))], 0.55)'),
    ('GEN["ui_click"] = lambda: seq([(0, crack(0.35, 4500, 0.02)\n'
     '                                + ks(midi2f(91), 0.05, 0.3, damp=0.99, lp=6000))], 0.1)',
     'GEN["ui_click"] = lambda: seq([(0, crack(0.35, 4500, 0.02)),\n'
     '        (0, ks(midi2f(91), 0.05, 0.3, damp=0.99, lp=6000))], 0.1)'),
    ('GEN["tree_fall"] = lambda: seq([(0, crack(0.7, 2200, 0.07)),\n'
     '        (0.15, crack(0.8, 1800, 0.09)),\n'
     '        (0.25, sweep(0.9, 1500, 150, 0.8)),\n'
     '        (0.95, mem(1.0, pitch=55, drop=16, dur=0.5) + crack(0.8, 1200, 0.12))], 1.5)',
     'GEN["tree_fall"] = lambda: seq([(0, crack(0.7, 2200, 0.07)),\n'
     '        (0.15, crack(0.8, 1800, 0.09)),\n'
     '        (0.25, sweep(0.9, 1500, 150, 0.8)),\n'
     '        (0.95, mem(1.0, pitch=55, drop=16, dur=0.5)),\n'
     '        (0.95, crack(0.8, 1200, 0.12))], 1.5)'),
    ('    GEN["chop" if i == 0 else "chop_%d" % (i + 1)] = (lambda f0=f0, v0=v0: seq(\n'
     '        [(0, ks(midi2f(2), 0.22, v0, damp=0.985, lp=1400, pick=0.3)\n'
     '           + crack(0.6, 2800, 0.04))], 0.3))',
     '    GEN["chop" if i == 0 else "chop_%d" % (i + 1)] = (lambda f0=f0, v0=v0: seq(\n'
     '        [(0, ks(midi2f(2), 0.22, v0, damp=0.985, lp=1400, pick=0.3)),\n'
     '         (0, crack(0.6, 2800, 0.04))], 0.3))'),
    ('    GEN["hammer" if i == 0 else "hammer_%d" % (i + 1)] = (lambda f0=f0, v0=v0: seq(\n'
     '        [(0, crack(0.55, 5000, 0.03)\n'
     '           + ks(midi2f(2) if False else f0 / 10.0, 0.16, v0, damp=0.9945, lp=7000, pick=0.15))], 0.25))',
     '    GEN["hammer" if i == 0 else "hammer_%d" % (i + 1)] = (lambda f0=f0, v0=v0: seq(\n'
     '        [(0, crack(0.55, 5000, 0.03)),\n'
     '         (0, ks(f0 / 10.0, 0.16, v0, damp=0.9945, lp=7000, pick=0.15))], 0.25))'),
    ('    GEN["mine" if i == 0 else "mine_%d" % (i + 1)] = (lambda v0=v0: seq(\n'
     '        [(0, crack(v0, 3800, 0.05) + crack(v0 * 0.6, 1600, 0.1)),\n'
     '         (0.07, crack(v0 * 0.5, 2500, 0.06))], 0.3))',
     '    GEN["mine" if i == 0 else "mine_%d" % (i + 1)] = (lambda v0=v0: seq(\n'
     '        [(0, crack(v0, 3800, 0.05)),\n'
     '         (0, crack(v0 * 0.6, 1600, 0.1)),\n'
     '         (0.07, crack(v0 * 0.5, 2500, 0.06))], 0.3))'),
    ('GEN["swing"] = lambda: seq([(0, sweep(0.18, 1100, 350, 0.55) + crack(0.15, 2400, 0.03))], 0.28)',
     'GEN["swing"] = lambda: seq([(0, sweep(0.18, 1100, 350, 0.55)),\n'
     '        (0, crack(0.15, 2400, 0.03))], 0.28)'),
    ('GEN["spell_wild"] = lambda: seq([(0, sweep(0.35, 400, 2400, 0.5)),\n'
     '        (0.1, ks(midi2f(64), 0.5, 0.5, damp=0.995, lp=4000, pick=0.35))], 0.7)',
     'GEN["spell_wild"] = lambda: seq([(0, sweep(0.35, 400, 2400, 0.5)),\n'
     '        (0.1, ks(midi2f(64), 0.5, 0.5, damp=0.995, lp=4000, pick=0.35))], 0.7)'),
]

for old, new in REPS:
    old_nl = old.replace("\n", nl) if "\r\n" in s else old
    new_nl = new.replace("\n", nl) if "\r\n" in s else new
    assert s.count(old_nl) == 1, "count=%d: %r" % (s.count(old_nl), old[:60])
    s = s.replace(old_nl, new_nl)

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ok: %d лямбд разнесены по событиям" % len(REPS))
