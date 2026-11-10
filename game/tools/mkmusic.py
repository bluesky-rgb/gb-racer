"""Original chiptune score for the game, written in a tiny text notation and compiled
to the sound driver's byte streams (build/music.asm).

Notation: notes like c4 f#5 (C2 is the lowest), r = rest, optional :n length in ticks
(a tick is a sixteenth note), Ln = default length, iN = instrument, arpN = arpeggio type,
drum names k s h o t on the noise channel."""
import sys, re

NOTE_IX = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
DRUMS = {"k": 0, "s": 1, "h": 2, "o": 3, "t": 4}
REST = 0x48

def compile_seq(text, drums=False):
    out, cur_len = [], None
    def set_len(n):
        nonlocal cur_len
        if n != cur_len:
            assert 1 <= n <= 64, n
            out.append(0x80 | (n - 1)); cur_len = n
    default = 1
    total = 0
    for tok in text.split():
        if tok == "|": continue
        if tok[0] == "L" and tok[1:].isdigit(): default = int(tok[1:]); continue
        if tok[0] == "i" and tok[1:].isdigit(): out.append(0xC0 | int(tok[1:])); continue
        if tok.startswith("arp"): out.append(0xD0 | int(tok[3:])); continue
        name, _, ln = tok.partition(":")
        n = int(ln) if ln else default
        if name == "r": v = REST
        elif drums: v = DRUMS[name]
        else:
            m = re.fullmatch(r"([a-g])(#?)(\d)", name)
            assert m, tok
            v = NOTE_IX[m.group(1)] + (1 if m.group(2) else 0) + (int(m.group(3)) - 2) * 12
            assert 0 <= v < 72, tok
        set_len(n)
        out.append(v)
        total += n
    return out, total

class Song:
    def __init__(self, name, tempo):
        self.name, self.tempo = name, tempo
        self.patterns = {}          # name -> (bytes, ticks)
        self.order = [None] * 4     # per channel: list of pattern names
        self.loop = True
    def pat(self, name, text, drums=False):
        self.patterns[name] = compile_seq(text, drums)
    def chan(self, ch, names):
        self.order[ch] = names.split()

songs = []

# ------------------------------------------------------------------ title
s = Song("Title", 7); songs.append(s)
s.pat("l1", "i5 e5:2 g5:2 c6:4 b5:2 c6:2 g5:4 | d5:2 g5:2 b5:4 a5:2 b5:2 g5:4")
s.pat("l2", "i5 c5:2 e5:2 a5:4 g5:2 a5:2 e5:4 | f5:2 a5:2 c6:4 d6:2 b5:2 g5:4")
s.pat("l3", "i5 g5:4 e5:2 g5:2 c6:6 r:2 | b5:4 g5:2 b5:2 d6:6 r:2")
s.pat("l4", "i5 c6:2 b5:2 a5:2 g5:2 a5:4 f5:4 | g5:2 a5:2 b5:2 d6:2 c6:8")
s.pat("h1", "i3 arp1 L4 c4 c4 c4 c4 | g3 g3 g3 g3")
s.pat("h2", "i3 arp2 L4 a3 a3 a3 a3 | arp1 f3 f3 g3 g3")
s.pat("b1", "L2 c3 c3 c4 c3 c3 c3 c4 c3 | g2 g2 g3 g2 g2 g2 g3 g2")
s.pat("b2", "L2 a2 a2 a3 a2 a2 a2 a3 a2 | f2 f2 f3 f2 g2 g2 g3 g2")
s.pat("d1", "L2 k h s h k k s h | k h s h k h s s", drums=True)
s.chan(0, "l1 l2 l3 l4")
s.chan(1, "h1 h2 h1 h2")
s.chan(2, "b1 b2 b1 b2")
s.chan(3, "d1 d1 d1 d1")

