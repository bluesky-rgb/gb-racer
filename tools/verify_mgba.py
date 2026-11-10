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
def replay(name, log, shots, rom=ROM):
    global total, bad
    a, b = GB(rom), MGBA(rom)
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
# finish, then START back to the title
bot = Bot(0)
bot.menu(); bot.race()
for i in range(300): bot.step(KEYS["start"] if 250 <= i < 256 else 0)
assert bot.gb.rd("wState") == 0, "did not return to the title"
replay("finish_to_title", bot.log[-700:] if False else bot.log, {len(bot.log) - 5})
# a run with no steering: collisions, off-road and the time-up ending
bot = Bot(1)
bot.menu()
for f in range(3600): bot.step(KEYS["a"] if 300 < f else 0)
replay("timeup", bot.log, {1500, 3000, 3700})
# ---- second cartridge: ORBIT LANCE
from shooter_bot import ShooterBot, ROM as LANCE
from gbpy import KEYS as K
# one full loop: three stages and their bosses, until stage 1 starts again
sb = ShooterBot()
marks = {}
def watch(f, gb):
    key = (gb.rd("wStage"), gb.rd("wLoop"), gb.rd("wBannerT") > 0, gb.rd("wScriptHold"))
    for name, cond in (("boss1", key[:2] == (0, 0) and gb.rd("wBossBoomT") == 40),
                       ("boss2", key[:2] == (1, 0) and gb.rd("wBossBoomT") == 40),
                       ("boss3", key[:2] == (2, 0) and gb.rd("wBossBoomT") == 40)):
        if cond and name not in marks: marks[name] = f
    if key[:2] == (0, 1) and "loop" not in marks: marks["loop"] = f
sb.play(on_frame=watch, max_frames=12000, stop_at_title=False)
end = marks.get("loop", len(sb.log)) + 120
log = sb.log[:end]
shots = {60, 300, 900, 2000} | {m + d for m in marks.values() for d in (-300, -120, 0, 30)}
print("lance_loop: events at", marks)
replay("lance_loop", log, {f for f in shots if 0 < f < len(log)}, LANCE)
# a player who never moves: shot down, game over, back to the title
sb = ShooterBot()
for _ in range(100): sb.step(0)
for _ in range(4): sb.step(K["start"])
seen = False
for f in range(8000):
    sb.step(K["a"])
    st = sb.gb.rd("wState")
    seen |= st == 2
    if seen and st == 0: break
for _ in range(60): sb.step(0)
n = len(sb.log)
replay("lance_gameover", sb.log, {n - 400, n - 300, n - 200, n - 30}, LANCE)
print(f"TOTAL: {total} frames compared, {bad} differ")
