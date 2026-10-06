# Author a dashboard wallpaper PPM: grayscale figure on a pure-black (transparent) 16:9 canvas.
# usage: python3 -I make_wallpaper.py SRC OUT.ppm [--cx 0.79] [--cy 0.74] [--fig-h 0.9]
import argparse
from PIL import Image

p = argparse.ArgumentParser()
p.add_argument("src"); p.add_argument("out")
p.add_argument("--size", default="320x180")     # canvas; ship >= the screen's half-block pixel size
p.add_argument("--cx", type=float, default=0.79) # figure centre, fraction of width
p.add_argument("--cy", type=float, default=0.74) # figure centre, fraction of height
p.add_argument("--fig-h", type=float, default=0.9)  # figure height, fraction of canvas height
p.add_argument("--bg-max", type=int, default=24)    # source backdrop at/below this -> 0 (the key)
p.add_argument("--lo", type=int, default=40)        # figure lifted into [lo, 255], clear of KEY_MAX
a = p.parse_args()

W, H = map(int, a.size.split("x"))
fig = Image.open(a.src).convert("L")  # grayscale: no per-channel tint (autocontrast on RGB went blue)
fh = round(H * a.fig_h); fw = round(fig.width * fh / fig.height)
fig = fig.resize((fw, fh), Image.LANCZOS)
lut = [0 if v <= a.bg_max else a.lo + (v - a.bg_max) * (255 - a.lo) // (255 - a.bg_max) for v in range(256)]
fig = fig.point(lut)
canvas = Image.new("L", (W, H), 0)
canvas.paste(fig, (round(W * a.cx - fw / 2), round(H * a.cy - fh / 2)))
canvas.convert("RGB").save(a.out, format="PPM")  # binary P6, maxval 255
print(a.out, canvas.size)
