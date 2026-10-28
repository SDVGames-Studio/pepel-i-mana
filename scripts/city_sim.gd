# Симуляция города — корень extends-цепочки частей (правки структуры v1.20.2).
# Файл-указатель: весь код разложен по city_sim_base/life/build/people/tick/
# zones/trade/gov/threat.gd; это один класс, вызовы sim.<метод> не меняются.
# Новые функции кладите в файл своей подсистемы, новые переменные — в base.
extends "res://scripts/city_sim_threat.gd"


## v1.28.1: продвижение незавершённых сканов мест (шахта/лесопилка) —
## вызывается из КОРНЯ цепочки (город_sim): функции gov не видны части
## city_sim_tick (она — родитель gov в extends-цепочке).
func tick(dt_raw: float) -> void:
	super(dt_raw)
	_advance_gather_scans_all()
