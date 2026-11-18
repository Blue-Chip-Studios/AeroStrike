import sys, numpy as np, soundfile as sf
src, dst = sys.argv[1], sys.argv[2]
y, sr = sf.read(src, always_2d=True)
env = np.abs(y).mean(1)
w = int(sr * 0.003); env = np.convolve(env, np.ones(w) / w, mode="same")
onset = int(np.argmax(env > 0.3 * env.max()))
start = max(0, onset - int(sr * 0.004))
seg = y[start:start + int(sr * 0.42)].copy()
n = len(seg); fade = int(sr * 0.16)
seg[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
seg[: int(sr * 0.002)] *= np.linspace(0, 1, int(sr * 0.002))[:, None]
seg *= 0.95 / (np.abs(seg).max() + 1e-9)
with sf.SoundFile(dst, "w", sr, seg.shape[1], format="OGG", subtype="VORBIS") as fh:
    for i in range(0, n, 4096): fh.write(seg[i:i + 4096].astype(np.float32))
print(dst.split("/")[-1], f"onset at {onset/sr*1000:.0f} ms, {n/sr:.2f}s")
