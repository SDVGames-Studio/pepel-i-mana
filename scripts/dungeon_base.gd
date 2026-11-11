# Часть: сцена данжа — прелоады, переменные, пауза, _ready, биом, _process,
# тьма и свет. Структура v1.62.0: бывший dungeon.gd (1337 строк) разрезан на
# extends-цепочку Node2D (dungeon_base -> dungeon_build -> dungeon.gd) — это
# один класс, сцена scenes/dungeon.tscn ссылается на dungeon.gd.
extends Node2D

## Сцена данжа-прототипа (M1): генерация, герой, враги, лут, мана-голод, HUD.
## Приёмка этапа: вошёл -> подрался -> собрал лут -> вернулся; смерть не завершает игру.

const DungeonGenScript := preload("res://scripts/dungeon_gen.gd")
const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const TrapScript := preload("res://scripts/trap.gd")
const ChestScript := preload("res://scripts/chest.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const ExitMarkerScript := preload("res://scripts/exit_marker.gd")
const DungeonViewScript := preload("res://scripts/dungeon_view.gd")
const HudScript := preload("res://scripts/hud.gd")
const SpellFxScript := preload("res://scripts/spell_fx.gd")
const CITY_CFG_PATH := "res://data/city.json"
const LOOT_CFG_PATH := "res://data/loot.json"

var params: Dictionary = {}
var biome: Dictionary = {}        # активный биом (M5: руины или лес-мутант)
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
var _zones: Array = []            # зоны «Терновых шипов»: {pos, radius, until, acc, dps}
var _zone_time := 0.0
var _darkness: CanvasModulate = null    # общий свет данжа: светлеет по мере убийств
var _ambient_base := Color.WHITE        # исходная тьма биома
var _enemies_total := 0                 # монстров на входе в данж (для подсветки)
var _pause_layer: CanvasLayer = null   # пауза данжа (M9, Esc)
var _pause_overlay = null
var _equip_panel = null                # панель экипировки (M14-B, клавиша I)
var _fog = null                        # туман войны (v1.33, dungeon_fog.gd)
var _visible_now: Dictionary = {}      # полы в поле зрения героя сейчас


## Пауза данжа (M9): Esc — вуаль + «Продолжить / В меню».
## Сначала Esc закрывает открытые окна (фидбек заказчика): экипировка,
## инвентарь; и только затем — пауза.
func _toggle_pause() -> void:
	if get_tree().paused:
		return  # закрытие оверлея делает сам оверлей (ALWAYS)
	if _equip_panel != null and _equip_panel.is_open():
		_equip_panel.close()
		return
	if hud.inventory_visible():
		hud.toggle_inventory()
		return
	_pause_overlay.open()


func _build_pause() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 50
	add_child(_pause_layer)
	_pause_overlay = load("res://scripts/pause_overlay.gd").new()
	# данжи транзитны (M14-A): середина данжа не сохраняется — честно говорим
	_pause_overlay.allow_save = false
	_pause_overlay.hint = Loc.t("save.dungeon_hint")
	_pause_layer.add_child(_pause_overlay)


func _ready() -> void:
	Game.in_dungeon = true   # в данже автосейва нет (транзитность, M14-A)
	params = _read_json("res://data/dungeon.json")
	enemies_data = _read_json("res://data/enemies.json")
	loot_data = _read_json(LOOT_CFG_PATH)
	ts = int(params["tile_size"])
	_seed_value = int(Time.get_unix_time_from_system())
	_rng.seed = _seed_value
	_loot_rng.seed = _seed_value + 1
	# локация карты мира (M8): руины и лагеря меньше полноценного данжа
	if Game.dungeon_scale < 1.0:
		params = params.duplicate(true)
		for key in ["max_rooms", "enemy_count", "chest_count", "crystal_count"]:
			params[key] = maxi(1, int(round(float(params[key]) * Game.dungeon_scale)))
		params["traps"]["count"] = maxi(1, int(round(float(params["traps"]["count"]) * Game.dungeon_scale)))
	biome = _pick_biome()
	# кодекс (M14-K): биом открыт
	Game.codex_seen("biomes", _biome_id())

	gen = DungeonGenScript.new()
	gen.generate(_seed_value, params)

	_build_darkness()
	add_child(_make_view())
	# страховка «пропавших тайлов» (v1.33.3, как у города v1.30.1): первый
	# _draw dungeon_view изредка сгорает впустую в кадре сборки сцены —
	# тогда виден только чёрный войд и герой без пола. Перерисовываем
	# слой отложенно ещё два кадра подряд (дёшево, ~2k команд).
	_view_redraw_guard()
	_ensure_dungeon_astar()   # v1.46: сетка путей врагов
	# «Данжи v2» (v1.42): декали (мох/порча/трещины/пропсы) и живой свет
	# (жаровни + холодные лужи + свечение порчи) по референсам этапа 4
	var v2: Dictionary = params.get("v2", {})
	var decals = load("res://scripts/dungeon_decals.gd").new()
	decals.setup(gen, ts, biome, v2)
	add_child(decals)
	# свет/вода/руны ДО героя (порядок канвы: всё на полу — под героем,
	# v1.42.2: «текстуры воды должны быть под персонажем»)
	_build_lights(v2)
	_build_runes(v2)
	_build_walls()
	_build_exit()
	_build_chests()
	_build_crystals()
	_build_hero()
	_build_enemies()
	_build_traps()
	_build_boss()
	_build_fauna()
	# туман войны (v1.33): поверх мира, до HUD — неисследованное чёрное,
	# изученное приглушено, видимое в свет герой — чистое
	_fog = load("res://scripts/dungeon_fog.gd").new()
	_fog.setup(gen, ts)
	add_child(_fog)
	# сколько монстров было на входе: по доле убитых данж светлеет (2026-10-21)
	_enemies_total = get_tree().get_nodes_in_group("enemies").size()

	hud = HudScript.new()
	hud.init(hero, gen, loot_data)
	# v1.33: HUD — CanvasLayer, рисуется выше тумана войны (z=40 в базовой
	# канве) автоматически, без z_index (у CanvasLayer его нет)
	add_child(hud)
	hud.minimap.setup(gen)
	_build_pause()
	# панель экипировки (M14-B, клавиша I): слоты, рюкзак, свитки/зелья
	_equip_panel = load("res://scripts/equipment_panel.gd").new()
	_equip_panel.hero_cb = func(): return hero
	_equip_panel.toast_cb = func(msg: String) -> void: hud.toast(msg)
	_equip_panel.on_change = _apply_equipment
	_equip_panel.cast_scroll_cb = _cast_scroll
	add_child(_equip_panel)
	# дикий регион: посещение леса-мутанта добавляет городу загрязнения (M5)
	var pol := float(biome.get("pollution_on_visit", 0.0))
	if pol > 0.0 and Game.city_sim != null:
		Game.city_sim.add_pollution(pol)


## Биом данжа по весам (M5): руины спокойнее, лес-мутант опаснее и жирнее.
## Точка интереса карты мира задаёт биом сама (M8); городская аномалия — как раньше.
func _pick_biome() -> Dictionary:
	var biomes: Dictionary = params.get("biomes", {})
	if Game.forced_biome != "" and biomes.has(Game.forced_biome):
		return biomes[Game.forced_biome]
	var weights: Dictionary = params.get("biome_weights", {})
	var total := 0
	for w: int in weights.values():
		total += w
	var roll := _rng.randi_range(1, maxi(1, total))
	for id in weights:
		roll -= int(weights[id])
		if roll <= 0 and biomes.has(id):
			return biomes[id]
	return biomes.get("ruins", params.get("biome", {}))


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_toggle_pause()
	if get_tree().paused or hero.dead:
		return
	_zone_time += delta
	_update_zones()
	_update_fog()
	_update_mana_hunger(delta)
	_update_hint()
	hud.refresh()
	# v1.46: скрытность качается в темноте рядом с врагами
	var moving: bool = hero != null and hero.velocity.length() > 5.0
	var near_enemy := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and int(e["hp"]) > 0 \
				and e.global_position.distance_to(hero.position) < 300.0:
			near_enemy = true
			break
	hero.train_stealth_if_dark(near_enemy, moving, delta)
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	if Input.is_action_just_pressed("inventory"):
		hud.toggle_inventory()


func _unhandled_input(event: InputEvent) -> void:
	# панель экипировки (M14-B): клавиша I
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_I:
		_equip_panel.toggle()
		get_viewport().set_input_as_handled()
		return
	# v1.46: фонарь (скрытность) — клавиша T
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_T:
		hero.toggle_lantern()
		hud.toast(Loc.t("dungeon.lantern_off" if not hero.lantern_on
				else "dungeon.lantern_on"))
		get_viewport().set_input_as_handled()
		return
	# слоты заклинаний 1–9 (спеллбук, порядок изучения; с M5 — 9 боевых школ-заклинаний)
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.physical_keycode:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
			KEY_4: idx = 3
			KEY_5: idx = 4
			KEY_6: idx = 5
			KEY_7: idx = 6
			KEY_8: idx = 7
			KEY_9: idx = 8
		if idx >= 0 and idx < Game.spellbook.size():
			_cast_spell(String(Game.spellbook[idx]))


func _tile_to_pos(tile: Vector2i) -> Vector2:
	return Vector2(tile) * float(ts) + Vector2(ts, ts) / 2.0


func _pos_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i((pos / float(ts)).floor())


## Тьма: весь данж гасится, видимость даёт только фонарь героя (hero.make_light).
## Правка 2026-10-21: с каждым убитым монстром данж светлеет — к финалу видно всё.
func _build_darkness() -> void:
	var dark := CanvasModulate.new()
	dark.name = "Darkness"
	# v1.33.1 (заказчик: «до этого был приятный РЕАЛИСТИЧНЫЙ свет»):
	# база данжа снова ТЁМНАЯ «тусклая луна» (эфф. ~0.53) — атмосферу даёт
	# тёплый фонарь героя с настоящими тенями от стен. В отличие от v1.30.1,
	# когда на такой базе тёмные тайлы биома сливались в черноту (стены
	# rgb(29,23,22)), теперь материалы полов/стен яркие (v1.33: камень,
	# кирпич, земля, кристалл) — в свете фонаря они читаются во всех
	# красках, вне света — тёмные, но узнаваемые. Войд остаётся чёрным.
	_ambient_base = Color(String(biome["ambient"])).lerp(
			Color(0.62, 0.62, 0.70), 0.80)
	dark.color = _ambient_base
	_darkness = dark
	add_child(dark)


## Чистая математика подсветки (для тестов): доля убитых 0..1 лерпит исходную
## тьму биома к светлому цвету clear_light с силой power.
static func bright_ambient(base: Color, killed_frac: float, lcfg: Dictionary) -> Color:
	var target := Color(String(lcfg.get("color", "#7a7a8c")))
	var power := clampf(float(lcfg.get("power", 0.9)), 0.0, 1.0)
	return base.lerp(target, clampf(killed_frac, 0.0, 1.0) * power)


## Пересчитать общий свет: чем больше монстров убито, тем светлее данж.
func _apply_clear_light() -> void:
	if _darkness == null or _enemies_total <= 0:
		return
	var alive := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and int(e["hp"]) > 0:
			alive += 1
	var killed_frac := 1.0 - float(alive) / float(_enemies_total)
	_darkness.color = bright_ambient(_ambient_base, killed_frac,
			params.get("clear_light", {}))


## Ночное усиление нечисти (v1.30, док 14): ночь города и тьма данжа до
## зачистки. Чистая формула — enemy.night_mult (тесты).
func night_boost() -> float:
	var is_night := false
	var cs = Game.city_sim
	if cs != null and cs.cfg != null:
		var dl := maxf(0.1, float(cs.cfg.get("day_length", 120.0)))
		var nf := clampf(float(cs.cfg.get("night_fraction", 0.3)), 0.0, 0.9)
		is_night = fmod(maxf(float(cs.time), 0.0), dl) >= dl * (1.0 - nf)
	var dark_frac := 1.0
	if _enemies_total > 0:
		var alive := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and int(e["hp"]) > 0:
				alive += 1
		dark_frac = float(alive) / float(_enemies_total)
	return EnemyScript.night_mult(is_night, dark_frac)


func _make_view() -> Node2D:
	var view = DungeonViewScript.new()
	view.setup(gen, ts, biome)
	return view


## «Данжи v2»: факелы/лужи/порча — живой свет поверх мира (dungeon_lights.gd).
## v1.42.1: факелы — только в биомах с живыми гуманоидами (biomes.humanoids).
var _lights: Node2D = null


func _build_lights(v2: Dictionary) -> void:
	_lights = load("res://scripts/dungeon_lights.gd").new()
	_lights.setup(gen, ts, v2, biome)
	add_child(_lights)


## «Данжи v2»: рунные круги — интерактивные точки (dungeon_rune.gd).
func _build_runes(v2: Dictionary) -> void:
	var rune_script: Script = load("res://scripts/dungeon_rune.gd")
	var school := "wild"
	if Game.magic != null:
		school = String(Game.magic.cfg.get("hero_school", "wild"))
	var col: Color = Game.magic.school_color(school) if Game.magic != null \
			else Color(0.62, 0.78, 1.0)
	for tile: Vector2i in gen.rune_spawns:
		var rune = rune_script.new()
		rune.setup(col, float(ts) * 1.6)
		rune.position = _tile_to_pos(tile)
		rune.add_to_group("dungeon_runes")
		add_child(rune)


## Отложенная переприсовка слоя тайлов: страховка от «сгоревшего» первого
## кадра (v1.33.3). _view хранится для повторных queue_redraw.
var _view: Node2D = null


func _view_redraw_guard() -> void:
	_view = get_child(get_child_count() - 1)
	_view.queue_redraw.call_deferred()
	_redraw_guard_2()


func _redraw_guard_2() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_view):
		_view.queue_redraw()