# ------------------------------------------------------------------ course 1: Sunset Coast (G major)
s = Song("Coast", 6); songs.append(s)
s.pat("a1", "i5 d5:2 g5:2 b5:3 a5:3 g5:2 r:4 | e5:2 g5:2 b5:3 a5:3 g5:2 e5:4")
s.pat("a2", "i5 e5:2 g5:2 c6:3 b5:3 g5:2 e5:4 | f#5:2 a5:2 d6:4 c6:2 b5:2 a5:4")
s.pat("a3", "i5 g5:2 b5:2 d6:3 b5:3 g5:2 b5:4 | g5:2 b5:2 e6:3 d6:3 b5:2 g5:4")
s.pat("a4", "i5 c6:2 b5:2 a5:2 g5:2 e5:4 g5:4 | a5:4 f#5:2 a5:2 d6:6 r:2")
s.pat("b1", "i0 e5:1 g5:1 c6:2 e5:1 g5:1 c6:2 e6:4 c6:4 | f#5:1 a5:1 d6:2 f#5:1 a5:1 d6:2 f#6:4 d6:4")
s.pat("b2", "i0 d5:1 f#5:1 b5:2 d5:1 f#5:1 b5:2 d6:4 b5:4 | e5:1 g5:1 b5:2 e5:1 g5:1 b5:2 e6:6 r:2")
s.pat("b3", "i5 c6:3 b5:3 a5:2 g5:4 e5:4 | d6:3 c6:3 b5:2 a5:4 f#5:4")
s.pat("b4", "i5 g5:2 a5:2 b5:2 d6:2 g6:8 | f#6:2 e6:2 d6:2 a5:2 d6:6 r:2")
def oom(root, chord, arp):
    return f"i2 arp0 {root}:2 i3 arp{arp} {chord}:2 " * 4
s.pat("hG", oom("g2", "g4", 1)); s.pat("hEm", oom("e2", "e4", 2))
s.pat("hC", oom("c3", "c4", 1)); s.pat("hD", oom("d3", "d4", 1)); s.pat("hBm", oom("b2", "b3", 2))
s.pat("d1", "L2 k h s h k k s h", drums=True)
s.pat("d2", "L2 k h s h k k s:1 s:1 t", drums=True)
s.chan(0, "a1 a2 a3 a4 b1 b2 b3 b4")
s.chan(1, "hG hEm hC hD hG hEm hC hD hC hD hBm hEm hC hD hG hD")
s.chan(3, "d1 d1 d1 d2 d1 d1 d1 d2 d1 d1 d1 d2 d1 d1 d1 d2")

# ------------------------------------------------------------------ course 2: Mesa Canyon (A minor)
s = Song("Canyon", 6); songs.append(s)
s.pat("a1", "i6 L2 a4 c5 e5 a5 g5 e5 c5 e5 | a4 c5 f5 a5 g5 f5 c5 f5")
s.pat("a2", "i6 L2 b4 d5 g5 b5 a5 g5 d5 g5 | b4 e5 g5 b5 a5:4 g5 e5")
s.pat("a3", "i5 e5:6 d5:2 c5:4 a4:4 | f5:6 e5:2 c5:4 a4:4")
s.pat("a4", "i5 g5:6 f5:2 d5:4 b4:4 | e5:4 g5:4 b5:6 r:2")
s.pat("b1", "i5 c6:4 a5:2 f5:2 a5:4 c6:4 | d6:4 b5:2 g5:2 b5:4 d6:4")
s.pat("b2", "i5 e6:3 d6:3 c6:2 a5:4 e5:4 | a5:2 g5:2 e5:2 c5:2 a4:6 r:2")
def gallop(root, hi):
    return f"i2 arp0 {root}:2 {root}:1 {root}:1 i3 arp7 {hi}:2 i2 arp0 {root}:2 " * 2
s.pat("hAm", gallop("a2", "a3")); s.pat("hF", gallop("f2", "f3"))
s.pat("hG", gallop("g2", "g3")); s.pat("hEm", gallop("e2", "e3"))
s.pat("d1", "L2 k h s h k k s h", drums=True)
s.pat("d2", "L2 k k s h k:1 k:1 t s t", drums=True)
s.chan(0, "a1 a2 a3 a4 b1 b2")
s.chan(1, "hAm hF hG hEm hAm hF hG hEm hF hG hAm hAm")
s.chan(3, "d1 d1 d1 d2 d1 d1 d1 d2 d1 d1 d1 d2")

