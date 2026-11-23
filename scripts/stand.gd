extends Node2D
## Тестовый стенд (v1.75): все горожане, монстры, боссы, здания и герой —
## в ряд, на расстоянии, прогоняют idle-анимации (где они есть).
## Открытие — кнопка «Тестовый стенд» в главном меню; ESC — назад в меню.
## Управление: WASD/стрелки/перетаскивание ЛКМ — обзор, колесо — зум.

const UITheme := preload("res://scripts/ui_theme.gd")

const VILL_SPACING := 120.0
const MOB_SPACING := 170.0
const BOSS_SPACING := 300.0
const BLD_SPACING := 360.0
const ROW_GAP := 420.0

const VILL_HEIGHT := 64.0    # высота фигур в рядах (для читаемости)
const MOB_HEIGHT := 60.0
const BOSS_HEIGHT := 130.0
const BLD_HEIGHT := 180.0

var _t := 0.0
var _cam := Vector2(520.0, -120.0)   # старт вида — начало ряда горожан
var _zoom := 1.0
var _drag := false

var _villagers: Array = []       # [prof, подпись]
var _mobs: Array = []            # [ref, подпись]
var _bosses: Array = []          # [ref, подпись]
var _buildings: Array = []       # [ref, подпись]
var _hero_tex: Texture2D = null
var _biome_patches: Array = []   # v1.76.3: галерея биомов 20x20 (запечённые)
var _wave_rows: Array = []       # волна 2026-11-23: ряды новой нарезки


func _ready() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var hint := Label.new()
	hint.text = Loc.t("stand.title") + "  ·  " + Loc.t("stand.hint")
	hint.position = Vector2(16, 12)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	ui.add_child(hint)
	var back := Button.new()
	back.text = Loc.t("stand.back")
	back.position = Vector2(16, 44)
	back.custom_minimum_size = Vector2(200, 40)
	back.add_theme_font_size_override("font_size", 16)
	back.focus_mode = Control.FOCUS_NONE
	UITheme.apply_button(back)
	back.pressed.connect(_back_to_menu)
	ui.add_child(back)

	var people: Dictionary = _read_json("res://data/residents.json")
	for prof: String in Assets.VILLAGER_PROF.keys():
		_villagers.append([prof, Loc.t("prof." + prof)])
	_villagers.append(["elder", Loc.t("prof.elder")])

	var enemies: Array = _read_json("res://data/enemies.json")
	for e in enemies:
		var row: Array = _bosses if bool(e.get("boss", false)) else _mobs
		row.append([String(e["sprite"]), Loc.t("enemy." + String(e["id"]))])

	var city: Dictionary = _read_json("res://data/city.json")
	for tier in [1, 2, 3]:
		_buildings.append(["b:дом_жителей_ур%d" % tier,
				Loc.t("bld.house") + " ур%d" % tier])
	for b in city["buildings"]:
		var ref := String(b.get("sprite", ""))
		if ref.begins_with("k:"):
			continue   # схематичные (стены сегментами и пр.) на стенд не идут
		_buildings.append([ref, Loc.t(String(b["loc"]))])

	_hero_tex = Assets.tex("res://assets/sprites/hero/knight_Idle.png")
	_prepare_wave_rows()       # волна 2026-11-23: чудь/капище/кладбище/скалы
	_prepare_biome_patches()   # v1.76.3


