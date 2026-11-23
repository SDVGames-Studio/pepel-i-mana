#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# [REUSE] Волна 2026-11-23: проводка нарезанных блобов в финальные имена
# (assets/sprites/env/*, плоско — под реф "e:<имя>"). Где ещё применимо:
# следующая волна ассетов — свои пары (лист/NN.png -> имя).
# Пак данжа d5 (руины чуди): тайлы ужимаются до 32x32, кромки — затемнение.
import os
import shutil

from PIL import Image

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
W = os.path.join(BASE, "assets", "sprites", "wave1123")
ENV = os.path.join(BASE, "assets", "sprites", "env")
BLD = os.path.join(BASE, "assets", "sprites", "buildings")
TS = 32

# (источник относительно W, имя в env/ или спец-путь)
COPY = [
    # чудь-данж: сокровища и утварь (декор данжей)
    ("chud_treasures/01.png", "chud_chest_closed"),
    ("chud_treasures/02.png", "chud_chest_open"),
    ("chud_treasures/03.png", "chud_chest_carved"),
    ("chud_treasures/04.png", "chud_coins_bag"),
    ("chud_treasures/05.png", "chud_coins_pile"),
    ("chud_treasures/06.png", "chud_skulls_pile"),
    ("chud_treasures/08.png", "chud_idol_copper"),
    ("chud_treasures/09.png", "chud_idol_stone"),
    ("chud_treasures/10.png", "chud_stele_runed"),
    ("chud_treasures/11.png", "chud_key_bone"),
    ("chud_treasures/12.png", "chud_barrel"),
    ("chud_treasures/13.png", "chud_crate"),
    ("chud_treasures/14.png", "chud_jug"),
    ("chud_treasures/15.png", "chud_candle"),
    ("chud_treasures/16.png", "chud_cage"),
    ("chud_treasures/17.png", "chud_chain_hook"),
    ("chud_treasures/18.png", "chud_sarcophagus"),
    ("chud_treasures/19.png", "chud_altar_bowl"),
    ("chud_treasures/20.png", "chud_coffin_open"),
    ("chud_treasures/21.png", "chud_web"),
    ("chud_treasures/22.png", "chud_rubble_small"),
    ("chud_treasures/23.png", "chud_rubble_big"),
    # реликвии-лут (ЛУТ-2 заказчика, 1:1 по items.json)
    ("chud_relics/01.png", "relic_potion_grace"),
    ("chud_relics/02.png", "relic_potion_rage"),
    ("chud_relics/03.png", "relic_potion_stone"),
    ("chud_relics/04.png", "relic_heart_vial"),
    ("chud_relics/05.png", "relic_feather"),
    ("chud_relics/06.png", "relic_heart"),
    ("chud_relics/07.png", "relic_dragon_harness"),
    ("chud_relics/08.png", "relic_crown"),
    ("chud_relics/09.png", "relic_boat_charm"),
    ("chud_relics/10.png", "relic_horse_charm"),
    # руины чуди: крупный декор данжа
    ("chud_ruins/05.png", "chud_mushrooms"),
    ("chud_ruins/20.png", "chud_bones"),
    ("chud_ruins/26.png", "chud_jugs"),
    ("chud_ruins/27.png", "chud_candles"),
    ("chud_ruins/18.png", "chud_idol_wood"),
    ("chud_ruins/19.png", "chud_idol_copper_big"),
    ("chud_ruins/21.png", "chud_brazier_fire"),
    ("chud_ruins/22.png", "chud_idol_stone_big"),
    ("chud_ruins/23.png", "chud_sarc_stone"),
    ("chud_ruins/25.png", "chud_basin"),
    ("chud_ruins/28.png", "chud_grate"),
    ("chud_ruins/29.png", "chud_chest_old"),
    ("chud_ruins/16.png", "chud_arch"),
    ("chud_ruins/24.png", "chud_logs_debris"),
    # идолы богов (капище): Велес/Мокошь/Перун по 2 варианта
    ("idols/01.png", "idol_veles_a"),
    ("idols/02.png", "idol_mokosh_a"),
    ("idols/03.png", "idol_perun_a"),
    ("idols/04.png", "idol_veles_b"),
    ("idols/05.png", "idol_mokosh_b"),
    ("idols/06.png", "idol_perun_b"),
    # скалы и камни
    ("rocks/01.png", "rock_cliff"),
    ("rocks/02.png", "rock_big"),
    ("rocks/03.png", "rock_big_moss"),
    ("rocks/04.png", "rock_quartz"),
    ("rocks/06.png", "rock_med"),
    ("rocks/07.png", "rock_flat"),
    ("rocks/09.png", "rock_rubble"),
    ("rocks/11.png", "rock_spire"),
    ("rocks/12.png", "rock_menhir"),
    ("rocks/13.png", "rock_arch"),
    ("rocks/14.png", "rock_steps"),
    # кладбище: пропсы + здание из склепа
    ("cemetery/01.png", "cem_fence"),
    ("cemetery/02.png", "cem_gate"),
    ("cemetery/03.png", "cem_willow"),
    ("cemetery/04.png", "cem_grave_cross"),
    ("cemetery/05.png", "cem_grave_slab"),
    ("cemetery/06.png", "cem_sarc"),
    ("cemetery/07.png", "cem_grave_mound"),
    ("cemetery/09.png", "cem_cenotaph"),
    ("cemetery/10.png", "cem_lamp"),
    ("cemetery/11.png", "cem_skull_bowl"),
    ("cemetery/08.png", "@cemetery"),
    # деревья, пни, брёвна
    ("trees_logs_a/01.png", "tree2_spruce"),
    ("trees_logs_a/02.png", "tree2_birch2"),
    ("trees_logs_a/03.png", "tree2_oak_old"),
    ("trees_logs_a/04.png", "tree2_snag"),
    ("trees_logs_a/05.png", "stump_fresh"),
    ("trees_logs_a/06.png", "stump_mossy"),
    ("trees_logs_a/07.png", "stump_split"),
    ("trees_logs_a/08.png", "snag_bent"),
    ("trees_logs_a/09.png", "logs_stack"),
    ("trees_logs_a/10.png", "log_mossy"),
    ("trees_logs_a/11.png", "log_big"),
]

