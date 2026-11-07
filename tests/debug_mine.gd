extends "res://tests/test_base.gd"

func _test_debug_mine() -> void:
	print("[debug: шахта]")
	var sim := _make_sim()
	sim._last_daily_day = 999999
	sim.res["food"] = 500.0
	sim.map.deposit_tiles.clear()
	# найти руду
	var ore := Vector2i(-1, -1)
	for y in range(1, sim.map.h - 1):
		for x in range(1, sim.map.w - 1):
			if int(sim.map.grid[y][x]) == sim.map.TILE_ORE:
				ore = Vector2i(x, y)
				break
		if ore.x >= 0:
			break
	print("ore=", ore)
	_check(sim.place_building("mine", ore), "шахта на руде")
	var mine: Dictionary = sim.building_at(ore)
	mine["done"] = true
	var miner: Dictionary = sim.residents[0]
	miner["prof"] = "miner"
	miner["bld"] = mine
	mine["worker"] = int(miner["id"])
	miner["traits"] = []
	sim.time = 10.0
	for i in 12:
		sim.tick(10.0)
		sim.time = 10.0
		print("t=%d state=%s pos=%s carry_i=%.1f carry_s=%.1f res_n=%.1f iron=%.1f vein=%s" % [
			i, String(miner.get("state", "?")), str(miner["pos"]),
			float(miner.get("carry_iron", 0.0)), float(miner.get("carry_stone", 0.0)),
			float(miner.get("carry_res_n", 0.0)), float(sim.res["iron"]),
			str(sim._vein_target(miner, mine).get("rock", "none"))])
	if tree != null:
		tree.quit(0)
