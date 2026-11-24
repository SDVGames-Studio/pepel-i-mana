#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v1.97.1 по фидбеку: свёрнутая панель = полоска (цифры+день+таймер волны),
# стрелка построек компактно слева с надписью «Строительство»,
# диалог выбора (квесты старосты) — у правого края, не по центру.
import io
import sys


def patch(path, old, new):
    src = io.open(path, encoding='utf-8').read()
    if old not in src:
        print('!! НЕ НАЙДЕНО в %s: %r' % (path, old[:70]))
        sys.exit(1)
    io.open(path, 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))


# ---------- 1. base: vars + полоска обновляется в дневном месте ----------
patch('scripts/city_hud_base.gd',
      'var _hud_res_fold: Button = null   # v1.97: свернуть ресурсы в полоску',
      'var _hud_res_fold: Button = null   # v1.97: свернуть ресурсы в полоску\n'
      'var _hud_res_strip: Label = null   # v1.97.1: полоска цифр в свёрнутом виде\n'
      'var _hud_res_open := true          # v1.97.1: панель поселения развёрнута?')

# ---------- 2. build: сворачиваем ДЕНЬ-независимо, полоску показываем ----------
patch('scripts/city_hud_build.gd',
      '\tres_fold.pressed.connect(func() -> void:\n'
      '\t\tvar open := res_fold.text == "▼"\n'
      '\t\tres_fold.text = "▲" if open else "▼"\n'
      '\t\tfor c in tl_box.get_children():\n'
      '\t\t\tif c != res_fold:\n'
      '\t\t\t\tc.visible = not open)',
      '\tres_fold.pressed.connect(func() -> void:\n'
      '\t\t_hud_res_open = not _hud_res_open\n'
      '\t\tres_fold.text = "▼" if _hud_res_open else "▲"\n'
      '\t\tfor c in tl_box.get_children():\n'
      '\t\t\tif c != res_fold and c != _hud_res_strip:\n'
      '\t\t\t\tc.visible = _hud_res_open\n'
      '\t\tif _hud_res_strip != null:\n'
      '\t\t\t_hud_res_strip.visible = not _hud_res_open)')
# полоска после стрелки (создаётся скрытой)
patch('scripts/city_hud_build.gd',
      '\t_hud_res_fold = res_fold\n'
      '\tres_fold.pressed.connect',
      '\t_hud_res_fold = res_fold\n'
      '\t_hud_res_strip = Label.new()\n'
      '\t_hud_res_strip.add_theme_font_size_override("font_size", 17)\n'
      '\t_hud_res_strip.add_theme_color_override("font_color", Color("#ffe9b0"))\n'
      '\t_hud_res_strip.visible = false\n'
      '\ttl_box.add_child(_hud_res_strip)\n'
      '\tres_fold.pressed.connect')

# ---------- 3. стрелка построек: компактно слева, с надписью ----------
patch('scripts/city_hud_build.gd',
      '\tvar bld_fold := Button.new()\n'
      '\tbld_fold.text = "▲"\n'
      '\tbld_fold.custom_minimum_size = Vector2(120, 40)\n'
      '\tbld_fold.focus_mode = Control.FOCUS_NONE\n'
      '\tbld_fold.add_theme_font_size_override("font_size", 15)\n'
      '\tbld_fold.visible = not guest\n'
      '\tbottom.add_child(bld_fold)\n'
      '\t_hud_bld_fold = bld_fold\n'
      '\tvar panel := PanelContainer.new()',
      '\tvar bld_fold := Button.new()\n'
      '\tbld_fold.text = "Строительство ▲"\n'
      '\tbld_fold.custom_minimum_size = Vector2(210, 34)\n'
      '\tbld_fold.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN\n'
      '\tbld_fold.focus_mode = Control.FOCUS_NONE\n'
      '\tbld_fold.add_theme_font_size_override("font_size", 15)\n'
      '\tbld_fold.visible = not guest\n'
      '\tbottom.add_child(bld_fold)\n'
      '\t_hud_bld_fold = bld_fold\n'
      '\tvar panel := PanelContainer.new()')
patch('scripts/city_hud_build.gd',
      '\tbld_fold.pressed.connect(func() -> void:\n'
      '\t\tpanel.visible = not panel.visible)',
      '\tbld_fold.pressed.connect(func() -> void:\n'
      '\t\tpanel.visible = not panel.visible\n'
      '\t\tbld_fold.text = "Строительство ▼" if panel.visible else "Строительство ▲")')

# ---------- 4. квест-диалог у правого края ----------
patch('scripts/city_hud_base.gd',
      '\t\t_choice_panel.position = Vector2(660, 260)\n'
      '\t\t_choice_panel.custom_minimum_size = Vector2(600, 0)',
      '\t\t_choice_panel.position = Vector2(1150, 90)\n'
      '\t\t_choice_panel.custom_minimum_size = Vector2(540, 0)')

# ---------- 5. полоска: обновление в дневном месте (base уже знает sim) ----------
patch('scripts/city_hud_base.gd',
      '\t	_pop_label.text = Loc.t("city.pop") % [sim.residents.size(), sim.pop_cap()]',
      '''\tpop_label.text = Loc.t("city.pop") % [sim.residents.size(), sim.pop_cap()]
	# v1.97.1: полоска свёрнутой панели — ключевые цифры + таймер волны
	if _hud_res_strip != null and not _hud_res_open:
		var wave_d := 999
		var nxt: Variant = sim.get("_next_raid_at")
		if nxt != null:
			wave_d = int(maxf(0.0, (float(nxt) - float(sim.time)) / maxf(1.0, float(sim.cfg.get("day_length", 300.0)))))
		_hud_res_strip.text = "День %d · еда %d · брёвна %d · камень %d · волна через %dд" % [
			sim.day_number(), int(sim.res.get("food", 0)), int(sim.res.get("wood", 0)),
			int(sim.res.get("stone", 0)), wave_d]''')
print('v1.97.1 ок')
