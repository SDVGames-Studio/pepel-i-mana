extends Node2D
## Сцена данжа-прототипа (M1): генерация, герой, враги, лут, мана-голод, HUD.
## Приёмка этапа: вошёл -> подрался -> собрал лут -> вернулся; смерть не завершает игру.

const DungeonGenScript := preload("res://scripts/dungeon_gen.gd")
const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const ChestScript := preload("res://scripts/chest.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const ExitMarkerScript := preload("res://scripts/exit_marker.gd")
const DungeonViewScript := preload("res://scripts/dungeon_view.gd")
const HudScript := preload("res://scripts/hud.gd")

var params: Dictionary = {}
var enemies_data: Array = []
var loot_data: Dictionary = {}
# ссылки на скрипты других узлов — динамические, без типов движка (свойств у них нет)
var gen = null
var hero = null
var hud = null
var ts := 32

var _seed_value := 0
var _visited: Dictionary = {}
var _mana_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _loot_rng := RandomNumberGenerator.new()


func _ready() -> void:
	params = _read_json("res://data/dungeon.json")
	enemies_data = _read_json("res://data/enemies.json")
	loot_data = _read_json("res://data/loot.json")
	ts = int(params["tile_size"])
	_seed_value = int(Time.get_unix_time_from_system())
	_rng.seed = _seed_value
	_loot_rng.seed = _seed_value + 1

	gen = DungeonGenScript.new()
	gen.generate(_seed_value, params)

	_build_darkness()
	add_child(_make_view())
	_build_walls()
	_build_exit()
	_build_chests()
	_build_crystals()
	_build_hero()
	_build_enemies()

	hud = HudScript.new()
	hud.init(hero, gen, loot_data)
	add_child(hud)
	hud.minimap.setup(gen)


func _process(delta: float) -> void:
	if hero.dead:
		return
	_update_fog()
	_update_mana_hunger(delta)
	_update_hint()
	hud.refresh()
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	if Input.is_action_just_pressed("inventory"):
		hud.toggle_inventory()


func _tile_to_pos(tile: Vector2i) -> Vector2:
	return Vector2(tile) * float(ts) + Vector2(ts, ts) / 2.0


func _pos_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i((pos / float(ts)).floor())


## Тьма: весь данж гасится, видимость даёт только фонарь героя (hero.make_light).
func _build_darkness() -> void:
	var dark := CanvasModulate.new()
	dark.name = "Darkness"
	dark.color = Color(String(params["biome"]["ambient"]))
	add_child(dark)


func _make_view() -> Node2D:
	var view = DungeonViewScript.new()
	view.setup(gen, ts, params["biome"])
	return view


## Стены: один StaticBody2D, горизонтальные цепочки стен слеплены в один прямоугольник.
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for y in gen.h:
		var x := 0
		while x < gen.w:
			if gen.grid[y][x] != DungeonGenScript.TILE_WALL:
				x += 1
				continue
			var x0 := x
			while x < gen.w and gen.grid[y][x] == DungeonGenScript.TILE_WALL:
				x += 1
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2((x - x0) * float(ts), float(ts))
			shape.shape = rect
			shape.position = Vector2((x0 + (x - x0) / 2.0) * float(ts), (y + 0.5) * float(ts))
			body.add_child(shape)


func _build_exit() -> void:
	var marker = ExitMarkerScript.new()
	marker.marker_color = Color(String(params["biome"]["exit_color"]))
	# на тайл в стороне от точки спавна, но всегда внутри стартовой комнаты
	marker.position = _tile_to_pos(gen.start_tile) + Vector2(float(ts), 0)
	marker.name = "ExitLadder"
	add_child(marker)


func _build_chests() -> void:
	for tile: Vector2i in gen.chest_spawns:
		var chest = ChestScript.new()
		chest.position = _tile_to_pos(tile)
		chest.add_to_group("chests")
		add_child(chest)


func _build_crystals() -> void:
	for tile: Vector2i in gen.crystal_spawns:
		_spawn_pickup("mana", "", _tile_to_pos(tile))


func _build_hero() -> void:
	hero = HeroScript.new()
	var hero_params: Dictionary = params["hero"]
	hero.setup(hero_params, int(hero_params["mana"]))
	hero.position = _tile_to_pos(gen.start_tile)
	hero.died.connect(_on_hero_died)
	add_child(hero)
	hero.set_camera_limits(Rect2(0, 0, gen.w * float(ts), gen.h * float(ts)))
	# радиус фонаря = радиус обзора + 1 тайл мягкого края
	hero.make_light((float(params["hero"]["vision_tiles"]) + 1.0) * float(ts))


func _build_enemies() -> void:
	for i in gen.enemy_spawns.size():
		var enemy = EnemyScript.new()
		enemy.setup(_pick_enemy_data())
		enemy.position = _tile_to_pos(gen.enemy_spawns[i])
		enemy.hero = hero
		enemy.died.connect(_on_enemy_died)
		add_child(enemy)


## Взвешенный случайный тип врага (enemy_weights в data/dungeon.json).
func _pick_enemy_data() -> Dictionary:
	var weights: Dictionary = params["enemy_weights"]
	var total := 0
	for w: int in weights.values():
		total += w
	var roll := _rng.randi_range(1, total)
	for enemy in enemies_data:
		roll -= int(weights.get(String(enemy["id"]), 0))
		if roll <= 0:
			return enemy
	return enemies_data[0]


func _spawn_pickup(kind: String, item_id: String, pos: Vector2) -> void:
	var pickup = PickupScript.new()
	pickup.setup(kind, item_id)
	pickup.position = pos
	pickup.collected.connect(_on_pickup_collected)
	add_child(pickup)


## Туман войны: миникарта рисуется только по реально пройденным тайлам.
func _update_fog() -> void:
	var t := _pos_to_tile(hero.position)
	var r := int(params["hero"]["vision_tiles"])
	var changed := false
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var p := Vector2i(t.x + dx, t.y + dy)
			if gen.is_floor(p) and not _visited.has(p):
				_visited[p] = true
				changed = true
	if changed:
		hud.minimap.update_state(t, _visited)


## Мана-голод (упрощённо): мана утекает по таймеру, на нуле — здоровье.
func _update_mana_hunger(delta: float) -> void:
	_mana_acc += delta
	if _mana_acc < float(params["mana_drain_period"]):
		return
	_mana_acc = 0.0
	if not hero.drain_mana():
		hero.take_damage(1)


func _update_hint() -> void:
	if _near_ladder():
		hud.set_hint(Loc.t("dungeon.hint_exit"))
		return
	var chest = _nearest_chest(float(ts) * 1.8)
	if chest != null:
		hud.set_hint(Loc.t("dungeon.hint_chest"))
		return
	hud.set_hint("")


func _near_ladder() -> bool:
	var ladder := get_node_or_null("ExitLadder")
	if ladder == null:
		return false
	return hero.position.distance_to(ladder.position) < float(ts) * 1.6


func _nearest_chest(radius: float):
	var best = null
	var best_d := radius
	for chest in get_tree().get_nodes_in_group("chests"):
		if chest.open:
			continue
		var d: float = chest.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = chest
	return best


func _try_interact() -> void:
	if _near_ladder():
		_leave_dungeon()
		return
	var chest = _nearest_chest(float(ts) * 1.8)
	if chest != null:
		_open_chest(chest)


func _open_chest(chest: Node) -> void:
	chest.open = true
	chest.queue_redraw()
	var count := _loot_rng.randi_range(int(loot_data["chest_items_min"]), int(loot_data["chest_items_max"]))
	for i in count:
		var item := _roll_item()
		Game.add_item(String(item["id"]))
		hud.toast(Loc.t("dungeon.got_item") % Loc.t(String(item["loc"])))


## Ролл предмета: сначала редкость по весам, затем случайный предмет этой редкости.
func _roll_item() -> Dictionary:
	var total := 0
	for rarity in loot_data["rarities"]:
		total += int(rarity["weight"])
	var roll := _loot_rng.randi_range(1, total)
	var chosen := ""
	for rarity in loot_data["rarities"]:
		roll -= int(rarity["weight"])
		if roll <= 0:
			chosen = String(rarity["id"])
			break
	var pool: Array = []
	for item in loot_data["items"]:
		if String(item["rarity"]) == chosen:
			pool.append(item)
	if pool.is_empty():
		return loot_data["items"][0]
	return pool[_loot_rng.randi_range(0, pool.size() - 1)]


func _on_pickup_collected(pickup) -> void:
	if pickup.kind == "mana":
		hero.add_mana(int(params["crystal_mana"]))
		hud.toast(Loc.t("dungeon.got_mana") % int(params["crystal_mana"]))
	else:
		Game.add_item(String(pickup.item_id))
		var item := _item_by_id(String(pickup.item_id))
		hud.toast(Loc.t("dungeon.got_item") % Loc.t(String(item["loc"])))


func _on_enemy_died(enemy) -> void:
	if _loot_rng.randf() < float(loot_data["enemy_drop_chance"]):
		_spawn_pickup("item", String(_roll_item()["id"]), enemy.position)
	if _loot_rng.randf() < float(enemy.p["mana_chance"]):
		_spawn_pickup("mana", "", enemy.position + Vector2(12, 6))


## Смерть героя: потеря половины лута и выброс в город, игра продолжается.
func _on_hero_died() -> void:
	Game.last_run_death = true
	Game.lose_half_loot()
	get_tree().change_scene_to_file("res://scenes/city.tscn")


func _leave_dungeon() -> void:
	Game.last_run_death = false
	get_tree().change_scene_to_file("res://scenes/city.tscn")


func _item_by_id(item_id: String) -> Dictionary:
	for item in loot_data.get("items", []):
		if item["id"] == item_id:
			return item
	return {}


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
