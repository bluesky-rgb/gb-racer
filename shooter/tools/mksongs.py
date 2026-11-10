"""Original music for ORBIT LANCE (build/music.asm). The lead is on pulse 2 because
pulse 1 is shared with the sound effects (every shot uses it)."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "tools"))
from chiptune import Song, write

songs = []
def arps(chords, arp_of, n=8):
    return " ".join(f"arp{arp_of[c[-1] == 'm']} {c.rstrip('m')}:{n}" for c in chords)

# ---------------------------------------------------------------- title (E minor, spacious)
s = Song("Title", 8); songs.append(s)
s.pat("lead", "i5 e5:4 g5:2 b5:2 e6:6 d6:2 | c6:4 b5:2 a5:2 b5:8 | e5:4 g5:2 b5:2 f#6:6 e6:2 | d6:4 b5:4 e6:8")
s.pat("arp", "i3 arp2 e4:16 arp1 c4:16 arp2 e4:16 arp1 d4:8 arp2 b3:8")
s.pat("bass", "L4 e2 e3 e2 e3 c2 c3 c2 c3 e2 e3 e2 e3 d2 d3 b2 b3")
s.pat("drm", "k:4 h:4 s:4 h:4 " * 4, drums=True)
s.chan(1, "lead"); s.chan(0, "arp"); s.chan(2, "bass"); s.chan(3, "drm")

# ---------------------------------------------------------------- stage 1 (A minor drive)
s = Song("Stage1", 6); songs.append(s)
s.pat("l1", "i0 a4:2 c5:2 e5:2 a5:4 g5:2 e5:2 g5:2 | f5:2 e5:2 d5:2 c5:2 d5:4 e5:4")
s.pat("l2", "i0 a4:2 c5:2 e5:2 a5:4 b5:2 c6:2 b5:2 | a5:2 g5:2 e5:2 g5:2 a5:8")
s.pat("l3", "i5 c6:6 b5:2 a5:4 e5:4 | f5:6 g5:2 a5:4 c6:4 | b5:6 a5:2 g5:4 d5:4 | e5:12 r:4")
s.pat("ar1", "i3 arp2 a3:8 arp1 f3:8 arp1 c4:8 arp1 g3:8")
s.pat("ar2", "i3 arp1 f3:16 arp1 c4:16 arp1 g3:16 arp7 e3:16")
s.pat("b1", "L2 a2 a2 a3 a2 a2 a2 a3 a2 f2 f2 f3 f2 g2 g2 g3 g2")
s.pat("b2", "L2 f2 f2 f3 f2 f2 f2 f3 f2 c3 c3 c4 c3 c3 c3 c4 c3 g2 g2 g3 g2 g2 g2 g3 g2 e2 e2 e3 e2 e2 e2 e3 e2")
s.pat("d1", "L2 k h s h k k s h k h s h k k s s", drums=True)
s.pat("d2", "L2 k h s h k k s h " * 3 + "k k s k s s t t", drums=True)
s.chan(1, "l1 l2 l3"); s.chan(0, "ar1 ar1 ar2"); s.chan(2, "b1 b1 b2"); s.chan(3, "d1 d1 d2")

# ---------------------------------------------------------------- stage 2 (D dorian, bouncy)
s = Song("Stage2", 6); songs.append(s)
s.pat("l1", "i6 d5:2 r:1 d5:1 f5:2 a5:2 g5:2 f5:2 e5:2 c5:2 | d5:2 r:1 d5:1 f5:2 a5:2 c6:4 b5:4")
s.pat("l2", "i5 a5:4 g5:2 f5:2 g5:4 a5:4 | c6:4 a5:2 g5:2 a5:8 | d6:4 c6:2 a5:2 g5:4 f5:4 | e5:4 g5:4 d5:8")
s.pat("ar1", "i3 arp2 d4:8 arp1 c4:8 arp2 d4:8 arp1 g3:8")
s.pat("ar2", "i3 arp1 f3:8 arp1 c4:8 arp1 f3:8 arp1 c4:8 arp1 a#3:8 arp1 f3:8 arp1 c4:8 arp2 d4:8")
s.pat("b1", "L2 d2 r d3 d2 r d2 d3 r c2 r c3 c2 r c2 c3 r d2 r d3 d2 r d2 d3 r g2 r g3 g2 a2 r a3 r")
s.pat("b2", "L2 f2 r f3 f2 c3 r c4 c3 f2 r f3 f2 c3 r c4 c3 a#2 r a#3 a#2 f2 r f3 f2 c3 r c4 c3 d3 r d4 d3")
s.pat("d1", "L2 k h s k h k s h", drums=True)
s.chan(1, "l1 l1 l2"); s.chan(0, "ar1 ar1 ar2"); s.chan(2, "b1 b2"); s.chan(3, "d1 d1 d1 d1 d1 d1 d1 d1")

# ---------------------------------------------------------------- stage 3 (C minor, driving)
s = Song("Stage3", 5); songs.append(s)
s.pat("l1", "i0 c5:2 d#5:2 g5:2 c6:2 a#5:2 g5:2 d#5:2 g5:2 | g#5:2 g5:2 f5:2 d#5:2 d5:4 g4:4")
s.pat("l2", "i5 c6:4 d6:4 d#6:4 d6:2 c6:2 | a#5:4 g#5:4 g5:8 | g#5:4 a#5:4 c6:4 a#5:2 g#5:2 | g5:4 f5:4 g5:8")
s.pat("ar1", "i3 arp2 c4:8 arp1 g#3:8 arp1 d#4:8 arp1 g3:8")
s.pat("ar2", "i3 arp1 g#3:16 arp7 g3:16 arp1 g#3:16 arp7 g3:16")
s.pat("b1", "L1 " + "c2 c2 c3 c2 " * 4 + "g#2 g#2 g#3 g#2 " * 2 + "g2 g2 g3 g2 " * 2)
s.pat("b2", "L1 " + "g#2 g#2 g#3 g#2 " * 4 + "g2 g2 g3 g2 " * 4 + "g#2 g#2 g#3 g#2 " * 4 + "g2 g2 g3 g2 " * 4)
s.pat("d1", "L2 k h s h k h s k", drums=True)
s.chan(1, "l1 l2"); s.chan(0, "ar1 ar2"); s.chan(2, "b1 b2"); s.chan(3, "d1 d1 d1 d1 d1 d1")

# ---------------------------------------------------------------- boss (tense, chromatic)
s = Song("Boss", 6); songs.append(s)
s.pat("l1", "i4 e5:2 e5:2 f5:2 e5:2 r:2 e5:2 g5:2 f5:2 | e5:2 e5:2 f5:2 e5:2 r:2 b4:2 c5:2 d5:2")
s.pat("l2", "i5 e6:6 d#6:2 d6:4 c#6:4 | c6:6 b5:2 a#5:4 b5:4")
s.pat("ar", "i3 arp2 e4:8 arp1 f4:8 arp2 e4:8 arp7 b3:8")
s.pat("b1", "L1 " + "e2 e2 e3 e2 " * 8)
s.pat("d1", "L2 k k s k k k s s", drums=True)
s.chan(1, "l1 l2"); s.chan(0, "ar ar"); s.chan(2, "b1 b1"); s.chan(3, "d1 d1 d1 d1")

# ---------------------------------------------------------------- jingles
s = Song("Clear", 6); songs.append(s); s.loop = False
s.pat("l", "i5 g5:2 c6:2 e6:2 g6:4 e6:2 g6:2 c6:2 d6:2 e6:2 c6:12 r:4")
s.pat("h", "i3 arp1 c4:8 arp1 g3:8 arp1 c4:16 r:4")
s.pat("d", "L2 k k s k s s t t k:12 r:8", drums=True)
s.chan(1, "l"); s.chan(0, "h"); s.chan(3, "d")
s = Song("Over", 9); songs.append(s); s.loop = False
s.pat("l", "i1 b4:4 a#4:4 a4:4 g#4:4 g4:12 r:4")
s.pat("h", "i2 arp2 e3:8 d#3:8 e3:12 r:4")
s.chan(1, "l"); s.chan(0, "h")

write(songs, sys.argv[1])
