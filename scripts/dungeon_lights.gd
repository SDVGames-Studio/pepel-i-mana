extends Node2D
const Assets := preload("res://scripts/assets.gd")
## Свет данжа («Данжи v2», этап 4 «Мир v2», референс a8ea4e27): ТЁПЛЫЕ
## факелы на стенах с живым огнём и мерцанием + ХОЛОДНЫЕ сине-бирюзовые
## лужи с медленной рябью — контраст «тёплый фонарь + холодные пятна»,
## на который накладывается тёплый фонарь героя (v1.33). В порченых
## комнатах огня нет — там красное тлеющее свечение трещин.
##
## v1.42.1 (правки приёмки):
## - факел — ПЛАМЯ НА СТЕНЕ (над тайлом у стены), не предмет на полу:
##   жаровня-чаша читалась «бочкой/сундуком»;
## - факелы горят ТОЛЬКО в биомах с живыми гуманоидами (biomes.humanoids,
##   фидбек: «жаровни там, где монстры нуждаются в свете»): бандиты и
##   изба Яги — да; нежить/зверь/демоны сидят в темноте;
## - все источники БРОСАЮТ ТЕНЬ ОТ СТЕН (shadow_enabled, окклюдеры данжа
##   поштучные): свет упирается в стены, за стену не просвечивает;
## - лужи — ОРГАНИЧЕСКИЕ пятна воды (скруглённые круги по кластеру,
##   тёмная середина, холодная кромка), а не синие квадраты-«предметы»:
##   читается вода, по которой герой проходит.

var gen: Object = null
var ts := 32
var v2: Dictionary = {}
var biome: Dictionary = {}
var hero: Node2D = null            # для отключения дальних источников (FPS)

var _time := 0.0
var _all_lights: Array = []        # [{light, pos}] — всё, что можно гасить
# дальше этого радиуса источники выключены: под глухим туманом они всё
# равно невидимы, а каждый теневой PointLight2D стоит кадров (v1.42.3)
var cull_px := 12.0 * 32.0
var _braziers: Array = []       # [{pos, phase, light}] (pos — основание пламени на стене)
var _puddles: Array = []        # [{tiles, light, phase}]
var _corrupt_lights: Array = [] # [{light, phase}]


func setup(dungeon_gen: Object, tile_size: int, v2_cfg: Dictionary,
		biome_data: Dictionary) -> void:
	gen = dungeon_gen
	ts = tile_size
	v2 = v2_cfg
	biome = biome_data
	# z по умолчанию (0): узел добавляется ДО героя — вода и пламя
	# рисуются ПОД героем (v1.42.2: «текстуры воды должны быть под
	# персонажем»); PointLight2D от порядка не зависит
	_build()


func _build() -> void:
	var warm := Color(String(v2.get("torch_color", "#ffb056")))
	var cold := Color(String(v2.get("cold_color", "#4dd0e1")))
	var warm_radius := float(v2.get("torch_radius", 2.6)) * float(ts)
	var cold_radius := float(v2.get("cold_radius", 2.0)) * float(ts)
	# факелы: только биомам с живыми гуманоидами (заказчик: свет нужен тем,
	# кто в нём живёт; нежить/зверь/демоны обходятся тьмой)
	if bool(biome.get("humanoids", false)):
		for i in gen.brazier_spawns.size():
			var tile: Vector2i = gen.brazier_spawns[i]
			# пламя — НА СТЕНЕ над тайлом (светильник), не предмет на полу
			var pos := Vector2(tile) * float(ts) + Vector2(float(ts) * 0.5, 5.0)
			var phase := float(i) * 1.7
			var light := _make_light(warm, warm_radius, 0.85)
			light.position = pos - Vector2(0, float(ts) * 0.4)
			add_child(light)
			_braziers.append({"pos": pos, "phase": phase, "light": light})
			_all_lights.append({"light": light, "pos": pos})
	# лужи: органическое пятно + холодный свет над центром кластера
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
		_all_lights.append({"light": light, "pos": center})
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
		_all_lights.append({"light": light, "pos": c})


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
	# v1.42.1: свет упирается в стены (окклюдеры поштучные — стабильные)
	light.shadow_enabled = true
	light.shadow_filter_smooth = 2.0
	return light


