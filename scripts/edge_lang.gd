extends RefCounted
class_name EdgeLang
## ЕДИНЫЙ ЯЗЫК КРОМОК «Природы 2.0» (v1.39.0): одни пропорции граней,
## губ и теней для плато, скал и берегов (принятые плато v1.36 — эталон).
## plateau_terrain.gd держит эти же значения в data/city.json → colors.plateau
## (дефолты совпадают с константами ниже); rock_terrain.gd и вода берут
## отсюда, чтобы все кромки города читались одной системой высот.
##
## Схема грани (свет с СЗ):
##   губа кромки (тёмная нависающая полоса) → тело среза (светлая полоса
##   сверху, тёмное основание) → контактная тень
##   → мягкие полосы тени на земле к югу (затухание).

# Доли тайла (как в colors.plateau):
const LIP_H := 0.12          # губа кромки
const FACE_H1 := 0.38        # высота среза плато уровня 1 / малого утёса
const FACE_H2 := 0.60        # высота среза двойного уровня / гряды
const TOP_STRIPE := 0.22     # светлая полоса среза (доля высоты среза)
const BOTTOM_STRIPE := 0.26  # тёмное основание (доля высоты среза)
const N_RIM := 0.10          # северная солнечная кромка (полоса сверху)
const E_RIM := 0.08          # восточное тёмное ребро
const W_RIM := 0.08          # западное светлое ребро
const SHADOW_ALPHA := 0.22   # первая полоса тени у подножия
const SHADOW_FADE := 0.34    # затухание каждой следующей полосы
const SHADOW_STEP := 0.16    # шаг полос тени (доля тайла)
const SHADOW_H := 0.18       # высота полосы тени (доля тайла)

## Мягкая тень у подножия: полосы с затуханием к югу от кромки.
## x/w — полоса по ширине грани; y_south — низ кромки (юг тайла).
static func draw_foot_shadow(canvas: Object, x: float, y_south: float, ts: float,
		w: float, diff: int, alpha: float = SHADOW_ALPHA) -> void:
	var bands := 2 + mini(diff, 2)
	for i in bands:
		var a := alpha * (1.0 - SHADOW_FADE * float(i))
		canvas.draw_rect(Rect2(x, y_south + ts * SHADOW_STEP * float(i), w,
				ts * SHADOW_H), Color(0.05, 0.08, 0.05, a))

## Трёхтоновый срез: светлая полоса у губы + тело + тёмное основание.
static func draw_face_stripes(canvas: Object, x: float, y_face: float,
		w: float, face_h: float, stone: Color, stone_dark: Color) -> void:
	var top_h := face_h * TOP_STRIPE
	var bot_h := face_h * BOTTOM_STRIPE
	canvas.draw_rect(Rect2(x, y_face, w, top_h), stone.lightened(0.14))
	canvas.draw_rect(Rect2(x, y_face + face_h - bot_h, w, bot_h), stone_dark)
