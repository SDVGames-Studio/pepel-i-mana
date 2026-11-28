# -*- coding: utf-8 -*-
"""v3.0.5 ночной FPS: PointLight2D съедали ~50 FPS (замер diag_fps_all:
ночь 59 -> 110 с выключенным светом). Меньше источников (5+9 -> 3+6),
меньше радиусы (костёр 2.6->1.7, дома 1.6->1.05, стайки 1.9/1.25->1.5/1.0),
свет выключается вне экрана (кулинг по видимой области).
Запуск: python -I tools/patch_night_fps.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "scripts", "city_ambience.gd")
s = io.open(P, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"


def rep(old, new):
    global s
    old_nl = old.replace("\n", nl)
    new_nl = new.replace("\n", nl)
    assert s.count(old_nl) == 1, "count=%d: %r" % (s.count(old_nl), old[:70])
    s = s.replace(old_nl, new_nl)


rep("const LIGHT_COUNT := 5        # кочующие огни стай (v1.80.1: 8→5, FPS)",
    "const LIGHT_COUNT := 3        # v3.0.5: 5→3 — ночные PointLight2D съедали ~50 FPS\n"
    "                              # (замер diag_fps_all: ночь 59 -> 110 без света)")
rep("const STREET_LIGHT_MAX := 8    # v2.6.5: откат 14 — 14 PointLight2D роняли ночной FPS   # фонари у домов (v1.80.1: 10→8, FPS)",
    "const STREET_LIGHT_MAX := 6    # v3.0.5: 8→6 (ночь 59->110 без света; радиусы срезаны)")
rep("\t\t\tl2.texture_scale = 2.6", "\t\t\tl2.texture_scale = 1.7")
rep("\t\t\tl2.texture_scale = 1.6", "\t\t\tl2.texture_scale = 1.05")
rep("\t\t\tl.texture_scale = 1.9", "\t\t\tl.texture_scale = 1.5")
rep("\t\t\tl.texture_scale = 1.25", "\t\t\tl.texture_scale = 1.0")

# кулинг: кочующие (строка l.enabled = true в цикле _lights)
rep("\t\tl.enabled = true\n", "\t\tl.enabled = _on_screen(l.position)\n")

# кулинг: уличные (два вхождения l3.enabled = true с их energy-строками)
rep("\t\t\tl3.enabled = true\n"
    '\t\t\tl3.energy = night * (0.85 + 0.15 * sin(_time * 7.0))   # пламя живое',
    "\t\t\tl3.enabled = _on_screen(l3.position)\n"
    '\t\t\tl3.energy = night * (0.85 + 0.15 * sin(_time * 7.0))   # пламя живое')
rep("\t\t\tl3.enabled = true\n"
    '\t\t\tl3.energy = lights_night * (0.6 + 0.08 * sin(_time * 2.3 + _street[i - 1]["fl"]))',
    "\t\t\tl3.enabled = _on_screen(l3.position)\n"
    '\t\t\tl3.energy = lights_night * (0.6 + 0.08 * sin(_time * 2.3 + _street[i - 1]["fl"]))')

# хелпер видимости
rep("## Детерминированный «случайный» для setup (важен стабильный вид, не честность).",
    "## Источник на экране? Вне кадра PointLight2D не рендерится вовсе —\n"
    "## ночью при панораме это половина стоимости света (v3.0.5, diag_fps_all).\n"
    "func _on_screen(pos: Vector2) -> bool:\n"
    "\tvar xf := get_viewport_transform()\n"
    "\tvar vis := (xf.affine_inverse() * get_viewport_rect()).grow(map.ts * 3.0)\n"
    "\treturn vis.has_point(pos)\n"
    "\n"
    "\n"
    "## Детерминированный «случайный» для setup (важен стабильный вид, не честность).")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ok: ночной свет ужат — 10 источников, малые пятна, кулинг вне экрана")
