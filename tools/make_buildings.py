# Генератор пиксель-спрайтов 32×32 (M9): 20 зданий города + дерево/скала/руда
# + иконка игры. Запуск: blender -b --python tools/make_buildings.py
# Стиль — палитра воина и Kenney (тёплое дерево, серый камень, тёмные крыши).
import zlib, struct, os, sys

BASE = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spritemap import write_png  # проверенный pure-python писатель PNG

OUT = os.path.join(BASE, "assets", "sprites")
TS = 32

# палитра (RGB)
PLASTER = (201, 177, 138)
WOOD_D = (122, 85, 52)
WOOD = (138, 106, 72)
WOOD_L = (160, 127, 88)
STONE = (154, 154, 146)
STONE_D = (120, 120, 112)
ROOF_RED = (122, 59, 46)
ROOF_RED_D = (94, 44, 34)
ROOF_TEAL = (58, 107, 100)
ROOF_TEAL_D = (44, 82, 76)
ROOF_GOLD = (176, 143, 74)
ROOF_GOLD_D = (138, 110, 54)
ROOF_BLUE = (62, 74, 99)
ROOF_BLUE_D = (46, 56, 76)
WIN = (40, 34, 30)
OUTLINE = (28, 22, 18)
FIRE = (240, 130, 50)
CRYSTAL = (110, 200, 200)
GREEN = (92, 130, 62)
GREEN_D = (66, 98, 46)


