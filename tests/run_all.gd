# Раннер автотестов (структура v1.20.2): модули tests/test_*.gd идут
# в историческом порядке. Запуск: godot --headless --path . --script res://tests/run_all.gd
extends SceneTree


const BLOCKS := [
	["res://tests/test_core.gd", [
	"_test_loc",
	"_test_data",
	"_test_scripts",
	"_test_scenes",
	"_test_dungeon_gen",
	"_test_game_inventory",
	"_test_city_map",
	"_test_city_sim",
	"_test_people",
	"_test_magic",
	"_test_magic_sim",
	"_test_spell_damage",
]],
	["res://tests/test_threat.gd", [
	"_test_threat",
	"_test_forbidden_school",
	"_test_mutant_forest",
	"_test_defense",
	"_test_gathering",
]],
	["res://tests/test_eras.gd", [
	"_test_m6",
	"_test_m7",
	"_test_m8",
	"_test_m9",
	"_test_m10",
]],
	["res://tests/test_life_a.gd", [
	"_test_wishlist",
	"_test_m12",
	"_test_m13",
	"_test_m14_save",
	"_test_m14_b",
	"_test_m14_c",
	"_test_m14_d",
	"_test_m14_e",
	"_test_m14_f",
]],
	["res://tests/test_life_b.gd", [
	"_test_m14_g",
	"_test_m14_h",
	"_test_m14_i",
	"_test_m14_j",
	"_test_m14_k",
	"_test_m14_l",
	"_test_fixes_v121",
	"_test_hero_work",
]],
	["res://tests/test_stage2.gd", [
	"_test_stage2_aspect1",
	"_test_stage2_aspect2",
	"_test_stage2_aspect3",
	"_test_stage2_entrance_recalc",
	"_test_stage2_aspect4",
	"_test_stage2_aspect5",
	"_test_stage2_aspect6",
]],
	["res://tests/test_v120.gd", [
	"_test_fixes_v1191",
	"_test_fixes_v120",
	"_test_fixes_v1201",
]],
]


func _initialize() -> void:
	var total := 0
	var mods := {}
	for b in BLOCKS:
		if not mods.has(b[0]):
			mods[b[0]] = load(b[0]).new()
			mods[b[0]].tree = self
		for fname in b[1]:
			mods[b[0]].call(fname)
		total += int(mods[b[0]]._fails)
	if total == 0:
		print("OK: все тесты пройдены")
		quit(0)
	else:
		print("FAIL: упавших проверок: %d" % total)
		quit(1)
