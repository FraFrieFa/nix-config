import sys, wave
import numpy as np

w = wave.open(sys.argv[1])
d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float)
s = np.abs(np.fft.rfft(d))
f = np.fft.rfftfreq(len(d), 1 / w.getframerate())
band = lambda lo, hi: 20 * np.log10(s[(f >= lo) & (f < hi)].mean() + 1e-9)
mid, high = band(8000, 10000), band(12000, 15000)
print(f"rms={np.sqrt((d**2).mean()):.0f}  8-10kHz={mid:.1f}dB  12-15kHz={high:.1f}dB  diff={high-mid:+.1f}dB")
print("VERDICT:", "BAD (narrowband)" if high - mid > 3 else "GOOD (wideband)")
