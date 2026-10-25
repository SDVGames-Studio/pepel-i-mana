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
	["res://tests/test_v121.gd", [
		"_test_v121_balance",
		"_test_v121_trees",
		"_test_v121_quarry",
		"_test_v21_golem_commit",
		"_test_v121_district",
		"_test_v121_city_repair",
		"_test_v21_fps_counter",
	]],
	["res://tests/test_v1214.gd", [
		"_test_v1214_caches",
		"_test_v1215_pop_max",
	]],
	["res://tests/test_v122.gd", [
		"_test_v122_seasons",
		"_test_v122_legends",
		"_test_v122_encounters",
		"_test_v122_static_ground",
	]],
	["res://tests/test_v123.gd", [
		"_test_v123_attributes",
		"_test_v123_spar",
		"_test_v123_cemetery",
		"_test_v123_necro_night",
		"_test_v123_farm_fields",
		"_test_v123_log_haul",
	]],
	["res://tests/test_v124.gd", [
		"_test_v124_pools",
		"_test_v124_wis_call",
		"_test_v124_hero_stats",
		"_test_v124_enemy_stats",
		"_test_v124_cemetery_building",
		"_test_v124_dark_storm",
		"_test_v124_necro_stealth",
	]],
	["res://tests/test_v126.gd", [
		"_test_v126_gates",
		"_test_v126_raiders_walls",
		"_test_v126_cemetery",
		"_test_v126_fps",
	]],
]


func _initialize() -> void:
	var total := 0
	var oks := 0
	var mods := {}
	for b in BLOCKS:
		if not mods.has(b[0]):
			var script: Script = load(b[0])
			if script == null or not script.can_instantiate():
				print("FAIL: модуль не загрузился: " + b[0])
				quit(1)
				return
			mods[b[0]] = script.new()
			mods[b[0]].tree = self
		for fname in b[1]:
			mods[b[0]].call(fname)
		total += int(mods[b[0]]._fails)
		oks += int(mods[b[0]]._oks)
	# страховка от «мгновенного зелёного»: ни одной проверки — это провал
	if oks < 100:
		print("FAIL: проверок слишком мало (%d) — раннер упал раньше тестов" % oks)
		quit(1)
		return
	if total == 0:
		print("OK: все тесты пройдены")
		quit(0)
	else:
		print("FAIL: упавших проверок: %d" % total)
		quit(1)