## Волна 2026-11-23: ряды новой нарезки заказчика — чудь-данж, руины чуди,
## идолы богов (капище), реликвии, кладбище, скалы, деревья, звери.
func _prepare_wave_rows() -> void:
	_wave_rows.append({"title": Loc.t("stand.row_wave_chud"), "h": 64.0,
			"gap": 150.0, "items": [
		["e:chud_chest_closed", "сундук"], ["e:chud_chest_open", "открыт"],
		["e:chud_chest_carved", "резной"], ["e:chud_coins_bag", "монеты"],
		["e:chud_coins_pile", "горка"], ["e:chud_skulls_pile", "черепа"],
		["e:chud_idol_copper", "идол медный"], ["e:chud_idol_stone", "идол чуди"],
		["e:chud_stele_runed", "стела"], ["e:chud_key_bone", "ключ"],
		["e:chud_barrel", "бочка"], ["e:chud_crate", "ящик"],
		["e:chud_jug", "кувшин"], ["e:chud_candle", "свеча"],
		["e:chud_cage", "клетка"], ["e:chud_chain_hook", "цепь"],
		["e:chud_sarcophagus", "саркофаг"], ["e:chud_altar_bowl", "алтарь"],
		["e:chud_coffin_open", "гроб"], ["e:chud_web", "паутина"],
		["e:chud_rubble_small", "щебень"], ["e:chud_rubble_big", "обвал"]]})
	_wave_rows.append({"title": Loc.t("stand.row_wave_ruins"), "h": 110.0,
			"gap": 220.0, "items": [
		["e:chud_idol_wood", "идол древний"], ["e:chud_idol_copper_big", "медный"],
		["e:chud_idol_stone_big", "истукан"], ["e:chud_brazier_fire", "жаровня"],
		["e:chud_basin", "чаша"], ["e:chud_chest_old", "сундук старый"],
		["e:chud_sarc_stone", "саркофаг"], ["e:chud_grate", "решётка"],
		["e:chud_arch", "арка"], ["e:chud_logs_debris", "завал"],
		["e:rock_menhir", "менгир"], ["e:rock_spire", "столб"]]})
	_wave_rows.append({"title": Loc.t("stand.row_wave_idols"), "h": 120.0,
			"gap": 240.0, "items": [
		["e:idol_veles_a", "Велес"], ["e:idol_veles_b", "Велес II"],
		["e:idol_mokosh_a", "Мокошь"], ["e:idol_mokosh_b", "Мокошь II"],
		["e:idol_perun_a", "Перун"], ["e:idol_perun_b", "Перун II"]]})
	_wave_rows.append({"title": Loc.t("stand.row_wave_relics"), "h": 56.0,
			"gap": 130.0, "items": [
		["e:relic_potion_grace", "благодать"], ["e:relic_potion_rage", "ярость"],
		["e:relic_potion_stone", "камень"], ["e:relic_heart_vial", "сосуд"],
		["e:relic_feather", "перо"], ["e:relic_heart", "сердце"],
		["e:relic_dragon_harness", "упряжь"], ["e:relic_crown", "корона"],
		["e:relic_boat_charm", "ладья"], ["e:relic_horse_charm", "конь"]]})
	_wave_rows.append({"title": Loc.t("stand.row_wave_cemetery"), "h": 104.0,
			"gap": 190.0, "items": [
		["e:cem_fence", "ограда"], ["e:cem_gate", "ворота"], ["e:cem_willow", "ива"],
		["e:cem_grave_cross", "могила"], ["e:cem_grave_slab", "плита"],
		["e:cem_sarc", "саркофаг"], ["e:cem_grave_mound", "холмик"],
		["e:cem_cenotaph", "кенотаф"], ["e:cem_lamp", "фонарь"],
		["e:cem_skull_bowl", "чаша"]]})
	_wave_rows.append({"title": Loc.t("stand.row_wave_rocks"), "h": 92.0,
			"gap": 180.0, "items": [
		["e:rock_cliff", "утёс"], ["e:rock_big", "валун"],
		["e:rock_big_moss", "во мху"], ["e:rock_quartz", "кварц"],
		["e:rock_med", "камень"], ["e:rock_flat", "плитняк"],
		["e:rock_rubble", "осыпь"], ["e:rock_spire", "столб"],
		["e:rock_menhir", "менгир"], ["e:rock_arch", "арка"],
		["e:rock_steps", "ступени"]]})
	_wave_rows.append({"title": Loc.t("stand.row_wave_trees"), "h": 128.0,
			"gap": 230.0, "items": [
		["e:tree2_spruce", "ель"], ["e:tree2_birch2", "берёза"],
		["e:tree2_oak_old", "дуб"], ["e:tree2_snag", "сухостой"],
		["e:stump_fresh", "пень"], ["e:stump_mossy", "пень во мху"],
		["e:stump_split", "расколот"], ["e:snag_bent", "коряга"],
		["e:logs_stack", "поленница"], ["e:log_mossy", "мшистое"],
		["e:log_big", "бревно"]]})
	_wave_rows.append({"title": Loc.t("stand.row_wave_hive"), "h": 92.0,
			"gap": 170.0, "items": [
		["e:hive_1", "улей ур1"], ["e:hive_2", "улей ур2"],
		["e:hive_3", "улей ур3"], ["e:hive_cocoon", "кокон"],
		["e:hive_eggs", "кладка"], ["e:hive_sporocarp", "спороносец"],
		["e:hive_bones", "кости"], ["e:mold_1", "плесень 1"],
		["e:mold_2", "плесень 2"], ["e:mold_3", "плесень 3"],
		["e:mold_4", "плесень 4"], ["e:mold_burned_1", "выжжено"]]})
	_wave_rows.append({"title": Loc.t("stand.row_wave_animals"), "h": 42.0,
			"gap": 120.0, "items": [
		["e:an_deer_1", "олень"], ["e:an_boar_1", "кабан"],
		["e:an_wolf_1", "волк"], ["e:an_fox_1", "лиса"],
		["e:an_hare_1", "заяц"], ["e:an_bird_1", "птица"],
		["e:an_fish_1", "рыба"], ["e:an_toad_1", "жаба"],
		["e:an_bear_1", "медведь"], ["e:an_elk_1", "лось"],
		["e:wendigo_1", "виндиго"]]})


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## v1.76.3: галерея биомов — патч 20x20 тайлов на каждый биом заказчика:
## Превью-шум (как в композиторе/городе): тайлы раскладываются пятнами.
func _pv_hash(x: int, y: int, n: int) -> int:
	return absi(int((x * 73856093) ^ (y * 19349663) ^ (n * 83492791))) % 97


