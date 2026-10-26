# Красивое окружение v1.27 (идея заказчика, 2026-10-26): скруглённые водоёмы,
# натурная скальная гряда, цветочные поляны, камыши; солнечный цикл — тени
# ползут с солнцем, разные закаты и характеры дня. Модуль проверяет чистые
# функции city_sky.gd (фазы, палитры, детерминизм) и подготовку теней.
# Общий хелпер — tests/test_base.gd.
extends "res://tests/test_base.gd"

const DaySky := preload("res://scripts/city_sky.gd")


## Утром тени на запад, в полдень короткие, вечером на восток; длина
## тени по краям дня заметно больше полуденной.
func _test_v127_sun_arc() -> void:
	var nf := 0.3
	# рассвет (u≈0.07): солнце на востоке — тени на запад (dir_x < 0)
	_check(DaySky.shadow_dir_x(0.05, nf) < -0.5, "v127: утром тени на запад")
	# закат (u≈0.93): солнце на западе — тени на восток (dir_x > 0)
	_check(DaySky.shadow_dir_x(0.65, nf) > 0.5, "v127: вечером тени на восток")
	# полдень (u≈0.5): направление ~0
	_check(absf(DaySky.shadow_dir_x(0.35, nf)) < 0.3, "v127: в полдень тени короткие под объектом")
	# высота солнца: пик в середине дня
	_check(DaySky.sun_elev(0.35, nf) > 0.95, "v127: полдень — солнце в зените")
	_check(DaySky.sun_elev(0.05, nf) < 0.5, "v127: рассвет — солнце низко")
	# длина теней: по краям дня длиннее, чем в полдень
	_check(DaySky.shadow_len(0.05, nf) > DaySky.shadow_len(0.35, nf) * 3.0,
			"v127: закатные/рассветные тени длиннее полуденных")
	# смещение тени: знак по X совпадает с направлением, юг не отрицательный
	var off_m := DaySky.shadow_offset(0.05, nf, 64.0)
	var off_e := DaySky.shadow_offset(0.65, nf, 64.0)
	_check(off_m.x < 0.0 and off_e.x > 0.0, "v127: смещение тени по знаку дня")
	_check(off_m.y >= 0.0 and off_e.y >= 0.0, "v127: тень наклонена к югу (читаемость)")
	# ночь не дневная
	_check(not DaySky.is_daylight(0.8, nf), "v127: t=0.8 при nf=0.3 — ночь")
	_check(DaySky.is_daylight(0.5, nf), "v127: t=0.5 при nf=0.3 — день")


## Разные закаты: палитра детерминирована по дню и покрывает несколько цветов.
func _test_v127_sunsets() -> void:
	var first := DaySky.sunset_color(1)
	for day in [1, 1, 1, 42, 42]:
		_check(DaySky.sunset_color(day) == (first if day == 1 else DaySky.sunset_color(42)),
				"v127: палитра заката дня %d детерминирована" % day)
	var uniq := {}
	for day in range(1, 41):
		var c := DaySky.sunset_color(day)
		uniq[c.to_html(false)] = true
		_check(c.r >= 0.0 and c.r <= 1.0 and c.g >= 0.0 and c.g <= 1.0
				and c.b >= 0.0 and c.b <= 1.0, "v127: цвет заката в диапазоне 0..1")
	_check(uniq.size() >= 3, "v127: за 40 дней встречается хотя бы 3 разных заката")


## Характер дня: погода сильнее календаря, в ясную погоду — детерминизм по дню.
func _test_v127_moods() -> void:
	_check(DaySky.mood_of(10, "rain") == DaySky.MOOD_OVERCAST, "v127: дождь — облачный день")
	_check(DaySky.mood_of(10, "snow") == DaySky.MOOD_OVERCAST, "v127: снег — облачный день")
	_check(DaySky.mood_of(10, "fog") == DaySky.MOOD_FOGGY, "v127: туман — туманный день")
	_check(DaySky.mood_of(10, "ash_storm") == DaySky.MOOD_GLOOMY, "v127: буря — хмурый день")
	# ясная погода: детерминизм и диапазон
	var m := DaySky.mood_of(7, "clear")
	for i in 5:
		_check(DaySky.mood_of(7, "clear") == m, "v127: характер дня 7 детерминирован")
	_check(m >= DaySky.MOOD_CLEAR and m <= DaySky.MOOD_GLOOMY, "v127: характер дня в диапазоне")
	var uniq := {}
	for day in range(1, 60):
		uniq[DaySky.mood_of(day, "clear")] = true
	_check(uniq.size() >= 3, "v127: за 59 ясных дней встречается 3+ характера")


