"""Road textures: for every track theme, two 256x72 perspective road images (light and dark
stripe variants) that the raster effect picks lines from."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from gbgfx import Canvas
from geom import ROWS, half_width

def bayer(x, y):
    return [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]][y & 3][x & 3]

# ground patterns: (x, y, variant) -> colour index. Periods divide 256 so the map wraps.
def ground_grass(x, y, v):
    if v == 0: return 1
    return 2 if ((x + y) & 1) else 1                 # checker dither: darker band

def ground_sand(x, y, v):
    if v == 0: return 1 if bayer(x, y) < 3 else 0    # pale sand with light speckle
    return 1                                           # flat light band

def ground_night(x, y, v):
    if v == 0: return 1
    return 2 if bayer(x, y) < 6 else 1

THEMES = {
    "coast":  dict(ground=ground_grass, road=2, rumble=(0, 3), dash=0, edge=None),
    "canyon": dict(ground=ground_sand,  road=2, rumble=(3, 0), dash=0, edge=None),
    "night":  dict(ground=ground_night, road=2, rumble=(0, 3), dash=0, edge=0),
    "title":  dict(ground=ground_grass, road=2, rumble=(0, 3), dash=0, edge=None),
}

def road_canvas(theme):
    t = THEMES[theme]
    c = Canvas(256, ROWS * 2)
    for v in (0, 1):
        for r in range(ROWS):
            y = v * ROWS + r
            w = half_width(r)
            rw = max(1.0, w * 0.13)
            dash = max(1, int(round(w * 0.05)))
            for x in range(256):
                d = abs(x + 0.5 - 128)
                if d > w + rw: col = t["ground"](x, r, v)
                elif d > w: col = t["rumble"][v]
                else:
                    col = t["road"]
                    if t["edge"] is not None and w - d < max(1.0, w * 0.04): col = t["edge"]
                    if v == 0 and d * 2 < dash: col = t["dash"]
                c.px[y][x] = col
    return c

if __name__ == "__main__":
    from gbgfx import TileSet
    for name in THEMES:
        cv = road_canvas(name)
        ts = TileSet(); ts.add_image(cv)
        print(name, "unique road tiles:", len(ts))
        cv.image(2).save(f"build/road_{name}.png")
