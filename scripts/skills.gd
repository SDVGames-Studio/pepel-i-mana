extends RefCounted
## Дерево навыков героя (M7): XP за врагов, уровни, ветки с узлами.
## Чистая логика без сцены: данные из data/skills.json, тестируется headless.
## XP и взятые узлы живут в Game — сохраняются между забегами в данж.

var cfg: Dictionary = {}
var xp := 0
var level := 1
var pending := 0                 # нераспределённых уровней
var taken: Array = []            # id взятых узлов


func setup(data: Dictionary) -> void:
	cfg = data


func reset() -> void:
	xp = 0
	level = 1
	pending = 0
	taken = []


## Сколько XP до следующего уровня: растёт с уровнем.
func xp_next() -> int:
	return int(cfg.get("xp_base", 12)) + int(cfg.get("xp_growth", 6)) * (level - 1)


## Добавить XP. Возвращает число новых уровней (они попадают в pending).
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	xp += amount
	var ups := 0
	while xp >= xp_next():
		xp -= xp_next()
		level += 1
		pending += 1
		ups += 1
	return ups


## Следующий доступный узел ветки (первый не взятый) или {} — ветка завершена.
func next_node(branch_id: String) -> Dictionary:
	for branch in cfg.get("branches", []):
		if String(branch["id"]) != branch_id:
			continue
		for node in branch.get("nodes", []):
			if not taken.has(String(node["id"])):
				return node
	return {}


## Взять узел (если он следующий своей ветки и есть pending). Возвращает деф или {}.
func choose(node_id: String) -> Dictionary:
	if pending <= 0 or taken.has(node_id):
		return {}
	for branch in cfg.get("branches", []):
		for node in branch.get("nodes", []):
			if String(node["id"]) == node_id:
				if next_node(String(branch["id"])).is_empty() \
						or String(next_node(String(branch["id"]))["id"]) != node_id:
					return {}
				taken.append(node_id)
				pending -= 1
				return node
	return {}


## Суммарные бонусы всех взятых узлов: {damage, hp, mana, ...}.
func bonuses() -> Dictionary:
	var out := {}
	for branch in cfg.get("branches", []):
		for node in branch.get("nodes", []):
			if not taken.has(String(node["id"])):
				continue
			_merge_bonuses(out, node)
	return out


## Бонусы одного узла (без текстовых полей).
static func node_bonuses(node: Dictionary) -> Dictionary:
	var out := {}
	_merge_bonuses(out, node)
	return out


static func _merge_bonuses(out: Dictionary, node: Dictionary) -> void:
	for key in node:
		if key in ["id", "loc", "desc"]:
			continue
		out[key] = float(out.get(key, 0.0)) + float(node[key])
