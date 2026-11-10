"""ctypes wrapper around build/libgb.so for tests, screenshots and scripted play."""
import ctypes, os, struct, zlib

_here = os.path.dirname(os.path.abspath(__file__))
_lib = ctypes.CDLL(os.path.join(_here, "..", "build", "libgb.so"))
_lib.gbx_create.restype = ctypes.c_void_p
_lib.gbx_create.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
_lib.gbx_front.restype = ctypes.POINTER(ctypes.c_uint8)
_lib.gbx_serial.restype = ctypes.c_char_p
_lib.gbx_cycles.restype = ctypes.c_uint64
_lib.gbx_pc.restype = ctypes.c_uint16
_lib.gbx_peek.restype = ctypes.c_uint8
for _n in ("gbx_destroy", "gbx_front", "gbx_serial", "gbx_cycles", "gbx_pc", "gbx_breakpoint",
           "gb_run_frame", "gbx_step", "gbx_halted", "gbx_line", "gb_reset"):
    getattr(_lib, _n).argtypes = [ctypes.c_void_p]
_lib.gbx_peek.argtypes = [ctypes.c_void_p, ctypes.c_uint16]
_lib.gbx_poke.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_uint8]
_lib.gbx_reg.argtypes = [ctypes.c_void_p, ctypes.c_int]
_lib.gbx_reg.restype = ctypes.c_uint8
_lib.gb_set_keys.argtypes = [ctypes.c_void_p, ctypes.c_uint8]
_lib.gb_set_audio_rate.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
_lib.gbx_audio.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_float), ctypes.c_int]
_lib.gbx_chan_mask.argtypes = [ctypes.c_void_p, ctypes.c_int]

KEYS = {"right": 1, "left": 2, "up": 4, "down": 8, "a": 16, "b": 32, "select": 64, "start": 128}
GRAY = [(255, 255, 255), (170, 170, 170), (85, 85, 85), (0, 0, 0)]


class GB:
    def __init__(self, rom):
        if isinstance(rom, str):
            with open(rom, "rb") as f:
                rom = f.read()
        self.g = _lib.gbx_create(rom, len(rom))
        self._abuf = (ctypes.c_float * (8192 * 2))()
        self.audio = []
        self.keep_audio = False
        self.frames = 0

    def frame(self, keys=0):
        _lib.gb_set_keys(self.g, keys)
        _lib.gb_run_frame(self.g)
        self.frames += 1
        n = _lib.gbx_audio(self.g, self._abuf, 8192)
        if self.keep_audio:
            self.audio.extend(self._abuf[: n * 2])

    def run(self, n, keys=0):
        for _ in range(n):
            self.frame(keys)

    def step(self): _lib.gbx_step(self.g)
    def screen(self): return bytes(_lib.gbx_front(self.g)[: 160 * 144])
    def serial(self): return _lib.gbx_serial(self.g).decode("latin1")
    def peek(self, a): return _lib.gbx_peek(self.g, a)
    def poke(self, a, v): _lib.gbx_poke(self.g, a, v)
    def reg(self, i): return _lib.gbx_reg(self.g, i)
    def pc(self): return _lib.gbx_pc(self.g)
    def cycles(self): return _lib.gbx_cycles(self.g)
    def breakpoint(self): return bool(_lib.gbx_breakpoint(self.g))
    def halted(self): return bool(_lib.gbx_halted(self.g))
    def line(self): return _lib.gbx_line(self.g)
    def set_rate(self, hz): _lib.gb_set_audio_rate(self.g, hz)
    def chan_mask(self, m): _lib.gbx_chan_mask(self.g, m)

    def png(self, path, scale=1, palette=GRAY):
        write_png(path, self.screen(), scale, palette)


def write_png(path, shades, scale=1, palette=GRAY, w=160, h=144):
    rows = bytearray()
    for y in range(h):
        line = bytearray()
        for x in range(w):
            line += bytes(palette[shades[y * w + x]]) * scale
        for _ in range(scale):
            rows += b"\0" + line
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w * scale, h * scale, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))
