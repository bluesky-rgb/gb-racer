"""Run Blargg test ROMs; they report over the serial port and/or on screen ($A000 protocol)."""
import sys, os, glob
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from gbpy import GB

def run(path, max_frames=4000):
    gb = GB(path)
    for i in range(max_frames):
        gb.frame()
        s = gb.serial()
        if "Passed" in s or "Failed" in s:
            gb.run(10)
            return ("Passed" in gb.serial()), gb.serial().strip().replace("\n", " | "), i
        # newer ROMs: signature DE B0 61 at $A001, status at $A000, text at $A004
        if gb.peek(0xA001) == 0xDE and gb.peek(0xA002) == 0xB0 and gb.peek(0xA003) == 0x61 and gb.peek(0xA000) != 0x80:
            txt = ""
            a = 0xA004
            while gb.peek(a) and a < 0xA400:
                txt += chr(gb.peek(a)); a += 1
            return gb.peek(0xA000) == 0, txt.strip().replace("\n", " | "), i
    return False, "TIMEOUT " + gb.serial().strip().replace("\n", " | ")[-200:], max_frames

if __name__ == "__main__":
    ok_all = True
    for p in sys.argv[1:]:
        ok, msg, fr = run(p)
        ok_all &= ok
        print(("PASS" if ok else "FAIL"), os.path.basename(p), "::", msg[-160:], f"({fr} frames)")
    sys.exit(0 if ok_all else 1)
