# -*- coding: utf-8 -*-
"""v3.0.9 «две гусли» (фидбек: боевая и зима звучат одинаково): тембры
разведены по физике щипка — зима щиплет ЗА ГРИФОМ (pick 0.45: круглый
тёмный тон, долгое кольцо, низкий регистр, сердце = низкое било вместо
мембраны), бой щиплет У ПОДСТАВКИ (pick 0.12: нос-резкий ударный тон,
короткий спад). Учитывай: у настоящих струнных точка щипка меняет тембр.
Запуск: python -I tools/patch_timbres_split.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "tools", "make_music_v3.py")
s = io.open(P, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"


def rep(old, new):
    global s
    old_nl = old.replace("\n", nl)
    new_nl = new.replace("\n", nl)
    assert s.count(old_nl) == 1, "count=%d: %r" % (s.count(old_nl), old[:70])
    s = s.replace(old_nl, new_nl)


# ks_bass: pick параметром (бой щиплет у подставки)
rep("def ks_bass(f, dur, vel=1.0, damp=0.9993):",
    "def ks_bass(f, dur, vel=1.0, damp=0.9993, pick=0.42):")
rep("    return vel * fft_lp(ks_pluck(f, dur, 1.0, damp=damp, lp=1400, pick=0.42), 520)",
    "    return vel * fft_lp(ks_pluck(f, dur, 1.0, damp=damp, lp=1400, pick=pick), 520)")

# --- зима: тёмная гусля (за грифом, длинное кольцо) ---
rep("            ev.append((t0 + 0.09 * j,\n"
    "                       ks_pluck(midi2f(m), BAR * 1.6 - 0.09 * j, 0.3,\n"
    "                                damp=0.9975, lp=4200),\n"
    "                       -0.35 + 0.35 * j))",
    "            ev.append((t0 + 0.09 * j,\n"
    "                       ks_pluck(midi2f(m), BAR * 1.6 - 0.09 * j, 0.3,\n"
    "                                damp=0.9985, lp=2400, pick=0.45),\n"
    "                       -0.35 + 0.35 * j))")
rep("        sig = ks_pluck(midi2f(SCALE[ni]), dur, 0.3, damp=0.997, lp=7000)",
    "        sig = ks_pluck(midi2f(SCALE[ni]), dur, 0.3, damp=0.997, lp=5000, pick=0.45)")
# сердце зимы — низкое било, не мембрана (мембрана остаётся только в бою)
rep("        if (cycle * len(PROG) + i) % 2 == 0:\n"
    "            ev.append((t0, thump2(0.32), 0.0))",
    "        if (cycle * len(PROG) + i) % 2 == 0:\n"
    "            ev.append((t0, bell2(midi2f(40), 4.0, 0.22), 0.0))")

# --- бой: щипок у подставки (нос-резкий, ударный) ---
rep("        ev.append((t0 + 0.02 * j,\n"
    "                   ks_pluck(midi2f(m + 12), 0.5 - 0.02 * j, 0.5,\n"
    "                            damp=0.9935, lp=6000),\n"
    "                   -0.3 + 0.3 * j))",
    "        ev.append((t0 + 0.02 * j,\n"
    "                   ks_pluck(midi2f(m + 12), 0.5 - 0.02 * j, 0.5,\n"
    "                            damp=0.9935, lp=6000, pick=0.12),\n"
    "                   -0.3 + 0.3 * j))")
rep("        ev.append((t0 + BAR * 0.375,\n"
    "                   ks_pluck(midi2f(chord[2] + 24), 0.35, 0.4, damp=0.9935, lp=6500),\n"
    "                   0.2))",
    "        ev.append((t0 + BAR * 0.375,\n"
    "                   ks_pluck(midi2f(chord[2] + 24), 0.35, 0.4, damp=0.9935, lp=6500, pick=0.12),\n"
    "                   0.2))")
rep("        sig = ks_pluck(midi2f(OST[k5]), 0.45, 0.34, damp=0.994, lp=6500)",
    "        sig = ks_pluck(midi2f(OST[k5]), 0.45, 0.34, damp=0.994, lp=6500, pick=0.12)")
rep("            ev.append((t0 + k6 * BAR / 4.0 + BAR / 16.0,\n"
    "                       ks_pluck(midi2f(m + 12), 0.45, 0.36, damp=0.994, lp=6500),\n"
    "                       -0.3 * np.sin(bar_i + k6)))",
    "            ev.append((t0 + k6 * BAR / 4.0 + BAR / 16.0,\n"
    "                       ks_pluck(midi2f(m + 12), 0.45, 0.36, damp=0.994, lp=6500, pick=0.12),\n"
    "                       -0.3 * np.sin(bar_i + k6)))")
rep("            ev.append((t0 + BAR * 0.5,\n"
    "                       ks_pluck(midi2f(HIGH[(bar_i // 2) % len(HIGH)] + 12), 0.5, 0.22,\n"
    "                                damp=0.994, lp=7000), 0.4))",
    "            ev.append((t0 + BAR * 0.5,\n"
    "                       ks_pluck(midi2f(HIGH[(bar_i // 2) % len(HIGH)] + 12), 0.5, 0.22,\n"
    "                                damp=0.994, lp=7000, pick=0.12), 0.4))")
# боевой бас — у подставки
rep("    ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.05, 0.7, damp=0.9975), 0.0))",
    "    ev.append((t0, ks_bass(midi2f(BASS[root]), BAR * 1.05, 0.7, damp=0.9975, pick=0.15), 0.0))")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ok: зима = тёмная гусля за грифом, бой = резкий щипок у подставки")
