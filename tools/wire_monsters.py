# -*- coding: utf-8 -*-
"""Проводка нарезанных монстров (monsters_new) в спрайты игры (v1.74).

Источники ссылок:
  e:<имя>  -> assets/sprites/env/<имя>.png (обычные враги и боссы кита);
  img:creatures/<имя> -> assets/sprites/creatures/<имя>.png (нечисть).
k:N-тайлы Kenney заменяются на e:<id> в data/enemies.json (у golem/
crystal_colossus, ash_hound/wolf, ash_tyrant/bandit_chief тайлы были
общие — каждому врагу теперь свой спрайт).
"""
import io
import json
import os
import shutil

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NEW = os.path.join(BASE, "assets", "sprites", "monsters_new")
ENV = os.path.join(BASE, "assets", "sprites", "env")
CRE = os.path.join(BASE, "assets", "sprites", "creatures")
ENEMIES = os.path.join(BASE, "data", "enemies.json")

# кроп -> (куда, имя файла, [тип врага, новый sprite] или None)
MAP = [
    # --- обычные монстры (лист m36 «36 монстров») ---
    ("m36_00",  ENV, "crawler.png",        ("crawler", "e:crawler")),
    ("m36_01",  ENV, "rat.png",            ("rat", "e:rat")),
    ("m36_02",  ENV, "skeleton.png",       ("skeleton", "e:skeleton")),
    ("m36_03",  ENV, "wisp.png",           ("wisp", "e:wisp")),
    ("m36_04",  ENV, "golem.png",          ("golem", "e:golem")),
    ("m36_05",  ENV, "shardling.png",      ("shardling", "e:shardling")),
    ("m36_06",  ENV, "ash_hound.png",      ("ash_hound", "e:ash_hound")),
    ("m36_07",  ENV, "mutant.png",         None),
    ("m36_08",  ENV, "brute.png",          None),
    ("m36_09",  ENV, "wolf.png",           ("wolf", "e:wolf")),
    ("m36_10",  ENV, "dust_stalker.png",   ("dust_stalker", "e:dust_stalker")),
    ("m36_11",  ENV, "ghoul.png",          None),
    ("m36_12",  ENV, "cinder.png",         ("cinder", "e:cinder")),
    ("m36_13",  ENV, "bandit.png",         ("bandit", "e:bandit")),
    ("m36_14",  ENV, "bandit_archer.png",  ("bandit_archer", "e:bandit_archer")),
    ("m36_15",  CRE, "leshy.png",          None),
    ("m36_16",  CRE, "upyr.png",           None),
    ("m36_17",  CRE, "kikimora.png",       None),
    ("m36_18",  ENV, "imp.png",            None),
    ("m36_19",  ENV, "hellcaller.png",     None),
    ("m36_20",  ENV, "fallen.png",         ("fallen", "e:fallen")),
    ("m36_21",  ENV, "dragon_whelp.png",   None),
    ("m36_22",  ENV, "vampire.png",        None),
    ("m36_23",  ENV, "lich.png",           None),
    ("m36_24",  ENV, "skeleton_mage.png",  None),
    ("m36_25",  ENV, "spirit.png",         None),
    ("m36_26",  CRE, "vodyanoy.png",       None),
    ("m36_27",  ENV, "spitter.png",        None),
    ("m36_28",  CRE, "rusalka.png",        None),
    ("m36_29",  CRE, "volkolak.png",       None),
    ("m36_30",  CRE, "bannik.png",         None),
    ("m36_31",  CRE, "polevik.png",        None),
    ("m36_32",  CRE, "nochnitsa.png",      None),
    ("m36_33",  CRE, "black_hen.png",      None),
    ("m36_34",  CRE, "death_needle.png",   None),
    # --- боссы ---
    ("bestiar_00",   ENV, "bone_knight.png",      ("bone_knight", "e:bone_knight")),
    ("bestiar_03",   ENV, "broodmother.png",      ("broodmother", "e:broodmother")),
    ("bestiar_21",   ENV, "crystal_colossus.png", ("crystal_colossus", "e:crystal_colossus")),
    ("bestiar_25",   ENV, "ash_tyrant.png",       ("ash_tyrant", "e:ash_tyrant")),
    ("bestiar_30",   ENV, "bandit_chief.png",     ("bandit_chief", "e:bandit_chief")),
    ("bestiar_52",   ENV, "seraph.png",           None),
    ("bosses_a_02",  ENV, "treant.png",           None),
    ("bosses_b_01",  ENV, "archvampire.png",      None),
    ("bosses_b_19",  ENV, "archlich.png",         None),
    ("bosses_a_30",  ENV, "demon_lord.png",       None),
    ("bosses_b_63",  ENV, "dragon.png",           None),
    ("dark0_113",    CRE, "koshchei.png",        None),
    ("dark0_116",    CRE, "baba_yaga.png",       None),
    ("dark0_117",    CRE, "viy.png",             None),
]


def main() -> None:
    for crop, dst_dir, fname, enemy in MAP:
        src = os.path.join(NEW, crop + ".png")
        dst = os.path.join(dst_dir, fname)
        shutil.copyfile(src, dst)
        tag = "env" if dst_dir == ENV else "creatures"
        print("%-12s -> %s/%s" % (crop, tag, fname))
    data = json.load(io.open(ENEMIES, encoding="utf-8"))
    by_id = {m["id"]: m for m in data}
    for crop, dst_dir, fname, enemy in MAP:
        if enemy is None:
            continue
        eid, ref = enemy
        assert eid in by_id, "нет врага: " + eid
        old = by_id[eid].get("sprite")
        by_id[eid]["sprite"] = ref
        print("enemies.json %-17s %s -> %s" % (eid, old, ref))
    io.open(ENEMIES, "w", encoding="utf-8", newline="\n").write(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
