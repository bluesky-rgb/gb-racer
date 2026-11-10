"""All original pixel art for the game, drawn procedurally: sprites (cars, roadside
objects at several sizes, countdown) and the horizon pictures for each course.

Sprite colours: None = transparent, 1 = white, 2 = mid tone (light or dark gray
depending on the object palette), 3 = black."""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from gbgfx import Canvas, tile_bytes
from geom import SKY_ROWS
import font

# --------------------------------------------------------------------------
# tiny vector rasteriser: shapes are given in "master" pixel coordinates and
# rendered at any size, so every object exists at several scales.

def _inside(shape, x, y, pad):
    kind = shape[0]
    if kind == "rect":
        _, x0, y0, x1, y1 = shape[:5]
        if x1 - x0 < pad: m = (x0 + x1) / 2; x0, x1 = m - pad / 2, m + pad / 2
        if y1 - y0 < pad: m = (y0 + y1) / 2; y0, y1 = m - pad / 2, m + pad / 2
        return x0 <= x < x1 and y0 <= y < y1
    if kind == "ell":
        _, cx, cy, rx, ry = shape[:5]
        rx, ry = max(rx, pad / 2), max(ry, pad / 2)
        return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0
    if kind == "poly":
        pts = shape[1]
        n, c = len(pts), False
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0): c = not c
        return c
    if kind == "line":
        _, x0, y0, x1, y1, t = shape[:6]
        t = max(t, pad)
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy
        u = 0 if L2 == 0 else max(0, min(1, ((x - x0) * dx + (y - y0) * dy) / L2))
        return (x - x0 - u * dx) ** 2 + (y - y0 - u * dy) ** 2 <= (t / 2) ** 2
    raise ValueError(kind)

def raster(shapes, mw, mh, w, h, outline=True, shear=0.0):
    """Render shapes (master size mw x mh) into a w x h canvas with 3x3 supersampling.
    Thin features are widened to stay at least one output pixel. `shear` slides the
    top of the drawing sideways (used for the car's turning pose)."""
    c = Canvas(w, h, None)
    sx, sy = mw / w, mh / h
    pad = max(sx, sy) * 0.9
    for y in range(h):
        for x in range(w):
            votes = {}
            for j in range(3):
                for i in range(3):
                    my = (y + (j + 0.5) / 3) * sy
                    mx = (x + (i + 0.5) / 3) * sx - shear * (1 - my / mh)
                    col, top = None, -1
                    for k, s in enumerate(shapes):
                        if _inside(s, mx, my, pad): col, top = s[-1], k
                    n, t = votes.get(col, (0, -1))
                    votes[col] = (n + 1, max(t, top))
            # majority colour; ties go to the topmost shape (keeps mirrored art mirrored)
            col = max(votes.items(), key=lambda kv: kv[1])[0]
            if isinstance(col, tuple):                      # dither between two colours
                col = col[(x + y) & 1]
            c.px[y][x] = col
    if outline:
        src = [row[:] for row in c.px]
        for y in range(h):
            for x in range(w):
                if src[y][x] is None:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < w and 0 <= yy < h and src[yy][xx] not in (None, 3):
                            c.px[y][x] = 3
                            break
    return c

# --------------------------------------------------------------------------
# sprite designs (master coordinates)

def car_player():
    return (32, 24, [
        ("rect", 4, 21, 28, 23.4, 3),                                   # shadow
        ("rect", 2.5, 14, 8.5, 22.5, 3), ("rect", 23.5, 14, 29.5, 22.5, 3),   # tyres
        ("poly", [(3, 10), (29, 10), (30.5, 13), (30.5, 18.5), (28.5, 20.5), (3.5, 20.5), (1.5, 18.5), (1.5, 13)], 1),  # body
        ("rect", 2, 16.5, 30, 18.5, 2),                                  # lower shade
        ("rect", 9, 18.5, 23, 20.5, 3),                                  # diffuser
        ("poly", [(8, 10), (10.5, 3.5), (21.5, 3.5), (24, 10)], 2),      # cabin
        ("poly", [(10.3, 9), (12, 5), (20, 5), (21.7, 9)], 3),           # rear window
        ("rect", 13, 5.6, 19, 6.5, 1),                                   # glare
        ("rect", 7, 6.5, 9, 10, 3), ("rect", 23, 6.5, 25, 10, 3),        # wing struts
        ("rect", 2, 4.6, 30, 6.9, 3), ("rect", 3, 5, 29, 6.2, 1),        # rear wing
        ("rect", 3.5, 11.5, 10.5, 14.5, 3), ("rect", 21.5, 11.5, 28.5, 14.5, 3),  # tail lights
        ("rect", 4.5, 12.4, 7, 13.6, 1), ("rect", 25, 12.4, 27.5, 13.6, 1),
        ("rect", 13, 12, 19, 15, 3), ("rect", 14, 12.8, 18, 14.2, 1),    # plate
    ])

