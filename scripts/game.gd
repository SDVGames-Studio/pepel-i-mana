extends Node
## Автозагрузка: состояние между сценами — рюкзак героя и итог последнего забега.
## Инвентарь без веса (решение заказчика, вопрос 52): стеки предметов, без лимита.

var inventory: Array = []        # [{id: String, count: int}]
var last_run_death := false      # true, если последний забег закончился гибелью


## Добавляет предмет в рюкзак, при совпадении складывается в стак.
func add_item(id: String, count: int = 1) -> void:
	for stack in inventory:
		if stack["id"] == id:
			stack["count"] = int(stack["count"]) + count
			return
	inventory.append({"id": id, "count": count})


func count_item(id: String) -> int:
	for stack in inventory:
		if stack["id"] == id:
			return int(stack["count"])
	return 0


## Всего единиц добычи в рюкзаке.
func loot_total() -> int:
	var total := 0
	for stack in inventory:
		total += int(stack["count"])
	return total


## Гибель в данже: каждый стак теряет половину с округлением вверх.
## Возвращает число потерянных единиц.
func lose_half_loot() -> int:
	var lost_total := 0
	for stack in inventory:
		var lost := ceili(int(stack["count"]) / 2.0)
		stack["count"] = int(stack["count"]) - lost
		lost_total += lost
	inventory = inventory.filter(func(stack: Dictionary) -> bool: return int(stack["count"]) > 0)
	return lost_total
