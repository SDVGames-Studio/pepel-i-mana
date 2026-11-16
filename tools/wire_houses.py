# -*- coding: utf-8 -*-
"""Проводка нарезанных домов (buildings_new) в спрайты игры (v1.73).

Маппинг согласуется с таблицей для заказчика; правки:
  1) копия кропа -> assets/sprites/buildings/<файл>.png;
  2) точечные замены "sprite" в data/city.json (только для зданий, чей
     старый файл-имя больше не соответствует смыслу).
Детерминирован: перезапуск после пересрезки повторяет то же распределение.
"""
import io
import os
import shutil

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NEW = os.path.join(BASE, "assets", "sprites", "buildings_new")
BLD = os.path.join(BASE, "assets", "sprites", "buildings")
CITY = os.path.join(BASE, "data", "city.json")

# кроп -> файл в buildings/ + (тип, новый sprite в city.json или None)
MAP = [
    ("fancy_00",    "дом_жителей_ур1.png",  None),
    ("fancy_01",    "дом_жителей_ур2.png",  None),
    ("fancy_03",    "дом_жителей_ур3.png",  None),
    ("village_00",  "ферма_грядки.png",     ("farm", "b:ферма_грядки")),
    ("village_07",  "лесопилка.png",        ("sawmill", "b:лесопилка")),
    ("fancy_04",    "well.png",             None),
    ("workshop_08", "каменоломня.png",      ("quarry", "b:каменоломня")),
    ("village_01",  "склад.png",            None),
    ("workshop_09", "мастерская.png",       ("workshop", "b:мастерская")),
    ("workshop_06", "ремесленный_двор.png", ("craftsman", "b:ремесленный_двор")),
    ("fort_02",     "частокол.png",         None),   # в задел: стены рисуются
    ("fort_05",     "ворота.png",           None),   # сегментами (city_view)
    ("fort_09",     "вышка.png",            ("tower", "b:вышка")),
    ("sanct_04",    "altar.png",            None),
    ("sanct_11",    "хижина_лекаря.png",    ("healer_hut", "b:хижина_лекаря")),
    ("slav_04",     "таверна.png",          None),
    ("village_02",  "шахта.png",            ("mine", "b:шахта")),
    ("village_13",  "плавильня.png",        ("smelter", "b:плавильня")),
    ("workshop_02", "кузница.png",          None),
    ("workshop_03", "оружейная.png",        ("armory", "b:оружейная")),
    ("village_05",  "pier.png",             None),
    ("fancy_05",    "garden.png",           None),
    ("fancy_06",    "идол.png",             None),   # + STATUE_REFS (city_view_props)
    ("village_06",  "tree_red.png",         None),
    ("sanct_15",    "temple.png",           None),
    ("sanct_26",    "tent.png",             None),
]


def main() -> None:
    for crop, target, sprite in MAP:
        src = os.path.join(NEW, crop + ".png")
        dst = os.path.join(BLD, target)
        shutil.copyfile(src, dst)
        print("%-12s -> buildings/%s" % (crop, target))
    s = io.open(CITY, encoding="utf-8").read()
    for crop, target, sprite in MAP:
        if sprite is None:
            continue
        btype, ref = sprite
        # находим блок типа и меняем его sprite
        i = s.find('"id": "%s"' % btype)
        assert i > 0, "тип не найден: " + btype
        j = s.find('"sprite":', i)
        k = s.find('"', j + 10)
        k2 = s.find('"', k + 1)
        old = s[k:k2 + 1]
        s = s[:k] + '"%s"' % ref + s[k2 + 1:]
        print("city.json %s: %s -> %s" % (btype, old, ref))
    io.open(CITY, "w", encoding="utf-8", newline="\n").write(s)


if __name__ == "__main__":
    main()
