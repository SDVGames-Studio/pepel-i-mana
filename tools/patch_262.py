# -*- coding: utf-8 -*-
## v2.6.2: guards зависания (чанки), тосты -> боковая панель (спам убран),
## письма с кликом-камерой, обновляемое письмо стройки, V -> весь звук.
import io, json

ROOT = r"F:\Z2\.zcode\workspace\default\pepel-i-mana"
R = lambda p: io.open(ROOT + "\\" + p, encoding="utf-8").read()
W = lambda p, s: io.open(ROOT + "\\" + p, "w", encoding="utf-8", newline="\n").write(s)

# --- 1) game.gd: is_minimized ---
p = r"scripts\game.gd"
s = R(p)
if "is_minimized" not in s:
    a = "func hero_train(stat_id: String, amount: float) -> void:"
    assert a in s
    s = s.replace(a, '''## v2.6.2: окно свёрнуто? (рендер стоит — GPU readback/bake откладывать)
func is_minimized() -> bool:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var rt: Window = (ml as SceneTree).root
		return rt != null and rt.mode == Window.MODE_MINIMIZED
	return false


''' + a, 1)
    W(p, s)
    print("game: is_minimized")

# --- 2) чанки террейна: не читать вьюпорты пока свёрнуто ---
p = r"scripts\city_terrain_base.gd"
s = R(p)
if "Game.is_minimized" not in s:
    a = "	for b in _brushes:\n		var wait: Vector2i = b[\"wait\"]"
    assert a in s, "chunk anchor"
    s = s.replace(a, '''	# v2.6.2: на свёрнутом окне рендер стоит — readback из вьюпорта
	# зависает навсегда. Просто ждём разворота: UPDATE_ONCE остаётся
	# в очереди и снимется после восстановления
	if Game.is_minimized():
		return
	for b in _brushes:
		var wait: Vector2i = b["wait"]''', 1)
    W(p, s)
    print("terrain_base: chunk guard")

# --- 3) вода: запечка откладывается пока свёрнуто ---
p = r"scripts\water_terrain.gd"
s = R(p)
a = "func _do_bake() -> void:\n	if _vp == null or not is_inside_tree():\n		return\n	_bake_dirty = false"
if "Game.is_minimized" not in s:
    assert a in s, "water: bake anchor"
    s = s.replace(a, "func _do_bake() -> void:\n	if _vp == null or not is_inside_tree():\n		return\n	if Game.is_minimized():\n		return   # v2.6.2: запечём после разворота (_bake_dirty остаётся)\n	_bake_dirty = false", 1)
    W(p, s)
    print("water: bake guard")

# --- 4) спам-тост «Нет свободного работника» — убрать ---
p = r"scripts\city_events.gd"
e = R(p)
a = '				hud.toast(Loc.t("city.no_free_worker") % bld_name)\n'
assert a in e, "worker toast anchor"
e = e.replace(a, '				pass   # v2.6.2: спам убран — нехватка видна по иконке здания\n', 1)
W(p, e)
print("events: worker spam removed")
