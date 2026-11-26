# -*- coding: utf-8 -*-
"""v2.8 «Биомы мира»: полотна манифеста на суше биом-регионов карты мира.
- save_game_base.gd: REGION_CHARS/REGION_IDS — 6 новых регионов В КОНЦЕ
  (буквы a–d не сдвигаются, старые сейвы совместимы);
- world_map_gen.gd: правила мест обитания для новых регионов;
- world_view.gd: запека рисует сушу региона канвасом биома из манифеста;
- data/world.json: ключ biome у 4 старых + 6 новых регионов.
Запуск: python -I tools/patch_v280_biomes.py
"""
import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)


def read(p):
    with io.open(p, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(p, s):
    with io.open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)
    assert len(read(p)) > 0


def patch(p, old, new):
    s = read(p)
    nl = "\r\n" if "\r\n" in s else "\n"
    old_nl = old.replace("\n", nl)
    new_nl = new.replace("\n", nl)
    assert old_nl in s, "якорь не найден в %s: %r" % (p, old[:60])
    assert s.count(old_nl) == 1, "якорь неуникален в %s: %r" % (p, old[:60])
    write(p, s.replace(old_nl, new_nl))
    print("ok:", os.path.relpath(p, GAME), "(eol=%r)" % nl)


# 1) сейв: буквы регионов (только ДОПИСАТЬ в конец)
P = os.path.join(GAME, "scripts", "save_game_base.gd")
patch(P,
      'const REGION_CHARS := {"snow": "a", "volcanic": "b", "desert": "c", "dead": "d"}\n'
      'const REGION_IDS := {"a": "snow", "b": "volcanic", "c": "desert", "d": "dead"}',
      'const REGION_CHARS := {"snow": "a", "volcanic": "b", "desert": "c", "dead": "d",\n'
      '\t"steppe": "e", "birch": "f", "bloom": "g", "ancient": "h", "mystic": "i",\n'
      '\t"cursed": "j"}\n'
      'const REGION_IDS := {"a": "snow", "b": "volcanic", "c": "desert", "d": "dead",\n'
      '\t"e": "steppe", "f": "birch", "g": "bloom", "h": "ancient", "i": "mystic",\n'
      '\t"j": "cursed"}')

# 2) генерация: места обитания новых регионов (правила — в match по id)
P = os.path.join(GAME, "scripts", "world_map_gen.gd")
patch(P,
      '\t\t\t"dead":\n'
      '\t\t\t\tif mo > moist_thr and not _near_tile(p, TILE_WASTE, 3):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t_:\n'
      '\t\t\t\tpass',
      '\t\t\t"dead":\n'
      '\t\t\t\tif mo > moist_thr and not _near_tile(p, TILE_WASTE, 3):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t# v2.8 «Биомы мира»: шесть манифестных регионов\n'
      '\t\t\t"steppe":\n'
      '\t\t\t\tif mo > moist_thr or p.y < int(h * 0.25):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t"birch":\n'
      '\t\t\t\tif mo < 0.35 or mo > 0.8 or p.y < int(h * 0.12):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t"bloom":\n'
      '\t\t\t\tif mo < 0.6:\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t"ancient":\n'
      '\t\t\t\tif not _near_tile(p, TILE_FOREST, 2):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t"mystic":\n'
      '\t\t\t\tif not _near_tile(p, TILE_FOREST, 3):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t"cursed":\n'
      '\t\t\t\tif not _near_tile(p, TILE_WASTE, 3):\n'
      '\t\t\t\t\tcontinue\n'
      '\t\t\t_:\n'
      '\t\t\t\tpass')

# 3) запека мира: канвасы регионов + пиксельный проход
P = os.path.join(GAME, "scripts", "world_view.gd")
patch(P,
      '\tvar biomes: Dictionary = map.cfg.get("biomes", {})\n'
      '\tvar hill_thr := float(map.cfg.get("hydro", {}).get("hill_threshold", 0.62))',
      '\tvar biomes: Dictionary = map.cfg.get("biomes", {})\n'
      '\tvar hill_thr := float(map.cfg.get("hydro", {}).get("hill_threshold", 0.62))\n'
      '\t# v2.8 «Биомы мира»: суша региона с ключом biome рисуется КАНВАСОМ\n'
      '\t# биома из манифеста (полотно заказчика), не плоским цветом. Рельеф,\n'
      '\t# свет и скальные/снежные шапки ниже — общие; вода остаётся процедурной.\n'
      '\tvar rcv: Dictionary = {}\n'
      '\tvar bmf: Dictionary = Assets.biome_manifest()\n'
      '\tfor entry in map.cfg.get("regions", {}).get("list", []):\n'
      '\t\tvar btag := String((entry as Dictionary).get("biome", ""))\n'
      '\t\tif btag == "" or not bmf.has(btag):\n'
      '\t\t\tcontinue\n'
      '\t\tvar cvp := String((bmf[btag] as Dictionary).get("canvas", ""))\n'
      '\t\tvar ctex: Texture2D = Assets.tex(cvp) if cvp != "" else null\n'
      '\t\tif ctex != null:\n'
      '\t\t\trcv[String((entry as Dictionary).get("id", ""))] = ctex.get_image()')
