# Контрольный лист Kenney-атласа: каждый тайл ×6 с сеткой (pure python).
# Запуск: blender -b --python tools/spritemap.py  (нет системного python)
# Порядок тайлов: индекс = ряд*12 + колонка, слева направо сверху вниз.
import zlib, struct, os

BASE = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(BASE, "assets", "sprites", "kenney.png")
OUT = os.path.join(BASE, "tools", "spritemap.png")
COLS, ROWS, TS, Z = 12, 11, 16, 6


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, w, h, ctype, bitd, plte, trns = 8, b"", 0, 0, 0, 8, b"", b""
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, bitd, ctype = struct.unpack(">IIBB", chunk[:10])
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"PLTE":
            plte = chunk
        elif typ == b"tRNS":
            trns = chunk
        pos += 12 + ln
    assert bitd == 8, "bit depth %d" % bitd
    raw = zlib.decompress(idat)
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    stride = w * nch
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        prev = line
        for x in range(w):
            o = (y * w + x) * 4
            if ctype == 6:
                out[o:o + 4] = line[x * 4:x * 4 + 4]
            elif ctype == 2:
                out[o:o + 3] = line[x * 3:x * 3 + 3]; out[o + 3] = 255
            elif ctype == 4:
                out[o] = out[o + 1] = out[o + 2] = line[x * 2]; out[o + 3] = line[x * 2 + 1]
            elif ctype == 0:
                out[o] = out[o + 1] = out[o + 2] = line[x]; out[o + 3] = 255
            elif ctype == 3:
                i = line[x] * 3
                out[o:o + 3] = plte[i:i + 3]
                out[o + 3] = trns[line[x]] if line[x] < len(trns) else 255
    return w, h, out


def write_png(path, w, h, rgba):
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        return c + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    open(path, "wb").write(png)


def main():
    W, H, PX = read_png(SRC)
    assert W == COLS * TS and H == ROWS * TS, "%dx%d" % (W, H)
    PAD, G = 2, 1  # поле вокруг тайла, толщина сетки
    OW, OH = COLS * (TS * Z + PAD + G) + G, ROWS * (TS * Z + PAD + G) + G
    canvas = bytearray(OW * OH * 4)

    def put(x, y, rgba, alpha=255):
        if 0 <= x < OW and 0 <= y < OH:
            o = (y * OW + x) * 4
            canvas[o] = rgba[0]; canvas[o + 1] = rgba[1]; canvas[o + 2] = rgba[2]
            canvas[o + 3] = max(canvas[o + 3], alpha)

    for ty in range(ROWS):
        for tx in range(COLS):
            x0 = G + tx * (TS * Z + PAD + G)
            y0 = G + ty * (TS * Z + PAD + G)
            for py in range(TS):
                for px in range(TS):
                    r, g, b, a = PX[((ty * TS + py) * W + tx * TS + px) * 4:][:4]
                    for dy in range(Z):
                        for dx in range(Z):
                            put(x0 + px * Z + dx, y0 + py * Z + dy, (r, g, b), a)
    # сетка красным по краям ячеек
    for ty in range(ROWS + 1):
        y = G + ty * (TS * Z + PAD + G) - (G if ty else 0)
        for x in range(OW):
            put(x, y, (255, 0, 0), 200)
    for tx in range(COLS + 1):
        x = G + tx * (TS * Z + PAD + G) - (G if tx else 0)
        for y in range(OH):
            put(x, y, (255, 0, 0), 200)
    write_png(OUT, OW, OH, canvas)
    print("OK", OUT, OW, "x", OH)


if __name__ == "__main__":
    main()
