import sys, glob, os
import numpy as np, soundfile as sf
rows = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.mp3"))):
    y, sr = sf.read(f, always_2d=True)
    y = y.mean(axis=1)
    n = 4096
    frames = [y[i:i+n] * np.hanning(n) for i in range(0, len(y) - n, n // 2)]
    if not frames: continue
    spec = np.mean([np.abs(np.fft.rfft(fr)) ** 2 for fr in frames], axis=0)
    freqs = np.fft.rfftfreq(n, 1 / sr)
    tot = spec.sum() + 1e-12
    cent = (spec * freqs).sum() / tot
    hi = spec[freqs > 4000].sum() / tot
    vhi = spec[freqs > 8000].sum() / tot
    lo = spec[freqs < 250].sum() / tot
    # strongest tonal peak above 1 kHz (whistle detector)
    m = freqs > 1000
    pk = freqs[m][np.argmax(spec[m])]
    peakiness = spec[m].max() / (np.median(spec[m]) + 1e-12)
    rows.append((os.path.basename(f), cent, lo, hi, vhi, pk, peakiness))
rows.sort(key=lambda r: -r[1])
print(f"{'file':28s} centroid  <250Hz  >4k   >8k   peak>1k  tonal")
for r in rows:
    print(f"{r[0]:28s} {r[1]:7.0f}  {r[2]:5.2f}  {r[3]:5.2f} {r[4]:5.2f} {r[5]:7.0f}  {r[6]:7.0f}")
