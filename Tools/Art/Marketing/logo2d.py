# AeroStrike title as a crisp 2D game logo: italic heavy type, gradient fills, extrusion, outlines.
# usage: python logo2d.py out.png [height_px]
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import numpy as np

OUT = sys.argv[1]; HPX = int(sys.argv[2]) if len(sys.argv) > 2 else 420
FONT = r"C:\Windows\Fonts\ariblk.ttf"
S = HPX / 420.0
fsize = int(300 * S)
font = ImageFont.truetype(FONT, fsize)

def word_mask(txt):
    l, t, r, b = font.getbbox(txt)
    m = Image.new("L", (r - l + int(40 * S), b - t + int(40 * S)), 0)
    ImageDraw.Draw(m).text((int(20 * S) - l, int(20 * S) - t), txt, font=font, fill=255)
    return m

def grad(size, stops):
    w, h = size
    y = np.linspace(0, 1, h)[:, None]
    out = np.zeros((h, w, 3), np.float32)
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        k = np.clip((y - p0) / max(1e-6, p1 - p0), 0, 1)
        sel = (y >= p0) & (y <= p1)
        c = np.array(c0) * (1 - k) + np.array(c1) * k
        out = np.where(sel[..., None], np.broadcast_to(c[:, None, :], (h, w, 3)), out)
    return Image.fromarray(out.astype(np.uint8))

def hx(h): h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

aero = word_mask("AERO"); strike = word_mask("STRIKE")
gap = int(-10 * S)
W = aero.width + strike.width + gap; H = max(aero.height, strike.height)
mask_a = Image.new("L", (W, H)); mask_a.paste(aero, (0, 0))
mask_s = Image.new("L", (W, H)); mask_s.paste(strike, (aero.width + gap, 0))
# italic shear + generous canvas
pad = int(90 * S)
def shear(m):
    big = Image.new("L", (m.width + pad * 2 + int(H * 0.25), m.height + pad * 2)); big.paste(m, (pad + int(H * 0.25), pad))
    return big.transform(big.size, Image.AFFINE, (1, 0.22, 0, 0, 1, 0), resample=Image.BICUBIC)
mask_a, mask_s = shear(mask_a), shear(mask_s)
full = ImageChops.lighter(mask_a, mask_s)
CW, CH = full.size

def dilate(m, r):
    return m.filter(ImageFilter.MaxFilter(r * 2 + 1)) if r > 0 else m

canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
def put(color_img, m):
    rgba = color_img.convert("RGBA") if isinstance(color_img, Image.Image) else Image.new("RGBA", (CW, CH), color_img + (255,))
    rgba.putalpha(m); canvas.alpha_composite(rgba)

o1 = int(10 * S); o2 = int(20 * S)
# outer gold rim and dark extrusion (stacked offsets down-right)
ext = int(26 * S)
outer = dilate(full, o2)
for i in range(ext, 0, -1):
    sh = ImageChops.offset(outer, int(i * 0.35), i)
    put(hx('#0a0f1c'), sh)
put(grad((CW, CH), [(0, hx('#fff1a8')), (0.55, hx('#ffb52a')), (1, hx('#c26a00'))]), outer)   # gold rim
put(hx('#0c1426'), dilate(full, o1))                                                          # navy outline
# face fills
put(grad((CW, CH), [(0.0, hx('#ffffff')), (0.47, hx('#e6eef8')), (0.53, hx('#9fb1c8')), (1.0, hx('#eef4fb'))]), mask_a)  # chrome
put(grad((CW, CH), [(0.0, hx('#fff27a')), (0.45, hx('#ffb21e')), (0.55, hx('#ff6a12')), (1.0, hx('#d81e0c'))]), mask_s)  # fire
# top gloss highlight
gl = Image.new("L", (CW, CH), 0)
gy = np.linspace(0, 1, CH)[:, None]
gm = (np.clip(1 - np.abs(gy - 0.36) / 0.08, 0, 1) * 70).astype(np.uint8)
gl = Image.fromarray(np.broadcast_to(gm, (CH, CW)).copy())
gl = ImageChops.multiply(gl, full)
put(hx('#ffffff'), gl)
canvas = canvas.crop(canvas.getbbox())
canvas.save(OUT)
print("ok", OUT, canvas.size)
