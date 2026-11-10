"""Automatic player for ORBIT LANCE: reads the game's RAM, lines up under targets, keeps
firing and steps away from incoming shots. Used for long test runs and the mGBA comparison."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from gbpy import GB, KEYS

ROM = os.path.join(os.path.dirname(__file__), "..", "shooter", "build", "lance.gb")
SYM = ROM.replace(".gb", ".sym")

def s8(v): return v - 256 if v > 127 else v

class ShooterBot:
    def __init__(self, rom=ROM, sym=SYM, bombs=True):
        self.gb = GB(rom).load_sym(sym)
        self.log, self.loads, self.events = [], [], []
        self.use_bombs = bombs
        self.last = None

    def step(self, keys):
        gb = self.gb
        h0, c0 = gb.halt_cycles(), gb.cycles()
        gb.frame(keys)
        self.log.append(keys)
        self.loads.append(1 - (gb.halt_cycles() - h0) / max(1, gb.cycles() - c0))
        cur = (gb.rd("wState"), gb.rd("wStage"), gb.rd("wLoop"), gb.rd("wLives"))
        if cur != self.last:
            self.events.append((len(self.log), "state %d stage %d loop %d lives %d score %s" % (
                cur + ("".join(f"{gb.rd('wScore', i):02X}" for i in (2, 1, 0)) + "0",))))
            self.last = cur

    def keys(self):
        gb = self.gb
        if gb.rd("wState") != 1 or gb.rd("wPDead"): return 0
        px, py = gb.rd("wPX") + 8, gb.rd("wPY") + 8
        movers = []                             # (x, y, vx, vy) of everything dangerous
        def v88(lo, hi): return s8(hi) + lo / 256
        for i in range(12):
            b = gb.sym["wEShots"] + i * 16
            if gb.peek(b):
                movers.append((gb.peek(b + 2) + 4, gb.peek(b + 4) + 4,
                               v88(gb.peek(b + 5), gb.peek(b + 6)), v88(gb.peek(b + 7), gb.peek(b + 8)), 5))
        target, best = None, -1
        for i in range(8):
            b = gb.sym["wEnemies"] + i * 16
            t = gb.peek(b)
            if t in (1, 2, 3, 4, 6) and gb.peek(b + 4) > 8:
                co = 16 if t == 4 else 8
                ex, ey = gb.peek(b + 2) + co, gb.peek(b + 4) + co
                if t != 6: movers.append((ex, ey, v88(gb.peek(b + 5), gb.peek(b + 6)), v88(gb.peek(b + 7), gb.peek(b + 8)), co + 4))
                score = ey + (200 if t == 6 else 0)
                if score > best: best, target = score, ex
        def risk(dx):
            worst = 999
            x = px
            for t in range(1, 17):
                x = min(160, max(16, x + dx * 1.5))
                for (mx, my, vx, vy, r) in movers:
                    d = max(abs(mx + vx * t - x), abs(my + vy * t - py)) - r
                    worst = min(worst, d + t * 0.25)
            return worst
        options = []
        for dx in (-1, 0, 1):
            r = risk(dx)
            pull = 0 if target is None else -abs(target - (px + dx * 6)) / 40
            edge = -2 if (px < 28 and dx < 0) or (px > 132 and dx > 0) else 0
            options.append((min(r, 6) + pull + edge, dx))
        options.sort(reverse=True)
        dx = options[0][1]
        k = KEYS["a"]
        if dx < 0: k |= KEYS["left"]
        elif dx > 0: k |= KEYS["right"]
        if self.use_bombs and gb.rd("wBombs") and risk(dx) < 1.5: k |= KEYS["b"]
        if py < 128: k |= KEYS["down"]
        return k

    def play(self, max_frames=30000, stop_at_title=True, on_frame=None, start_stage=0):
        for _ in range(80): self.step(0)
        for _ in range(start_stage):
            for _ in range(4): self.step(KEYS["select"])
            for _ in range(6): self.step(0)
        for _ in range(20): self.step(0)
        for _ in range(4): self.step(KEYS["start"])
        seen_play = False
        for f in range(max_frames):
            self.step(self.keys())
            if on_frame: on_frame(len(self.log), self.gb)
            st = self.gb.rd("wState")
            if st == 1: seen_play = True
            if stop_at_title and seen_play and st == 0: break

if __name__ == "__main__":
    b = ShooterBot()
    b.play()
    gb = b.gb
    for e in b.events: print("  ", e)
    print("frames", len(b.log), "lag frames", gb.rd("hLagFrames"),
          "CPU max %.1f%% mean %.1f%%" % (max(b.loads[120:]) * 100, sum(b.loads[120:]) / len(b.loads[120:]) * 100))