func _process(delta: float) -> void:
	_time += delta
	# FPS (v1.42.3): дальние источники гасим — тени стоят кадров, а под
	# глухим туманом они всё равно не видны
	if hero != null:
		var hp: Vector2 = hero.global_position
		for rec in _all_lights:
			(rec["light"] as PointLight2D).enabled = 					(Vector2(rec["pos"]) as Vector2).distance_to(hp) <= cull_px
	# кадры огня 8 к/с; энергия света дышит синусами — дёшево
	var fire_frame := int(_time * 8.0) % 3 + 1
	for b in _braziers:
		var flick := 0.85 + 0.25 * sin(_time * 7.0 + float(b["phase"])) \
				+ 0.08 * sin(_time * 23.0 + float(b["phase"]) * 2.0)
		(b["light"] as PointLight2D).energy = flick
		b["frame"] = (fire_frame + int(b["phase"])) % 3 + 1
	for p in _puddles:
		(p["light"] as PointLight2D).energy = 0.62 + 0.15 * sin(_time * 1.3 + float(p["phase"]))
	for c in _corrupt_lights:
		(c["light"] as PointLight2D).energy = 0.5 + 0.18 * sin(_time * 2.1 + float(c["phase"]))
	queue_redraw()


func _draw() -> void:
	var fire_h := float(v2.get("fire_height", 40.0))
	# факел-светильник: пламя на стене, под ним — тлеющее гнездо крепления
	for b in _braziers:
		var pos: Vector2 = b["pos"]
		var frame := int(b.get("frame", 1))
		Assets.draw_ref(self, "e:d2_fire_%d" % frame,
				pos - Vector2(0, fire_h * 0.5), fire_h, false, Color(1, 1, 1))
		draw_circle(pos, 2.6, Color(1.0, 0.62, 0.25, 0.9))
		draw_circle(pos + Vector2(-1.2, -1.0), 1.2, Color(1.0, 0.85, 0.5))
	# лужи: ОРГАНИЧЕСКОЕ пятно — союз из 3 блобов на тайл со сдвигами по
	# хэшу (кромка светлым под телом), гладкие края, живые блики-блёстки
	# (v1.42.4: «воду покрасивее» — вместо цепочки кругов)
	var deep := Color(String(v2.get("water_deep", "#1d4e63")))
	var edge := Color(String(v2.get("water_edge", "#6cc4d8")))
	var half := Vector2(float(ts), float(ts)) * 0.5
	for p in _puddles:
		var tiles: Array = p["tiles"]
		# кромка: те же блобы чуть крупнее, светлым полупрозрачным
		for t in tiles:
			var c := Vector2(t) * float(ts) + half
			for k in 3:
				draw_circle(c + _blob_off(t, k), float(ts) * 0.56,
						Color(edge.r, edge.g, edge.b, 0.45))
		# тело воды: тёмно-синее, чуть просвечивает пол (не «смола»)
		for t in tiles:
			var c := Vector2(t) * float(ts) + half
			for k in 3:
				draw_circle(c + _blob_off(t, k), float(ts) * 0.46,
						Color(deep.r, deep.g, deep.b, 0.9))
		# глубина: второй проход блобов поменьше и темнее — органично,
		# без искусственного «ядра-круга»
		for t in tiles:
			var c := Vector2(t) * float(ts) + half
			for k in 3:
				draw_circle(c + _blob_off(t, k) * 0.6, float(ts) * 0.3,
						Color(deep.r * 0.6, deep.g * 0.65, deep.b * 0.75, 0.5))
		# блики: редкие светлые точки, медленно дрейфуют и пульсируют
		for t in tiles:
			if tile_hash(int(t.x), int(t.y)) % 3 != 0:
				continue
			var base := Vector2(t) * float(ts) + half + _blob_off(t, 1)
			var drift := Vector2(sin(_time * 1.1 + float(t.x) * 2.1),
					cos(_time * 0.9 + float(t.y) * 1.7)) * 3.0
			var tw := 0.5 + 0.5 * sin(_time * 2.4 + float(t.x + t.y))
			draw_circle(base + drift, 1.8 + tw, Color(0.82, 0.96, 1.0, 0.25 + 0.4 * tw))
			draw_circle(base + drift * 0.5, 1.0, Color(1.0, 1.0, 1.0, 0.3 * tw))


## Сдвиг суб-блоба внутри тайла — детерминированный по хэшу тайла.
func _blob_off(t: Vector2i, k: int) -> Vector2:
	var h1 := tile_hash(int(t.x) * 3 + k, int(t.y))
	var h2 := tile_hash(int(t.x), int(t.y) * 3 + k + 7)
	return Vector2(float(h1 % 15) - 7.0, float(h2 % 15) - 7.0)


static func tile_hash(x: int, y: int) -> int:
	var v := int((x * 73856093) ^ (y * 19349663))
	return absi(v) % maxi(1, 1000)
