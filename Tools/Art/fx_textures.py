"""AeroStrike VFX textures: fireball + smoke flipbooks (4x4 of 256px), flare glow, shockwave ring.
uv run --with numpy --with pillow --with opensimplex python Tools/Art/fx_textures.py Assets/Textures"""
import sys, os
import numpy as np
from PIL import Image
import opensimplex

out = sys.argv[1]
S = 256
opensimplex.seed(7)
yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
u = (xx / (S - 1)) * 2 - 1
v = (yy / (S - 1)) * 2 - 1
r = np.sqrt(u * u + v * v)

def fbm(x, y, z, oct=5):
    acc = np.zeros_like(x); amp = 1.0; f = 1.0; tot = 0
    for _ in range(oct):
        acc += amp * opensimplex.noise3array(x[0] * f, y[:, 0] * f, np.array([z * f]))[0]
        tot += amp; amp *= 0.5; f *= 2.0
    return acc / tot  # ~[-1,1]

def ramp(h):
    # heat -> colour: dark red smoke, orange, yellow, white-hot
    stops = [(0.0, (40, 30, 28)), (0.25, (150, 40, 15)), (0.5, (255, 110, 30)), (0.75, (255, 200, 80)), (1.0, (255, 250, 230))]
    c = np.zeros(h.shape + (3,))
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        m = (h >= a) & (h <= b)
        t = ((h - a) / (b - a))[..., None]
        c[m] = (np.array(ca) * (1 - t) + np.array(cb) * t)[m]
    return c

def sheet(frames):
    atlas = Image.new("RGBA", (S * 4, S * 4))
    for i, f in enumerate(frames):
        atlas.paste(f, ((i % 4) * S, (i // 4) * S))
    return atlas

def fireball():
    frames = []
    for i in range(16):
        a = i / 15
        n = fbm(u * 2.8, v * 2.8, a * 1.6)
        n2 = fbm(u * 6.0 + 4, v * 6.0, a * 2.4 + 2, 3)
        R = 0.26 + 0.6 * a ** 0.5
        shape = np.clip((R + 0.34 * n + 0.08 * n2 - r) / 0.12, 0, 1)
        core = np.exp(-(r / (0.45 * R)) ** 2) * (1 - a) ** 1.5
        heat = np.clip((1 - a * 1.05) * (0.7 + 0.5 * n + 0.2 * n2) * (1.5 - r / max(R, 1e-3)) + core, 0, 1) * shape
        rgb = ramp(heat)
        alpha = shape * np.clip(1 - a ** 2.2, 0, 1)
        img = np.dstack([rgb, alpha * 255]).astype(np.uint8)
        frames.append(Image.fromarray(img, "RGBA"))
    return sheet(frames)

def smoke():
    frames = []
    for i in range(16):
        a = i / 15
        n = fbm(u * 1.8 + 3.1, v * 1.8, a * 0.9 + 5)
        R = 0.42 + 0.45 * a ** 0.6
        shape = np.clip((R + 0.3 * n - r) / 0.18, 0, 1)
        shade = np.clip(0.55 + 0.35 * fbm(u * 3, v * 3, a + 9) - 0.25 * (v + 1) * 0.5, 0, 1)  # lit from above
        g = (shade * 255)[..., None].repeat(3, 2)
        alpha = shape * (0.95 * (1 - a) ** 0.9)
        frames.append(Image.fromarray(np.dstack([g, alpha * 255]).astype(np.uint8), "RGBA"))
    return sheet(frames)

def flare():
    core = np.exp(-(r / 0.12) ** 2)
    halo = np.exp(-(r / 0.45) ** 2) * 0.55
    streak = np.exp(-(np.abs(v) / 0.04) ** 2) * np.exp(-(np.abs(u) / 0.9) ** 2) * 0.35
    a = np.clip(core + halo + streak, 0, 1)
    rgb = np.dstack([np.full_like(a, 255), 200 + 55 * core, 140 + 115 * core])
    return Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")

def ring():
    a = np.exp(-((r - 0.82) / 0.06) ** 2) * np.clip(1 - (r - 0.82) * 4, 0, 1)
    rgb = np.dstack([np.full_like(a, 255), np.full_like(a, 235), np.full_like(a, 210)])
    return Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")

fireball().save(os.path.join(out, "FX_Fireball_4x4.png"))
smoke().save(os.path.join(out, "FX_Smoke_4x4.png"))
flare().save(os.path.join(out, "FX_FlareGlow.png"))
ring().save(os.path.join(out, "FX_Shockwave.png"))
print("ok")
