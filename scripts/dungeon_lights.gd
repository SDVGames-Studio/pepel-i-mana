extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Свет данжа («Данжи v2», этап 4 «Мир v2», референс a8ea4e27): ТЁПЛЫЕ
## жаровни с живым огнём и мерцанием + ХОЛОДНЫЕ сине-бирюзовые лужи с
## медленной рябью — контраст «тёплый фонарь + холодные пятна», на который
## накладывается тёплый фонарь героя (v1.33). В порченых комнатах огня нет —
## там красное тлеющее свечение трещин. Всё статично, кроме мелких
## анимаций: кадры огня 8 к/с, вода 3 к/с, энергия света дышит синусом.

var gen: Object = null
var ts := 32
var v2: Dictionary = {}

var _time := 0.0
var _braziers: Array = []       # [{pos, phase, light}]
var _puddles: Array = []        # [{tiles, light, phase}]
var _corrupt_lights: Array = [] # [{pos, light}]


func setup(dungeon_gen: Object, tile_size: int, v2_cfg: Dictionary) -> void:
	gen = dungeon_gen
	ts = tile_size
	v2 = v2_cfg
	z_index = 10
	_build()


func _build() -> void:
	var warm := Color(String(v2.get("torch_color", "#ffb056")))
	var cold := Color(String(v2.get("cold_color", "#4dd0e1")))
	var warm_radius := float(v2.get("torch_radius", 2.6)) * float(ts)
	var cold_radius := float(v2.get("cold_radius", 2.0)) * float(ts)
	# жаровни: чаша + огонь (3 кадра мерцания) + тёплый свет
	for i in gen.brazier_spawns.size():
		var tile: Vector2i = gen.brazier_spawns[i]
		var pos := Vector2(tile) * float(ts) + Vector2(float(ts), float(ts)) * 0.5
		var phase := float(i) * 1.7
		var light := _make_light(warm, warm_radius, 0.85)
		light.position = pos - Vector2(0, float(ts) * 0.4)
		add_child(light)
		_braziers.append({"pos": pos, "phase": phase, "light": light})
	# лужи: анимированная вода + холодный свет над центром кластера
	for zi in gen.puddle_zones.size():
		var zone: Array = gen.puddle_zones[zi]
		var center := Vector2.ZERO
		for t in zone:
			center += Vector2(t) * float(ts) + Vector2(float(ts), float(ts)) * 0.5
		center /= float(zone.size())
		var light := _make_light(cold, cold_radius, 0.7)
		light.position = center
		add_child(light)
		_puddles.append({"tiles": zone, "light": light, "phase": float(zi) * 2.3})
	# красное тлеющее свечение в сердцах порчи (комната без огня дышит злом)
	var corrupt_col := Color(String(v2.get("corrupt_glow", "#c43a30")))
	for ri in gen.corrupt_rooms:
		var room: Dictionary = gen.rooms[ri]
		var c := Vector2(float(room["x"]) + float(room["w"]) * 0.5,
				float(room["y"]) + float(room["h"]) * 0.5) * float(ts)
		var light := _make_light(corrupt_col, float(v2.get("corrupt_radius", 2.4)) * float(ts), 0.55)
		light.position = c
		add_child(light)
		_corrupt_lights.append({"light": light, "phase": float(ri) * 3.1})


func _make_light(col: Color, radius_px: float, energy: float) -> PointLight2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(col.r, col.g, col.b, 0.9),
		Color(col.r, col.g, col.b, 0.55),
		Color(col.r, col.g, col.b, 0.22),
		Color(col.r, col.g, col.b, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	var light := PointLight2D.new()
	light.texture = tex
	light.texture_scale = radius_px / 64.0
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	return light


func _process(delta: float) -> void:
	_time += delta
	# кадры: огонь 8 к/с, вода 3 к/с — редкие переключения, дешёво
	var fire_frame := int(_time * 8.0) % 3 + 1
	var water_frame := int(_time * 3.0) % 3 + 1
	var fire_h := float(v2.get("fire_height", 46.0))
	for b in _braziers:
		var flick := 0.85 + 0.25 * sin(_time * 7.0 + float(b["phase"])) \
				+ 0.08 * sin(_time * 23.0 + float(b["phase"]) * 2.0)
		(b["light"] as PointLight2D).energy = flick
		b["frame"] = (fire_frame + int(b["phase"])) % 3 + 1
	for p in _puddles:
		(p["light"] as PointLight2D).energy = 0.62 + 0.15 * sin(_time * 1.3 + float(p["phase"]))
		p["frame"] = (water_frame + int(float(p["phase"]))) % 3 + 1
	for c in _corrupt_lights:
		(c["light"] as PointLight2D).energy = 0.5 + 0.18 * sin(_time * 2.1 + float(c["phase"]))
	queue_redraw()


func _draw() -> void:
	var half := Vector2(float(ts), float(ts)) * 0.5
	var fire_h := float(v2.get("fire_height", 46.0))
	for b in _braziers:
		var pos: Vector2 = b["pos"]
		Assets.draw_ref(self, "e:d2_brazier", pos - Vector2(0, 2.0), float(ts) * 0.8, false,
				Color(1, 1, 1))
		var frame := int(b.get("frame", 1))
		Assets.draw_ref(self, "e:d2_fire_%d" % frame,
				pos - Vector2(0, fire_h * 0.36), fire_h, false, Color(1, 1, 1))
	for p in _puddles:
		var frame := int(p.get("frame", 1))
		for t in p["tiles"]:
			var pos := Vector2(t) * float(ts) + half
			Assets.draw_ref(self, "e:d2_water_%d" % frame, pos, float(ts), false, Color(1, 1, 1))
		# блик-пена: редкие искорки на тайлах лужи (кадры воды пака ровные —
		# живость добавляем блеском, как рябь на референсе)
		for t in p["tiles"]:
			if (tile_hash(int(t.x), int(t.y)) + int(_time * 3.0)) % 5 != 0:
				continue
			var fp := Vector2(t) * float(ts) + half + Vector2(
					float(tile_hash(int(t.y), int(t.x)) % 10) - 5.0, -4.0)
			Assets.draw_ref(self, "e:d2_foam", fp, float(ts) * 0.5, false,
					Color(0.8, 0.95, 1.0, 0.8))


static func tile_hash(x: int, y: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, 1000)
