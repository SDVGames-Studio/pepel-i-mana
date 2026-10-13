extends Node
## Автозагрузка: состояние между сценами — рюкзак героя, итог последнего
## забега и город (M2). Инвентарь без веса (ответ 52), стеки без лимита.
## Симуляция города тикается здесь: пока герой в данже, город продолжает жить.

const CITY_CFG_PATH := "res://data/city.json"
const CITY_SIM_SCRIPT := "res://scripts/city_sim.gd"
const CITY_MAP_SCRIPT := "res://scripts/city_map.gd"
const MAGIC_SCRIPT := "res://scripts/magic.gd"
const MAGIC_CFG_PATH := "res://data/magic.json"

var inventory: Array = []        # [{id: String, count: int}]
var last_run_death := false      # true, если последний забег закончился гибелью
var city_sim = null              # city_sim.gd, нетипизированно (грабли GDScript 4)
var magic = null                 # magic.gd — школы/рецепты/заклинания (M3)
var spellbook: Array = []        # изученные заклинания: [id: String]
var start_residents := 5         # настройки старта из меню (вопрос 11)
var start_level := "normal"      # "low" | "normal" | "high"


func _init() -> void:
	# В _init (не _ready): тесты создают Game через new() вне дерева сцены.
	var data: Variant = _read_json(MAGIC_CFG_PATH)
	if data is Dictionary:
		magic = load(MAGIC_SCRIPT).new()
		magic.setup(data)
	else:
		push_error("Не читается data/magic.json")


func _process(delta: float) -> void:
	if city_sim != null:
		city_sim.tick(delta)


## Создать город с настройками старта (новая игра). Рюкзак и спеллбук очищаются.
func new_city() -> void:
	inventory = []
	spellbook = []
	last_run_death = false
	var cfg: Variant = _read_json(CITY_CFG_PATH)
	if not (cfg is Dictionary):
		push_error("Не читается data/city.json")
		return
	var map_script: Script = load(CITY_MAP_SCRIPT)
	var sim_script: Script = load(CITY_SIM_SCRIPT)
	var city_map = map_script.new()
	city_map.generate(randi(), cfg)
	city_sim = sim_script.new()
	city_sim.setup(city_map, cfg, start_residents, start_level)


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


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


## Убрать n единиц предмета; пустые стакы удаляются. Возвращает сколько убрано.
func remove_item(id: String, count: int) -> int:
	var left := count
	var i := 0
	while i < inventory.size() and left > 0:
		var stack: Dictionary = inventory[i]
		if String(stack["id"]) == id:
			var take := mini(left, int(stack["count"]))
			stack["count"] = int(stack["count"]) - take
			left -= take
			if int(stack["count"]) <= 0:
				inventory.remove_at(i)
				continue
		i += 1
	return count - left


## Заклинание изучено?
func has_spell(spell_id: String) -> bool:
	return spellbook.has(spell_id)


## Изучить заклинание (без дублей).
func learn_spell(spell_id: String) -> void:
	if not spellbook.has(spell_id):
		spellbook.append(spell_id)


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
