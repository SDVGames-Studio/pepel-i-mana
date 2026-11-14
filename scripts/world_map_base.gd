# Часть: карта мира — тайловые константы и вся память карты (grid, высоты,
# река, регионы, POI, туман, эпицентр, A*).
# Структура v1.62.0: бывший world_map.gd (1012 строк) разрезан на
# extends-цепочку RefCounted (world_map_base -> world_map_gen -> world_map.gd) —
# это один класс, мир создаёт его по-прежнему через world_map.gd.
extends RefCounted

## Карта мира (M8): процедурная по сиду, биомы цветом, точки интереса (POI),
## туман войны, старые дороги. Чистая логика без сцены — тестируется headless.
## Город игрока — стартовая локация; от него герой выходит на карту и входит назад.
##
## Тайл: 0 равнина, 1 вода (непроходима), 2 лес, 3 холмы, 4 пепел, 5 старая дорога.
## POI: {id, kind, biome, faction, tile, discovered, strength, state,
##       cleared_day, used} — kind: city|dungeon|ruins|camp|settlement|
##       caravan|obelisk; biome — биом данжа из dungeon.json ("" у городской
##       аномалии, она выбирает биом как раньше); faction — traders|bandits|cult.
##
## Гидрология («Мир v2», этап 1): карта высот (наклон N→S + шум) → скалы
## на севере, океан на юге + внутренние моря, реки из скал к морю (жадный
## спуск + меандр), озёра/болота по влажности. Река — ОВЕРЛЕЙ (river):
## тайл остаётся сушей и проходим (брод), но дороже; grid-вода (море/озёра)
## непроходима, как раньше. Клетка города несёт свои водоёмы в локацию
## города — city_hydro() (река на глобале = река в городе, ответ №117).

const TILE_PLAINS := 0
const TILE_WATER := 1
const TILE_FOREST := 2
const TILE_HILL := 3
const TILE_WASTE := 4
const TILE_ROAD := 5
const TILE_SWAMP := 6   # болото (M14-I): проходимо, но дорого — замедление

var w := 0
var h := 0
var ts := 32
var cfg: Dictionary = {}
var grid: Array = []
var height: Array = []          # высоты 0..1 (гидрология) — по строкам, как grid
var river: Dictionary = {}      # Vector2i -> true: русло (оверлей, проходим)
var water_kind: Dictionary = {} # Vector2i -> "sea"|"lake": тип grid-воды
var region: Dictionary = {}     # Vector2i -> String: биом-регион («Мир v2»
                                # этап 2, v1.40): "snow"|"volcanic"|"desert"|
                                # "dead" — перекрашивает сушу и дорожает путь
var sea_mode := "both"          # рандом мира (№118): "ocean" — океан у южного
                                # края, "inner" — только внутренние моря,
                                # "both" — и то и другое
var city_tile := Vector2i.ZERO      # город игрока — стартовая локация
var gen_seed := 0                   # сид генерации: города НПС сидируются от него
var pois: Array = []                # точки интереса, см. шапку
var fog: Dictionary = {}            # Vector2i -> true: исследованные тайлы
var fog_ver := 0                    # счётчик раскрытий (совместимость)
var fog_new: Array = []             # v1.40.2: тайлы, раскрытые ПОСЛЕДНИМ
                                    # reveal_around — view стирает их из
                                    # текстуры тумана (дёшево, без перепечки)
var astar: AStarGrid2D = null
var astar_ready := false   # v1.68: сетка строится первым запросом пути (848 мс на старте)
# v1.45 («Новый мир v2» этап 3): эпицентр магической катастрофы — выбросы
# раз в ~25 дней (магзагрязнение вокруг, усиление данжей/мутантов/магтварей),
# рядом — лагерь ИСКАЖЁННЫХ магией: растёт, нападает на поселения
var epicenter: Dictionary = {}   # {tile, radius, next_event_day, power, eruption_days}
var boats_enabled := false   # лодки (M14-I): вода проходима, но медленна
var _terrain_bake = null     # v1.35.1: кэш запечённого рельефа (world_view.gd)
var _rng := RandomNumberGenerator.new()
var _poi_id := 1


## Генерация по сиду: детерминированная (тот же сид — та же карта и POI).

static func _smooth_step(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


var _moist: Array = []   # влажность 0..1+, по строкам

# --- заглушки для парсера (структура v1.62.0) ------------------------------
# Оркестраторы генерации зовут хелперы, живущие ниже по цепочке; реальные
# тела — там. Сигнатуры держите в синхроне (как в city_sim_base.gd).
func in_bounds(p: Vector2i) -> bool:
	return false

func is_walkable(p: Vector2i) -> bool:
	return false

func _blob(center: Vector2i, radius: int, kind: int) -> void:
	pass

func _clear_around_land(center: Vector2i, radius: int) -> void:
	pass

func _random_inner_tile() -> Vector2i:
	return Vector2i(-1, -1)

func _swamp_blob(center: Vector2i, radius: int) -> void:
	pass

func _place_pois(params: Dictionary) -> void:
	pass

func _poi_near(tile: Vector2i, radius: float):
	pass

func _pois_ok() -> bool:
	return false

func _setup_fog() -> void:
	pass

func _place_epicenter() -> void:
	pass

func _setup_astar() -> void:
	pass

func _draw_roads() -> void:
	pass