## Стены: один StaticBody2D, горизонтальные цепочки стен слеплены в один прямоугольник.
## Тени (v1.33.3): окклюдер — ПОШТУЧНО на каждый тайл стены (общий ресурс
## полигона). Слитые в ряд «полосы» на всю ширину глючили: стоило фонарю
## оказаться вплотную к такой огромной коробке — экструзия тени накрывала
## всю лужу света (свет «глох» в узких местах, замерено в v1.33.3).
## Коллизии оставлены слитыми (физике это только в плюс).

# --- заглушки для парсера (структура v1.62.0) ------------------------------
# Цепочка частей одного класса: часть выше зовёт функции, живущие ниже —
# парсеру нужны сигнатуры (как в city_sim_base.gd). Реальные тела — в частях
# ниже; в рантайме виртуальная диспетчеризация зовёт их. Сигнатуры в синхроне.
func _build_walls() -> void:
	pass

func _build_exit() -> void:
	pass

func _build_chests() -> void:
	pass

func _build_crystals() -> void:
	pass

func _build_hero() -> void:
	pass

func _apply_equipment() -> void:
	pass

func _build_enemies() -> void:
	pass

func _build_fauna() -> void:
	pass

func _build_traps() -> void:
	pass

func _build_boss() -> void:
	pass

func _biome_id() -> String:
	return ""

func _cast_spell(spell_id: String, free_cast := false) -> void:
	pass

func _on_enemy_died(enemy) -> void:
	pass

func _on_pickup_collected(pickup) -> void:
	pass

func _on_hero_died() -> void:
	pass

func _on_boss_died(enemy) -> void:
	pass

func _update_zones() -> void:
	pass

func _update_mana_hunger(delta: float) -> void:
	pass

func _update_hint() -> void:
	pass

func _update_fog() -> void:
	pass

func _ensure_dungeon_astar() -> void:
	pass

func _try_interact() -> void:
	pass

## Свитки героя: ссылка на метод уходит колбэком в панель экипировки (v1.49).
func _cast_scroll(item_id: String) -> String:
	return ""

func _read_json(path: String) -> Variant:
	return null

func _add_fx(kind: String, col: Color, radius: float, duration: float,
		pos: Vector2, points: PackedVector2Array = PackedVector2Array()) -> void:
	pass