# ------------------------------------------------------------------ course 3: Neon Night (D minor)
s = Song("Night", 7); songs.append(s)
s.pat("a1", "i1 d5:3 f5:3 a5:2 r:2 g5:2 f5:2 d5:2 | d5:3 f5:3 a#5:2 r:2 a5:2 f5:2 d5:2")
s.pat("a2", "i1 e5:3 g5:3 c6:2 r:2 a#5:2 g5:2 e5:2 | e5:3 a5:3 c6:2 r:2 a5:2 g5:2 e5:2")
s.pat("a3", "i5 a5:2 r:1 a5:1 a5:2 g5:2 f5:2 g5:2 a5:4 | a#5:2 r:1 a#5:1 a#5:2 a5:2 f5:2 a5:2 a#5:4")
s.pat("a4", "i5 c6:2 r:1 c6:1 c6:2 a#5:2 g5:2 a#5:2 c6:4 | a5:4 g5:2 e5:2 a5:6 r:2")
s.pat("b1", "i0 f5:2 a#5:2 d6:4 c6:2 a#5:2 f5:4 | g5:2 c6:2 e6:4 d6:2 c6:2 g5:4")
s.pat("b2", "i0 a5:2 d6:2 f6:4 e6:2 d6:2 a5:4 | d6:2 c6:2 a5:2 g5:2 f5:2 e5:2 d5:4")
def funk(lo, hi):
    return f"i2 arp0 {lo}:2 {hi}:2 r:1 {lo}:1 {hi}:2 {lo}:2 {hi}:2 r:1 {lo}:1 {hi}:2 "
s.pat("hDm", funk("d2", "d3")); s.pat("hBb", funk("a#2", "a#3"))
s.pat("hC", funk("c3", "c4")); s.pat("hAm", funk("a2", "a3"))
s.pat("d1", "k:2 h:2 s:2 h:2 k:1 k:1 h:2 s:2 h:1 h:1", drums=True)
s.pat("d2", "k:2 h:2 s:2 o:2 k:1 k:1 h:2 s:1 s:1 t:2", drums=True)
s.chan(0, "a1 a2 a3 a4 b1 b2")
s.chan(1, "hDm hBb hC hAm hDm hBb hC hAm hBb hC hDm hDm")
s.chan(3, "d1 d1 d1 d2 d1 d1 d1 d2 d1 d1 d1 d2")

# ------------------------------------------------------------------ jingles
s = Song("Finish", 6); songs.append(s); s.loop = False
s.pat("l", "i5 c5:2 e5:2 g5:2 c6:4 g5:2 c6:2 e6:2 d6:2 e6:2 g6:12")
s.pat("h", "i3 arp1 c4:4 c4:4 c4:4 g4:4 c5:8 r:8")
s.pat("d", "L2 k k s k k s s s t:4 k:8 r:4", drums=True)
s.chan(0, "l"); s.chan(1, "h"); s.chan(3, "d")

s = Song("GameOver", 9); songs.append(s); s.loop = False
s.pat("l", "i1 a4:4 g4:4 f4:4 e4:4 d4:12")
s.pat("h", "i2 arp2 d3:8 a#2:8 a2:12")
s.chan(0, "l"); s.chan(1, "h")

# ------------------------------------------------------------------ output
out = ["; generated by tools/mkmusic.py - do not edit", 'SECTION "Music", ROM0', "FreqTable:"]
for n in range(72):
    f = 65.406 * 2 ** (n / 12)
    out.append(f"    dw {int(round(2048 - 131072 / f))}")
size = 144
for s in songs:
    lens = set()
    for ch in range(4):
        if s.order[ch]: lens.add(sum(s.patterns[p][1] for p in s.order[ch]))
    assert len(lens) == 1, (s.name, lens)
    out.append(f"Song{s.name}::")
    out.append(f"    db {s.tempo}")
    for ch in range(4):
        out.append(f"    dw {'Song' + s.name + '_ch' + str(ch) if s.order[ch] else '0'}")
    size += 9
    for ch in range(4):
        if not s.order[ch]: continue
        out.append(f"Song{s.name}_ch{ch}:")
        for p in s.order[ch]:
            out.append(f"    db $F2\n    dw Song{s.name}_{p}")
        if s.loop: out.append(f"    db $F0\n    dw Song{s.name}_ch{ch}")
        else: out.append("    db $F1")
        size += 3 * len(s.order[ch]) + 3
    for name, (data, ticks) in s.patterns.items():
        out.append(f"Song{s.name}_{name}:")
        out.append("    db " + ",".join(f"${b:02X}" for b in data) + ",$F3")
        size += len(data) + 1
    print(f"song {s.name}: {lens.pop()} ticks, tempo {s.tempo}")
open(sys.argv[1], "w").write("\n".join(out) + "\n")
print("music bytes:", size)