func _pv_noise(xf: float, yf: float, n: int) -> float:
	var x0 := int(floorf(xf))
	var y0 := int(floorf(yf))
	var fx := xf - float(x0)
	var fy := yf - float(y0)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := float(_pv_hash(x0, y0, n))
	var b := float(_pv_hash(x0 + 1, y0, n))
	var c := float(_pv_hash(x0, y0 + 1, n))
	var d := float(_pv_hash(x0 + 1, y0 + 1, n))
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


## земля (6 тайлов + подложки) запекается в ImageTexture один раз,
## река (3 тайла, меандр) рисуется живой анимацией полосы воды,
## деревья — 5 позиций из манифеста. Лето добавляется отдельной записью
## (его файлы лежат в env/summer, не в манифесте).
func _prepare_biome_patches() -> void:
	var mf: Dictionary = Assets.biome_manifest()
	var list: Array = []
	var summer := {
		"tag": "лето",
		"grass": [], "fill": [],
		"water": "res://assets/sprites/env/summer/fm_water_summer.png",
		"trees": ["e:tree2_summer_oak", "e:tree2_summer_pine",
				"e:tree2_summer_birch", "e:tree2_summer_willow",
				"e:tree2_summer_dead"],
	}
	for i in range(6):
		summer["grass"].append("res://assets/sprites/env/summer/grass_S%d.png" % (i + 1))
		summer["fill"].append("res://assets/sprites/env/summer/grass_S%d_fill.png" % (i + 1))
	list.append(summer)
	# v1.77.0: порядок — сезонные (композитор может подменить их
	# полем season), затем остальные по алфавиту манифеста
	var seen := {}
	var order: Array = []
	for ssn in ["spring", "autumn", "winter"]:
		var st := Assets.biome_tag_for_season(ssn)
		if st != "" and mf.has(st) and not seen.has(st):
			order.append(st)
			seen[st] = true
	for tag in mf.keys():
		if not seen.has(tag):
			order.append(String(tag))
			seen[tag] = true
	for tag in order:
		if not mf.has(tag):
			continue
		var e: Dictionary = mf[tag]
		var entry := {"tag": String(e.get("label", String(tag))), "grass": e.get("grass", []),
			"fill": [], "water": String(e.get("water", "")),
			"trees": e.get("trees", []), "grid": e.get("grid", [])}
		if bool(e.get("composed", false)):
			# v1.78.0: собранные в композиторе — рецепт на лету
			var uni := Assets.uniform_ground(e.get("grass", []))
			entry["gimgs"] = []
			for ut in uni[0]:
				entry["gimgs"].append((ut as Texture2D).get_image())
			entry["fimgs"] = []
			for ut2 in uni[1]:
				entry["fimgs"].append((ut2 as Texture2D).get_image())
		for gp in entry["grass"]:
			entry["fill"].append(String(gp).replace(".png", "_fill.png"))
		list.append(entry)
	var tiles := 20
	var img_cache: Dictionary = {}
	for entry in list:
		var img := Image.create(tiles * 32, tiles * 32, false, Image.FORMAT_RGBA8)
		var n_grass: int = (entry["grass"] as Array).size()
		# v1.78.8: нарисованная карта (grid 20×20) рисуется КАК ЕСТЬ —
		# что заказчик нарисовал, то стенд и город показывают
		var big_grid: Array = entry.get("grid", [])
		var use_grid: bool = (big_grid as Array).size() == tiles * tiles
		# v1.78.6 (для алгоритмических биомов): тайлы пятнами
		var fams := maxi(2, n_grass / 4)
		var per := maxi(1, n_grass / fams)
		for ty in range(tiles):
			for tx in range(tiles):
				var fi: int = -1
				if use_grid:
					fi = clampi(int(big_grid[ty * tiles + tx]), 0,
							maxi(0, n_grass - 1))
				else:
					var n_71: int = int(_pv_noise(tx / 6.0, ty / 6.0, 71))
					fi = mini(n_grass - 1,
							(absi(n_71) % fams) * per + _pv_hash(tx, ty, 97) % per)
				var fill_p := String(entry["fill"][fi]) if (entry["fill"] as Array).size() > 0 else ""
				if not img_cache.has(fill_p):
					var ft := Assets.tex(fill_p)
					img_cache[fill_p] = null if ft == null else ft.get_image()
				var fim: Image = img_cache[fill_p]
				if fim != null:
					img.blend_rect(fim, Rect2i(0, 0, 32, 32), Vector2i(tx * 32, ty * 32))
				var gim2: Image = null
				if (entry.get("gimgs", []) as Array).size() > 0:
					gim2 = entry["gimgs"][fi % (entry["gimgs"] as Array).size()]
					if gim2 != null:
						img.blend_rect(gim2, Rect2i(0, 0, 32, 32), Vector2i(tx * 32, ty * 32))
				var grass_p := String(entry["grass"][fi])
				if not img_cache.has(grass_p):
					var gt := Assets.tex(grass_p)
					img_cache[grass_p] = null if gt == null else gt.get_image()
				var gim: Image = img_cache[grass_p]
				if gim != null:
					img.blend_rect(gim, Rect2i(0, 0, 32, 32), Vector2i(tx * 32, ty * 32))
		entry["baked"] = ImageTexture.create_from_image(img)
		var cells: Array = []
		if entry["water"] != "" and Assets.tex(String(entry["water"])) != null:
			for tx in range(tiles):
				var yc := 8 + int(round(2.0 * sin(tx / 3.0)))
				for dy in 3:
					cells.append(Vector2i(tx, yc + dy))
		entry["cells"] = cells
		entry["spots"] = [Vector2i(3, 3), Vector2i(15, 4), Vector2i(4, 15),
				Vector2i(15, 15), Vector2i(9, 17)]
		_biome_patches.append(entry)
	print("stand: биом-патчей ", _biome_patches.size())