def car_rival():
    return (32, 24, [
        ("rect", 4, 21, 28, 23.4, 3),
        ("rect", 3, 15, 9, 22.5, 3), ("rect", 23, 15, 29, 22.5, 3),
        ("poly", [(3.5, 9), (6.5, 2.5), (25.5, 2.5), (28.5, 9), (29.8, 18.5), (28, 20.5), (4, 20.5), (2.2, 18.5)], 2),  # tall body
        ("rect", 7, 2.5, 25, 3.6, 1),                                    # roof highlight
        ("poly", [(7.5, 8.5), (9.5, 4.6), (22.5, 4.6), (24.5, 8.5)], 3), # window
        ("rect", 12, 5.3, 20, 6.2, 1),
        ("rect", 3.5, 10.5, 9.5, 13.5, 1), ("rect", 22.5, 10.5, 28.5, 13.5, 1),   # tail lights
        ("rect", 12.5, 11, 19.5, 14.5, 1), ("rect", 14, 12, 18, 13.4, 3),          # plate
        ("rect", 3, 16.3, 29, 18.2, 3),                                  # bumper
    ])

def palm():
    sh = [("poly", [(9.5, 47.5), (14.5, 47.5), (14.2, 32), (15.5, 15), (12.5, 15), (11, 32)], 2)]
    for y in range(20, 46, 5):
        sh.append(("line", 11, y, 15, y - 1.2, 0.9, 3))
    leaves = [(-12.5, 6.5, 3), (-13, -3.5, 3), (-7.5, -12, 2), (1, -14.5, 3), (9, -11, 2), (10.5, -2, 3), (10, 7.5, 3)]
    cx, cy = 13.5, 14.5
    for dx, dy, col in leaves:
        tx, ty = cx + dx, cy + dy
        nx, ny = -dy, dx
        n = math.hypot(nx, ny) or 1
        nx, ny = nx / n * 3.3, ny / n * 3.3
        mx, my = cx + dx * 0.5, cy + dy * 0.5 - 2.5
        sh.append(("poly", [(cx, cy), (mx + nx, my + ny), (tx, ty), (mx - nx, my - ny)], col))
    sh.append(("ell", 13.5, 14.5, 2.6, 2.3, 3))
    sh.append(("ell", 11.4, 16.6, 1.3, 1.3, 2))
    sh.append(("ell", 15.6, 16.8, 1.3, 1.3, 2))
    return (24, 48, sh)

def billboard():
    return (24, 32, [
        ("rect", 4, 19, 6.5, 32, 2), ("rect", 17.5, 19, 20, 32, 2),
        ("rect", 0.5, 2.5, 23.5, 20.5, 3), ("rect", 1.8, 3.8, 22.2, 19.2, 1),
        ("ell", 16.5, 9, 3.6, 3.6, 2),                                   # sun
        ("line", 3, 15, 8, 13, 1.2, 3), ("line", 8, 13, 13, 15, 1.2, 3), ("line", 13, 15, 20, 13.2, 1.2, 3),  # wave
        ("line", 4, 8, 10, 8, 1.3, 3), ("line", 4, 11, 8, 11, 1.3, 3),
    ])

def cactus():
    return (24, 48, [
        ("rect", 9, 6, 15, 47.5, 2), ("ell", 12, 6.5, 3, 3.5, 2),
        ("rect", 2.5, 23, 9.5, 27.5, 2), ("rect", 2.5, 13, 6.5, 27, 2), ("ell", 4.5, 13.5, 2, 2.4, 2),
        ("rect", 14.5, 29, 21.5, 33.5, 2), ("rect", 17.5, 18, 21.5, 33, 2), ("ell", 19.5, 18.5, 2, 2.4, 2),
        ("line", 10.6, 7, 10.6, 46, 0.8, 1), ("line", 13.6, 8, 13.6, 46, 0.8, 3),
        ("line", 3.8, 14, 3.8, 24, 0.7, 1), ("line", 18.8, 19, 18.8, 30, 0.7, 1),
    ])