class Img:
    def __init__(self):
        self.px = [[(0, 0, 0, 0)] * TS for _ in range(TS)]

    def set(self, x, y, c):
        if 0 <= x < TS and 0 <= y < TS:
            self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        for j in range(h):
            for i in range(w):
                self.set(x + i, y + j, c)

    def hline(self, x, y, w, c):
        self.rect(x, y, w, 1, c)

    def outline_rect(self, x, y, w, h, c):
        self.hline(x, y, w, c); self.hline(x, y + h - 1, w, c)
        for j in range(h):
            self.set(x, y + j, c); self.set(x + w - 1, y + j, c)

    def roof(self, x0, y0, w, peak_y, c, c_d):
        # двускатная крыша: от пика вниз-вширь, каждый 2-й ряд темнее (черепица)
        rows = TS - peak_y if False else y0 + (w // 2) - peak_y
        for r in range(rows):
            yy = peak_y + r
            half = min(r + 1, w // 2 + 1)
            left = x0 + w // 2 - half
            self.hline(max(x0, left), yy, min(w, half * 2), c if yy % 2 == 0 else c_d)
        self.set(x0 + w // 2, peak_y, c)

    def house_body(self, x, y, w, h, wall, beams=True):
        self.rect(x, y, w, h, wall)
        if beams:  # фахверк: тёмные балки по углам и через стену
            self.outline_rect(x, y, w, h, WOOD_D)
            self.hline(x, y + h // 3, w, WOOD_D)
        self.hline(x, y + h - 1, w, OUTLINE)

    def window(self, x, y):
        self.rect(x, y, 4, 4, WIN)
        self.set(x + 1, y + 1, (250, 220, 140))
        self.rect(x - 1, y, 1, 4, WOOD_D); self.rect(x + 4, y, 1, 4, WOOD_D)

    def door(self, x, y, h=7):
        self.rect(x, y - h, 5, h, WOOD_D)
        self.set(x + 3, y - h // 2 - 1, (222, 197, 110))

    def chimney(self, x, y):
        self.rect(x, y, 3, 5, STONE_D)
        self.hline(x, y, 3, STONE)


def save(img, name, folder="buildings"):
    d = os.path.join(OUT, folder)
    os.makedirs(d, exist_ok=True)
    flat = bytearray()
    for row in img.px:
        assert len(row) == TS
        for c in row:
            flat += bytes(c if len(c) == 4 else (c[0], c[1], c[2], 255))
    assert len(flat) == TS * TS * 4, len(flat)
    write_png(os.path.join(d, name + ".png"), TS, TS, bytes(flat))


def base_house(wall=PLASTER, roof=(ROOF_RED, ROOF_RED_D)):
    im = Img()
    im.house_body(7, 14, 18, 14, wall)
    im.roof(5, 8, 22, 5, roof[0], roof[1])
    im.window(10, 17)
    im.door(17, 28)
    return im


SPRITES = {}


def sp(name, fn):
    SPRITES[name] = fn


sp("house", lambda: base_house())
sp("farm", lambda: _farm())
sp("sawmill", lambda: _sawmill())
sp("well", lambda: _well())
sp("quarry", lambda: _quarry())
sp("warehouse", lambda: _warehouse())
sp("workshop", lambda: _workshop())
sp("wall", lambda: _wall())
sp("gate", lambda: _gate())
sp("tower", lambda: _tower())
sp("altar", lambda: _altar())
sp("healer_hut", lambda: _healer())
sp("tavern", lambda: _tavern())
sp("mine", lambda: _mine())
sp("smelter", lambda: _smelter())
sp("forge", lambda: _forge())
sp("armory", lambda: _armory())
sp("pier", lambda: _pier())
sp("garden", lambda: _garden())
sp("statue", lambda: _statue())


def _farm():
    im = base_house(PLASTER, (ROOF_GOLD, ROOF_GOLD_D))
    for i in range(4):  # грядки перед домом
        im.hline(3 + i * 7, 29, 5, GREEN if i % 2 == 0 else GREEN_D)
    return im


def _sawmill():
    im = Img()
    im.house_body(4, 12, 16, 16, WOOD)
    im.roof(2, 6, 20, 3, ROOF_BLUE, ROOF_BLUE_D)
    im.door(8, 28)
    for k in range(3):  # штабель брёвен
        im.rect(22, 24 - k * 3, 8, 3, WOOD_L if k % 2 == 0 else WOOD)
        im.hline(22, 24 - k * 3, 8, WOOD_D)
    return im


def _well():
    im = Img()
    im.rect(9, 18, 14, 9, STONE)
    im.outline_rect(9, 18, 14, 9, STONE_D)
    im.rect(11, 20, 10, 5, (30, 40, 46))
    im.rect(14, 8, 1, 11, WOOD_D); im.rect(18, 8, 1, 11, WOOD_D)
    im.roof(8, 6, 16, 3, ROOF_RED, ROOF_RED_D)
    im.rect(15, 12, 3, 3, WOOD_D)
    return im


def _quarry():
    im = Img()
    im.rect(2, 8, 28, 21, STONE_D)
    for yy in range(8, 29, 4):
        im.hline(2, yy, 28, (100, 100, 92))
    for k in range(4):
        im.rect(4 + k * 7, 4, 5, 5, STONE)
        im.outline_rect(4 + k * 7, 4, 5, 5, OUTLINE)
    im.rect(20, 22, 8, 3, WOOD_D)  # тачка
    im.rect(22, 25, 2, 2, OUTLINE); im.rect(25, 25, 2, 2, OUTLINE)
    return im


def _warehouse():
    im = Img()
    im.house_body(3, 12, 26, 16, WOOD)
    im.roof(1, 4, 30, 2, (108, 84, 56), (84, 64, 42))
    im.rect(12, 18, 8, 10, WOOD_D)  # ворота
    im.hline(12, 21, 8, OUTLINE); im.hline(12, 24, 8, OUTLINE)
    im.rect(3, 26, 4, 3, (196, 174, 118)); im.rect(7, 27, 3, 2, (176, 152, 98))  # мешки
    return im


def _workshop():
    im = base_house(WOOD, (ROOF_BLUE, ROOF_BLUE_D))
    im.rect(12, 25, 7, 3, STONE_D)  # наковальня у двери
    im.rect(13, 23, 5, 2, STONE)
    return im


def _wall():
    im = Img()
    im.rect(0, 8, 32, 24, STONE)
    for yy in range(8, 32, 5):
        im.hline(0, yy, 32, STONE_D)
        off = 4 if (yy // 5) % 2 else 0
        for xx in range(off, 32, 8):
            im.hline(xx, yy, 1, STONE_D)
            im.hline(xx, yy + 1, 1, STONE_D)
    im.hline(0, 8, 32, OUTLINE)
    return im


def _gate():
    im = _wall()
    im.rect(9, 12, 14, 20, (46, 36, 28))  # арка
    im.outline_rect(9, 12, 14, 20, STONE_D)
    im.rect(11, 14, 4, 18, WOOD_D); im.rect(17, 14, 4, 18, WOOD_D)
    im.hline(15, 14, 2, (196, 162, 84))
    return im


def _tower():
    im = Img()
    im.rect(10, 4, 12, 28, STONE)
    im.outline_rect(10, 4, 12, 28, STONE_D)
    for k in range(3):  # зубцы
        im.rect(9 + k * 5, 2, 3, 3, STONE)
    im.rect(14, 10, 3, 4, WIN)  # бойница
    im.hline(10, 20, 12, STONE_D)
    return im


def _altar():
    im = Img()
    im.rect(10, 20, 12, 8, STONE)
    im.outline_rect(10, 20, 12, 8, STONE_D)
    im.rect(12, 16, 8, 4, STONE_D)
    for k, c in enumerate([(90, 170, 190), CRYSTAL, (170, 240, 240)]):  # кристалл
        im.rect(14 + (2 - k) // 2, 8 + k * 3, 4 + k * 2 - k, 3, c)
    return im


def _healer():
    im = base_house(PLASTER, (ROOF_TEAL, ROOF_TEAL_D))
    im.rect(11, 18, 5, 5, (250, 250, 244))  # полоска-знамя лекаря
    im.rect(12, 19, 3, 3, ROOF_TEAL)
    for k in range(3):
        im.set(24 + k, 27 - k % 2, GREEN)
    return im


def _tavern():
    im = base_house(WOOD_L, (ROOF_GOLD, ROOF_GOLD_D))
    im.rect(5, 15, 6, 6, WOOD_D)  # вывеска-кружка
    im.rect(6, 16, 4, 4, (240, 214, 150))
    im.hline(6, 17, 4, (255, 244, 200))
    return im


def _mine():
    im = Img()
    im.rect(2, 6, 28, 23, STONE_D)
    for yy in range(6, 29, 5):
        im.hline(2, yy, 28, (100, 100, 92))
    im.rect(9, 14, 14, 16, (24, 20, 18))  # штольня
    im.hline(9, 14, 14, WOOD_D); im.hline(9, 20, 14, WOOD_D)
    im.rect(9, 14, 2, 16, WOOD_D); im.rect(21, 14, 2, 16, WOOD_D)
    im.set(15, 24, (90, 90, 96)); im.set(17, 26, (120, 110, 100))  # рельса-блик
    return im


def _smelter():
    im = Img()
    im.rect(6, 10, 20, 19, STONE)
    im.outline_rect(6, 10, 20, 19, STONE_D)
    im.chimney(20, 5)
    im.rect(12, 22, 8, 7, FIRE)  # горн
    im.rect(14, 24, 4, 5, (255, 200, 90))
    return im


def _forge():
    im = Img()
    im.house_body(4, 12, 20, 16, STONE)
    im.roof(2, 6, 24, 3, (80, 72, 66), (60, 54, 48))
    im.chimney(22, 6)
    im.rect(8, 24, 7, 4, FIRE)
    im.rect(19, 22, 6, 3, STONE_D); im.rect(20, 20, 4, 2, STONE)  # наковальня
    return im


def _armory():
    im = base_house(PLASTER, (ROOF_RED, ROOF_RED_D))
    im.rect(20, 16, 6, 7, STONE_D)  # щит на стене
    im.rect(21, 17, 4, 5, (150, 150, 158))
    im.rect(9, 16, 2, 8, (170, 170, 178))  # меч
    im.hline(8, 23, 4, WOOD_D)
    return im


def _pier():
    im = Img()
    for k in range(4):  # настил досками
        im.hline(4, 18 + k * 3, 26, WOOD_L if k % 2 == 0 else WOOD)
    for xx in (6, 14, 22):
        im.rect(xx, 27, 2, 3, WOOD_D)  # сваи
    im.rect(24, 8, 2, 12, WOOD_D)  # удочка
    im.hline(20, 8, 5, WOOD_D)
    im.set(20, 13, (90, 170, 190))
    return im


def _garden():
    im = Img()
    im.rect(14, 16, 4, 8, WOOD_D)  # ствол
    for k, c in enumerate([GREEN_D, GREEN, (110, 150, 72)]):
        im.rect(8 + k, 6 + k, 16 - k * 2, 5, c)  # крона
    im.rect(10, 26, 5, 3, GREEN_D); im.rect(19, 27, 4, 2, GREEN)
    im.hline(4, 30, 24, (150, 130, 96))  # дорожка
    return im


def _statue():
    im = Img()
    im.rect(9, 24, 14, 5, STONE_D)
    im.rect(11, 21, 10, 3, STONE)
    im.rect(13, 9, 6, 12, STONE)  # фигура
    im.rect(12, 5, 8, 5, STONE)
    im.set(14, 7, OUTLINE); im.set(18, 7, OUTLINE)
    im.rect(11, 12, 2, 6, STONE_D); im.rect(19, 12, 2, 6, STONE_D)  # руки-складки
    return im


def make_icons():
    # иконка 128×128: воин 32×32 ×4 (nearest)
    src = os.path.join(OUT, "knight.png")
    if os.path.exists(src):
        import sys
        sys.path.insert(0, os.path.dirname(__file__))
        from spritemap import read_png
        w, h, px = read_png(src)
        flat = bytearray()
        for y in range(h):
            row = bytearray()
            for x in range(w):
                row += bytes(px[(y * w + x) * 4:]) * 4
            flat += row * 4
        write_png(os.path.join(BASE, "icon.png"), w * 4, h * 4, flat)


def main():
    for name, fn in SPRITES.items():
        save(fn(), name)
    for name, fn in [("tree", _tree), ("rock", _rock), ("ore", _ore)]:
        pass
    save(_tree(), "tree", folder=".")
    save(_rock(), "rock", folder=".")
    save(_ore(), "ore", folder=".")
    make_icons()
    print("OK", len(SPRITES) + 3, "sprites")


def _tree():
    im = Img()
    im.rect(14, 20, 4, 9, WOOD_D)
    for k, c in enumerate([GREEN_D, GREEN, (110, 150, 72), (124, 164, 80)]):
        w = 20 - k * 3
        im.rect(16 - w // 2, 4 + k * 4, w, 5, c)
    return im


def _rock():
    im = Img()
    for k, c in enumerate([STONE_D, STONE, (176, 176, 168)]):
        im.rect(4 + k * 2, 22 - k * 7, 24 - k * 4, 8, c)
    im.rect(4, 28, 24, 2, STONE_D)
    return im


def _ore():
    im = _rock()
    for x, y in [(10, 18), (16, 22), (20, 16), (13, 25)]:
        im.rect(x, y, 2, 2, (224, 122, 63))
    return im


main()