patch(P,
      '\t\t\tvar base: Color = _bilinear_col(cols, fx, fy)\n'
      '\t\t\tvar wmk := clampf(_bilinear_f(wmask, fx, fy), 0.0, 1.0)',
      '\t\t\tvar base: Color = _bilinear_col(cols, fx, fy)\n'
      '\t\t\t# v2.8: пиксель суши региона с полотном — канвас биома (тайлится\n'
      '\t\t\t# по миру целиком, без швов набора); лес темнее, пепел серее\n'
      '\t\t\tvar ttx := clampi(int(floorf(fx + 0.5)), 0, map.w - 1)\n'
      '\t\t\tvar tty := clampi(int(floorf(fy + 0.5)), 0, map.h - 1)\n'
      '\t\t\tvar treg: String = map.region_at(Vector2i(ttx, tty)) if map.get("region") != null else ""\n'
      '\t\t\tif treg != "" and rcv.has(treg):\n'
      '\t\t\t\tvar cimg: Image = rcv[treg]\n'
      '\t\t\t\tvar tc: Color = cimg.get_pixel(\n'
      '\t\t\t\t\tint((fx + 0.5) * float(map.ts)) % cimg.get_width(),\n'
      '\t\t\t\t\tint((fy + 0.5) * float(map.ts)) % cimg.get_height())\n'
      '\t\t\t\tvar tkind: int = int(map.grid[tty][ttx])\n'
      '\t\t\t\tif tkind == map.TILE_FOREST:\n'
      '\t\t\t\t\ttc = tc.darkened(0.22)\n'
      '\t\t\t\telif tkind == map.TILE_WASTE:\n'
      '\t\t\t\t\ttc = tc.darkened(0.12).desaturated(0.15)\n'
      '\t\t\t\tbase = tc\n'
      '\t\t\tvar wmk := clampf(_bilinear_f(wmask, fx, fy), 0.0, 1.0)')

# 4) data/world.json: biome у старых 4 + 6 новых регионов
P = os.path.join(GAME, "data", "world.json")
wd = json.loads(read(P))
lst = wd["regions"]["list"]
BIOME_OF = {"snow": "зима", "volcanic": "огненные земли", "desert": "пустыня",
            "dead": "мёртвый лес"}
NEW = [
    {"id": "steppe", "count_min": 4, "count_max": 7, "radius": [9, 13],
     "cost_mult": 1.05, "moist_max": 0.45, "biome": "степи",
     "colors": {"plains": "#b8a95e", "forest": "#8a8442", "hills": "#a3915e", "waste": "#a89a66"}},
    {"id": "birch", "count_min": 3, "count_max": 5, "radius": [6, 9],
     "cost_mult": 1.0, "biome": "берёзовая роща",
     "colors": {"plains": "#7d9a52", "forest": "#5f7d3e", "hills": "#8a9a60", "waste": "#8f9660"}},
    {"id": "bloom", "count_min": 3, "count_max": 5, "radius": [6, 9],
     "cost_mult": 1.0, "biome": "цветущий край",
     "colors": {"plains": "#6fae4e", "forest": "#4d8a3a", "hills": "#7fa055", "waste": "#8aa05c"}},
    {"id": "ancient", "count_min": 3, "count_max": 6, "radius": [7, 11],
     "cost_mult": 1.1, "biome": "древний лес",
     "colors": {"plains": "#3c5e33", "forest": "#274223", "hills": "#4a5e3e", "waste": "#52604a"}},
    {"id": "mystic", "count_min": 1, "count_max": 2, "radius": [5, 8],
     "cost_mult": 1.15, "biome": "мистический лес",
     "colors": {"plains": "#3e5a6e", "forest": "#2a4054", "hills": "#4a5e6e", "waste": "#50606a"}},
    {"id": "cursed", "count_min": 2, "count_max": 4, "radius": [6, 10],
     "cost_mult": 1.25, "biome": "проклятый лес",
     "colors": {"plains": "#5a4a5e", "forest": "#3e3444", "hills": "#645460", "waste": "#655a62"}},
]
have = [str(e.get("id")) for e in lst]
for e in lst:
    i = str(e.get("id"))
    if i in BIOME_OF and "biome" not in e:
        e["biome"] = BIOME_OF[i]
for ne in NEW:
    if ne["id"] not in have:
        lst.append(ne)
wd["regions"]["_note"] = ("Мир v2 этап 2 (v1.40): режим моря — рандом мира; "
                          "биом-регионы красят сушу и дорожают путь. v2.8 «Биомы мира»: "
                          "каждый регион несёт biome — канвас из манифеста "
                          "(assets/sprites/env/biomes), запека рисует полотном. "
                          "Новые регионы только В КОНЕЦ списка — буквы сейва a–d не сдвигаются.")
write(P, json.dumps(wd, ensure_ascii=False, indent=2) + "\n")
print("ok: data/world.json — 4 biome + 6 новых регионов")

# 5) версия
P = os.path.join(GAME, "data", "version.json")
s = read(P)
assert '"version": "2.7.1"' in s
write(P, s.replace('"version": "2.7.1"', '"version": "2.8.0"'))
print("ok: data/version.json -> 2.8.0")

print("ПАТЧ v2.8 ГОТОВ")
