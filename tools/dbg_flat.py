TOOLS = r"F:Z2.zcodeworkspacedefaultpostapok_game	ools"
import sys, os
TOOLS = os.path.dirname(os.path.abspath(sys.argv[-1])) if False else os.path.dirname(os.path.abspath("tools"))
sys.path.insert(0, TOOLS)
import importlib.util
spec = importlib.util.spec_from_file_location("mb", os.path.join(TOOLS, "make_buildings.py"))
# подавим автозапуск main: читаем исходник, убираем последний вызов
src = open(os.path.join(TOOLS, "make_buildings.py"), encoding="utf-8").read()
src = src.replace("\nmain()\n", "\n")
mod = {}
exec(compile(src, "make_buildings.py", "exec"), mod)
im = mod["SPRITES"]["altar"]()
flat = bytearray()
for row in im.px:
    assert len(row) == 32, len(row)
    for c in row:
        assert len(c) == 4, c
        flat += bytes(c)
print("FLAT", len(flat))
mod["write_png"]("altar_test.png", 32, 32, flat)
import zlib, struct
data = open("altar_test.png", "rb").read()
pos = 8
while pos < len(data):
    ln = struct.unpack(">I", data[pos:pos+4])[0]
    if data[pos+4:pos+8] == b"IDAT":
        print("DEC", len(zlib.decompress(data[pos+8:pos+8+ln])))
    pos += 12 + ln
