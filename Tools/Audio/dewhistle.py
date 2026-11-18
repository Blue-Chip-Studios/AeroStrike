import sys, os
import numpy as np, soundfile as sf
from scipy.ndimage import median_filter
src, dst = sys.argv[1], sys.argv[2]
y, sr = sf.read(src, always_2d=True)
out = np.zeros_like(y)
for c in range(y.shape[1]):
    X = np.fft.rfft(y[:, c]); f = np.fft.rfftfreq(len(y), 1/sr)
    mag = np.abs(X) + 1e-12
    width = max(5, int(60 / (sr / len(y))))  # ~60 Hz neighbourhood
    ref = np.exp(median_filter(np.log(mag), size=width, mode="wrap"))
    ratio = mag / ref
    mask = (f > 600) & (ratio > 4.0)        # >12 dB narrow spikes above 600 Hz
    gain = np.ones_like(mag)
    gain[mask] = np.clip(2.0 / ratio[mask], 0.05, 1)  # pull spikes back near the noise floor
    # gentle extra roll-off above 9 kHz (removes fizz, keeps air)
    gain *= 1 / np.sqrt(1 + (f / 9000) ** 4)
    out[:, c] = np.fft.irfft(X * gain, len(y))
pk = np.abs(out).max()
if pk > 0.98: out *= 0.98 / pk
with sf.SoundFile(dst, "w", sr, out.shape[1], format="OGG", subtype="VORBIS") as fh:
    o32 = out.astype(np.float32)
    for i in range(0, len(o32), 4096): fh.write(o32[i:i+4096])
print(os.path.basename(dst), "notched bins:", int(mask.sum()))