func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		_back_to_menu()
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(3.0, _zoom * 1.15)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(0.2, _zoom / 1.15)
	elif ev is InputEventMouseMotion and _drag:
		_cam -= ev.relative / _zoom


func _process(delta: float) -> void:
	_t += delta
	var v := 620.0 * delta / _zoom
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_cam.x -= v
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_cam.x += v
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_cam.y -= v
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_cam.y += v
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	# фон — тёмная земля «зола и дерево»
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.14, 0.13, 0.11))
	var to_screen := func(world: Vector2) -> Vector2:
		return (world - _cam) * _zoom + vp * 0.5

	# --- ряд 1: горожане (idle-анимация жителей) ---
	var row_y := 0.0
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 120.0),
			Loc.t("stand.row_villagers"))
	for i in range(_villagers.size()):
		var org := Vector2(i * VILL_SPACING, row_y)
		var pos: Vector2 = to_screen.call(org + Vector2(VILL_SPACING * 0.5, 40.0))
		Assets.draw_villager(self, String(_villagers[i][0]), "right",
				false, false, pos, _t + 0.13 * float(i), Color.WHITE, 2.0)
		_label(font, pos + Vector2(0, 46), String(_villagers[i][1]))

	# --- ряд 2: герой во ВСЕХ анимациях (v1.75.3) ---
	row_y += ROW_GAP
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 150.0),
			Loc.t("stand.row_hero"))
	var hero_anims := [
		["knight_Idle", 2.5, "Айдл"], ["knight_Run", 10.0, "Бег вбок"],
		["knight_RunUp", 12.0, "Бег вверх"], ["knight_RunDown", 6.0, "Бег вниз"],
		["knight_Attack", 8.0, "Атака"],
		["knight_Cast", 10.0, "Магия"], ["knight_Crouch", 8.0, "Крадучись"],
		["knight_Roll", 14.0, "Рывок"], ["knight_Hurt", 15.0, "Урон"],
		["knight_Death", 7.0, "Смерть"],
	]
	var hsp := 62.0 / 76.0   # фигура героя ~62px при жителе ~54 (2x игры)
	for i in range(hero_anims.size()):
		var spec: Array = hero_anims[i]
		var htex: Texture2D = Assets.tex(
				"res://assets/sprites/hero/%s.png" % String(spec[0]))
		if htex == null:
			continue
		var hn := int(htex.get_width()) / 120
		var f := int(_t * float(spec[1])) % maxi(1, hn)
		var hpos: Vector2 = to_screen.call(
				Vector2(150.0 + 220.0 * float(i), row_y + 60.0))
		var dst := Rect2(hpos - Vector2(60.0, 80.0 * hsp),
				Vector2(120.0 * hsp, 80.0 * hsp))
		draw_texture_rect_region(htex, dst,
				Rect2(float(f) * 120.0, 0, 120, 80))
		_label(font, hpos + Vector2(0, 30), String(spec[2]))

	# --- ряд 3: монстры (обычные) ---
	row_y += ROW_GAP
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 120.0),
			Loc.t("stand.row_mobs"))
	for i in range(_mobs.size()):
		var org := Vector2(i * MOB_SPACING, row_y)
		var pos: Vector2 = to_screen.call(org + Vector2(MOB_SPACING * 0.5, 60.0))
		Assets.draw_ref(self, String(_mobs[i][0]), pos, MOB_HEIGHT)
		_label(font, pos + Vector2(0, MOB_HEIGHT * 0.5 + 16.0),
				String(_mobs[i][1]))

	# --- ряд 4: боссы ---
	row_y += ROW_GAP
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 170.0),
			Loc.t("stand.row_bosses"))
	for i in range(_bosses.size()):
		var org := Vector2(i * BOSS_SPACING, row_y)
		var pos: Vector2 = to_screen.call(org + Vector2(BOSS_SPACING * 0.5, 90.0))
		Assets.draw_ref(self, String(_bosses[i][0]), pos, BOSS_HEIGHT)
		_label(font, pos + Vector2(0, BOSS_HEIGHT * 0.5 + 18.0),
				String(_bosses[i][1]))

	# --- ряд 5: здания ---
	row_y += ROW_GAP + 120.0
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, row_y - 220.0),
			Loc.t("stand.row_buildings"))
	for i in range(_buildings.size()):
		var org := Vector2(i * BLD_SPACING, row_y)
		var pos: Vector2 = to_screen.call(org + Vector2(BLD_SPACING * 0.5, 130.0))
		Assets.draw_ref(self, String(_buildings[i][0]), pos, BLD_HEIGHT)
		_label(font, pos + Vector2(0, BLD_HEIGHT * 0.5 + 18.0),
				String(_buildings[i][1]))

	# --- ряды 6+: волна 2026-11-23 — чудь-данж, капище, кладбище, скалы ---
	for wr: Dictionary in _wave_rows:
		row_y += ROW_GAP
		var wh := float(wr["h"])
		var wg := float(wr["gap"])
		_row_caption(font, to_screen,
				Vector2(-VILL_SPACING, row_y - 60.0 - wh), String(wr["title"]))
		var witems: Array = wr["items"]
		for i in range(witems.size()):
			var it: Array = witems[i]
			var worg := Vector2(float(i) * wg, row_y)
			var wpos: Vector2 = to_screen.call(
					worg + Vector2(wg * 0.5, wh * 0.5 + 24.0))
			Assets.draw_ref(self, String(it[0]), wpos, wh)
			_label(font, wpos + Vector2(0, wh * 0.5 + 16.0), String(it[1]))

	# --- ряд: БИОМЫ — патчи 20x20 с рекой и деревьями (v1.76.3) ---
	var by := row_y + 300.0
	_row_caption(font, to_screen, Vector2(-VILL_SPACING, by - 60.0),
			Loc.t("stand.row_biomes"))
	for i in range(_biome_patches.size()):
		var e: Dictionary = _biome_patches[i]
		var origin := Vector2(-VILL_SPACING + 30.0 + float(i % 2) * 700.0,
				by + float(i / 2) * 730.0)
		var corner: Vector2 = to_screen.call(origin)
		draw_texture_rect(e["baked"], Rect2(corner, Vector2(640, 640)), false)
		# река: живая анимация полосы воды (кадр по времени, вариант по y)
		var wtex: Texture2D = null
		if String(e["water"]) != "":
			wtex = Assets.tex(String(e["water"]))
		if wtex != null:
			var wf := int(_t * 3.0) % 6
			for c in e["cells"]:
				var vpx: Vector2 = to_screen.call(origin + Vector2(float(c.x * 32), float(c.y * 32)))
				draw_texture_rect_region(wtex, Rect2(vpx, Vector2(32, 32)),
						Rect2(float(wf) * 32.0, float(c.y % 3) * 32.0, 32.0, 32.0))
		# деревья из манифеста биома
		var trees: Array = e["trees"]
		if not trees.is_empty():
			for k in range(e["spots"].size()):
				var tp: Vector2i = e["spots"][k]
				var ref := String(trees[(i + k) % trees.size()])
				var base: Vector2 = origin + Vector2(float(tp.x * 32 + 16), float(tp.y * 32 + 30))
				Assets.draw_ref(self, ref, to_screen.call(base) + Vector2(0, -34), 100.0)
		_label(font, to_screen.call(origin + Vector2(320, 672)), String(e["tag"]))


func _row_caption(font: Font, to_screen: Callable, world: Vector2,
		text: String) -> void:
	var pos: Vector2 = to_screen.call(world)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(0.95, 0.8, 0.5))


func _label(font: Font, center: Vector2, text: String) -> void:
	var size := 12
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := center + Vector2(-w * 0.5, 0)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			Color(0.85, 0.85, 0.8))
