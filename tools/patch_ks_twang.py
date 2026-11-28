# -*- coding: utf-8 -*-
"""v3.0.8 «трям трям»: у KS-струны возбуждение имело обрыв на обороте
буфера — каждый период щёлкал (на низких = металлический трям), и ком
позиции щипка был слишком резким (банджо-оттенок). Фикс: сшивка хвоста
возбуждения с началом (безступенчатый оборот) + мягче ком и ярче срез.
Запуск: python -I tools/patch_ks_twang.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "tools", "make_music_v3.py")
s = io.open(P, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"

old = (
    "    N = max(2, int(SR / f))\n" +
    "    exc = rng.standard_normal(N)\n" +
    "    exc = fft_lp(exc, min(f * 9.0, lp))\n" +
    "    d = max(1, int(N * pick))\n" +
    "    exc[d:] -= exc[:-d] * 0.85\n" +
    "    exc[:d] *= 0.2\n"
)
new = (
    "    N = max(2, int(SR / f))\n" +
    "    exc = rng.standard_normal(N)\n" +
    "    exc = fft_lp(exc, min(f * 5.0, lp))\n" +
    "    d = max(1, int(N * pick))\n" +
    "    exc[d:] -= exc[:-d] * 0.45\n" +
    "    exc[:d] *= 0.45\n" +
    "    # v3.0.8 «трям»: сшивка хвоста возбуждения с началом — без\n" +
    "    # безступенчатого оборота буфера нет периодического щелчка\n" +
    "    m = min(N // 8, 24)\n" +
    "    exc[N - m:] = np.linspace(exc[N - m], exc[0], m)\n"
)
assert s.count(old.replace("\n", nl)) == 1, s.count(old.replace("\n", nl))
io.open(P, "w", encoding="utf-8", newline="").write(
    s.replace(old.replace("\n", nl), new.replace("\n", nl)))
print("ok: KS без тряма — сшитый оборот, мягкий щипок")