def boulder():
    return (24, 32, [
        ("poly", [(2, 31.5), (1, 22), (5, 13), (12, 9), (19, 12), (23, 21), (22.5, 31.5)], 2),
        ("poly", [(5, 13.5), (12, 9.5), (14, 16), (7, 20)], 1),
        ("poly", [(14, 16), (19, 12.5), (22.5, 21), (16, 24)], 3),
        ("line", 7, 20, 9, 30, 0.9, 3), ("line", 16, 24, 15, 31, 0.9, 3),
    ])

def lamp():
    return (24, 48, [
        ("rect", 10.6, 7, 13.4, 47.5, 1),
        ("rect", 10, 42, 14, 47.5, 2),
        ("line", 12, 7, 20, 4.5, 1.6, 1),
        ("ell", 20.5, 6, 6.2, 5.2, (1, None)),                           # glow
        ("ell", 20.5, 5.5, 3, 2.6, 1),
    ])

def neon():
    return (24, 32, [
        ("rect", 10.5, 18, 13.5, 32, 2),
        ("rect", 0.5, 1.5, 23.5, 19.5, 1), ("rect", 2, 3, 22, 18, 3),
        ("line", 5, 14.5, 9, 6.5, 1.5, 1), ("line", 9, 6.5, 13, 14.5, 1.5, 1),
        ("line", 13, 14.5, 17, 6.5, 1.5, 1), ("line", 17, 6.5, 19.5, 11, 1.5, 1),
    ])

def flagpost():
    sh = [("rect", 1.5, 2, 4, 47.5, 1), ("rect", 1, 43, 4.5, 47.5, 2), ("rect", 4, 3, 15.5, 15, 1)]
    for j in range(3):
        for i in range(3):
            if (i + j) & 1 == 0:
                sh.append(("rect", 4 + i * 3.83, 3 + j * 4, 4 + (i + 1) * 3.83, 3 + (j + 1) * 4, 3))
    return (16, 48, sh)

