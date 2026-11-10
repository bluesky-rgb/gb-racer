"""Replay the same input script in our emulator and in mGBA and compare every frame.
   compare.py rom nframes [keys@from-to ...] [--save prefix f1,f2,..] [--offset n]"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from gbpy import GB, write_png
from mgbapy import MGBA
from shot import parse_script, keys_at

def compare(rom, n, spans, save=None, frames=(), offset=0, quiet=False, keyfn=None):
    a, b = GB(rom), MGBA(rom)
    for _ in range(offset): b.frame(0)
    ndiff, first, worst = 0, None, (0, 0)
    for f in range(n):
        k = keyfn(f, a) if keyfn else keys_at(spans, f)
        a.frame(k); b.frame(k)
        sa, sb = a.screen(), b.screen()
        if sa != sb:
            d = sum(1 for x, y in zip(sa, sb) if x != y)
            ndiff += 1
            if first is None: first = f
            if d > worst[1]: worst = (f, d)
            if save and (ndiff <= 3):
                write_png(f"{save}diff{f}_ours.png", sa, 2); write_png(f"{save}diff{f}_mgba.png", sb, 2)
        if save and f in frames:
            write_png(f"{save}{f}_ours.png", sa, 2); write_png(f"{save}{f}_mgba.png", sb, 2)
    b.close()
    if not quiet: print(f"{n} frames: {ndiff} differ; first at {first}; worst {worst}")
    return ndiff, first, worst

if __name__ == "__main__":
    args = sys.argv[1:]
    save, frames, offset = None, [], 0
    if "--save" in args:
        i = args.index("--save"); save = args[i + 1]; frames = [int(x) for x in args[i + 2].split(",")]; del args[i:i + 3]
    if "--offset" in args:
        i = args.index("--offset"); offset = int(args[i + 1]); del args[i:i + 2]
    compare(args[0], int(args[1]), parse_script(args[2:]), save, frames, offset)
