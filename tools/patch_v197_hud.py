#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v1.97 срез 1: сворачивание ресурсов и панели построек (HUD-компакт).
import io
import sys


def patch(path, old, new):
    src = io.open(path, encoding='utf-8').read()
    if old not in src:
        print('!! НЕ НАЙДЕНО в %s: %r' % (path, old[:70]))
        sys.exit(1)
    io.open(path, 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))


# ---------- vars ----------
patch('scripts/city_hud_base.gd',
      'var _residents_text: RichTextLabel',
      'var _residents_text: RichTextLabel\n'
      'var _hud_res_fold: Button = null   # v1.97: свернуть ресурсы в полоску\n'
      'var _hud_bld_fold: Button = null   # v1.97: свернуть панель построек')

# ---------- ресурсы: стрелка сворачивает всё, кроме себя и дня ----------
patch('scripts/city_hud_build.gd',
      '\t# v1.53: панель ресурсов — сетка ИКОНОК 6×2 (число рядом с картинкой,\n'
      '\t# название ресурса — всплывающая подсказка)\n'
      '\tvar res_grid := GridContainer.new()',
      '\t# v1.97: сворачивание панели поселения — остаётся день + кнопка\n'
      '\tvar res_fold := Button.new()\n'
      '\tres_fold.text = "▼"\n'
      '\tres_fold.custom_minimum_size = Vector2(34, 28)\n'
      '\tres_fold.focus_mode = Control.FOCUS_NONE\n'
      '\tres_fold.add_theme_font_size_override("font_size", 15)\n'
      '\ttl_box.add_child(res_fold)\n'
      '\t_hud_res_fold = res_fold\n'
      '\tres_fold.pressed.connect(func() -> void:\n'
      '\t\tvar open := res_fold.text == "▼"\n'
      '\t\tres_fold.text = "▲" if open else "▼"\n'
      '\t\tfor c in tl_box.get_children():\n'
      '\t\t\tif c != res_fold:\n'
      '\t\t\t\tc.visible = not open)\n'
      '\t# v1.53: панель ресурсов — сетка ИКОНОК 6×2 (число рядом с картинкой,\n'
      '\t# название ресурса — всплывающая подсказка)\n'
      '\tvar res_grid := GridContainer.new()')

# ---------- постройки: кнопка «Постройки ▲/▼» ПЕРЕД панелью (в bottom) ----------
patch('scripts/city_hud_build.gd',
      '\tvar panel := PanelContainer.new()\n'
      '\tpanel.add_theme_stylebox_override("panel", _panel_style())\n'
      '\tpanel.visible = not guest   # гость не строит: панели инструментов нет (№120)\n'
      '\tbottom.add_child(panel)\n'
      '\tvar row := HBoxContainer.new()\n'
      '\trow.add_theme_constant_override("separation", 8)\n'
      '\tpanel.add_child(row)',
      '\t# v1.97: панель построек сворачивается кнопкой рядом (кнопка вне\n'
      '\t# панели — иначе прячет саму себя)\n'
      '\tvar bld_fold := Button.new()\n'
      '\tbld_fold.text = "▲"\n'
      '\tbld_fold.custom_minimum_size = Vector2(120, 40)\n'
      '\tbld_fold.focus_mode = Control.FOCUS_NONE\n'
      '\tbld_fold.add_theme_font_size_override("font_size", 15)\n'
      '\tbld_fold.visible = not guest\n'
      '\tbottom.add_child(bld_fold)\n'
      '\t_hud_bld_fold = bld_fold\n'
      '\tvar panel := PanelContainer.new()\n'
      '\tpanel.add_theme_stylebox_override("panel", _panel_style())\n'
      '\tpanel.visible = not guest   # гость не строит: панели инструментов нет (№120)\n'
      '\tbottom.add_child(panel)\n'
      '\tbld_fold.pressed.connect(func() -> void:\n'
      '\t\tpanel.visible = not panel.visible)\n'
      '\tvar row := HBoxContainer.new()\n'
      '\trow.add_theme_constant_override("separation", 8)\n'
      '\tpanel.add_child(row)')

print('HUD v1.97 срез 1 ок')
