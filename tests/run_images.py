"""Image-based tests: render a ROM and compare with a reference screenshot (shade-for-shade)."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from gbpy import GB
from PIL import Image

def shades(path):
    im = Image.open(path).convert("L")
    assert im.size == (160, 144), im.size
    px = list(im.tobytes())
    vals = sorted(set(px), reverse=True)
    return px, vals

def compare(rom, ref, frames=120):
    gb = GB(rom); gb.run(frames)
    px, vals = shades(ref)
    scr = gb.screen()
    lut = {255: 0, 170: 1, 85: 2, 0: 3}
    if all(v in lut for v in vals):
        return sum(1 for i in range(160 * 144) if lut[px[i]] != scr[i])
    # reference uses another palette: compare by brightness rank of the shades actually used
    lut = {v: i for i, v in enumerate(vals)}
    mine = {v: i for i, v in enumerate(sorted(set(scr)))}
    return sum(1 for i in range(160 * 144) if lut[px[i]] != mine[scr[i]])

if __name__ == "__main__":
    E = "/home/claude/ext"
    tests = [("dmg-acid2", f"{E}/mgba/cinema/gb/acid/dmg-acid2/test.gb", f"{E}/dmg-acid2/img/reference-dmg.png"),
             ("mooneye sprite_priority", f"{E}/mgba/cinema/gb/mooneye-gb/manual-only/sprite_priority/test.gb",
              f"{E}/mgba/cinema/gb/mooneye-gb/manual-only/sprite_priority/baseline_0000.png")]
    bad = 0
    for name, rom, ref in tests:
        d = compare(rom, ref)
        print("PASS" if d == 0 else "FAIL", name, f"({d} differing pixels)")
        bad += d != 0
    sys.exit(bad)
