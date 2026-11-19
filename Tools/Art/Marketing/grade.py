# Post pass for AeroStrike marketing renders: colour grade, bloom, vignette, logo overlay.
# usage: python grade.py in.png out.png [--logo logo.png --logo-pos x,y --logo-w frac] [--warm 0.25] [--sat 1.25]
import argparse
from PIL import Image, ImageFilter, ImageEnhance, ImageChops, ImageDraw
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("dst")
ap.add_argument("--logo"); ap.add_argument("--logo-pos", default="0.05,0.05"); ap.add_argument("--logo-w", type=float, default=0.46)
ap.add_argument("--sat", type=float, default=1.28); ap.add_argument("--contrast", type=float, default=1.10)
ap.add_argument("--warm", type=float, default=0.22); ap.add_argument("--teal", type=float, default=0.18)
ap.add_argument("--bloom", type=float, default=0.45); ap.add_argument("--vignette", type=float, default=0.32)
ap.add_argument("--sky", type=float, default=0.35, help="deepen the blue of the upper sky")
ap.add_argument("--size", default=None, help="final WxH")
a = ap.parse_args()

im = Image.open(a.src).convert("RGB")
if a.size:
    w, h = map(int, a.size.split("x")); im = im.resize((w, h), Image.LANCZOS)
W, H = im.size
f = np.asarray(im).astype(np.float32) / 255.0

# split-tone: warm highlights, teal-blue shadows (the "blockbuster" look)
lum = (0.2126 * f[..., 0] + 0.7152 * f[..., 1] + 0.0722 * f[..., 2])[..., None]
warm = np.array([1.0, 0.62, 0.30]); teal = np.array([0.10, 0.32, 0.55])
hi = np.clip((lum - 0.45) / 0.55, 0, 1); lo = np.clip((0.5 - lum) / 0.5, 0, 1)
f = f + hi * a.warm * (warm - 0.5) * 0.5 + lo * a.teal * (teal - 0.5) * 0.5

# deepen the zenith: a vertical gradient that pushes the top of frame towards rich blue
y = np.linspace(0, 1, H)[:, None, None]
skyw = np.clip(1 - y / 0.55, 0, 1) ** 1.6 * a.sky
deep = np.array([0.12, 0.30, 0.72])
f = f * (1 - skyw * 0.55) + deep * skyw * 0.55 * (0.6 + lum)

f = np.clip(f, 0, 1)
im = Image.fromarray((f * 255).astype(np.uint8))
im = ImageEnhance.Color(im).enhance(a.sat)
im = ImageEnhance.Contrast(im).enhance(a.contrast)

# bloom from the brightest areas (sun, afterburners, fire)
if a.bloom > 0:
    g = np.asarray(im).astype(np.float32) / 255.0
    l = g.max(axis=2, keepdims=True)
    br = np.clip((l - 0.78) / 0.22, 0, 1) * g
    b = Image.fromarray((br * 255).astype(np.uint8))
    r = max(4, W // 90)
    acc = np.zeros_like(g)
    for k, wgt in ((1, 0.5), (3, 0.35), (8, 0.25)):
        acc += np.asarray(b.filter(ImageFilter.GaussianBlur(r * k))).astype(np.float32) / 255.0 * wgt
    g = 1 - (1 - g) * (1 - np.clip(acc * a.bloom * 1.6, 0, 1))  # screen
    im = Image.fromarray((np.clip(g, 0, 1) * 255).astype(np.uint8))

# vignette
if a.vignette > 0:
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) / 1.414
    v = 1 - a.vignette * np.clip((d - 0.45) / 0.55, 0, 1) ** 1.5
    g = np.asarray(im).astype(np.float32) * v[..., None]
    im = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8))

if a.logo:
    lg = Image.open(a.logo).convert("RGBA")
    bb = lg.getbbox(); lg = lg.crop(bb)
    tw = int(W * a.logo_w); th = int(lg.height * tw / lg.width)
    lg = lg.resize((tw, th), Image.LANCZOS)
    px, py = (float(v) for v in a.logo_pos.split(","))
    x, y0 = int(px * W), int(py * H)
    # soft drop shadow so it reads on any background
    sh = Image.new("RGBA", lg.size, (0, 0, 0, 0)); sh.putalpha(lg.getchannel("A").point(lambda v: int(v * 0.65)))
    pad = th // 3
    shc = Image.new("RGBA", (tw + pad * 2, th + pad * 2), (0, 0, 0, 0)); shc.paste(sh, (pad, pad), sh)
    shc = shc.filter(ImageFilter.GaussianBlur(max(3, th // 14)))
    base = im.convert("RGBA")
    base.alpha_composite(shc, (x - pad + th // 30, y0 - pad + th // 18))
    base.alpha_composite(lg, (x, y0))
    im = base.convert("RGB")

im.save(a.dst, quality=95)
print("ok", a.dst, im.size)
