class_name MagicLogic
extends RefCounted
## Магия (M3): школы, руны, рецепты крафта, заклинания, зачарования.
## Чистая логика без сцены: данные из data/magic.json, тестируется headless.
## Руны — предметы рюкзака (id из data/loot.json), рецепт = пара рун без порядка.

var cfg: Dictionary = {}


# --- статическая логика v1.66 (магия-просто) — тестируется headless ---------

## Уровень заклинания за использованием: +1 уровень за 10 кастов, потолок 10.
static func level_from_uses(uses: int) -> int:
	return mini(10, int(uses / 10))


## Множитель силы заклинания от уровня: ×1.1 за уровень, потолок ×2.
static func power_from_level(level: int) -> float:
	return 1.0 + 0.1 * float(level)


## Руны первого заклинания (гарантия обучения, дизайн-док 15-ОЖИВЛЕНИЕ
## аспект 2): пока ничего не изучено и пары нет в рюкзаке — вернуть руну
## первого рецепта. Иначе [].
static func first_gift_runes(spellbook: Array, inventory: Array) -> Array:
	if not spellbook.is_empty():
		return []
	var have := {}
	for stack in inventory:
		var id := String(stack["id"])
		if id.begins_with("rune_"):
			have[id] = true
	var missing: Array = []
	for rune_id in FIRST_SPELL_RUNES:
		if not have.has(rune_id):
			missing.append(rune_id)
	return missing


## Первое заклинание: пара рун первого рецепта (Огненная вспышка).
const FIRST_SPELL_RUNES := ["rune_sparks", "rune_chaos"]
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
