import sys, os, zlib, struct
BASE = os.path.dirname(__file__)
data = open(os.path.join(BASE, "..", "assets", "sprites", "buildings", "altar.png"), "rb").read()
pos = 8
while pos < len(data):
    ln = struct.unpack(">I", data[pos:pos+4])[0]
    typ = data[pos+4:pos+8]
    print(typ, ln)
    if typ == b"IDAT":
        raw = zlib.decompress(data[pos+8:pos+8+ln])
        print("decompressed", len(raw), "expected", 32*(1+32*4))
    pos += 12 + ln
