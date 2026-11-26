extends "res://tests/test_base.gd"
## v2.7: выбор сложности новой игры (множители угрозы).

const GameScript := preload("res://scripts/game.gd")


func _test_difficulty() -> void:
	print("[v2.7: сложность новой игры]")
	var cfg: Dictionary = _read_json("res://data/city.json")
	var base_day: int = int(cfg["threat"]["start_day"])
	var base_max: int = int(cfg["threat"]["raid_size_max"])
	var base_base: int = int(cfg["threat"]["raid_size_base"])
	var easy: Dictionary = cfg.duplicate(true)
	GameScript.apply_difficulty(easy, "easy")
	_check(int(easy["threat"]["start_day"]) > base_day, "лёгкая: волна приходит позже")
	_check(int(easy["threat"]["raid_size_max"]) < base_max, "лёгкая: волны меньше")
	_check(int(easy["threat"]["raid_size_base"]) < base_base, "лёгкая: база волн меньше")
	var hard: Dictionary = cfg.duplicate(true)
	GameScript.apply_difficulty(hard, "hard")
	_check(int(hard["threat"]["raid_size_base"]) > base_base, "суровая: база волн больше")
	_check(int(hard["threat"]["start_day"]) <= base_day, "суровая: не позже старта")
	var norm: Dictionary = cfg.duplicate(true)
	GameScript.apply_difficulty(norm, "normal")
	_check(int(norm["threat"]["start_day"]) == base_day, "нормальная не меняет баланс")
	var none: Dictionary = cfg.duplicate(true)
	GameScript.apply_difficulty(none, "unknown")
	_check(int(none["threat"]["start_day"]) == base_day, "неизвестная сложность = без изменений")