## Амбиентный свет: полдень ясного дня почти белый, рассвет теплее,
## ночь темнее дня; характер дня меняет фон.
func _test_v127_daylight_colors() -> void:
	var nf := 0.3
	var noon := DaySky.daylight_color(DaySky.MOOD_CLEAR, 0.5 * (1.0 - nf), nf, 3)
	_check(noon.r > 0.93 and noon.g > 0.93, "v127: ясный полдень — почти белый свет")
	var dawn := DaySky.daylight_color(DaySky.MOOD_CLEAR, 0.0, nf, 3)
	_check(dawn.r > dawn.b, "v127: рассвет теплее (красный канал выше синего)")
	# золотой час: тёплая краска до входа в закатную палитру
	var golden := DaySky.daylight_color(DaySky.MOOD_CLEAR, 0.70 * (1.0 - nf), nf, 3)
	_check(golden.r > golden.b, "v127: золотой час теплее нейтрального")
	# сам закат: детерминирован по дню и окрашивает свет (палитра любая)
	var s1 := DaySky.daylight_color(DaySky.MOOD_CLEAR, 0.98 * (1.0 - nf), nf, 9)
	var s2 := DaySky.daylight_color(DaySky.MOOD_CLEAR, 0.98 * (1.0 - nf), nf, 9)
	_check(s1 == s2, "v127: закатная краска дня детерминирована")
	_check(s1 != Color.WHITE, "v127: закат окрашивает свет (не чистый белый)")
	_check(DaySky.night_color(DaySky.MOOD_CLEAR).r < 0.5, "v127: ночь темнее дня")
	_check(DaySky.night_color(DaySky.MOOD_GLOOMY).r < DaySky.night_color(DaySky.MOOD_CLEAR).r,
			"v127: хмурый день даёт более глухую ночь")
	# хмурый день темнее ясного в полдень
	var noon_gloom := DaySky.daylight_color(DaySky.MOOD_GLOOMY, 0.5 * (1.0 - nf), nf, 3)
	_check(noon_gloom.r < noon.r, "v127: пасмурный полдень темнее ясного")


## Сила теней по характеру дня: ясно — плотные, хмуро — почти нет.
func _test_v127_shadow_alpha() -> void:
	_check(DaySky.shadow_alpha(DaySky.MOOD_CLEAR) > DaySky.shadow_alpha(DaySky.MOOD_OVERCAST) * 2.0,
			"v127: в пасмурный день тени втрое бледнее")
	_check(DaySky.shadow_alpha(DaySky.MOOD_OVERCAST) < 0.12, "v127: рассеянный свет почти не тенит")
	_check(DaySky.shadow_alpha(DaySky.MOOD_FOGGY) < DaySky.shadow_alpha(DaySky.MOOD_ROSY),
			"v127: в туман тени слабее, чем в ясный розовый день")
	_check(DaySky.shadow_alpha(DaySky.MOOD_GOLDEN) >= DaySky.shadow_alpha(DaySky.MOOD_CLEAR),
			"v127: золотой час — тени не бледнее ясного дня")


## Луна: в ночи свет идёт с востока на запад, как солнце днём.
func _test_v127_moon() -> void:
	var nf := 0.3
	var t0 := 1.0 - nf + 0.01   # начало ночи
	var t1 := 0.99              # конец ночи
	_check(DaySky.moon_dir_x_at(t0, nf) < -0.5, "v127: в начале ночи луна на востоке")
	_check(DaySky.moon_dir_x_at(t1, nf) > 0.5, "v127: к утру луна на западе")
	_check(absf(DaySky.moon_u(0.5, nf)) < 0.001, "v127: днём лунной фазы нет (u=0)")
