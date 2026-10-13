extends RefCounted
## Магия (M3): школы, руны, рецепты крафта, заклинания, зачарования.
## Чистая логика без сцены: данные из data/magic.json, тестируется headless.
## Руны — предметы рюкзака (id из data/loot.json), рецепт = пара рун без порядка.

var cfg: Dictionary = {}
var _spells: Dictionary = {}      # id заклинания -> определение
var _recipes: Dictionary = {}     # "руна|руна" (отсортировано) -> id заклинания
var _enchants: Dictionary = {}    # id зачарования -> определение


func setup(data: Dictionary) -> void:
	cfg = data
	_spells.clear()
	_recipes.clear()
	_enchants.clear()
	for s in cfg.get("spells", []):
		_spells[String(s["id"])] = s
	for r in cfg.get("recipes", []):
		_recipes[_pair_key(String(r["a"]), String(r["b"]))] = String(r["spell"])
	for e in cfg.get("enchantments", []):
		_enchants[String(e["id"])] = e


## Результат крафта пары рун (порядок не важен); "" — неизвестная комбинация.
func recipe_result(rune_a: String, rune_b: String) -> String:
	return String(_recipes.get(_pair_key(rune_a, rune_b), ""))


func spell(spell_id: String) -> Dictionary:
	return _spells.get(spell_id, {})


func spells() -> Array:
	return cfg.get("spells", [])


func enchantment(ench_id: String) -> Dictionary:
	return _enchants.get(ench_id, {})


func enchantments() -> Array:
	return cfg.get("enchantments", [])


func school_color(school_id: String) -> Color:
	for s in cfg.get("schools", []):
		if String(s["id"]) == school_id:
			return Color(String(s["color"]))
	return Color.WHITE


func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a <= b else b + "|" + a
