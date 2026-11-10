"""Sampling profiler for the game: attributes T-cycles to the routine (global label) the PC is in.
   profile.py rom sym warm_frames n_frames [keys@from-to ...]"""
import sys, os, bisect
sys.path.insert(0, os.path.dirname(__file__))
from gbpy import GB
from shot import parse_script, keys_at

def main():
    rom, symf, warm, n = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    spans = parse_script(sys.argv[5:])
    labels = []
    for line in open(symf):
        p = line.split()
        if len(p) == 2 and ":" in p[0] and "." not in p[1]:
            b, a = p[0].split(":"); a = int(a, 16)
            if a < 0x8000 or 0xC200 <= a < 0xC300 or a >= 0xFF80: labels.append((a, p[1]))
    labels.sort()
    addrs = [a for a, _ in labels]
    gb = GB(rom)
    for f in range(warm): gb.frame(keys_at(spans, f))
    acc = {}
    total0 = gb.cycles()
    import gbpy
    for f in range(warm, warm + n):
        gbpy._lib.gb_set_keys(gb.g, keys_at(spans, f))
        line_prev = gb.line()
        while True:
            pc = gb.pc(); c0 = gb.cycles(); halted = gb.halted()
            gb.step()
            i = bisect.bisect_right(addrs, pc) - 1
            name = "HALT (idle)" if halted else labels[i][1]
            acc[name] = acc.get(name, 0) + gb.cycles() - c0
            ln = gb.line()
            if ln == 144 and line_prev != 144: break
            line_prev = ln
    total = gb.cycles() - total0
    for name, c in sorted(acc.items(), key=lambda kv: -kv[1])[:24]:
        print(f"{name:22s} {c / n / 4:8.0f} cycles/frame  {100 * c / total:5.1f}%")

main()
