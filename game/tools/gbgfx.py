"""Shared helpers for the asset generators: indexed images -> Game Boy 2bpp tiles."""
from PIL import Image

GRAY = [(255, 255, 255), (170, 170, 170), (85, 85, 85), (0, 0, 0)]


class Canvas:
    """A small indexed (0..3, or None for transparent) pixel canvas."""
    def __init__(self, w, h, fill=0):
        self.w, self.h = w, h
        self.px = [[fill] * w for _ in range(h)]

    def set(self, x, y, c, wrap=False):
        if wrap: x %= self.w
        if 0 <= x < self.w and 0 <= y < self.h: self.px[y][x] = c

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def rect(self, x0, y0, x1, y1, c, wrap=False):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): self.set(x, y, c, wrap)

    def ellipse(self, cx, cy, rx, ry, c, wrap=False):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0: self.set(x, y, c, wrap)

    def poly(self, pts, c, wrap=False):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            yc = y + 0.5
            for i in range(len(pts)):
                (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
                if (y0 <= yc < y1) or (y1 <= yc < y0):
                    xs.append(x0 + (yc - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(round(xs[i])), int(round(xs[i + 1]))): self.set(x, y, c, wrap)

    def line(self, x0, y0, x1, y1, c, wrap=False):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n + 1):
            t = i / n
            self.set(int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t)), c, wrap)

    def blit(self, other, ox, oy, wrap=False):
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[y][x]
                if c is not None: self.set(ox + x, oy + y, c, wrap)

    def text_rows(self, rows, ox, oy, key):
        """Stamp ASCII-art rows; `key` maps characters to colours (missing = skip)."""
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in key: self.set(ox + x, oy + y, key[ch])

    def image(self, scale=1, bg=(255, 0, 255)):
        im = Image.new("RGB", (self.w, self.h))
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y][x]
                im.putpixel((x, y), bg if c is None else GRAY[c])
        return im.resize((self.w * scale, self.h * scale), Image.NEAREST) if scale != 1 else im


def tile_bytes(px, tx, ty, transparent=0):
    """8x8 tile at (tx,ty) of a 2D index array -> 16 bytes of 2bpp data."""
    out = bytearray()
    for y in range(8):
        lo = hi = 0
        for x in range(8):
            c = px[ty + y][tx + x]
            if c is None: c = transparent
            lo = (lo << 1) | (c & 1)
            hi = (hi << 1) | (c >> 1)
        out += bytes([lo, hi])
    return bytes(out)


class TileSet:
    """Deduplicating tile store."""
    def __init__(self, base=0):
        self.tiles, self.index, self.base = [], {}, base

    def add(self, data, dedup=True):
        if dedup and data in self.index: return self.index[data]
        i = self.base + len(self.tiles)
        self.tiles.append(data)
        if dedup: self.index.setdefault(data, i)
        return i

    def add_image(self, canvas, dedup=True):
        """Returns a row-major list of tile indices covering the canvas."""
        ids = []
        for ty in range(0, canvas.h, 8):
            for tx in range(0, canvas.w, 8):
                ids.append(self.add(tile_bytes(canvas.px, tx, ty), dedup))
        return ids

    def data(self): return b"".join(self.tiles)
    def __len__(self): return len(self.tiles)
