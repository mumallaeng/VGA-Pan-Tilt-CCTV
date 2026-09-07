#!/usr/bin/env python3
"""Render every viewable artifact in a run directory to PNG, for eyeballing.

Naming is preserved:  golden_* = software golden model,  rtl_* = SV (iverilog
/ xsim) verification. Per config tag (640x480 / 640x480_raw / 320x240):

    golden_green_<tag>.png   rtl_green_<tag>.png    green_color_filter mask
    golden_clean_<tag>.png   rtl_clean_<tag>.png    noise_filter_3x3 mask
    golden_out_<tag>.png     rtl_out_<tag>.png      final displayed frame
    fb565.png                                       loaded frame buffer (input)

Masks (320x240) are scaled x2 (nearest) so they line up with the 640x480
output frames. Needs Pillow (use .venv / setup_env.bat).

Usage:  python render_images.py [dir]     (default: _work)
"""
import sys
import os
import glob
from PIL import Image

IMG_W, IMG_H = 320, 240


def hex_to_img(path):
    vals = [int(x, 16) for x in open(path) if x.strip()]
    out = Image.new("RGB", (IMG_W, IMG_H))
    px = out.load()
    for i, v in enumerate(vals[:IMG_W * IMG_H]):
        r5, g6, b5 = (v >> 11) & 0x1F, (v >> 5) & 0x3F, v & 0x1F
        px[i % IMG_W, i // IMG_W] = ((r5 << 3) | (r5 >> 2),
                                     (g6 << 2) | (g6 >> 4),
                                     (b5 << 3) | (b5 >> 2))
    return out


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "_work"
    n = 0

    fb = sorted(glob.glob(os.path.join(d, "rtl_fb565_*.hex")))
    if fb:
        hex_to_img(fb[0]).resize((IMG_W * 2, IMG_H * 2), Image.NEAREST) \
            .save(os.path.join(d, "fb565.png"))
        n += 1

    masks = (glob.glob(os.path.join(d, "golden_green_*.pgm"))
             + glob.glob(os.path.join(d, "rtl_green_*.pgm"))
             + glob.glob(os.path.join(d, "golden_clean_*.pgm"))
             + glob.glob(os.path.join(d, "rtl_clean_*.pgm")))
    for f in masks:
        Image.open(f).convert("L").resize((IMG_W * 2, IMG_H * 2), Image.NEAREST) \
            .save(os.path.splitext(f)[0] + ".png")
        n += 1

    frames = (glob.glob(os.path.join(d, "golden_out_*.ppm"))
              + glob.glob(os.path.join(d, "rtl_out_*.ppm")))
    for f in frames:
        Image.open(f).save(os.path.splitext(f)[0] + ".png")
        n += 1

    print("rendered %d PNGs in %s" % (n, d))


if __name__ == "__main__":
    main()
