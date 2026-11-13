class_name SfxLib
extends Object
## Звук (v1.65, программа «Оживление» аспект 1 — ЗВУК-ФУНДАМЕНТ).
## Вся логика — СТАТИКА: вызовы SfxLib.play(...) безопасны в любом
## контексте (в headless-тестах автозагрузок нет — пул создаётся лениво
## под текущий SceneTree, headless-драйвер аудио молчит).
## Шины: Master / Music / SFX / UI / Ambient; громкости — user://audio_settings.json.
## Музыкальный директор (состояния/переходы/слои) — data/music.json +
## SfxLib.director_tick(delta, state), тикает из sfx_director.gd (автозагрузка).

const MANIFEST := "res://data/music.json"
const SETTINGS := "user://audio_settings.json"

static var _cfg: Dictionary = {}
static var _ready := false
static var _streams: Dictionary = {}      # путь -> AudioStreamWAV
static var _sfx_pool: Array = []
static var _music_a: AudioStreamPlayer = null
static var _music_b: AudioStreamPlayer = null
static var _music_active: AudioStreamPlayer = null
static var _music_track := ""
static var _fade_t := 1.0
static var _amb: AudioStreamPlayer = null
static var _amb_id := ""
static var _layers: Dictionary = {}       # id слоя -> AudioStreamPlayer
static var _layer_target: Dictionary = {}
static var _vol := {"Master": 1.0, "Music": 0.75, "SFX": 0.9, "UI": 0.8, "Ambient": 0.7}

## События города -> звук (роутер city_events.gd зовёт event()).
const EVENT_SFX := {
	"raid_warn": "alarm", "raid_start": "alarm", "raid_breached": "alarm",
	"built": "build_done", "quest_done": "quest_done", "wedding": "wedding",
	"birth": "birth", "tree_felled": "tree_fall", "morning_plan": "bell_day",
	"raid_repelled": "fanfare", "found_day": "wedding", "legend_joined": "fanfare",
	"hive_destroyed": "fanfare", "necro_revealed": "rune",
}


