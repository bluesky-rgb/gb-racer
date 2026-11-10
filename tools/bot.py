"""A simple driver that plays the game by reading its RAM. Used to exercise whole races,
measure CPU load and produce input logs that can be replayed in mGBA.
   bot.py course [--frames N] [--log file] [--shots prefix f1,f2,...] [--skill s]"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from gbpy import GB, KEYS

ROM = os.path.join(os.path.dirname(__file__), "..", "game", "build", "racer.gb")
SYM = ROM.replace(".gb", ".sym")

def s8(v): return v - 256 if v > 127 else v

class Bot:
    def __init__(self, course=0, skill=1.0, rom=ROM, sym=SYM):
        self.gb = GB(rom).load_sym(sym)
        self.course, self.skill = course, skill
        self.log = []
        self.loads = []
        self.events = []

    def step(self, keys):
        gb = self.gb
        h0, c0 = gb.halt_cycles(), gb.cycles()
        gb.frame(keys)
        self.log.append(keys)
        self.loads.append(1 - (gb.halt_cycles() - h0) / max(1, gb.cycles() - c0))

    def menu(self):
        for _ in range(100): self.step(0)
        for _ in range(4): self.step(KEYS["start"])
        for _ in range(20): self.step(0)
        for _ in range(self.course):
            for _ in range(4): self.step(KEYS["right"])
            for _ in range(10): self.step(0)
        for _ in range(4): self.step(KEYS["a"])

    def drive_keys(self):
        gb = self.gb
        x = s8(gb.rd("wPlayerX", 1))
        curve = s8(gb.rd("wCurCurve"))
        speed = gb.rd("wSpeed", 1)
        target = curve * 5 * self.skill          # hug the inside of the bend
        # avoid the nearest rival ahead in our lane
        for i in range(7):
            row = gb.rd("wRivalRow", i)
            if row != 0xFF and row >= 30:
                lat = s8(gb.rd("wRivals", i * 8 + 6)) * 9
                if abs(lat - x) < 40:
                    target = lat + 46 if lat < 10 else lat - 46
                break
        keys = KEYS["a"]
        if x < target - 3: keys |= KEYS["right"]
        elif x > target + 3: keys |= KEYS["left"]
        if abs(x) > 70 and speed > 0x14: keys &= ~KEYS["a"]     # about to leave the road: lift
        return keys

    def race(self, max_frames=20000, on_frame=None):
        gb = self.gb
        last = (None, None)
        for f in range(max_frames):
            state = gb.rd("wRaceState")
            keys = self.drive_keys() if state == 1 else 0
            self.step(keys)
            cur = (gb.rd("wLap"), state)
            if cur != last:
                self.events.append((len(self.log), "lap %d state %d time %d pos %d" % (cur[0], state, gb.rd("wTimeLeft"), gb.rd("wPosition"))))
                last = cur
            if on_frame: on_frame(len(self.log), gb)
            if state in (2, 3) and gb.rd16("wStateTimer") > 200: break
        return gb.rd("wRaceState")

if __name__ == "__main__":
    args = sys.argv[1:]
    course = int(args[0])
    skill = 1.0
    shots, prefix, logf = [], None, None
    if "--shots" in args:
        i = args.index("--shots"); prefix = args[i + 1]; shots = [int(x) for x in args[i + 2].split(",")]
    if "--log" in args: logf = args[args.index("--log") + 1]
    if "--skill" in args: skill = float(args[args.index("--skill") + 1])
    b = Bot(course, skill)
    b.menu()
    n0 = len(b.log)
    def snap(f, gb):
        if f in shots: gb.png(f"{prefix}{f}.png", 2)
    res = b.race(on_frame=snap)
    gb = b.gb
    print("result:", {2: "FINISHED", 3: "TIME UP"}.get(res, res), "frames", len(b.log),
          "total %d'%02d\"" % (gb.rd("wTotMin"), gb.rd("wTotSec")), "position", gb.rd("wPosition"), "clock left", gb.rd("wTimeLeft"))
    for e in b.events: print("  ", e)
    race_loads = b.loads[n0 + 260:]
    print("CPU load during race: max %.1f%% mean %.1f%%; frames over 95%%: %d; lag frames: %d" % (
        max(race_loads) * 100, sum(race_loads) / len(race_loads) * 100, sum(1 for l in race_loads if l > 0.95), gb.rd("hLagFrames")))
    if logf: open(logf, "wb").write(bytes(b.log))