def big_char(ch):
    """16x16 countdown character: the HUD font doubled, with a shadow."""
    c = Canvas(16, 16, None)
    rows = font.GLYPHS[ch].split()
    for y, row in enumerate(rows):
        for x, v in enumerate(row):
            if v == '#':
                for dy in range(2):
                    for dx in range(2):
                        c.px[1 + y * 2 + dy][3 + x * 2 + dx] = 1
    src = [r[:] for r in c.px]
    for y in range(16):
        for x in range(16):
            if src[y][x] is None:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (-1, -1), (1, 1), (1, -1), (-1, 1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < 16 and 0 <= yy < 16 and src[yy][xx] == 1: c.px[y][x] = 3
    return c

# --------------------------------------------------------------------------
# sprite packing: canvases -> 8x16 cells (deduplicated, mirrored cells share tiles)

class SpritePacker:
    def __init__(self, base=0):
        self.cells, self.index, self.base = [], {}, base

    def _cell(self, cv, cx, cy):
        return tile_bytes(cv.px, cx, cy) + tile_bytes(cv.px, cx, cy + 8)

    @staticmethod
    def _flip(data):
        return bytes(int(f"{b:08b}"[::-1], 2) for b in data)

    def add(self, cv, attr=0, anchor_x=None):
        """Returns frame pieces [(dy, dx, tile, attr)] relative to the bottom-centre of cv."""
        w, h = cv.w, cv.h
        assert w % 8 == 0 and h % 16 == 0, (w, h)
        ax = w // 2 if anchor_x is None else anchor_x
        pieces = []
        for cy in range(0, h, 16):
            for cx in range(0, w, 8):
                if all(cv.px[cy + j][cx + i] is None for j in range(16) for i in range(8)): continue
                data = self._cell(cv, cx, cy)
                a = attr
                if data in self.index: idx = self.index[data]
                elif self._flip(data) in self.index: idx = self.index[self._flip(data)]; a ^= 0x20
                else:
                    idx = len(self.cells); self.cells.append(data); self.index[data] = idx
                pieces.append((cy - h + 1, cx - ax, self.base + idx * 2, a))
        return pieces

    def data(self): return b"".join(self.cells)

def pad_canvas(cv, w, h):
    """Bottom-centre cv inside a w x h transparent canvas."""
    out = Canvas(w, h, None)
    out.blit(cv, (w - cv.w) // 2, h - cv.h)
    return out

def hflip(cv):
    out = Canvas(cv.w, cv.h, None)
    for y in range(cv.h): out.px[y] = cv.px[y][::-1]
    return out

def scaled(design, w, h, outline=True, shear=0.0, cw=None, ch=None):
    mw, mh, shapes = design
    cv = raster(shapes, mw, mh, w, h, outline, shear)
    cw = cw or ((w + 7) // 8) * 8
    ch = ch or ((h + 15) // 16) * 16
    return pad_canvas(cv, cw, ch)

# sizes (w, h) per level
TALL_LEVELS = [(24, 48), (16, 32), (12, 24), (8, 16), (6, 12), (4, 8), (2, 4)]
WIDE_LEVELS = [(24, 32), (16, 22), (12, 16), (8, 11), (6, 8), (4, 5), (2, 3)]
POST_LEVELS = [(16, 48), (8, 32), (8, 24), (5, 16), (4, 12), (3, 8), (2, 4)]
CAR_LEVELS = [(32, 24), (24, 16), (16, 12), (12, 9), (8, 6), (4, 3)]
PAL1 = 0x10

def object_frames(pk, design, levels, attr):
    frames = []
    for (w, h) in levels:
        frames.append(pk.add(scaled(design, w, h, outline=h >= 12), attr))
    return frames

SCENE_OBJECTS = {
    "coast": [(palm, TALL_LEVELS, PAL1), (billboard, WIDE_LEVELS, PAL1)],
    "canyon": [(cactus, TALL_LEVELS, PAL1), (boulder, WIDE_LEVELS, PAL1)],
    "night": [(lamp, TALL_LEVELS, 0), (neon, WIDE_LEVELS, 0)],
    "title": [(palm, TALL_LEVELS, PAL1), (palm, TALL_LEVELS, PAL1)],   # must stay below tile 128: the logo needs every BG tile
}
OBJ_TILE_LIMIT = 168        # sprite tiles 0..167; the BG gives up indices 128..167 on race screens
TITLE_OBJ_LIMIT = 132       # the title logo needs nearly every BG tile

def build_sprites(out, inc):
    asm = ["; generated by tools/mkassets.py - sprite frames: count, then (dy, dx+72, tile, attr) per piece"]
    def emit(label, pieces):
        asm.append(f"{label}::")
        asm.append(f"    db {len(pieces)}")
        for dy, dx, tile, attr in pieces:
            asm.append(f"    db {dy}, {dx + 72}, {tile}, ${attr:02X}")
        asm.append("    db $80")

    sheet = []
    common = SpritePacker(0)
    # player: straight, and leaning left (right is the mirror image)
    straight = scaled(car_player(), 32, 24)
    left = scaled(car_player(), 32, 24, shear=-2.2)
    emit("FramePlayer0", common.add(straight))
    emit("FramePlayerL", common.add(left))
    emit("FramePlayerR", common.add(hflip(left)))
    sheet += [straight, left]
    for i, (w, h) in enumerate(CAR_LEVELS):
        cv = scaled(car_rival(), w, h, outline=h >= 9)
        sheet.append(cv)
        emit(f"FrameRival{i}", common.add(cv, PAL1))
        emit(f"FrameRivalB{i}", common.add(cv, 0))
    for i, (w, h) in enumerate(POST_LEVELS):
        cv = scaled(flagpost(), w, h, outline=h >= 12)
        sheet.append(cv)
        emit(f"FramePostL{i}", common.add(cv, 0))
        emit(f"FramePostR{i}", common.add(hflip(cv), 0))
    for name, text in (("3", "3"), ("2", "2"), ("1", "1"), ("Go", "GO")):
        cv = Canvas(16 * len(text), 16, None)
        for k, ch in enumerate(text): cv.blit(big_char(ch), k * 16, 0)
        sheet.append(cv)
        emit(f"FrameCount{name}", common.add(cv, 0))
    open(f"{out}/obj_common.bin", "wb").write(common.data())
    ncommon = len(common.cells) * 2
    inc.append(f"DEF OBJ_COMMON_TILES EQU {ncommon}")

    for theme, objs in SCENE_OBJECTS.items():
        pk = SpritePacker(ncommon)
        for t, (design, levels, attr) in enumerate(objs):
            for side, flip in (("L", False), ("R", True)):
                for i, (w, h) in enumerate(levels):
                    cv = scaled(design(), w, h, outline=h >= 12)
                    if flip: cv = hflip(cv)
                    if theme != "title" and not flip: sheet.append(cv)
                    emit(f"Frame_{theme}_{t}{side}{i}", pk.add(cv, attr))
        total = ncommon + len(pk.cells) * 2
        assert total <= (TITLE_OBJ_LIMIT if theme == "title" else OBJ_TILE_LIMIT), f"{theme}: {total} sprite tiles"
        open(f"{out}/obj_{theme}.bin", "wb").write(pk.data())
        inc.append(f"DEF OBJ_{theme.upper()}_TILES EQU {len(pk.cells) * 2}")
        print(f"{theme}: {total} sprite tiles of {OBJ_TILE_LIMIT}")
    asm.append("RivalFrames::\n    dw " + ", ".join(f"FrameRival{i}" for i in range(len(CAR_LEVELS))))
    asm.append("RivalFramesB::\n    dw " + ", ".join(f"FrameRivalB{i}" for i in range(len(CAR_LEVELS))))
    asm.append("CountFrames::\n    dw FrameCount3, FrameCount2, FrameCount1, FrameCountGo")
    for theme in SCENE_OBJECTS:
        asm.append(f"SceneFrames_{theme}::")
        for t in range(2):
            for side in "LR":
                asm.append("    dw " + ", ".join(f"Frame_{theme}_{t}{side}{i}" for i in range(7)))
        for side in "LR":
            asm.append("    dw " + ", ".join(f"FramePost{side}{i}" for i in range(7)))
    open(f"{out}/frames.asm", "w").write("\n".join(asm) + "\n")

    # contact sheet for eyeballing the art
    W = sum(c.w + 4 for c in sheet)
    H = max(c.h for c in sheet) + 4
    im = Canvas(min(W, 640), ((W // 640) + 1) * H, 2)
    x = y = 2
    for c in sheet:
        if x + c.w > im.w: x = 2; y += H
        for yy in range(c.h):
            for xx in range(c.w):
                v = c.px[yy][xx]
                if v is not None: im.px[y + yy][x + xx] = {1: 0, 2: 1, 3: 3}[v]
        x += c.w + 4
    im.image(3).save(f"{out}/sprites.png")

# --------------------------------------------------------------------------
# horizon pictures: 256x80, drawn as a 128-pixel pattern repeated twice

def sky(theme):
    return {"coast": sky_coast, "canyon": sky_canyon, "night": sky_night, "title": sky_title}[theme]()

def _tile2(half):
    c = Canvas(256, SKY_ROWS, 0)
    c.blit(half, 0, 0)
    c.blit(half, 128, 0)
    return c

def _cloud(c, x, y, w, col=0, under=None):
    for i, (dx, r) in enumerate(((0, 0.5), (0.28, 0.8), (0.55, 1.0), (0.8, 0.6))):
        c.ellipse(x + dx * w, y - r * 2, w * 0.2, 2 + r * 3, col, wrap=True)
    c.rect(int(x - w * 0.15), y - 2, int(x + w * 0.95), y, col, wrap=True)
    if under is not None:
        for xx in range(int(x - w * 0.1), int(x + w * 0.9), 2): c.set(xx, y + 1, under, wrap=True)

def sky_coast():
    c = Canvas(128, SKY_ROWS, 1)
    # setting sun, cut by horizontal slits
    for y in range(40, 70):
        for x in range(40, 90):
            if (x - 64.5) ** 2 + (y - 68) ** 2 <= 22 ** 2:
                slit = y >= 54 and (y - 54) % 4 >= 2 + (y - 54) // 8
                c.px[y][x] = 1 if slit else 0
    _cloud(c, 6, 30, 30, 0)
    _cloud(c, 92, 42, 26, 0)
    _cloud(c, 60, 20, 20, 0)
    # far islands
    for (x0, w, h) in ((2, 34, 9), (100, 24, 6)):
        for x in range(x0, x0 + w):
            t = (x - x0) / w
            top = 70 - int(h * math.sin(t * math.pi) ** 0.7)
            for y in range(top, 70): c.set(x, y, 2, wrap=True)
    # sea with glints
    for y in range(70, 80):
        for x in range(128):
            c.px[y][x] = 2
    c.rect(0, 70, 127, 70, 3)
    for (x, y, w) in ((58, 72, 14), (54, 74, 22), (60, 76, 10), (10, 73, 6), (100, 75, 8), (30, 77, 5), (84, 78, 7), (118, 72, 5)):
        c.rect(x, y, x + w, y, 0, wrap=True)
    return _tile2(c)

def sky_canyon():
    c = Canvas(128, SKY_ROWS, 0)
    c.ellipse(100, 26, 9, 9, 1)
    c.ellipse(100, 26, 7, 7, 0)
    for (x, y, w) in ((10, 22, 34), (20, 25, 18), (66, 40, 28), (60, 43, 16)):
        c.rect(x, y, x + w, y, 1, wrap=True)
    # far mesas (light), near buttes (dark with shadowed right faces)
    def mesa(x0, x1, top, col, shade=None, slope=3):
        for x in range(x0 - slope, x1 + slope + 1):
            if x < x0: t = top + (x0 - x) * 2
            elif x > x1: t = top + (x - x1) * 2
            else: t = top + ((x * 7) % 5 == 0)
            for y in range(t, 80):
                col2 = col
                if shade is not None and x > x1 - (x1 - x0) * 0.3: col2 = shade
                c.set(x, y, col2, wrap=True)
    mesa(4, 40, 58, 1)
    mesa(74, 122, 62, 1)
    mesa(48, 66, 50, 2, 3)
    mesa(100, 110, 44, 2, 3, slope=2)
    mesa(14, 24, 56, 2, 3, slope=2)
    for x in range(128):                      # ground line
        c.px[78][x] = 2 if c.px[78][x] == 0 else c.px[78][x]
        c.px[79][x] = 2
    return _tile2(c)

def sky_night():
    # night palette: 0 white, 1 dark gray, 2/3 black
    c = Canvas(128, SKY_ROWS, 2)
    import random
    rnd = random.Random(7)
    for _ in range(26):
        c.set(rnd.randrange(128), rnd.randrange(8, 52), 0)
    c.ellipse(24, 24, 7, 7, 0)
    c.ellipse(27, 22, 6, 6, 2)                # crescent moon
    x = 0
    heights = [18, 30, 12, 24, 38, 16, 28, 10, 22, 34, 14, 26, 20]
    widths = [10, 8, 12, 9, 7, 12, 10, 11, 9, 8, 12, 10, 10]
    for h, w in zip(heights, widths):
        top = 80 - h
        c.rect(x, top, x + w - 2, 79, 1, wrap=True)
        for wy in range(top + 3, 78, 4):
            for wx in range(x + 2, x + w - 3, 3):
                if rnd.random() < 0.45: c.set(wx, wy, 0, wrap=True); c.set(wx, wy + 1, 0, wrap=True)
        if h > 30:
            c.rect(x + w // 2 - 1, top - 6, x + w // 2 - 1, top, 1, wrap=True)
            c.set(x + w // 2 - 1, top - 7, 0, wrap=True)
        x += w
    return _tile2(c)

def sky_title():
    """Title card: the logo sits where the sky is."""
    c = Canvas(256, SKY_ROWS, 1)
    def word(text, y0, sx, sy, ink, cut, shadow):
        pitch = 6 * sx
        x0 = 128 - (len(text) * pitch - sx) // 2
        cells = []
        for k, ch in enumerate(text):
            for y, row in enumerate(font.GLYPHS[ch].split()):
                for x, v in enumerate(row):
                    if v == '#': cells.append((x0 + k * pitch + x * sx, y0 + y * sy))
        for (px, py) in cells:
            c.rect(px + shadow, py + shadow, px + sx - 1 + shadow, py + sy - 1 + shadow, 3)
        for (px, py) in cells:
            for yy in range(py, py + sy):
                c.rect(px, yy, px + sx - 1, yy, cut if (yy - y0) % 3 == 2 else ink)   # scanlines through the letters
    word("SCANLINE", 12, 3, 3, 0, 1, 2)
    word("SPRINT", 40, 4, 4, 0, 1, 2)
    for x in range(48, 208):
        c.px[73][x] = 3; c.px[74][x] = 3
        if x % 4 < 2: c.px[76][x] = 3
    for x in range(256):
        c.px[79][x] = 2
    return c
