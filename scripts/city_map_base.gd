# Часть: карта города — тайловые константы и вся память карты (grid, дороги,
# износ, вода, плато, A*).
# Структура v1.62.0: бывший city_map.gd (1432 строки) разрезан на
# extends-цепочку RefCounted (city_map_base -> city_map_gen -> city_map.gd) —
# это один класс, сцена/сим/сейв создают его по-прежнему через city_map.gd.
extends RefCounted

## Карта города (M2): тайлы травы/воды/скал/деревьев, аномалия-вход в данж.
## Чистая логика без сцены — тестируется headless. Пиксель-арт — этап M8.

const TILE_GRASS := 0
const TILE_WATER := 1
const TILE_ROCK := 2
const TILE_TREE := 3
const TILE_ORE := 4       # скала с железной рудой — под ней можно поставить шахту (M5+)
const TILE_DEADROCK := 5  # выработанный массив (правки v1.21): пустая порода/жилы —
const TILE_DEPOSIT := 7   # v1.56: месторождение регионального ресурса
                          # (медь/серебро/золото/янтарь) — добывается шахтой
const TILE_RUIN := 6      # v1.48: руины городской карты (куча древних камней,
                          # добывается как скала; лут-тайлы — ruin_loot)
                          # стоит на месте выработанной скалы, добывается шахтой

const TREE_SMALL := 1     # размеры деревьев (правки v1.21): малое/среднее/большое
const TREE_MEDIUM := 2
const TREE_LARGE := 3

var w := 0
var h := 0
var ts := 32
var ruin_loot: Dictionary = {}   # v1.48: лут-тайлы руин (Vector2i -> true)
var grid_ver := 0
var edited: Array = []        # v1.43: тайлы правок сетки — чанкам запечки
var edited_static: Array = [] # v1.52.2: тайлы правок НАДСТРОЕК (дороги/зоны/
                              # площадь) — инкремент духовки №2 (веб-фризы)


## Отметить правку сетки (для точечной перевыпечки чанка запечки).
func note_edit(t: Vector2i) -> void:
	if not edited.has(t):
		edited.append(t)


## Отметить правку надстроек (дорога/зона/площадь) — v1.52.2.
func note_edit_static(t: Vector2i) -> void:
	if not edited_static.has(t):
		edited_static.append(t)
		if edited_static.size() > 512:
			edited_static.pop_front()
	if edited.size() > 128:
		edited.pop_front()             # v1.28.1: версия масок воды/скал — инкремент при выработке породы
var grid: Array = []            # grid[y][x] -> TILE_*
var region_resource := "copper"   # v1.56: богатство локации (гарантирован)
var deposit_tiles := {}         # Vector2i -> true — клетки месторождения
var road := {}                  # Vector2i -> true: дороги (M6) — ускорение и приоритет путей
var wear := {}                  # Vector2i -> float: износ троп (M6) — город сам строит дороги там, где ходят
var rock_hp := {}               # Vector2i -> float: запас скалы (M11) — добыча истощает тайл
var stumps := {}                # Vector2i -> true: пни на месте срубленных деревьев (M11)
var saplings := {}              # Vector2i -> {t: float}: посаженные деревья, растут (M11)
var tree_size := {}             # Vector2i -> int (TREE_SMALL/MEDIUM/LARGE): размер дерева (v1.21)
var tree_growth := {}           # Vector2i -> float: дни роста дерева до следующего размера (v1.21)
var logs := {}                  # Vector2i -> {size: int}: поваленные брёвна на земле (v1.21.2) —
                                # герой валит, лесопилка подбирает и пилит
var bridges := {}               # Vector2i -> true: мосты через воду (M14-I)
var fords := {}                 # Vector2i -> true: мелководье-брод (v1.31)
var river_origin := {}          # Vector2i -> true: тайлы, нарисованные РЕКОЙ (v1.31.2)
var water_kind := {}            # Vector2i -> "lake"|"river"|"swamp" — тип водоёма
                                # для отрисовки (цвет воды, песчаная кромка)
var anomaly_tile := Vector2i.ZERO   # вход в данж (у аномалии)
var spawn_tile := Vector2i.ZERO     # старт героя и жителей
var world_exit_tile := Vector2i.ZERO  # край города — выход на карту мира (M8)
# Многоуровневый рельеф (№113–115): height — уровень тайла (0 равнина,
# 1 плато, 2 терраса выше), stairs — тайлы-проходы (лестницы) между
# уровнями. Отвес плато непроходим; единственный путь наверх — лестница.
var height := {}                # Vector2i -> int
var stairs := {}                # Vector2i -> true
var plateau_cfg := {}           # тюнинг рельефа (city.json → plateaus) — лифт и пр.
var astar = null                 # пути жителей/героя: ворота всегда проходимы
var astar_raider = null          # пути мутантов: закрытые ворота — стена (v1.26)


## Генерация по seed: детерминированная, связная (от старта достижимы все проходимые тайлы).
## v2 («Мир v2», этап 1): гидро-контекст клетки мира (world_map.city_hydro())
## решает, какие водоёмы есть в локации: река на глобальной клетке = река

const REGION_RESOURCES := {
	"copper": {"loc": "res.copper", "color": "#c87941"},
	"silver": {"loc": "res.silver", "color": "#d7dde3"},
	"gold": {"loc": "res.gold", "color": "#ffd54f"},
	"amber": {"loc": "res.amber", "color": "#e8963c"},
	"pearls": {"loc": "res.pearls", "color": "#ead9e8"},
	"fish_abound": {"loc": "res.fish_abound", "color": "#4dd0e1"},
}

var astar_ready := false   # v1.43: рёбра A* построены (лениво, первым запросом)

const BRIDGE_WEIGHT := 0.7

# --- заглушки для парсера (структура v1.62.0) ------------------------------
# Оркестраторы генерации зовут хелперы, живущие ниже по цепочке; реальные
# тела — там. Сигнатуры держите в синхроне (как в city_sim_base.gd).
func _connected() -> bool:
	return false

static func _roll_tree_size(roll: float) -> int:
	return 0

func _blob(center: Vector2i, radius: int, kind: int) -> void:
	pass

func in_bounds(p: Vector2i) -> bool:
	return false

func is_nature_walkable(p: Vector2i) -> bool:
	return false

func is_walkable(p: Vector2i) -> bool:
	return false

func ensure_astar() -> void:
	pass

func _setup_astar() -> void:
	pass

func _generate_river(rng: RandomNumberGenerator) -> void:
	pass

func _random_clear_tile(rng: RandomNumberGenerator, rad: int) -> Vector2i:
	return Vector2i(-1, -1)

func _lake_blob(center: Vector2i, rng: RandomNumberGenerator) -> void:
	pass

func _swamp_blob(center: Vector2i, rng: RandomNumberGenerator) -> void:
	pass

func _random_inner_tile(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(-1, -1)

func _ore_blob(center: Vector2i, radius: int) -> void:
	pass

func _clear_around(center: Vector2i, radius: int) -> void:
	pass

func _generate_plateaus(rng: RandomNumberGenerator, params: Dictionary) -> void:
	pass

func _plant_swamp_trees(centers: Array, rng: RandomNumberGenerator) -> void:
	pass

func _near_swamp_water(p: Vector2i) -> bool:
	return false

