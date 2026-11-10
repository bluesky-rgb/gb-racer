"""Run a ROM with scripted input and save screenshots. Usage:
   shot.py rom out_prefix frame[,frame...] [keys@from-to ...]   e.g. a@0-600 right@200-260"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from gbpy import GB, KEYS

def parse_script(args):
    spans = []
    for a in args:
        k, rng = a.split("@")
        lo, hi = rng.split("-")
        m = 0
        for name in k.split("+"): m |= KEYS[name]
        spans.append((int(lo), int(hi), m))
    return spans

def keys_at(spans, f):
    m = 0
    for lo, hi, k in spans:
        if lo <= f < hi: m |= k
    return m

if __name__ == "__main__":
    rom, prefix, frames = sys.argv[1], sys.argv[2], [int(x) for x in sys.argv[3].split(",")]
    spans = parse_script(sys.argv[4:])
    gb = GB(rom)
    for f in range(max(frames) + 1):
        gb.frame(keys_at(spans, f))
        if f in frames: gb.png(f"{prefix}{f}.png", 2)
