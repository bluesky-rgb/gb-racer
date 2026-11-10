"""Play each course with the bot in our emulator, replay the recorded inputs in mGBA,
and compare every frame. Saves matching screenshot pairs to docs/screenshots/."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from gbpy import GB, write_png, KEYS
from mgbapy import MGBA
from bot import Bot, ROM

out = sys.argv[1] if len(sys.argv) > 1 else "build/verify"
os.makedirs(out, exist_ok=True)
total = bad = 0
def replay(name, log, shots):
    global total, bad
    a, b = GB(ROM), MGBA(ROM)
    nd, first = 0, None
    for f, k in enumerate(log):
        a.frame(k); b.frame(k)
        sa, sb = a.screen(), b.screen()
        if sa != sb:
            nd += 1
            if first is None:
                first = f
                write_png(f"{out}/{name}_MISMATCH{f}_ours.png", sa, 2); write_png(f"{out}/{name}_MISMATCH{f}_mgba.png", sb, 2)
        if f in shots:
            write_png(f"{out}/{name}_f{f:05d}_ours.png", sa, 2); write_png(f"{out}/{name}_f{f:05d}_mgba.png", sb, 2)
    b.close()
    total += len(log); bad += nd
    print(f"{name}: {len(log)} frames replayed, {nd} differ" + (f" (first at {first})" if nd else ""))

# title + course select, no race
log = [0] * 100 + [KEYS["start"]] * 4 + [0] * 40 + [KEYS["right"]] * 4 + [0] * 40 + [KEYS["left"]] * 4 + [0] * 60
replay("title", log, {60, 140, 200})
for course, name in enumerate(("coast", "canyon", "night")):
    bot = Bot(course)
    bot.menu()
    res = bot.race()
    n = len(bot.log)
    shots = {300, 420, 900, 1800, 2700, 3600, 5000, n - 150}
    print(f"{name}: bot result {'FINISHED' if res == 2 else 'TIME UP'}, position {bot.gb.rd('wPosition')}, max CPU load {max(bot.loads[420:]) * 100:.1f}%")
    replay(name, bot.log, shots)
# a run with no steering: collisions, off-road and the time-up ending
bot = Bot(1)
bot.menu()
for f in range(3600): bot.step(KEYS["a"] if 300 < f else 0)
replay("timeup", bot.log, {1500, 3000, 3700})
print(f"TOTAL: {total} frames compared, {bad} differ")
