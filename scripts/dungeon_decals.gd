extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Статичные декали данжа («Данжи v2», этап 4 «Мир v2»): мох, наползающий
## на камень скруглёнными пятнами (референс 0d1fe2dc), «пепельная порча» —
## красно-чёрные потёки на гранях стен и трещины пола порченых комнат
## (5f017950), обычные трещины и пропсы пака (черепа/кости/щебень/паутина).
## Рисуется один раз на забег (запечка в _draw), туман войны — сверху.

var gen: Object = null
var ts := 32
var biome: Dictionary = {}
var v2: Dictionary = {}          # dungeon.json → v2 (цвета порчи/мха)
var corrupt: Dictionary = {}     # тайлы порченых комнат (для быстрой проверки)


func setup(dungeon_gen: Object, tile_size: int, biome_data: Dictionary,
		v2_cfg: Dictionary) -> void:
	gen = dungeon_gen
	ts = tile_size
	biome = biome_data
	v2 = v2_cfg
	corrupt = {}
	for ri in gen.corrupt_rooms:
		var room: Dictionary = gen.rooms[ri]
		for y in range(int(room["y"]) - 1, int(room["y"]) + int(room["h"]) + 1):
			for x in range(int(room["x"]) - 1, int(room["x"]) + int(room["w"]) + 1):
				corrupt[Vector2i(x, y)] = true
	queue_redraw()


func _draw() -> void:
	if gen == null:
		return
	var mossy := bool(biome.get("moss", false))
	var moss_col := Color(String(v2.get("moss_color", "#5c8a44")))
	var corrupt_col := Color(String(v2.get("corrupt_color", "#7a1e1e")))
	var corrupt_glow := Color(String(v2.get("corrupt_glow", "#c43a30")))
	var half := Vector2(ts, ts) * 0.5
	for y in gen.h:
		for x in gen.w:
			var tile: int = gen.grid[y][x]
			var pos := Vector2(x, y) * ts
			var h := tile_hash(x, y)
			var here := Vector2i(x, y)
			var is_corrupt := corrupt.has(here)
			if tile == gen.TILE_FLOOR:
				# трещины: обычные — редко и вне порчи, красные — в порче
				if is_corrupt and h % 4 == 0:
					var ref := "e:d2_crack_a" if h % 8 == 0 else "e:d2_crack_b"
					Assets.draw_ref(self, ref, pos + half, float(ts), h % 3 == 0,
							Color(corrupt_glow.r, corrupt_glow.g, corrupt_glow.b, 0.5))
				elif h % 17 == 0:
					Assets.draw_ref(self, "e:d2_crack_c", pos + half, float(ts),
							h % 2 == 0, Color(0.2, 0.18, 0.16, 0.5))
				# мох на полу: скруглённые пятна, чаще у стен
				if mossy and not is_corrupt and h % 9 < 2 and _near_wall(x, y):
					Assets.draw_ref(self, "e:d2_moss_a" if h % 2 == 0 else "e:d2_moss_b",
							pos + half, float(ts), h % 5 == 0,
							Color(moss_col.r, moss_col.g, moss_col.b, 0.8))
			elif is_corrupt and _wall_visible(x, y):
				# порча на стенах: потёки по грани (темнее к низу) + трещины
				Assets.draw_ref(self, "e:d2_wall_crack_a", pos + half, float(ts),
						h % 2 == 0, Color(corrupt_col.r, corrupt_col.g, corrupt_col.b, 0.75))
				if h % 3 == 0:
					Assets.draw_ref(self, "e:d2_wall_crack_b", pos + half, float(ts),
							h % 4 == 0,
							Color(corrupt_glow.r, corrupt_glow.g, corrupt_glow.b, 0.4))
			elif mossy and _wall_visible(x, y) and h % 11 < 3:
				# мох на стенах: наползает сверху/по углам
				Assets.draw_ref(self, "e:d2_moss_a", pos + Vector2(half.x, half.y * 0.7),
						float(ts), h % 6 == 0,
						Color(moss_col.r, moss_col.g, moss_col.b, 0.85))
	# пропсы пака: по хэшу редкие, в порче — кости, в мшистых — щебень/паутина
	_draw_props(half)


func _draw_props(half: Vector2) -> void:
	var props_rare := int(v2.get("props_per_hundred", 6))
	for y in gen.h:
		for x in gen.w:
			if gen.grid[y][x] != gen.TILE_FLOOR:
				continue
			var h := tile_hash(x, y)
			if h % 100 >= props_rare:
				continue
			var pos := Vector2(x, y) * ts + half
			var kind := (h / 7) % 6
			var is_corrupt := corrupt.has(Vector2i(x, y))
			var ref := ""
			if is_corrupt:
				match kind % 3:
					0: ref = "p:d2_prop_skull"
					1: ref = "p:d2_prop_bones"
					2: ref = "p:d2_prop_rubble2"
			elif bool(biome.get("crystals", false)) and kind == 4:
				ref = "p:d2_prop_crystal%d" % (h % 3 + 1)
			else:
				match kind:
					0: ref = "p:d2_prop_rubble1"
					1: ref = "p:d2_prop_rubble2"
					2: ref = "p:d2_prop_web"
					3: ref = "p:d2_prop_rubble1"
			if ref != "":
				Assets.draw_ref(self, ref, pos, float(ts), h % 2 == 0, Color(1, 1, 1, 0.95))


func _near_wall(x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if gen.tile_at(Vector2i(x, y) + d) == gen.TILE_WALL:
			return true
	return false


func _wall_visible(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if gen.is_floor(Vector2i(x + dx, y + dy)):
				return true
	return false


## Хэш тайла — тот же, что в dungeon_view.gd (стабильный паттерн декалей).
static func tile_hash(x: int, y: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, 1000)
