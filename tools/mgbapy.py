"""Run a ROM in mGBA (reference emulator) through build/mgba_run; same interface subset as gbpy.GB."""
import os, subprocess
_here = os.path.dirname(os.path.abspath(__file__))

class MGBA:
    def __init__(self, rom_path):
        self.p = subprocess.Popen([os.path.join(_here, "..", "build", "mgba_run"), rom_path],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self._screen = bytes(160 * 144)
        self.frames = 0
    def frame(self, keys=0):
        self.p.stdin.write(bytes([keys])); self.p.stdin.flush()
        self._screen = self.p.stdout.read(160 * 144)
        self.frames += 1
    def run(self, n, keys=0):
        for _ in range(n): self.frame(keys)
    def screen(self): return self._screen
    def close(self):
        self.p.stdin.close(); self.p.wait()