static func ensure() -> void:
	if _ready:
		return
	# шины
	for bus in ["Music", "SFX", "UI", "Ambient"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	# манифест
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		_cfg = parsed if parsed is Dictionary else {}
	f = null
	_load_settings()
	_apply_volumes()
	# игроки лениво под текущий root (headless: dummy-драйвер молчит)
	var root := _root()
	if root == null:
		return   # _ready остаётся false — ensure() повторится на следующем вызове
	# v1.65.1 фикс: во время _ready автозагрузки root занят setup детей —
	# прямой add_child ПРОВАЛИВАЕТСЯ ("Parent node is busy"), игроки
	# оставались вне дерева и всё молчало. Только call_deferred.
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		root.call_deferred("add_child", p)
		_sfx_pool.append(p)
	_music_a = _mk_player(root, "Music")
	_music_b = _mk_player(root, "Music")
	_music_active = _music_a
	_amb = _mk_player(root, "Ambient")
	# v1.65.1 фикс: «layers» в манифесте — МАССИВ id (было .keys() на массиве —
	# крэш ensure() посреди инициализации = полная тишина в игре)
	for layer_id in _cfg.get("layers", []):
		var lp := _mk_player(root, "Music")
		lp.volume_db = -60.0
		_layers[String(layer_id)] = lp
		_layer_target[String(layer_id)] = 0.0
	_ready = true


static func _mk_player(root: Node, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	root.call_deferred("add_child", p)   # v1.65.1: deferred (root busy при старте)
	return p


static func _root() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null


# --- эффекты -----------------------------------------------------------------

static func play(id: String, vol := 1.0) -> void:
	ensure()
	var sfx_list: Dictionary = _cfg.get("sfx", {})
	var def: Dictionary = sfx_list.get(id, {})
	var file := String(def.get("file", "assets/audio/sfx/%s.wav" % id))
	var stream := _stream(file, false)
	if stream == null or _root() == null:
		return
	var p: AudioStreamPlayer = null
	for cand in _sfx_pool:
		if not (cand as AudioStreamPlayer).playing:
			p = cand
			break
	if p == null:
		p = _sfx_pool[0]
	p.stream = stream
	p.volume_db = linear_to_db(clampf(float(def.get("vol", 1.0)) * vol * _vol.get("SFX", 0.9), 0.0, 1.0))
	p.pitch_scale = float(def.get("pitch", 1.0)) * (1.0 + randf_range(-0.04, 0.04))
	p.play()


## Звук городского события по его типу (неизвестные — молча).
static func event(ev_type: String) -> void:
	if EVENT_SFX.has(ev_type):
		play(String(EVENT_SFX[ev_type]))


# --- музыка: директор --------------------------------------------------------

## state: {"scene": "menu"|"city"|"dungeon"|"world", "night": bool,
## "raid": bool, "boss": bool, "dark_biome": bool, "busy": bool,
## "festival": bool, "amb": "day"|"night"|"dungeon"|"storm"}
static func director_tick(delta: float, state: Dictionary) -> void:
	ensure()
	if _cfg.is_empty() or _root() == null:
		return
	var track := track_for(state)
	if track != _music_track:
		_switch_music(track)
	_amb_tick(state)
	_layers_tick(state, delta)
	_fade_tick(delta)


## Карта состояние -> трек (чистая функция — тестируется headless).
## Ключ состояния выводится из scene/флагов (_state_key), приоритеты
## (boss > raid > ...) расписаны в data/music.json -> priority.
static func track_for(state: Dictionary) -> String:
	var key := _state_key(state)
	var states: Dictionary = _cfg.get("states", {})
	var prio: Dictionary = _cfg.get("priority", {})
	var best := "city_day"
	var best_p := -1
	for cand in ["menu", "boss", "raid", "dungeon_dark", "dungeon", "world",
			"city_festival", "city_night", "city_day"]:
		if cand != key:
			continue
		var p := int(prio.get(cand, 0))
		if p > best_p:
			best_p = p
			best = cand
	return String((states.get(best, {}) as Dictionary).get("music", "mus_city_day"))


static func _switch_music(track: String) -> void:
	if track == _music_track:
		return
	if _music_active == null or not _music_active.is_inside_tree():
		return   # v1.65.1: игроки добавляются deferred — вернёмся на след. тик
	_music_track = track
	var stream := _stream("assets/audio/music/%s.wav" % track, true)
	if stream == null:
		return
	# кроссфейд: новый в плеер B, старый угасает
	var idle := _music_b if _music_active == _music_a else _music_a
	var fade_out := _music_active
	idle.stream = stream
	idle.volume_db = -60.0
	idle.play()
	_music_active = idle
	_fade_t = 0.0
	_fade_tick(0.0)
	# угасающий глушим по завершении фейда (в _fade_tick)


static func _fade_tick(delta: float) -> void:
	var cross: float = float(_cfg.get("crossfade", 1.5))
	if _fade_t < 1.0:
		_fade_t = minf(1.0, _fade_t + delta / maxf(0.1, cross))
		var k := _fade_t
		if _music_active != null:
			_music_active.volume_db = linear_to_db(clampf(k, 0.02, 1.0) * _vol.get("Music", 0.75))
		var other := _music_b if _music_active == _music_a else _music_a
		if other != null and other.playing:
			other.volume_db = linear_to_db(clampf(1.0 - k, 0.0, 1.0) * _vol.get("Music", 0.75))
			if k >= 1.0:
				other.stop()
	else:
		if _music_active != null:
			_music_active.volume_db = linear_to_db(_vol.get("Music", 0.75))


static func _amb_tick(state: Dictionary) -> void:
	var want := String(state.get("amb", ""))
	if want == "":
		want = "dungeon" if String(state.get("scene", "")) == "dungeon" \
				else ("night" if bool(state.get("night", false)) else "day")
	var amb_list: Dictionary = _cfg.get("ambience", {})
	var file := String(amb_list.get(want, ""))
	if file == "":
		return
	if _amb_id != want:
		if _amb == null or not _amb.is_inside_tree():
			return   # v1.65.1: deferred — вернёмся на следующем тике
		_amb_id = want
		var stream := _stream("assets/audio/amb/%s" % file, true)
		if stream != null and _amb != null:
			_amb.stream = stream
			_amb.volume_db = linear_to_db(_vol.get("Ambient", 0.7))
			_amb.play()
	# тревога: слой барабанов поверх амбиента
	var raid_p: AudioStreamPlayer = _layers.get("raid_drums")
	if raid_p != null:
		var on := bool(state.get("raid", false))
		_layer_target["raid_drums"] = 0.8 if on else 0.0


static func _layers_tick(state: Dictionary, delta: float) -> void:
	# музыкальные слои состояния (busy/festival/boss/dark) + слои-таргеты
	var states: Dictionary = _cfg.get("states", {})
	var key := _state_key(state)
	var want: Dictionary = (states.get(key, {}) as Dictionary).get("layers", {})
	if bool(state.get("boss", false)) and key.begins_with("dungeon"):
		want = (states.get("boss", {}) as Dictionary).get("layers", {})
	for id in _layers:
		var target: float = float(_layer_target.get(id, 0.0))
		if want.has(id):
			target = maxf(target, 0.85)
		var p: AudioStreamPlayer = _layers[id]
		if not p.is_inside_tree():
			continue   # v1.65.1: deferred ещё не отработал
		if not p.playing:
			var stream := _stream("assets/audio/music/%s.wav" % id, true)
			if stream == null:
				continue
			p.stream = stream
			p.volume_db = -60.0
			p.play()
		var linear := clampf(db_to_linear(p.volume_db), 0.0, 1.0)
		linear = lerpf(linear, target, clampf(delta * 1.2, 0.0, 1.0))
		p.volume_db = linear_to_db(maxf(linear, 0.0001))
		if linear < 0.02 and target == 0.0:
			p.stop()
			p.volume_db = -60.0


static func _state_key(state: Dictionary) -> String:
	var scene := String(state.get("scene", "city"))
	if bool(state.get("boss", false)):
		return "boss"
	if bool(state.get("raid", false)):
		return "raid"
	if scene == "dungeon":
		return "dungeon_dark" if bool(state.get("dark_biome", false)) else "dungeon"
	if scene == "world":
		return "world"
	if scene == "menu":
		return "menu"
	if bool(state.get("festival", false)):
		return "city_festival"
	if bool(state.get("night", false)):
		return "city_night"
	return "city_day"


# --- потоки ------------------------------------------------------------------

## WAV из кэша; loop=true — дубликат с включённым зацикливанием.
static func _stream(path: String, loop: bool) -> AudioStreamWAV:
	var key := path + ("#loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var stream: AudioStreamWAV = null
	if ResourceLoader.exists(path):
		var loaded: Variant = load(path)
		stream = loaded if loaded is AudioStreamWAV else null
	if stream != null and loop:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_streams[key] = stream
	return _streams[key]


# --- громкость и настройки ---------------------------------------------------

static func set_bus_vol(bus: String, linear: float) -> void:
	ensure()
	_vol[bus] = clampf(linear, 0.0, 1.0)
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, _vol[bus])))
	save_settings()
	# активная музыка перетюнется на следующем _fade_tick


static func get_bus_vol(bus: String) -> float:
	ensure()
	return float(_vol.get(bus, 1.0))


static func save_settings() -> void:
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_vol))
		f.flush()
		f = null


static func _load_settings() -> void:
	# v1.65.1 фикс: пустой/битый файл (прерывание записи) — молча дефолты
	if not FileAccess.file_exists(SETTINGS):
		return
	var f := FileAccess.open(SETTINGS, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f = null
	if txt.strip_edges() == "":
		return
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		for k in (parsed as Dictionary):
			_vol[String(k)] = float(parsed[k])


static func _apply_volumes() -> void:
	for bus in _vol:
		var idx := AudioServer.get_bus_index(String(bus))
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, float(_vol[bus]))))