# звери: кадры [айдл x2, бег x4] (рыба/жаба — [айдл x2, бег x2])
ANIMALS = {
    "deer": 6, "boar": 6, "wolf": 6, "fox": 6, "hare": 6, "bird": 6,
    "fish": 4, "toad": 4,
}


def save_env(src_path: str, name: str) -> None:
    dst = os.path.join(ENV, name + ".png")
    shutil.copyfile(src_path, dst)
    print("env/%s.png" % name)


def main() -> None:
    for rel, name in COPY:
        src = os.path.join(W, rel)
        if not os.path.isfile(src):
            print("!! нет: %s" % rel)
            continue
        if name.startswith("@"):
            shutil.copyfile(src, os.path.join(BLD, name[1:] + ".png"))
            print("buildings/%s.png" % name[1:])
        else:
            save_env(src, name)
    # звери: an_<вид>_<n>.png
    for kind, n in ANIMALS.items():
        for i in range(1, n + 1):
            src = os.path.join(W, "wildlife", "%02d.png" % i)
            # wildlife-лист нарезан по порядку рядов: кадры вида подряд
            # (олень 01-06, кабан 07-12, ... см. контакт-лист)
    # вручную ниже — офсеты каждого вида в wildlife
    offs = {"deer": 1, "boar": 7, "wolf": 13, "fox": 19, "hare": 25,
            "bird": 31, "fish": 37, "toad": 41}
    for kind, off in offs.items():
        n = ANIMALS[kind]
        for i in range(n):
            src = os.path.join(W, "wildlife", "%02d.png" % (off + i))
            save_env(src, "an_%s_%d" % (kind, i + 1))
    # пак данжа d5 «руины чуди»: тайлы 32x32
    def tile(src_rel: str, name: str, darken: float = 1.0) -> None:
        im = Image.open(os.path.join(W, src_rel)).convert("RGBA")
        im = im.resize((TS, TS), Image.LANCZOS)
        if darken != 1.0:
            px = im.load()
            for y in range(TS):
                for x in range(TS):
                    r, g, b, a = px[x, y]
                    px[x, y] = (int(r * darken), int(g * darken), int(b * darken), a)
        im.save(os.path.join(ENV, name + ".png"))
        print("env/%s.png" % name)
    tile("chud_ruins/01.png", "d5_floor_a")
    tile("chud_ruins/03.png", "d5_floor_b")
    tile("chud_ruins/04.png", "d5_floor_c")
    tile("chud_ruins/02.png", "d5_floor_d")
    for side in ("n", "s", "w", "e"):
        tile("chud_ruins/01.png", "d5_edge_%s" % side, darken=0.62)
    tile("chud_ruins/11.png", "d5_wall_face")
    tile("chud_ruins/14.png", "d5_wall_top")
    print("готово.")


if __name__ == "__main__":
    main()
