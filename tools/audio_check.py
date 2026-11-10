"""Render audio from the game and report the dominant pitch per channel over time."""
import sys, os, wave, struct
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from gbpy import GB, KEYS
ROM = os.path.join(os.path.dirname(__file__), "..", "game", "build", "racer.gb")
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

def note_name(f):
    if f <= 0: return "--"
    n = int(round(12 * np.log2(f / 440.0))) + 57
    return f"{NAMES[n % 12]}{n // 12}"

def render(mask, frames, keyfn, rate=32768):
    gb = GB(ROM); gb.set_rate(rate); gb.chan_mask(mask); gb.keep_audio = True
    for f in range(frames): gb.frame(keyfn(f))
    a = np.array(gb.audio, dtype=np.float32).reshape(-1, 2)
    return a

def pitch_track(mono, rate, win=4096, hop=2048, fmin=40, fmax=2500):
    out = []
    for i in range(0, len(mono) - win, hop):
        seg = mono[i:i + win] * np.hanning(win)
        if np.abs(seg).max() < 0.004: out.append(0.0); continue
        sp = np.abs(np.fft.rfft(seg))
        freqs = np.fft.rfftfreq(win, 1 / rate)
        band = (freqs >= fmin) & (freqs <= fmax)
        # fundamental: lowest strong peak
        thr = sp[band].max() * 0.45
        idx = np.where(band & (sp >= thr))[0][0]
        out.append(freqs[idx])
    return out

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "title"
    rate = 32768
    if what == "title":
        keyfn = lambda f: 0
        frames, skip = 500, 0
    else:
        course = int(what)
        def keyfn(f):
            if 100 <= f < 104: return KEYS["start"]
            for c in range(course):
                if 130 + 14 * c <= f < 134 + 14 * c: return KEYS["right"]
            if 180 <= f < 184: return KEYS["a"]
            return KEYS["a"] if f > 420 else 0
        frames, skip = 1100, 0
    full = render(0x0F, frames, keyfn, rate)
    with wave.open(f"build/audio_{what}.wav", "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes((np.clip(full, -1, 1) * 32000).astype("<i2").tobytes())
    print(f"{what}: {len(full) / rate:.1f}s rendered, peak {np.abs(full).max():.3f}, rms {np.sqrt((full ** 2).mean()):.3f}")
    for ch, label in ((1, "pulse1"), (2, "pulse2"), (4, "wave"), (8, "noise")):
        a = render(ch, frames, keyfn, rate)
        mono = a.mean(axis=1)
        if label == "noise":
            env = [float(np.abs(mono[i:i + 2048]).max()) for i in range(0, len(mono) - 2048, 2048)]
            hits = sum(1 for i in range(1, len(env)) if env[i] > 0.02 and env[i] > env[i - 1] * 1.5)
            print(f"  {label}: peak {np.abs(mono).max():.3f}, ~{hits} hits")
            continue
        tr = pitch_track(mono, rate)
        seq, last = [], None
        for f in tr:
            n = note_name(f)
            if n != last: seq.append(n); last = n
        print(f"  {label}: peak {np.abs(mono).max():.3f}; notes: {' '.join(seq[:44])}")
