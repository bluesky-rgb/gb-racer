"""Run mooneye-style test ROMs: they execute LD B,B when done with Fibonacci numbers in B..L on success."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from gbpy import GB

def run(path, max_frames=1800):
    gb = GB(path)
    for i in range(max_frames):
        gb.frame()
        if gb.breakpoint():
            regs = [gb.reg(i) for i in range(6)]
            return regs == [3, 5, 8, 13, 21, 34], regs
    return False, "timeout"

if __name__ == "__main__":
    root = sys.argv[1]
    verbose = len(sys.argv) > 2
    tests = []
    for d, _, files in os.walk(root):
        if "test.gb" in files:
            tests.append(d)
    tests.sort()
    npass = 0
    fails = []
    for t in tests:
        name = os.path.relpath(t, root)
        # skip tests for other hardware models
        base = name.split("/")[-1]
        if any(s in base for s in ("-cgb", "-sgb", "-agb", "-mgb", "-S", "-C", "-A", "-dmg0")) and "dmgABC" not in base and "-GS" not in base:
            if not ("-GS" in base or "dmgABC" in base or base.endswith("-G")): continue
        ok, info = run(os.path.join(t, "test.gb"))
        npass += ok
        if not ok: fails.append(name)
        if verbose or not ok: print("PASS" if ok else "FAIL", name, "" if ok else info)
    print(f"{npass}/{npass+len(fails)} passed")
